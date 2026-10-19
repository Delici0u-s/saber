import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:sbn/has_size.dart';

void main() {
  group('Stroke.splitIntoPieces', () {
    // A straight line 10 long, along x, as two segments.
    final line = [
      const PointVector(0, 0, 0.2),
      const PointVector(4, 0, 0.4),
      const PointVector(10, 0, 1),
    ];

    List<List<double>> xs(List<List<PointVector>> pieces) => [
      for (final piece in pieces) [for (final p in piece) p.x],
    ];

    test('dashes start and end where the pattern says', () {
      final pieces = Stroke.splitIntoPieces(line, [3, 2]);
      expect(xs(pieces), [
        [0, 3],
        [5, 8],
      ]);
    });

    test('a dash keeps the points inside it', () {
      final pieces = Stroke.splitIntoPieces(line, [6, 1]);
      expect(xs(pieces), [
        [0, 4, 6],
        [7, 10],
      ]);
    });

    test('interpolates pressure where it cuts', () {
      final pieces = Stroke.splitIntoPieces(line, [2, 8]);
      expect(pieces.single.last.pressure, closeTo(0.3, 1e-9));
    });

    test('a drawn length of 0 gives dots', () {
      final pieces = Stroke.splitIntoPieces(line, [0, 4]);
      expect(xs(pieces), [
        [0, 0],
        [4, 4],
        [8, 8],
      ]);
    });

    test('skips a dash that only just started at the end', () {
      final pieces = Stroke.splitIntoPieces(line, [5, 5]);
      expect(xs(pieces), [
        [0, 4, 5],
      ]);
    });

    test('starts [offset] into the pattern', () {
      // 4 into [3, 2]: 1 of the gap left, then dashes at 5..8 and 10..
      final pieces = Stroke.splitIntoPieces(line, [3, 2], offset: 4);
      expect(xs(pieces), [
        [1, 4],
        [6, 9],
      ]);
      // a whole period further gives the same
      expect(xs(Stroke.splitIntoPieces(line, [3, 2], offset: 9)), xs(pieces));
    });

    test('an offset inside a dash starts drawing at once', () {
      final pieces = Stroke.splitIntoPieces(line, [3, 2], offset: 1);
      expect(xs(pieces).first, [0, 2]);
    });

    test('an empty pattern draws the whole line', () {
      expect(Stroke.splitIntoPieces(line, []), [line]);
    });
  });

  group('Stroke with a line style', () {
    Stroke stroke(LineStyle lineStyle) =>
        Stroke(
            color: Colors.black,
            pressureEnabled: false,
            options: StrokeOptions(size: 2, isComplete: true),
            pageIndex: 0,
            page: const HasSize(Size(1000, 1400)),
            toolId: .ballpointPen,
            lineStyle: lineStyle,
          )
          ..addPoint(const Offset(0, 10))
          ..addPoint(const Offset(100, 10));

    for (final lineStyle in LineStyle.values) {
      test('${lineStyle.name} survives saving', () {
        final json = stroke(lineStyle).toJson();
        final loaded = Stroke.fromJson(
          json,
          fileVersion: EditorCoreInfo.sbnVersion,
          pageIndex: 0,
          page: const HasSize(Size(1000, 1400)),
        );
        expect(loaded.lineStyle, lineStyle);
        expect(stroke(lineStyle).copy().lineStyle, lineStyle);
      });
    }

    test('solid strokes are saved as before', () {
      expect(stroke(.solid).toJson().containsKey('ls'), isFalse);
    });

    test('an unknown style loads as solid', () {
      expect(LineStyle.fromJson('wavy'), LineStyle.solid);
      expect(LineStyle.fromJson(null), LineStyle.solid);
    });

    test('is drawn as one outline per dash', () {
      final dashed = stroke(.dashed);
      // 100 long, dashes of 3*2 and gaps of 2*2: 10 dashes
      expect(dashed.highQualityPieces, hasLength(10));
      expect(dashed.lowQualityPieces, hasLength(10));
      expect(
        dashed.highQualityPolygon,
        hasLength(
          dashed.highQualityPieces.fold<int>(0, (n, p) => n + p.length),
        ),
      );
      expect(stroke(.solid).isInPieces, isFalse);
    });

    test('exports each dash as its own outline', () {
      final svg = stroke(.dashed).toSvgPath();
      expect('M'.allMatches(svg), hasLength(10));
    });

    test('a dash looks the same while drawing and when finished', () {
      // Simulated pressure (e.g. a mouse) must not change once finished.
      Stroke drawn({required bool isComplete}) =>
          Stroke(
            color: Colors.black,
            pressureEnabled: true,
            options: StrokeOptions(size: 4, isComplete: isComplete),
            pageIndex: 0,
            page: const HasSize(Size(1000, 1400)),
            toolId: .fountainPen,
            lineStyle: .dashed,
          )..addPoints([
            for (var x = 0.0; x <= 200; x += 3 + x / 20) Offset(x, 10),
          ]);
      double width(List<Offset> piece) =>
          piece.map((p) => p.dy).reduce(max) -
          piece.map((p) => p.dy).reduce(min);

      final drawing = drawn(isComplete: false).highQualityPieces;
      final finished = drawn(isComplete: true).highQualityPieces;
      expect(drawing, hasLength(finished.length));
      for (var i = 0; i < finished.length; i++) {
        expect(width(drawing[i]), closeTo(width(finished[i]), 0.05));
      }
    });

    test('a dot stays a dot', () {
      final dot = Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2, isComplete: true),
        pageIndex: 0,
        page: const HasSize(Size(1000, 1400)),
        toolId: .ballpointPen,
        lineStyle: .dashed,
      )..addPoint(const Offset(5, 5));
      expect(dot.isInPieces, isFalse);
    });
  });
}
