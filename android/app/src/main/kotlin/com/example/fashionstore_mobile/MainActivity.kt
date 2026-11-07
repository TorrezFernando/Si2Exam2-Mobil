package com.example.fashionstore_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "fashionstore_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fashionstore/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                        }
                    }
                    result.success(true)
                }
                "show" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = args?.get("title")?.toString() ?: "FashionStore"
                    val body = args?.get("body")?.toString() ?: ""
                    val id = (args?.get("id") as? Number)?.toInt() ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                    showSystemNotification(id, title, body)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Compras y Reservas FashionStore",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notificaciones de compras, pagos, reservas y sincronización"
                enableVibration(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun showSystemNotification(id: Int, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingFlags)

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, builder.build())
    }
}
