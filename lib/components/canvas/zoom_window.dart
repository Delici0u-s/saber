import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// A magnified view of part of a page (the box), shown in a panel: what's
/// written big in the panel appears small on the page, like GoodNotes' zoom
/// window. See [ZoomWindowBox] and [ZoomWindowPanel].
class ZoomWindow extends ChangeNotifier {
  /// The box starts this fraction of the page wide, and is never narrower
  /// than [minWidthFraction] of it.
  static const startWidthFraction = 1 / 3, minWidthFraction = 1 / 20;

  /// The strip at the right of the panel where ending a stroke moves the
  /// box on (if [autoAdvance]), as a fraction of the panel's width; the box
  /// moves on by the rest of its width, so what was written there stays in
  /// view.
  static const marginFraction = 0.2;

  /// The panel takes this fraction of the canvas's height, at least and at
  /// most.
  static const minPanelFraction = 0.2, maxPanelFraction = 0.6;

  bool get visible => _visible;
  var _visible = false;

  /// The page the box is on, and the box on it.
  int get pageIndex => _pageIndex;
  var _pageIndex = 0;
  Rect get rect => _rect;
  var _rect = Rect.zero;

  var _pageSize = Size.zero;

  /// Where lines start: the box's left edge when it was last moved by hand,
  /// which [newLine] goes back to.
  var _lineStart = 0.0;

  /// The panel's width over its height, which the box has too.
  var _aspect = 1.0;

  /// Whether ending a stroke in the margin moves the box on, see
  /// [marginFraction].
  bool get autoAdvance => stows.zoomWindowAutoAdvance.value;
  set autoAdvance(bool autoAdvance) {
    stows.zoomWindowAutoAdvance.value = autoAdvance;
    notifyListeners();
  }

  /// How much of the canvas's height the panel takes.
  double get panelFraction => stows.zoomWindowPanelFraction.value;
  set panelFraction(double fraction) {
    stows.zoomWindowPanelFraction.value = fraction.clamp(
      minPanelFraction,
      maxPanelFraction,
    );
    notifyListeners();
  }

  /// Shows the box on page [pageIndex] (of [pageSize]), at the top left of
  /// [onScreen] (the part of the page on screen), on a line of the page's
  /// [lineHeight].
  void show({
    required int pageIndex,
    required Size pageSize,
    required Rect onScreen,
    required double lineHeight,
  }) {
    _pageIndex = pageIndex;
    _pageSize = pageSize;
    _lineStart = max(0, onScreen.left);
    final width = pageSize.width * startWidthFraction;
    final top = (max(0, onScreen.top) / lineHeight).floor() * lineHeight;
    _rect = _fit(Rect.fromLTWH(_lineStart, top, width, width / _aspect));
    _visible = true;
    notifyListeners();
  }

  void hide() {
    _visible = false;
    notifyListeners();
  }

  /// Sets the panel's (and so the box's) width over height.
  void setAspect(double aspect) {
    if (!(aspect > 0) || aspect == _aspect) return;
    _aspect = aspect;
    _rect = _fit(_rect.topLeft & Size(_rect.width, _rect.width / aspect));
    notifyListeners();
  }

  /// Moves the box by [delta], by hand.
  void moveBy(Offset delta) {
    _rect = _fit(_rect.shift(delta));
    _lineStart = _rect.left;
    notifyListeners();
  }

  /// Makes the box [delta] wider (less magnified), or narrower.
  void resizeBy(double delta) {
    final width = _rect.width + delta;
    _rect = _fit(_rect.topLeft & Size(width, width / _aspect));
    notifyListeners();
  }

  double get _step => _rect.width * (1 - marginFraction);

  /// Moves the box on along the line, or to the next line if there's no
  /// room left on this one for more than the margin.
  void forward(double lineHeight) {
    if (_pageSize.width - _rect.right < _rect.width * marginFraction) {
      return newLine(lineHeight);
    }
    _rect = _fit(_rect.shift(Offset(_step, 0)));
    notifyListeners();
  }

  void back() {
    _rect = _fit(_rect.shift(Offset(-_step, 0)));
    notifyListeners();
  }

