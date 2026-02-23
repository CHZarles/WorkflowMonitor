import "dart:async";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_manager/window_manager.dart";

import "../api/core_client.dart";
import "../utils/desktop_agent.dart";
import "../utils/tray_controller.dart";
import "../utils/update_manager.dart";
import "reports_screen.dart";
import "search_screen.dart";
import "settings_screen.dart";
import "today_screen.dart";

enum _TrackingAction { resume, pause15, pause60, pauseManual }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialDeepLink,
    this.startMinimized = false,
    this.externalCommands,
  });

  final String? initialDeepLink;
  final bool startMinimized;
  final Stream<String>? externalCommands;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _prefServerUrl = "serverUrl";
  static const _defaultServerUrl = "http://127.0.0.1:17600";
  static const _prefUpdateRepo = "updateGitHubRepo";
  static const _prefUpdateAutoCheck = "updateAutoCheck";
  static const _prefUpdateLastCheckIso = "updateLastCheckIso";

  final _todayKey = GlobalKey<TodayScreenState>();
  final _searchKey = GlobalKey<SearchScreenState>();
  final _reportsKey = GlobalKey<ReportsScreenState>();

  bool _ready = false;
  int _index = 0;
  bool _handledInitialDeepLink = false;

  String _serverUrl = _defaultServerUrl;
  late CoreClient _client = CoreClient(baseUrl: _serverUrl);
  TrackingStatus? _tracking;
  Timer? _trackingTimer;
  bool _agentStartAttempted = false;
  StreamSubscription<String>? _externalSub;
  bool _updateCheckAttempted = false;

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
    _externalSub = widget.externalCommands?.listen((msg) {
      _handleExternalCommand(msg);
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _externalSub?.cancel();
    TrayController.instance.dispose();
    super.dispose();
  }

  Future<void> _showAndFocusWindow() async {
    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } catch (_) {
      // ignore
    }
  }

  void _handleExternalCommand(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;

    if (s == "__show__") {
      unawaited(_showAndFocusWindow());
      return;
    }

    if (s.startsWith("recorderphone://")) {
      unawaited(_showAndFocusWindow());
      _handleDeepLink(s);
      return;
    }

    // Unknown command: best-effort just bring the app to front.
    unawaited(_showAndFocusWindow());
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

    // Windows tray: close-to-tray + quick actions.
    unawaited(
      TrayController.instance.ensureInitialized(
        getServerUrl: () => _serverUrl,
        onQuickReview: () async {
          if (!mounted) return;
          setState(() => _index = 1);
          _searchKey.currentState?.refresh(silent: false);
        },
        startHidden: widget.startMinimized &&
            (widget.initialDeepLink == null ||
                widget.initialDeepLink!.trim().isEmpty),
      ),
    );

    // Best-effort: if Core is down and we're on Windows, try starting the local agent so the user
    // doesn't need to run Core/Collector separately.
    unawaited(_maybeStartLocalAgent());
    unawaited(_maybeAutoCheckUpdates());

    await _refreshTracking();
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshTracking();
      TrayController.instance.refreshStatus();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHandleInitialDeepLink();
    });
  }

  bool _isLocalhostServer() {
    final uri = Uri.tryParse(_serverUrl.trim());
    if (uri == null) return false;
    final host = uri.host.trim().toLowerCase();
    return host == "127.0.0.1" ||
        host == "localhost" ||
        host == "0.0.0.0" ||
        host == "::1";
  }

  Future<void> _maybeStartLocalAgent() async {
    if (_agentStartAttempted) return;
    _agentStartAttempted = true;

    final agent = DesktopAgent.instance;
    if (!agent.isAvailable) return;
    if (!_isLocalhostServer()) return;

    // Always best-effort "ensure" Core + Collector are running locally.
    // This gives the one-click desktop experience in packaged mode.
    final res =
        await agent.start(coreUrl: _serverUrl, restart: false, sendTitle: true);
    if (!mounted) return;
    if (!res.ok) {
      final details = (res.message ?? "").trim();
      if (details.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 6),
              showCloseIcon: true,
              content: Text("Agent start failed: $details")),
        );
      }
      return;
    }

    // Refresh tracking state after Core comes up.
    await _refreshTracking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _todayKey.currentState?.refresh(silent: true, triggerReminder: true);
      _searchKey.currentState?.refresh(silent: true);
      _reportsKey.currentState?.refresh(silent: true);
    });
  }

  Future<void> _maybeAutoCheckUpdates() async {
    if (_updateCheckAttempted) return;
    _updateCheckAttempted = true;

    final mgr = UpdateManager.instance;
    if (!mgr.isAvailable) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final auto = prefs.getBool(_prefUpdateAutoCheck) ?? true;
      if (!auto) return;

      var repo = (prefs.getString(_prefUpdateRepo) ?? "").trim();
      repo = repo.isEmpty ? ((await mgr.defaultGitHubRepo()) ?? "").trim() : repo;
      if (repo.isEmpty) return;

      final lastIso = (prefs.getString(_prefUpdateLastCheckIso) ?? "").trim();
      if (lastIso.isNotEmpty) {
        try {
          final last = DateTime.parse(lastIso).toLocal();
          if (DateTime.now().difference(last) < const Duration(hours: 6)) return;
        } catch (_) {
          // ignore
        }
      }

      final res = await mgr.checkLatest(gitHubRepo: repo);
      try {
        await prefs.setString(_prefUpdateLastCheckIso, DateTime.now().toIso8601String());
      } catch (_) {
        // ignore
      }
      if (!res.ok || !res.updateAvailable) return;
      if (!mounted) return;

      // If the app started minimized to tray, don't spam a snackbar the user won't see.
      if (widget.startMinimized) return;

      final tag = res.latest?.tag ?? "latest";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          showCloseIcon: true,
          content: Text("Update available: $tag"),
          action: SnackBarAction(
            label: "Open Settings",
            onPressed: () => _setIndex(3),
          ),
        ),
      );
    } catch (_) {
      // best effort
    }
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

    final route = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : "");
    if (route != "review" && route != "quick-review") return;

    final blockId =
        (uri.queryParameters["block"] ?? uri.queryParameters["block_id"])
            ?.trim();
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
      final minutes =
          int.tryParse((uri.queryParameters["minutes"] ?? "").trim());
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
        const SnackBar(
            duration: Duration(seconds: 4),
            showCloseIcon: true,
            content: Text("Skipped the block")),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
      _searchKey.currentState?.refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Skip failed: $e")));
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
        SnackBar(
            duration: const Duration(seconds: 4),
            showCloseIcon: true,
            content: Text(label)),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Pause failed: $e")));
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
        const SnackBar(
            duration: Duration(seconds: 4),
            showCloseIcon: true,
            content: Text("Resumed")),
      );
      _todayKey.currentState?.refresh(silent: true, triggerReminder: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Resume failed: $e")));
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
                onPressed: () =>
                    Navigator.pop(ctx, _TrackingAction.pauseManual),
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
      _agentStartAttempted = false;
    });

    unawaited(_maybeStartLocalAgent());
    unawaited(TrayController.instance.refreshStatus());
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
    final titles = ["Today", "Review", "Reports", "Settings"];

    final pages = [
      TodayScreen(
        key: _todayKey,
        client: _client,
        serverUrl: _serverUrl,
        onOpenReview: () => _setIndex(1),
        onOpenSettings: () => _setIndex(3),
        onOpenReviewQuery: (q, day) async {
          _setIndex(1);
          final review = _searchKey.currentState;
          if (review != null) {
            await review.setDay(day, refresh: false);
            await review.applyQuery(q);
          }
        },
      ),
      SearchScreen(
        key: _searchKey,
        client: _client,
        serverUrl: _serverUrl,
        isActive: _index == 1,
      ),
      ReportsScreen(
        key: _reportsKey,
        client: _client,
        serverUrl: _serverUrl,
        onOpenSettings: () => _setIndex(3),
        isActive: _index == 2,
      ),
      SettingsScreen(
        client: _client,
        serverUrl: _serverUrl,
        onServerUrlChanged: _setServerUrl,
        isActive: _index == 3,
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
      if (_index == 2)
        IconButton(
          onPressed: () => _reportsKey.currentState?.refresh(),
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
                  icon: Icon(Icons.article_outlined),
                  selectedIcon: Icon(Icons.article),
                  label: Text("Reports"),
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
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: "Reports",
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
