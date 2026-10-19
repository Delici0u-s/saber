import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';

/// The shapes a [Ruler] can take.
///
/// Saved by [name], so values can be reordered but not renamed.
enum RulerShape {
  /// A straight edge as long as the screen.
  ruler(symmetry: pi),

  /// An L of a thick stock and a thin blade at 90°, like a machinist's square.
  trySquare(symmetry: 2 * pi),

  /// A right isosceles triangle with a mm scale on its long edge, centred on
  /// a protractor (a Geodreieck).
  setSquare(symmetry: 2 * pi);

  new({required this.symmetry});

  /// The smallest rotation that makes the shape look the same.
  final double symmetry;

  /// The shape saved as [json] (its [name]), or [ruler] if unknown.
  static RulerShape fromJson(Object? json) =>
      values.asNameMap()[json] ?? .ruler;
}

/// Sizes a [RulerOutline] is laid out with.
typedef RulerDimensions = ({
  /// See [Stows.rulerSnapDistance].
  double snapDistance,

  /// The hole and outside of the rotation ring, see [RulerOutline.ringInner].
  double ringInner,
  double ringOuter,

  /// The screen area the ruler is shown in.
  Size overlay,
});

/// A scale of marks along a side of a [RulerOutline], in its coordinates.
typedef RulerScale = ({
  /// Where the scale's 0 is, on the side.
  Offset origin,

  /// A unit vector along the side, towards positive values.
  Offset direction,

  /// A unit vector from the side into the ruler, where marks are drawn.
  Offset inward,

  /// The part of the side with marks, as distances from [origin].
  double from,
  double to,

  /// Whether the marks have labels (otherwise they're only lines).
  bool labeled,
});

/// The shape of a [Ruler] at a size, in its own coordinates: the rotation ring
/// is at the origin and the ruler's angle is 0.
@immutable
class RulerOutline {
  const new({
    required this.corners,
    required this.ringInner,
    required this.ringOuter,
    required this.scales,
    this.protractor,
  });

  /// The outline, clockwise on screen. Strokes snap to each of its sides.
  final List<Offset> corners;

  /// Radii of the rotation ring around the origin: the angle shows in its
  /// hole, and dragging the ring rotates the ruler.
  final double ringInner, ringOuter;

  final List<RulerScale> scales;

  /// The centre and radius of a protractor's degree marks, if any.
  final ({Offset center, double radius})? protractor;

  /// The width of a [RulerShape.ruler] and the blade of a
  /// [RulerShape.trySquare]: a grab area between two snap bands.
  static double barWidth(double snapDistance) =>
      kMinInteractiveDimension + 2 * snapDistance;

  /// A [RulerShape.trySquare]'s blade and a [RulerShape.setSquare]'s long
  /// side, as fractions of the overlay's shorter side.
  static const _bladeOfScreen = 0.6, _setSquareOfScreen = 0.9;

  /// A [RulerShape.trySquare]'s stock, as a fraction of its blade.
  static const _stockOfBlade = 0.6;

