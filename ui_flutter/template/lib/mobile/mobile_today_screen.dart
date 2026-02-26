import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "../utils/format.dart";
import "mobile_models.dart";
import "mobile_prefs.dart";
import "mobile_quick_review_sheet.dart";
import "mobile_store.dart";
import "mobile_usage.dart";
import "mobile_widgets.dart";

class MobileTodayScreen extends StatefulWidget {
  const MobileTodayScreen({super.key});

  @override
  State<MobileTodayScreen> createState() => _MobileTodayScreenState();
}

class _MobileTodayScreenState extends State<MobileTodayScreen>
    with WidgetsBindingObserver {
  bool _loading = false;
  String? _error;
  List<MobileBlock> _blocks = const [];
  MobileNow? _now;
  int _blockMinutes = MobilePrefs.defaultBlockMinutes;
  DateTime _day = DateTime.now();

  @override
  void initState() {
    super.initState();
    _day = _normalizeDay(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User likely just granted Usage Access in system settings.
      if (!_loading && _viewingToday()) {
        _refresh();
      }
    }
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

  String _ageLabel(int timestampMs) {
    final ageMs = DateTime.now().millisecondsSinceEpoch - timestampMs;
    if (ageMs <= 15 * 1000) {
      return "刚刚";
    }
    final minutes = (ageMs / 60000).floor();
    if (minutes <= 0) {
      return "刚刚";
    }
    if (minutes < 60) {
      return "$minutes 分钟前";
    }
    final hours = (minutes / 60).floor();
    return "$hours 小时前";
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

  Future<void> _refresh() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blockMinutes = await MobilePrefs.getBlockMinutes();
      if (!mounted) {
        return;
      }
      _blockMinutes = blockMinutes;

      final ok = await MobileUsage.instance.hasPermission();
      if (!ok) {
        setState(() {
          _blocks = const [];
          _now = null;
          _error = "需要开启“使用情况访问权限”（Usage Access）才能读取应用使用记录。";
        });
        return;
      }

      final nowInfo =
          _viewingToday() ? await MobileUsage.instance.queryNow() : null;

      await MobileStore.instance.ensureBlocksForDay(
        dayLocal: _day,
        blockSize: Duration(minutes: _blockMinutes),
      );
      final blocks = await MobileStore.instance.listBlocksForDay(_day);
      if (!mounted) {
        return;
      }
      setState(() {
        _now = nowInfo;
        _blocks = blocks;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
    final title = _viewingToday() ? "今天" : "日视图";
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
            tooltip: "刷新",
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
                        child: const Text("去设置开启"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RecorderTokens.space4),
            ],
            if (_error == null && _viewingToday()) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(RecorderTokens.space4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _now == null
                          ? const Icon(Icons.bolt_outlined)
                          : MobileAppIcon(
                              packageName: _now!.id,
                              label: _now!.displayName,
                              size: 28,
                            ),
                      const SizedBox(width: RecorderTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Now（正在用）",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: RecorderTokens.space1),
                            Text(
                              _now == null
                                  ? "（尚未识别到）"
                                  : "${_now!.displayName} · ${_ageLabel(_now!.timestampMs)}",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
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
                  child: Text("还没有数据。授予“使用情况访问权限”后点右上角刷新。"),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _blocks.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: RecorderTokens.space3),
                  itemBuilder: (context, i) {
                    final b = _blocks[i];
                    final start =
                        DateTime.fromMillisecondsSinceEpoch(b.startMs);
                    final end = DateTime.fromMillisecondsSinceEpoch(b.endMs);
                    final line1 =
                        "${formatHHMM(start.toUtc().toIso8601String())}–${formatHHMM(end.toUtc().toIso8601String())}";
                    return InkWell(
                      onTap: () => _openReview(b),
                      borderRadius:
                          BorderRadius.circular(RecorderTokens.radius3),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  _statusChip(b),
                                ],
                              ),
                              const SizedBox(height: RecorderTokens.space2),
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
      ),
    );
  }
}
