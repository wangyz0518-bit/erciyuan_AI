package dev.erciyuan.mobile

import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.concurrent.Executors

/** Run the same 16-kHz, 32-ms Silero model as the Windows lab, off the UI thread. */
class SpeechDetector(messenger: BinaryMessenger, assets: AssetManager) {
    private val channel = MethodChannel(messenger, "dev.erciyuan/vad")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val env by lazy { OrtEnvironment.getEnvironment() }
    private var session: OrtSession? = null
    private val window = FloatArray(576)
    private val state = FloatArray(256)

    init {
        channel.setMethodCallHandler { call, result ->
            val bytes = call.arguments as? ByteArray
            when (call.method) {
                "reset", "probability" -> worker.execute {
                    try {
                        if (session == null) {
                            val model = assets.open("silero_vad_v5.onnx").use { it.readBytes() }
                            session = OrtSession.SessionOptions().use { options ->
                                options.setIntraOpNumThreads(1)
                                env.createSession(model, options)
                            }
                        }
                        val value = if (call.method == "reset") {
                            window.fill(0f)
                            state.fill(0f)
                            null
                        } else {
                            require(bytes?.size == 1024)
                            probability(checkNotNull(bytes))
                        }
                        main.post { result.success(value) }
                    } catch (_: Exception) {
                        main.post { result.error("VAD_FAILED", "Speech detection failed", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun probability(bytes: ByteArray): Double {
        for (i in 0 until 512) {
            val value = (bytes[i * 2].toInt() and 255) or (bytes[i * 2 + 1].toInt() shl 8)
            window[i + 64] = value.toShort() / 32768f
        }
        OnnxTensor.createTensor(env, FloatBuffer.wrap(window), longArrayOf(1, 576)).use { input ->
            OnnxTensor.createTensor(env, FloatBuffer.wrap(state), longArrayOf(2, 1, 128)).use { hidden ->
                OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(16000)), longArrayOf()).use { rate ->
                    checkNotNull(session).run(mapOf("input" to input, "state" to hidden, "sr" to rate)).use { result ->
                        val next = result.get("stateN").get() as OnnxTensor
                        next.floatBuffer.get(state)
                        window.copyInto(window, 0, 512, 576)
                        val score = result.get("output").get() as OnnxTensor
                        return score.floatBuffer.get(0).toDouble()
                    }
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.execute { session?.close(); session = null }
        worker.shutdown()
    }
}
