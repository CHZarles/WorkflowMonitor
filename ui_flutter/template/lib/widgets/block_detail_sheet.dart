import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../api/core_client.dart";
import "../theme/tokens.dart";
import "../utils/format.dart";

class _BlockStatItem {
  const _BlockStatItem({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.seconds,
  });

  final String kind; // "app" | "domain"
  final String entity; // app id or hostname
  final String label;
  final String? subtitle;
  final int seconds;
}

class BlockDetailSheet extends StatefulWidget {
  const BlockDetailSheet({super.key, required this.client, required this.block});

  final CoreClient client;
  final BlockSummary block;

  @override
  State<BlockDetailSheet> createState() => _BlockDetailSheetState();
}

class _BlockDetailSheetState extends State<BlockDetailSheet> {
  late final TextEditingController _doing;
  late final TextEditingController _output;
  late final TextEditingController _next;
  bool _saving = false;
  bool _deleting = false;
  bool _skipSaving = false;
  bool _rulesLoading = true;
  final Map<String, int> _ruleIdByKey = {};
  final Set<String> _blockedKeys = {};
  final Set<String> _tags = {};

  bool _statsLoading = true;
  List<_BlockStatItem> _focusStats = const [];
  List<_BlockStatItem> _audioStats = const [];
  int? _audioTotalSeconds;

  static const _presetTags = ["Work", "Meeting", "Learning", "Admin", "Life", "Entertainment"];

  @override
  void initState() {
    super.initState();
    _doing = TextEditingController(text: widget.block.review?.doing ?? "");
    _output = TextEditingController(text: widget.block.review?.output ?? "");
    _next = TextEditingController(text: widget.block.review?.next ?? "");
    _tags.addAll(widget.block.review?.tags ?? const []);
    _loadRules();
    _loadStats();
  }

  @override
  void dispose() {
    _doing.dispose();
    _output.dispose();
    _next.dispose();
    super.dispose();
  }

  String _ruleKey(String kind, String value) => "$kind|$value";

  bool _isBlockedEntity({required String kind, required String entity}) {
    if (kind != "domain" && kind != "app") return false;
    final value = kind == "domain" ? entity.toLowerCase() : entity;
    return _blockedKeys.contains(_ruleKey(kind, value));
  }

  String _guessKind(String value) {
    final v = value.trim();
    if (v.isEmpty) return "app";
    if (v.contains("\\") || v.contains("/") || v.contains(":")) return "app";
    if (!v.contains(".")) return "app";
    if (v.contains(" ")) return "app";
    return "domain";
  }

  String _kindForTopItem(TopItem it) {
    return (it.kind == "domain" || it.kind == "app") ? it.kind : _guessKind(it.entity);
  }

