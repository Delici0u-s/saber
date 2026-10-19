import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A straight edge over the canvas: pen strokes started near one of its
/// edges are drawn along it, and its marks measure in millimetres.
///
/// It lives on the screen, not on a page: it stays put while scrolling and is
/// never saved or exported. Shown by [RulerOverlay].
class Ruler extends ChangeNotifier {
  /// How close to an edge (in logical pixels, on either side of it) a stroke
  /// has to start to be drawn along that edge.
  static const snapDistance = 16.0;

  /// The ruler's width: a grab area in the middle and a [snapDistance] band
  /// inside each edge, which strokes start on instead of moving the ruler.
  static const thickness = kMinInteractiveDimension + 2 * snapDistance;

  /// Rotating snaps to multiples of this angle when within [_snapTolerance].
  static const _snapAngle = pi / 12;
  static const _snapTolerance = pi / 90;

  /// How far one scroll of the mouse wheel rotates the ruler.
  static const _wheelStep = pi / 180;

  bool get visible => _visible;
  var _visible = false;
  set visible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    notifyListeners();
  }

  /// Where the ruler's middle is in [RulerOverlay], or null for the middle of
  /// the overlay. See [centerIn].
  Offset? _center;

  /// The ruler's angle in radians, clockwise from horizontal.
  double get angle => _angle;
  var _angle = 0.0;

  /// Identifies the [RulerOverlay] showing this ruler, to convert between its
  /// coordinates and global ones.
  final overlayKey = GlobalKey();

  /// The ruler's middle in an overlay of [size]: kept inside it, so the ruler
  /// can't get lost off screen (e.g. after the window shrinks).
  Offset centerIn(Size size) => _clamp(_center ?? size.center(.zero), size);

  /// Moves the ruler by [delta] within an overlay of [size].
  void moveBy(Offset delta, Size size) {
    _center = _clamp(centerIn(size) + delta, size);
    notifyListeners();
  }

  static Offset _clamp(Offset point, Size size) =>
      Offset(point.dx.clamp(0, size.width), point.dy.clamp(0, size.height));

  /// Rotates the ruler to [angle], snapping to nearby multiples of 15°
  /// if [snap] is true.
  void rotateTo(double angle, {bool snap = true}) {
    if (snap) {
      final snapped = (angle / _snapAngle).round() * _snapAngle;
      if ((angle - snapped).abs() <= _snapTolerance) angle = snapped;
    }
    _angle = angle;
    notifyListeners();
  }

  /// Rotates the ruler one step per mouse wheel scroll, [down] clockwise.
  void rotateByWheel({required bool down}) =>
      rotateTo(_angle + (down ? _wheelStep : -_wheelStep), snap: false);

  /// The ruler's angle in whole degrees counterclockwise from horizontal,
  /// from 0 to 179 (the ruler looks the same turned by 180°).
  int get displayedDegrees => (-_angle * 180 / pi).round() % 180;

  RenderBox? get _overlayBox {
    final box = overlayKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box;
  }

  /// Where the ruler is, in global coordinates, or null if it isn't shown.
  RulerGeometry? get globalGeometry {
    final box = _overlayBox;
    if (!visible || box == null) return null;
    return RulerGeometry(
      center: box.localToGlobal(centerIn(box.size)),
      angle: angle,
    );
  }

  /// The edge a stroke starting at [globalPosition] is drawn along,
  /// or null if it starts away from the ruler (or the ruler isn't shown).
  RulerEdge? edgeNear(Offset globalPosition) =>
      globalGeometry?.edgeNear(globalPosition);
}

/// Where a [Ruler] is: its middle line runs through [center] at [angle].
@immutable
class RulerGeometry {
  const new({required this.center, required this.angle});

  final Offset center;

  /// In radians, clockwise from horizontal.
  final double angle;

  /// A unit vector along the ruler.
  Offset get direction => Offset(cos(angle), sin(angle));

  /// A unit vector across the ruler, 90° clockwise from [direction].
  Offset get normal => Offset(-sin(angle), cos(angle));