  /// Moves the box down by as many lines of [lineHeight] as it's high, and
  /// back to where lines start.
  void newLine(double lineHeight) {
    final lines = max(1, (_rect.height / lineHeight).round());
    _rect = _fit(
      Offset(_lineStart, _rect.top + lines * lineHeight) & _rect.size,
    );
    notifyListeners();
  }

  /// Whether [fraction] of the way across the panel is in the margin.
  static bool isInMargin(double fraction) => fraction >= 1 - marginFraction;

  /// [rect] with [_aspect], kept on the page and no narrower than the
  /// minimum.
  Rect _fit(Rect rect) {
    if (_pageSize.isEmpty) return rect;
    final width = min(
      max(rect.width, _pageSize.width * minWidthFraction),
      min(_pageSize.width, _pageSize.height * _aspect),
    );
    final height = width / _aspect;
    return Rect.fromLTWH(
      rect.left.clamp(0, _pageSize.width - width),
      rect.top.clamp(0, _pageSize.height - height),
      width,
      height,
    );
  }
}

/// The [ZoomWindow]'s box on its page: an outline with the auto-advance
/// margin shaded, a handle at the top left to move it and one at the bottom
/// right to resize it. The inside lets pointers through, so the page can
/// still be drawn on.
class ZoomWindowBox extends StatelessWidget {
  const new({super.key, required this.zoomWindow, required this.scale});

  final ZoomWindow zoomWindow;

  /// The page's zoom, so the handles keep their size on screen.
  final double scale;

  /// The handles' size and the outline's width, in screen pixels.
  static const _handleSize = kMinInteractiveDimension / 2, _lineWidth = 2.0;

  /// The opacity of the shaded auto-advance margin.
  static const marginOpacity = 0.1;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final handle = _handleSize / scale;
    Widget handleAt(
      Alignment alignment,
      IconData icon,
      ValueChanged<Offset> drag,
    ) => Align(
      alignment: alignment,
      // Claims the pointer straight away, so the canvas doesn't draw or pan
      // with it.
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          onPointerMove: (event) => drag(event.localDelta),
          child: Container(
            width: handle,
            height: handle,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: handle * 2 / 3,
              color: colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );

    // The handles are inside the corners, so they stay on the page.
    return Positioned.fromRect(
      rect: zoomWindow.rect,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.primary,
                    width: _lineWidth / scale,
                  ),
                ),
                child: zoomWindow.autoAdvance
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: ZoomWindow.marginFraction,
                          heightFactor: 1,
                          child: ColoredBox(
                            color: colorScheme.primary.withValues(
                              alpha: marginOpacity,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          handleAt(Alignment.topLeft, Icons.open_with, zoomWindow.moveBy),
          handleAt(
            Alignment.bottomRight,
            Icons.open_in_full,
            (delta) => zoomWindow.resizeBy(delta.dx),
          ),
        ],
      ),
    );
  }
}

/// The [ZoomWindow]'s panel: the box's part of the page, magnified to fill
/// it, with buttons to move the box along.
class ZoomWindowPanel extends StatelessWidget {
  const new({
    super.key,
    required this.zoomWindow,
    required this.coreInfo,
    required this.currentStroke,
    required this.onPointer,
    required this.onResize,
  });

  final ZoomWindow zoomWindow;
  final EditorCoreInfo coreInfo;

  /// The stroke being drawn, if it's on the box's page.
  final Stroke? currentStroke;

  /// A pointer event in the panel, at [onPage] on the box's page, and
  /// whether it's in the auto-advance margin.
  final void Function(PointerEvent event, Offset onPage, bool inMargin)
  onPointer;