  _BlockStatItem _statFromTopItem(TopItem it) {
    final kind = _kindForTopItem(it);
    if (kind == "domain") {
      final domain = it.entity.trim().toLowerCase();
      final rawTitle = (it.title ?? "").trim();
      final title = rawTitle.isEmpty ? "" : normalizeWebTitle(domain, rawTitle);
      final label = title.isEmpty ? displayEntity(domain) : title;
      final subtitle = title.isEmpty ? null : displayEntity(domain);
      return _BlockStatItem(kind: kind, entity: domain, label: label, subtitle: subtitle, seconds: it.seconds);
    }

    final appEntity = it.entity.trim();
    final label = displayEntity(appEntity);
    return _BlockStatItem(kind: kind, entity: appEntity, label: label, subtitle: null, seconds: it.seconds);
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

  bool _isBrowserLabel(String label) {
    final v = label.toLowerCase();
    return v == "chrome" || v == "msedge" || v == "edge" || v == "brave" || v == "vivaldi" || v == "opera";
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final startUtc = DateTime.parse(widget.block.startTs).toUtc();
      final endUtc = DateTime.parse(widget.block.endTs).toUtc();
      if (!endUtc.isAfter(startUtc)) return;

      final startLocal = startUtc.toLocal();
      final dateLocal =
          "${startLocal.year.toString().padLeft(4, "0")}-${startLocal.month.toString().padLeft(2, "0")}-${startLocal.day.toString().padLeft(2, "0")}";
      final tzOffsetMinutes = startLocal.timeZoneOffset.inMinutes;

      final settings = await widget.client.settings();
      final storeTitles = settings.storeTitles;

      final segs = await widget.client.timelineDay(date: dateLocal, tzOffsetMinutes: tzOffsetMinutes);
      final focus = _aggregateSegments(segs, startUtc, endUtc, storeTitles, audio: false);
      final audio = _aggregateSegments(segs, startUtc, endUtc, storeTitles, audio: true);
      final audioTotal = audio.fold<int>(0, (sum, it) => sum + it.seconds);

      if (!mounted) return;
      setState(() {
        _focusStats = focus;
        _audioStats = audio;
        _audioTotalSeconds = audioTotal > 0 ? audioTotal : null;
      });
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  List<_BlockStatItem> _aggregateSegments(
    List<TimelineSegment> segs,
    DateTime blockStartUtc,
    DateTime blockEndUtc,
    bool storeTitles, {
    required bool audio,
  }) {
    final secByKey = <String, int>{};
    final kindByKey = <String, String>{};
    final entityByKey = <String, String>{};
    final labelByKey = <String, String>{};
    final subtitleByKey = <String, String?>{};

    for (final s in segs) {
      final kind = s.kind;
      if (kind != "app" && kind != "domain") continue;
      final isAudio = s.activity == "audio";
      if (audio != isAudio) continue;

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

      final start = segStartUtc.isAfter(blockStartUtc) ? segStartUtc : blockStartUtc;
      final end = segEndUtc.isBefore(blockEndUtc) ? segEndUtc : blockEndUtc;
      if (!end.isAfter(start)) continue;

      final seconds = end.difference(start).inSeconds;
      if (seconds <= 0) continue;

      String key;
      String entity;
      String label;
      String? subtitle;

      if (kind == "domain") {
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
        key = "app|$appEntity";
        entity = appEntity;
        label = appLabel;
        subtitle = null;

        if (storeTitles) {
          final t = (s.title ?? "").trim();
          if (t.isNotEmpty && !_isBrowserLabel(appLabel)) {
            if (t.contains("Visual Studio Code") || appLabel.toLowerCase() == "code" || appLabel.toLowerCase() == "vscode") {
              final ws = extractVscodeWorkspace(t);
              subtitle = (ws != null && ws.trim().isNotEmpty) ? "Workspace: ${ws.trim()}" : t;
            } else {
              subtitle = t;
            }
          }
        }
      }

      secByKey[key] = (secByKey[key] ?? 0) + seconds;
      kindByKey[key] = kind;
      entityByKey[key] = entity;
      labelByKey[key] = label;
      subtitleByKey[key] = subtitle;
    }

    final out = <_BlockStatItem>[];
    for (final key in secByKey.keys) {
      out.add(
        _BlockStatItem(
          kind: kindByKey[key] ?? "",
          entity: entityByKey[key] ?? "",
          label: labelByKey[key] ?? "",
          subtitle: subtitleByKey[key],
          seconds: secByKey[key] ?? 0,
        ),
      );
    }
    out.sort((a, b) => b.seconds.compareTo(a.seconds));
    if (out.length > 5) return out.take(5).toList();
    return out;
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

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add tag"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "e.g. Work"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Add"),
          ),
        ],
      ),
    );
    controller.dispose();
    final t = tag?.trim();
    if (t == null || t.isEmpty) return;
    setState(() => _tags.add(t));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.client.upsertReview(
        ReviewUpsert(
          blockId: widget.block.id,
          skipped: false,
          skipReason: null,
          doing: _doing.text.trim().isEmpty ? null : _doing.text.trim(),
          output: _output.text.trim().isEmpty ? null : _output.text.trim(),
          next: _next.text.trim().isEmpty ? null : _next.text.trim(),
          tags: _tags.toList(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSkip({required bool skipped}) async {
    setState(() => _skipSaving = true);
    try {
      await widget.client.upsertReview(
        ReviewUpsert(
          blockId: widget.block.id,
          skipped: skipped,
          skipReason: null,
          doing: _doing.text.trim().isEmpty ? null : _doing.text.trim(),
          output: _output.text.trim().isEmpty ? null : _output.text.trim(),
          next: _next.text.trim().isEmpty ? null : _next.text.trim(),
          tags: _tags.toList(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Action failed: $e")));
    } finally {
      if (mounted) setState(() => _skipSaving = false);
    }
  }

  Future<void> _deleteBlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this block?"),
        content: Text(
          "This will delete events and review for:\n${widget.block.startTs} – ${widget.block.endTs}\n\nThis cannot be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      final res = await widget.client.deleteBlock(startTs: widget.block.startTs, endTs: widget.block.endTs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted ${res.eventsDeleted} events, ${res.reviewsDeleted} reviews")),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusItems = _focusStats.isNotEmpty ? _focusStats : widget.block.topItems.map(_statFromTopItem).toList();
    final audioItems =
        _audioStats.isNotEmpty ? _audioStats : widget.block.backgroundTopItems.map(_statFromTopItem).toList();

    final top = focusItems.take(3).map((e) => e.label).join(" · ");
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxSeconds = focusItems.fold<int>(0, (m, it) => it.seconds > m ? it.seconds : m);
    final bgMaxSeconds = audioItems.fold<int>(0, (m, it) => it.seconds > m ? it.seconds : m);
    final allTags = {..._presetTags, ..._tags}.toList();
    allTags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final skipped = widget.block.review?.skipped == true;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_saving || _deleting || _skipSaving) return;
          _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_saving || _deleting || _skipSaving) return;
          _save();
        },
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: EdgeInsets.only(
            left: RecorderTokens.space4,
            right: RecorderTokens.space4,
            bottom: bottom + RecorderTokens.space4,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text("Block details", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: RecorderTokens.space2),
              Text("Top: $top", style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: RecorderTokens.space4),
              Text("Top items", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: RecorderTokens.space2),
              if (_statsLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: RecorderTokens.space2),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (focusItems.isEmpty)
                const Text("No items.")
              else
                ...focusItems.map((it) {
                  final ratio = maxSeconds <= 0 ? 0.0 : (it.seconds / maxSeconds).clamp(0.0, 1.0);
                  final blocked = _isBlockedEntity(kind: it.kind, entity: it.entity);
                  final isDomain = it.kind == "domain";
                  final subtitle = it.subtitle;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: RecorderTokens.space3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isDomain ? Icons.public : Icons.apps, size: 18),
                            const SizedBox(width: RecorderTokens.space2),
                            Expanded(
                              child: Column(
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
                              ),
                            ),
                            const SizedBox(width: RecorderTokens.space2),
                            Text(formatDuration(it.seconds), style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(width: RecorderTokens.space1),
                            IconButton(
                              onPressed: blocked || _rulesLoading
                                  ? null
                                  : () => _blacklistEntity(
                                        kind: it.kind,
                                        entity: it.entity,
                                        displayName: isDomain ? it.entity : it.label,
                                      ),
                              tooltip: blocked ? "Blacklisted" : "Add to blacklist",
                              icon: Icon(blocked ? Icons.block : Icons.block_outlined),
                            ),
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 10,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
          if (audioItems.isNotEmpty) ...[
            const SizedBox(height: RecorderTokens.space4),
            Row(
              children: [
                const Icon(Icons.headphones, size: 18),
                const SizedBox(width: RecorderTokens.space2),
                Expanded(
                  child: Text("Background audio", style: Theme.of(context).textTheme.titleMedium),
                ),
                if ((_audioTotalSeconds ?? widget.block.backgroundSeconds) != null)
                  Text(
                    formatDuration((_audioTotalSeconds ?? widget.block.backgroundSeconds)!),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: RecorderTokens.space2),
            ...audioItems.map((it) {
              final ratio = bgMaxSeconds <= 0 ? 0.0 : (it.seconds / bgMaxSeconds).clamp(0.0, 1.0);
              final blocked = _isBlockedEntity(kind: it.kind, entity: it.entity);
              final subtitle = it.subtitle;
              final icon = it.kind == "app" ? Icons.apps : Icons.public;
              return Padding(
                padding: const EdgeInsets.only(bottom: RecorderTokens.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: RecorderTokens.space2),
                        Expanded(
                          child: Column(
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
                          ),
                        ),
                        const SizedBox(width: RecorderTokens.space2),
                        Text(formatDuration(it.seconds), style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(width: RecorderTokens.space1),
                        IconButton(
                          onPressed: blocked || _rulesLoading
                              ? null
                              : () => _blacklistEntity(
                                    kind: it.kind,
                                    entity: it.entity,
                                    displayName: it.entity,
                                  ),
                          tooltip: blocked ? "Blacklisted" : "Add to blacklist",
                          icon: Icon(blocked ? Icons.block : Icons.block_outlined),
                        ),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 10,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: RecorderTokens.space4),
          Text("Review", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RecorderTokens.space3),
          TextField(controller: _doing, decoration: const InputDecoration(labelText: "Doing (optional)")),
          const SizedBox(height: RecorderTokens.space3),
          TextField(controller: _output, decoration: const InputDecoration(labelText: "Output / Result")),
          const SizedBox(height: RecorderTokens.space3),
          TextField(controller: _next, decoration: const InputDecoration(labelText: "Next (optional)")),
          const SizedBox(height: RecorderTokens.space4),
          Row(
            children: [
              Expanded(child: Text("Tags", style: Theme.of(context).textTheme.titleMedium)),
              OutlinedButton.icon(onPressed: _addTag, icon: const Icon(Icons.add), label: const Text("Add")),
            ],
          ),
          const SizedBox(height: RecorderTokens.space2),
          Wrap(
            spacing: RecorderTokens.space2,
            runSpacing: RecorderTokens.space2,
            children: [
              for (final t in allTags)
                FilterChip(
                  label: Text(t),
                  selected: _tags.contains(t),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _tags.add(t);
                    } else {
                      _tags.remove(t);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: RecorderTokens.space4),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saving || _deleting || _skipSaving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Save"),
                ),
              ),
              const SizedBox(width: RecorderTokens.space3),
              OutlinedButton(
                onPressed: _saving || _deleting || _skipSaving ? null : () => _toggleSkip(skipped: !skipped),
                child: _skipSaving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(skipped ? "Unskip" : "Skip"),
              ),
            ],
          ),
          const SizedBox(height: RecorderTokens.space4),
          const Divider(),
          const SizedBox(height: RecorderTokens.space2),
          Text("Danger zone", style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: RecorderTokens.space2),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: _deleting || _saving || _skipSaving ? null : _deleteBlock,
            icon: const Icon(Icons.delete_forever_outlined),
            label: _deleting ? const Text("Deleting…") : const Text("Delete this block"),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
