import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "../utils/format.dart";
import "mobile_models.dart";
import "mobile_quick_review_sheet.dart";
import "mobile_store.dart";
import "mobile_usage.dart";

class MobileTodayScreen extends StatefulWidget {
  const MobileTodayScreen({super.key});

  @override
  State<MobileTodayScreen> createState() => _MobileTodayScreenState();
}

class _MobileTodayScreenState extends State<MobileTodayScreen> {
  bool _loading = false;
  String? _error;
  List<MobileBlock> _blocks = const [];

  int _blockMinutes = 45;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await MobileUsage.instance.hasPermission();
      if (!ok) {
        setState(() {
          _blocks = const [];
          _error = "Usage Access is required to collect app usage.";
        });
        return;
      }

      await MobileStore.instance.ensureBlocksForToday(blockSize: Duration(minutes: _blockMinutes));
      final blocks = await MobileStore.instance.listBlocksForDay(DateTime.now());
      if (!mounted) return;
      setState(() => _blocks = blocks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReview(MobileBlock b) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MobileQuickReviewSheet(block: b),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Widget _statusChip(MobileBlock b) {
    final cs = Theme.of(context).colorScheme;
    if (b.reviewed) {
      return Chip(
        label: const Text("Done"),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: cs.outlineVariant),
      );
    }
    if (b.skipped) {
      return Chip(
        label: const Text("Skipped"),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: cs.outlineVariant),
      );
    }
    return Chip(
      label: const Text("Due"),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: cs.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = "Today";
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          children: [
            if (_error != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(RecorderTokens.space4),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline),
                      const SizedBox(width: RecorderTokens.space3),
                      Expanded(child: Text(_error!)),
                      const SizedBox(width: RecorderTokens.space3),
                      FilledButton(
                        onPressed: () async {
                          await MobileUsage.instance.openPermissionSettings();
                        },
                        child: const Text("Open settings"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RecorderTokens.space4),
            ],
            if (_loading && _blocks.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_blocks.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("No blocks yet. Pull to refresh after granting Usage Access."),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _blocks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: RecorderTokens.space3),
                  itemBuilder: (context, i) {
                    final b = _blocks[i];
                    final start = DateTime.fromMillisecondsSinceEpoch(b.startMs);
                    final end = DateTime.fromMillisecondsSinceEpoch(b.endMs);
                    final line1 = "${formatHHMM(start.toUtc().toIso8601String())}–${formatHHMM(end.toUtc().toIso8601String())}";
                    final line2 = b.topItems.take(3).map((it) => "${it.id} ${formatDuration(it.seconds)}").join(" · ");
                    return InkWell(
                      onTap: () => _openReview(b),
                      borderRadius: BorderRadius.circular(RecorderTokens.radius3),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(RecorderTokens.space4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line1,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  _statusChip(b),
                                ],
                              ),
                              const SizedBox(height: RecorderTokens.space2),
                              Text(line2, style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

