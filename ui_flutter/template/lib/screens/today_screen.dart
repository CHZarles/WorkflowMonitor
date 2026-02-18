import "dart:async";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../api/core_client.dart";
import "../theme/tokens.dart";
import "../utils/format.dart";
import "../widgets/block_detail_sheet.dart";
import "../widgets/day_timeline.dart";
import "../widgets/entity_avatar.dart";
import "../widgets/quick_review_sheet.dart";

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.client,
    required this.serverUrl,
    required this.onOpenReview,
    this.onOpenSettings,
    this.onOpenReviewQuery,
  });

  final CoreClient client;
  final String serverUrl;
  final VoidCallback onOpenReview;
  final VoidCallback? onOpenSettings;
  final Future<void> Function(String query, DateTime day)? onOpenReviewQuery;

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

enum _TopFilter { all, apps, web }

class _StatItem {
  const _StatItem({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.seconds,
    required this.hasAudio,
  });

  final String kind; // "app" | "domain"
  final String entity; // app id or hostname (for blacklist rules)
  final String label;
  final String? subtitle;
  final int seconds;
  final bool hasAudio;
}

class _TopAgg {
  const _TopAgg({required this.focusSeconds, required this.audioSeconds, required this.items});

  final int focusSeconds;
  final int audioSeconds;
  final List<_StatItem> items;
}

class _LaneAcc {
  _LaneAcc({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String kind;
  final String entity;
  final String label;
  final String? subtitle;
  final IconData icon;
  int totalSeconds = 0;
  int firstStartMinute = 1440;
  final List<DayTimelineBar> bars = [];
}

class _RangeStatItem {
  const _RangeStatItem({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.seconds,
    required this.audio,
  });

  final String kind; // "app" | "domain"
  final String entity; // app id or hostname
  final String label;
  final String? subtitle;
  final int seconds;
  final bool audio;
}

class _FlowItem {
  const _FlowItem({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.start,
    required this.end,
    required this.seconds,
    required this.icon,
  });

  final String kind; // "app" | "domain"
  final String entity;
  final String label;
  final String? subtitle;
  final DateTime start;
  final DateTime end;
  final int seconds;
  final IconData icon;
}

class TodayScreenState extends State<TodayScreen> {
  static const _prefSnoozeUntilMs = "reviewSnoozeUntilMs";
  static const _prefSnoozeBlockId = "reviewSnoozeBlockId";

  static const _nowPollSeconds = 5;
  static const _blocksPollSeconds = 60;

  _TopFilter _topFilter = _TopFilter.all;

  DateTime _day = DateTime.now();

  int _blockSeconds = 45 * 60;
  bool _coreStoreTitles = false;
  bool _coreStoreExePath = false;
  bool _loading = true;
  String? _error;
  List<TimelineSegment> _segments = const [];
  List<BlockSummary> _blocks = const [];
  BlockSummary? _dueBlock;
  EventRecord? _latestAppEvent;
  EventRecord? _latestTabEvent;
  EventRecord? _latestAudioEvent;
  EventRecord? _latestAudioStopEvent;
  EventRecord? _latestAppAudioEvent;
  EventRecord? _latestAppAudioStopEvent;
  final Map<String, String> _latestTitleByKey = {};

  Timer? _nowTimer;
  Timer? _blocksTimer;
  bool _promptShowing = false;
  bool _refreshingNow = false;
  bool _refreshingBlocks = false;
  bool _timelineShowAll = false;
  bool _timelineSortByTime = false;
  DateTime? _nowUpdatedAt;
  DateTime? _blocksUpdatedAt;
  int? _lastAnyEventId;
  DateTime? _lastAutoBlocksRefreshAt;
  int? _snoozeUntilMs;
  String? _snoozeBlockId;

  bool _rulesLoading = true;
  final Map<String, int> _ruleIdByKey = {};
  final Set<String> _blockedKeys = {};

  @override
  void initState() {
    super.initState();
    _loadReminderPrefs();
    _loadCoreSettings();
    _loadRules();
    refresh(triggerReminder: _viewingToday());
    _nowTimer = Timer.periodic(const Duration(seconds: _nowPollSeconds), (_) {
      if (!_viewingToday()) return;
      _refreshNow(silent: true, kickBlocksOnChange: true);
    });
    _blocksTimer = Timer.periodic(const Duration(seconds: _blocksPollSeconds), (_) {
      if (!_viewingToday()) return;
      _refreshBlocks(silent: true, triggerReminder: true);
    });
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverUrl != widget.serverUrl) {
      _loadRules();
      refresh(triggerReminder: _viewingToday());
    }
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _blocksTimer?.cancel();
    super.dispose();
  }

  DateTime _normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _todayDay() => _normalizeDay(DateTime.now());

  bool _viewingToday() => _isSameDay(_normalizeDay(_day), _todayDay());

  String _dateLocal(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  int _tzOffsetMinutesForDay(DateTime d) {
    // Prefer noon to avoid DST edge cases near midnight.
    final noon = DateTime(d.year, d.month, d.day, 12);
    return noon.timeZoneOffset.inMinutes;
  }

  bool _canGoNextDay() {
    final day = _normalizeDay(_day);
    return day.isBefore(_todayDay());
  }

  Future<void> _setDay(DateTime d) async {
    final next = _normalizeDay(d);
    final viewingToday = _isSameDay(next, _todayDay());

    setState(() {
      _day = next;
      if (!viewingToday) {
        _latestAppEvent = null;
        _latestTabEvent = null;
        _latestAudioEvent = null;
        _latestAudioStopEvent = null;
        _latestAppAudioEvent = null;
        _latestAppAudioStopEvent = null;
        _latestTitleByKey.clear();
        _nowUpdatedAt = null;
      }
    });

    await refresh(silent: false, triggerReminder: viewingToday);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _normalizeDay(_day),
      firstDate: DateTime(2020, 1, 1),
      lastDate: _todayDay(),
    );
    if (picked == null) return;
    await _setDay(picked);
  }

  bool _isReviewed(BlockSummary b) {
    final r = b.review;
    if (r == null) return false;
    if (r.skipped) return true;
    final doing = (r.doing ?? "").trim();
    final output = (r.output ?? "").trim();
    final next = (r.next ?? "").trim();
    return doing.isNotEmpty || output.isNotEmpty || next.isNotEmpty || r.tags.isNotEmpty;
  }

  BlockSummary? _findDueBlock(List<BlockSummary> blocks) {
    if (blocks.isEmpty) return null;
    final now = DateTime.now();
    const minSeconds = 5 * 60;
    final fullBlockSeconds = _blockSeconds;

    for (var i = blocks.length - 1; i >= 0; i--) {
      final b = blocks[i];
      if (b.totalSeconds < minSeconds) continue;
      if (_isReviewed(b)) continue;

      final hasNext = i < blocks.length - 1;
      if (hasNext) return b;

      if (b.totalSeconds >= fullBlockSeconds) return b;

      // If the last block hasn't advanced for a bit, treat it as ended (idle cutoff).
      try {
        final end = DateTime.parse(b.endTs).toLocal();
        if (now.difference(end) > const Duration(seconds: 30)) {
          return b;
        }
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

  Future<void> _loadReminderPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _snoozeUntilMs = prefs.getInt(_prefSnoozeUntilMs);
        _snoozeBlockId = prefs.getString(_prefSnoozeBlockId);
      });
    } catch (_) {
      // best effort
    }
  }

