package dev.erciyuan.companion_poc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var pcm: PcmPlayer? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pcm = PcmPlayer(flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pcm?.dispose(); pcm = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
