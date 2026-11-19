import ConversationVAD
import Flutter
import Foundation

final class SpeechDetector {
  private let queue = DispatchQueue(label: "dev.erciyuan.speech-detector")
  private let channel: FlutterMethodChannel
  private var state: OpaquePointer?

  init(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.erciyuan/vad", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      guard call.method == "reset" || call.method == "probability" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pcm = (call.arguments as? FlutterStandardTypedData)?.data
      self.queue.async {
        let response: Any?
        if self.state == nil, let path = Bundle.main.path(forResource: "silero_vad_v5", ofType: "onnx") {
          self.state = path.withCString { conversation_vad_open($0) }
        }
        if let state = self.state, call.method == "reset" {
          conversation_vad_reset(state)
          response = nil
        } else if let state = self.state, let pcm = pcm, pcm.count == 1024 {
          var score: Float = 0
          let success = pcm.withUnsafeBytes { raw in
            conversation_vad_score(state, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &score)
          }
          response = success != 0 ? NSNumber(value: score) : self.failure()
        } else {
          response = self.failure()
        }
        DispatchQueue.main.async { result(response) }
      }
    }
  }

  private func failure() -> FlutterError {
    FlutterError(code: "VAD_FAILED", message: "Speech detection failed", details: nil)
  }

  deinit {
    channel.setMethodCallHandler(nil)
    conversation_vad_close(state)
  }
}