  factory of(RulerShape shape, RulerDimensions dimensions) {
    final (:snapDistance, :ringInner, :ringOuter, :overlay) = dimensions;
    final bar = barWidth(snapDistance);
    // Room for the ring with a snap band around it.
    final ringRoom = ringOuter + snapDistance;

    switch (shape) {
      case .ruler:
        // The ring stays on screen, so this reaches past every screen edge.
        final reach = overlay.longestSide * 2 + bar;
        return RulerOutline(
          corners: [
            Offset(-reach, -bar / 2),
            Offset(reach, -bar / 2),
            Offset(reach, bar / 2),
            Offset(-reach, bar / 2),
          ],
          ringInner: ringInner,
          ringOuter: ringOuter,
          scales: [
            (
              origin: Offset(0, -bar / 2),
              direction: const Offset(1, 0),
              inward: const Offset(0, 1),
              from: -reach,
              to: reach,
              labeled: true,
            ),
            (
              origin: Offset(0, bar / 2),
              direction: const Offset(1, 0),
              inward: const Offset(0, -1),
              from: -reach,
              to: reach,
              labeled: false,
            ),
          ],
        );

      case .trySquare:
        // The outer corner at (0, 0), the blade along x and the stock along y,
        // with the ring in the stock below the blade.
        final stockWidth = 2 * ringRoom;
        final bladeLength = max(
          overlay.shortestSide * _bladeOfScreen,
          stockWidth + bar,
        );
        final stockLength = max(
          bladeLength * _stockOfBlade,
          bar + 2 * ringRoom,
        );
        final ring = Offset(stockWidth / 2, (bar + stockLength) / 2);
        Offset at(double x, double y) => Offset(x, y) - ring;
        return RulerOutline(
          corners: [
            at(0, 0),
            at(bladeLength, 0),
            at(bladeLength, bar),
            at(stockWidth, bar),
            at(stockWidth, stockLength),
            at(0, stockLength),
          ],
          ringInner: ringInner,
          ringOuter: ringOuter,
          scales: [
            (
              origin: at(0, 0),
              direction: const Offset(1, 0),
              inward: const Offset(0, 1),
              from: 0,
              to: bladeLength,
              labeled: true,
            ),
            (
              origin: at(0, 0),
              direction: const Offset(0, 1),
              inward: const Offset(1, 0),
              from: 0,
              to: stockLength,
              labeled: true,
            ),
          ],
        );

      case .setSquare:
        // The long side on top, its middle above the ring, and the right
        // angle below. The protractor fits between the ring and the short
        // sides, which are length / (2√2) from the middle.
        final minLength = 2 * sqrt2 * (2 * ringRoom + snapDistance);
        final length = max(
          overlay.shortestSide * _setSquareOfScreen,
          minLength,
        );
        final middle = Offset(0, -ringRoom);
        return RulerOutline(
          corners: [
            middle + Offset(-length / 2, 0),
            middle + Offset(length / 2, 0),
            middle + Offset(0, length / 2),
          ],
          ringInner: ringInner,
          ringOuter: ringOuter,
          scales: [
            (
              origin: middle,
              direction: const Offset(1, 0),
              inward: const Offset(0, 1),
              from: -length / 2,
              to: length / 2,
              labeled: true,
            ),
          ],
          protractor: (
            center: middle,
            radius: length / (2 * sqrt2) - snapDistance,
          ),
        );
    }
  }

  /// The sides of the outline, clockwise.
  Iterable<RulerEdge> get sides sync* {
    for (var i = 0; i < corners.length; i++) {
      yield RulerEdge(
        start: corners[i],
        end: corners[(i + 1) % corners.length],
      );
    }
  }

  Path get path => Path()..addPolygon(corners, true);

  /// Whether [point] is in the rotation ring.
  bool inRing(Offset point) {
    final distance = point.distance;
    return distance >= ringInner && distance <= ringOuter;
  }

  /// Whether [point] is on the part of the ruler that moves it: inside it, but
  /// not in the ring or within [snapDistance] of a side.
  bool grabs(Offset point, double snapDistance) {
    if (inRing(point)) return false;
    if (point.distance < ringInner) return true;
    if (!path.contains(point)) return false;
    return sides.every((side) => side.distanceTo(point) > snapDistance);
  }

  /// The side nearest to [point] if it's within [snapDistance] of it (on
  /// either side) and not in the ring, otherwise null.
  RulerEdge? edgeNear(Offset point, double snapDistance) {
    if (point.distance <= ringOuter) return null;
    RulerEdge? nearest;
    var nearestDistance = snapDistance;
    for (final side in sides) {
      final distance = side.distanceTo(point);
      if (distance > nearestDistance) continue;
      nearest = side;
      nearestDistance = distance;
    }
    return nearest;
  }
}

/// A side of a [RulerOutline], from [start] to [end] (clockwise around it).
@immutable
class RulerEdge {
  const new({required this.start, required this.end});

  final Offset start, end;

  Offset get _direction => (end - start) / (end - start).distance;

