package com.rou39.omniverse

import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.view.View
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.omniverse/device_info"
    private val JOB_CHANNEL = "com.omniverse/background_job"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureBackgroundJob(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, intentFilter)
                    val temp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
                    val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val batteryPct = if (level >= 0 && scale > 0) (level * 100.0 / scale) else -1.0

                    val uid = android.os.Process.myUid()
                    val txBytes = TrafficStats.getUidTxBytes(uid)
                    val rxBytes = TrafficStats.getUidRxBytes(uid)

                    result.success(mapOf(
                        "temperature" to (temp / 10.0),
                        "batteryPercent" to batteryPct,
                        "txBytes" to txBytes,
                        "rxBytes" to rxBytes
                    ))
                }
                // 旧APIとの互換性
                "getBatteryInfo" -> {
                    val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = registerReceiver(null, intentFilter)
                    val temp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
                    val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val batteryPct = if (level >= 0 && scale > 0) (level * 100.0 / scale) else -1.0
                    result.success(mapOf(
                        "temperature" to (temp / 10.0),
                        "batteryPercent" to batteryPct
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }
    /**
     * 長い取得を裏で続けるための窓口。中身は [JobForegroundService] と、
     * 裏用 WebView の見え方の直し。
     */
    private fun configureBackgroundJob(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JOB_CHANNEL)
        JobForegroundService.onCancelRequested = {
            runOnUiThread { channel.invokeMethod("cancelRequested", null) }
        }
        channel.setMethodCallHandler { call, result ->
            val title = call.argument<String>("title") ?: ""
            val text = call.argument<String>("text") ?: ""
            val done = call.argument<Int>("done") ?: 0
            val total = call.argument<Int>("total") ?: 0
            when (call.method) {
                "start" -> result.success(
                    JobForegroundService.start(applicationContext, title, text, done, total))
                "update" -> {
                    JobForegroundService.update(applicationContext, title, text, done, total)
                    result.success(null)
                }
                "stop" -> {
                    JobForegroundService.stop(applicationContext)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    // 拒否されても取得は続く。通知が出ないだけ
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4201)
                    }
                    result.success(null)
                }
                "revealWebView" -> result.success(
                    revealWebView(flutterEngine, call.argument<String>("id") ?: ""))
                else -> result.notImplemented()
            }
        }
    }

    /**
     * HeadlessInAppWebView は INVISIBLE で置かれ、X からは「見えていない
     * ページ」に見えて再送が 404 になる。表のホストと同じく、
     * 見えている状態のまま画面の外へ逃がす。
     */
    private fun revealWebView(flutterEngine: FlutterEngine, id: String): Boolean {
        return try {
            val plugin = flutterEngine.plugins.get(InAppWebViewFlutterPlugin::class.java)
                as? InAppWebViewFlutterPlugin ?: return false
            val headless = plugin.headlessInAppWebViewManager?.webViews?.get(id) ?: return false
            val flutterWebView = headless.flutterWebView ?: return false
            val view = flutterWebView.view ?: return false
            view.translationX = -(resources.displayMetrics.widthPixels * 3f)
            view.visibility = View.VISIBLE
            // アプリが裏に居る間に作ると、WebView は「窓が見えていない」状態で
            // 生まれ、そのままだと 1 分ほどでページ内の通信が返らなくなる
            // （実測）。表に居るときと同じく、窓も見えている扱いにする。
            // allowBackgroundAudioPlaying が付いているので、この後に届く
            // 「隠れた」知らせは無視される
            view.dispatchWindowVisibilityChanged(View.VISIBLE)
            flutterWebView.webView?.let {
                it.onResume()
                it.resumeTimers()
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "revealWebView failed: $e")
            false
        }
    }
}
