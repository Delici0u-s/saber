package com.adilhanney.saber

import android.os.Bundle
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getIntExtra("org.chromium.chrome.extra.TASK_ID", -1) == this.taskId) {
            this.finish()
            intent.addFlags(FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Physical screen density, so pages can be shown at their real size.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.adilhanney.saber/display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "logicalPixelsPerInch" -> {
                        val metrics = resources.displayMetrics
                        result.success(((metrics.xdpi + metrics.ydpi) / 2 / metrics.density).toDouble())
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
