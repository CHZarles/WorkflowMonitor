import "package:flutter/services.dart";

class AndroidUsageEvent {
  const AndroidUsageEvent({
    required this.timestampMs,
    required this.eventType,
    required this.packageName,
    this.className,
    this.label,
  });

  final int timestampMs;
  final int eventType;
  final String packageName;
  final String? className;
  final String? label;

  static AndroidUsageEvent fromJson(Map obj) {
    final tsRaw = obj["timestampMs"];
    final ts = tsRaw is int ? tsRaw : int.tryParse(tsRaw.toString()) ?? 0;
    final typeRaw = obj["eventType"];
    final type = typeRaw is int
        ? typeRaw
        : int.tryParse(typeRaw.toString()) ?? 0;
    final pkg = (obj["packageName"] ?? "").toString();
    final clsRaw = (obj["className"] ?? "").toString().trim();
    final labelRaw = (obj["label"] ?? "").toString().trim();
    return AndroidUsageEvent(
      timestampMs: ts,
      eventType: type,
      packageName: pkg,
      className: clsRaw.isEmpty ? null : clsRaw,
      label: labelRaw.isEmpty ? null : labelRaw,
    );
  }
}

class AndroidAppUsage {
  const AndroidAppUsage({
    required this.packageName,
    this.label,
    required this.foregroundMs,
  });

  final String packageName;
  final String? label;
  final int foregroundMs;

  static AndroidAppUsage fromJson(Map obj) {
    final pkg = (obj["packageName"] ?? "").toString();
    final labelRaw = (obj["label"] ?? "").toString().trim();
    final msRaw = obj["foregroundMs"];
    final ms = msRaw is int ? msRaw : int.tryParse(msRaw.toString()) ?? 0;
    return AndroidAppUsage(
      packageName: pkg,
      label: labelRaw.isEmpty ? null : labelRaw,
      foregroundMs: ms,
    );
  }
}

class RecorderphoneAndroidUsage {
  static const MethodChannel _channel = MethodChannel(
    "recorderphone_android_usage",
  );

  static Future<bool> hasUsageAccess() async {
    final v = await _channel.invokeMethod<bool>("hasUsageAccess");
    return v ?? false;
  }

  static Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod<void>("openUsageAccessSettings");
  }

  static Future<void> openAppSettings() async {
    await _channel.invokeMethod<void>("openAppSettings");
  }

  static Future<Uint8List?> getAppIconPng({
    required String packageName,
    int sizePx = 64,
  }) async {
    final v = await _channel.invokeMethod<Uint8List?>("getAppIconPng", {
      "packageName": packageName,
      "sizePx": sizePx,
    });
    return v;
  }

  /// Returns UsageEvents for the given interval.
  ///
  /// Requires Usage Access permission. Throws `PlatformException(code: "permission_denied")`
  /// if permission is missing.
  static Future<List<AndroidUsageEvent>> queryEvents({
    required int startMs,
    required int endMs,
  }) async {
    final res = await _channel.invokeMethod<List<Object?>>("queryEvents", {
      "startMs": startMs,
      "endMs": endMs,
    });
    final out = <AndroidUsageEvent>[];
    for (final it in (res ?? const [])) {
      if (it is Map) out.add(AndroidUsageEvent.fromJson(it));
    }
    return out;
  }

  /// Best-effort "Now": latest foreground-like event within `lookbackMs`.
  ///
  /// Returns `null` if no events are found in the lookback window.
  static Future<AndroidUsageEvent?> queryNow({
    int lookbackMs = 10 * 60 * 1000,
  }) async {
    final res = await _channel.invokeMethod<Object?>("queryNow", {
      "lookbackMs": lookbackMs,
    });
    if (res is Map) return AndroidUsageEvent.fromJson(res);
    return null;
  }

  /// Returns aggregated usage for the given interval.
  ///
  /// Requires Usage Access permission. Throws `PlatformException(code: "permission_denied")`
  /// if permission is missing.
  static Future<List<AndroidAppUsage>> queryUsage({
    required int startMs,
    required int endMs,
    int? lookbackMs,
  }) async {
    final res = await _channel.invokeMethod<List<Object?>>("queryUsage", {
      "startMs": startMs,
      "endMs": endMs,
      if (lookbackMs != null) "lookbackMs": lookbackMs,
    });
    final out = <AndroidAppUsage>[];
    for (final it in (res ?? const [])) {
      if (it is Map) out.add(AndroidAppUsage.fromJson(it));
    }
    return out;
  }
}
