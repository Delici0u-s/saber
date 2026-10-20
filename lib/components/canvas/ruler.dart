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

  /// A flat try square (DIN 875), 150 × 100 mm with 30 mm wide legs.
  trySquare(symmetry: 2 * pi),

  /// A Geodreieck: a right isosceles triangle with a 160 mm long side,
  /// a ±7 cm scale along it and a protractor centred on it.
  setSquare(symmetry: 2 * pi);

  new({required this.symmetry});

  /// The smallest rotation that makes the shape look the same.
  final double symmetry;

  /// The shape saved as [json] (its [name]), or [ruler] if unknown.
  static RulerShape fromJson(Object? json) =>
      values.asNameMap()[json] ?? .ruler;
}

/// The units a [Ruler]'s marks measure in.
///
/// Saved by [name], so values can be reordered but not renamed.
enum RulerUnit {
  /// A mark every millimetre, labels in centimetres.
  mm(groups: [5, 10]),

  /// A mark every 1/16 inch, labels in inches.
  inch(groups: [2, 4, 8, 16]),

  /// A mark every point (1/72 inch), labels in picas (12 points).
  points(groups: [6, 12]),

  /// A mark every [Stows.rulerMarkSpacingMm], labels in centimetres.
  custom(groups: [5, 10]);

  new({required this.groups});

  /// Marks that are multiples of these counts are longer, the more the
  /// longer; every [groups].last-th mark has a label.
  final List<int> groups;

  /// Millimetres between two marks.
  double get markMm => switch (this) {
    mm => 1,
    inch => _mmPerInch / 16,
    points => _mmPerInch / 72,
    custom => stows.rulerMarkSpacingMm.value,
  };

  /// The label of the [index]th mark from 0 (a multiple of [groups].last).
  String label(int index) => switch (this) {
    custom => _format(index.abs() * markMm / 10),
    _ => '${index.abs() ~/ groups.last}',
  };

  static const _mmPerInch = 25.4;

  static String _format(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// The unit saved as [json] (its [name]), or [mm] if unknown.
  static RulerUnit fromJson(Object? json) => values.asNameMap()[json] ?? .mm;
}

/// The units a [Ruler]'s angle and protractor show.
///
/// Saved by [name], so values can be reordered but not renamed.
enum AngleUnit {
  /// Degrees, with protractor labels every 10°.
  degrees(groups: [5, 10]),

  /// Radians, as fractions of π on the protractor (every π/12) and for
  /// multiples of 15°, otherwise as decimals.
  radians(groups: [5, 15]);

  new({required this.groups});

  /// Protractor marks are every degree, longer on multiples of these;
  /// labels are on multiples of [groups].last degrees.
  final List<int> groups;

  /// [degrees] (a whole number) in this unit.
  String format(int degrees) => switch (this) {
    .degrees => '$degrees°',
    .radians when degrees % _piFraction == 0 => _ofPi(degrees ~/ _piFraction),
    .radians => (degrees * pi / 180).toStringAsFixed(2),
  };

  /// The widest of [format]'s results for angles below [limit] degrees.
  Iterable<String> widestCandidates(int limit) => switch (this) {
    .degrees => ['${limit - 1}°'],
    .radians => [
      format(limit - 1),
      format((limit ~/ _piFraction - 1) * _piFraction),
    ],
  };

  /// Radians are fractions of π in steps of 180° / [_piFraction].
  static const _piFraction = 15, _piSteps = 180 ~/ _piFraction;

