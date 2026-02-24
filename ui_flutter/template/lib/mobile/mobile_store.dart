import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:sqflite/sqflite.dart";

import "mobile_models.dart";
import "mobile_usage.dart";

class MobileStore {
  static final MobileStore instance = MobileStore._();

  MobileStore._();

  Database? _db;
  Future<Database>? _opening;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!;

    _opening = () async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final dbPath = p.join(dir.path, "recorderphone-mobile.db");

      final db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute("""
CREATE TABLE IF NOT EXISTS blocks (
  id TEXT PRIMARY KEY,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  top_json TEXT NOT NULL,
  review_json TEXT NULL
);
""");
          await db.execute(
              "CREATE UNIQUE INDEX IF NOT EXISTS idx_blocks_start_ms ON blocks(start_ms);");
        },
      );

      // Defensive: ensure schema exists even if `onCreate` was skipped for some reason.
      await db.execute("""
CREATE TABLE IF NOT EXISTS blocks (
  id TEXT PRIMARY KEY,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  top_json TEXT NOT NULL,
  review_json TEXT NULL
);
""");
      await db.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_blocks_start_ms ON blocks(start_ms);");

      _db = db;
      return db;
    }();

    try {
      return await _opening!;
    } finally {
      _opening = null;
    }
  }

  Future<List<MobileBlock>> listBlocksForDay(DateTime dayLocal) async {
    final db = await _open();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    final rows = await db.rawQuery(
      "SELECT id, start_ms, end_ms, top_json, review_json FROM blocks WHERE start_ms >= ? AND start_ms < ? ORDER BY start_ms ASC",
      [startMs, endMs],
    );

    final out = <MobileBlock>[];
    for (final r in rows) {
      final id = (r["id"] ?? "").toString();
      final sRaw = r["start_ms"];
      final eRaw = r["end_ms"];
      final startMs = sRaw is int ? sRaw : int.tryParse(sRaw.toString()) ?? 0;
      final endMs = eRaw is int ? eRaw : int.tryParse(eRaw.toString()) ?? 0;

      final topRaw = (r["top_json"] ?? "[]").toString();
      final topObj = jsonDecode(topRaw);
      final top = <MobileTopItem>[];
      if (topObj is List) {
        for (final it in topObj) {
          if (it is Map) top.add(MobileTopItem.fromJson(it));
        }
      }

      MobileReview? review;
      final reviewRaw = (r["review_json"] ?? "").toString();
      if (reviewRaw.trim().isNotEmpty) {
        final obj = jsonDecode(reviewRaw);
        if (obj is Map) review = MobileReview.fromJson(obj);
      }

      out.add(MobileBlock(
        id: id,
        startMs: startMs,
        endMs: endMs,
        topItems: top,
        review: review,
      ));
    }
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
    final db = await _open();
    final review = MobileReview(
      updatedAtIso: DateTime.now().toUtc().toIso8601String(),
      skipped: skipped,
      doing: (doing ?? "").trim().isEmpty ? null : doing!.trim(),
      output: (output ?? "").trim().isEmpty ? null : output!.trim(),
      next: (next ?? "").trim().isEmpty ? null : next!.trim(),
      tags: tags,
    );
    await db.rawUpdate(
      "UPDATE blocks SET review_json = ? WHERE id = ?",
      [jsonEncode(review.toJson()), blockId],
    );
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
    final db = await _open();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final now = DateTime.now();
    final blockMs = blockSize.inMilliseconds;
    if (blockMs < const Duration(minutes: 5).inMilliseconds) return;

    final dayStartMs = start.millisecondsSinceEpoch;
    final nowMs = now.millisecondsSinceEpoch;

    for (var s = dayStartMs; s + blockMs <= nowMs; s += blockMs) {
      final e = s + blockMs;

      final exists = await db.rawQuery(
        "SELECT 1 FROM blocks WHERE start_ms = ? LIMIT 1",
        [s],
      );
      if (exists.isNotEmpty) continue;

      final items =
          await MobileUsage.instance.queryTopApps(startMs: s, endMs: e);
      final id = "a-${s.toString()}";
      await db.rawInsert(
        "INSERT INTO blocks(id, start_ms, end_ms, top_json, review_json) VALUES(?, ?, ?, ?, NULL)",
        [id, s, e, jsonEncode(items.map((it) => it.toJson()).toList())],
      );
    }
  }

  Future<void> wipeAll() async {
    final db = await _open();
    await db.execute("DELETE FROM blocks");
  }
}
