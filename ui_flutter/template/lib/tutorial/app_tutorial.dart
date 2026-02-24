import "dart:async";
import "dart:math";

import "package:flutter/material.dart";

import "../theme/tokens.dart";

class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.beforeShow,
  });

  final String title;
  final String body;
  final GlobalKey? targetKey;
  final Future<void> Function()? beforeShow;
}

class TutorialRunner {
  TutorialRunner({required this.context, required this.steps});

  final BuildContext context;
  final List<TutorialStep> steps;

  final ValueNotifier<int> _index = ValueNotifier<int>(0);
  final Completer<void> _done = Completer<void>();
  OverlayEntry? _entry;
  bool _closing = false;

  Future<void> start() async {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    _entry = OverlayEntry(
      builder: (ctx) {
        return ValueListenableBuilder<int>(
          valueListenable: _index,
          builder: (_, i, __) {
            final step = steps[i];
            return TutorialOverlay(
              step: step,
              index: i,
              total: steps.length,
              onNext: next,
              onBack: back,
              onClose: close,
            );
          },
        );
      },
    );
    overlay.insert(_entry!);
    await _goTo(0);
  }

  Future<void> _goTo(int i) async {
    if (_closing) return;
    if (i < 0 || i >= steps.length) return;
    final step = steps[i];
    try {
      await step.beforeShow?.call();
    } catch (_) {
      // best effort
    }
    _index.value = i;
  }

  Future<void> next() async {
    if (_closing) return;
    final i = _index.value;
    if (i >= steps.length - 1) {
      close();
      return;
    }
    await _goTo(i + 1);
  }

  Future<void> back() async {
    if (_closing) return;
    final i = _index.value;
    if (i <= 0) return;
    await _goTo(i - 1);
  }

  void close() {
    if (_closing) return;
    _closing = true;
    _entry?.remove();
    _entry = null;
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> get done => _done.future;
}

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onClose,
  });

  final TutorialStep step;
  final int index;
  final int total;
  final Future<void> Function() onNext;
  final Future<void> Function() onBack;
  final VoidCallback onClose;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Rect? _target;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateTarget());
  }

  @override
  void didUpdateWidget(covariant TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.targetKey != widget.step.targetKey ||
        oldWidget.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateTarget());
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Rect? _resolveRect(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox) return null;
    if (!ro.hasSize) return null;
    final topLeft = ro.localToGlobal(Offset.zero);
    return topLeft & ro.size;
  }

  void _updateTarget() {
    final key = widget.step.targetKey;
    final next = key == null ? null : _resolveRect(key);
    if (!mounted) return;
    setState(() => _target = next);
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;
    final scheme = Theme.of(context).colorScheme;

    final hole = _target == null
        ? null
        : _target!
            .inflate(10)
            .intersect(Offset.zero & MediaQuery.of(context).size);

    final progress = "${widget.index + 1}/${widget.total}";

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => CustomPaint(
                  painter: _TutorialScrimPainter(
                    hole: hole,
                    holeRadius: 14,
                    scrimColor: Colors.black.withValues(alpha: 0.55),
                    borderColor: scheme.primary.withValues(
                      alpha: 0.55 + 0.35 * _pulse.value,
                    ),
                    borderWidth: 2 + 1.5 * _pulse.value,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: safe.top + RecorderTokens.space3,
            right: RecorderTokens.space3,
            child: IconButton(
              tooltip: "退出教程",
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          Positioned(
            left: RecorderTokens.space4,
            right: RecorderTokens.space4,
            bottom: safe.bottom + RecorderTokens.space4,
            child: SafeArea(
              top: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _TutorialCard(
                  key: ValueKey(widget.index),
                  title: widget.step.title,
                  body: widget.step.body,
                  progress: progress,
                  showBack: widget.index > 0,
                  isLast: widget.index == widget.total - 1,
                  onBack: widget.onBack,
                  onNext: widget.onNext,
                  onClose: widget.onClose,
                ),
              ),
            ),
          ),
          if (hole != null)
            Positioned(
              left: max(RecorderTokens.space4, hole.left),
              top: max(RecorderTokens.space4, hole.top - 26),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RecorderTokens.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    "看这里",
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    super.key,
    required this.title,
    required this.body,
    required this.progress,
    required this.showBack,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.onClose,
  });

  final String title;
  final String body;
  final String progress;
  final bool showBack;
  final bool isLast;
  final Future<void> Function() onBack;
  final Future<void> Function() onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  progress,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: RecorderTokens.space2),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: RecorderTokens.space4),
            Row(
              children: [
                TextButton(
                  onPressed: onClose,
                  child: const Text("跳过"),
                ),
                const Spacer(),
                if (showBack)
                  OutlinedButton(
                    onPressed: onBack,
                    child: const Text("上一步"),
                  ),
                if (showBack) const SizedBox(width: RecorderTokens.space2),
                FilledButton(
                  onPressed: onNext,
                  child: Text(isLast ? "完成" : "下一步"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialScrimPainter extends CustomPainter {
  const _TutorialScrimPainter({
    required this.hole,
    required this.holeRadius,
    required this.scrimColor,
    required this.borderColor,
    required this.borderWidth,
  });

  final Rect? hole;
  final double holeRadius;
  final Color scrimColor;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()..addRect(full);
    if (hole != null) {
      final rrect = RRect.fromRectAndRadius(hole!, Radius.circular(holeRadius));
      path.addRRect(rrect);
      path.fillType = PathFillType.evenOdd;
    }

    canvas.drawPath(path, Paint()..color = scrimColor);

    if (hole != null) {
      final rrect = RRect.fromRectAndRadius(hole!, Radius.circular(holeRadius));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = borderColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TutorialScrimPainter oldDelegate) {
    return oldDelegate.hole != hole ||
        oldDelegate.holeRadius != holeRadius ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}
