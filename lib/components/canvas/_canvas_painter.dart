import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/select_result.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/selection_transform.dart';
import 'package:saber/data/editor/shape_handles.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';

class CanvasPainter extends CustomPainter {
  const new({
    super.repaint,
    this.invert = false,
    required this.strokes,
    required this.laserStrokes,
    required this.currentStroke,
    required this.currentSelection,
    required this.primaryColor,
    required this.page,
    required this.showPageIndicator,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    double? screenScale,
    required this.defaultTextStyle,
  }) : screenScale = screenScale ?? currentScale;

  final bool invert;
  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;
  final Stroke? currentStroke;
  final SelectResult? currentSelection;
  final Color primaryColor;
  final EditorPage page;
  final bool showPageIndicator;
  final int pageIndex;
  final int totalPages;

  /// The zoom level, e.g. for the level of detail of strokes.
  final double currentScale;

  /// How many screen pixels a page unit takes up (the zoom times how much
  /// the page is scaled to fit), for things sized on screen, like the
  /// eraser outline and the selection box.
  final double screenScale;
  final TextStyle defaultTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;

    _drawHighlighterStrokes(canvas, canvasRect);
    _drawNonHighlighterStrokes(canvas);
    _drawTapes(canvas);
    for (final stroke in laserStrokes) _drawLaserStroke(canvas, stroke);
    _drawCurrentStroke(canvas);
    _drawDetectedShape(canvas);
    _drawSelection(canvas);
    _drawEraserOutline(canvas);
    _drawPageIndicator(canvas, size);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return false ||
        // Current stroke is being drawn, so always repaint if present
        (currentStroke != null || oldDelegate.currentStroke != null) ||
        // Laser strokes are always fading out, so always repaint if present
        (laserStrokes.isNotEmpty || oldDelegate.laserStrokes.isNotEmpty) ||
        // Check for any other changes
        invert != oldDelegate.invert ||
        strokes.length != oldDelegate.strokes.length ||
        currentSelection != oldDelegate.currentSelection ||
        primaryColor != oldDelegate.primaryColor ||
        page != oldDelegate.page ||
        showPageIndicator != oldDelegate.showPageIndicator ||
        pageIndex != oldDelegate.pageIndex ||
        totalPages != oldDelegate.totalPages ||
        currentScale != oldDelegate.currentScale ||
        screenScale != oldDelegate.screenScale;
  }

  void _drawHighlighterStrokes(Canvas canvas, Rect canvasRect) {
    final layerPaint = Paint()
      ..blendMode = invert ? BlendMode.lighten : BlendMode.darken
      ..color = Colors.white.withAlpha(Highlighter.alpha);
    bool needToRestoreCanvasLayer = false;

    Color? lastColor;
    for (final stroke in strokes) {
      if (stroke.toolId != .highlighter) continue;

      final color = stroke.color.withValues(alpha: 1).withInversion(invert);

      if (color != lastColor) {
        // new layer for each color
        if (needToRestoreCanvasLayer) canvas.restore();
        canvas.saveLayer(canvasRect, layerPaint);

        needToRestoreCanvasLayer = true;
        lastColor = color;
      }

      canvas.drawPath(_selectPath(stroke), Paint()..color = color);
    }

    if (needToRestoreCanvasLayer) canvas.restore();
  }

  void _drawNonHighlighterStrokes(Canvas canvas) {
    late final paint = Paint();

    for (final stroke in strokes) {
      if (stroke.toolId == .highlighter) continue;
      if (stroke.isTape) continue; // on top, see [_drawTapes]

      var color = stroke.color.withInversion(invert);
      if (currentSelection?.strokes.contains(stroke) ?? false) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }

      paint.color = color;
      paint.shader = null;
      paint.maskFilter = null;
      if (stroke.toolId == .pencil) {
        if (shouldUsePencilShader(stroke.options.size)) {
          // With a shader, only the colour's opacity counts.
          paint.color = Colors.white.withValues(alpha: color.a);
          paint.shader = page.pencilShader
            ..setFloat(0, color.r)
            ..setFloat(1, color.g)
            ..setFloat(2, color.b);
          paint.maskFilter = _getPencilMaskFilter(stroke.options.size);
        } else {
          // Fast imitation of pencil when zoomed out
          final background = invert ? Colors.black : Colors.white;
          paint.color = Color.lerp(
            background,
            color.withValues(alpha: 1),
            0.6,
          )!.withValues(alpha: color.a);
        }
      }

      late final shapePaint = Paint()
        ..color = paint.color
        ..style = .stroke
        ..strokeWidth = stroke.options.size;

      if (stroke is CircleStroke) {
        canvas.drawCircle(stroke.center, stroke.radius, shapePaint);
      } else if (stroke is RectangleStroke) {
        final strokeSize = stroke.options.size;
        canvas.drawRRect(
          RRect.fromRectAndRadius(stroke.rect, Radius.circular(strokeSize / 4)),
          shapePaint,
        );
      } else {
        canvas.drawPath(_selectPath(stroke), paint);
      }
    }
  }

  /// How much darker tape's stripes are than the tape, and how much of its
  /// colour tints revealed tape.
  static const _tapeStripeDarkness = 0.12, _revealedTapeAlpha = 0.15;

  /// Tape, above everything else (see [paintTape]).
  void _drawTapes(Canvas canvas) {
    for (final stroke in strokes) {
      if (!stroke.isTape) continue;
      paintTape(
        canvas,
        _selectPath(stroke),
        color: stroke.color.withInversion(invert),
        width: stroke.options.size,
        revealed: stroke.tapeRevealed,
        outlineWidth: _outlineWidth / screenScale,
      );
    }
  }

  /// Paints tape of [width] filling [path]: opaque [color] with faint
  /// diagonal stripes, or, [revealed] (see [Stroke.tapeRevealed]), a tint
  /// with an outline [outlineWidth] wide.
  static void paintTape(
    Canvas canvas,
    Path path, {
    required Color color,
    required double width,
    bool revealed = false,
    required double outlineWidth,
  }) {
    if (revealed) {
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: _revealedTapeAlpha),
      );
      // Merged first, so the outline doesn't show where the strip's rounded
      // ends overlap it.
      canvas.drawPath(
        Path.combine(.union, path, Path()),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = outlineWidth,
      );
      return;
    }

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 1));
    // Stripes a strip's width apart.
    final bounds = path.getBounds();
    final stripe = Paint()
      ..color = Color.lerp(color, Colors.black, _tapeStripeDarkness)!
      ..strokeWidth = width / 4;
    canvas.save();
    canvas.clipPath(path);
    for (var x = bounds.left - bounds.height; x < bounds.right; x += width) {
      canvas.drawLine(
        Offset(x, bounds.bottom),
        Offset(x + bounds.height, bounds.top),
        stripe,
      );
    }
    canvas.restore();
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    final color = currentStroke!.color.withInversion(invert);
    final paint = Paint();

    paint.color = color;
    paint.shader = null;
    paint.maskFilter = null;
    if (currentStroke!.toolId == .pencil) {
      // With a shader, only the colour's opacity counts.
      paint.color = Colors.white.withValues(alpha: color.a);
      paint.shader = page.pencilShader
        ..setFloat(0, color.r)
        ..setFloat(1, color.g)
        ..setFloat(2, color.b);
      paint.maskFilter = _getPencilMaskFilter(currentStroke!.options.size);
    }

    // Current stroke always uses high quality
    if (currentStroke!.isTape) {
      // Looking like tape while it's drawn.
      return paintTape(
        canvas,
        currentStroke!.highQualityPath,
        color: color,
        width: currentStroke!.options.size,
        outlineWidth: _outlineWidth / screenScale,
      );
    }
    canvas.drawPath(currentStroke!.highQualityPath, paint);
  }

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    canvas.drawPath(
      _selectPath(stroke),
      Paint()
        ..color = stroke.color.withInversion(invert)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.solid,
          stroke.options.size * 0.4,
        ),
    );
    canvas.drawPath(stroke.innerPath, Paint()..color = const Color(0xDDffffff));
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = Pen.detectedShape;
    if (shape == null) return;

    final color = currentStroke?.color.withInversion(invert) ?? Colors.black;
    final size = currentStroke?.options.size ?? 3;
    final shapePaint = Paint()
      ..color = Color.lerp(color, primaryColor, 0.5)!.withValues(alpha: 0.7)
      ..style = .stroke
      ..strokeWidth = size
      ..strokeCap = .round;
    // In the stroke's line style, like the shape it becomes.
    final pattern = [
      for (final length in currentStroke?.lineStyle.pattern ?? const <double>[])
        length * size,
    ];
    void drawPath(Path path) =>
        canvas.drawPath(_inPattern(path, pattern), shapePaint);

    switch (shape.name) {
      case null:
        break;
      case DefaultUnistrokeNames.line:
        var (firstPoint, lastPoint) = shape.convertToLine();
        (firstPoint, lastPoint) = Stroke.snapLine(
          firstPoint is PointVector
              ? firstPoint
              : PointVector.fromOffset(offset: firstPoint),
          lastPoint is PointVector
              ? lastPoint
              : PointVector.fromOffset(offset: lastPoint),
        );
        drawPath(
          Path()
            ..moveTo(firstPoint.dx, firstPoint.dy)
            ..lineTo(lastPoint.dx, lastPoint.dy),
        );
      case DefaultUnistrokeNames.rectangle:
        final rect = shape.convertToRect();
        drawPath(Path()..addRect(rect));
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        drawPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
        );
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = shape.convertToCanonicalPolygon();
        drawPath(Path()..addPolygon(polygon, true));
    }
  }

  /// The parts of [path] that [pattern] draws (see [LineStyle.pattern], in
  /// page units): all of it for an empty pattern. A drawn length of 0 is
  /// a dot, given a round cap.
  static Path _inPattern(Path path, List<double> pattern) {
    if (pattern.isEmpty) return path;
    final pieces = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      for (var i = 0; distance < metric.length; i++) {
        final length = pattern[i % pattern.length];
        if (i.isEven && length > 0) {
          pieces.addPath(
            metric.extractPath(distance, distance + length),
            .zero,
          );
        } else if (i.isEven) {
          // A zero-length line, which the round cap draws as a dot.
          final dot = metric.getTangentForOffset(distance)!.position;
          pieces
            ..moveTo(dot.dx, dot.dy)
            ..lineTo(dot.dx, dot.dy);
        }
        distance += length;
      }
    }
    return pieces;
  }

  /// The fill of the area being selected or the selection box.
  static const _selectionFillAlpha = 0.1;

  void _drawSelection(Canvas canvas) {
    if (currentSelection == null) return;
    // Once selected, the box with handles takes over from the outline.
    if (currentSelection!.box != null) return _drawSelectionBox(canvas);

    // draw translucent fill
    canvas.drawPath(
      currentSelection!.path,
      Paint()..color = primaryColor.withValues(alpha: _selectionFillAlpha),
    );

    // A dashed outline where whatever it touches (or mostly covers) is
    // selected, a solid one where only what's completely inside.
    canvas.drawPath(
      currentSelection!.selectsWhole
          ? currentSelection!.path
          : dashPath(
              currentSelection!.path,
              dashArray: CircularIntervalList([10, 10]),
            ),
      Paint()
        ..color = primaryColor
        ..strokeWidth = 3
        ..style = .stroke,
    );
  }

  /// The box around the selection with its handles, see [SelectionBox].
  void _drawSelectionBox(Canvas canvas) {
    final box = currentSelection?.box?.copyWith(pixel: 1 / screenScale);
    if (box == null) return;
    final pixel = box.pixel;
    final line = Paint()
      ..color = primaryColor
      ..style = .stroke
      ..strokeWidth = _outlineWidth * pixel;

    final dash = _outlineDash * pixel;
    final outline = Path()..addPolygon(box.corners, true);
    canvas.drawPath(
      outline,
      Paint()..color = primaryColor.withValues(alpha: _selectionFillAlpha),
    );
    canvas.drawPath(
      dashPath(outline, dashArray: CircularIntervalList([dash, dash])),
      line,
    );
    if (box.rotatable) {
      canvas.drawLine(
        box.handlePosition(.top),
        box.handlePosition(.rotate),
        line,
      );
    }

    final background = Paint()..color = invert ? Colors.black : Colors.white;
    final radius = SelectionBox.handleRadius * pixel;
    for (final handle in box.handles) {
      final center = box.handlePosition(handle);
      // The rotate handle is filled, so it stands out from the others.
      canvas.drawCircle(
        center,
        radius,
        handle == .rotate ? (Paint()..color = primaryColor) : background,
      );
      canvas.drawCircle(center, radius, line);
    }

    _drawShapeHandles(canvas, line, background);

    // The angle, beside the rotate handle, while rotating.
    final rotation = box.transform.rotation;
    if (rotation == 0) return;
    final label = TextPainter(
      text: TextSpan(
        text: '${(rotation * 180 / pi).round()}°',
        style: TextStyle(
          color: primaryColor,
          fontSize: _angleLabelSize * pixel,
        ),
      ),
      textDirection: .ltr,
    )..layout();
    label.paint(
      canvas,
      box.handlePosition(.rotate) +
          Offset(SelectionBox.grabRadius * pixel, -label.height / 2),
    );
  }

  /// The handles on a selected shape (see [ShapeHandles]): a square on a
  /// corner, a filled circle on a smooth anchor, a small circle in the
  /// middle of a side.
  void _drawShapeHandles(Canvas canvas, Paint line, Paint background) {
    final shape = currentSelection?.shape;
    if (shape == null) return;
    final pixel = 1 / screenScale;
    final fill = Paint()..color = primaryColor;
    for (final (handle, center) in ShapeHandles(
      shape: shape,
      pixel: pixel,
    ).handles) {
      if (handle.middle) {
        final radius = ShapeHandles.middleRadius * pixel;
        canvas.drawCircle(center, radius, background);
        canvas.drawCircle(center, radius, line);
        continue;
      }
      final radius = ShapeHandles.anchorRadius * pixel;
      final smooth = switch (shape) {
        PathShape(:final points) => points[handle.index].smooth,
        EllipseShape() => true,
      };
      if (smooth) {
        canvas.drawCircle(center, radius, fill);
      } else {
        final square = Rect.fromCircle(center: center, radius: radius);
        canvas.drawRect(square, background);
        canvas.drawRect(square, line);
      }
    }
  }

  /// Dash length and line width of the eraser outline and the selection
  /// box, in screen pixels.
  static const double _outlineDash = 4;
  static const _outlineWidth = 1.5;

  /// The size of the angle shown while rotating a selection, in screen
  /// pixels.
  static const _angleLabelSize = 14.0;

  void _drawEraserOutline(Canvas canvas) {
    final outline = page.eraserOutline;
    if (outline == null) return;

    final dash = _outlineDash / screenScale;
    canvas.drawPath(
      dashPath(
        Path()..addOval(
          Rect.fromCircle(center: outline.center, radius: outline.radius),
        ),
        dashArray: CircularIntervalList([dash, dash]),
      ),
      Paint()
        ..color = primaryColor
        ..strokeWidth = _outlineWidth / screenScale
        ..style = .stroke,
    );
  }

  static const double _pageIndicatorFontSize = 20;
  static const double _pageIndicatorPadding = 5;
  void _drawPageIndicator(Canvas canvas, Size pageSize) {
    if (!showPageIndicator) return;

    final style = ui.ParagraphStyle(
      textAlign: .end,
      textDirection: .ltr,
      maxLines: 1,
    );

    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black.withInversion(invert).withValues(alpha: 0.5),
          fontSize: _pageIndicatorFontSize,
          fontFamily: defaultTextStyle.fontFamily,
          fontFamilyFallback: defaultTextStyle.fontFamilyFallback,
        ),
      )
      ..addText('${pageIndex + 1} / $totalPages');

    final paragraph = builder.build();
    paragraph.layout(
      ui.ParagraphConstraints(
        width: pageSize.width - 2 * _pageIndicatorPadding,
      ),
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        _pageIndicatorPadding,
        pageSize.height - _pageIndicatorPadding - _pageIndicatorFontSize * 1.2,
      ),
    );
  }

  static MaskFilter _getPencilMaskFilter(double size) =>
      MaskFilter.blur(BlurStyle.normal, min(size * 0.2, 3));
  bool shouldUsePencilShader(double strokeSize) =>
      currentScale >= _zoomThreshold && (strokeSize * currentScale) >= 3;

  static const _zoomThreshold = 0.9;
  Path _selectPath(Stroke stroke) => switch (currentScale) {
    < _zoomThreshold => stroke.lowQualityPath,
    _ => stroke.highQualityPath,
  };
}
