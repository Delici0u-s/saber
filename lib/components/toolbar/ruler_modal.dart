import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/components/toolbar/tool_mode_button.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// Lets the user pick the [Ruler]'s shape and mark spacing, or hide it.
class RulerModal extends StatelessWidget {
  const new({super.key, required this.ruler, required this.hide});

  final Ruler ruler;

  /// Hides the ruler and this modal.
  final VoidCallback hide;

  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final shapes = t.editor.rulerOptions.shapes;

    return ListenableBuilder(
      listenable: ruler,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (final shape in RulerShape.values)
              ToolModeButton(
                selected: ruler.shape == shape,
                tooltip: switch (shape) {
                  .ruler => shapes.ruler,
                  .trySquare => shapes.trySquare,
                  .setSquare => shapes.setSquare,
                },
                onPressed: () => ruler.shape = shape,
                icon: switch (shape) {
                  .ruler => const Icon(Symbols.straighten),
                  .trySquare => const _TrySquareIcon(),
                  .setSquare => const Icon(Symbols.square_foot),
                },
              ),
            const _MarkSpacingField(),
            IconButton(
              tooltip: t.editor.rulerOptions.hide,
              onPressed: hide,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits [Stows.rulerMarkSpacingMm].
class _MarkSpacingField extends StatefulWidget {
  const new();

  @override
  State<_MarkSpacingField> createState() => _MarkSpacingFieldState();
}

class _MarkSpacingFieldState extends State<_MarkSpacingField> {
  late final controller = TextEditingController(
    text: _format(stows.rulerMarkSpacingMm.value),
  );

  static String _format(double mm) =>
      mm.toString().replaceFirst(RegExp(r'\.0$'), '');

  /// Saves the typed spacing if it's a positive number.
  void _onChanged(String text) {
    final mm = double.tryParse(text.replaceAll(',', '.'));
    if (mm == null || !(mm > 0) || !mm.isFinite) return;
    stows.rulerMarkSpacingMm.value = mm;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.editor.rulerOptions.markSpacing,
      child: IntrinsicWidth(
        child: TextField(
          controller: controller,
          onChanged: _onChanged,
          // Show the saved value again if what's typed wasn't valid.
          onTapOutside: (_) {
            controller.text = _format(stows.rulerMarkSpacingMm.value);
            FocusScope.of(context).unfocus();
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
          ],
          textAlign: .end,
          decoration: InputDecoration(
            isDense: true,
            suffixText: t.editor.rulerOptions.mm,
            labelText: t.editor.rulerOptions.markSpacing,
          ),
        ),
      ),
    );
  }
}

/// An L like [RulerShape.trySquare], sized and coloured like an [Icon].
class _TrySquareIcon extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return CustomPaint(
      size: .square(iconTheme.size!),
      painter: _TrySquareIconPainter(iconTheme.color!),
    );
  }
}

class _TrySquareIconPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  /// The blade's and the stock's widths, as fractions of the icon's size.
  static const _blade = 0.2, _stock = 0.32;

  /// Space around the L, as a fraction of the icon's size (like the padding
  /// in Material icons).
  static const _padding = 0.1;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.shortestSide * _padding);
    final blade = rect.width * _blade, stock = rect.width * _stock;
    canvas.drawPath(
      Path()..addPolygon([
        rect.topLeft,
        rect.topRight,
        rect.topRight + Offset(0, blade),
        rect.topLeft + Offset(stock, blade),
        rect.bottomLeft + Offset(stock, 0),
        rect.bottomLeft,
      ], true),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrySquareIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
