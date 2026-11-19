package dev.erciyuan.companion_poc

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** A bounded PCM stream. Recording and file playback remain in their existing plugins. */
class PcmPlayer(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.erciyuan/pcm")
    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private val epoch = AtomicLong(0)
    private val publication = Any()
    @Volatile private var track: AudioTrack? = null
    @Volatile private var token = ""
    private var prebuffer = ByteArrayOutputStream()
    @Volatile private var running = false
    @Volatile private var framesWritten = 0L
    @Volatile private var significantFrame = -1L
    @Volatile private var firstOutputMs: Double? = null
    @Volatile private var outputClock = "unavailable"
    private var startNs = 0L
    private var baselineUnderruns = 0
    private var threshold = 19200
    private val rate = 24000

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "stop") {
                stop()
                result.success(null)
            } else if (call.method == "progress") {
                val played = try {
                    val audio = track
                    if (audio == null || call.argument<String>("id") != token) 0
                    else minOf(head(audio), framesWritten).toInt()
                } catch (_: IllegalStateException) { 0 }
                result.success(played)
            } else if (call.method == "start") {
                stop()
                val id = call.argument<String>("id") ?: ""
                val buffer = call.argument<Int>("bufferMs") ?: 400
                val usage = if (call.argument<Boolean>("communication") == true)
                    AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA
                if (id.isEmpty() || buffer !in 100..1000) {
                    result.error("INVALID_PCM", "Invalid stream", null)
                } else {
                    token = id
                    val generation = epoch.get()
                    startNs = System.nanoTime()
                    writer.execute {
                        try {
                            if (generation != epoch.get()) throw IllegalStateException("cancelled")
                            val size = maxOf(AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO,
                                AudioFormat.ENCODING_PCM_16BIT), rate * 2 / 2)
                            val created = AudioTrack.Builder()
                                .setAudioAttributes(AudioAttributes.Builder().setUsage(usage)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                                .setAudioFormat(AudioFormat.Builder().setSampleRate(rate)
                                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                                .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(size).build()
                            if (created.state != AudioTrack.STATE_INITIALIZED) throw IllegalStateException("init")
                            synchronized(publication) {
                                if (generation != epoch.get()) { created.release(); throw IllegalStateException("cancelled") }
                                track = created
                            }
                            prebuffer = ByteArrayOutputStream()
                            running = false; framesWritten = 0; significantFrame = -1
                            firstOutputMs = null; outputClock = "unavailable"
                            threshold = rate * 2 * buffer / 1000
                            baselineUnderruns = created.underrunCount
                            main.post { result.success(null) }
                        } catch (_: Exception) { main.post { result.error("PCM_START_FAILED", "Cannot open audio", null) } }
                    }
                }
            } else if (call.method == "append" || call.method == "end") {
                val id = call.argument<String>("id")
                val bytes = call.argument<ByteArray>("bytes")
                val generation = epoch.get()
                if (id != token) {
                    result.error("PCM_STALE", "Old stream", null)
                } else {
                    writer.execute {
                        try {
                            val audio = track ?: throw IllegalStateException("closed")
                            if (generation != epoch.get()) throw IllegalStateException("cancelled")
                            if (call.method == "append") {
                                if (bytes == null || bytes.size % 2 != 0 || bytes.size > 192000) throw IllegalArgumentException()
                                if (!running) {
                                    prebuffer.write(bytes)
                                    if (prebuffer.size() >= threshold) {
                                        val pending = prebuffer.toByteArray(); prebuffer.reset()
                                        write(audio, pending, generation)
                                    }
                                } else write(audio, bytes, generation)
                                main.post { result.success(null) }
                            } else {
                                if (!running && prebuffer.size() > 0) {
                                    val pending = prebuffer.toByteArray(); prebuffer.reset()
                                    write(audio, pending, generation)
                                }
                                // Separate starvation while feeding from the normal final drain.
                                val beforeDrain = maxOf(0, audio.underrunCount-baselineUnderruns)
                                val deadline = System.nanoTime() + 15_000_000_000L
                                while (generation == epoch.get() && head(audio) < framesWritten) {
                                    if (System.nanoTime() > deadline) throw IllegalStateException("drain")
                                    Thread.sleep(10)
                                }
                                if (generation != epoch.get()) throw IllegalStateException("cancelled")
                                val metrics = mapOf("firstOutputMs" to firstOutputMs,
                                    "clock" to outputClock, "frames" to framesWritten,
                                    "underrunsBeforeDrain" to beforeDrain,
                                    "underrunsDuringDrain" to maxOf(0, audio.underrunCount-baselineUnderruns-beforeDrain),
                                    "underruns" to maxOf(0, audio.underrunCount-baselineUnderruns))
                                audio.pause()
                                main.post { result.success(metrics) }
                            }
                        } catch (_: Exception) { main.post { result.error("PCM_WRITE_FAILED", "Audio stopped or unavailable", null) } }
                    }
                }
            } else result.notImplemented()
        }
    }

    private fun head(audio: AudioTrack): Long = audio.playbackHeadPosition.toLong() and 0xffffffffL

    private fun write(audio: AudioTrack, bytes: ByteArray, generation: Long) {
        if (significantFrame < 0) {
            for (i in bytes.indices step 2) {
                val sample = ((bytes[i].toInt() and 255) or (bytes[i+1].toInt() shl 8)).toShort().toInt()
                if (kotlin.math.abs(sample) > 200) { significantFrame = framesWritten+i/2; break }
            }
        }
        var offset = 0
        if (!running) {
            val written = audio.write(bytes, 0, bytes.size, AudioTrack.WRITE_NON_BLOCKING)
            if (written < 0) throw IllegalStateException("write")
            offset = written; framesWritten += written/2
            if (generation != epoch.get()) throw IllegalStateException("cancelled")
            audio.play(); running = true
            main.post {
                if (generation == epoch.get()) {
                    channel.invokeMethod("event", mapOf("id" to token, "event" to "playing"))
                    observe(audio, generation)
                }
            }
        }
        while (offset < bytes.size && generation == epoch.get()) {
            val written = audio.write(bytes, offset, bytes.size-offset, AudioTrack.WRITE_BLOCKING)
            if (written <= 0) throw IllegalStateException("write")
            offset += written; framesWritten += written/2
        }
        if (generation != epoch.get()) throw IllegalStateException("cancelled")
    }

    private fun observe(audio: AudioTrack, generation: Long) {
        if (generation != epoch.get() || firstOutputMs != null) return
        try {
            val played = head(audio)
            if (significantFrame >= 0 && played > significantFrame) {
                val timestamp = AudioTimestamp()
                val ns: Long
                if (audio.getTimestamp(timestamp)) {
                    ns = timestamp.nanoTime + ((significantFrame-timestamp.framePosition)*1_000_000_000L/rate)
                    outputClock = "AudioTrack.timestamp"
                } else {
                    ns = System.nanoTime() - ((played-significantFrame)*1_000_000_000L/rate)
                    outputClock = "playback_head_estimate"
                }
                firstOutputMs = (ns-startNs)/1_000_000.0
                channel.invokeMethod("event", mapOf("id" to token, "event" to "firstOutput",
                    "firstOutputMs" to firstOutputMs, "clock" to outputClock))
                return
            }
        } catch (_: Exception) { return }
        main.postDelayed({ observe(audio, generation) }, 10)
    }

    fun stop() {
        val old = synchronized(publication) {
            epoch.incrementAndGet()
            val previous = track
            track = null; token = ""
            previous
        }
        // Pause/flush immediately, then release behind any in-flight writer.
        try { old?.pause(); old?.flush() } catch (_: Exception) { }
        if (old != null) writer.execute { try { old.release() } catch (_: Exception) { } }
    }

    fun dispose() { stop(); channel.setMethodCallHandler(null); writer.shutdown() }
}