  /// How far [point] is along the ruler from [center].
  double along(Offset point) => _dot(point - center, direction);

  /// How far [point] is across the ruler from its middle line,
  /// positive on the [normal]'s side.
  double across(Offset point) => _dot(point - center, normal);

  /// Whether [point] is on the part of the ruler that moves it,
  /// i.e. on the ruler but not within [Ruler.snapDistance] of an edge.
  bool grabs(Offset point) =>
      across(point).abs() < Ruler.thickness / 2 - Ruler.snapDistance;

  /// The edge within [Ruler.snapDistance] of [point], if any.
  RulerEdge? edgeNear(Offset point) {
    final across = this.across(point);
    if ((across.abs() - Ruler.thickness / 2).abs() > Ruler.snapDistance) {
      return null;
    }
    return RulerEdge(ruler: this, side: across.sign);
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
}

/// One of the long edges of a [Ruler].
@immutable
class RulerEdge {
  const new({required this.ruler, required this.side});

  final RulerGeometry ruler;

  /// 1 for the edge on the [RulerGeometry.normal]'s side, -1 for the other.
  final double side;

  /// [point] moved straight onto this edge, then [gap] further away from the
  /// ruler (e.g. half a stroke's width, so the stroke touches the edge).
  Offset project(Offset point, {double gap = 0}) =>
      ruler.center +
      ruler.direction * ruler.along(point) +
      ruler.normal * (side * (Ruler.thickness / 2 + gap));
}

/// Shows [ruler] over the canvas when it's [Ruler.visible].
///
/// Drag it to move it; rotate it with two fingers, a trackpad or the mouse
/// wheel. Pointers near its edges pass through to the canvas.
class RulerOverlay extends StatefulWidget {
  const new({
    super.key,
    required this.ruler,
    required this.zoom,
    required this.pixelsPerMm,
  });

  final Ruler ruler;

  /// Notifies when the zoom level, and so [pixelsPerMm], changes.
  final Listenable zoom;

  /// How long a millimetre on the page is on screen, in logical pixels.
  final double Function() pixelsPerMm;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  /// The ruler's angle when the current gesture started.
  var _angleAtStart = 0.0;