  /// The panel's top edge was dragged down by this many pixels.
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final strings = t.editor.zoomWindow;
    final lineHeight = coreInfo.lineHeight.toDouble();
    return ListenableBuilder(
      listenable: zoomWindow,
      builder: (context, _) => Material(
        color: colorScheme.surfaceContainer,
        child: Column(
          children: [
            // The bar: buttons, and dragging it resizes the panel.
            GestureDetector(
              behavior: .opaque,
              onVerticalDragUpdate: (details) => onResize(details.delta.dy),
              child: Row(
                children: [
                  IconButton(
                    tooltip: strings.back,
                    onPressed: zoomWindow.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: strings.forward,
                    onPressed: () => zoomWindow.forward(lineHeight),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  IconButton(
                    tooltip: strings.newLine,
                    onPressed: () => zoomWindow.newLine(lineHeight),
                    icon: const Icon(Icons.keyboard_return),
                  ),
                  IconButton(
                    tooltip: strings.autoAdvance,
                    isSelected: zoomWindow.autoAdvance,
                    onPressed: () =>
                        zoomWindow.autoAdvance = !zoomWindow.autoAdvance,
                    icon: const Icon(Icons.fast_forward_outlined),
                    selectedIcon: const Icon(Icons.fast_forward),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        width: kMinInteractiveDimension,
                        height: kMinInteractiveDimension / 12,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant,
                          borderRadius: .circular(kMinInteractiveDimension),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.close,
                    onPressed: zoomWindow.hide,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _buildView(context, constraints.biggest),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildView(BuildContext context, Size size) {
    if (size.isEmpty) {
      return const SizedBox.shrink();
    }
    // The box takes the panel's proportions (after this frame: it notifies).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => zoomWindow.setAspect(size.aspectRatio),
    );
    final pageIndex = zoomWindow.pageIndex;
    if (pageIndex >= coreInfo.pages.length) return const SizedBox.shrink();
    final page = coreInfo.pages[pageIndex];
    final rect = zoomWindow.rect;
    final scale = size.width / rect.width;
    final colorScheme = ColorScheme.of(context);

    void forward(PointerEvent event) => onPointer(
      event,
      rect.topLeft + event.localPosition / scale,
      ZoomWindow.isInMargin(event.localPosition.dx / size.width),
    );

    return Listener(
      behavior: .opaque,
      onPointerDown: forward,
      onPointerMove: forward,
      onPointerUp: forward,
      onPointerCancel: forward,
      child: ClipRect(
        child: Stack(
          children: [
            OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: -rect.topLeft,
                    child: _PageMirror(
                      coreInfo: coreInfo,
                      page: page,
                      pageIndex: pageIndex,
                      currentStroke: currentStroke,
                      scale: scale,
                    ),
                  ),
                ),
              ),
            ),
            if (zoomWindow.autoAdvance)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: size.width * ZoomWindow.marginFraction,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: colorScheme.primary.withValues(
                      alpha: ZoomWindowBox.marginOpacity,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [page] drawn like on the canvas (background, images and strokes,
/// without typed text), at [scale].
class _PageMirror extends StatelessWidget {
  const new({
    required this.coreInfo,
    required this.page,
    required this.pageIndex,
    required this.currentStroke,
    required this.scale,
  });

  final EditorCoreInfo coreInfo;
  final EditorPage page;
  final int pageIndex;
  final Stroke? currentStroke;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: InnerCanvas.backgroundPainter(context, coreInfo, page),
      foregroundPainter: CanvasPainter(
        repaint: page,
        invert: InnerCanvas.invertIn(context),
        strokes: page.strokes,
        laserStrokes: page.laserStrokes,
        currentStroke: currentStroke,
        currentSelection: null,
        primaryColor: theme.colorScheme.primary,
        page: page,
        showPageIndicator: false,
        pageIndex: pageIndex,
        totalPages: coreInfo.pages.length,
        currentScale: scale,
        defaultTextStyle: theme.textTheme.bodyMedium!,
      ),
      child: SizedBox.fromSize(
        size: page.size,
        child: Stack(
          children: [
            if (page.backgroundImage case final image?)
              CanvasImage(
                filePath: coreInfo.filePath,
                image: image,
                pageSize: page.size,
                setAsBackground: null,
                isBackground: true,
                readOnly: true,
              ),
            for (final image in page.images)
              CanvasImage(
                filePath: coreInfo.filePath,
                image: image,
                pageSize: page.size,
                setAsBackground: null,
                readOnly: true,
              ),
          ],
        ),
      ),
    );
  }
}
