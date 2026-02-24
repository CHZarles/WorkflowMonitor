import "dart:convert";
import "dart:io";

import "package:path_provider/path_provider.dart";

import "mobile_models.dart";
import "mobile_usage.dart";

class MobileStore {
  static final MobileStore instance = MobileStore._();

  MobileStore._();

  File? _file;
  Map<String, MobileBlock> _byId = {};
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path =
        "${dir.path}${Platform.pathSeparator}recorderphone-mobile.json";
    _file = File(path);
    return _file!;
  }

  Future<void> _load() async {
    if (_loaded) return;
    final file = await _ensureFile();
    if (!await file.exists()) {
      _byId = {};
      _loaded = true;
      return;
    }
    try {
      final raw = await file.readAsString();
      final obj = jsonDecode(raw);
      final Map<String, MobileBlock> next = {};
      if (obj is Map && obj["blocks"] is List) {
        for (final it in (obj["blocks"] as List)) {
          if (it is Map) {
            final b = MobileBlock.fromJson(Map<String, dynamic>.from(it));
            next[b.id] = b;
          }
        }
      }
      _byId = next;
      _loaded = true;
    } catch (_) {
      // Corrupted file: keep a backup and start fresh.
      try {
        final ts =
            DateTime.now().toUtc().toIso8601String().replaceAll(":", "-");
        await file.rename("${file.path}.bad.$ts");
      } catch (_) {
        // ignore
      }
      _byId = {};
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    final file = await _ensureFile();
    final blocks = _byId.values.toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final obj = {
      "schema": 1,
      "updated_at_iso": DateTime.now().toUtc().toIso8601String(),
      "blocks": blocks.map((b) => b.toJson()).toList(),
    };
    final text = const JsonEncoder.withIndent("  ").convert(obj);

    final tmp = File("${file.path}.tmp");
    await tmp.writeAsString(text);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ignore
    }
    await tmp.rename(file.path);
  }

  Future<List<MobileBlock>> listBlocksForDay(DateTime dayLocal) async {
    await _load();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    final out = _byId.values
        .where((b) => b.startMs >= startMs && b.startMs < endMs)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return out;
  }

  Future<void> upsertReview({
    required String blockId,
    required bool skipped,
    String? doing,
    String? output,
    String? next,
    required List<String> tags,
  }) async {
    await _load();
    final b = _byId[blockId];
    if (b == null) return;

    final review = MobileReview(
      updatedAtIso: DateTime.now().toUtc().toIso8601String(),
      skipped: skipped,
      doing: (doing ?? "").trim().isEmpty ? null : doing!.trim(),
      output: (output ?? "").trim().isEmpty ? null : output!.trim(),
      next: (next ?? "").trim().isEmpty ? null : next!.trim(),
      tags: tags,
    );
    _byId[blockId] = MobileBlock(
      id: b.id,
      startMs: b.startMs,
      endMs: b.endMs,
      topItems: b.topItems,
      review: review,
    );
    await _persist();
  }

  Future<void> ensureBlocksForToday({required Duration blockSize}) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await ensureBlocksForDay(dayLocal: day, blockSize: blockSize);
  }

  Future<void> ensureBlocksForDay({
    required DateTime dayLocal,
    required Duration blockSize,
  }) async {
    await _load();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final now = DateTime.now();
    final blockMs = blockSize.inMilliseconds;
    if (blockMs < const Duration(minutes: 5).inMilliseconds) return;

    final dayStartMs = start.millisecondsSinceEpoch;
    final nowMs = now.millisecondsSinceEpoch;

    var changed = false;

    // Only create *completed* blocks: [t, t+block] where end <= now.
    for (var s = dayStartMs; s + blockMs <= nowMs; s += blockMs) {
      final id = "a-${s.toString()}";
      if (_byId.containsKey(id)) continue;

      final e = s + blockMs;
      final items =
          await MobileUsage.instance.queryTopApps(startMs: s, endMs: e);
      _byId[id] = MobileBlock(
        id: id,
        startMs: s,
        endMs: e,
        topItems: items,
        review: null,
      );
      changed = true;
    }

    if (changed) await _persist();
  }

  Future<void> wipeAll() async {
    await _load();
    _byId = {};
    await _persist();
  }
}
