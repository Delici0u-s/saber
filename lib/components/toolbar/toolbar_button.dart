import 'package:flutter/material.dart';

class ToolbarIconButton extends StatelessWidget {
  const new({
    super.key,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    required this.onPressed,
    required this.padding,
    required this.child,
  });

  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  final EdgeInsets padding;
  final Widget child;

  /// The icon's size and the space around it inside the button.
  static const iconSize = 20.0, innerPadding = 8.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final backgroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) ||
          !states.contains(WidgetState.selected)) {
        return Colors.transparent;
      }
      return colorScheme.primary;
    });
    final foregroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.selected)) {
        return colorScheme.onPrimary;
      }
      return colorScheme.primary;
    });
    final buttonStyle = ButtonStyle(
      backgroundColor: backgroundColor,
      iconColor: foregroundColor,
      foregroundColor: foregroundColor,
      iconSize: const WidgetStatePropertyAll(iconSize),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(innerPadding)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Padding(
      padding: padding,
      child: IconButton.filled(
        style: buttonStyle,
        onPressed: (enabled) ? onPressed : null,
        tooltip: tooltip,
        isSelected: selected,
        icon: child,
      ),
    );
  }
}
