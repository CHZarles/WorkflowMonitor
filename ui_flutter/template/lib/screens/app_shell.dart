import "dart:async";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../api/core_client.dart";
import "search_screen.dart";
import "settings_screen.dart";
import "today_screen.dart";

enum _TrackingAction { resume, pause15, pause60, pauseManual }

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialDeepLink});

  final String? initialDeepLink;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _prefServerUrl = "serverUrl";
  static const _defaultServerUrl = "http://127.0.0.1:17600";

  final _todayKey = GlobalKey<TodayScreenState>();
  final _searchKey = GlobalKey<SearchScreenState>();

  bool _ready = false;
  int _index = 0;
  bool _handledInitialDeepLink = false;

  String _serverUrl = _defaultServerUrl;
  late CoreClient _client = CoreClient(baseUrl: _serverUrl);
  TrackingStatus? _tracking;
  Timer? _trackingTimer;

  String _normalizeServerUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return trimmed;

    final host = uri.host.contains(":") ? "[${uri.host}]" : uri.host;
    final port = uri.hasPort ? ":${uri.port}" : "";
    return "${uri.scheme}://$host$port";
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefServerUrl);
    if (v != null && v.trim().isNotEmpty) {
      _serverUrl = _normalizeServerUrl(v);
      _client = CoreClient(baseUrl: _serverUrl);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    await _refreshTracking();
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshTracking();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHandleInitialDeepLink();
    });
  }

  void _maybeHandleInitialDeepLink() {
    if (_handledInitialDeepLink) return;
    _handledInitialDeepLink = true;

    final raw = widget.initialDeepLink;
    if (raw == null || raw.trim().isEmpty) return;
    _handleDeepLink(raw.trim());
  }

  void _handleDeepLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != "recorderphone") return;

    final route = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : "");
    if (route != "review" && route != "quick-review") return;

    final blockId = (uri.queryParameters["block"] ?? uri.queryParameters["block_id"])?.trim();
    final action = uri.queryParameters["action"]?.trim().toLowerCase();

    if (action == "skip") {
      setState(() => _index = 1);
      final id = (blockId ?? "").trim();
      if (id.isEmpty) return;
      _skipBlock(id);
      return;
    }

    if (action == "pause") {
      setState(() => _index = 0);
      final minutes = int.tryParse((uri.queryParameters["minutes"] ?? "").trim());
      _pauseTrackingFromDeepLink(minutes: minutes);
      return;
    }

    if (action == "resume") {
      setState(() => _index = 0);
      _resumeTrackingFromDeepLink();
      return;
    }

    setState(() => _index = 1);
    final review = _searchKey.currentState;
    if (review == null) return;

    if (blockId != null && blockId.isNotEmpty) {
      review.openBlockById(blockId, quick: true).catchError((_) {});
    } else {
      review.refresh().catchError((_) {});
    }
  }

  Future<void> _skipBlock(String blockId) async {
    try {
      await _client.upsertReview(
        ReviewUpsert(
          blockId: blockId,
          skipped: true,
          skipReason: null,
          doing: null,
          output: null,
          next: null,
          tags: const [],
        ),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(duration: Duration(seconds: 4), showCloseIcon: true, content: Text("Skipped the block")),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
      _searchKey.currentState?.refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Skip failed: $e")));
    }
  }

  Future<void> _pauseTrackingFromDeepLink({int? minutes}) async {
    try {
      final status = await _client.pauseTracking(minutes: minutes);
      if (!mounted) return;
      setState(() => _tracking = status);
      final label = minutes == null ? "Paused" : "Paused ${minutes}m";
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 4), showCloseIcon: true, content: Text(label)),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pause failed: $e")));
    }
  }

  Future<void> _resumeTrackingFromDeepLink() async {
    try {
      final status = await _client.resumeTracking();
      if (!mounted) return;
      setState(() => _tracking = status);
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(duration: Duration(seconds: 4), showCloseIcon: true, content: Text("Resumed")),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Resume failed: $e")));
    }
  }

  Future<void> _refreshTracking() async {
    try {
      final status = await _client.trackingStatus();
      if (!mounted) return;
      setState(() => _tracking = status);
    } catch (_) {
      // best effort
    }
  }

  Future<void> _openTrackingMenu() async {
    try {
      final status = await _client.trackingStatus();
      if (!mounted) return;
      setState(() => _tracking = status);

      final paused = status.paused;
      final action = await showDialog<_TrackingAction>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text("Tracking"),
          children: [
            if (paused)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, _TrackingAction.resume),
                child: const Text("Resume"),
              )
            else ...[
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, _TrackingAction.pause15),
                child: const Text("Pause 15m"),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, _TrackingAction.pause60),
                child: const Text("Pause 1h"),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, _TrackingAction.pauseManual),
                child: const Text("Pause until resume"),
              ),
            ],
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
          ],
        ),
      );
      if (action == null) return;

      TrackingStatus next;
      switch (action) {
        case _TrackingAction.resume:
          next = await _client.resumeTracking();
          break;
        case _TrackingAction.pause15:
          next = await _client.pauseTracking(minutes: 15);
          break;
        case _TrackingAction.pause60:
          next = await _client.pauseTracking(minutes: 60);
          break;
        case _TrackingAction.pauseManual:
          next = await _client.pauseTracking();
          break;
      }
      if (!mounted) return;
      setState(() => _tracking = next);
      _todayKey.currentState?.refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Tracking action failed: $e")),
      );
    }
  }

  Future<void> _setServerUrl(String url) async {
    final normalized = _normalizeServerUrl(url);
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerUrl, normalized);
    if (!mounted) return;
    setState(() {
      _serverUrl = normalized;
      _client = CoreClient(baseUrl: _serverUrl);
    });

    await _refreshTracking();
    _todayKey.currentState?.refresh();
    _searchKey.currentState?.refresh();
  }

  void _setIndex(int i) => setState(() => _index = i);

  String _trackingChipLabel(TrackingStatus? s) {
    if (s == null) return "…";
    if (!s.paused) return "ON";

    final until = s.pausedUntilTs;
    if (until == null || until.trim().isEmpty) return "PAUSED";
    try {
      final t = DateTime.parse(until).toLocal();
      final diff = t.difference(DateTime.now());
      if (diff.inSeconds <= 0) return "PAUSED";
      final m = (diff.inSeconds / 60).ceil().clamp(1, 9999);
      return "PAUSED ${m}m";
    } catch (_) {
      return "PAUSED";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isWide = MediaQuery.of(context).size.width >= 720;
    final titles = ["Today", "Review", "Settings"];

    final pages = [
      TodayScreen(
        key: _todayKey,
        client: _client,
        serverUrl: _serverUrl,
        onOpenReview: () => _setIndex(1),
        onOpenSettings: () => _setIndex(2),
        onOpenReviewQuery: (q, day) async {
          _setIndex(1);
          final review = _searchKey.currentState;
          if (review != null) {
            await review.setDay(day, refresh: false);
            await review.applyQuery(q);
          }
        },
      ),
      SearchScreen(key: _searchKey, client: _client, serverUrl: _serverUrl),
      SettingsScreen(
        client: _client,
        serverUrl: _serverUrl,
        onServerUrlChanged: _setServerUrl,
      ),
    ];

    final trackingLabel = _trackingChipLabel(_tracking);

    final actions = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ActionChip(
          label: Text(trackingLabel),
          avatar: Icon(
            _tracking?.paused == true ? Icons.pause : Icons.play_arrow,
            size: 18,
          ),
          onPressed: _openTrackingMenu,
        ),
      ),
      if (_index == 0)
        IconButton(
          onPressed: () => _todayKey.currentState?.refresh(),
          tooltip: "Refresh",
          icon: const Icon(Icons.refresh),
        ),
      if (_index == 1)
        IconButton(
          onPressed: () => _searchKey.currentState?.refresh(),
          tooltip: "Refresh",
          icon: const Icon(Icons.refresh),
        ),
    ];

    if (isWide) {
      return Scaffold(
        appBar: AppBar(title: Text(titles[_index]), actions: actions),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _setIndex,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: Text("Today"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt),
                  label: Text("Review"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text("Settings"),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: IndexedStack(index: _index, children: pages)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index]), actions: actions),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _setIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: "Today",
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: "Review",
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