  /// [steps] / [_piSteps] of π, reduced, e.g. "3π/4".
  static String _ofPi(int steps) {
    if (steps == 0) return '0';
    final divisor = _gcd(steps.abs(), _piSteps);
    final numerator = steps ~/ divisor, denominator = _piSteps ~/ divisor;
    final top = switch (numerator) {
      1 => 'π',
      -1 => '-π',
      _ => '$numeratorπ',
    };
    return denominator == 1 ? top : '$top/$denominator';
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// The unit saved as [json] (its [name]), or [degrees] if unknown.
  static AngleUnit fromJson(Object? json) =>
      values.asNameMap()[json] ?? .degrees;
}

/// Sizes a [RulerOutline] is laid out with.
typedef RulerDimensions = ({
  /// See [Stows.rulerSnapDistance].
  double snapDistance,

  /// The hole and outside of the rotation ring, see [RulerOutline.ringInner].
  double ringInner,
  double ringOuter,

  /// How long a millimetre on the page is on screen.
  double pixelsPerMm,

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

/// A protractor on a [RulerOutline], in its coordinates: degrees are
/// measured around [center] from the base's right towards [inward].
typedef RulerProtractor = ({
  /// The middle of its base, where the angles meet.
  Offset center,

  /// How far its marks and labels reach from [center].
  double radius,

  /// A unit vector from the base into the ruler, along its 90° line.
  Offset inward,
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

  /// The ruler's protractor, if any.
  final RulerProtractor? protractor;

  /// The width of a [RulerShape.ruler]: a grab area between two snap bands.
  static double barWidth(double snapDistance) =>
      kMinInteractiveDimension + 2 * snapDistance;

  /// A [RulerShape.trySquare]'s legs (DIN 875, 150 × 100 mm; the leg width is
  /// that of e.g. Hoffmann's DIN 875/1 flat square).
  static const _bladeMm = 150.0, _stockMm = 100.0, _legWidthMm = 30.0;

  /// A [RulerShape.setSquare]'s long side, the reach of its scale either way
  /// from the middle, and the margin between its protractor and short sides
  /// (for the degree marks along them), as on Aristo's and mizi's.
  static const _setSquareMm = 160.0, _setSquareScaleMm = 70.0;
  static const _protractorMarginMm = 6.0;

  factory of(RulerShape shape, RulerDimensions dimensions) {
    final (:snapDistance, :ringInner, :ringOuter, :pixelsPerMm, :overlay) =
        dimensions;

    switch (shape) {
      case .ruler:
        final bar = barWidth(snapDistance);
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
        // The outer corner at (0, 0), the blade along x and the stock along y;
        // the ring in the square where they meet.
        final blade = _bladeMm * pixelsPerMm;
        final stock = _stockMm * pixelsPerMm;
        final width = _legWidthMm * pixelsPerMm;
        final ring = Offset(width / 2, width / 2);
        Offset at(double x, double y) => Offset(x, y) - ring;
        return RulerOutline(
          corners: [
            at(0, 0),
            at(blade, 0),
            at(blade, width),
            at(width, width),
            at(width, stock),
            at(0, stock),
          ],
          ringInner: ringInner,
          ringOuter: ringOuter,
          scales: [
            (
              origin: at(0, 0),
              direction: const Offset(1, 0),
              inward: const Offset(0, 1),
              from: 0,
              to: blade,
              labeled: true,
            ),
            (
              origin: at(0, 0),
              direction: const Offset(0, 1),
              inward: const Offset(1, 0),
              from: 0,
              to: stock,
              labeled: true,
            ),
            // The inner sides, measured from the inner corner.
            (
              origin: at(width, width),
              direction: const Offset(1, 0),
              inward: const Offset(0, -1),
              from: 0,
              to: blade - width,
              labeled: true,
            ),
            (
              origin: at(width, width),
              direction: const Offset(0, 1),
              inward: const Offset(-1, 0),
              from: 0,
              to: stock - width,
              labeled: true,
            ),
          ],
        );

      case .setSquare:
        // The long side at the bottom with its middle below the ring (the
        // ring keeps clear of the scale), and the right angle on top.
        final length = _setSquareMm * pixelsPerMm;
        final middle = Offset(0, ringOuter + snapDistance);
        final scaleReach = _setSquareScaleMm * pixelsPerMm;
        const up = Offset(0, -1);
        return RulerOutline(
          corners: [
            middle + Offset(length / 2, 0),
            middle + Offset(-length / 2, 0),
            middle + up * (length / 2),
          ],
          ringInner: ringInner,
          ringOuter: ringOuter,
          scales: [
            (
              origin: middle,
              direction: const Offset(1, 0),
              inward: up,
              from: -scaleReach,
              to: scaleReach,
              labeled: true,
            ),
          ],
          // The short sides are length / (2√2) from the middle.
          protractor: (
            center: middle,
            radius:
                (_setSquareMm / (2 * sqrt2) - _protractorMarginMm) *
                pixelsPerMm,
            inward: up,
          ),
        );
    }
  }

  /// The sides of the outline, clockwise.
  Iterable<RulerEdge> get sides sync* {
    for (var i = 0; i < corners.length; i++) {
      final n = corners.length;
      yield RulerEdge(
        start: corners[i],
        end: corners[(i + 1) % n],
        before: corners[(i - 1) % n],
        after: corners[(i + 2) % n],
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
    return _nearestSide(point, maxDistance: snapDistance);
  }

  /// The side a pen at [point] runs along, like against a real ruler:
  /// [current] while the pen stays against it or pushes into the ruler,
  /// otherwise the side the pen reaches (see [edgeNear]), if any.
  RulerEdge? edgeFor(Offset point, double snapDistance, {RulerEdge? current}) {
    final inside = path.contains(point);
    if (current != null &&
        (inside || current.distanceTo(point) <= snapDistance)) {
      return current;
    }
    if (inside) return _nearestSide(point);
    return edgeNear(point, snapDistance);
  }

  RulerEdge? _nearestSide(
    Offset point, {
    double maxDistance = double.infinity,
  }) {
    RulerEdge? nearest;
    var nearestDistance = maxDistance;
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
  const new({required this.start, required this.end, this.before, this.after});

  final Offset start, end;

  /// The corners before [start] and after [end] around the outline, if any,
  /// so [project] goes round them like a pen round a real ruler's corners.
  final Offset? before, after;

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

  /// Where a ray from [origin] towards [direction] crosses the side, if it
  /// does.
  Offset? intersect(Offset origin, Offset direction) {
    final side = end - start;
    final denominator = _cross(direction, side);
    if (denominator == 0) return null;
    final toStart = start - origin;
    final alongRay = _cross(toStart, side) / denominator;
    final alongSide = _cross(toStart, direction) / denominator;
    if (alongRay <= 0 || alongSide < 0 || alongSide > 1) return null;
    return origin + direction * alongRay;
  }

  /// [point] moved onto the side, then [gap] further away from the ruler
  /// (e.g. half a stroke's width, so the stroke touches the side).
  ///
  /// Like a pen against a real ruler, it goes round an outer corner on an
  /// arc of radius [gap] (up to the next side), and stops before an inner
  /// corner where it touches the next side too.
  Offset project(Offset point, {double gap = 0}) {
    final direction = _direction;
    final length = (end - start).distance;
    final startTurn = before == null ? 0.0 : _turn(start - before!, direction);
    final endTurn = after == null ? 0.0 : _turn(direction, after! - end);
    final from = startTurn < 0 ? gap * tan(-startTurn / 2) : 0.0;
    final to = max(from, length - (endTurn < 0 ? gap * tan(-endTurn / 2) : 0));

    final along = _dot(point - start, direction);
    if (along > length && endTurn > 0) {
      final round = _turn(outward, point - end).clamp(0.0, endTurn);
      return end + Ruler.rotate(outward, round) * gap;
    }
    if (along < 0 && startTurn > 0) {
      final round = _turn(outward, point - start).clamp(-startTurn, 0.0);
      return start + Ruler.rotate(outward, round) * gap;
    }
    return start + direction * along.clamp(from, to) + outward * gap;
  }

  /// The angle from [a] to [b], clockwise on screen: positive where the
  /// outline turns at an outer corner, negative at an inner one.
  static double _turn(Offset a, Offset b) => atan2(_cross(a, b), _dot(a, b));

  @override
  bool operator ==(Object other) =>
      other is RulerEdge && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
}

/// A straight edge over the canvas: pen strokes that reach one of its sides
/// are drawn along it, and its marks measure the page.
///
/// It lives on the screen, not on a page: it stays put while scrolling and is
/// never saved or exported. Shown by [RulerOverlay].
class Ruler extends ChangeNotifier {
  /// Rotating snaps to multiples of this angle when within [_snapTolerance],
  /// otherwise to whole multiples of [_fineAngle]. The tolerance is less
  /// than [_fineAngle], so the angles next to a snap angle can be set too.
  static const _snapAngle = pi / 12;
  static const _snapTolerance = _fineAngle * 0.75;
  static const _fineAngle = pi / 180;

  /// How far one scroll of the mouse wheel rotates the ruler.
  static const _wheelStep = _fineAngle;

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

  RulerUnit get unit => .fromJson(stows.rulerUnit.value);
  set unit(RulerUnit unit) {
    stows.rulerUnit.value = unit.name;
    notifyListeners();
  }

  AngleUnit get angleUnit => .fromJson(stows.rulerAngleUnit.value);
  set angleUnit(AngleUnit angleUnit) {
    stows.rulerAngleUnit.value = angleUnit.name;
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

  /// Rotates the ruler to [angle], snapping it (see [snapAngle]) if [snap]
  /// is true.
  void rotateTo(double angle, {bool snap = true}) {
    if (snap) angle = snapAngle(angle);
    _angle = angle;
    notifyListeners();
  }

  /// [angle] (in radians) moved to a nearby multiple of 15°, or else to
  /// whole degrees: how the ruler (and other things rotated by hand, e.g. a
  /// selection) snap.
  static double snapAngle(double angle) {
    final snapped = (angle / _snapAngle).round() * _snapAngle;
    return (angle - snapped).abs() <= _snapTolerance
        ? snapped
        : (angle / _fineAngle).round() * _fineAngle;
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

  /// The side a pen at [globalPosition] is drawn along, see
  /// [RulerOutline.edgeFor]: [current] is the side it was drawn along so
  /// far in this stroke, if any. Null if the pen is away from the ruler
  /// (or the ruler isn't shown).
  RulerSnap? snapFor(Offset globalPosition, {RulerSnap? current}) {
    final box = _overlayBox;
    final outline = this.outline;
    if (!visible || box == null || outline == null) return null;
    final edge = outline.edgeFor(
      toRuler(box.globalToLocal(globalPosition), box.size),
      stows.rulerSnapDistance.value,
      current: current?.edge,
    );
    if (edge == null) return null;
    if (edge == current?.edge) return current;
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

  /// Space between the angle and the ring, and between the ring and the
  /// ruler's sides.
  static const _ringPadding = 4.0;

  /// The ring's width: as much as fits in the ruler, within these.
  static const _minRingWidth = 16.0,
      _maxRingWidth = kMinInteractiveDimension / 2;

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
        stows.rulerUnit,
        stows.rulerAngleUnit,
      ]),
      builder: (context, _) {
        if (!ruler.visible) return const SizedBox.shrink();
        final colorScheme = ColorScheme.of(context);
        final textStyle = TextTheme.of(context).labelSmall!
            .copyWith(color: colorScheme.onSurfaceVariant);

        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final snapDistance = stows.rulerSnapDistance.value;
            final pixelsPerMm = widget.pixelsPerMm();
            final angleLabel = ruler.angleUnit
                .widestCandidates((ruler.shape.symmetry * 180 / pi).round())
                .map((text) => _layOutText(text, textStyle))
                .reduce((a, b) => a.width >= b.width ? a : b);
            final ringInner =
                Offset(angleLabel.width, angleLabel.height).distance / 2 +
                RulerOverlay._ringPadding;
            // As wide as fits within the ruler's bar, but always grabbable.
            final ringWidth =
                (RulerOutline.barWidth(snapDistance) / 2 -
                        RulerOverlay._ringPadding -
                        ringInner)
                    .clamp(
                      RulerOverlay._minRingWidth,
                      RulerOverlay._maxRingWidth,
                    );
            final outline = ruler.outline = RulerOutline.of(ruler.shape, (
              snapDistance: snapDistance,
              ringInner: ringInner,
              ringOuter: ringInner + ringWidth,
              pixelsPerMm: pixelsPerMm,
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
                // The ruler reaches past the overlay, which mustn't cover the
                // toolbar or app bar next to it.
                child: ClipRect(
                  child: CustomPaint(
                    key: ruler.overlayKey,
                    size: size,
                    painter: _RulerPainter(
                      outline: outline,
                      center: ruler.centerIn(size),
                      angle: ruler.angle,
                      degrees: ruler.displayedDegrees,
                      angleUnit: ruler.angleUnit,
                      snapDistance: snapDistance,
                      pixelsPerMm: pixelsPerMm,
                      unit: ruler.unit,
                      markMm: ruler.unit.markMm,
                      colorScheme: colorScheme,
                      textStyle: textStyle,
                    ),
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
  new({
    required this.outline,
    required this.center,
    required this.angle,
    required this.degrees,
    required this.angleUnit,
    required this.snapDistance,
    required this.pixelsPerMm,
    required this.unit,
    required this.markMm,
    required this.colorScheme,
    required this.textStyle,
  });

  final RulerOutline outline;
  final Offset center;
  final double angle;
  final int degrees;
  final AngleUnit angleUnit;
  final double snapDistance;
  final double pixelsPerMm;
  final RulerUnit unit;

  /// [RulerUnit.markMm], which may come from a setting.
  final double markMm;
  final ColorScheme colorScheme;
  final TextStyle textStyle;

  /// Opacity of the ruler's body, so the page shows through it.
  static const _bodyOpacity = 0.85;

  /// The body's shadow, as a [Material] elevation.
  static const _elevation = 3.0;

  /// Opacity of the rotation ring's band.
  static const _ringOpacity = 0.12;

  /// The rotate arrows on the ring: how far each reaches around it, and the
  /// size of their heads, as a fraction of the ring's width.
  static const _arrowSweep = pi / 4, _arrowHead = 0.35;

  /// Lengths of the shortest and longest marks, in logical pixels.
  static const _shortMark = 5.0, _longMark = 14.0;

  /// Marks closer together than this (in logical pixels) are left out.
  static const _minMarkGap = 3.0;

  /// Space between labels, as a fraction of the widest label's height.
  static const _labelGap = 0.5;

  /// Protractor marks every degree, longer on multiples of the angle unit's
  /// groups; labels on multiples of the last.
  List<int> get _degreeGroups => angleUnit.groups;

  /// A Geodreieck's lines parallel to its long side are at least this far
  /// apart (in logical pixels).
  static const _minParallelGap = 12.0;

  /// The length of the dashes in dashed lines, and of the gaps between them.
  static const _dash = 4.0;

  Paint get _markPaint => Paint()
    ..color = colorScheme.onSurfaceVariant
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = outline.path;
    canvas.drawShadow(path, colorScheme.shadow, _elevation, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = colorScheme.surfaceContainerHigh.withValues(
          alpha: _bodyOpacity,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = colorScheme.outline
        ..style = .stroke
        ..strokeWidth = 1,
    );

    // The screen's corners, to draw only the marks on screen.
    final screen = [
      Offset.zero,
      size.topRight(.zero),
      size.bottomLeft(.zero),
      size.bottomRight(.zero),
    ].map((corner) => Ruler.rotate(corner - center, -angle)).toList();
    for (final (index, scale) in outline.scales.indexed) {
      _paintScale(canvas, index, scale, screen);
    }
    if (outline.protractor case final protractor?) {
      _paintProtractor(canvas, protractor, screen);
    }
    _paintRing(canvas);

    canvas.restore();
  }

  /// The length of a mark that's a multiple of the first [tier] of [groups]
  /// (0 for none), from [_shortMark] to [_longMark].
  static double _markLength(int tier, List<int> groups) =>
      _shortMark + (_longMark - _shortMark) * tier / groups.length;

  /// How many of [groups] [index] is a multiple of, counting from the first.
  static int _tier(int index, List<int> groups) =>
      groups.lastIndexWhere((group) => index % group == 0) + 1;

  /// The smallest of [steps] (or a multiple of the last) that keeps lines
  /// [gap] apart for each step at least [minGap] apart.
  static int _step(double gap, List<int> steps, {double minGap = _minMarkGap}) {
    for (final step in steps) {
      if (step * gap >= minGap) return step;
    }
    var step = steps.last;
    while (step * gap < minGap) {
      step *= 2;
    }
    return step;
  }

  /// Draws the marks and labels of [scale], the [index]th of the outline's.
  void _paintScale(
    Canvas canvas,
    int index,
    RulerScale scale,
    List<Offset> screen,
  ) {
    final markGap = markMm * pixelsPerMm;
    if (!(markGap > 0)) return;
    final groups = unit.groups;
    final step = _step(markGap, [1, ...groups]);

    final alongScreen = screen.map(
      (corner) => _dot(corner - scale.origin, scale.direction),
    );
    final from = max(scale.from, alongScreen.reduce(min));
    final to = min(scale.to, alongScreen.reduce(max));
    if (from > to) return;
    final first = (from / markGap / step).ceil() * step;
    final last = (to / markGap).floor();

    // Labels on a multiple of the largest group, far enough apart.
    final widestLabel = _layOutText(
      unit.label(max(first.abs(), last.abs())),
      textStyle,
    );
    final labelStep = _lcm(groups.last, step);
    final labelSpacing = widestLabel.width + _labelGap * widestLabel.height;
    final labelEvery =
        labelStep * max(1, (labelSpacing / (labelStep * markGap)).ceil());

    final paint = _markPaint;
    for (var i = first; i <= last; i += step) {
      final point = scale.origin + scale.direction * (i * markGap);
      final length = _markLength(_tier(i, groups), groups);
      canvas.drawLine(point, point + scale.inward * length, paint);

      if (!scale.labeled || i % labelEvery != 0) continue;
      final label = _layOutText(unit.label(i), textStyle);
      final labelCenter = point + scale.inward * _labelDepth(scale, label);
      if (!_hasRoomForLabel(labelCenter, label, index)) continue;
      label.paint(
        canvas,
        labelCenter - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  /// Half the size of [label] along [direction], a unit vector, plus a gap:
  /// how far its centre has to be from a line across [direction] not to
  /// touch it. [rotation] is how far the label is turned from upright in the
  /// ruler, clockwise.
  static double _extent(
    TextPainter label,
    Offset direction, {
    double rotation = 0,
  }) {
    final local = Ruler.rotate(direction, -rotation);
    return (local.dx.abs() * label.width + local.dy.abs() * label.height) / 2 +
        _minMarkGap;
  }

  /// How far into the ruler from [scale]'s side its [label]'s centre goes:
  /// just past its longest marks.
  static double _labelDepth(RulerScale scale, TextPainter label) =>
      _longMark + _extent(label, scale.inward);

  /// Whether [label], centred at [center] and turned by [rotation], keeps
  /// [reach] away from [segment].
  static bool _clearOfSegment(
    RulerEdge segment,
    Offset center,
    TextPainter label,
    double reach, {
    double rotation = 0,
  }) {
    final away = center - segment.closestPoint(center);
    final distance = away.distance;
    return distance > 0 &&
        distance >= reach + _extent(label, away / distance, rotation: rotation);
  }

  /// Whether [label], centred at [center], is wholly inside or outside the
  /// band between radii [inner] and [outer] around [middle].
  static bool _clearOfBand(
    Offset middle,
    double inner,
    double outer,
    Offset center,
    TextPainter label, {
    double rotation = 0,
  }) {
    final away = center - middle;
    final distance = away.distance;
    if (distance == 0) {
      return inner > _extent(label, const Offset(1, 0), rotation: rotation);
    }
    final extent = _extent(label, away / distance, rotation: rotation);
    return distance + extent <= inner || distance - extent >= outer;
  }

  /// Whether [label] of the [scale]th scale (counting the outline's first,
  /// then any inside the protractor), centred at [center], keeps clear of
  /// the ring, the protractor's marks, the outline's sides, the marks of the
  /// outline's other scales and the labels of the scales before it (so the
  /// first scales keep theirs where two meet).
  bool _hasRoomForLabel(Offset center, TextPainter label, int scale) {
    if (!_clearOfRingAndSides(center, label)) return false;
    if (outline.protractor case final protractor?) {
      final marks = _protractorLayout!.marks;
      if (!_clearOfBand(
        protractor.center,
        marks - _longMark,
        marks,
        center,
        label,
      )) {
        return false;
      }
    }
    return _clearOfScales(center, label, outline.scales.take(scale)) &&
        _clearOfScales(
          center,
          label,
          outline.scales.skip(scale + 1),
          theirLabels: false,
        );
  }

  /// Whether [label] centred at [center] keeps clear of the ring and the
  /// outline's sides.
  bool _clearOfRingAndSides(
    Offset center,
    TextPainter label, {
    double rotation = 0,
  }) =>
      _clearOfBand(
        .zero,
        0,
        outline.ringOuter,
        center,
        label,
        rotation: rotation,
      ) &&
      outline.sides.every(
        (side) => _clearOfSegment(side, center, label, 0, rotation: rotation),
      );

  /// Whether [label] centred at [center] keeps clear of the marks of
  /// [scales], and of their labels if [theirLabels].
  bool _clearOfScales(
    Offset center,
    TextPainter label,
    Iterable<RulerScale> scales, {
    bool theirLabels = true,
    double rotation = 0,
  }) => scales.every(
    (scale) => _clearOfSegment(
      _sideOf(scale),
      center,
      label,
      _reach(scale, label, withLabels: theirLabels),
      rotation: rotation,
    ),
  );

  /// The part of the side [scale] runs along that has marks.
  static RulerEdge _sideOf(RulerScale scale) => RulerEdge(
    start: scale.origin + scale.direction * scale.from,
    end: scale.origin + scale.direction * scale.to,
  );

  /// How far into the ruler the marks of [scale] reach, and its labels (if
  /// sized like [label]) if [withLabels].
  static double _reach(
    RulerScale scale,
    TextPainter label, {
    bool withLabels = true,
  }) => withLabels && scale.labeled
      ? _labelDepth(scale, label) + _extent(label, scale.inward)
      : _longMark;

  /// Where the protractor's parts are, as radii from its centre, like on a
  /// Geodreieck: two rows of labels just inside its radius, then its marks
  /// (reaching in from [marks]), then [inside], the area within them.
  late final ({
    TextPainter widest,
    double rowWidth,
    double outerRow,
    double innerRow,
    double marks,
    double inside,
  })?
  _protractorLayout = switch (outline.protractor) {
    null => null,
    (:final radius, center: _, inward: _) => () {
      final widest = [
        for (var degree = 0; degree <= 180; degree += _degreeGroups.last)
          _layOutText(_protractorLabel(degree), textStyle),
      ].reduce((a, b) => a.width >= b.width ? a : b);
      // Labels follow the arc, so a row is a label's height deep.
      final rowWidth = widest.height + 2 * _minMarkGap;
      final outerRow = radius - rowWidth / 2;
      final innerRow = outerRow - rowWidth;
      final marks = innerRow - rowWidth / 2;
      return (
        widest: widest,
        rowWidth: rowWidth,
        outerRow: outerRow,
        innerRow: innerRow,
        marks: marks,
        inside: marks - _longMark - _minMarkGap,
      );
    }(),
  };

  /// Draws [protractor] like on a Geodreieck: two rows of labels, 0° to 180°
  /// counterclockwise from the right outside and the other way round inside,
  /// with the degree marks inside them; lines from the labels out to the
  /// sides and degree marks along them; the perpendicular through its centre;
  /// and inside it, lines parallel to its base with scales to measure them
  /// and lines at 45°.
  void _paintProtractor(
    Canvas canvas,
    RulerProtractor protractor,
    List<Offset> screen,
  ) {
    final (:center, :radius, :inward) = protractor;
    final layout = _protractorLayout!;
    final groups = _degreeGroups;
    final paint = _markPaint;

    _paintInside(canvas, protractor, screen);

    // The perpendicular through the centre, for right angles, broken where
    // it crosses the rows of labels.
    if (_toOutline(center, inward) case final end?) {
      canvas.save();
      canvas.clipPath(
        Path.combine(
          .difference,
          Path()..addRect(Rect.fromPoints(center, end).inflate(_minMarkGap)),
          Path.combine(
            .difference,
            _circle(center, radius),
            _circle(center, layout.innerRow - layout.rowWidth / 2),
          ),
        ),
      );
      canvas.drawLine(center, end, paint);
      canvas.restore();
    }

    final step = _step(layout.marks * pi / 180, [1, ...groups]);
    for (var degree = 0; degree <= 180; degree += step) {
      final direction = _direction(protractor, degree);
      final length = _markLength(_tier(degree, groups), groups);
      canvas.drawLine(
        center + direction * layout.marks,
        center + direction * (layout.marks - length),
        paint,
      );
    }

    // Labels on the same angles in both rows, far enough apart along the
    // inner (shorter) one not to overlap.
    final labelStep = groups.last;
    var degreesPerLabel = labelStep;
    while (degreesPerLabel < 180 &&
        layout.innerRow * degreesPerLabel * pi / 180 <
            layout.widest.width + 2 * _minMarkGap) {
      degreesPerLabel += labelStep;
    }

    // From the labels out to the sides, on the labelled angles.
    for (
      var degree = degreesPerLabel;
      degree < 180;
      degree += degreesPerLabel
    ) {
      final direction = _direction(protractor, degree);
      final end = _toOutline(center, direction);
      if (degree == 90 || end == null) continue; // the perpendicular
      final start = center + direction * (radius + _minMarkGap);
      if ((end - center).distance > (start - center).distance) {
        canvas.drawLine(start, end, paint);
      }
    }
    _paintEdgeDegrees(canvas, protractor);

    for (var degree = 0; degree <= 180; degree += degreesPerLabel) {
      final direction = _direction(protractor, degree);
      // Upright when read from the centre.
      final rotation = direction.direction + pi / 2;
      for (final (row, value) in [
        (layout.outerRow, degree),
        (layout.innerRow, 180 - degree),
      ]) {
        final label = _layOutText(_protractorLabel(value), textStyle);
        final labelCenter = center + direction * row;
        if (!_clearOfRingAndSides(labelCenter, label, rotation: rotation) ||
            !_clearOfScales(
              labelCenter,
              label,
              outline.scales,
              rotation: rotation,
            )) {
          continue;
        }
        canvas.save();
        canvas.translate(labelCenter.dx, labelCenter.dy);
        canvas.rotate(rotation);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
  }

  /// A protractor label for [degrees]: without the ° sign, which would only
  /// crowd it.
  String _protractorLabel(int degrees) =>
      angleUnit == .degrees ? '$degrees' : angleUnit.format(degrees);

  /// A unit vector [degree]s round [protractor] from its base on the right,
  /// towards its inside.
  static Offset _direction(RulerProtractor protractor, num degree) {
    final inward = protractor.inward;
    final right = Offset(-inward.dy, inward.dx);
    final radians = degree * pi / 180;
    return right * cos(radians) + inward * sin(radians);
  }

  /// Where a line from [point] towards [direction] leaves the outline, or
  /// null if it runs along a side.
  Offset? _toOutline(Offset point, Offset direction) {
    Offset? nearest;
    for (final side in outline.sides) {
      final hit = side.intersect(point, direction);
      if (hit == null || (hit - point).distance < _minMarkGap) continue;
      if (nearest == null ||
          (hit - point).distance < (nearest - point).distance) {
        nearest = hit;
      }
    }
    return nearest;
  }

  /// Degree marks on the sides where lines from the protractor's centre meet
  /// them, each along its line, to read angles at the edge; shortened to
  /// keep clear of the protractor's labels.
  void _paintEdgeDegrees(Canvas canvas, RulerProtractor protractor) {
    final (:center, :radius, inward: _) = protractor;
    final groups = _degreeGroups;
    // Not the base, which runs through the centre.
    final sides = outline.sides
        .where((side) => side.distanceTo(center) >= _minMarkGap)
        .toList();
    if (sides.isEmpty) return;
    final nearest = sides.map((side) => side.distanceTo(center)).reduce(min);
    final step = _step(nearest * pi / 180, [1, ...groups]);
    final paint = _markPaint;
    for (var degree = step; degree < 180; degree += step) {
      final direction = _direction(protractor, degree);
      for (final side in sides) {
        final hit = side.intersect(center, direction);
        if (hit == null ||
            (hit - side.start).distance < _minMarkGap ||
            (hit - side.end).distance < _minMarkGap) {
          continue;
        }
        final room = (hit - center).distance - radius - _minMarkGap;
        if (room <= 0) continue;
        final length =
            _markLength(_tier(degree, groups), groups) *
            min(1.0, room / _longMark);
        // Along the angle it marks, pointing at the centre.
        canvas.drawLine(hit, hit - direction * length, paint);
      }
    }
  }

  /// Inside the protractor's marks, like on a Geodreieck: lines parallel to
  /// its base at distances of the [unit], a scale up from the base on either
  /// side (about halfway out) to measure them, and dashed lines at 45°.
  void _paintInside(
    Canvas canvas,
    RulerProtractor protractor,
    List<Offset> screen,
  ) {
    final (:center, :inward, radius: _) = protractor;
    final inside = _protractorLayout!.inside;
    final markGap = markMm * pixelsPerMm;
    if (!(markGap > 0) || inside <= 0) return;
    final right = Offset(-inward.dy, inward.dx);
    final groups = unit.groups;
    // E.g. every 5 mm for mm, every 1/2 inch for inches.
    final parallelGroup = groups.length > 1
        ? groups[groups.length - 2]
        : groups.last;

    // The scales stand on a line between two of the base's labels (an odd
    // multiple of parallelGroup marks), so they don't cover them.
    final groupGap = parallelGroup * markGap;
    final offset =
        (2 * max(0, ((inside / 2 / groupGap - 1) / 2).round()) + 1) * groupGap;
    final scales = <RulerScale>[
      if (offset < inside)
        for (final side in const [1.0, -1.0])
          (
            origin: center + right * (offset * side),
            direction: inward,
            inward: right * -side,
            from: 0,
            to: sqrt(inside * inside - offset * offset),
            labeled: true,
          ),
    ];
    for (final (index, scale) in scales.indexed) {
      _paintScale(canvas, outline.scales.length + index, scale, screen);
    }

    final sample = _layOutText(unit.label(groups.last), textStyle);
    Path band(RulerScale scale, double reach) {
      final RulerEdge(:start, :end) = _sideOf(scale);
      final back = scale.inward * -_minMarkGap;
      final forth = scale.inward * (reach + _minMarkGap);
      return Path()..addPolygon([
        start + back,
        end + back,
        end + forth,
        start + forth,
      ], true);
    }

    final perpendicularEnd = center + inward * inside;
    final keepOut = [
      for (final scale in [...outline.scales, ...scales])
        band(scale, _reach(scale, sample)),
      _circle(.zero, outline.ringOuter + _minMarkGap),
      // Beside the perpendicular.
      Path()..addPolygon([
        center + right * _minMarkGap,
        perpendicularEnd + right * _minMarkGap,
        perpendicularEnd - right * _minMarkGap,
        center - right * _minMarkGap,
      ], true),
    ];
    final clip = keepOut.fold(
      Path.combine(.intersect, outline.path, _circle(center, inside)),
      (area, out) => Path.combine(.difference, area, out),
    );

    final step = _step(markGap, [parallelGroup], minGap: _minParallelGap);
    final paint = _markPaint;
    canvas.save();
    canvas.clipPath(clip);
    for (var i = step; i * markGap <= inside; i += step) {
      final across = center + inward * (i * markGap);
      canvas.drawLine(across - right * inside, across + right * inside, paint);
    }
    for (final degree in const [45, 135]) {
      _drawDashed(
        canvas,
        center,
        center + _direction(protractor, degree) * inside,
        paint,
      );
    }
    canvas.restore();
  }

  static Path _circle(Offset center, double radius) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  static void _drawDashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    final length = (to - from).distance;
    final direction = (to - from) / length;
    for (var along = 0.0; along < length; along += 2 * _dash) {
      canvas.drawLine(
        from + direction * along,
        from + direction * min(along + _dash, length),
        paint,
      );
    }
  }

  void _paintRing(Canvas canvas) {
    final inner = outline.ringInner, outer = outline.ringOuter;
    final width = outer - inner;
    final middle = (inner + outer) / 2;
    final accent = colorScheme.primary;

    canvas.drawCircle(Offset.zero, outer, Paint()..color = colorScheme.surface);
    canvas.drawCircle(
      Offset.zero,
      middle,
      Paint()
        ..color = accent.withValues(alpha: _ringOpacity)
        ..style = .stroke
        ..strokeWidth = width,
    );
    final line = Paint()
      ..color = accent
      ..style = .stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset.zero, outer, line);
    canvas.drawCircle(Offset.zero, inner, line);

    // Two arrows around the ring, showing that dragging it rotates.
    final arrows = Paint.from(line)
      ..strokeWidth = 2
      ..strokeCap = .round;
    final head = width * _arrowHead;
    for (final start in [-pi / 2 - _arrowSweep / 2, pi / 2 - _arrowSweep / 2]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: middle),
        start,
        _arrowSweep,
        false,
        arrows,
      );
      final tip = Offset.fromDirection(start + _arrowSweep, middle);
      final along = Offset.fromDirection(start + _arrowSweep + pi / 2);
      final across = Offset.fromDirection(start + _arrowSweep);
      final back = tip - along * head;
      canvas.drawLine(tip, back + across * (head / 2), arrows);
      canvas.drawLine(tip, back - across * (head / 2), arrows);
    }

    // The angle, upright whichever way the ruler is turned.
    canvas.save();
    canvas.rotate(-angle);
    final label = _layOutText(
      angleUnit.format(degrees),
      textStyle.copyWith(color: colorScheme.onSurface),
    );
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

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
      unit != oldDelegate.unit ||
      angleUnit != oldDelegate.angleUnit ||
      degrees != oldDelegate.degrees ||
      markMm != oldDelegate.markMm ||
      colorScheme != oldDelegate.colorScheme ||
      textStyle != oldDelegate.textStyle;
}
