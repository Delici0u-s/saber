import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/tools/pen.dart';

/// The handles on a [SelectionBox].
enum SelectionHandle {
  topLeft(Alignment.topLeft),
  top(Alignment.topCenter),
  topRight(Alignment.topRight),
  right(Alignment.centerRight),
  bottomRight(Alignment.bottomRight),
  bottom(Alignment.bottomCenter),
  bottomLeft(Alignment.bottomLeft),
  left(Alignment.centerLeft),

  /// On a stem above the top: rotates the selection.
  rotate(Alignment.topCenter);

  new(this.alignment);

  /// Where the handle is on the box (for [rotate], what its stem stands on).
  final Alignment alignment;

  /// Whether dragging it resizes keeping proportions (a corner).
  bool get isCorner => alignment.x != 0 && alignment.y != 0;
}

/// The box around a selection, with handles to resize and rotate it.
///
/// Its handles keep their size on screen whatever the zoom ([pixel]).
@immutable
class SelectionBox {
  const new({
    required this.rect,
    required this.pixel,
    this.rotatable = true,
    this.transform = SelectionTransform.identity,
  });

  /// The selection's bounds before [transform], on the page.
  final Rect rect;

  /// How long a screen pixel is on the page.
  final double pixel;

  /// Whether it has a [SelectionHandle.rotate] handle.
  final bool rotatable;

  /// A resize or rotation being dragged, which the box shows.
  final SelectionTransform transform;

  /// How big handles are drawn (radius), how far from their middle they can
  /// be grabbed, and how far above the top the rotate handle is, in screen
  /// pixels: big enough for a finger.
  static const handleRadius = kMinInteractiveDimension / 8,
      grabRadius = kMinInteractiveDimension / 2,
      rotateStem = kMinInteractiveDimension;

  /// A resized side is never shorter than this, in screen pixels.
  static const minSize = kMinInteractiveDimension;

  /// Space between the selection and its box, in screen pixels, so the
  /// handles don't sit on what's selected.
  static const margin = handleRadius * 2;

  /// The bounds of [strokes] and [images] on the page, or null if both are
  /// empty.
  static Rect? boundsOf(
    Iterable<Stroke> strokes,
    Iterable<EditorImage> images,
  ) {
    Rect? bounds;
    for (final rect in [
      for (final stroke in strokes) stroke.lowQualityPath.getBounds(),
      for (final image in images) image.dstRect,
    ]) {
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    return bounds;
  }

  Iterable<SelectionHandle> get handles =>
      SelectionHandle.values.where((handle) => handle != .rotate || rotatable);

  /// Where [handle] is on the page, moved by [transform].
  Offset handlePosition(SelectionHandle handle) =>
      transform.map(_handleBefore(handle));

  Offset _handleBefore(SelectionHandle handle) => handle == .rotate
      ? rect.topCenter - Offset(0, rotateStem * pixel)
      : handle.alignment.withinRect(rect);

  /// The box's corners, clockwise from the top left, moved by [transform].
  List<Offset> get corners => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ].map(transform.map).toList();

  /// The handle at [point], if any (the nearest, where they're close).
  SelectionHandle? handleAt(Offset point) {
    SelectionHandle? nearest;
    var nearestDistance = grabRadius * pixel;
    for (final handle in handles) {
      final distance = (handlePosition(handle) - point).distance;
      if (distance > nearestDistance) continue;
      nearest = handle;
      nearestDistance = distance;
    }
    return nearest;
  }

