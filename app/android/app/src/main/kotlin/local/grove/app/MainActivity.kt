package local.grove.app

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // When the phone was used, for the sleep times
        // (lib/services/device_activity_source.dart). Only times and two
        // codes leave this file: no app names.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grove/activity")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "access" -> result.success(access())
                        "openAccessSettings" -> {
                            openAccessSettings()
                            result.success(null)
                        }
                        "events" -> {
                            val from = (call.argument<Number>("from"))?.toLong()
                            val to = (call.argument<Number>("to"))?.toLong()
                            if (from == null || to == null) {
                                result.error("args", "events needs from and to", null)
                            } else {
                                result.success(events(from, to))
                            }
                        }
                        "nextAlarm" -> result.success(nextAlarm())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("activity", e.message, null)
                }
            }
    }

    /// "granted", "needsGrant" or "unsupported". The screen events came with
    /// Android 9 (API 28).
    private fun access(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return "unsupported"
        val ops = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return "unsupported"
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
            )
        }
        val granted = if (mode == AppOpsManager.MODE_DEFAULT) {
            checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
        return if (granted) "granted" else "needsGrant"
    }

    /// The "Usage access" page of the system, on Grove when the phone can.
    private fun openAccessSettings() {
        val withPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(withPackage)
        } catch (e: ActivityNotFoundException) {
            startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /// [ms, code, ms, code, …], oldest first. Code 0: the phone is used
    /// (screen on, unlocked). Code 1: the screen went off.
    private fun events(from: Long, to: Long): LongArray {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return LongArray(0)
        val usage = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return LongArray(0)
        val found = usage.queryEvents(from, to) ?: return LongArray(0)
        val flat = ArrayList<Long>()
        val event = UsageEvents.Event()
        while (found.hasNextEvent()) {
            found.getNextEvent(event)
            val code = when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> 0L
                UsageEvents.Event.KEYGUARD_HIDDEN -> 0L
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> 1L
                else -> null
            } ?: continue
            flat.add(event.timeStamp)
            flat.add(code)
        }
        return flat.toLongArray()
    }

    /// When the next alarm clock rings (ms), or null.
    private fun nextAlarm(): Long? {
        val alarms = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return null
        return alarms.nextAlarmClock?.triggerTime
    }
}
