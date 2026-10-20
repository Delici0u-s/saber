import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';
import 'package:stow_plain/stow_plain.dart';

/// A shape that can be placed by dragging it out (see [ShapePlacer]): from
/// one corner of its box to the other, or along a line. Adding a shape is
/// adding an entry here.
enum ShapeSample {
  line,
  arrow,
  doubleArrow,
  rectangle,
  ellipse,
  triangle,
  parallelogram,
  polygon,
  star,
  axes;

  String get label => switch (this) {
    line => t.editor.shapes.line,
    arrow => t.editor.shapes.arrow,
    doubleArrow => t.editor.shapes.doubleArrow,
    rectangle => t.editor.shapes.rectangle,
    ellipse => t.editor.shapes.ellipse,
    triangle => t.editor.shapes.triangle,
    parallelogram => t.editor.shapes.parallelogram,
    polygon => t.editor.shapes.polygon,
    star => t.editor.shapes.star,
    axes => t.editor.shapes.axes,
  };

  /// Whether it has [corners] to choose (see [Stows.lastShapeCorners]).
  bool get hasCorners => this == polygon || this == star;

  /// The fewest and most corners a polygon or star can have.
  static const minCorners = 3, maxCorners = 12;

  /// How far a star's inner corners are from its middle, relative to its
  /// points.
  static const _starInnerRadius = 0.45;

  /// How far a parallelogram's sides lean, relative to its width.
  static const _parallelogramLean = 0.25;

  static ShapeSample fromJson(String? name) =>
      values.asNameMap()[name] ?? rectangle;

  bool get _isLine => this == line || this == arrow || this == doubleArrow;

  /// The shape dragged from [start] to [end], with [corners] for a polygon
  /// or star. [proportional] makes a line's angle a multiple of 15° and a
  /// box square (a square, circle, regular polygon).
  StrokeShape build(
    Offset start,
    Offset end, {
    bool proportional = false,
    int corners = 5,
  }) {
    if (_isLine) {
      if (proportional) {
        final angle =
            ((end - start).direction / _snapAngle).round() * _snapAngle;
        end = start + Offset.fromDirection(angle, (end - start).distance);
      }
      return PathShape(
        [ShapeAnchor(start), ShapeAnchor(end)],
        startHead: this == doubleArrow,
        endHead: this != line,
      );
    }

    if (proportional) {
      final side = max((end - start).dx.abs(), (end - start).dy.abs());
      end =
          start +
          Offset(
            side * ((end - start).dx < 0 ? -1 : 1),
            side * ((end - start).dy < 0 ? -1 : 1),
          );
    }
    final box = Rect.fromPoints(start, end);
    Offset around(double angle, double scale) =>
        box.center +
        Offset(
          cos(angle) * box.width / 2 * scale,
          sin(angle) * box.height / 2 * scale,
        );
    const top = -pi / 2;
    return switch (this) {
      rectangle => PathShape.polygon([
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ]),
      ellipse => EllipseShape(
        center: box.center,
        u: Offset(box.width / 2, 0),
        v: Offset(0, box.height / 2),
      ),
      triangle => PathShape.polygon([
        box.topCenter,
        box.bottomRight,
        box.bottomLeft,
      ]),
      parallelogram => PathShape.polygon([
        box.topLeft + Offset(box.width * _parallelogramLean, 0),
        box.topRight,
        box.bottomRight - Offset(box.width * _parallelogramLean, 0),
        box.bottomLeft,
      ]),
      polygon => PathShape.polygon([
        for (var i = 0; i < corners; i++) around(top + 2 * pi * i / corners, 1),
      ]),
      star => PathShape.polygon([
        for (var i = 0; i < 2 * corners; i++)
          around(top + pi * i / corners, i.isEven ? 1 : _starInnerRadius),
      ]),
      // The first quadrant's: up and to the right from the bottom left.
      axes => PathShape(
        [
          ShapeAnchor(box.topLeft),
          ShapeAnchor(box.bottomLeft),
          ShapeAnchor(box.bottomRight),
        ],
        startHead: true,
        endHead: true,
      ),
      line || arrow || doubleArrow => throw StateError('A line, see above'),
    };
  }

  /// The angles a line is drawn at while proportional.
  static const _snapAngle = pi / 12;
}

/// Places a [ShapeSample] by dragging it out, with the colour, size, line
/// style and opacity of the pen used last ([Pen.currentPen]).
class ShapePlacer extends Pen {
  new _()
    : super(
        name: t.editor.toolbar.shapes,
        sizeMin: 1,
        sizeMax: 25,
        sizeStep: 1,
        icon: shapesIcon,
        options: Pen.currentPen.options,
        pressureEnabled: false,
        color: Pen.currentPen.color,
        // Like the shape pen's, e.g. no fast ink on Onyx devices, which
        // would draw the drag instead of the shape.
        toolId: .shapePen,
      );

  static final currentPlacer = ShapePlacer._();

  static const shapesIcon = Icons.category_outlined;

  /// The shape placed.
  ShapeSample get sample => .fromJson(stows.lastShapeSample.value);
  set sample(ShapeSample sample) => stows.lastShapeSample.value = sample.name;

  /// How many corners a polygon or star gets.
  int get corners => stows.lastShapeCorners.value.clamp(
    ShapeSample.minCorners,
    ShapeSample.maxCorners,
  );
  set corners(int corners) => stows.lastShapeCorners.value = corners;

  Pen get _pen => Pen.currentPen;

  @override
  Color get color => _pen.color;
  @override
  set color(Color color) => _pen.color = color;

  @override
  StrokeOptions get options => _pen.options;
  @override
  set options(StrokeOptions options) => _pen.options = options;

  @override
  PlainStow<String>? get lineStyleStow => _pen.lineStyleStow;
  @override
  PlainStow<double>? get opacityStow => _pen.opacityStow;

  @override
  ToolId get strokeToolId => _pen.strokeToolId;

  /// Shapes aren't recognised, they're placed.
  @override
  bool get holdsToShape => false;

  /// Where the drag started.
  Offset? _start;

  /// Whether a shape keeps its proportions while placed: with Shift held.
  static bool get _proportional => HardwareKeyboard.instance.isShiftPressed;

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    _start = position;
    super.onDragStart(position, page, pageIndex, pressure);
  }

  /// Reshapes the stroke in place: the canvas draws the one it was given.
  @override
  void onDragUpdate(Offset position, double? pressure) {
    final start = _start;
    final stroke = Pen.currentStroke;
    if (start == null || stroke == null) return;
    if (position == start) {
      // Nothing to place yet: a dot where the drag starts.
      stroke.addPoint(position);
      return;
    }
    stroke.setShape(
      sample.build(
        start,
        position,
        proportional: _proportional,
        corners: corners,
      ),
    );
  }

  /// The placed shape, or null if it was too small to see (e.g. a tap).
  @override
  Stroke? onDragEnd() {
    _start = null;
    final stroke = Pen.currentStroke;
    Pen.currentStroke = null;
    if (stroke == null || stroke.shape == null) return null;
    final bounds = stroke.shape!.anchors.fold<Rect?>(
      null,
      (rect, point) =>
          rect?.expandToInclude(Rect.fromPoints(point, point)) ??
          Rect.fromPoints(point, point),
    )!;
    if (bounds.longestSide < stroke.options.size) return null;
    return stroke;
  }
}
