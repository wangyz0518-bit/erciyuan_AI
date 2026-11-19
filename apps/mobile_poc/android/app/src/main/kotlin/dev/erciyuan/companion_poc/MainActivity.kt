package dev.erciyuan.companion_poc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var vad: SpeechDetector? = null
    private var pcm: PcmPlayer? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        pcm = PcmPlayer(messenger)
        vad = SpeechDetector(messenger, assets)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        vad?.dispose(); vad = null
        pcm?.dispose(); pcm = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
