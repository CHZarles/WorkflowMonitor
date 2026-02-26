import "dart:typed_data";

import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "mobile_models.dart";
import "mobile_usage.dart";

String formatDurationZh(int seconds) {
  final m = ((seconds + 30) / 60).floor();
  if (m <= 0) return "0 分钟";
  if (m < 60) return "$m 分钟";
  final h = (m / 60).floor();
  final rm = m % 60;
  if (rm == 0) return "$h 小时";
  return "$h 小时 $rm 分钟";
}

class MobileAppIcon extends StatefulWidget {
  const MobileAppIcon({
    super.key,
    required this.packageName,
    required this.label,
    this.size = 22,
  });

  final String packageName;
  final String label;
  final double size;

  @override
  State<MobileAppIcon> createState() => _MobileAppIconState();
}

class _MobileAppIconState extends State<MobileAppIcon> {
  Uint8List? _bytes;
  String? _requestedKey;
  int _sizePx = 0;

  int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  String _firstGlyph(String s) {
    final v = s.trim();
    if (v.isEmpty) return "?";
    final code = v.runes.first;
    return String.fromCharCode(code).toUpperCase();
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final seed = widget.packageName.trim().toLowerCase().isEmpty
        ? widget.label.trim().toLowerCase()
        : widget.packageName.trim().toLowerCase();
    final h = _fnv1a32(seed).abs() % 360;
    final lightness = brightness == Brightness.dark ? 0.30 : 0.86;
    final bg = HSLColor.fromAHSL(1.0, h.toDouble(), 0.45, lightness).toColor();
    final fg = bg.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    final glyph = _firstGlyph(widget.label);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(widget.size * 0.22),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Center(
        child: Text(
          glyph,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final sizePx = (widget.size * dpr).round().clamp(16, 192);
    if (sizePx != _sizePx) {
      _sizePx = sizePx;
      _bytes = null;
      _requestedKey = null;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant MobileAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName == widget.packageName &&
        oldWidget.size == widget.size) {
      return;
    }
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    _sizePx = (widget.size * dpr).round().clamp(16, 192);
    _bytes = null;
    _requestedKey = null;
    _load();
  }

  void _load() {
    final pkg = widget.packageName.trim();
    if (pkg.isEmpty) return;
    final key = "${_sizePx.toString()}:${pkg.toLowerCase()}";
    if (_requestedKey == key) return;
    _requestedKey = key;

    final cached = MobileUsage.instance.peekAppIconBytes(pkg, sizePx: _sizePx);
    final has = MobileUsage.instance.isAppIconCached(pkg, sizePx: _sizePx);
    if (has) {
      if (!mounted) return;
      setState(() => _bytes = cached);
      return;
    }

    MobileUsage.instance.getAppIconBytes(pkg, sizePx: _sizePx).then((bytes) {
      if (!mounted) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: bytes == null || bytes.isEmpty
          ? _fallback(context)
          : ClipRRect(
              borderRadius: BorderRadius.circular(widget.size * 0.22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(widget.size * 0.22),
                ),
                child: Image.memory(
                  bytes,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
    );
  }
}

class MobileTopItemsList extends StatelessWidget {
  const MobileTopItemsList({
    super.key,
    required this.items,
    this.maxItems = 3,
    this.iconSize = 20,
  });

  final List<MobileTopItem> items;
  final int maxItems;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(maxItems).toList();
    if (shown.isEmpty) {
      return Text(
        "（此段没有记录到前台使用情况）",
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _MobileTopItemRow(item: shown[i], iconSize: iconSize),
          if (i != shown.length - 1)
            const SizedBox(height: RecorderTokens.space2),
        ]
      ],
    );
  }
}

class _MobileTopItemRow extends StatelessWidget {
  const _MobileTopItemRow({required this.item, required this.iconSize});

  final MobileTopItem item;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MobileAppIcon(
          packageName: item.id,
          label: item.displayName,
          size: iconSize,
        ),
        const SizedBox(width: RecorderTokens.space3),
        Expanded(
          child: Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: RecorderTokens.space3),
        Text(
          formatDurationZh(item.seconds),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
