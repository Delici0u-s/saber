import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/line_style_picker.dart';
import 'package:saber/components/toolbar/opacity_picker.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/tool_mode_button.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_placer.dart';
import 'package:saber/i18n/strings.g.dart';

/// The options of [ShapePlacer]: which shape (each shown as itself), how
/// many corners a polygon or star has, and the size, line style and
/// opacity of the pen it draws with.
class ShapesBar extends StatefulWidget {
  const new({super.key});

  @override
  State<ShapesBar> createState() => _ShapesBarState();
}

class _ShapesBarState extends State<ShapesBar> {
  ShapePlacer get _placer => ShapePlacer.currentPlacer;

  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    // The pen's own, so its settings are saved with it.
    final pen = Pen.currentPen;
    final sample = _placer.sample;
    return Flex(
      direction: axis,
      mainAxisAlignment: .center,
      children: [
        for (final option in ShapeSample.values)
          ToolModeButton(
            selected: option == sample,
            tooltip: option.label,
            onPressed: () => setState(() => _placer.sample = option),
            icon: _ShapeIcon(
              sample: option,
              corners: _placer.corners,
              color: ToolModeButton.iconColor(
                context,
                selected: option == sample,
              ),
            ),
          ),
        if (sample.hasCorners) ...[
          const SizedBox.square(dimension: 8),
          _CornersPicker(
            axis: axis,
            corners: _placer.corners,
            onChanged: (corners) => setState(() => _placer.corners = corners),
          ),
        ],
        const SizedBox.square(dimension: 8),
        SizePicker(axis: axis, pen: pen),
        if (pen.lineStyleStow != null) ...[
          const SizedBox.square(dimension: 8),
          LineStylePicker(axis: axis, pen: pen),
        ],
        if (pen.opacityStow != null) ...[
          const SizedBox.square(dimension: 8),
          OpacityPicker(axis: axis, pen: pen),
        ],
      ],
    );
  }
}

/// [sample] drawn as an icon: the shape itself, as it's placed.
class _ShapeIcon extends StatelessWidget {
  const new({required this.sample, required this.corners, required this.color});

  final ShapeSample sample;
  final int corners;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = IconTheme.of(context).size ?? kDefaultFontSize;
    return CustomPaint(
      size: Size.square(size),
      painter: _ShapeIconPainter(
        sample: sample,
        corners: corners,
        color: color,
      ),
    );
  }
}

class _ShapeIconPainter extends CustomPainter {
  const new({required this.sample, required this.corners, required this.color});

  final ShapeSample sample;
  final int corners;
  final Color color;

  /// The line width, relative to the icon's size.
  static const _lineWidth = 1 / 14;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.shortestSide * _lineWidth;
    // Inset, so the line (and arrow heads) stay inside.
    final box = (Offset.zero & size).deflate(width * 2);
    // Dragged across the box: a line goes diagonally up, the rest fills it.
    final shape = sample.build(box.bottomLeft, box.topRight, corners: corners);
    final outline = shape.outline(width);
    canvas.drawPath(
      Path()..addPolygon(outline, false),
      Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = width
        ..strokeJoin = .round
        ..strokeCap = .round,
    );
  }

  @override
  bool shouldRepaint(_ShapeIconPainter oldDelegate) =>
      sample != oldDelegate.sample ||
      corners != oldDelegate.corners ||
      color != oldDelegate.color;
}

/// How many corners a polygon or star has, with buttons for one less or
/// one more.
class _CornersPicker extends StatelessWidget {
  const new({
    required this.axis,
    required this.corners,
    required this.onChanged,
  });

  final Axis axis;
  final int corners;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Flex(
      direction: axis,
      mainAxisSize: .min,
      children: [
        IconButton(
          tooltip: t.editor.shapes.corners,
          onPressed: corners > ShapeSample.minCorners
              ? () => onChanged(corners - 1)
              : null,
          icon: const Icon(Icons.remove),
        ),
        Column(
          mainAxisSize: .min,
          children: [
            Text(
              t.editor.shapes.corners,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1,
              ),
            ),
            Text('$corners'),
          ],
        ),
        IconButton(
          tooltip: t.editor.shapes.corners,
          onPressed: corners < ShapeSample.maxCorners
              ? () => onChanged(corners + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
