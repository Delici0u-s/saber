import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';

/// Twice the area of [corners], positive if they run clockwise on screen.
double _clockwiseArea(List<Offset> corners) {
  var sum = 0.0;
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();

  const ringInner = 20.0, ringOuter = 44.0;
  const overlays = [Size(800, 600), Size(120, 900), Size(3000, 80), Size.zero];

  for (final shape in RulerShape.values) {
    for (final overlay in overlays) {
      for (final (snapDistance, pixelsPerMm) in [
        (8.0, 3.78),
        (16.0, 6.0),
        (32.0, 12.0),
      ]) {
        group('$shape in $overlay, snapping at $snapDistance, '
            '$pixelsPerMm px/mm', () {
          final outline = RulerOutline.of(shape, (
            snapDistance: snapDistance,
            ringInner: ringInner,
            ringOuter: ringOuter,
            pixelsPerMm: pixelsPerMm,
            overlay: overlay,
          ));

          test('runs clockwise, with every side pointing outward', () {
            expect(_clockwiseArea(outline.corners), greaterThan(0));
            for (final side in outline.sides) {
              final middle = (side.start + side.end) / 2;
              expect(outline.path.contains(middle + side.outward), isFalse);
              expect(outline.path.contains(middle - side.outward), isTrue);
            }
          });

          test('the ring is inside', () {
            expect(outline.path.contains(.zero), isTrue);
            if (shape == .ruler) return; // as wide as its grab area and bands
            for (final side in outline.sides) {
              expect(side.distanceTo(.zero), greaterThanOrEqualTo(ringOuter));
            }
          });

          if (shape != .ruler) {
            test('is real size', () {
              final xs = outline.corners.map((corner) => corner.dx);
              final widthMm = (xs.reduce(max) - xs.reduce(min)) / pixelsPerMm;
              expect(widthMm, closeTo(shape == .trySquare ? 150 : 160, 1e-9));
            });
          }

          test('a pen keeps against a side until it pulls away', () {
            final side = outline.sides.first;
            final middle = (side.start + side.end) / 2;
            final along =
                (side.end - side.start) / (side.end - side.start).distance;
            final beside = middle + along * (ringOuter + snapDistance);
            // Reaching the side mid-stroke snaps to it.
            expect(
              outline.edgeFor(
                beside + side.outward * (snapDistance * 3),
                snapDistance,
              ),
              isNull,
            );
            expect(
              outline.edgeFor(
                beside + side.outward * (snapDistance / 2),
                snapDistance,
              ),
              side,
            );
            // Pushing into the ruler stays on it.
            final inside = beside - side.outward * (snapDistance * 2);
            if (outline.path.contains(inside)) {
              expect(
                outline.edgeFor(inside, snapDistance, current: side),
                side,
              );
            }
            // Pulling away lets go.
            expect(
              outline.edgeFor(
                beside + side.outward * (snapDistance + 1),
                snapDistance,
                current: side,
              ),
              isNull,
            );
          });

          test('strokes snap to each side from either side of it', () {
            for (final side in outline.sides) {
              final middle = (side.start + side.end) / 2;
              for (final across in [
                -snapDistance + 0.5,
                0.0,
                snapDistance - 0.5,
              ]) {
                final point = middle + side.outward * across;
                if (point.distance <= ringOuter) continue;
                expect(outline.edgeNear(point, snapDistance), side);
                expect(outline.grabs(point, snapDistance), isFalse);
              }
              final away = middle + side.outward * (snapDistance + 1);
              expect(outline.edgeNear(away, snapDistance), isNull);
            }
          });

          test('the ring rotates, its hole moves the ruler', () {
            const ringMiddle = Offset((ringInner + ringOuter) / 2, 0);
            expect(outline.inRing(ringMiddle), isTrue);
            expect(outline.grabs(ringMiddle, snapDistance), isFalse);
            expect(outline.edgeNear(ringMiddle, snapDistance), isNull);
            expect(outline.grabs(.zero, snapDistance), isTrue);
          });

          if (outline.protractor case final protractor?) {
            test('the protractor fits inside, away from the ring', () {
              expect(protractor.radius, greaterThan(ringOuter));
              // The short sides; the long one goes through its centre.
              for (final side in outline.sides.skip(1)) {
                expect(
                  side.distanceTo(protractor.center),
                  greaterThanOrEqualTo(protractor.radius),
                );
              }
            });
          }
        });
      }
    }
  }

  group('RulerEdge', () {
    const edge = RulerEdge(start: Offset.zero, end: Offset(100, 100));

    test('projects points onto the side, a gap outside it', () {
      for (final point in const [
        Offset(80, 20),
        Offset(-10, 60),
        Offset(50, 50),
      ]) {
        final projected = edge.project(point, gap: 3);
        expect(edge.distanceTo(projected), closeTo(3, 1e-9));
        expect(
          (projected - edge.outward * 3 - edge.closestPoint(point)).distance,
          closeTo(0, 1e-9),
        );
      }
    });

    test('stops at its ends', () {
      expect(edge.project(const Offset(500, 400)), const Offset(100, 100));
      expect(edge.project(const Offset(-50, -80)), Offset.zero);
    });
  });

  group('RulerUnit', () {
    test('labels every largest group of marks', () {
      expect(RulerUnit.mm.markMm, 1);
      expect(RulerUnit.mm.label(30), '3');
      expect(RulerUnit.inch.markMm * 16, closeTo(25.4, 1e-9));
      expect(RulerUnit.inch.label(-32), '2');
      expect(RulerUnit.points.markMm * 72, closeTo(25.4, 1e-9));
      expect(RulerUnit.points.label(24), '2');
      stows.rulerMarkSpacingMm.value = 2.5;
      expect(RulerUnit.custom.markMm, 2.5);
      expect(RulerUnit.custom.label(10), '2.5');
      expect(RulerUnit.custom.label(40), '10');
      stows.rulerMarkSpacingMm.value = 1;
    });
  });

  group('Ruler', () {
    setUp(() => stows.lastRulerShape.value = RulerShape.ruler.name);

    test('rotating snaps to nearby multiples of 15°', () {
      final ruler = Ruler();
      ruler.rotateTo(31 * pi / 180);
      expect(ruler.angle, closeTo(30 * pi / 180, 1e-9));
      ruler.rotateTo(37 * pi / 180);
      expect(ruler.angle, closeTo(37 * pi / 180, 1e-9));
      ruler.rotateTo(31 * pi / 180, snap: false);
      expect(ruler.angle, closeTo(31 * pi / 180, 1e-9));
    });

    test('the mouse wheel rotates in steps without snapping', () {
      final ruler = Ruler()..rotateTo(15 * pi / 180);
      ruler.rotateByWheel(down: true);
      expect(ruler.displayedDegrees, 164);
      ruler.rotateByWheel(down: false);
      expect(ruler.displayedDegrees, 165);
    });

    test('shows angles counterclockwise, within its symmetry', () {
      final ruler = Ruler();
      for (final (shape, degrees, displayed) in [
        (RulerShape.ruler, 0, 0),
        (RulerShape.ruler, -30, 30),
        (RulerShape.ruler, 30, 150),
        (RulerShape.ruler, -270, 90),
        (RulerShape.setSquare, 30, 330),
        (RulerShape.setSquare, -200, 200),
        (RulerShape.trySquare, 450, 270),
      ]) {
        ruler
          ..shape = shape
          ..rotateTo(degrees * pi / 180, snap: false);
        expect(ruler.displayedDegrees, displayed, reason: '$shape $degrees°');
      }
    });

    test('converts to its own coordinates and back', () {
      const size = Size(400, 300);
      final ruler = Ruler()
        ..moveBy(const Offset(30, -20), size)
        ..rotateTo(1.1, snap: false);
      const point = Offset(123, 45);
      final there = ruler.toRuler(point, size);
      expect((ruler.fromRuler(there, size) - point).distance, closeTo(0, 1e-9));
      expect(ruler.toRuler(ruler.centerIn(size), size), Offset.zero);
    });

    test('stays inside the overlay', () {
      final ruler = Ruler();
      const size = Size(400, 300);
      expect(ruler.centerIn(size), const Offset(200, 150));
      ruler.moveBy(const Offset(10000, -10000), size);
      expect(ruler.centerIn(size), const Offset(400, 0));
      // e.g. after the window shrinks
      expect(ruler.centerIn(const Size(100, 100)), const Offset(100, 0));
    });
  });

  group('RulerOverlay', () {
    late Ruler ruler;
    late List<PointerDownEvent> canvasDowns;
    var pixelsPerMm = 4.0;
    const size = Size(800, 600);

    Future<void> pumpOverlay(WidgetTester tester, [Size size = size]) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: .opaque,
                  onPointerDown: canvasDowns.add,
                ),
              ),
              Positioned.fill(
                child: RulerOverlay(
                  ruler: ruler,
                  zoom: ruler,
                  pixelsPerMm: () => pixelsPerMm,
                ),
              ),
            ],
          ),
        ),
      );
    }

    double barHalf() =>
        RulerOutline.barWidth(stows.rulerSnapDistance.value) / 2;

    setUp(() {
      stows.lastRulerShape.value = RulerShape.ruler.name;
      stows.rulerMarkSpacingMm.value = 1;
      stows.rulerSnapDistance.value = 16;
      stows.rulerUnit.value = RulerUnit.mm.name;
      ruler = Ruler()..visible = true;
      canvasDowns = [];
      pixelsPerMm = 4;
    });

    testWidgets('dragging the middle moves the ruler', (tester) async {
      await pumpOverlay(tester);
      final start = ruler.centerIn(size);
      await tester.dragFrom(start + const Offset(200, 0), const Offset(30, 50));
      expect(ruler.centerIn(size), start + const Offset(30, 50));
      expect(ruler.angle, 0);
      expect(canvasDowns, isEmpty);
    });

    testWidgets('dragging the ring rotates the ruler', (tester) async {
      await pumpOverlay(tester);
      final center = ruler.centerIn(size);
      final outline = ruler.outline!;
      final radius = (outline.ringInner + outline.ringOuter) / 2;
      final gesture = await tester.startGesture(center + Offset(radius, 0));
      // A quarter turn clockwise, along the ring.
      for (var degrees = 5; degrees <= 90; degrees += 5) {
        await gesture.moveTo(
          center + Offset.fromDirection(degrees * pi / 180, radius),
        );
      }
      await gesture.up();
      await tester.pump();
      expect(ruler.centerIn(size), center);
      expect(ruler.angle, closeTo(pi / 2, 1e-9));
      expect(ruler.displayedDegrees, 90);
      expect(canvasDowns, isEmpty);
    });

    testWidgets('pointers near a side reach the canvas', (tester) async {
      await pumpOverlay(tester);
      final edge = ruler.centerIn(size) + Offset(200, barHalf() - 2);
      await tester.tapAt(edge);
      expect(canvasDowns, hasLength(1));
      final projected = ruler.snapFor(edge)!.project(edge, gap: 3);
      expect(
        (projected - (ruler.centerIn(size) + Offset(200, barHalf() + 3)))
            .distance,
        closeTo(0, 1e-9),
      );
    });

    testWidgets('strokes follow a rotated set square', (tester) async {
      stows.lastRulerShape.value = RulerShape.setSquare.name;
      ruler.rotateTo(0.3, snap: false);
      await pumpOverlay(tester);
      final longSide = ruler.outline!.sides.first;
      final start = ruler.fromRuler(
        (longSide.start + longSide.end) / 2 + const Offset(40, -5),
        size,
      );
      final snap = ruler.snapFor(start)!;
      expect(snap.edge, longSide);
      for (final point in [start, start + const Offset(60, 10)]) {
        final local = ruler.toRuler(snap.project(point, gap: 2), size);
        expect(longSide.distanceTo(local), closeTo(2, 1e-6));
      }
    });

    testWidgets('the mouse wheel rotates the ruler', (tester) async {
      await pumpOverlay(tester);
      final pointer = TestPointer(1, .mouse);
      await tester.sendEventToBinding(
        pointer.hover(ruler.centerIn(size) + const Offset(200, 0)),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      expect(ruler.displayedDegrees, 179);
    });

    testWidgets('hidden, it lets everything through', (tester) async {
      await pumpOverlay(tester);
      ruler.visible = false;
      await tester.pump();
      await tester.tapAt(ruler.centerIn(size));
      expect(canvasDowns, hasLength(1));
      expect(ruler.snapFor(ruler.centerIn(size)), isNull);
    });

    testWidgets('a stroke snaps when it reaches a side', (tester) async {
      await pumpOverlay(tester);
      final center = ruler.centerIn(size);
      final away = center + Offset(200, barHalf() + 100);
      expect(ruler.snapFor(away), isNull);
      final near = center + Offset(220, barHalf() + 5);
      final snap = ruler.snapFor(near)!;
      expect(
        ruler.snapFor(center + Offset(240, barHalf() - 10), current: snap),
        same(snap),
      );
      expect(
        ruler.snapFor(center + Offset(260, barHalf() + 100), current: snap),
        isNull,
      );
    });

    for (final shape in RulerShape.values) {
      for (final overlay in const [Size(120, 900), Size(3000, 200)]) {
        for (final (zoom, unit, spacing) in [
          (0.05, RulerUnit.mm, 1.0),
          (1.1, RulerUnit.points, 1.0),
          (4.0, RulerUnit.custom, 7.0),
          (40.0, RulerUnit.inch, 1.0),
          (400.0, RulerUnit.custom, 0.3),
        ]) {
          testWidgets(
            'draws $shape at $overlay, $zoom px/mm, $unit ($spacing mm)',
            (tester) async {
              stows.lastRulerShape.value = shape.name;
              stows.rulerUnit.value = unit.name;
              stows.rulerMarkSpacingMm.value = spacing;
              pixelsPerMm = zoom;
              ruler.rotateTo(0.4);
              await pumpOverlay(tester, overlay);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
