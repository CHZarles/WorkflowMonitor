package com.recorderphone.android_usage

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream

class RecorderphoneAndroidUsagePlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "recorderphone_android_usage")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "hasUsageAccess" -> result.success(hasUsageAccess(context))
      "openUsageAccessSettings" -> {
        openUsageAccessSettings(context)
        result.success(null)
      }
      "openAppSettings" -> {
        openAppSettings(context)
        result.success(null)
      }
      "queryUsage" -> queryUsage(call, result)
      "queryEvents" -> queryEvents(call, result)
      "queryNow" -> queryNow(call, result)
      "getAppIconPng" -> getAppIconPng(call, result)
      else -> result.notImplemented()
    }
  }

  private fun hasUsageAccess(ctx: Context): Boolean {
    val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
    val mode = if (Build.VERSION.SDK_INT >= 29) {
      ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), ctx.packageName)
    } else {
      ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), ctx.packageName)
    }
    return mode == AppOpsManager.MODE_ALLOWED
  }

  private fun openUsageAccessSettings(ctx: Context) {
    try {
      val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      ctx.startActivity(i)
    } catch (_: Exception) {
      // Some OEM ROMs may not resolve this intent reliably; fall back to app settings.
      openAppSettings(ctx)
    }
  }

  private fun openAppSettings(ctx: Context) {
    try {
      val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
      i.data = Uri.parse("package:${ctx.packageName}")
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      ctx.startActivity(i)
    } catch (_: Exception) {
      // ignore
    }
  }

  private fun queryUsage(call: MethodCall, result: Result) {
    if (!hasUsageAccess(context)) {
      result.error("permission_denied", "Usage Access not granted", null)
      return
    }

    val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
    val endMs = (call.argument<Number>("endMs") ?: 0).toLong()
    if (startMs <= 0 || endMs <= 0 || endMs <= startMs) {
      result.error("invalid_args", "startMs/endMs invalid", null)
      return
    }

    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val pm = context.packageManager

    // NOTE: queryAndAggregateUsageStats may return bucketed (daily) totals on some devices,
    // causing each sub-interval in the same day to look identical. For block-level slicing
    // we compute foreground time from UsageEvents instead.
    val lookbackMs = (call.argument<Number>("lookbackMs") ?: (2 * 60 * 1000)).toLong()
        .coerceIn(0, 24L * 60L * 60L * 1000L)
    val beginMs = (startMs - lookbackMs).coerceAtLeast(0)

    fun isFg(type: Int): Boolean {
      return type == UsageEvents.Event.MOVE_TO_FOREGROUND ||
          (Build.VERSION.SDK_INT >= 29 && type == UsageEvents.Event.ACTIVITY_RESUMED)
    }

    fun isBg(type: Int): Boolean {
      return type == UsageEvents.Event.MOVE_TO_BACKGROUND ||
          (Build.VERSION.SDK_INT >= 29 && type == UsageEvents.Event.ACTIVITY_PAUSED)
    }

    val labelCache: MutableMap<String, String> = HashMap()
    fun labelFor(pkg: String): String {
      val cached = labelCache[pkg]
      if (cached != null) return cached
      val label = try {
        val info = pm.getApplicationInfo(pkg, 0)
        pm.getApplicationLabel(info).toString()
      } catch (_: PackageManager.NameNotFoundException) {
        pkg
      } catch (_: Exception) {
        pkg
      }
      labelCache[pkg] = label
      return label
    }

    val totals: MutableMap<String, Long> = HashMap()
    val events = usm.queryEvents(beginMs, endMs)
    val event = UsageEvents.Event()

    var currentPkg: String? = null
    var lastTs = startMs

    while (events.hasNextEvent()) {
      events.getNextEvent(event)
      val pkg = event.packageName ?: continue
      if (pkg == context.packageName) continue

      val ts = event.timeStamp
      val type = event.eventType

      // Prime the "current foreground" state before the interval starts.
      if (ts < startMs) {
        if (isFg(type)) {
          currentPkg = pkg
        } else if (isBg(type) && currentPkg == pkg) {
          currentPkg = null
        }
        continue
      }

      if (ts > endMs) break
      val clampedTs = ts.coerceIn(startMs, endMs)

      if (currentPkg != null && clampedTs > lastTs) {
        totals[currentPkg] = (totals[currentPkg] ?: 0) + (clampedTs - lastTs)
      }

      if (isFg(type)) {
        currentPkg = pkg
      } else if (isBg(type) && currentPkg == pkg) {
        currentPkg = null
      }

      lastTs = clampedTs
    }

    if (currentPkg != null && endMs > lastTs) {
      totals[currentPkg] = (totals[currentPkg] ?: 0) + (endMs - lastTs)
    }

    val out: MutableList<Map<String, Any>> = ArrayList()
    for ((pkg, ms) in totals) {
      if (ms <= 0) continue
      out.add(mapOf("packageName" to pkg, "label" to labelFor(pkg), "foregroundMs" to ms))
    }
    result.success(out)
  }

  private fun queryEvents(call: MethodCall, result: Result) {
    if (!hasUsageAccess(context)) {
      result.error("permission_denied", "Usage Access not granted", null)
      return
    }

    val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
    val endMs = (call.argument<Number>("endMs") ?: 0).toLong()
    if (startMs <= 0 || endMs <= 0 || endMs <= startMs) {
      result.error("invalid_args", "startMs/endMs invalid", null)
      return
    }

    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val events = usm.queryEvents(startMs, endMs)
    val event = UsageEvents.Event()
    val pm = context.packageManager
    val labelCache: MutableMap<String, String> = HashMap()

    fun labelFor(pkg: String): String {
      val cached = labelCache[pkg]
      if (cached != null) return cached
      val label = try {
        val info = pm.getApplicationInfo(pkg, 0)
        pm.getApplicationLabel(info).toString()
      } catch (_: PackageManager.NameNotFoundException) {
        pkg
      } catch (_: Exception) {
        pkg
      }
      labelCache[pkg] = label
      return label
    }

    val out: MutableList<Map<String, Any>> = ArrayList()
    while (events.hasNextEvent()) {
      events.getNextEvent(event)
      val pkg = event.packageName ?: continue
      val t = event.timeStamp
      val type = event.eventType

      // We only care about transitions that approximate "user switched to/from app".
      val isFg =
          type == UsageEvents.Event.MOVE_TO_FOREGROUND ||
              (Build.VERSION.SDK_INT >= 29 &&
                  type == UsageEvents.Event.ACTIVITY_RESUMED)
      val isBg =
          type == UsageEvents.Event.MOVE_TO_BACKGROUND ||
              (Build.VERSION.SDK_INT >= 29 &&
                  type == UsageEvents.Event.ACTIVITY_PAUSED)
      val keep = isFg || isBg
      if (!keep) continue

      val cls = event.className ?: ""
      val label = labelFor(pkg)
      out.add(mapOf(
          "timestampMs" to t,
          "eventType" to type,
          "phase" to (if (isFg) "fg" else "bg"),
          "packageName" to pkg,
          "className" to cls,
          "label" to label,
      ))
    }
    result.success(out)
  }

  private fun queryNow(call: MethodCall, result: Result) {
    if (!hasUsageAccess(context)) {
      result.error("permission_denied", "Usage Access not granted", null)
      return
    }

    val lookbackMs = (call.argument<Number>("lookbackMs") ?: (10 * 60 * 1000)).toLong().coerceAtLeast(15_000)
    val endMs = System.currentTimeMillis()
    val startMs = (endMs - lookbackMs).coerceAtLeast(0)

    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val events = usm.queryEvents(startMs, endMs)
    val event = UsageEvents.Event()
    var lastTs: Long = 0
    var lastType: Int = 0
    var lastPkg: String? = null
    var lastCls: String? = null

    while (events.hasNextEvent()) {
      events.getNextEvent(event)
      val type = event.eventType
      val isFg =
          type == UsageEvents.Event.MOVE_TO_FOREGROUND ||
              (Build.VERSION.SDK_INT >= 29 &&
                  type == UsageEvents.Event.ACTIVITY_RESUMED)
      if (!isFg) continue

      val pkg = event.packageName
      if (pkg == null || pkg == context.packageName) continue

      lastTs = event.timeStamp
      lastType = event.eventType
      lastPkg = pkg
      lastCls = event.className
    }

    if (lastPkg == null) {
      result.success(null)
      return
    }

    val pm = context.packageManager
    val pkg = lastPkg ?: ""
    val label = try {
      val info = pm.getApplicationInfo(pkg, 0)
      pm.getApplicationLabel(info).toString()
    } catch (_: PackageManager.NameNotFoundException) {
      pkg
    } catch (_: Exception) {
      pkg
    }

    val out = mapOf(
        "timestampMs" to lastTs,
        "eventType" to lastType,
        "packageName" to pkg,
        "className" to (lastCls ?: ""),
        "label" to label,
    )
    result.success(out)
  }

  private fun getAppIconPng(call: MethodCall, result: Result) {
    val pkg = (call.argument<String>("packageName") ?: "").trim()
    val sizePx =
        (call.argument<Number>("sizePx") ?: 64).toInt().coerceIn(16, 256)

    if (pkg.isEmpty()) {
      result.error("invalid_args", "packageName missing", null)
      return
    }

    val pm = context.packageManager
    val bytes = try {
      val drawable = pm.getApplicationIcon(pkg)
      val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
        Bitmap.createScaledBitmap(drawable.bitmap, sizePx, sizePx, true)
      } else {
        val b = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(c)
        b
      }

      val out = ByteArrayOutputStream()
      bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
      out.toByteArray()
    } catch (_: PackageManager.NameNotFoundException) {
      null
    } catch (_: Exception) {
      null
    }

    result.success(bytes)
  }
}
