import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/canvas/hud/canvas_gesture_lock_btn.dart';
import 'package:saber/components/canvas/hud/canvas_zoom_indicator.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class CanvasHud extends HookWidget {
  const new({
    super.key,
    required this.transformationController,
    required this.zoomLock,
    required this.setZoomLock,
    required this.resetZoom,
    required this.zoomToRealSize,
    required this.isAtRealSize,
    required this.singleFingerPanLock,
    required this.setSingleFingerPanLock,
    required this.axisAlignedPanLock,
    required this.setAxisAlignedPanLock,
  });

  final TransformationController transformationController;
  final bool zoomLock;
  final ValueChanged<bool> setZoomLock;
  final VoidCallback? resetZoom;

  /// Zooms so pages show at their physical size, or null if zoom is locked.
  final VoidCallback? zoomToRealSize;
  final bool Function() isAtRealSize;
  final bool singleFingerPanLock;
  final ValueChanged<bool> setSingleFingerPanLock;
  final bool axisAlignedPanLock;
  final ValueChanged<bool> setAxisAlignedPanLock;

  /// Distance of the HUD from the canvas edges, and between its buttons.
  static const _margin = 5.0;
  static const _spacing = 5.0;

  @override
  Widget build(BuildContext context) {
    /// The opacity of the HUD
    final opacity = useState(0.0);

    /// A timer to set the opacity to 0 after inactivity
    final hideTimer = useRef<Timer?>(null);
    useEffect(() => hideTimer.value?.cancel, [hideTimer.value]);

    void onTransform() {
      opacity.value = 1;
      hideTimer.value?.cancel();
      hideTimer.value = Timer(
        const Duration(seconds: 5),
        () => opacity.value = 0,
      );
    }

    useOnListenableChange(transformationController, onTransform);

    return IgnorePointer(
      ignoring: opacity.value < 0.5,
      child: AnimatedOpacity(
        opacity: opacity.value,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          children: [
            Positioned(
              top: _margin,
              left: _margin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _spacing,
                children: [
                  CanvasGestureLockBtn(
                    lock: zoomLock,
                    setLock: setZoomLock,
                    icon: zoomLock ? Icons.lock : Icons.lock_open,
                    tooltip: zoomLock
                        ? t.editor.hud.unlockZoom
                        : t.editor.hud.lockZoom,
                  ),
                  CanvasGestureLockBtn(
                    lock: singleFingerPanLock,
                    setLock: setSingleFingerPanLock,
                    icon: singleFingerPanLock ? Icons.pinch : Icons.swipe_up,
                    tooltip: singleFingerPanLock
                        ? t.editor.hud.unlockSingleFingerPan
                        : t.editor.hud.lockSingleFingerPan,
                  ),
                  CanvasGestureLockBtn(
                    lock: axisAlignedPanLock,
                    setLock: setAxisAlignedPanLock,
                    tooltip: axisAlignedPanLock
                        ? t.editor.hud.unlockAxisAlignedPan
                        : t.editor.hud.lockAxisAlignedPan,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: axisAlignedPanLock ? 0 : 1 / 8,
                      child: const Icon(Symbols.drag_pan),
                    ),
                  ),
                  if (zoomToRealSize != null)
                    AnimatedBuilder(
                      animation: transformationController,
                      builder: (context, _) => CanvasGestureLockBtn(
                        lock: isAtRealSize(),
                        setLock: (_) => zoomToRealSize!(),
                        icon: Symbols.straighten,
                        tooltip: t.editor.hud.realSize(
                          paper: EditorPage.paperName(
                            stows.realSizeWidthMm.value,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: _margin,
              right: _margin,
              child: AnimatedBuilder(
                animation: transformationController,
                builder: (context, _) => CanvasZoomIndicator(
                  scale: transformationController.value.approxScale,
                  resetZoom: resetZoom,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
