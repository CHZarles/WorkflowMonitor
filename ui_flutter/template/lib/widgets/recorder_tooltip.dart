import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

class RecorderTooltip extends StatelessWidget {
  const RecorderTooltip({
    super.key,
    required this.message,
    required this.child,
    this.preferBelow,
  });

  final String message;
  final Widget child;
  final bool? preferBelow;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      preferBelow: preferBelow,
      excludeFromSemantics: defaultTargetPlatform == TargetPlatform.windows,
      child: child,
    );
  }
}
