import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// Picks [Pen.opacity] with a slider from see-through to the pen's colour,
/// laid out like [SizePicker].
class OpacityPicker extends StatefulWidget {
  const new({super.key, required this.axis, required this.pen});

  final Axis axis;
  final Pen pen;

  /// The most see-through a pen can be, so its strokes stay visible.
  static const minOpacity = 0.1;

  /// The slider moves in steps of this much opacity.
  static const step = 0.05;

  @override
  State<OpacityPicker> createState() => _OpacityPickerState();
}

class _OpacityPickerState extends State<OpacityPicker> {
  /// Sets the opacity [percent] of the way along the slider (clamped).
  void _onDrag(double percent) {
    const min = OpacityPicker.minOpacity, step = OpacityPicker.step;
    final steps = ((1 - min) / step).round();
    final opacity = min + (clampDouble(percent, 0, 1) * steps).round() * step;
    if (opacity == widget.pen.opacity) return;
    setState(() => widget.pen.opacity = opacity);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final horizontal = widget.axis == Axis.horizontal;
    double along(Offset position) =>
        (horizontal ? position.dx : position.dy) / SizePicker.largeLength;

    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      children: [
        Column(
          children: [
            Text(
              t.editor.penOptions.opacity,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1,
              ),
            ),
            Text('${(widget.pen.opacity * 100).round()}%'),
          ],
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const .symmetric(vertical: 8),
          child: GestureDetector(
            onHorizontalDragStart: horizontal
                ? (details) => _onDrag(along(details.localPosition))
                : null,
            onHorizontalDragUpdate: horizontal
                ? (details) => _onDrag(along(details.localPosition))
                : null,
            onVerticalDragStart: horizontal
                ? null
                : (details) => _onDrag(along(details.localPosition)),
            onVerticalDragUpdate: horizontal
                ? null
                : (details) => _onDrag(along(details.localPosition)),
            onTapDown: (details) => _onDrag(along(details.localPosition)),
            child: RotatedBox(
              quarterTurns: horizontal ? 0 : 1,
              child: CustomPaint(
                size: const Size(
                  SizePicker.largeLength,
                  SizePicker.smallLength,
                ),
                painter: _OpacitySliderPainter(
                  color: widget.pen.color.withValues(alpha: 1),
                  opacity: widget.pen.opacity,
                  checkerColor: colorScheme.onSurface.withValues(alpha: 0.15),
                  thumbColor: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OpacitySliderPainter extends CustomPainter {
  const new({
    required this.color,
    required this.opacity,
    required this.checkerColor,
    required this.thumbColor,
  });

  final Color color;
  final double opacity;
  final Color checkerColor;
  final Color thumbColor;

  /// The track's checkerboard has two rows of squares.
  static const _checkerRows = 2;

  /// The thumb's width, as a fraction of the track's height.
  static const _thumbWidth = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.save();
    canvas.clipRRect(track);

    // A checkerboard, so see-through colours look see-through.
    final square = size.height / _checkerRows;
    final checker = Paint()..color = checkerColor;
    for (var row = 0; row < _checkerRows; row++) {
      for (var column = row % 2; column * square < size.width; column += 2) {
        canvas.drawRect(
          Rect.fromLTWH(column * square, row * square, square, square),
          checker,
        );
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: OpacityPicker.minOpacity),
            color,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // The thumb: a bar across the track at the current opacity.
    final ratio =
        (opacity - OpacityPicker.minOpacity) / (1 - OpacityPicker.minOpacity);
    final thumbWidth = size.height * _thumbWidth;
    final x = thumbWidth / 2 + (size.width - thumbWidth) * ratio;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: thumbWidth,
          height: size.height,
        ),
        Radius.circular(thumbWidth / 2),
      ),
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_OpacitySliderPainter oldDelegate) =>
      color != oldDelegate.color ||
      opacity != oldDelegate.opacity ||
      checkerColor != oldDelegate.checkerColor ||
      thumbColor != oldDelegate.thumbColor;
}
