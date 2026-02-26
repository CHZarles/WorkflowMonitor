import "dart:collection";
import "dart:typed_data";

import "package:recorderphone_android_usage/recorderphone_android_usage.dart";

import "mobile_models.dart";

class MobileUsage {
  static final MobileUsage instance = MobileUsage._();
  MobileUsage._();

  final _icons = _MobileIconCache();

  Future<bool> hasPermission() => RecorderphoneAndroidUsage.hasUsageAccess();

  Future<void> openPermissionSettings() =>
      RecorderphoneAndroidUsage.openUsageAccessSettings();

  Future<void> openAppSettings() => RecorderphoneAndroidUsage.openAppSettings();

  Future<Uint8List?> getAppIconBytes(
    String packageName, {
    int sizePx = 48,
  }) =>
      _icons.get(packageName, sizePx: sizePx);

  Uint8List? peekAppIconBytes(
    String packageName, {
    int sizePx = 48,
  }) =>
      _icons.peek(packageName, sizePx: sizePx);

  bool isAppIconCached(
    String packageName, {
    int sizePx = 48,
  }) =>
      _icons.contains(packageName, sizePx: sizePx);

  Future<MobileNow?> queryNow({int lookbackMs = 10 * 60 * 1000}) async {
    final ev = await RecorderphoneAndroidUsage.queryNow(lookbackMs: lookbackMs);
    if (ev == null) return null;
    return MobileNow(
        id: ev.packageName, label: ev.label, timestampMs: ev.timestampMs);
  }

  Future<List<MobileTopItem>> queryTopApps(
      {required int startMs,
      required int endMs,
      int? lookbackMs,
      int topN = 5}) async {
    final rows = await RecorderphoneAndroidUsage.queryUsage(
      startMs: startMs,
      endMs: endMs,
      lookbackMs: lookbackMs,
    );
    rows.sort((a, b) => b.foregroundMs.compareTo(a.foregroundMs));
    final out = <MobileTopItem>[];
    for (final r in rows.take(topN)) {
      final sec = (r.foregroundMs / 1000).round();
      if (sec <= 0) continue;
      out.add(MobileTopItem(id: r.packageName, label: r.label, seconds: sec));
    }
    return out;
  }
}

class _MobileIconCache {
  static const _capacity = 128;

  final _lru = LinkedHashMap<String, Uint8List?>();
  final _inflight = <String, Future<Uint8List?>>{};

  String _key(String packageName, int sizePx) =>
      "${sizePx.toString()}:${packageName.trim().toLowerCase()}";

  bool contains(String packageName, {required int sizePx}) {
    final pkg = packageName.trim();
    if (pkg.isEmpty) return false;
    return _lru.containsKey(_key(pkg, sizePx));
  }

  Uint8List? peek(String packageName, {required int sizePx}) {
    final pkg = packageName.trim();
    if (pkg.isEmpty) return null;

    final key = _key(pkg, sizePx);
    if (!_lru.containsKey(key)) return null;
    final v = _lru.remove(key);
    _lru[key] = v;
    return v;
  }

  Future<Uint8List?> get(String packageName, {required int sizePx}) {
    final pkg = packageName.trim();
    if (pkg.isEmpty) return Future.value(null);

    final key = _key(pkg, sizePx);
    if (_lru.containsKey(key)) {
      final v = _lru.remove(key);
      _lru[key] = v;
      return Future.value(v);
    }

    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final f = RecorderphoneAndroidUsage.getAppIconPng(
      packageName: pkg,
      sizePx: sizePx,
    ).then((bytes) {
      _inflight.remove(key);
      _put(key, bytes);
      return bytes;
    }).catchError((_) {
      _inflight.remove(key);
      _put(key, null);
      return null;
    });

    _inflight[key] = f;
    return f;
  }

  void _put(String key, Uint8List? bytes) {
    _lru.remove(key);
    _lru[key] = bytes;
    while (_lru.length > _capacity) {
      _lru.remove(_lru.keys.first);
    }
  }
}
