import "dart:async";

import "package:flutter/material.dart";

import "../api/core_client.dart";
import "../theme/tokens.dart";
import "../utils/format.dart";
import "../widgets/block_card.dart";
import "../widgets/block_detail_sheet.dart";
import "../widgets/quick_review_sheet.dart";

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.client,
    required this.serverUrl,
    this.isActive = false,
    this.tutorialHeaderKey,
  });

  final CoreClient client;
  final String serverUrl;
  final bool isActive;
  final GlobalKey? tutorialHeaderKey;

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();

  _BlockStatusFilter _statusFilter = _BlockStatusFilter.all;

  bool _loading = false;
  bool _refreshing = false;
  Completer<void>? _loadCompleter;
  String? _error;
  DateTime _day = DateTime.now();
  List<BlockSummary> _blocks = const [];
  final Map<String, List<BlockCardItem>> _previewFocusByBlockId = {};
  final Map<String, BlockCardItem> _previewAudioTopByBlockId = {};

  Timer? _autoRetryTimer;
  int _autoRetryAttempts = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _load(silent: true);
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverUrl != widget.serverUrl) {
      _autoRetryTimer?.cancel();
      _autoRetryTimer = null;
      _autoRetryAttempts = 0;
      if (widget.isActive) {
        _load();
      } else if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _blocks = const [];
          _previewFocusByBlockId.clear();
          _previewAudioTopByBlockId.clear();
        });
      }
      return;
    }
    if (!oldWidget.isActive && widget.isActive) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> setDay(DateTime day, {bool refresh = true}) async {
    final next = DateTime(day.year, day.month, day.day);
    if (_day.year == next.year &&
        _day.month == next.month &&
        _day.day == next.day) {
      if (refresh) await _load(silent: true);
      return;
    }
    setState(() => _day = next);
    if (refresh) await _load(silent: true);
  }

  Future<void> applyQuery(String query, {bool refresh = true}) async {
    final q = query.trim();
    if (_queryController.text != q) {
      _queryController.text = q;
    }
    if (mounted) setState(() {});
    if (refresh) {
      await _load(silent: true);
    }
  }

  bool _isReviewed(BlockSummary b) {
    final r = b.review;
    if (r == null) return false;
    if (r.skipped) return true;
    final doing = (r.doing ?? "").trim();
    final output = (r.output ?? "").trim();
    final next = (r.next ?? "").trim();
    return doing.isNotEmpty ||
        output.isNotEmpty ||
        next.isNotEmpty ||
        r.tags.isNotEmpty;
  }

  String _dateLocal(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  bool _serverLooksLikeLocalhost() {
    final uri = Uri.tryParse(widget.serverUrl.trim());
    if (uri == null) return false;
    final host = uri.host.trim().toLowerCase();
    return host == "127.0.0.1" ||
        host == "localhost" ||
        host == "0.0.0.0" ||
        host == "::1";
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) {
      await (_loadCompleter?.future ?? Future.value());
    }
    await _load(silent: silent);
  }

  Future<void> _load({bool silent = false}) async {
    if (!widget.isActive && !silent) return;
    if (_refreshing) return;
    _refreshing = true;
    _loadCompleter = Completer<void>();
    final showLoadingUi = !silent || _error != null;
    if (showLoadingUi) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final ok = await widget.client.waitUntilHealthy(
        timeout: showLoadingUi
            ? (_serverLooksLikeLocalhost()
                ? const Duration(seconds: 15)
                : const Duration(seconds: 6))
            : const Duration(milliseconds: 900),
      );
      if (!ok) {
        if (showLoadingUi) throw Exception("health_failed");
        _scheduleAutoRetryIfNeeded("health_failed");
        return;
      }

      final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final blocks = await widget.client.blocksToday(
        date: _dateLocal(_day),
        tzOffsetMinutes: tzOffsetMinutes,
      );
      final previews = _buildPreviewsFromBlocks(blocks: blocks);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _previewFocusByBlockId
          ..clear()
          ..addAll(previews.focus);
        _previewAudioTopByBlockId
          ..clear()
          ..addAll(previews.audioTop);
        _error = null;
      });
      _autoRetryAttempts = 0;
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (showLoadingUi) setState(() => _error = msg);
      _scheduleAutoRetryIfNeeded(msg);
    } finally {
      if (showLoadingUi && mounted) {
        setState(() => _loading = false);
      }
      _refreshing = false;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }
  }

  bool _isTransientError(String msg) {
    final s = msg.toLowerCase();
    if (s.contains("health_failed")) return true;
    if (s.contains("connection") || s.contains("socket")) return true;
    if (s.contains("refused") ||
        s.contains("timed out") ||
        s.contains("timeout")) return true;
    if (s.contains("http_502") ||
        s.contains("http_503") ||
        s.contains("http_504")) return true;
    return false;
  }

  void _scheduleAutoRetryIfNeeded(String msg) {
    if (!mounted) return;
    if (_autoRetryTimer != null) return;
    if (!_serverLooksLikeLocalhost()) return;
    if (!_isTransientError(msg)) return;
    if (_autoRetryAttempts >= 8) return;

    final backoffMs = (350 * (1 << _autoRetryAttempts)).clamp(350, 5000);
    _autoRetryAttempts += 1;
    _autoRetryTimer = Timer(Duration(milliseconds: backoffMs), () {
      _autoRetryTimer = null;
      if (!mounted) return;
      _load(silent: true);
    });
  }

  ({
    Map<String, List<BlockCardItem>> focus,
    Map<String, BlockCardItem> audioTop
  }) _buildPreviewsFromBlocks({
    required List<BlockSummary> blocks,
  }) {
    String guessKind(String entity) {
      final v = entity.trim();
      if (v.isEmpty) return "app";
      if (v.contains("\\") || v.contains("/") || v.contains(":")) return "app";
      if (!v.contains(".")) return "app";
      if (v.contains(" ")) return "app";
      return "domain";
    }

    String kindForTopItem(TopItem it) {
      return (it.kind == "domain" || it.kind == "app")
          ? it.kind
          : guessKind(it.entity);
    }

    BlockCardItem itemFromTopItem(TopItem it, {required bool audio}) {
      final kind = kindForTopItem(it);
      if (kind == "domain") {
        final domain = it.entity.trim().toLowerCase();
        final rawTitle = (it.title ?? "").trim();
        final title =
            rawTitle.isEmpty ? "" : normalizeWebTitle(domain, rawTitle);
        final label = title.isEmpty ? displayEntity(domain) : title;
        final subtitle = title.isEmpty ? null : displayEntity(domain);
        return BlockCardItem(
          kind: kind,
          entity: domain,
          label: label,
          subtitle: subtitle,
          seconds: it.seconds,
          audio: audio,
        );
      }

      final appEntity = it.entity.trim();
      final appLabel = displayEntity(appEntity);
      String? subtitle;

      final title = (it.title ?? "").trim();
      if (title.isNotEmpty) {
        final labelLc = appLabel.toLowerCase();
        final isVscode = labelLc == "code" ||
            labelLc == "vscode" ||
            title.contains("Visual Studio Code");
        if (isVscode) {
          final ws = extractVscodeWorkspace(title);
          if (ws != null && ws.trim().isNotEmpty) {
            subtitle = "Workspace: ${ws.trim()}";
          }
        }
      }

      return BlockCardItem(
        kind: kind,
        entity: appEntity,
        label: appLabel,
        subtitle: subtitle,
        seconds: it.seconds,
        audio: audio,
      );
    }

    final focus = <String, List<BlockCardItem>>{};
    final audioTop = <String, BlockCardItem>{};

    for (final b in blocks) {
      focus[b.id] = b.topItems
          .take(4)
          .map((it) => itemFromTopItem(it, audio: false))
          .toList();
      if (b.backgroundTopItems.isNotEmpty) {
        audioTop[b.id] =
            itemFromTopItem(b.backgroundTopItems.first, audio: true);
      }
    }

    return (focus: focus, audioTop: audioTop);
  }

  Future<void> openBlockById(String blockId, {bool quick = false}) async {
    final id = blockId.trim();
    if (id.isEmpty) return;

    // Prefer the day inferred from block_id (block_id == start_ts RFC3339).
    try {
      final local = DateTime.parse(id).toLocal();
      final nextDay = DateTime(local.year, local.month, local.day);
      if (_day.year != nextDay.year ||
          _day.month != nextDay.month ||
          _day.day != nextDay.day) {
        setState(() => _day = nextDay);
      }
    } catch (_) {
      // ignore
    }

    if (_refreshing) {
      await (_loadCompleter?.future ?? Future.value());
    }
    await _load();

    BlockSummary? found;
    for (final b in _blocks) {
      if (b.id == id) {
        found = b;
        break;
      }
    }

    if (found == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Block not found: $id")),
      );
      return;
    }

    await _openBlock(found, quick: quick);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    await _load();
  }

  bool _matches(BlockSummary b, String q) {
    final target = q.trim().toLowerCase();
    if (target.isEmpty) return true;

    final timeRange =
        "${formatHHMM(b.startTs)}–${formatHHMM(b.endTs)}".toLowerCase();
    if (timeRange.contains(target)) return true;

    for (final it in b.topItems) {
      final name = displayTopItemName(it).toLowerCase();
      if (name.contains(target)) return true;
      if (it.entity.toLowerCase().contains(target)) return true;
      if ((it.title ?? "").toLowerCase().contains(target)) return true;
    }

    final preview = _previewFocusByBlockId[b.id];
    if (preview != null) {
      for (final it in preview) {
        if (it.label.toLowerCase().contains(target)) return true;
        if ((it.subtitle ?? "").toLowerCase().contains(target)) return true;
        if (it.entity.toLowerCase().contains(target)) return true;
      }
    }
    final audio = _previewAudioTopByBlockId[b.id];
    if (audio != null) {
      if (audio.label.toLowerCase().contains(target)) return true;
      if ((audio.subtitle ?? "").toLowerCase().contains(target)) return true;
    }

    final r = b.review;
    if (r != null) {
      final doing = (r.doing ?? "").toLowerCase();
      final output = (r.output ?? "").toLowerCase();
      final next = (r.next ?? "").toLowerCase();
      final reason = (r.skipReason ?? "").toLowerCase();
      if (doing.contains(target) ||
          output.contains(target) ||
          next.contains(target) ||
          reason.contains(target)) {
        return true;
      }
      for (final t in r.tags) {
        if (t.toLowerCase().contains(target)) return true;
      }
    }

    return false;
  }

  List<BlockSummary> _filteredBlocks() {
    Iterable<BlockSummary> out = _blocks;
    switch (_statusFilter) {
      case _BlockStatusFilter.all:
        break;
      case _BlockStatusFilter.pending:
        out = out.where((b) => !_isReviewed(b));
        break;
      case _BlockStatusFilter.reviewed:
        out = out.where(_isReviewed);
        break;
      case _BlockStatusFilter.skipped:
        out = out.where((b) => b.review?.skipped == true);
        break;
    }

    final q = _queryController.text;
    if (q.trim().isEmpty) return out.toList();
    return out.where((b) => _matches(b, q)).toList();
  }

  Future<void> _openBlock(BlockSummary b, {bool quick = false}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => quick
          ? QuickReviewSheet(client: widget.client, block: b)
          : BlockDetailSheet(client: widget.client, block: b),
    );
    if (ok == true) {
      await _load(silent: true);
    }
  }

  Widget _searchHeader(BuildContext context, int results, int total) {
    final date = _dateLocal(_day);
    final isWide = MediaQuery.of(context).size.width >= 720;

    final field = TextField(
      controller: _queryController,
      decoration: InputDecoration(
        hintText: "Search apps/domains/notes/tags…",
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _queryController.text.trim().isEmpty
            ? null
            : IconButton(
                tooltip: "Clear",
                onPressed: () => setState(() => _queryController.text = ""),
                icon: const Icon(Icons.clear),
              ),
      ),
      onChanged: (_) => setState(() {}),
    );

    final dateBtn = OutlinedButton.icon(
      onPressed: _pickDate,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(date),
    );

    final meta = Text(
      "$results / $total blocks",
      style: Theme.of(context).textTheme.labelMedium,
    );

    final filter = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_BlockStatusFilter>(
        segments: const [
          ButtonSegment(value: _BlockStatusFilter.all, label: Text("All")),
          ButtonSegment(
              value: _BlockStatusFilter.pending, label: Text("Pending")),
          ButtonSegment(
              value: _BlockStatusFilter.reviewed, label: Text("Reviewed")),
          ButtonSegment(
              value: _BlockStatusFilter.skipped, label: Text("Skipped")),
        ],
        selected: {_statusFilter},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _statusFilter = v.first),
      ),
    );

    final Widget content = isWide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: RecorderTokens.space3),
                  dateBtn,
                ],
              ),
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Expanded(child: meta),
                  const SizedBox(width: RecorderTokens.space3),
                  filter,
                ],
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field,
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  dateBtn,
                  const SizedBox(width: RecorderTokens.space3),
                  meta,
                ],
              ),
              const SizedBox(height: RecorderTokens.space2),
              filter,
            ],
          );

    return Container(key: widget.tutorialHeaderKey, child: content);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      final msg = _error ?? "";
      final auto = _serverLooksLikeLocalhost() && _isTransientError(msg);
      return Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Review unavailable",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RecorderTokens.space2),
            Text("Server URL: ${widget.serverUrl}",
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: RecorderTokens.space2),
            Text("Error: $msg", style: Theme.of(context).textTheme.labelMedium),
            if (auto) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: RecorderTokens.space2),
                  const Expanded(child: Text("Retrying automatically…")),
                ],
              ),
            ],
            const SizedBox(height: RecorderTokens.space4),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredBlocks().reversed.toList();

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        itemCount: filtered.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(height: RecorderTokens.space3),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _searchHeader(context, filtered.length, _blocks.length);
          }
          final block = filtered[i - 1];
          return BlockCard(
            block: block,
            onTap: () => _openBlock(block),
            previewFocus: _previewFocusByBlockId[block.id],
            previewAudioTop: _previewAudioTopByBlockId[block.id],
          );
        },
      ),
    );
  }
}

enum _BlockStatusFilter { all, pending, reviewed, skipped }
