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

  /// The width of a [RulerShape.ruler]: a grab area between two snap bands.
  static double barWidth(double snapDistance) =>
      kMinInteractiveDimension + 2 * snapDistance;

  /// A [RulerShape.trySquare]'s legs (DIN 875, 150 × 100 mm; the leg width is
  /// that of e.g. Hoffmann's DIN 875/1 flat square).
  static const _bladeMm = 150.0, _stockMm = 100.0, _legWidthMm = 30.0;

  /// A [RulerShape.setSquare]'s long side, the reach of its scale either way
  /// from the middle, and the margin between its protractor and short sides.
  static const _setSquareMm = 160.0, _setSquareScaleMm = 70.0;
  static const _protractorMarginMm = 3.0;

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
          ],
        );

      case .setSquare:
        // The long side on top with its middle above the ring (the ring
        // keeps clear of the scale), and the right angle below.
        final length = _setSquareMm * pixelsPerMm;
        final middle = Offset(0, -(ringOuter + snapDistance));
        final scaleReach = _setSquareScaleMm * pixelsPerMm;
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

/// A straight edge over the canvas: pen strokes that reach one of its sides
/// are drawn along it, and its marks measure the page.
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

  RulerUnit get unit => .fromJson(stows.rulerUnit.value);
  set unit(RulerUnit unit) {
    stows.rulerUnit.value = unit.name;
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
            final angleLabel = _layOutText(
              '${(ruler.shape.symmetry * 180 / pi).round() - 1}°',
              textStyle,
            );
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
                child: CustomPaint(
                  key: ruler.overlayKey,
                  size: size,
                  painter: _RulerPainter(
                    outline: outline,
                    center: ruler.centerIn(size),
                    angle: ruler.angle,
                    degrees: ruler.displayedDegrees,
                    snapDistance: snapDistance,
                    pixelsPerMm: pixelsPerMm,
                    unit: ruler.unit,
                    markMm: ruler.unit.markMm,
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
    required this.unit,
    required this.markMm,
    required this.colorScheme,
    required this.textStyle,
  });

  final RulerOutline outline;
  final Offset center;
  final double angle;
  final int degrees;
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

  /// The protractor's labels are this many degrees apart, or a multiple.
  static const _degreesPerLabel = 10;

  /// Protractor marks every degree, longer every 5° and every 10°.
  static const _degreeGroups = [5, 10];

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
    for (final scale in outline.scales) {
      _paintScale(canvas, scale, screen);
    }
    if (outline.protractor case final protractor?) {
      _paintProtractor(canvas, protractor);
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

  /// The smallest step through the marks (1, a group, or a multiple of the
  /// largest group) that keeps marks at least [_minMarkGap] apart.
  static int _step(double markGap, List<int> groups) {
    for (final step in [1, ...groups]) {
      if (step * markGap >= _minMarkGap) return step;
    }
    var step = groups.last;
    while (step * markGap < _minMarkGap) {
      step *= 2;
    }
    return step;
  }

  void _paintScale(Canvas canvas, RulerScale scale, List<Offset> screen) {
    final markGap = markMm * pixelsPerMm;
    if (!(markGap > 0)) return;
    final groups = unit.groups;
    final step = _step(markGap, groups);

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

      if (!scale.labeled || i == 0 || i % labelEvery != 0) continue;
      final label = _layOutText(unit.label(i), textStyle);
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

  /// Half the diagonal of [label] plus a gap: how far its centre has to be
  /// from anything it shouldn't touch.
  static double _clearance(TextPainter label) =>
      Offset(label.width, label.height).distance / 2 + _labelGap * label.height;

  /// Whether [label], centred at [center], keeps clear of the ring, the
  /// protractor's marks and the outline's sides, and of a scale starting at a
  /// corner [fromZero] away (e.g. a [RulerShape.trySquare]'s other scale).
  bool _hasRoomForLabel(Offset center, TextPainter label, double fromZero) {
    final clearance = _clearance(label);
    if (fromZero < clearance) return false;
    if (center.distance < outline.ringOuter + clearance) return false;
    if (outline.protractor case final protractor?) {
      final distance = (center - protractor.center).distance;
      if (distance > protractor.radius - _longMark - clearance &&
          distance < protractor.radius + clearance) {
        return false;
      }
    }
    return outline.sides.every((side) => side.distanceTo(center) >= clearance);
  }

  /// Draws degree marks around [protractor] and two rows of labels inside
  /// them: 0° to 180° counterclockwise from the right outside, the other
  /// way round inside, like on a Geodreieck.
  void _paintProtractor(
    Canvas canvas,
    ({Offset center, double radius}) protractor,
  ) {
    final (:center, :radius) = protractor;
    final step = _step(radius * pi / 180, _degreeGroups);
    final paint = _markPaint;

    // The perpendicular through the centre, for right angles.
    canvas.drawLine(center, center + Offset(0, radius), paint);

    for (var degree = 0; degree <= 180; degree += step) {
      // Clockwise on screen from the right: through the triangle.
      final direction = Offset.fromDirection(degree * pi / 180);
      final length = _markLength(_tier(degree, _degreeGroups), _degreeGroups);
      canvas.drawLine(
        center + direction * radius,
        center + direction * (radius - length),
        paint,
      );
    }

    final widest = _layOutText('180', textStyle);
    final rowGap = 2 * _clearance(widest);
    final outerRow = radius - _longMark - rowGap / 2;
    final innerRow = outerRow - rowGap;
    // Labels on the same angles in both rows, far enough apart along the
    // inner (shorter) one not to overlap.
    var degreesPerLabel = _degreesPerLabel;
    while (degreesPerLabel < 180 &&
        innerRow * degreesPerLabel * pi / 180 < rowGap) {
      degreesPerLabel += _degreesPerLabel;
    }
    for (var degree = 0; degree <= 180; degree += degreesPerLabel) {
      final direction = Offset.fromDirection(degree * pi / 180);
      for (final (row, value) in [
        (outerRow, 180 - degree),
        (innerRow, degree),
      ]) {
        final label = _layOutText('$value', textStyle);
        final labelCenter = center + direction * row;
        if (!_protractorLabelFits(labelCenter, label)) continue;
        label.paint(
          canvas,
          labelCenter - Offset(label.width / 2, label.height / 2),
        );
      }
    }
  }

  /// Whether a protractor [label] centred at [center] keeps clear of the
  /// ring, the sides and the labels of scales along them.
  bool _protractorLabelFits(Offset center, TextPainter label) {
    final clearance = _clearance(label);
    if (center.distance < outline.ringOuter + clearance) return false;
    if (outline.sides.any((side) => side.distanceTo(center) < clearance)) {
      return false;
    }
    final scaleLabels = _longMark + (1 + _labelGap) * label.height;
    return !outline.scales.any(
      (scale) =>
          scale.labeled &&
          RulerEdge(
                start: scale.origin + scale.direction * scale.from,
                end: scale.origin + scale.direction * scale.to,
              ).distanceTo(center) <
              scaleLabels + clearance,
    );
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
      '$degrees°',
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
      markMm != oldDelegate.markMm ||
      colorScheme != oldDelegate.colorScheme ||
      textStyle != oldDelegate.textStyle;
}