  @override
  Widget build(BuildContext context) {
    final ruler = widget.ruler;
    return ListenableBuilder(
      listenable: Listenable.merge([ruler, widget.zoom]),
      builder: (context, _) {
        if (!ruler.visible) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => ruler.rotateByWheel(down: event.scrollDelta.dy > 0),
                );
              },
              child: GestureDetector(
                onScaleStart: (_) => _angleAtStart = ruler.angle,
                onScaleUpdate: (details) {
                  ruler.moveBy(details.focalPointDelta, size);
                  if (details.rotation != 0) {
                    ruler.rotateTo(_angleAtStart + details.rotation);
                  }
                },
                child: CustomPaint(
                  key: ruler.overlayKey,
                  size: size,
                  painter: _RulerPainter(
                    geometry: RulerGeometry(
                      center: ruler.centerIn(size),
                      angle: ruler.angle,
                    ),
                    degrees: ruler.displayedDegrees,
                    pixelsPerMm: widget.pixelsPerMm(),
                    colorScheme: ColorScheme.of(context),
                    textStyle: TextTheme.of(context).labelSmall!,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  const new({
    required this.geometry,
    required this.degrees,
    required this.pixelsPerMm,
    required this.colorScheme,
    required this.textStyle,
  });

  final RulerGeometry geometry;
  final int degrees;
  final double pixelsPerMm;
  final ColorScheme colorScheme;
  final TextStyle textStyle;

  /// Opacity of the ruler's body, so the page shows through it.
  static const _bodyOpacity = 0.75;

  /// Lengths of the marks every millimetre, half centimetre and centimetre,
  /// as fractions of [Ruler.thickness] (each edge has its own marks).
  static const _mmMark = 0.08, _halfCmMark = 0.13, _cmMark = 0.2;

  /// Marks closer together than this (in logical pixels) are left out.
  static const _minMarkGap = 4.0;

  /// Space between centimetre labels, as a multiple of the widest label.
  static const _labelSpacing = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    // How far the screen reaches along the ruler, so it's drawn end to end.
    final corners = [
      Offset.zero,
      size.topRight(.zero),
      size.bottomLeft(.zero),
      size.bottomRight(.zero),
    ].map(geometry.along);
    final start = corners.reduce(min), end = corners.reduce(max);

    canvas.save();
    canvas.translate(geometry.center.dx, geometry.center.dy);
    canvas.rotate(geometry.angle);

    const halfThickness = Ruler.thickness / 2;
    final body = Rect.fromLTRB(start, -halfThickness, end, halfThickness);
    canvas.drawRect(
      body,
      Paint()..color = colorScheme.surface.withValues(alpha: _bodyOpacity),
    );
    final linePaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 1;
    canvas.drawLine(body.topLeft, body.topRight, linePaint);
    canvas.drawLine(body.bottomLeft, body.bottomRight, linePaint);

    _paintMarks(canvas, start, end, linePaint);

    canvas.restore();
  }

  void _paintMarks(Canvas canvas, double start, double end, Paint linePaint) {
    const halfThickness = Ruler.thickness / 2;
    final mmStep = switch (pixelsPerMm) {
      >= _minMarkGap => 1,
      _ when pixelsPerMm * 5 >= _minMarkGap => 5,
      _ => 10,
    };
    // Centimetres between labels, so the widest label fits with space around.
    final maxCm = max(start.abs(), end.abs()) / (pixelsPerMm * 10);
    final widestLabel = _label('${maxCm.floor()}').width;
    final labelGap = widestLabel * (_labelSpacing - 1);
    var cmPerLabel = 1;
    while (cmPerLabel * pixelsPerMm * 10 < widestLabel + labelGap) {
      cmPerLabel *= 2;
    }

    // The angle, on the 0 mark, with the body's colour behind it.
    final angle = _label('$degrees°');
    final angleBox = Rect.fromCenter(
      center: .zero,
      width: angle.width + labelGap,
      height: angle.height,
    );

    for (
      var mm = (start / pixelsPerMm / mmStep).ceil() * mmStep;
      mm * pixelsPerMm <= end;
      mm += mmStep
    ) {
      final x = mm * pixelsPerMm;
      final length = switch (mm) {
        0 => halfThickness,
        _ when mm % 10 == 0 => Ruler.thickness * _cmMark,
        _ when mm % 5 == 0 => Ruler.thickness * _halfCmMark,
        _ => Ruler.thickness * _mmMark,
      };
      canvas.drawLine(
        Offset(x, -halfThickness),
        Offset(x, -halfThickness + length),
        linePaint,
      );
      canvas.drawLine(
        Offset(x, halfThickness),
        Offset(x, halfThickness - length),
        linePaint,
      );

      if (mm % (10 * cmPerLabel) != 0) continue;
      final label = _label('${mm.abs() ~/ 10}');
      if (x.abs() - label.width / 2 < angleBox.width / 2 + labelGap) continue;
      label.paint(canvas, Offset(x - label.width / 2, -label.height / 2));
    }

    canvas.drawRect(angleBox, Paint()..color = colorScheme.surface);
    angle.paint(canvas, Offset(-angle.width / 2, -angle.height / 2));
  }

  TextPainter _label(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: textStyle.copyWith(color: colorScheme.onSurface),
    ),
    textDirection: .ltr,
  )..layout();

  @override
  bool? hitTest(Offset position) => geometry.grabs(position);

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      geometry.center != oldDelegate.geometry.center ||
      geometry.angle != oldDelegate.geometry.angle ||
      pixelsPerMm != oldDelegate.pixelsPerMm ||
      colorScheme != oldDelegate.colorScheme ||
      textStyle != oldDelegate.textStyle;
}
