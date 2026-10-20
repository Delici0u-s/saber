import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  testGoldens(
    'turning or stretching a page reshapes its background and ink, with undo',
    (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlavorConfig.setup();
      setupMockPathProvider();
      setupMockPrinting();
      EditorImage.shouldLoadOutImmediately = true;
      await tester.runAsync(FileManager.init);

      await tester.pumpWidget(
        TranslationProvider(
          child: ScreenshotApp(
            device: GoldenScreenshotDevices.androidPhone.device,
            home: Editor(),
          ),
        ),
      );
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);
      await tester.pumpAndSettle();

      final page = state.coreInfo.pages.first;
      final portrait = page.size;
      List<Stroke> strokes() => page.strokes;
      Offset onScreen(Offset onPage) => page.renderBox!.localToGlobal(onPage);
      Future<void> drag(Offset from, Offset to) async {
        final gesture = await tester.startGesture(from);
        for (var t = 1; t <= 10; t++) {
          await gesture.moveTo(Offset.lerp(from, to, t / 10)!);
          await tester.pump(const Duration(milliseconds: 8));
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // A level line near the top left.
      final lineStart = Offset(portrait.width * 0.1, portrait.height * 0.15);
      final lineEnd = lineStart + Offset(portrait.width * 0.3, 0);
      await drag(onScreen(lineStart), onScreen(lineEnd));
      final original = strokes().single;

      const svgString = '<svg height="100" width="100"></svg>';
      SvgEditorImage svg(Rect dstRect) => SvgEditorImage(
        id: state.coreInfo.nextImageId++,
        assetCache: state.coreInfo.assetCache,
        svgString: svgString,
        svgFile: null,
        pageIndex: 0,
        pageSize: page.size,
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        newImage: false,
        dstRect: dstRect,
        naturalSize: dstRect.size,
      );
      // The background fills the page; the image is wide and low, so turned
      // it would stick out on the left.
      final background = svg(Offset.zero & portrait);
      final imageRect = Rect.fromLTWH(
        0,
        portrait.height * 0.9,
        portrait.width * 0.9,
        portrait.height * 0.05,
      );
      final image = svg(imageRect);
      page.backgroundImage = background;
      page.images.add(image);

      void expectTurned() {
        expect(page.size, portrait.flipped);
        expect(background.quarterTurns, 1);
        expect(background.dstRect, Offset.zero & portrait.flipped);

        // (x, y) went to (height - y, x): the line now stands up on the right.
        final bounds = strokes().single.lowQualityPath.getBounds();
        final slack = original.options.size;
        expect(
          bounds.center.dx,
          closeTo(portrait.height - lineStart.dy, slack),
        );
        expect(bounds.top, closeTo(lineStart.dx, slack));
        expect(bounds.bottom, closeTo(lineEnd.dx, slack));
        expect(strokes().single.options.size, original.options.size);

        // The image keeps its orientation and size, moved onto the page.
        expect(image.dstRect.size, imageRect.size);
        expect(image.dstRect.left, 0);
        expect(image.dstRect.center.dy, closeTo(imageRect.center.dx, 1e-9));
      }

      state.rotatePage(0);
      await tester.pumpAndSettle();
      expectTurned();
      expect(
        find.byWidgetPredicate((w) => w is RotatedBox && w.quarterTurns == 1),
        findsOneWidget,
      );

      // One undo step puts everything back as it was.
      state.undo();
      await tester.pumpAndSettle();
      expect(page.size, portrait);
      expect(background.quarterTurns, 0);
      expect(background.dstRect, Offset.zero & portrait);
      expect(image.dstRect, imageRect);
      expect(strokes().single, same(original));

      state.redo();
      await tester.pumpAndSettle();
      expectTurned();

      // The turn is saved with the background.
      final json = background.toJson(OrderedAssetCache());
      expect(json['qt'], 1);
      final loaded = EditorImage.fromJson(
        json,
        inlineAssets: [utf8.encode(svgString)],
        sbnPath: '',
        assetCache: state.coreInfo.assetCache,
      );
      expect(loaded.quarterTurns, 1);
      expect(loaded.copy().quarterTurns, 1);

      // Four turns make a full turn.
      for (var i = 0; i < 3; i++) {
        state.rotatePage(0);
      }
      await tester.pumpAndSettle();
      expect(page.size, portrait);
      expect(background.quarterTurns, 0);
      final bounds = strokes().single.lowQualityPath.getBounds();
      final originalBounds = original.lowQualityPath.getBounds();
      expect(bounds.left, closeTo(originalBounds.left, 0.01));
      expect(bounds.top, closeTo(originalBounds.top, 0.01));
      expect(bounds.right, closeTo(originalBounds.right, 0.01));
      // An unturned image saves nothing extra, as before.
      expect(background.toJson(OrderedAssetCache()).containsKey('qt'), isFalse);

      // Stretching to landscape: everything stretches to the new edges.
      final beforeStretch = strokes().single;
      final beforeBounds = beforeStretch.lowQualityPath.getBounds();
      final imageBefore = image.dstRect;
      final sx = portrait.height / portrait.width;
      final sy = portrait.width / portrait.height;
      void expectRect(Rect actual, Rect expected) {
        for (final (a, e) in [
          (actual.left, expected.left),
          (actual.top, expected.top),
          (actual.right, expected.right),
          (actual.bottom, expected.bottom),
        ]) {
          expect(a, closeTo(e, 0.01));
        }
      }

      Rect stretched(Rect rect) => Rect.fromLTRB(
        rect.left * sx,
        rect.top * sy,
        rect.right * sx,
        rect.bottom * sy,
      );

      state.stretchPage(0);
      await tester.pumpAndSettle();
      expect(page.size, portrait.flipped);
      expect(background.backgroundFit, BoxFit.fill);
      expect(background.quarterTurns, 0);
      expectRect(background.dstRect, Offset.zero & portrait.flipped);
      expectRect(image.dstRect, stretched(imageBefore));
      final stretchedBounds = strokes().single.lowQualityPath.getBounds();
      final slack = original.options.size;
      expect(
        stretchedBounds.center.dx,
        closeTo(beforeBounds.center.dx * sx, slack),
      );
      expect(
        stretchedBounds.center.dy,
        closeTo(beforeBounds.center.dy * sy, slack),
      );
      expect(stretchedBounds.width, greaterThan(beforeBounds.width * 1.2));
      expect(strokes().single.options.size, beforeStretch.options.size);

      // One undo step, and stretching back to portrait undoes it too.
      state.undo();
      await tester.pumpAndSettle();
      expect(page.size, portrait);
      expect(background.backgroundFit, BoxFit.contain);
      expect(image.dstRect, imageBefore);
      expect(strokes().single, same(beforeStretch));

      state.stretchPage(0);
      state.stretchPage(0);
      await tester.pumpAndSettle();
      expect(page.size, portrait);
      expectRect(image.dstRect, imageBefore);
      expectRect(strokes().single.lowQualityPath.getBounds(), beforeBounds);
    },
  );
}