  /// What dragging [handle] from [start] to [current] does to the selection.
  SelectionTransform drag(
    SelectionHandle handle,
    Offset start,
    Offset current,
  ) {
    if (handle == .rotate) {
      final center = rect.center;
      final turn = (current - center).direction - (start - center).direction;
      return SelectionTransform(
        origin: center,
        rotation: Ruler.snapAngle(turn),
      );
    }

    // The handle follows the pointer; the opposite side or corner stays.
    final from = _handleBefore(handle);
    final to = from + (current - start);
    final anchor = Alignment(
      -handle.alignment.x,
      -handle.alignment.y,
    ).withinRect(rect);
    final minScale = minSize * pixel / max(rect.width, rect.height);

    if (handle.isCorner) {
      final diagonal = from - anchor;
      final along =
          ((to - anchor).dx * diagonal.dx + (to - anchor).dy * diagonal.dy) /
          diagonal.distanceSquared;
      final scale = max(along, minScale);
      return SelectionTransform(origin: anchor, scaleX: scale, scaleY: scale);
    }
    double scaleAlong(double to, double from, double anchor, double length) =>
        length > 0
        ? max((to - anchor) / (from - anchor), minSize * pixel / length)
        : 1;
    return SelectionTransform(
      origin: anchor,
      scaleX: handle.alignment.x == 0
          ? 1
          : scaleAlong(to.dx, from.dx, anchor.dx, rect.width),
      scaleY: handle.alignment.y == 0
          ? 1
          : scaleAlong(to.dy, from.dy, anchor.dy, rect.height),
    );
  }

  SelectionBox copyWith({
    Rect? rect,
    double? pixel,
    SelectionTransform? transform,
  }) => SelectionBox(
    rect: rect ?? this.rect,
    pixel: pixel ?? this.pixel,
    rotatable: rotatable,
    transform: transform ?? this.transform,
  );
}

/// Scales a selection around [origin] by [scaleX] and [scaleY], then rotates
/// it by [rotation] (radians, clockwise on screen) around it, and scales its
/// strokes' widths by [widthScale].
@immutable
class SelectionTransform {
  const new({
    this.origin = Offset.zero,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this._widthScale,
  });

  static const identity = SelectionTransform();

  final Offset origin;
  final double scaleX, scaleY, rotation;
  final double? _widthScale;

  /// How much stroke widths scale: by default the average of [scaleX] and
  /// [scaleY], so a stretched stroke gets a bit thicker.
  double get widthScale => _widthScale ?? (scaleX + scaleY) / 2;

  bool get isIdentity =>
      scaleX == 1 && scaleY == 1 && rotation == 0 && widthScale == 1;

  /// [point] moved by this transform.
  Offset map(Offset point) {
    final from = point - origin;
    return origin +
        Ruler.rotate(Offset(from.dx * scaleX, from.dy * scaleY), rotation);
  }

  /// This transform as a matrix, e.g. for [Path.transform].
  Float64List get matrix {
    final c = cos(rotation), s = sin(rotation);
    // The linear part, rotation times scale, then the translation that keeps
    // [origin] in place; column by column.
    final a = c * scaleX, b = s * scaleX, d = -s * scaleY, e = c * scaleY;
    return Float64List.fromList([
      a, b, 0, 0, //
      d, e, 0, 0, //
      0, 0, 1, 0, //
      origin.dx - (a * origin.dx + d * origin.dy),
      origin.dy - (b * origin.dx + e * origin.dy),
      0,
      1,
    ]);
  }

  /// [rect] moved by this transform, which mustn't rotate (e.g. an image's
  /// place, as images can't be rotated).
  Rect applyToRect(Rect rect) {
    assert(rotation == 0, "Images can't be rotated");
    return Rect.fromPoints(map(rect.topLeft), map(rect.bottomRight));
  }

  /// A copy of [stroke] moved by this transform, with its width scaled.
  /// A shape (see [StrokeShape.of]) stays one.
  Stroke apply(Stroke stroke) {
    final transformed = switch (StrokeShape.of(stroke)) {
      final shape? => Pen.shapeStroke(stroke, shape.map(map)),
      null =>
        stroke.copy()..replacePoints([
          for (final point in stroke.pointVectors)
            PointVector.fromOffset(
              offset: map(point),
              pressure: point.pressure,
            ),
        ]),
    };
    // The dash pattern is in multiples of the width, so its start scales too.
    return transformed
      ..options.size *= widthScale
      ..lineStyleOffset *= widthScale
      ..markPolygonNeedsUpdating();
  }
}
