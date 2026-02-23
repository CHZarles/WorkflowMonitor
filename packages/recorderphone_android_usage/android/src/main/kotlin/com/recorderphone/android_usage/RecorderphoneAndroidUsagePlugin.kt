package com.recorderphone.android_usage

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.app.usage.UsageStatsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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
      "queryUsage" -> queryUsage(call, result)
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
    val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(i)
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
    val map = usm.queryAndAggregateUsageStats(startMs, endMs)
    val out: MutableList<Map<String, Any>> = ArrayList()
    for ((_, s) in map) {
      val ms = s.totalTimeInForeground
      if (ms <= 0) continue
      out.add(mapOf("packageName" to s.packageName, "foregroundMs" to ms))
    }
    result.success(out)
  }
}