  Future<void> _loadCoreSettings() async {
    try {
      final s = await widget.client.settings();
      if (!mounted) return;
      setState(() {
        _blockSeconds = s.blockSeconds;
        _coreStoreTitles = s.storeTitles;
        _coreStoreExePath = s.storeExePath;
      });
    } catch (_) {
      // best effort
    }
  }

  String _ruleKey(String kind, String value) => "$kind|$value";

  bool _isBlockedEntity({required String kind, required String entity}) {
    if (kind != "domain" && kind != "app") return false;
    final value = kind == "domain" ? entity.toLowerCase() : entity;
    return _blockedKeys.contains(_ruleKey(kind, value));
  }

  Future<void> _loadRules() async {
    setState(() => _rulesLoading = true);
    try {
      final rules = await widget.client.privacyRules();
      if (!mounted) return;
      setState(() {
        _ruleIdByKey.clear();
        _blockedKeys.clear();
        for (final r in rules) {
          final value = r.kind == "domain" ? r.value.toLowerCase() : r.value;
          final key = _ruleKey(r.kind, value);
          _ruleIdByKey[key] = r.id;
          _blockedKeys.add(key);
        }
      });
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _rulesLoading = false);
    }
  }

  Future<void> _blacklistEntity({
    required String kind,
    required String entity,
    required String displayName,
  }) async {
    if (kind != "domain" && kind != "app") return;
    final value = kind == "domain" ? entity.toLowerCase() : entity;
    final key = _ruleKey(kind, value);

    if (_blockedKeys.contains(key)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Already blacklisted: $displayName")),
      );
      return;
    }

    try {
      final rule = await widget.client.upsertPrivacyRule(
        PrivacyRuleUpsert(kind: kind, value: value, action: "drop"),
      );
      if (!mounted) return;
      setState(() {
        _blockedKeys.add(key);
        _ruleIdByKey[key] = rule.id;
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          showCloseIcon: true,
          content: Text("Blacklisted: $displayName"),
          action: SnackBarAction(
            label: "Undo",
            onPressed: () async {
              final id = _ruleIdByKey[key];
              if (id == null) return;
              try {
                await widget.client.deletePrivacyRule(id);
                if (!mounted) return;
                setState(() {
                  _blockedKeys.remove(key);
                  _ruleIdByKey.remove(key);
                });
              } catch (_) {}
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Blacklist failed: $e")),
      );
    }
  }

  String? _subtitleForAppEntity(String appEntity) {
    if (!_coreStoreTitles || !_viewingToday()) return null;
    final title = _latestTitleByKey[_ruleKey("app", appEntity)];
    if (title == null || title.trim().isEmpty) return null;

    final app = displayEntity(appEntity).toLowerCase();
    final isBrowser = app == "chrome" ||
        app == "msedge" ||
        app == "edge" ||
        app == "brave" ||
        app == "vivaldi" ||
        app == "opera" ||
        app == "firefox";
    if (isBrowser) return null;

    final t = title.trim();
    if (t.contains("Visual Studio Code") || app == "code" || app == "vscode") {
      final ws = extractVscodeWorkspace(t);
      if (ws != null && ws.trim().isNotEmpty) return "Workspace: ${ws.trim()}";
    }
    return t;
  }

  String? _subtitleForDomainEntity(String domain) {
    if (!_coreStoreTitles || !_viewingToday()) return null;
    final title = _latestTitleByKey[_ruleKey("domain", domain.toLowerCase())];
    if (title == null || title.trim().isEmpty) return null;
    final t = normalizeWebTitle(domain, title);
    return t.isEmpty ? null : t;
  }

  _TopAgg _buildTopAgg() {
    final accSeconds = <String, int>{};
    final accHasAudio = <String, bool>{};
    final accKind = <String, String>{};
    final accEntity = <String, String>{};
    final accLabel = <String, String>{};
    final accSubtitle = <String, String?>{};

    var focusSeconds = 0;
    var audioSeconds = 0;

    for (final s in _segments) {
      final kind = s.kind;
      final entity = s.entity.trim();
      if (kind != "app" && kind != "domain") continue;
      if (entity.isEmpty) continue;
      if (s.seconds <= 0) continue;

      final isAudio = s.activity == "audio";
      if (isAudio) {
        audioSeconds += s.seconds;
      } else {
        focusSeconds += s.seconds;
      }

      String key;
      String label;
      String? subtitle;

      if (kind == "domain") {
        final rawTitle = (s.title ?? "").trim();
        final normTitle = _coreStoreTitles ? normalizeWebTitle(entity, rawTitle) : "";
        if (_coreStoreTitles && normTitle.isNotEmpty) {
          key = "domain|$entity|$normTitle";
          label = normTitle;
          subtitle = displayEntity(entity);
        } else {
          key = "domain|$entity";
          label = displayEntity(entity);
          subtitle = _subtitleForDomainEntity(entity);
        }
      } else {
        key = "app|$entity";
        label = displayEntity(entity);
        subtitle = _subtitleForAppEntity(entity);
      }

      accSeconds[key] = (accSeconds[key] ?? 0) + s.seconds;
      accHasAudio[key] = (accHasAudio[key] ?? false) || isAudio;
      accKind[key] = kind;
      accEntity[key] = entity;
      accLabel[key] = label;
      accSubtitle[key] = subtitle;
    }

    final items = <_StatItem>[];
    for (final key in accSeconds.keys) {
      items.add(
        _StatItem(
          kind: accKind[key] ?? "",
          entity: accEntity[key] ?? "",
          label: accLabel[key] ?? "",
          subtitle: accSubtitle[key],
          seconds: accSeconds[key] ?? 0,
          hasAudio: accHasAudio[key] ?? false,
        ),
      );
    }
    items.sort((a, b) => b.seconds.compareTo(a.seconds));
    return _TopAgg(focusSeconds: focusSeconds, audioSeconds: audioSeconds, items: items);
  }

  IconData _iconForAppLabel(String label) {
    final name = label.toLowerCase();
    if (name.contains("code") || name.contains("vscode")) return Icons.code;
    if (name.contains("chrome") ||
        name.contains("edge") ||
        name.contains("brave") ||
        name.contains("vivaldi") ||
        name.contains("opera") ||
        name.contains("firefox")) {
      return Icons.public;
    }
    if (name.contains("slack") || name.contains("discord") || name.contains("teams") || name.contains("telegram")) {
      return Icons.chat_bubble_outline;
    }
    if (name.contains("notion") || name.contains("obsidian") || name.contains("notes")) return Icons.note_alt_outlined;
    if (name.contains("excel") || name.contains("word") || name.contains("powerpoint")) return Icons.description_outlined;
    return Icons.apps;
  }

  bool _isBrowserLabel(String label) {
    final v = label.toLowerCase();
    return v == "chrome" ||
        v == "msedge" ||
        v == "edge" ||
        v == "brave" ||
        v == "vivaldi" ||
        v == "opera" ||
        v == "firefox";
  }

  IconData _iconForStatItem(_StatItem it) {
    if (it.kind == "domain") return Icons.public;
    if (it.kind == "app") return _iconForAppLabel(it.label);
    return Icons.category_outlined;
  }

  List<_StatItem> _applyTopFilter(List<_StatItem> items) {
    switch (_topFilter) {
      case _TopFilter.all:
        return items;
      case _TopFilter.apps:
        return items.where((it) => it.kind == "app").toList();
      case _TopFilter.web:
        return items.where((it) => it.kind == "domain").toList();
    }
  }

  Future<void> _setSnooze({required String blockId, required Duration duration}) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    _snoozeUntilMs = until;
    _snoozeBlockId = blockId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefSnoozeUntilMs, until);
      await prefs.setString(_prefSnoozeBlockId, blockId);
    } catch (_) {
      // best effort
    }
  }

  Future<void> _setSkipped(BlockSummary b, {required bool skipped}) async {
    try {
      final r = b.review;
      await widget.client.upsertReview(
        ReviewUpsert(
          blockId: b.id,
          skipped: skipped,
          skipReason: null,
          doing: r?.doing,
          output: r?.output,
          next: r?.next,
          tags: r?.tags ?? const [],
        ),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
          content: Text(skipped ? "Skipped this block" : "Restored this block"),
          action: SnackBarAction(
            label: "Undo",
            onPressed: () => _setSkipped(b, skipped: !skipped),
          ),
        ),
      );
      await refresh(silent: true, triggerReminder: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Action failed: $e")));
    }
  }

  Future<void> _openBlock(BlockSummary b) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlockDetailSheet(client: widget.client, block: b),
    );
    if (ok == true) {
      await refresh(silent: true, triggerReminder: false);
    }
  }

  Future<void> _openQuickReview(BlockSummary b) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickReviewSheet(client: widget.client, block: b),
    );
    if (ok == true) {
      await refresh(silent: true, triggerReminder: false);
    }
  }

  Future<void> _maybePromptDueBlock(BlockSummary b) async {
    if (_promptShowing) return;
    final snoozeUntil = _snoozeUntilMs;
    if (_snoozeBlockId == b.id && snoozeUntil != null) {
      if (DateTime.now().millisecondsSinceEpoch < snoozeUntil) return;
    }

    _promptShowing = true;
    try {
      final top = _blockTopLine(b);
      final title = "${formatHHMM(b.startTs)}–${formatHHMM(b.endTs)}";

      final action = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text("Time to review"),
          content: Text("$title\n\nTop: $top"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, "skip"),
              child: const Text("Skip"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, "pause15"),
              child: const Text("Pause 15m"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, "snooze10"),
              child: const Text("Snooze 10m"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, "review"),
              child: const Text("Quick review"),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (action == "review") {
        await _openQuickReview(b);
      } else if (action == "skip") {
        await _setSkipped(b, skipped: true);
      } else if (action == "pause15") {
        try {
          await widget.client.pauseTracking(minutes: 15);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(duration: Duration(seconds: 4), showCloseIcon: true, content: Text("Paused 15m")),
          );
          await refresh(silent: true, triggerReminder: false);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pause failed: $e")));
        }
      } else {
        // Treat dismiss as snooze to avoid nagging.
        await _setSnooze(blockId: b.id, duration: const Duration(minutes: 10));
      }
    } finally {
      _promptShowing = false;
    }
  }

  Future<void> _refreshNow({bool silent = false, bool kickBlocksOnChange = false}) async {
    if (_refreshingNow) return;
    _refreshingNow = true;
    try {
      final ev = await widget.client.events(limit: 500);
      final latestAnyId = ev.isEmpty ? null : ev.first.id;
      EventRecord? latestApp;
      EventRecord? latestTab;
      EventRecord? latestAudio;
      EventRecord? latestAudioStop;
      EventRecord? latestAppAudio;
      EventRecord? latestAppAudioStop;
      final latestTitles = <String, String>{};
      for (final e in ev) {
        if (latestApp == null && e.event == "app_active") latestApp = e;
        if (latestTab == null && e.event == "tab_active" && e.activity != "audio") latestTab = e;
        if (latestAudio == null && e.event == "tab_active" && e.activity == "audio") latestAudio = e;
        if (latestAudioStop == null && e.event == "tab_audio_stop") latestAudioStop = e;
        if (latestAppAudio == null && e.event == "app_audio") latestAppAudio = e;
        if (latestAppAudioStop == null && e.event == "app_audio_stop") latestAppAudioStop = e;

        final title = (e.title ?? "").trim();
        final entity = (e.entity ?? "").trim();
        if (title.isNotEmpty && entity.isNotEmpty) {
          if (e.event == "tab_active") {
            latestTitles.putIfAbsent(_ruleKey("domain", entity.toLowerCase()), () => title);
          } else if (e.event == "app_active") {
            latestTitles.putIfAbsent(_ruleKey("app", entity), () => title);
          }
        }

        if (latestApp != null &&
            latestTab != null &&
            latestAudio != null &&
            latestAudioStop != null &&
            latestAppAudio != null &&
            latestAppAudioStop != null) {
          break;
        }
      }
      if (!mounted) return;
      final now = DateTime.now();
      final anyChanged = latestAnyId != null && latestAnyId != _lastAnyEventId;
      final canAutoRefreshBlocks = kickBlocksOnChange &&
          anyChanged &&
          _viewingToday() &&
          !_refreshingBlocks &&
          _blocksUpdatedAt != null &&
          (_lastAutoBlocksRefreshAt == null ||
              now.difference(_lastAutoBlocksRefreshAt!) > const Duration(seconds: 10));
      setState(() {
        _latestAppEvent = latestApp;
        _latestTabEvent = latestTab;
        _latestAudioEvent = latestAudio;
        _latestAudioStopEvent = latestAudioStop;
        _latestAppAudioEvent = latestAppAudio;
        _latestAppAudioStopEvent = latestAppAudioStop;
        _latestTitleByKey
          ..clear()
          ..addAll(latestTitles);
        _nowUpdatedAt = now;
        _lastAnyEventId = latestAnyId;
        if (canAutoRefreshBlocks) _lastAutoBlocksRefreshAt = now;
      });

      if (canAutoRefreshBlocks) {
        unawaited(_refreshBlocks(silent: true, triggerReminder: false));
      }
    } catch (_) {
      // best effort (Now card shouldn't hard-fail)
    } finally {
      _refreshingNow = false;
    }
  }

  Future<void> _refreshBlocks({bool silent = false, bool triggerReminder = false}) async {
    if (_refreshingBlocks) return;
    _refreshingBlocks = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _loadCoreSettings();

      if (!silent) {
        final ok = await widget.client.health();
        if (!ok) throw Exception("health_failed");
      }

      final date = _dateLocal(_day);
      final tzOffsetMinutes = _tzOffsetMinutesForDay(_day);

      final blocks = await widget.client.blocksToday(
        date: date,
        tzOffsetMinutes: tzOffsetMinutes,
      );
      final segments = await widget.client.timelineDay(date: date, tzOffsetMinutes: tzOffsetMinutes);
      final viewingToday = _viewingToday();
      final due = viewingToday ? _findDueBlock(blocks) : null;
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _blocks = blocks;
        _dueBlock = due;
        _blocksUpdatedAt = DateTime.now();
      });
      if (triggerReminder && viewingToday && due != null) {
        await _maybePromptDueBlock(due);
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (!silent && mounted) {
        setState(() {
          _loading = false;
        });
      }
      _refreshingBlocks = false;
    }
  }

  Future<void> refresh({bool silent = false, bool triggerReminder = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final viewingToday = _viewingToday();
    if (viewingToday) {
      await _refreshNow(silent: true);
    }
    await _refreshBlocks(silent: silent, triggerReminder: triggerReminder && viewingToday);
  }

  String _ageText(String rfc3339) {
    try {
      final ts = DateTime.parse(rfc3339).toLocal();
      final d = DateTime.now().difference(ts);
      if (d.inSeconds < 60) return "${d.inSeconds}s ago";
      if (d.inMinutes < 60) return "${d.inMinutes}m ago";
      if (d.inHours < 24) return "${d.inHours}h ago";
      return "${d.inDays}d ago";
    } catch (_) {
      return "";
    }
  }

  Future<void> _openReview({String query = ""}) async {
    final cb = widget.onOpenReviewQuery;
    if (cb != null) {
      await cb(query, _normalizeDay(_day));
    } else {
      widget.onOpenReview();
    }
  }

  Future<void> _openReviewForEntity({required String kind, required String? entity, String? label}) async {
    final e = (entity ?? "").trim();
    if (e.isEmpty) return;
    String query;
    if (kind == "domain") {
      final l = (label ?? "").trim();
      final looksLikeTitle = _coreStoreTitles && l.isNotEmpty && l.toLowerCase() != e.toLowerCase();
      query = looksLikeTitle ? l : e;
    } else {
      var l = (label ?? displayEntity(e)).trim();
      if (l.toLowerCase().startsWith("workspace:")) {
        l = l.substring("workspace:".length).trim();
      }
      query = l.isEmpty ? displayEntity(e) : l;
    }
    await _openReview(query: query);
  }

  String _updatedAge(DateTime? t) {
    if (t == null) return "—";
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 10) return "just now";
    if (d.inMinutes < 1) return "${d.inSeconds}s ago";
    if (d.inHours < 1) return "${d.inMinutes}m ago";
    return "${d.inHours}h ago";
  }

  int _countReviewedBlocks() {
    var c = 0;
    for (final b in _blocks) {
      if (_isReviewed(b)) c += 1;
    }
    return c;
  }

  int _countFocusSwitches() {
    String? lastKey;
    var switches = 0;
    for (final s in _segments) {
      if (s.activity == "audio") continue;
      final kind = s.kind;
      final entity = s.entity.trim();
      if (entity.isEmpty) continue;
      if (kind != "app" && kind != "domain") continue;

      String key;
      if (kind == "domain") {
        final rawTitle = (s.title ?? "").trim();
        final normTitle = _coreStoreTitles ? normalizeWebTitle(entity, rawTitle) : "";
        key = (_coreStoreTitles && normTitle.isNotEmpty) ? "domain|$entity|$normTitle" : "domain|$entity";
      } else {
        key = "app|$entity";
      }

      if (lastKey != null && key != lastKey) {
        switches += 1;
      }
      lastKey = key;
    }
    return switches;
  }

  int _longestFocusStreakSeconds() {
    var max = 0;
    for (final s in _segments) {
      if (s.activity == "audio") continue;
      if (s.seconds > max) max = s.seconds;
    }
    return max;
  }

  String _privacyLevelLabel() {
    if (!_coreStoreTitles && !_coreStoreExePath) return "L1";
    if (_coreStoreTitles && !_coreStoreExePath) return "L2";
    return "L3";
  }

  Widget _overviewCard(BuildContext context, _TopAgg topAgg) {
    final dayLabel = _dateLocal(_day);
    final viewingToday = _viewingToday();
    final focusSeconds = topAgg.focusSeconds;
    final audioSeconds = topAgg.audioSeconds;
    final trackedSeconds = focusSeconds + audioSeconds;
    final focusSwitches = _countFocusSwitches();
    final longestStreak = _longestFocusStreakSeconds();

    final totalBlocks = _blocks.length;
    final reviewedBlocks = _countReviewedBlocks();
    final pendingBlocks = (totalBlocks - reviewedBlocks).clamp(0, 99999);
    final progress = totalBlocks <= 0 ? 0.0 : (reviewedBlocks / totalBlocks).clamp(0.0, 1.0);

    final due = _dueBlock;
    final dueRange = due == null ? null : "${formatHHMM(due.startTs)}–${formatHHMM(due.endTs)}";
    final dueTop = due == null ? null : _blockTopLine(due);
    final dueAudioTop = due == null ? null : _blockAudioTop(due);

    final scheme = Theme.of(context).colorScheme;

    Widget metric({
      required IconData icon,
      required String label,
      required String value,
      String? tooltip,
      VoidCallback? onTap,
    }) {
      final tile = InkWell(
        borderRadius: BorderRadius.circular(RecorderTokens.radiusM),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RecorderTokens.space3,
            vertical: RecorderTokens.space2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(RecorderTokens.radiusM),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: RecorderTokens.space2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(value, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ],
          ),
        ),
      );

      if (tooltip == null || tooltip.trim().isEmpty) return tile;
      return Tooltip(message: tooltip, child: tile);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(viewingToday ? "Today overview" : "Day overview", style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: "Previous day",
                  onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(dayLabel),
                ),
                IconButton(
                  tooltip: "Next day",
                  onPressed: _canGoNextDay() ? () => _setDay(_day.add(const Duration(days: 1))) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: RecorderTokens.space2),
                Text(
                  "Updated ${_updatedAge(_blocksUpdatedAt)}",
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: RecorderTokens.space3),
            Wrap(
              spacing: RecorderTokens.space2,
              runSpacing: RecorderTokens.space2,
              children: [
                metric(
                  icon: Icons.timer_outlined,
                  label: "Tracked",
                  value: trackedSeconds <= 0 ? "—" : formatDuration(trackedSeconds),
                  tooltip: "Focus + background audio",
                ),
                metric(
                  icon: Icons.apps_outlined,
                  label: "Focus",
                  value: focusSeconds <= 0 ? "—" : formatDuration(focusSeconds),
                ),
                metric(
                  icon: Icons.swap_horiz,
                  label: "Switches",
                  value: focusSwitches.toString(),
                  tooltip: "Focus context switches today",
                ),
                metric(
                  icon: Icons.center_focus_strong_outlined,
                  label: "Deep focus",
                  value: longestStreak <= 0 ? "—" : formatDuration(longestStreak),
                  tooltip: "Longest continuous focus segment",
                ),
                metric(
                  icon: Icons.list_alt_outlined,
                  label: "Blocks",
                  value: totalBlocks <= 0 ? "—" : "$reviewedBlocks/$totalBlocks",
                  tooltip: pendingBlocks <= 0 ? "All reviewed" : "$pendingBlocks pending",
                  onTap: () {
                    _openReview();
                  },
                ),
                metric(
                  icon: Icons.lock_outline,
                  label: "Privacy",
                  value: _privacyLevelLabel(),
                  tooltip: _coreStoreTitles ? "Titles stored" : "Titles off",
                  onTap: widget.onOpenSettings,
                ),
              ],
            ),
            if (totalBlocks > 0) ...[
              const SizedBox(height: RecorderTokens.space3),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: RecorderTokens.space2),
                  Text("$pendingBlocks pending", style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ],
            const SizedBox(height: RecorderTokens.space3),
            if (due != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Review due: $dueRange",
                      style: Theme.of(context).textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openQuickReview(due),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text("Quick review"),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    _openReview();
                  },
                  icon: const Icon(Icons.list_alt_outlined, size: 18),
                  label: const Text("Review blocks"),
                ),
              ),
            if (dueTop != null && dueTop.trim().isNotEmpty) ...[
              const SizedBox(height: RecorderTokens.space2),
              Text(
                "Top: $dueTop",
                style: Theme.of(context).textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (dueAudioTop != null && dueAudioTop.seconds > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.headphones, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "${dueAudioTop.label} ${formatDuration(dueAudioTop.seconds)}",
                      style: Theme.of(context).textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reviewDueCard(BuildContext context, BlockSummary due) {
    final top = _blockTopLine(due);
    final audioTop = _blockAudioTop(due);
    final title = "${formatHHMM(due.startTs)}–${formatHHMM(due.endTs)}";
    final audioSuffix = audioTop == null ? "" : " · 🎧 ${audioTop.label} ${formatDuration(audioTop.seconds)}";
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space2),
        child: ListTile(
          isThreeLine: true,
          minVerticalPadding: RecorderTokens.space2,
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text("Review due"),
          subtitle: Text(
            "$title\nTop: $top$audioSuffix",
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openBlock(due),
          trailing: FilledButton(
            onPressed: () => _openQuickReview(due),
            child: const Text("Quick review"),
          ),
        ),
      ),
    );
  }

  Widget _nowUnavailableCard(BuildContext context) {
    final dayLabel = _dateLocal(_day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Now", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RecorderTokens.space2),
            Text(
              "You’re viewing $dayLabel.\nNow shows live activity for Today only.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: RecorderTokens.space2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _setDay(DateTime.now()),
                child: const Text("Go to Today"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowCard(BuildContext context) {
    bool isFresh(EventRecord e, Duration maxAge) {
      try {
        final t = DateTime.parse(e.ts).toLocal();
        return DateTime.now().difference(t) <= maxAge;
      } catch (_) {
        return false;
      }
    }

    const focusFreshness = Duration(minutes: 3);
    final app = (_latestAppEvent != null && isFresh(_latestAppEvent!, focusFreshness)) ? _latestAppEvent : null;
    final tab = (_latestTabEvent != null && isFresh(_latestTabEvent!, focusFreshness)) ? _latestTabEvent : null;
    final audio = _latestAudioEvent;
    final audioStop = _latestAudioStopEvent;
    final appAudio = _latestAppAudioEvent;
    final appAudioStop = _latestAppAudioStopEvent;

    bool showAudioNow() {
      if (audio == null) return false;

      // If we have an explicit stop marker that is newer than the last audio event, treat audio as stopped.
      if (audioStop != null) {
        try {
          final a = DateTime.parse(audio.ts).toUtc();
          final s = DateTime.parse(audioStop.ts).toUtc();
          if (!s.isBefore(a)) return false;
        } catch (_) {
          // ignore
        }
      }

      // Fallback: hide "now" audio when the last audio event is stale.
      try {
        final a = DateTime.parse(audio.ts).toLocal();
        if (DateTime.now().difference(a) > const Duration(seconds: 120)) return false;
      } catch (_) {
        // ignore
      }

      return true;
    }

    final showAudio = showAudioNow();

    bool showAppAudioNow() {
      if (appAudio == null) return false;

      if (appAudioStop != null) {
        try {
          final a = DateTime.parse(appAudio.ts).toUtc();
          final s = DateTime.parse(appAudioStop.ts).toUtc();
          if (!s.isBefore(a)) return false;
        } catch (_) {
          // ignore
        }
      }

      try {
        final a = DateTime.parse(appAudio.ts).toLocal();
        if (DateTime.now().difference(a) > const Duration(seconds: 120)) return false;
      } catch (_) {
        // ignore
      }

      return true;
    }

    final showAppAudio = showAppAudioNow();
    final appLabelLc = app == null ? "" : displayEntity(app.entity).toLowerCase();
    final appSaysBrowserFocused = app != null &&
        (appLabelLc == "chrome" ||
            appLabelLc == "msedge" ||
            appLabelLc == "edge" ||
            appLabelLc == "brave" ||
            appLabelLc == "vivaldi" ||
            appLabelLc == "opera" ||
            appLabelLc == "firefox");
    final browserFocused = appSaysBrowserFocused || (app == null && tab != null);

    final usingTab = browserFocused ? tab : (showAudio ? audio : null);
    final usingTabIcon = browserFocused ? Icons.public : Icons.headphones;

    if (app == null && usingTab == null && !(showAppAudio && appAudio != null)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(RecorderTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Now", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: RecorderTokens.space2),
              Text(
                "No recent activity yet.\nTip: switch apps or tabs to generate events.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: RecorderTokens.space2),
              Text(
                "We record the focused app + “using tab” (focused tab, or an audible tab while the browser is in background) + background app audio (e.g. music player).",
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      );
    }

    Widget row({
      required IconData icon,
      required String label,
      required EventRecord e,
      required VoidCallback onTap,
    }) {
      final title = displayEntity(e.entity);
      final when = _ageText(e.ts);
      final detail = (e.title ?? "").trim();
      return ListTile(
        isThreeLine: true,
        minVerticalPadding: RecorderTokens.space2,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 18),
        title: Text(
          "$label · $title",
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          detail.isEmpty ? when : "$when · $detail",
          style: Theme.of(context).textTheme.labelMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      );
    }

    final hideAppAudio = app != null && appAudio != null && displayEntity(app.entity) == displayEntity(appAudio.entity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text("Now", style: Theme.of(context).textTheme.titleMedium)),
                Text(
                  "Updated ${_updatedAge(_nowUpdatedAt)}",
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            if (app != null)
              row(
                icon: Icons.apps,
                label: "Focus app",
                e: app,
                onTap: () => _openReviewForEntity(kind: "app", entity: app.entity, label: displayEntity(app.entity)),
              ),
            if (usingTab != null)
              row(
                icon: usingTabIcon,
                label: "Using tab",
                e: usingTab,
                onTap: () {
                  final domain = (usingTab.entity ?? "").trim();
                  final rawTitle = (usingTab.title ?? "").trim();
                  final title = (_coreStoreTitles && domain.isNotEmpty) ? normalizeWebTitle(domain, rawTitle) : rawTitle;
                  _openReviewForEntity(kind: "domain", entity: usingTab.entity, label: title.isEmpty ? null : title);
                },
              ),
            if (showAppAudio && !hideAppAudio)
              row(
                icon: Icons.headphones,
                label: "Background audio",
                e: appAudio!,
                onTap: () => _openReviewForEntity(kind: "app", entity: appAudio.entity, label: displayEntity(appAudio.entity)),
              ),
          ],
        ),
      ),
    );
  }

  int _minuteOfDay(DateTime t, DateTime dayStart) {
    return t.difference(dayStart).inMinutes.clamp(0, 1440);
  }

  String _hhmmFromMinute(int minute) {
    final h = (minute ~/ 60).clamp(0, 24).toString().padLeft(2, "0");
    final m = (minute % 60).clamp(0, 59).toString().padLeft(2, "0");
    return "$h:$m";
  }

  List<DayTimelineLane> _buildTimelineLanesAll() {
    final dayStart = DateTime(_day.year, _day.month, _day.day);

    final lanes = <String, _LaneAcc>{};

    Iterable<TimelineSegment> segs;
    switch (_topFilter) {
      case _TopFilter.apps:
        segs = _segments.where((s) => s.kind == "app");
        break;
      case _TopFilter.web:
        segs = _segments.where((s) => s.kind == "domain");
        break;
      case _TopFilter.all:
        segs = _segments;
        break;
    }

    for (final s in segs) {
      final kind = s.kind;
      final entity = s.entity.trim();
      if (kind != "app" && kind != "domain") continue;
      if (entity.isEmpty) continue;

      DateTime start;
      DateTime end;
      try {
        start = DateTime.parse(s.startTs).toLocal();
        end = DateTime.parse(s.endTs).toLocal();
      } catch (_) {
        continue;
      }
      final startMin = _minuteOfDay(start, dayStart);
      final endMin = _minuteOfDay(end, dayStart);
      if (endMin <= startMin) continue;

      String laneKey;
      String label;
      String? subtitle;
      IconData icon;

      if (kind == "domain") {
        final domain = entity.toLowerCase();
        final rawTitle = (s.title ?? "").trim();
        final normTitle = _coreStoreTitles ? normalizeWebTitle(domain, rawTitle) : "";
        if (_coreStoreTitles && normTitle.isNotEmpty) {
          laneKey = "domain|$domain|$normTitle";
          label = normTitle;
          subtitle = displayEntity(domain);
        } else {
          laneKey = "domain|$domain";
          label = displayEntity(domain);
          subtitle = null;
        }
        icon = Icons.public;
      } else {
        label = displayEntity(entity);
        icon = _iconForAppLabel(label);

        final t = (s.title ?? "").trim();
        final labelLc = label.toLowerCase();
        final isVscode = labelLc == "code" || labelLc == "vscode" || t.contains("Visual Studio Code");
        if (_coreStoreTitles && isVscode && t.isNotEmpty) {
          final ws = extractVscodeWorkspace(t);
          if (ws != null && ws.trim().isNotEmpty) {
            final w = ws.trim();
            laneKey = "app|$entity|$w";
            subtitle = "Workspace: $w";
          } else {
            laneKey = "app|$entity";
            subtitle = null;
          }
        } else {
          laneKey = "app|$entity";
          subtitle = null;
        }
      }

      final lane = lanes.putIfAbsent(
        laneKey,
        () => _LaneAcc(
          kind: kind,
          entity: kind == "domain" ? entity.toLowerCase() : entity,
          label: label,
          subtitle: subtitle,
          icon: icon,
        ),
      );
      lane.totalSeconds += s.seconds;
      if (startMin < lane.firstStartMinute) lane.firstStartMinute = startMin;
      final audio = s.activity == "audio";
      final time = "${_hhmmFromMinute(startMin)}–${_hhmmFromMinute(endMin)}";
      final tipHead = subtitle == null ? label : "$label\n$subtitle";
      lane.bars.add(
        DayTimelineBar(
          startMinute: startMin,
          endMinute: endMin,
          audio: audio,
          tooltip: audio ? "$tipHead\n$time · audio" : "$tipHead\n$time",
        ),
      );
    }

    final out = lanes.values.toList();
    out.sort((a, b) {
      if (_timelineSortByTime) {
        final byTime = a.firstStartMinute.compareTo(b.firstStartMinute);
        if (byTime != 0) return byTime;
      }
      final byTotal = b.totalSeconds.compareTo(a.totalSeconds);
      if (byTotal != 0) return byTotal;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out
        .map(
          (l) => DayTimelineLane(
            kind: l.kind,
            entity: l.entity,
            label: l.label,
            subtitle: l.subtitle,
            icon: l.icon,
            totalSeconds: l.totalSeconds,
            bars: l.bars,
          ),
        )
        .toList();
  }

  List<_RangeStatItem> _aggregateSegmentsForRange({
    required DateTime startUtc,
    required DateTime endUtc,
    required bool audio,
  }) {
    if (!endUtc.isAfter(startUtc)) return const [];

    final secByKey = <String, int>{};
    final kindByKey = <String, String>{};
    final entityByKey = <String, String>{};
    final labelByKey = <String, String>{};
    final subtitleByKey = <String, String?>{};

    for (final s in _segments) {
      final isAudio = s.activity == "audio";
      if (audio != isAudio) continue;

      final kind = s.kind;
      if (kind != "app" && kind != "domain") continue;

      final rawEntity = s.entity.trim();
      if (rawEntity.isEmpty) continue;

      DateTime segStartUtc;
      DateTime segEndUtc;
      try {
        segStartUtc = DateTime.parse(s.startTs).toUtc();
        segEndUtc = DateTime.parse(s.endTs).toUtc();
      } catch (_) {
        continue;
      }
      if (!segEndUtc.isAfter(segStartUtc)) continue;

      if (!segEndUtc.isAfter(startUtc) || !endUtc.isAfter(segStartUtc)) continue;
      final overlapStart = segStartUtc.isAfter(startUtc) ? segStartUtc : startUtc;
      final overlapEnd = segEndUtc.isBefore(endUtc) ? segEndUtc : endUtc;
      final seconds = overlapEnd.difference(overlapStart).inSeconds;
      if (seconds <= 0) continue;

      String key;
      String entity;
      String label;
      String? subtitle;

      if (kind == "domain") {
        final domain = rawEntity.toLowerCase();
        final rawTitle = (s.title ?? "").trim();
        final normTitle = _coreStoreTitles ? normalizeWebTitle(domain, rawTitle) : "";
        if (_coreStoreTitles && normTitle.isNotEmpty) {
          key = "domain|$domain|$normTitle";
          entity = domain;
          label = normTitle;
          subtitle = displayEntity(domain);
        } else {
          key = "domain|$domain";
          entity = domain;
          label = displayEntity(domain);
          subtitle = null;
        }
      } else {
        final appEntity = rawEntity;
        final appLabel = displayEntity(appEntity);
        final title = (s.title ?? "").trim();

        final labelLc = appLabel.toLowerCase();
        final isVscode = labelLc == "code" || labelLc == "vscode" || title.contains("Visual Studio Code");
        final ws = (_coreStoreTitles && isVscode && title.isNotEmpty) ? extractVscodeWorkspace(title) : null;
        if (ws != null && ws.trim().isNotEmpty) {
          final w = ws.trim();
          key = "app|$appEntity|$w";
          entity = appEntity;
          label = appLabel;
          subtitle = "Workspace: $w";
        } else {
          key = "app|$appEntity";
          entity = appEntity;
          label = appLabel;
          subtitle = null;
          if (_coreStoreTitles && title.isNotEmpty && !_isBrowserLabel(appLabel)) {
            subtitle = title;
          }
        }
      }

      secByKey[key] = (secByKey[key] ?? 0) + seconds;
      kindByKey[key] = kind;
      entityByKey[key] = entity;
      labelByKey[key] = label;
      subtitleByKey[key] = (subtitleByKey[key] == null || subtitleByKey[key]!.trim().isEmpty) ? subtitle : subtitleByKey[key];
    }

    final out = <_RangeStatItem>[];
    for (final k in secByKey.keys) {
      out.add(
        _RangeStatItem(
          kind: kindByKey[k] ?? "",
          entity: entityByKey[k] ?? "",
          label: labelByKey[k] ?? "",
          subtitle: subtitleByKey[k],
          seconds: secByKey[k] ?? 0,
          audio: audio,
        ),
      );
    }
    out.sort((a, b) => b.seconds.compareTo(a.seconds));
    if (out.length > 6) return out.take(6).toList();
    return out;
  }

  List<_RangeStatItem> _blockRangeItems(BlockSummary b, {required bool audio}) {
    try {
      final startUtc = DateTime.parse(b.startTs).toUtc();
      final endUtc = DateTime.parse(b.endTs).toUtc();
      return _aggregateSegmentsForRange(startUtc: startUtc, endUtc: endUtc, audio: audio);
    } catch (_) {
      return const [];
    }
  }

  String _blockTopLine(BlockSummary b) {
    final focus = _blockRangeItems(b, audio: false);
    if (focus.isEmpty) {
      return b.topItems.take(3).map((it) => "${displayTopItemName(it)} ${formatDuration(it.seconds)}").join(" · ");
    }
    return focus
        .take(3)
        .map((it) {
          final sub = (it.subtitle ?? "").trim();
          final preferWorkspace = it.kind == "app" && sub.toLowerCase().startsWith("workspace:");
          final name = preferWorkspace ? sub : it.label;
          return "${name.trim().isEmpty ? "(unknown)" : name.trim()} ${formatDuration(it.seconds)}";
        })
        .join(" · ");
  }

  _RangeStatItem? _blockAudioTop(BlockSummary b) {
    final audio = _blockRangeItems(b, audio: true);
    if (audio.isEmpty) return null;
    return audio.first;
  }

  String _hhmm(DateTime t) => "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}";

  Widget _flowCard(BuildContext context) {
    final items = <_FlowItem>[];

    Iterable<TimelineSegment> segs;
    switch (_topFilter) {
      case _TopFilter.apps:
        segs = _segments.where((s) => s.kind == "app" && s.activity != "audio");
        break;
      case _TopFilter.web:
        segs = _segments.where((s) => s.kind == "domain" && s.activity != "audio");
        break;
      case _TopFilter.all:
        segs = _segments.where((s) => s.activity != "audio");
        break;
    }

    for (final s in segs) {
      final kind = s.kind;
      if (kind != "app" && kind != "domain") continue;
      final rawEntity = s.entity.trim();
      if (rawEntity.isEmpty) continue;

      DateTime start;
      DateTime end;
      try {
        start = DateTime.parse(s.startTs).toLocal();
        end = DateTime.parse(s.endTs).toLocal();
      } catch (_) {
        continue;
      }
      if (!end.isAfter(start)) continue;

      String entity;
      String label;
      String? subtitle;
      IconData icon;

      if (kind == "domain") {
        final domain = rawEntity.toLowerCase();
        final rawTitle = (s.title ?? "").trim();
        final normTitle = _coreStoreTitles ? normalizeWebTitle(domain, rawTitle) : "";
        if (_coreStoreTitles && normTitle.isNotEmpty) {
          entity = domain;
          label = normTitle;
          subtitle = displayEntity(domain);
        } else {
          entity = domain;
          label = displayEntity(domain);
          subtitle = null;
        }
        icon = Icons.public;
      } else {
        entity = rawEntity;
        label = displayEntity(entity);
        icon = _iconForAppLabel(label);
        subtitle = null;

        if (_coreStoreTitles) {
          final t = (s.title ?? "").trim();
          if (t.isNotEmpty && !_isBrowserLabel(label)) {
            final labelLc = label.toLowerCase();
            final isVscode = labelLc == "code" || labelLc == "vscode" || t.contains("Visual Studio Code");
            if (isVscode) {
              final ws = extractVscodeWorkspace(t);
              subtitle = (ws != null && ws.trim().isNotEmpty) ? "Workspace: ${ws.trim()}" : t;
            } else {
              subtitle = t;
            }
          }
        }
      }

      items.add(
        _FlowItem(
          kind: kind,
          entity: entity,
          label: label,
          subtitle: subtitle,
          start: start,
          end: end,
          seconds: s.seconds,
          icon: icon,
        ),
      );
    }

    final show = items.length <= 10 ? items : items.sublist(items.length - 10);
    final latestFirst = show.reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Flow", style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  "Updated ${_updatedAge(_blocksUpdatedAt)}",
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: RecorderTokens.space2),
            if (latestFirst.isEmpty)
              Text(
                "No focus activity yet.\nTip: switch apps or tabs to generate events.",
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...latestFirst.map((it) {
                final sub = (it.subtitle ?? "").trim();
                final meta = "${_hhmm(it.start)}–${_hhmm(it.end)} · ${formatDuration(it.seconds)}";
                final subtitleText = sub.isEmpty ? meta : "$meta\n$sub";
                return ListTile(
                  isThreeLine: true,
                  minVerticalPadding: RecorderTokens.space2,
                  contentPadding: EdgeInsets.zero,
                  leading: EntityAvatar(
                    kind: it.kind,
                    entity: it.entity,
                    label: it.label,
                    icon: it.kind == "app" ? it.icon : null,
                  ),
                  title: Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  subtitle: Text(
                    subtitleText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  onTap: () {
                    final preferWorkspace = it.kind == "app" && sub.toLowerCase().startsWith("workspace:");
                    final label = preferWorkspace ? sub : it.label;
                    _openReviewForEntity(kind: it.kind, entity: it.entity, label: label);
                  },
                );
              }),
            if (!_coreStoreTitles) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Titles are off (L1). Enable L2 in Settings to see page/workspace names.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (widget.onOpenSettings != null)
                    TextButton(
                      onPressed: widget.onOpenSettings,
                      child: const Text("Settings"),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timelineCard(BuildContext context) {
    final all = _buildTimelineLanesAll();
    final hasMore = all.length > 12;
    final lanes = _timelineShowAll ? all : all.take(12).toList();
    final viewingToday = _viewingToday();
    final showWeb = _topFilter != _TopFilter.apps;
    final hasWebSeg = _segments.any((s) => s.kind == "domain");
    final hasWebTitleSeg = _segments.any((s) => s.kind == "domain" && (s.title ?? "").trim().isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Timeline", style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  "Updated ${_updatedAge(_blocksUpdatedAt)}",
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(width: RecorderTokens.space2),
                TextButton.icon(
                  onPressed: () => setState(() => _timelineSortByTime = !_timelineSortByTime),
                  icon: Icon(_timelineSortByTime ? Icons.schedule : Icons.bar_chart, size: 18),
                  label: Text(_timelineSortByTime ? "By time" : "By total"),
                ),
                if (hasMore)
                  TextButton.icon(
                    onPressed: () => setState(() => _timelineShowAll = !_timelineShowAll),
                    icon: Icon(_timelineShowAll ? Icons.expand_less : Icons.expand_more, size: 18),
                    label: Text(_timelineShowAll ? "Top 12" : "Show all"),
                  ),
              ],
            ),
            const SizedBox(height: RecorderTokens.space2),
            DayTimeline(
              lanes: lanes,
              showNowIndicator: _viewingToday(),
              onLaneTap: (lane) {
                final subtitle = (lane.subtitle ?? "").trim();
                final preferWorkspace = lane.kind == "app" && subtitle.toLowerCase().startsWith("workspace:");
                final label = preferWorkspace ? subtitle : lane.label;
                _openReviewForEntity(kind: lane.kind, entity: lane.entity, label: label);
              },
            ),
            if (lanes.isNotEmpty) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Tip: tap a lane to filter blocks in Review.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (!_coreStoreTitles) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Titles are off (L1). Enable L2 in Settings to see page/workspace names.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (widget.onOpenSettings != null)
                    TextButton(
                      onPressed: widget.onOpenSettings,
                      child: const Text("Settings"),
                    ),
                ],
              ),
            ] else if (viewingToday && showWeb && hasWebSeg && !hasWebTitleSeg) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Tab titles not received yet. Turn on “Send tab title”, then reload the extension.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _todayTopCard(BuildContext context, _TopAgg topAgg) {
    final focusSeconds = topAgg.focusSeconds;
    final items = _applyTopFilter(topAgg.items);
    final displayItems = items.take(10).toList();
    final maxSeconds = displayItems.fold<int>(0, (m, it) => it.seconds > m ? it.seconds : m);
    final viewingToday = _viewingToday();
    final hasWebSeg = _segments.any((s) => s.kind == "domain");
    final hasWebTitleSeg = _segments.any((s) => s.kind == "domain" && (s.title ?? "").trim().isNotEmpty);

    Widget filters() {
      return Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_TopFilter>(
            segments: const [
              ButtonSegment(value: _TopFilter.all, label: Text("All")),
              ButtonSegment(value: _TopFilter.apps, label: Text("Apps")),
              ButtonSegment(value: _TopFilter.web, label: Text("Web")),
            ],
            selected: {_topFilter},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _topFilter = s.first),
          ),
        ),
      );
    }

    Widget list() {
      if (displayItems.isEmpty) {
        return Text(
          "No activity yet.\nTip: switch apps or tabs to generate events.",
          style: Theme.of(context).textTheme.bodyMedium,
        );
      }

      return Column(
        children: [
          for (final it in displayItems)
            Padding(
              padding: const EdgeInsets.only(bottom: RecorderTokens.space3),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(RecorderTokens.radiusM),
                  onTap: () {
                    final subtitle = (it.subtitle ?? "").trim();
                    final preferWorkspace = it.kind == "app" && subtitle.toLowerCase().startsWith("workspace:");
                    final label = preferWorkspace ? subtitle : it.label;
                    _openReviewForEntity(kind: it.kind, entity: it.entity, label: label);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(RecorderTokens.space2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            EntityAvatar(
                              kind: it.kind,
                              entity: it.entity,
                              label: it.label,
                              icon: it.kind == "app" ? _iconForStatItem(it) : null,
                            ),
                            const SizedBox(width: RecorderTokens.space2),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final subtitle = it.subtitle;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        it.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                      if (subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.labelMedium,
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: RecorderTokens.space2),
                            Text(formatDuration(it.seconds), style: Theme.of(context).textTheme.labelMedium),
                            if (it.hasAudio) ...[
                              const SizedBox(width: RecorderTokens.space1),
                              Icon(Icons.headphones, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ],
                            if (it.kind == "domain" || it.kind == "app") ...[
                              const SizedBox(width: RecorderTokens.space1),
                              IconButton(
                                onPressed: _isBlockedEntity(kind: it.kind, entity: it.entity) || _rulesLoading
                                    ? null
                                    : () => _blacklistEntity(
                                          kind: it.kind,
                                          entity: it.entity,
                                          displayName: it.kind == "domain" ? it.entity : it.label,
                                        ),
                                tooltip: _isBlockedEntity(kind: it.kind, entity: it.entity)
                                    ? "Blacklisted"
                                    : (it.kind == "domain" ? "Blacklist domain" : "Blacklist app"),
                                icon: Icon(
                                  _isBlockedEntity(kind: it.kind, entity: it.entity) ? Icons.block : Icons.block_outlined,
                                ),
                              ),
                            ],
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: maxSeconds <= 0 ? 0.0 : (it.seconds / maxSeconds).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Today Top", style: Theme.of(context).textTheme.titleMedium),
                ),
                if (focusSeconds > 0)
                  Text(formatDuration(focusSeconds), style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: RecorderTokens.space2),
            filters(),
            const SizedBox(height: RecorderTokens.space3),
            list(),
            if (displayItems.isNotEmpty) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Tip: tap an item to filter blocks in Review.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (!_coreStoreTitles) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Titles are off (L1). Enable “Store window/tab titles (L2)” in Settings to see page/workspace names.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (widget.onOpenSettings != null)
                    TextButton(
                      onPressed: widget.onOpenSettings,
                      child: const Text("Settings"),
                    ),
                ],
              ),
            ] else if (viewingToday && hasWebSeg && !hasWebTitleSeg) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "Titles enabled, but tab titles are not coming through yet. Turn on “Send tab title”, then reload the extension.",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RecorderTokens.space2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _openReview();
                },
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text("Review blocks"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(serverUrl: widget.serverUrl, error: _error!, onRetry: refresh);
    }

    final viewingToday = _viewingToday();
    final due = _dueBlock;
    final topAgg = _buildTopAgg();
    final showEmpty = topAgg.focusSeconds <= 0 && topAgg.audioSeconds <= 0;

    final isWide = MediaQuery.of(context).size.width >= 1100;

    return RefreshIndicator(
      onRefresh: () => refresh(triggerReminder: viewingToday),
      child: isWide
          ? ListView(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _overviewCard(context, topAgg),
                          const SizedBox(height: RecorderTokens.space3),
                          _todayTopCard(context, topAgg),
                        ],
                      ),
                    ),
                    const SizedBox(width: RecorderTokens.space3),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          if (due != null) ...[
                            _reviewDueCard(context, due),
                            const SizedBox(height: RecorderTokens.space3),
                          ],
                          viewingToday ? _nowCard(context) : _nowUnavailableCard(context),
                          if (!showEmpty) ...[
                            const SizedBox(height: RecorderTokens.space3),
                            _flowCard(context),
                          ] else ...[
                            const SizedBox(height: RecorderTokens.space3),
                            _EmptyState(
                              dayLabel: _dateLocal(_day),
                              serverUrl: widget.serverUrl,
                              onRefresh: () => refresh(triggerReminder: viewingToday),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RecorderTokens.space3),
                _timelineCard(context),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              itemCount: 1 + 1 + 1 + 1 + (due != null ? 1 : 0) + 1 + (showEmpty ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: RecorderTokens.space3),
              itemBuilder: (context, i) {
                var idx = 0;
                if (i == idx) return _overviewCard(context, topAgg);
                idx += 1;
                if (i == idx) return _todayTopCard(context, topAgg);
                idx += 1;
                if (i == idx) return _flowCard(context);
                idx += 1;
                if (i == idx) return _timelineCard(context);
                idx += 1;
                if (due != null) {
                  if (i == idx) return _reviewDueCard(context, due);
                  idx += 1;
                }
                if (i == idx) return viewingToday ? _nowCard(context) : _nowUnavailableCard(context);
                idx += 1;
                return _EmptyState(
                  dayLabel: _dateLocal(_day),
                  serverUrl: widget.serverUrl,
                  onRefresh: () => refresh(triggerReminder: viewingToday),
                );
              },
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.serverUrl, required this.error, required this.onRetry});

  final String serverUrl;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RecorderTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cannot reach Core", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RecorderTokens.space2),
          Text("Server URL: $serverUrl", style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: RecorderTokens.space2),
          Text("Error: $error", style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: RecorderTokens.space4),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
          ),
          const SizedBox(height: RecorderTokens.space4),
          const Text("Tip: run Core locally:\n  cargo run -p recorder_core -- --listen 127.0.0.1:17600"),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.dayLabel, required this.serverUrl, required this.onRefresh});

  final String dayLabel;
  final String serverUrl;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RecorderTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("No activity", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RecorderTokens.space2),
          Text("Day: $dayLabel", style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: RecorderTokens.space2),
          Text("Server URL: $serverUrl", style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: RecorderTokens.space4),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text("Refresh"),
          ),
          const SizedBox(height: RecorderTokens.space4),
          const Text(
            "Generate some activity:\n- Run Core\n- Install browser extension\n- Switch apps / tabs a few times",
          ),
        ],
      ),
    );
  }
}
