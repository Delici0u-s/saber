import 'package:flutter/material.dart';

/// A round button for picking one of a tool's modes in a toolbar modal,
/// e.g. stroke/area eraser or lasso/box selection.
class ToolModeButton extends StatelessWidget {
  const new({
    super.key,
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final bool selected;
  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// The color for a mode's icon, depending on whether it's [selected].
  static Color iconColor(BuildContext context, {required bool selected}) {
    final colorScheme = ColorScheme.of(context);
    return selected ? colorScheme.secondary : colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return IconButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: iconColor(context, selected: selected),
        backgroundColor: selected
            ? colorScheme.secondary.withAlpha((0.1 * 255).round())
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: tooltip,
      icon: icon,
    );
  }
}
