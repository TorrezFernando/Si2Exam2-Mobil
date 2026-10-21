package com.example.fashionstore_mobile

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fashionstore/payments").setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
            } else {
                val uri = Uri.parse(call.arguments as? String ?: "")
                if (uri.scheme != "https" || uri.host.isNullOrEmpty()) {
                    result.error("INVALID_URL", "Se requiere HTTPS", null)
                } else {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", "No se pudo abrir el navegador", null)
                    }
                }
            }
        }
    }
}
