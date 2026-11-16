package dz.dourousi.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Uses FlutterFragmentActivity (required for local_auth BiometricPrompt on Android)
 * and enforces WindowManager.LayoutParams.FLAG_SECURE to block screenshots,
 * screen recording, and recent-apps preview leaks (Strict DRM Compliance).
 */
class MainActivity : FlutterFragmentActivity() {
    private val drmChannelName = "dz.dourousi.app/drm_protection"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enforce FLAG_SECURE from startup so encrypted materials can never be screen-recorded
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, drmChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecureScreen" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
