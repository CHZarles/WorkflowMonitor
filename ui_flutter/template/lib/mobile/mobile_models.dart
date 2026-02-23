class MobileTopItem {
  const MobileTopItem({required this.id, required this.seconds});

  final String id; // packageName
  final int seconds;

  Map<String, Object> toJson() => {"id": id, "seconds": seconds};

  static MobileTopItem fromJson(Map obj) {
    final id = (obj["id"] ?? "").toString();
    final sRaw = obj["seconds"];
    final seconds = sRaw is int ? sRaw : int.tryParse(sRaw.toString()) ?? 0;
    return MobileTopItem(id: id, seconds: seconds);
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
      doing: (obj["doing"] ?? "").toString().trim().isEmpty ? null : (obj["doing"] ?? "").toString(),
      output: (obj["output"] ?? "").toString().trim().isEmpty ? null : (obj["output"] ?? "").toString(),
      next: (obj["next"] ?? "").toString().trim().isEmpty ? null : (obj["next"] ?? "").toString(),
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
}

