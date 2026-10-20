import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/select_result.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:sbn/has_size.dart';

void main() {
  group('Select tool', () {
    test('selects the right strokes', () async {
      final select = SelectBox.currentSelect;
      final options = StrokeOptions(size: 9);

      // Drag gesture in a 10x10 square shape, on page 0
      select.onDragStart(Offset.zero, 0);
      select.onDragUpdate(const Offset(9, 10));
      select.onDragUpdate(const Offset(10, 10));

      expect(
        select.selectResult.pageIndex,
        0,
        reason: 'The page index should be 0',
      );

      const page = HasSize(Size(100, 100));

      final strokes = <Stroke>[
        // index 0 is inside
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(5, 5)),
        // index > 0 is outside
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(10, 10)),
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(15, 15)),
      ];

      select.onDragEnd(strokes, const []);

      expect(
        select.selectResult.strokes.length,
        1,
        reason: 'Only one stroke should be selected',
      );
      expect(
        select.selectResult.strokes.first,
        strokes[0],
        reason: 'The first stroke should be selected',
      );
      expect(
        select.selectResult.images.isEmpty,
        true,
        reason: 'No images should be selected',
      );
    });

    test('dragged left to right, selects only what is completely inside', () {
      final select = SelectBox.currentSelect;
      select.onDragStart(Offset.zero, 0);
      select.onDragUpdate(const Offset(10, 10));
      expect(select.selectResult.selectsWhole, isTrue);

      final images = <EditorImage>[
        TestImage(dstRect: const .fromLTWH(0, 0, 10, 10)),
        TestImage(dstRect: const .fromLTWH(0, 0, 10 / 0.75, 10 / 0.75)),
        TestImage(dstRect: const .fromLTWH(20, 20, 10, 10)),
      ];
      select.onDragEnd(const [], images);
      expect(select.selectResult.images, [images[0]]);
    });

    test('dragged right to left, selects everything it touches', () {
      final select = SelectBox.currentSelect;
      select.onDragStart(const Offset(10, 0), 0);
      select.onDragUpdate(const Offset(0, 10));
      expect(select.selectResult.selectsWhole, isFalse);

      const page = HasSize(Size(100, 100));
      Stroke line(Offset from, Offset to) => Stroke(
        color: Stroke.defaultColor,
        pressureEnabled: false,
        options: StrokeOptions(size: 1),
        pageIndex: 0,
        page: page,
        toolId: .fountainPen,
      )..addPoints([from, to]);
      final strokes = [
        // Partly inside.
        line(const Offset(5, 5), const Offset(50, 5)),
        // Crossing it, with no point inside.
        line(const Offset(-20, 5), const Offset(30, 5)),
        // Outside.
        line(const Offset(20, 20), const Offset(30, 30)),
      ];
      final images = <EditorImage>[
        TestImage(dstRect: const .fromLTWH(5, 5, 50, 50)),
        TestImage(dstRect: const .fromLTWH(20, 20, 10, 10)),
      ];
      select.onDragEnd(strokes, images);
      expect(select.selectResult.strokes, [strokes[0], strokes[1]]);
      expect(select.selectResult.images, [images[0]]);
    });

    group('getDominantStrokeColor', () {
      test('not done selecting', () {
        final select = SelectBox.currentSelect;
        select.unselect();
        expect(select.getDominantStrokeColor(), isNull);
      });

      test('with no selected strokes', () {
        final select = SelectBox.currentSelect;
        select.selectResult = SelectResult(
          pageIndex: 0,
          strokes: const [],
          images: const [],
          path: Path(),
          pageIndexStart: 0,
        );
        expect(select.getDominantStrokeColor(), isNull);
      });

      test('with selected strokes', () {
        final select = SelectBox.currentSelect;
        select.selectResult = SelectResult(
          pageIndex: 0,
          strokes: [
            _strokeWithColor(Colors.red),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.red),
          ],
          images: const [],
          path: Path(),
          pageIndexStart: 0,
        );
        select.doneSelecting = true;
        expect(select.getDominantStrokeColor(), Colors.blue);
      });
    });
  });
}

// ignore: missing_override_of_must_be_overridden
class TestImage extends PngEditorImage {
  static final _assetCache = AssetCache();

  TestImage({required super.dstRect})
    : super(
        id: -1,
        extension: '.png',
        imageProvider: null,
        pageIndex: 0,
        pageSize: const Size(100, 100),
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        assetCache: _assetCache,
      );

  @override
  Future<void> firstLoad() async {
    // do nothing
  }
}

Stroke _strokeWithColor(Color color) {
  return Stroke(
    color: color,
    pressureEnabled: false,
    options: StrokeOptions(),
    pageIndex: 0,
    page: const HasSize(Size.zero),
    toolId: .fountainPen,
  );
}
