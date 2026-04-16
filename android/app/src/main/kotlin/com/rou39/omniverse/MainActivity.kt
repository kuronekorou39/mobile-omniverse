package com.rou39.omniverse

import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.omniverse/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
