class MobileTopItem {
  const MobileTopItem({
    required this.id,
    this.label,
    required this.seconds,
  });

  final String id; // packageName
  final String? label;
  final int seconds;

  Map<String, Object?> toJson() =>
      {"id": id, "label": label, "seconds": seconds};

  String get displayName {
    final v = (label ?? "").trim();
    return v.isEmpty ? id : v;
  }

  static MobileTopItem fromJson(Map obj) {
    final id = (obj["id"] ?? "").toString();
    final labelRaw = (obj["label"] ?? "").toString().trim();
    final sRaw = obj["seconds"];
    final seconds = sRaw is int ? sRaw : int.tryParse(sRaw.toString()) ?? 0;
    return MobileTopItem(
      id: id,
      label: labelRaw.isEmpty ? null : labelRaw,
      seconds: seconds,
    );
  }
}

class MobileReview {
  const MobileReview({
    required this.updatedAtIso,
    required this.skipped,
    this.doing,
    this.output,
    this.next,
    required this.tags,
  });

  final String updatedAtIso;
  final bool skipped;
  final String? doing;
  final String? output;
  final String? next;
  final List<String> tags;

  Map<String, Object?> toJson() => {
        "updated_at": updatedAtIso,
        "skipped": skipped,
        "doing": doing,
        "output": output,
        "next": next,
        "tags": tags,
      };

  static MobileReview fromJson(Map obj) {
    final tagsRaw = obj["tags"];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final t in tagsRaw) {
        final s = t.toString().trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }
    return MobileReview(
      updatedAtIso: (obj["updated_at"] ?? "").toString(),
      skipped: obj["skipped"] == true,
      doing: (obj["doing"] ?? "").toString().trim().isEmpty
          ? null
          : (obj["doing"] ?? "").toString(),
      output: (obj["output"] ?? "").toString().trim().isEmpty
          ? null
          : (obj["output"] ?? "").toString(),
      next: (obj["next"] ?? "").toString().trim().isEmpty
          ? null
          : (obj["next"] ?? "").toString(),
      tags: tags,
    );
  }
}

class MobileBlock {
  const MobileBlock({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.topItems,
    this.review,
  });

  final String id;
  final int startMs;
  final int endMs;
  final List<MobileTopItem> topItems;
  final MobileReview? review;

  bool get reviewed => review != null && review!.skipped == false;
  bool get skipped => review?.skipped == true;

  Map<String, Object?> toJson() => {
        "id": id,
        "start_ms": startMs,
        "end_ms": endMs,
        "top": topItems.map((it) => it.toJson()).toList(),
        "review": review?.toJson(),
      };

  static MobileBlock fromJson(Map<String, dynamic> obj) {
    final id = (obj["id"] ?? "").toString();
    final sRaw = obj["start_ms"];
    final eRaw = obj["end_ms"];
    final startMs = sRaw is int ? sRaw : int.tryParse(sRaw.toString()) ?? 0;
    final endMs = eRaw is int ? eRaw : int.tryParse(eRaw.toString()) ?? 0;

    final topItems = <MobileTopItem>[];
    final topRaw = obj["top"];
    if (topRaw is List) {
      for (final it in topRaw) {
        if (it is Map) topItems.add(MobileTopItem.fromJson(it));
      }
    }

    MobileReview? review;
    final reviewRaw = obj["review"];
    if (reviewRaw is Map) {
      review = MobileReview.fromJson(reviewRaw);
    }

    return MobileBlock(
      id: id,
      startMs: startMs,
      endMs: endMs,
      topItems: topItems,
      review: review,
    );
  }
}
