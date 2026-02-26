import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "../utils/format.dart";
import "mobile_models.dart";
import "mobile_quick_review_sheet.dart";
import "mobile_store.dart";
import "mobile_widgets.dart";

class MobileReviewScreen extends StatefulWidget {
  const MobileReviewScreen({super.key});

  @override
  State<MobileReviewScreen> createState() => _MobileReviewScreenState();
}

class _MobileReviewScreenState extends State<MobileReviewScreen> {
  DateTime _day = DateTime.now();
  bool _loading = false;
  List<MobileBlock> _blocks = const [];
  _MobileReviewFilter _filter = _MobileReviewFilter.due;

  @override
  void initState() {
    super.initState();
    _day = _normalizeDay(DateTime.now());
    _refresh();
  }

  DateTime _normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _viewingToday() {
    final now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: _normalizeDay(now).add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) {
      return;
    }
    final next = _normalizeDay(picked);
    if (next.year == _day.year &&
        next.month == _day.month &&
        next.day == _day.day) {
      return;
    }
    setState(() => _day = next);
    await _refresh();
  }

  List<MobileBlock> _applyFilter(List<MobileBlock> blocks) {
    switch (_filter) {
      case _MobileReviewFilter.due:
        return blocks.where((b) => b.review == null).toList();
      case _MobileReviewFilter.done:
        return blocks.where((b) => b.reviewed).toList();
      case _MobileReviewFilter.skipped:
        return blocks.where((b) => b.skipped).toList();
      case _MobileReviewFilter.all:
        return blocks;
    }
  }

  Future<void> _refresh() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final blocks = await MobileStore.instance.listBlocksForDay(_day);
      if (!mounted) {
        return;
      }
      setState(() => _blocks = blocks);
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
    if (changed == true) {
      await _refresh();
    }
  }

  Widget _statusChip(MobileBlock b) {
    final cs = Theme.of(context).colorScheme;
    if (b.reviewed) {
      return Chip(
        label: const Text("已完成"),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: cs.outlineVariant),
      );
    }
    if (b.skipped) {
      return Chip(
        label: const Text("已跳过"),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: cs.outlineVariant),
      );
    }
    return Chip(
      label: const Text("待复盘"),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: cs.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _viewingToday() ? "复盘" : "复盘";
    final shown = _applyFilter(_blocks);
    return Scaffold(
      appBar: AppBar(
        title: Text("$title · ${_dayLabel(_day)}"),
        actions: [
          IconButton(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: "选择日期",
          ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RecorderTokens.space4,
              RecorderTokens.space3,
              RecorderTokens.space4,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_MobileReviewFilter>(
                segments: const [
                  ButtonSegment(
                      value: _MobileReviewFilter.due, label: Text("待复盘")),
                  ButtonSegment(
                      value: _MobileReviewFilter.done, label: Text("已完成")),
                  ButtonSegment(
                      value: _MobileReviewFilter.skipped, label: Text("已跳过")),
                  ButtonSegment(
                      value: _MobileReviewFilter.all, label: Text("全部")),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          Expanded(
            child: _loading && shown.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? const Center(child: Text("没有数据。"))
                    : ListView.separated(
                        padding: const EdgeInsets.all(RecorderTokens.space4),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: RecorderTokens.space3),
                        itemBuilder: (context, i) {
                          final b = shown[i];
                          final start =
                              DateTime.fromMillisecondsSinceEpoch(b.startMs);
                          final end =
                              DateTime.fromMillisecondsSinceEpoch(b.endMs);
                          final title =
                              "${formatHHMM(start.toUtc().toIso8601String())}–${formatHHMM(end.toUtc().toIso8601String())}";
                          return InkWell(
                            onTap: () => _open(b),
                            borderRadius:
                                BorderRadius.circular(RecorderTokens.radius3),
                            child: Card(
                              child: Padding(
                                padding:
                                    const EdgeInsets.all(RecorderTokens.space4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        _statusChip(b),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: RecorderTokens.space2),
                                    MobileTopItemsList(items: b.topItems),
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
    );
  }
}

enum _MobileReviewFilter { due, done, skipped, all }
