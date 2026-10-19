import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/has_size.dart';

/// Picks [Pen.lineStyle], showing each style as a short line.
class LineStylePicker extends StatefulWidget {
  const new({super.key, required this.axis, required this.pen});

  final Axis axis;
  final Pen pen;

  @override
  State<LineStylePicker> createState() => _LineStylePickerState();
}

class _LineStylePickerState extends State<LineStylePicker> {
  /// The size of each style's preview line.
  static const _previewSize = Size(32, 16);

  /// The thickness of the preview lines.
  static const _previewStrokeSize = 2.5;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      children: [
        for (final lineStyle in LineStyle.values)
          _buildOption(lineStyle, colorScheme),
      ],
    );
  }

  Widget _buildOption(LineStyle lineStyle, ColorScheme colorScheme) {
    final selected = widget.pen.lineStyle == lineStyle;
    final color = selected ? colorScheme.secondary : colorScheme.onSurface;
    return IconButton(
      onPressed: () => setState(() => widget.pen.lineStyle = lineStyle),
      isSelected: selected,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? colorScheme.secondary.withValues(alpha: 0.1)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: _name(lineStyle),
      icon: CustomPaint(
        size: _previewSize,
        painter: _LineStylePreviewPainter(lineStyle: lineStyle, color: color),
      ),
    );
  }

  static String _name(LineStyle lineStyle) => switch (lineStyle) {
    .solid => t.editor.penOptions.lineStyles.solid,
    .dashed => t.editor.penOptions.lineStyles.dashed,
    .dotted => t.editor.penOptions.lineStyles.dotted,
    .dashDot => t.editor.penOptions.lineStyles.dashDot,
  };
}

/// Draws a line in [lineStyle] the way a stroke is drawn on the page.
class _LineStylePreviewPainter extends CustomPainter {
  const new({required this.lineStyle, required this.color});

  final LineStyle lineStyle;
  final Color color;

  /// How long to draw the line, at most [available]: whole repeats of the
  /// pattern ending with its first drawn length, so the preview doesn't end
  /// in a stub that looks like another style.
  double _lineLength(double available) {
    final pattern = [
      for (final length in lineStyle.pattern)
        length * _LineStylePickerState._previewStrokeSize,
    ];
    if (pattern.isEmpty) return available;
    final period = pattern.sum;
    final repeats = ((available - pattern.first) / period).floor();
    return repeats * period + pattern.first;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const margin = _LineStylePickerState._previewStrokeSize;
    final length = _lineLength(size.width - 2 * margin);
    final inset = (size.width - length) / 2;
    final y = size.height / 2;
    final stroke =
        Stroke(
            color: color,
            pressureEnabled: false,
            options: StrokeOptions(
              size: _LineStylePickerState._previewStrokeSize,
              thinning: 0,
              simulatePressure: false,
              isComplete: true,
            ),
            pageIndex: 0,
            page: HasSize(size),
            toolId: .ballpointPen,
            lineStyle: lineStyle,
          )
          ..addPoint(Offset(inset, y))
          ..addPoint(Offset(inset + length, y));
    canvas.drawPath(stroke.highQualityPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LineStylePreviewPainter oldDelegate) =>
      lineStyle != oldDelegate.lineStyle || color != oldDelegate.color;
}
