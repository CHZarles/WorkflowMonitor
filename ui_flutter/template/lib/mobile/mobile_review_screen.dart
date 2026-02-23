import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "../utils/format.dart";
import "mobile_models.dart";
import "mobile_quick_review_sheet.dart";
import "mobile_store.dart";

class MobileReviewScreen extends StatefulWidget {
  const MobileReviewScreen({super.key});

  @override
  State<MobileReviewScreen> createState() => _MobileReviewScreenState();
}

class _MobileReviewScreenState extends State<MobileReviewScreen> {
  bool _loading = false;
  List<MobileBlock> _due = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final blocks = await MobileStore.instance.listBlocksForDay(DateTime.now());
      final due = blocks.where((b) => b.review == null || b.review!.skipped).toList();
      if (!mounted) return;
      setState(() => _due = due);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(MobileBlock b) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MobileQuickReviewSheet(block: b),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Review"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _due.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _due.isEmpty
              ? const Center(child: Text("No due blocks."))
              : ListView.separated(
                  padding: const EdgeInsets.all(RecorderTokens.space4),
                  itemCount: _due.length,
                  separatorBuilder: (_, __) => const SizedBox(height: RecorderTokens.space3),
                  itemBuilder: (context, i) {
                    final b = _due[i];
                    final start = DateTime.fromMillisecondsSinceEpoch(b.startMs);
                    final end = DateTime.fromMillisecondsSinceEpoch(b.endMs);
                    final title =
                        "${formatHHMM(start.toUtc().toIso8601String())}–${formatHHMM(end.toUtc().toIso8601String())}";
                    final sub = b.topItems.take(3).map((it) => "${it.displayName} ${formatDuration(it.seconds)}").join(" · ");
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RecorderTokens.radius3)),
                      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      title: Text(title),
                      subtitle: Text(sub),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(b),
                    );
                  },
                ),
    );
  }
}
