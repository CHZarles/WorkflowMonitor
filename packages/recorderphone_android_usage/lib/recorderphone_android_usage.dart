import "package:flutter/services.dart";

class AndroidAppUsage {
  const AndroidAppUsage({required this.packageName, required this.foregroundMs});

  final String packageName;
  final int foregroundMs;

  static AndroidAppUsage fromJson(Map obj) {
    final pkg = (obj["packageName"] ?? "").toString();
    final msRaw = obj["foregroundMs"];
    final ms = msRaw is int ? msRaw : int.tryParse(msRaw.toString()) ?? 0;
    return AndroidAppUsage(packageName: pkg, foregroundMs: ms);
  }
}

class RecorderphoneAndroidUsage {
  static const MethodChannel _channel = MethodChannel("recorderphone_android_usage");

  static Future<bool> hasUsageAccess() async {
    final v = await _channel.invokeMethod<bool>("hasUsageAccess");
    return v ?? false;
  }

  static Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod<void>("openUsageAccessSettings");
  }

  /// Returns aggregated usage for the given interval.
  ///
  /// Requires Usage Access permission. Throws `PlatformException(code: "permission_denied")`
  /// if permission is missing.
  static Future<List<AndroidAppUsage>> queryUsage({
    required int startMs,
    required int endMs,
  }) async {
    final res = await _channel.invokeMethod<List<Object?>>("queryUsage", {
      "startMs": startMs,
      "endMs": endMs,
    });
    final out = <AndroidAppUsage>[];
    for (final it in (res ?? const [])) {
      if (it is Map) out.add(AndroidAppUsage.fromJson(it));
    }
    return out;
  }
}

