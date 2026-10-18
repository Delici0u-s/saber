import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/i18n/strings.g.dart';

/// Lets the user pick a crop area for [image].
///
/// Pops with the crop as a fraction of the image (0 to 1 on each axis),
/// or null if cancelled.
class ImageCropDialog extends StatefulWidget {
  const new({super.key, required this.image});

  final PngEditorImage image;

  /// The key of the handle that moves the given crop [edges]
  /// (-1 for left/top, 1 for right/bottom, 0 for neither).
  static Key handleKey(Offset edges) => ValueKey(('cropHandle', edges));

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  /// The crop area as a fraction of the image.
  var crop = const Rect.fromLTWH(0, 0, 1, 1);

  /// The largest share of the screen the image may take up.
  static const _maxScreenFraction = 0.7;

  /// The smallest crop, in logical pixels on screen.
  static const _minCropSize = 32.0;

  /// The diameter of the drag handles, in logical pixels.
  static const _handleSize = 24.0;

  /// Moves the crop edges selected by [edges] (-1 for left/top, 1 for
  /// right/bottom, 0 for neither) by [delta], keeping the crop inside the
  /// image and at least [minSize] (as a fraction) big.
  /// Edges of (0, 0) move the whole crop.
  void _drag(Offset edges, Offset delta, Size minSize) {
    var Rect(:left, :top, :right, :bottom) = crop;
    if (edges == Offset.zero) {
      final dx = delta.dx.clamp(-left, 1 - right);
      final dy = delta.dy.clamp(-top, 1 - bottom);
      setState(() => crop = crop.translate(dx, dy));
      return;
    }
    if (edges.dx < 0) {
      left = (left + delta.dx).clamp(0.0, right - minSize.width);
    }
    if (edges.dx > 0) {
      right = (right + delta.dx).clamp(left + minSize.width, 1.0);
    }
    if (edges.dy < 0) {
      top = (top + delta.dy).clamp(0.0, bottom - minSize.height);
    }
    if (edges.dy > 0) {
      bottom = (bottom + delta.dy).clamp(top + minSize.height, 1.0);
    }
    setState(() => crop = Rect.fromLTRB(left, top, right, bottom));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final naturalSize = widget.image.naturalSize;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(
              t.editor.imageOptions.crop,
              style: TextTheme.of(context).titleLarge,
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screen.width * _maxScreenFraction,
                  maxHeight: screen.height * _maxScreenFraction,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Leave half a handle around the image, so the handles on
                    // its edges are fully inside this widget and can be grabbed.
                    const inset = _handleSize / 2;
                    final scale = min(
                      (constraints.maxWidth - 2 * inset) / naturalSize.width,
                      (constraints.maxHeight - 2 * inset) / naturalSize.height,
                    );
                    final size = naturalSize * scale;
                    final imageRect = const Offset(inset, inset) & size;
                    final cropRect = Rect.fromLTRB(
                      imageRect.left + crop.left * size.width,
                      imageRect.top + crop.top * size.height,
                      imageRect.left + crop.right * size.width,
                      imageRect.top + crop.bottom * size.height,
                    );
                    final minSize = Size(
                      min(1.0, _minCropSize / size.width),
                      min(1.0, _minCropSize / size.height),
                    );
                    Offset toFraction(Offset delta) =>
                        Offset(delta.dx / size.width, delta.dy / size.height);

                    return Center(
                      child: SizedBox.fromSize(
                        size: imageRect.inflate(inset).size,
                        child: Stack(
                          children: [
                            Positioned.fromRect(
                              rect: imageRect,
                              child: Image(
                                image: widget.image.imageProvider!,
                                fit: BoxFit.fill,
                              ),
                            ),
                            Positioned.fromRect(
                              rect: imageRect,
                              child: CustomPaint(
                                painter: _OutsideCropPainter(
                                  cropRect: cropRect.shift(-imageRect.topLeft),
                                  color: colorScheme.scrim.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fromRect(
                              rect: cropRect,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) => _drag(
                                  Offset.zero,
                                  toFraction(details.delta),
                                  minSize,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            for (final edges in _handleEdges)
                              Positioned(
                                left:
                                    cropRect.center.dx +
                                    edges.dx * cropRect.width / 2 -
                                    inset,
                                top:
                                    cropRect.center.dy +
                                    edges.dy * cropRect.height / 2 -
                                    inset,
                                child: GestureDetector(
                                  key: ImageCropDialog.handleKey(edges),
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (details) => _drag(
                                    edges,
                                    toFraction(details.delta),
                                    minSize,
                                  ),
                                  child: Container(
                                    width: _handleSize,
                                    height: _handleSize,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colorScheme.onPrimary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.common.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(crop),
                  child: Text(t.editor.imageOptions.crop),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Which crop edges each handle moves: corners and edge midpoints.
  static final _handleEdges = [
    for (final dx in const [-1.0, 0.0, 1.0])
      for (final dy in const [-1.0, 0.0, 1.0])
        if (dx != 0 || dy != 0) Offset(dx, dy),
  ];
}

/// Darkens everything outside the crop area.
class _OutsideCropPainter extends CustomPainter {
  const new({required this.cropRect, required this.color});

  final Rect cropRect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(cropRect),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OutsideCropPainter oldDelegate) =>
      cropRect != oldDelegate.cropRect || color != oldDelegate.color;
}
