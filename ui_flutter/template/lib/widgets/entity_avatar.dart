import "package:flutter/material.dart";

class EntityAvatar extends StatelessWidget {
  const EntityAvatar({
    super.key,
    required this.kind,
    required this.entity,
    required this.label,
    this.icon,
    this.size = 22,
  });

  final String kind; // "app" | "domain"
  final String entity;
  final String label;
  final IconData? icon;
  final double size;

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

  String? _faviconUrlForDomain(String rawDomain) {
    final d = rawDomain.trim().toLowerCase();
    if (d.isEmpty) return null;
    if (d == "__hidden__") return null;
    if (d.contains(RegExp(r"[\\/\s]"))) return null;
    // Avoid IPv6 / ports; keep it conservative.
    if (d.contains(":")) return null;
    return Uri(scheme: "https", host: d, path: "/favicon.ico").toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final isHidden = entity.trim() == "__hidden__";

    final seed = "${kind.trim().toLowerCase()}:${entity.trim().toLowerCase()}";
    final h = _fnv1a32(seed).abs() % 360;
    final lightness = brightness == Brightness.dark ? 0.30 : 0.86;
    final bg = isHidden
        ? scheme.surfaceContainerHighest
        : HSLColor.fromAHSL(1.0, h.toDouble(), 0.45, lightness).toColor();
    final fg = isHidden
        ? scheme.onSurfaceVariant
        : (bg.computeLuminance() > 0.55 ? Colors.black : Colors.white);

    final effectiveIcon = isHidden ? Icons.visibility_off_outlined : icon;
    final showIcon = effectiveIcon != null && (isHidden || kind == "app");
    final text = kind == "domain" ? _firstGlyph(entity) : _firstGlyph(label);

    final faviconUrl = kind == "domain" && !isHidden ? _faviconUrlForDomain(entity) : null;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.18), width: 1),
        ),
        child: Center(
          child: showIcon
              ? Icon(effectiveIcon, size: (size * 0.58).clamp(14, 18).toDouble(), color: fg)
              : (faviconUrl != null
                  ? ClipOval(
                      child: Image.network(
                        faviconUrl,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _letterFallback(context, text, fg),
                      ),
                    )
                  : _letterFallback(context, text, fg)),
        ),
      ),
    );
  }

  Widget _letterFallback(BuildContext context, String text, Color fg) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
    );
  }
}
