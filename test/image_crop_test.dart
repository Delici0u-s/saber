import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/image_crop_dialog.dart';

/// An image whose left half is [left] and right half is [right].
Future<Uint8List> _twoColorPng(
  Size size, {
  required Color left,
  required Color right,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      Offset.zero & Size(size.width / 2, size.height),
      Paint()..color = left,
    )
    ..drawRect(
      Offset(size.width / 2, 0) & Size(size.width / 2, size.height),
      Paint()..color = right,
    );
  final image = await recorder.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
  final data = await image.toByteData(format: .png);
  return data!.buffer.asUint8List();
}

Future<Color> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: .rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

PngEditorImage _image(Uint8List bytes, Size naturalSize, Rect dstRect) =>
    PngEditorImage(
      id: 7,
      assetCache: AssetCache(),
      extension: '.jpg',
      imageProvider: MemoryImage(bytes),
      pageIndex: 0,
      pageSize: const Size(1000, 1400),
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      dstRect: dstRect,
      srcRect: Offset.zero & naturalSize,
      naturalSize: naturalSize,
    );

void main() {
  group('PngEditorImage.cropped', () {
    const left = Color(0xffff0000);
    const right = Color(0xff0000ff);

    for (final naturalSize in const [
      Size(4, 2),
      Size(400, 200),
      Size(1, 1000),
    ]) {
      testWidgets('keeps the right half of a $naturalSize image', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final bytes = await _twoColorPng(
            naturalSize,
            left: left,
            right: right,
          );
          final dstRect = const Offset(100, 50) & const Size(400, 200);
          final image = _image(bytes, naturalSize, dstRect);
          const crop = Rect.fromLTRB(0.5, 0, 1, 1);

          final cropped = await image.cropped(crop);

          final expectedSize = Size(
            (naturalSize.width / 2).roundToDouble().clamp(1, double.infinity),
            naturalSize.height,
          );
          expect(cropped.naturalSize, expectedSize);
          expect(cropped.srcRect, Offset.zero & expectedSize);
          expect(cropped.extension, '.png');
          expect(
            cropped.dstRect,
            Rect.fromLTRB(
              dstRect.left + dstRect.width / 2,
              dstRect.top,
              dstRect.right,
              dstRect.bottom,
            ),
          );

          // The first kept column is the middle one, or the only one
          // of a 1px-wide image.
          final firstKeptColumn = naturalSize.width ~/ 2;
          expect(
            await _pixel(await cropped.getBytes(), 0, 0),
            await _pixel(
              bytes,
              firstKeptColumn.clamp(0, naturalSize.width.toInt() - 1),
              0,
            ),
          );
        });
      });
    }

    testWidgets('a full crop covers the same area', (tester) async {
      await tester.runAsync(() async {
        const naturalSize = Size(8, 4);
        final bytes = await _twoColorPng(naturalSize, left: left, right: right);
        final dstRect = const Offset(10, 20) & const Size(80, 40);
        final image = _image(bytes, naturalSize, dstRect);

        final cropped = await image.cropped(const Rect.fromLTWH(0, 0, 1, 1));

        expect(cropped.naturalSize, naturalSize);
        expect(cropped.dstRect, dstRect);
        expect(await _pixel(await cropped.getBytes(), 0, 0), left);
        expect(await _pixel(await cropped.getBytes(), 7, 0), right);
      });
    });
  });

  group('ImageCropDialog', () {
    const naturalSize = Size(400, 200);

    Future<Rect?> dragAndCrop(
      WidgetTester tester, {
      required Offset edges,
      required Offset by,
    }) async {
      final bytes = await tester.runAsync(
        () => _twoColorPng(
          naturalSize,
          left: const Color(0xffff0000),
          right: const Color(0xff0000ff),
        ),
      );
      final image = _image(bytes!, naturalSize, Offset.zero & naturalSize);
      Rect? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<Rect>(
                context: context,
                builder: (_) => ImageCropDialog(image: image),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(ImageCropDialog.handleKey(edges)), by);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      return result;
    }

    for (final screen in const [Size(360, 640), Size(2000, 400)]) {
      for (final imageSize in const [Size(4000, 100), Size(100, 4000)]) {
        testWidgets('fits a $imageSize image on a $screen screen', (
          tester,
        ) async {
          tester.view.physicalSize = screen * tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);
          final bytes = await tester.runAsync(
            () => _twoColorPng(
              imageSize,
              left: const Color(0xffff0000),
              right: const Color(0xff0000ff),
            ),
          );
          final image = _image(bytes!, imageSize, Offset.zero & imageSize);
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<Rect>(
                    context: context,
                    builder: (_) => ImageCropDialog(image: image),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          for (final key in [const Offset(-1, -1), const Offset(1, 1)]) {
            expect(find.byKey(ImageCropDialog.handleKey(key)), findsOneWidget);
          }
        });
      }
    }

    testWidgets('dragging the bottom-right handle inwards shrinks the crop', (
      tester,
    ) async {
      final crop = await dragAndCrop(
        tester,
        edges: const Offset(1, 1),
        by: const Offset(-100, -50),
      );
      expect(crop, isNotNull);
      expect(crop!.topLeft, Offset.zero);
      expect(crop.right, lessThan(1));
      expect(crop.bottom, lessThan(1));
    });

    testWidgets('dragging a handle far outwards stays inside the image', (
      tester,
    ) async {
      final crop = await dragAndCrop(
        tester,
        edges: const Offset(-1, -1),
        by: const Offset(-5000, -5000),
      );
      expect(crop, const Rect.fromLTWH(0, 0, 1, 1));
    });

    testWidgets('dragging a handle across the crop keeps a minimum size', (
      tester,
    ) async {
      final crop = await dragAndCrop(
        tester,
        edges: const Offset(1, 0),
        by: const Offset(-5000, 0),
      );
      expect(crop!.width, greaterThan(0));
      expect(crop.left, 0);
    });
  });
}
