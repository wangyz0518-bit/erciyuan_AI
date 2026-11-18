package dev.erciyuan.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Native PCM player is owned by the same Flutter engine, never a character. */
class MainActivity : FlutterActivity() {
    private var pcm: PcmPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pcm = PcmPlayer(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pcm?.dispose()
        pcm = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