  /// A unit vector away from the ruler: to the left of the side's direction,
  /// as the outline runs clockwise on screen.
  Offset get outward => Offset(_direction.dy, -_direction.dx);

  /// The point of the side closest to [point].
  Offset closestPoint(Offset point) {
    final length = (end - start).distance;
    final along = _dot(point - start, _direction).clamp(0.0, length);
    return start + _direction * along;
  }

  double distanceTo(Offset point) => (point - closestPoint(point)).distance;

  /// [point] moved onto the side, then [gap] further away from the ruler
  /// (e.g. half a stroke's width, so the stroke touches the side).
  Offset project(Offset point, {double gap = 0}) =>
      closestPoint(point) + outward * gap;

  @override
  bool operator ==(Object other) =>
      other is RulerEdge && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
}

/// A straight edge over the canvas: pen strokes started near one of its
/// sides are drawn along it, and its marks measure in millimetres.
///
/// It lives on the screen, not on a page: it stays put while scrolling and is
/// never saved or exported. Shown by [RulerOverlay].
class Ruler extends ChangeNotifier {
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

  RulerShape get shape => .fromJson(stows.lastRulerShape.value);
  set shape(RulerShape shape) {
    stows.lastRulerShape.value = shape.name;
    notifyListeners();
  }

  /// Where the ring is in [RulerOverlay], or null for the middle of the
  /// overlay. See [centerIn].
  Offset? _center;

  /// The ruler's angle in radians, clockwise from horizontal.
  double get angle => _angle;
  var _angle = 0.0;

  /// The ruler's [shape] as last laid out by [RulerOverlay].
  RulerOutline? outline;

  /// Identifies the [RulerOverlay] showing this ruler, to convert between its
  /// coordinates and global ones.
  final overlayKey = GlobalKey();

  /// The ring's position in an overlay of [size]: kept inside it, so the
  /// ruler can't get lost off screen (e.g. after the window shrinks).
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
  /// below the [RulerShape.symmetry] of its shape.
  int get displayedDegrees =>
      (-_angle * 180 / pi).round() % (shape.symmetry * 180 / pi).round();

  /// [point], given in an overlay of [size], in the ruler's own coordinates
  /// (see [RulerOutline]).
  Offset toRuler(Offset point, Size size) =>
      rotate(point - centerIn(size), -angle);

  /// [point], given in the ruler's own coordinates, in an overlay of [size].
  Offset fromRuler(Offset point, Size size) =>
      rotate(point, angle) + centerIn(size);

  /// [point] rotated by [angle] around the origin, clockwise on screen.
  static Offset rotate(Offset point, double angle) => Offset(
    point.dx * cos(angle) - point.dy * sin(angle),
    point.dx * sin(angle) + point.dy * cos(angle),
  );

  RenderBox? get _overlayBox {
    final box = overlayKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box;
  }

  /// The side a stroke starting at [globalPosition] is drawn along,
  /// or null if it starts away from the ruler (or the ruler isn't shown).
  RulerSnap? edgeNear(Offset globalPosition) {
    final box = _overlayBox;
    final outline = this.outline;
    if (!visible || box == null || outline == null) return null;
    final edge = outline.edgeNear(
      toRuler(box.globalToLocal(globalPosition), box.size),
      stows.rulerSnapDistance.value,
    );
    if (edge == null) return null;
    return RulerSnap._(this, box, edge);
  }
}

/// A [RulerEdge] of a [Ruler] that a stroke is drawn along.
class RulerSnap {
  new _(this._ruler, this._box, this.edge);

  final Ruler _ruler;
  final RenderBox _box;
  final RulerEdge edge;

  /// [globalPosition] moved onto [edge], see [RulerEdge.project].
  Offset project(Offset globalPosition, {double gap = 0}) {
    final size = _box.size;
    final local = _ruler.toRuler(_box.globalToLocal(globalPosition), size);
    return _box.localToGlobal(
      _ruler.fromRuler(edge.project(local, gap: gap), size),
    );
  }
}

