import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../api/core_client.dart";
import "../theme/tokens.dart";
import "../utils/format.dart";

class QuickReviewSheet extends StatefulWidget {
  const QuickReviewSheet({super.key, required this.client, required this.block});

  final CoreClient client;
  final BlockSummary block;

  @override
  State<QuickReviewSheet> createState() => _QuickReviewSheetState();
}

class _QuickReviewSheetState extends State<QuickReviewSheet> {
  late final TextEditingController _doing;
  late final TextEditingController _output;
  late final TextEditingController _next;
  bool _saving = false;
  bool _skipSaving = false;
  final Set<String> _tags = {};

  static const _presetTags = ["Work", "Meeting", "Learning", "Admin", "Life", "Entertainment"];

  @override
  void initState() {
    super.initState();
    _doing = TextEditingController(text: widget.block.review?.doing ?? "");
    _output = TextEditingController(text: widget.block.review?.output ?? "");
    _next = TextEditingController(text: widget.block.review?.next ?? "");
    _tags.addAll(widget.block.review?.tags ?? const []);
  }

  @override
  void dispose() {
    _doing.dispose();
    _output.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final doing = _doing.text.trim();
    final output = _output.text.trim();
    final next = _next.text.trim();

    if (doing.isEmpty && output.isEmpty && next.isEmpty && _tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Write a quick note, or choose Skip.")),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.client.upsertReview(
        ReviewUpsert(
          blockId: widget.block.id,
          skipped: false,
          skipReason: null,
          doing: doing.isEmpty ? null : doing,
          output: output.isEmpty ? null : output,
          next: next.isEmpty ? null : next,
          tags: _tags.toList(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save failed: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSkip({required bool skipped}) async {
    setState(() => _skipSaving = true);
    try {
      final r = widget.block.review;
      await widget.client.upsertReview(
        ReviewUpsert(
          blockId: widget.block.id,
          skipped: skipped,
          skipReason: null,
          doing: r?.doing,
          output: r?.output,
          next: r?.next,
          tags: r?.tags ?? const [],
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final title = "${formatHHMM(widget.block.startTs)}–${formatHHMM(widget.block.endTs)}";
    final top = widget.block.topItems
        .take(3)
        .map((it) => "${displayTopItemName(it)} ${formatDuration(it.seconds)}")
        .join(" · ");
    final skipped = widget.block.review?.skipped == true;

    final allTags = {..._presetTags, ..._tags}.toList();
    allTags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_saving || _skipSaving) return;
          _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_saving || _skipSaving) return;
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
              Text("Quick review", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: RecorderTokens.space1),
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: RecorderTokens.space2),
              Text("Top: $top", style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: RecorderTokens.space4),
              TextField(
                controller: _doing,
                decoration: const InputDecoration(labelText: "Doing (optional)"),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: RecorderTokens.space3),
              TextField(
                controller: _output,
                decoration: const InputDecoration(labelText: "Output / Result"),
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: RecorderTokens.space3),
              TextField(
                controller: _next,
                decoration: const InputDecoration(labelText: "Next (optional)"),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: RecorderTokens.space4),
              Row(
                children: [
                  Expanded(child: Text("Tags", style: Theme.of(context).textTheme.titleMedium)),
                  Text(skipped ? "Skipped" : "", style: Theme.of(context).textTheme.labelMedium),
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
                      onPressed: _saving || _skipSaving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("Save"),
                    ),
                  ),
                  const SizedBox(width: RecorderTokens.space3),
                  OutlinedButton(
                    onPressed: _saving || _skipSaving ? null : () => _toggleSkip(skipped: !skipped),
                    child: _skipSaving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(skipped ? "Unskip" : "Skip"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
