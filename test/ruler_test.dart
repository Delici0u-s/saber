import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/ruler.dart';

void main() {
  const halfThickness = Ruler.thickness / 2;

  group('RulerGeometry', () {
    for (final degrees in [0, 30, 90, 135, -60]) {
      final geometry = RulerGeometry(
        center: const Offset(300, 200),
        angle: degrees * pi / 180,
      );
      Offset at({required double along, required double across}) =>
          geometry.center +
          geometry.direction * along +
          geometry.normal * across;

      group('at $degrees°', () {
        test('the middle moves the ruler, the edges don\'t', () {
          expect(geometry.grabs(at(along: 1000, across: 0)), isTrue);
          expect(
            geometry.grabs(at(along: -50, across: halfThickness - 1)),
            isFalse,
          );
          expect(
            geometry.grabs(at(along: 0, across: halfThickness + 1)),
            isFalse,
          );
        });

        test('a stroke starts on an edge within the snap distance', () {
          for (final side in [1.0, -1.0]) {
            for (final across in [
              halfThickness - Ruler.snapDistance + 0.5,
              halfThickness,
              halfThickness + Ruler.snapDistance - 0.5,
            ]) {
              final edge = geometry.edgeNear(
                at(along: 40, across: side * across),
              );
              expect(edge?.side, side, reason: 'across $across on $side');
            }
          }
          expect(geometry.edgeNear(at(along: 0, across: 0)), isNull);
          expect(
            geometry.edgeNear(
              at(along: 0, across: halfThickness + Ruler.snapDistance + 1),
            ),
            isNull,
          );
        });

        test('projects points onto the edge, a gap away from it', () {
          final edge = geometry.edgeNear(at(along: 0, across: -halfThickness))!;
          for (final point in [
            at(along: 120, across: -halfThickness - 10),
            at(along: -900, across: -halfThickness + 7),
            at(along: 3, across: -200),
          ]) {
            final projected = edge.project(point, gap: 2.5);
            expect(
              geometry.along(projected),
              closeTo(geometry.along(point), 1e-9),
            );
            expect(
              geometry.across(projected),
              closeTo(-halfThickness - 2.5, 1e-9),
            );
          }
        });
      });
    }
  });

  group('Ruler', () {
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

    test('shows angles counterclockwise from 0 to 179', () {
      final ruler = Ruler();
      for (final (degrees, displayed) in [
        (0, 0),
        (-30, 30),
        (30, 150),
        (-180, 0),
        (-270, 90),
        (450, 90),
      ]) {
        ruler.rotateTo(degrees * pi / 180, snap: false);
        expect(ruler.displayedDegrees, displayed, reason: '$degrees°');
      }
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

    Future<void> pumpOverlay(WidgetTester tester, Size size) async {
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

    setUp(() {
      ruler = Ruler()..visible = true;
      canvasDowns = [];
      pixelsPerMm = 4;
    });

    testWidgets('dragging the middle moves the ruler', (tester) async {
      const size = Size(800, 600);
      await pumpOverlay(tester, size);
      final start = ruler.centerIn(size);
      await tester.dragFrom(start + const Offset(100, 0), const Offset(30, 50));
      expect(ruler.centerIn(size), start + const Offset(30, 50));
      expect(canvasDowns, isEmpty);
    });

    testWidgets('pointers near an edge reach the canvas', (tester) async {
      const size = Size(800, 600);
      await pumpOverlay(tester, size);
      final edge = ruler.centerIn(size) + const Offset(0, halfThickness - 2);
      await tester.tapAt(edge);
      expect(canvasDowns, hasLength(1));
      expect(ruler.edgeNear(edge)?.side, 1);
    });

    testWidgets('the mouse wheel rotates the ruler', (tester) async {
      const size = Size(800, 600);
      await pumpOverlay(tester, size);
      final pointer = TestPointer(1, .mouse);
      await tester.sendEventToBinding(pointer.hover(ruler.centerIn(size)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      expect(ruler.displayedDegrees, 179);
    });

    testWidgets('hidden, it lets everything through', (tester) async {
      const size = Size(800, 600);
      await pumpOverlay(tester, size);
      ruler.visible = false;
      await tester.pump();
      await tester.tapAt(ruler.centerIn(size));
      expect(canvasDowns, hasLength(1));
      expect(ruler.edgeNear(ruler.centerIn(size)), isNull);
    });

    for (final size in [const Size(120, 900), const Size(3000, 200)]) {
      for (final zoom in [0.05, 1.0, 400.0]) {
        testWidgets('draws at $size, $zoom px per mm', (tester) async {
          pixelsPerMm = zoom;
          ruler.rotateTo(0.4);
          await pumpOverlay(tester, size);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