/// Shows [ruler] over the canvas when it's [Ruler.visible].
///
/// Drag it to move it; rotate it by dragging its ring, with two fingers,
/// a trackpad or the mouse wheel. Pointers near its sides pass through to the
/// canvas.
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

  /// Width of the rotation ring, and space between it and the angle.
  static const _ringWidth = kMinInteractiveDimension / 2;
  static const _ringPadding = 4.0;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  /// The ruler's angle when the current gesture started.
  var _angleAtStart = 0.0;

  /// The pointer's direction from the ring when dragging the ring started,
  /// or null if the current gesture isn't on the ring.
  double? _ringDirectionAtStart;

  @override
  Widget build(BuildContext context) {
    final ruler = widget.ruler;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ruler,
        widget.zoom,
        stows.rulerSnapDistance,
        stows.rulerMarkSpacingMm,
      ]),
      builder: (context, _) {
        if (!ruler.visible) return const SizedBox.shrink();
        final colorScheme = ColorScheme.of(context);
        final textStyle = TextTheme.of(context).labelSmall!
            .copyWith(color: colorScheme.onSurface);

        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final snapDistance = stows.rulerSnapDistance.value;
            final widestAngle = _layOutText(
              '${(ruler.shape.symmetry * 180 / pi).round() - 1}°',
              textStyle,
            ).width;
            final ringInner = widestAngle / 2 + RulerOverlay._ringPadding;
            final outline = ruler.outline = RulerOutline.of(ruler.shape, (
              snapDistance: snapDistance,
              ringInner: ringInner,
              ringOuter: ringInner + RulerOverlay._ringWidth,
              overlay: size,
            ));

            return Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => ruler.rotateByWheel(down: event.scrollDelta.dy > 0),
                );
              },
              child: GestureDetector(
                onScaleStart: (details) {
                  _angleAtStart = ruler.angle;
                  final onRing =
                      details.pointerCount == 1 &&
                      outline.inRing(
                        ruler.toRuler(details.localFocalPoint, size),
                      );
                  _ringDirectionAtStart = onRing
                      ? (details.localFocalPoint - ruler.centerIn(size))
                            .direction
                      : null;
                },
                onScaleUpdate: (details) {
                  if (_ringDirectionAtStart case final directionAtStart?) {
                    final direction =
                        (details.localFocalPoint - ruler.centerIn(size))
                            .direction;
                    ruler.rotateTo(
                      _angleAtStart + direction - directionAtStart,
                    );
                    return;
                  }
                  ruler.moveBy(details.focalPointDelta, size);
                  if (details.rotation != 0) {
                    ruler.rotateTo(_angleAtStart + details.rotation);
                  }
                },
                onScaleEnd: (_) => _ringDirectionAtStart = null,
                child: CustomPaint(
                  key: ruler.overlayKey,
                  size: size,
                  painter: _RulerPainter(
                    outline: outline,
                    center: ruler.centerIn(size),
                    angle: ruler.angle,
                    degrees: ruler.displayedDegrees,
                    snapDistance: snapDistance,
                    pixelsPerMm: widget.pixelsPerMm(),
                    markSpacingMm: stows.rulerMarkSpacingMm.value,
                    colorScheme: colorScheme,
                    textStyle: textStyle,
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

TextPainter _layOutText(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: .ltr,
)..layout();

class _RulerPainter extends CustomPainter {
  const new({
    required this.outline,
    required this.center,
    required this.angle,
    required this.degrees,
    required this.snapDistance,
    required this.pixelsPerMm,
    required this.markSpacingMm,
    required this.colorScheme,
    required this.textStyle,
  });

  final RulerOutline outline;
  final Offset center;
  final double angle;
  final int degrees;
  final double snapDistance;
  final double pixelsPerMm;
  final double markSpacingMm;
  final ColorScheme colorScheme;
  final TextStyle textStyle;

  /// Opacity of the ruler's body, so the page shows through it.
  static const _bodyOpacity = 0.75;

  /// Opacity of the rotation ring.
  static const _ringOpacity = 0.3;

  /// Lengths of every mark, every 5th and every 10th, in logical pixels.
  static const _shortMark = 6.0, _midMark = 10.0, _longMark = 16.0;

  /// Marks closer together than this (in logical pixels) are left out.
  static const _minMarkGap = 3.0;

  /// Space between labels, as a fraction of the widest label.
  static const _labelGap = 0.5;

  /// The protractor's labels are this many degrees apart, or a multiple.
  static const _degreesPerLabel = 10;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final linePaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 1;
    final path = outline.path;
    canvas.drawPath(
      path,
      Paint()..color = colorScheme.surface.withValues(alpha: _bodyOpacity),
    );
    canvas.drawPath(path, Paint.from(linePaint)..style = .stroke);

    // The screen's corners, to draw only the marks on screen.
    final screen = [
      Offset.zero,
      size.topRight(.zero),
      size.bottomLeft(.zero),
      size.bottomRight(.zero),
    ].map((corner) => Ruler.rotate(corner - center, -angle)).toList();
    for (final scale in outline.scales) {
      _paintScale(canvas, scale, screen, linePaint);
    }
    if (outline.protractor case final protractor?) {
      _paintProtractor(canvas, protractor, linePaint);
    }
    _paintRing(canvas, linePaint);

    canvas.restore();
  }

  void _paintScale(
    Canvas canvas,
    RulerScale scale,
    List<Offset> screen,
    Paint linePaint,
  ) {
    final markGap = markSpacingMm * pixelsPerMm;
    if (!(markGap > 0)) return;

    // Leave out marks (in steps of 1, 5, 10, 50, ...) that would crowd.
    var step = 1;
    while (step * markGap < _minMarkGap) {
      step *= step.toString().startsWith('1') ? 5 : 2;
    }

    final alongScreen = screen.map(
      (corner) => _dot(corner - scale.origin, scale.direction),
    );
    final from = max(scale.from, alongScreen.reduce(min));
    final to = min(scale.to, alongScreen.reduce(max));
    if (from > to) return;
    final first = (from / markGap / step).ceil() * step;
    final last = (to / markGap).floor();

    // Labels every 10th mark or a multiple of that, so they don't overlap.
    final widestLabel = _layOutText(
      _formatCm(max(first.abs(), last.abs()) * markSpacingMm),
      textStyle,
    ).width;
    final labelStep = _lcm(10, step);
    final labelEvery =
        labelStep *
        max(1, (widestLabel * (1 + _labelGap) / (labelStep * markGap)).ceil());

    for (var i = first; i <= last; i += step) {
      final point = scale.origin + scale.direction * (i * markGap);
      final length = switch (i) {
        _ when i % 10 == 0 => _longMark,
        _ when i % 5 == 0 => _midMark,
        _ => _shortMark,
      };
      canvas.drawLine(point, point + scale.inward * length, linePaint);

      if (!scale.labeled || i == 0 || i % labelEvery != 0) continue;
      final label = _layOutText(_formatCm(i.abs() * markSpacingMm), textStyle);
      final depth = _longMark + _labelGap * label.height + label.height / 2;
      final labelCenter = point + scale.inward * depth;
      if (!_hasRoomForLabel(labelCenter, label, (i * markGap).abs() - depth)) {
        continue;
      }
      label.paint(
        canvas,
        labelCenter - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  /// Whether [label], centred at [center], keeps clear of the ring, the
  /// protractor and the outline's sides, and of a scale starting at a corner
  /// [fromZero] away (e.g. a [RulerShape.trySquare]'s other scale).
  bool _hasRoomForLabel(Offset center, TextPainter label, double fromZero) {
    final clearance =
        Offset(label.width, label.height).distance / 2 +
        _labelGap * label.height;
    if (fromZero < clearance) return false;
    if (center.distance < outline.ringOuter + clearance) return false;
    // The protractor's marks (its labels keep clear of scales themselves).
    if (outline.protractor case final protractor?) {
      final distance = (center - protractor.center).distance;
      if (distance > protractor.radius - _longMark - clearance &&
          distance < protractor.radius + clearance) {
        return false;
      }
    }
    return outline.sides.every((side) => side.distanceTo(center) >= clearance);
  }

  void _paintProtractor(
    Canvas canvas,
    ({Offset center, double radius}) protractor,
    Paint linePaint,
  ) {
    final (:center, :radius) = protractor;
    final degreeGap = radius * pi / 180;
    final step = degreeGap >= _minMarkGap
        ? 1
        : degreeGap * 5 >= _minMarkGap
        ? 5
        : _degreesPerLabel;

    // Labels far enough apart (along their circle) not to overlap.
    final widest = _layOutText('180', textStyle);
    final labelRadius =
        radius - _longMark - _labelGap * widest.height - widest.width / 2;
    final labelSpacing = widest.width * (1 + _labelGap);
    var degreesPerLabel = _degreesPerLabel;
    while (degreesPerLabel < 180 &&
        labelRadius * degreesPerLabel * pi / 180 < labelSpacing) {
      degreesPerLabel += _degreesPerLabel;
    }
    for (var degree = 0; degree <= 180; degree += step) {
      // 0° on the right, 90° straight down (into the triangle), 180° left,
      // like a protractor laid on the page.
      final direction = Offset.fromDirection(degree * pi / 180);
      final length = switch (degree) {
        _ when degree % 10 == 0 => _longMark,
        _ when degree % 5 == 0 => _midMark,
        _ => _shortMark,
      };
      canvas.drawLine(
        center + direction * radius,
        center + direction * (radius - length),
        linePaint,
      );
      if (degree % degreesPerLabel != 0) continue;
      final label = _layOutText('$degree', textStyle);
      if (labelRadius - widest.width / 2 <= outline.ringOuter) continue;
      final labelCenter = center + direction * labelRadius;
      // Keep clear of the sides and the labels of scales along them.
      final clearance =
          Offset(label.width, label.height).distance / 2 +
          _labelGap * label.height;
      final scaleLabels = _longMark + (1 + _labelGap) * label.height;
      final tooClose =
          outline.sides.any(
            (side) => side.distanceTo(labelCenter) < clearance,
          ) ||
          outline.scales.any(
            (scale) =>
                scale.labeled &&
                RulerEdge(
                      start: scale.origin + scale.direction * scale.from,
                      end: scale.origin + scale.direction * scale.to,
                    ).distanceTo(labelCenter) <
                    scaleLabels + clearance,
          );
      if (tooClose) continue;
      label.paint(
        canvas,
        labelCenter - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  void _paintRing(Canvas canvas, Paint linePaint) {
    final ringWidth = outline.ringOuter - outline.ringInner;
    final ringRadius = (outline.ringOuter + outline.ringInner) / 2;
    canvas.drawCircle(
      Offset.zero,
      outline.ringOuter,
      Paint()..color = colorScheme.surface,
    );
    canvas.drawCircle(
      Offset.zero,
      ringRadius,
      Paint()
        ..color = colorScheme.primary.withValues(alpha: _ringOpacity)
        ..style = .stroke
        ..strokeWidth = ringWidth,
    );
    canvas.drawCircle(
      Offset.zero,
      outline.ringOuter,
      Paint.from(linePaint)..style = .stroke,
    );

    // The angle, upright whichever way the ruler is turned.
    canvas.save();
    canvas.rotate(-angle);
    final label = _layOutText('$degrees°', textStyle);
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

  /// [mm] in centimetres, without trailing zeros.
  static String _formatCm(num mm) =>
      (mm / 10).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  static int _lcm(int a, int b) => a * b ~/ _gcd(a, b);
  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  @override
  bool? hitTest(Offset position) {
    final local = Ruler.rotate(position - center, -angle);
    return outline.inRing(local) || outline.grabs(local, snapDistance);
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      outline != oldDelegate.outline ||
      center != oldDelegate.center ||
      angle != oldDelegate.angle ||
      pixelsPerMm != oldDelegate.pixelsPerMm ||
      markSpacingMm != oldDelegate.markSpacingMm ||
      colorScheme != oldDelegate.colorScheme ||
      textStyle != oldDelegate.textStyle;
}
