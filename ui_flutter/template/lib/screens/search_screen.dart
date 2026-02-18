import "dart:async";

import "package:flutter/material.dart";

import "../api/core_client.dart";
import "../theme/tokens.dart";
import "../utils/format.dart";
import "../widgets/block_card.dart";
import "../widgets/block_detail_sheet.dart";
import "../widgets/quick_review_sheet.dart";

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.client, required this.serverUrl});

  final CoreClient client;
  final String serverUrl;

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();

  _BlockStatusFilter _statusFilter = _BlockStatusFilter.all;

  bool _loading = true;
  bool _refreshing = false;
  Completer<void>? _loadCompleter;
  String? _error;
  DateTime _day = DateTime.now();
  List<BlockSummary> _blocks = const [];
  final Map<String, List<BlockCardItem>> _previewFocusByBlockId = {};
  final Map<String, BlockCardItem> _previewAudioTopByBlockId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverUrl != widget.serverUrl) {
      _load();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> setDay(DateTime day, {bool refresh = true}) async {
    final next = DateTime(day.year, day.month, day.day);
    if (_day.year == next.year && _day.month == next.month && _day.day == next.day) {
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
    return doing.isNotEmpty || output.isNotEmpty || next.isNotEmpty || r.tags.isNotEmpty;
  }

  String _dateLocal(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  Future<void> refresh({bool silent = false}) async => _load(silent: silent);

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    _loadCompleter = Completer<void>();
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (!silent) {
        final ok = await widget.client.health();
        if (!ok) throw Exception("health_failed");
      }

      final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final date = _dateLocal(_day);

      final settingsFuture = widget.client.settings();
      final blocksFuture = widget.client.blocksToday(
        date: _dateLocal(_day),
        tzOffsetMinutes: tzOffsetMinutes,
      );
      final segsFuture = widget.client.timelineDay(date: date, tzOffsetMinutes: tzOffsetMinutes);

      final settings = await settingsFuture;
      final blocks = await blocksFuture;
      final segs = await segsFuture;

      final previews = _buildPreviews(blocks: blocks, segments: segs, storeTitles: settings.storeTitles);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _previewFocusByBlockId
          ..clear()
          ..addAll(previews.focus);
        _previewAudioTopByBlockId
          ..clear()
          ..addAll(previews.audioTop);
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _loading = false);
      }
      _refreshing = false;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }
  }

  ({Map<String, List<BlockCardItem>> focus, Map<String, BlockCardItem> audioTop}) _buildPreviews({
    required List<BlockSummary> blocks,
    required List<TimelineSegment> segments,
    required bool storeTitles,
  }) {
    bool isBrowserLabel(String label) {
      final v = label.toLowerCase();
      return v == "chrome" || v == "msedge" || v == "edge" || v == "brave" || v == "vivaldi" || v == "opera" || v == "firefox";
    }

    final parsedSegs = <({TimelineSegment s, DateTime startUtc, DateTime endUtc})>[];
    for (final s in segments) {
      try {
        final startUtc = DateTime.parse(s.startTs).toUtc();
        final endUtc = DateTime.parse(s.endTs).toUtc();
        if (!endUtc.isAfter(startUtc)) continue;
        parsedSegs.add((s: s, startUtc: startUtc, endUtc: endUtc));
      } catch (_) {
        // ignore
      }
    }

    Map<String, List<BlockCardItem>> buildFor({required bool audio}) {
      final out = <String, List<BlockCardItem>>{};

      for (final b in blocks) {
        DateTime blockStartUtc;
        DateTime blockEndUtc;
        try {
          blockStartUtc = DateTime.parse(b.startTs).toUtc();
          blockEndUtc = DateTime.parse(b.endTs).toUtc();
        } catch (_) {
          continue;
        }
        if (!blockEndUtc.isAfter(blockStartUtc)) continue;

        final secByKey = <String, int>{};
        final kindByKey = <String, String>{};
        final entityByKey = <String, String>{};
        final labelByKey = <String, String>{};
        final subtitleByKey = <String, String?>{};

        for (final seg in parsedSegs) {
          final s = seg.s;
          final isAudio = s.activity == "audio";
          if (audio != isAudio) continue;
          if (s.kind != "app" && s.kind != "domain") continue;
          final rawEntity = s.entity.trim();
          if (rawEntity.isEmpty) continue;

          if (!seg.endUtc.isAfter(blockStartUtc) || !blockEndUtc.isAfter(seg.startUtc)) continue;
          final overlapStart = seg.startUtc.isAfter(blockStartUtc) ? seg.startUtc : blockStartUtc;
          final overlapEnd = seg.endUtc.isBefore(blockEndUtc) ? seg.endUtc : blockEndUtc;
          final seconds = overlapEnd.difference(overlapStart).inSeconds;
          if (seconds <= 0) continue;

          String key;
          String entity;
          String label;
          String? subtitle;

          if (s.kind == "domain") {
            final domain = rawEntity.toLowerCase();
            final rawTitle = (s.title ?? "").trim();
            final normTitle = storeTitles ? normalizeWebTitle(domain, rawTitle) : "";
            if (storeTitles && normTitle.isNotEmpty) {
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
            final labelLc = appLabel.toLowerCase();
            final title = (s.title ?? "").trim();
            final isVscode = labelLc == "code" || labelLc == "vscode" || title.contains("Visual Studio Code");
            final ws = (storeTitles && isVscode && title.isNotEmpty) ? extractVscodeWorkspace(title) : null;

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

              if (storeTitles && title.isNotEmpty && !isBrowserLabel(appLabel)) {
                subtitle = title;
              }
            }
          }

          secByKey[key] = (secByKey[key] ?? 0) + seconds;
          kindByKey[key] = s.kind;
          entityByKey[key] = entity;
          labelByKey[key] = label;
          subtitleByKey[key] = (subtitleByKey[key] == null || subtitleByKey[key]!.trim().isEmpty)
              ? subtitle
              : subtitleByKey[key];
        }

        final items = <BlockCardItem>[];
        for (final k in secByKey.keys) {
          items.add(
            BlockCardItem(
              kind: kindByKey[k] ?? "",
              entity: entityByKey[k] ?? "",
              label: labelByKey[k] ?? "",
              subtitle: subtitleByKey[k],
              seconds: secByKey[k] ?? 0,
              audio: audio,
            ),
          );
        }
        items.sort((a, b) => b.seconds.compareTo(a.seconds));
        out[b.id] = items;
      }

      return out;
    }

    final focus = buildFor(audio: false);
    final audioItems = buildFor(audio: true);
    final audioTop = <String, BlockCardItem>{};
    for (final e in audioItems.entries) {
      final list = e.value;
      if (list.isEmpty) continue;
      audioTop[e.key] = list.first;
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
      if (_day.year != nextDay.year || _day.month != nextDay.month || _day.day != nextDay.day) {
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

    final timeRange = "${formatHHMM(b.startTs)}–${formatHHMM(b.endTs)}".toLowerCase();
    if (timeRange.contains(target)) return true;

    for (final it in b.topItems) {
      final name = displayTopItemName(it).toLowerCase();
      if (name.contains(target)) return true;
      if (it.name.toLowerCase().contains(target)) return true;
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
      if (doing.contains(target) || output.contains(target) || next.contains(target) || reason.contains(target)) {
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
      builder: (_) =>
          quick ? QuickReviewSheet(client: widget.client, block: b) : BlockDetailSheet(client: widget.client, block: b),
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
          ButtonSegment(value: _BlockStatusFilter.pending, label: Text("Pending")),
          ButtonSegment(value: _BlockStatusFilter.reviewed, label: Text("Reviewed")),
          ButtonSegment(value: _BlockStatusFilter.skipped, label: Text("Skipped")),
        ],
        selected: {_statusFilter},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _statusFilter = v.first),
      ),
    );

    if (isWide) {
      return Column(
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
      );
    }

    return Column(
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
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Review unavailable", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RecorderTokens.space2),
            Text("Server URL: ${widget.serverUrl}", style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: RecorderTokens.space2),
            Text("Error: $_error", style: Theme.of(context).textTheme.labelMedium),
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
        separatorBuilder: (_, __) => const SizedBox(height: RecorderTokens.space3),
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
