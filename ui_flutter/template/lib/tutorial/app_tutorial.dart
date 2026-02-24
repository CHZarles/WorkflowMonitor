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
    this.targetHint,
    this.allowInteraction = false,
  });

  final String title;
  final String body;
  final GlobalKey? targetKey;
  final Future<void> Function()? beforeShow;
  final String? targetHint;
  final bool allowInteraction;
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
  Timer? _resolveTimer;
  int _resolveAttempts = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startResolve());
  }

  @override
  void didUpdateWidget(covariant TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.targetKey != widget.step.targetKey ||
        oldWidget.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startResolve());
    }
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
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

  void _startResolve() {
    _resolveTimer?.cancel();
    _resolveAttempts = 0;
    _updateTarget();
  }

  void _updateTarget() {
    final key = widget.step.targetKey;
    final next = key == null ? null : _resolveRect(key);
    if (!mounted) return;
    if (next != _target) {
      setState(() => _target = next);
    }

    // If the target hasn't been laid out yet, retry a few times.
    if (next == null && key != null && _resolveAttempts < 24) {
      _resolveAttempts += 1;
      _resolveTimer?.cancel();
      _resolveTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateTarget());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    final hole = _target == null
        ? null
        : _target!.inflate(10).intersect(Offset.zero & size);

    final canTapTarget = hole != null && widget.step.allowInteraction;

    final progress = "${widget.index + 1}/${widget.total}";
    final placeCardTop = hole != null && hole.center.dy >= size.height * 0.58;

    final hint = (widget.step.targetHint ?? "").trim();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => CustomPaint(
                  painter: _TutorialScrimPainter(
                    hole: hole,
                    holeRadius: 14,
                    scrimColor: const Color(0x4A000000),
                    borderColor: scheme.primary.withValues(
                      alpha: 0.55 + 0.35 * _pulse.value,
                    ),
                    borderWidth: 2 + 1.5 * _pulse.value,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: _TutorialBarrier(
              hole: hole,
              allowHoleTapThrough: canTapTarget,
            ),
          ),
          if (hole != null)
            Positioned(
              left: hole.center.dx - 10,
              top: hole.center.dy - 10,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return Opacity(
                      opacity: 0.35 + 0.35 * (1 - t),
                      child: Container(
                        width: 20 + 10 * t,
                        height: 20 + 10 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.85),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Positioned.fill(
            child: SafeArea(
              top: true,
              bottom: true,
              child: Align(
                alignment:
                    placeCardTop ? Alignment.topCenter : Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(RecorderTokens.space4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
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
                        canTapTarget: canTapTarget,
                        hint: hint.isEmpty ? null : hint,
                        onBack: widget.onBack,
                        onNext: widget.onNext,
                        onClose: widget.onClose,
                      ),
                    ),
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
        ],
      ),
    );
  }
}

class _TutorialBarrier extends StatelessWidget {
  const _TutorialBarrier({
    required this.hole,
    required this.allowHoleTapThrough,
  });

  final Rect? hole;
  final bool allowHoleTapThrough;

  Widget _blocker() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (hole == null || !allowHoleTapThrough) {
      return _blocker();
    }

    final size = MediaQuery.of(context).size;
    final h = hole!;

    final topH = h.top.clamp(0.0, size.height).toDouble();
    final bottomTop = h.bottom.clamp(0.0, size.height).toDouble();
    final leftW = h.left.clamp(0.0, size.width).toDouble();
    final rightLeft = h.right.clamp(0.0, size.width).toDouble();

    final holeHeight = h.height.clamp(0.0, size.height).toDouble();
    final rightW = max(0.0, size.width - rightLeft).toDouble();

    return Stack(
      children: [
        if (topH > 0)
          Positioned(
              left: 0, top: 0, right: 0, height: topH, child: _blocker()),
        if (bottomTop < size.height)
          Positioned(
              left: 0, top: bottomTop, right: 0, bottom: 0, child: _blocker()),
        if (leftW > 0 && holeHeight > 0)
          Positioned(
              left: 0,
              top: topH,
              width: leftW,
              height: holeHeight,
              child: _blocker()),
        if (rightW > 0 && holeHeight > 0)
          Positioned(
              left: rightLeft,
              top: topH,
              width: rightW,
              height: holeHeight,
              child: _blocker()),
      ],
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
    required this.canTapTarget,
    required this.hint,
    required this.onBack,
    required this.onNext,
    required this.onClose,
  });

  final String title;
  final String body;
  final String progress;
  final bool showBack;
  final bool isLast;
  final bool canTapTarget;
  final String? hint;
  final Future<void> Function() onBack;
  final Future<void> Function() onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxBodyH = max(120.0, MediaQuery.of(context).size.height * 0.28);
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
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBodyH),
              child: SingleChildScrollView(
                child:
                    Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
            if (hint != null && hint!.trim().isNotEmpty) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      hint!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            if (canTapTarget) ...[
              const SizedBox(height: RecorderTokens.space2),
              Row(
                children: [
                  Icon(Icons.touch_app,
                      size: 16, color: scheme.primary.withValues(alpha: 0.95)),
                  const SizedBox(width: RecorderTokens.space1),
                  Expanded(
                    child: Text(
                      "你可以直接点击高亮区域，看看会发生什么。",
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
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
