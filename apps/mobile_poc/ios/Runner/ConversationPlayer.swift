import AVFoundation
import Flutter
import Foundation

/// Flutter delivers method calls on the main queue. Audio callbacks only touch
/// state after hopping back to that queue and checking the original stream.
final class ConversationPlayer {
  private final class Stream {
    let id: String
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let format: AVAudioFormat
    let prebuffer: Int
    var ownsSession = false
    var submitted = 0
    var rendered = 0
    var firstSignal: Int?
    var reported = false
    var started = false
    var finish: FlutterResult?
    var timer: Timer?
    var drainDeadline: TimeInterval?

    init(id: String, format: AVAudioFormat, prebuffer: Int) {
      self.id = id
      self.format = format
      self.prebuffer = prebuffer
    }
  }

  private let channel: FlutterMethodChannel
  private var current: Stream?
  private var observers: [NSObjectProtocol] = []

  init(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.erciyuan/pcm", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      self.handle(call, result)
    }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
      if let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
         AVAudioSession.InterruptionType(rawValue: value) == .began { self?.stop() }
    })
    observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: nil, queue: .main) { [weak self] note in
      guard let self = self, let stream = self.current, let engine = note.object as? AVAudioEngine,
            engine === stream.engine, !engine.isRunning else { return }
      self.stop()
    })
  }

  private func failure(_ message: String) -> FlutterError {
    FlutterError(code: "PCM_FAILED", message: message, details: nil)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "stop" { stop(); result(nil); return }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let id = args["id"] as? String, !id.isEmpty else {
      result(failure("Missing stream ID")); return
    }
    if call.method == "start" {
      let ms = args["bufferMs"] as? Int ?? 400
      guard (100...1000).contains(ms),
            let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
        result(failure("Invalid format")); return
      }
      stop()
      let stream = Stream(id: id, format: format, prebuffer: 24 * ms)
      current = stream
      do {
        if args["communication"] as? Bool != true {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .spokenAudio)
          try session.setActive(true)
          stream.ownsSession = true
        }
        stream.engine.attach(stream.node)
        stream.engine.connect(stream.node, to: stream.engine.mainMixerNode, format: format)
        stream.engine.prepare()
        try stream.engine.start()
        result(nil)
      } catch { stop(); result(failure("Audio output unavailable")) }
      return
    }

    guard let stream = current, stream.id == id else {
      if call.method == "progress" { result(0) } else { result(failure("Stream stopped")) }
      return
    }
    switch call.method {
    case "progress":
      result(progress(stream))
    case "append":
      guard stream.finish == nil, let pcm = args["bytes"] as? FlutterStandardTypedData,
            append(pcm.data, to: stream) else { result(failure("Invalid audio packet")); return }
      if stream.submitted >= stream.prebuffer { play(stream) }
      result(nil)
    case "end":
      guard stream.finish == nil, stream.submitted > 0 else {
        result(failure("Empty or ended stream")); return
      }
      stream.finish = result
      stream.drainDeadline = ProcessInfo.processInfo.systemUptime
        + Double(stream.submitted - progress(stream)) / 24000.0 + 5.0
      play(stream)
      check(stream)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func append(_ bytes: Data, to stream: Stream) -> Bool {
    let count = bytes.count / 2
    guard count > 0, bytes.count % 2 == 0, count <= 24000 * 60 - stream.submitted,
          let buffer = AVAudioPCMBuffer(pcmFormat: stream.format, frameCapacity: AVAudioFrameCount(count)),
          let samples = buffer.floatChannelData?[0] else { return false }
    buffer.frameLength = AVAudioFrameCount(count)
    bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      for i in 0..<count {
        let bits = UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)
        let sample = Int(Int16(bitPattern: bits))
        samples[i] = Float(sample) / 32768
        if stream.firstSignal == nil, abs(sample) > 200 { stream.firstSignal = stream.submitted + i }
      }
    }
    stream.submitted += count
    let endFrame = stream.submitted
    stream.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self, weak stream] _ in
      DispatchQueue.main.async {
        guard let self = self, let stream = stream, self.current === stream else { return }
        stream.rendered = max(stream.rendered, endFrame)
        self.check(stream)
      }
    }
    return true
  }

  private func play(_ stream: Stream) {
    guard !stream.started else { return }
    stream.started = true
    stream.node.play()
    channel.invokeMethod("event", arguments: ["id": stream.id, "event": "playing"])
    stream.timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self, weak stream] _ in
      guard let self = self, let stream = stream, self.current === stream else { return }
      self.check(stream)
    }
  }

  private func progress(_ stream: Stream) -> Int {
    guard stream.started, let time = stream.node.lastRenderTime,
          let position = stream.node.playerTime(forNodeTime: time), position.sampleRate > 0 else {
      return stream.rendered
    }
    let seconds = Double(position.sampleTime) / position.sampleRate - AVAudioSession.sharedInstance().outputLatency
    return max(stream.rendered, min(stream.submitted, Int(max(0, seconds) * 24000)))
  }

  private func check(_ stream: Stream) {
    if !stream.reported, let first = stream.firstSignal, progress(stream) > first {
      stream.reported = true
      channel.invokeMethod("event", arguments: ["id": stream.id, "event": "firstOutput", "clock": "AVAudioPlayerNode"])
    }
    guard let reply = stream.finish else { return }
    if stream.rendered == stream.submitted {
      stream.finish = nil
      stop()
      reply(["frames": stream.rendered])
    } else if let deadline = stream.drainDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
      stop()
    }
  }

  private func stop() {
    guard let stream = current else { return }
    current = nil
    stream.timer?.invalidate()
    if stream.node.engine != nil { stream.node.stop() }
    stream.engine.stop()
    if stream.ownsSession {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    stream.finish?(failure("Playback stopped before draining"))
    stream.finish = nil
  }

  deinit {
    channel.setMethodCallHandler(nil)
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    stop()
  }
}
