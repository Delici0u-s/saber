import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/screen_density.dart';

void main() {
  group('CanvasGestureDetector.realSizeScaleFor', () {
    for (final pixelsPerInch in const [96.0, 160.0, 400.0]) {
      final pixelsPerMm = pixelsPerInch / ScreenDensity.mmPerInch;
      final realWidth = EditorPage.defaultWidthMm * pixelsPerMm;

      for (final containerWidth in const [200.0, 999.0, 1000.0, 5000.0]) {
        test('shows the page at its physical width '
            '(${pixelsPerInch}ppi, ${containerWidth}px container)', () {
          final scale = CanvasGestureDetector.realSizeScaleFor(
            containerWidth: containerWidth,
            logicalPixelsPerMm: pixelsPerMm,
          );

          // At 1.0x the page is the container's width, but at most its own.
          final widthAt1x = containerWidth < EditorPage.defaultWidth
              ? containerWidth
              : EditorPage.defaultWidth;
          expect(widthAt1x * scale, closeTo(realWidth, 1e-9));
        });
      }
    }
  });
}
