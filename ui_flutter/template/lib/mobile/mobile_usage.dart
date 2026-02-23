import "package:recorderphone_android_usage/recorderphone_android_usage.dart";

import "mobile_models.dart";

class MobileUsage {
  static final MobileUsage instance = MobileUsage._();
  MobileUsage._();

  Future<bool> hasPermission() => RecorderphoneAndroidUsage.hasUsageAccess();

  Future<void> openPermissionSettings() => RecorderphoneAndroidUsage.openUsageAccessSettings();

  Future<List<MobileTopItem>> queryTopApps({required int startMs, required int endMs, int topN = 5}) async {
    final rows = await RecorderphoneAndroidUsage.queryUsage(startMs: startMs, endMs: endMs);
    rows.sort((a, b) => b.foregroundMs.compareTo(a.foregroundMs));
    final out = <MobileTopItem>[];
    for (final r in rows.take(topN)) {
      final sec = (r.foregroundMs / 1000).round();
      if (sec <= 0) continue;
      out.add(MobileTopItem(id: r.packageName, seconds: sec));
    }
    return out;
  }
}

