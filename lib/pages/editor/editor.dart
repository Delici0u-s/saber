import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as flutter_quill;
import 'package:keybinder/keybinder.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/components/canvas/select_result.dart';
import 'package:saber/components/canvas/zoom_window.dart';
import 'package:saber/components/editor/read_only_banner.dart';
import 'package:saber/components/home/search_notes_button.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/editor_bottom_sheet.dart';
import 'package:saber/components/toolbar/editor_page_manager.dart';
import 'package:saber/components/toolbar/toolbar.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/selection_transform.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/nextcloud/sync_scheduler.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/double_tap_to_erase.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/scribble_erase.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/data/tools/select_lasso.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/tape.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/pdf_page_chooser.dart';
import 'package:saber/pages/editor/side_by_side.dart';
import 'package:saber/pages/home/whiteboard.dart';
import 'package:sbn/change.dart';
import 'package:super_clipboard/super_clipboard.dart';

typedef _PhotoInfo = ({Uint8List bytes, String extension});

/// How an [Editor] is shown inside another (side by side): the other's
/// toolbar picks the tool, and this one can be kept still or read-only.
@immutable
class EditorEmbedding {
  const new({
    required this.getTool,
    required this.setTool,
    required this.changed,
    this.lockPosition = false,
    this.writable = false,
  });

  /// The other editor's tool, and changing it (e.g. the stylus button
  /// switching to the eraser here).
  final Tool Function() getTool;
  final ValueChanged<Tool> setTool;

  /// Called when what the other editor's toolbar shows may have changed,
  /// e.g. a selection was made here.
  final VoidCallback changed;

  /// Whether it can't be scrolled or zoomed.
  final bool lockPosition;

  /// Whether it can be written in, rather than only looked at.
  final bool writable;
}

class Editor extends StatefulWidget {
  new({super.key, String? path, this.customTitle, this.pdfPath, this.embedding})
    : initialPath = path != null
          ? Future.value(path)
          : FileManager.newFilePath('/'),
      needsNaming = path == null;

  /// Set when shown inside another editor (side by side): then it's only
  /// the canvas, without its own app bar and toolbar.
  final EditorEmbedding? embedding;

  final Future<String> initialPath;
  final bool needsNaming;

  final String? customTitle;
  final String? pdfPath;

  /// The file extension used by the app.
  /// Files with this extension are
  /// encoded in BSON format.
  static const extension = '.sbn2';

  /// The old file extension used by the app.
  /// Files with this extension are
  /// encoded in JSON format.
  static const extensionOldJson = '.sbn';

  static const double gapBetweenPages = 16;

  /// Returns true if [path] belongs to a hidden file
  /// used by other functions of the app
  static bool isReservedPath(String path) {
    return _reservedFilePaths.any((regex) => regex.hasMatch(path));
  }

  static final _reservedFilePaths = <RegExp>[
    RegExp(RegExp.escape(Whiteboard.filePath)),
  ];

  /// Whether the platform can rasterize a pdf
  static var canRasterPdf = true;

  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor> {
  final log = Logger('EditorState');

  late var coreInfo = EditorCoreInfo.placeholder;

  final _canvasGestureDetectorKey = GlobalKey<CanvasGestureDetectorState>();
  final _transformationController = TransformationController();

  /// A straight edge to draw along, toggled in the toolbar.
  final ruler = Ruler();

  /// A magnified view of part of a page to write in, toggled in the
  /// toolbar.
  final zoomWindow = ZoomWindow();

  /// A note or PDF shown next to this one, opened from the menu.
  final sideBySide = SideBySide();

  /// Whether the export bar is open, toggled by the share button.
  final _showExportOptions = ValueNotifier(false);

  /// The pointer drawing in the [zoomWindow]'s panel, if any.
  int? _zoomWindowPointer;

  /// Whether the stylus button is held, as last seen in the zoom window.
  var _zoomWindowStylusButton = false;

  /// Whether the stroke being drawn comes from the zoom window (so it isn't
  /// drawn along the ruler, which is on the canvas).
  var _drawingInZoomWindow = false;

  /// The ruler side the current stroke is drawn along, while the pen is
  /// against it (see [Ruler.snapFor]).
  RulerSnap? _rulerSnap;

  double get scrollY {
    final transformation = _transformationController.value;
    final scale = transformation.approxScale;
    final translation = transformation.getTranslation();
    final gestureDetector = _canvasGestureDetectorKey.currentState;

    if (gestureDetector == null) {
      log.warning('scrollY: Could not find CanvasGestureDetectorState');
      return translation.y / scale;
    } else {
      final middle = gestureDetector.containerBounds.maxHeight / 2;
      return (translation.y - middle) / scale + middle;
    }
  }

  var history = EditorHistory();

  late bool needsNaming = widget.needsNaming && stows.editorPromptRename.value;

  late Tool _currentTool = () {
    switch (stows.lastTool.value) {
      case .fountainPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.fountainPen();
        }
        return Pen.currentPen;
      case .ballpointPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.ballpointPen();
        }
        return Pen.currentPen;
      case .shapePen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = ShapePen();
        }
        return Pen.currentPen;
      case .highlighter:
        return Tape.highlighterTab;
      case .pencil:
        return Pencil.currentPencil;
      case .eraser:
        return Eraser.currentEraser;
      case .select || .selectBox:
        return Select.current;
      case .textEditing:
        return Tool.textEditing;
      case .laserPointer:
        return LaserPointer.currentLaserPointer;
    }
  }();
  Tool get currentTool => widget.embedding?.getTool() ?? _currentTool;
  set currentTool(Tool tool) {
    _currentTool = tool;
    if (tool is Eraser) {
      Eraser.currentEraser = tool;
    } else {
      _lastNonEraserTool = tool;
    }
    stows.lastTool.value = tool.toolId;
    widget.embedding?.setTool(tool);
  }

  ValueNotifier<SavingState> savingState = ValueNotifier(SavingState.saved);
  Timer? _delayedSaveTimer;
  Timer? _watchServerTimer;
  StreamSubscription<SaberSyncFile>? _noteDownloadSubscription;

  // used to prevent accidentally drawing when pinch zooming
  var lastSeenPointerCount = 0;
  Timer? _lastSeenPointerCountTimer;

  ValueNotifier<QuillStruct?> quillFocus = ValueNotifier(null);

  /// The last non-Eraser [currentTool] value.
  late Tool _lastNonEraserTool = Pen.currentPen;

  /// If the stylus button is pressed, or was pressed, during the current draw gesture.
  ///
  /// For now, this also includes when an [PointerDeviceKind.inverseStylus] is
  /// used since the stylus rear-end and stylus button currently act the same.
  /// If we add customized button bindings, we may have to separate this again.
  var stylusButtonWasPressed = false;

  @override
  void initState() {
    DynamicMaterialApp.addFullscreenListener(_setState);
    zoomWindow.addListener(_onZoomWindowChanged);
    sideBySide.addListener(_setState);

    _initAsync();
    _assignKeybindings();
    _noteDownloadSubscription = syncer.downloader.transferStream.listen(
      _onFileDownloaded,
    );
    Pen.onDetectedShapeChanged = _setState;

    super.initState();
  }

  void _initAsync() async {
    final filePath = await widget.initialPath;
    filenameTextEditingController.text = p.basename(filePath);

    if (needsNaming) {
      filenameTextEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filenameTextEditingController.text.length,
      );
    }

    await _loadCoreInfo(filePath);

    if (widget.pdfPath != null) {
      await importPdfFromFilePath(widget.pdfPath!);
    }
  }

  Future _loadCoreInfo(String filePath) async {
    await _applyCoreInfo(await EditorCoreInfo.loadFromFilePath(filePath));
  }

  Future _applyCoreInfo(EditorCoreInfo loaded) async {
    coreInfo = loaded;
    if (coreInfo.readOnly) {
      log.info('Loaded file as read-only: ${coreInfo.readOnlyReason}');
    }

    for (int pageIndex = 0; pageIndex < coreInfo.pages.length; pageIndex++) {
      listenToQuillChanges(coreInfo.pages[pageIndex].quill, pageIndex);
    }

    if (coreInfo.isEmpty) {
      createPage(-1);
    } else {
      for (final page in coreInfo.pages) {
        page.backgroundImage?.onMoveImage = onMoveImage;
        page.backgroundImage?.onDeleteImage = onDeleteImage;
        page.backgroundImage?.onMiscChange = autosaveAfterDelay;
        for (final image in page.images) {
          image.onMoveImage = onMoveImage;
          image.onDeleteImage = onDeleteImage;
          image.onMiscChange = autosaveAfterDelay;
          image.onReplaceImage = onReplaceImage;
        }
      }
    }

    if (currentTool == Tool.textEditing) {
      int pageIndex;
      if (coreInfo.initialPageIndex != null) {
        pageIndex = coreInfo.initialPageIndex!;
      } else {
        pageIndex = 0;
      }
      assert(pageIndex < coreInfo.pages.length);

      quillFocus.value = coreInfo.pages[pageIndex].quill
        ..focusNode.requestFocus();
    }

    if (coreInfo.filePath == Whiteboard.filePath &&
        stows.autoClearWhiteboardOnExit.value &&
        Whiteboard.needsToAutoClearWhiteboard) {
      // clear whiteboard (and add to history)
      clearAllPages();

      // save cleared whiteboard
      await saveToFile();
      Whiteboard.needsToAutoClearWhiteboard = false;
    } else {
      setState(() {});
    }
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlZ, _ctrlY, _ctrlShiftZ;
  void _assignKeybindings() {
    _ctrlZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    _ctrlY = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyY),
    ], inclusive: true);
    _ctrlShiftZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    // Every editor binds them; only one acts on them, see [_shortcutTarget].
    void ifTarget(VoidCallback action) {
      final target = _shortcutTarget;
      if (target == this ||
          (widget.embedding == null && !(target?.mounted ?? false))) {
        action();
      }
    }

    Keybinder.bind(_ctrlZ!, () => ifTarget(undo));
    Keybinder.bind(_ctrlY!, () => ifTarget(redo));
    Keybinder.bind(_ctrlShiftZ!, () => ifTarget(redo));
  }

  /// The editor keyboard shortcuts (undo, redo) act on, when two are open
  /// side by side: the one last drawn in, or else the main one.
  static EditorState? _shortcutTarget;

  void _removeKeybindings() {
    if (_ctrlZ != null) Keybinder.remove(_ctrlZ!);
    if (_ctrlY != null) Keybinder.remove(_ctrlY!);
    if (_ctrlShiftZ != null) Keybinder.remove(_ctrlShiftZ!);
  }

  /// Creates pages until the given page index exists,
  /// plus an extra blank page
  void createPage(int pageIndex) {
    while (pageIndex >= coreInfo.pages.length - 1) {
      final page = EditorPage();
      coreInfo.pages.add(page);
      listenToQuillChanges(page.quill, coreInfo.pages.length - 1);
    }
  }

  void removeExcessPages() {
    bool removedAPage = false;

    // remove excess pages if all pages >= this one are empty
    for (int i = coreInfo.pages.length - 1; i >= 1; --i) {
      final thisPage = coreInfo.pages[i];
      final prevPage = coreInfo.pages[i - 1];
      if (thisPage.isEmpty && prevPage.isEmpty) {
        final page = coreInfo.pages.removeAt(i);
        page.dispose();
        removedAPage = true;
      } else {
        break;
      }
    }

    if (removedAPage) {
      // scroll to the last page (only if we're below the last page)

      final scrollY = this.scrollY;
      late final topOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length - 1,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );
      final bottomOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );

      if (scrollY < bottomOfLastPage) {
        _transformationController.value = Matrix4.translationValues(
          0,
          // Slight upwards offset so that the page is not flush with the top of the screen
          topOfLastPage + 50,
          0,
        );
      }
    }
  }

  void undo([EditorHistoryItem? item]) {
    if (item == null) {
      if (!history.canUndo) return;

      // if we disabled redo, re-enable it
      if (!history.canRedo) {
        // no redo is possible, so clear the redo stack
        history.clearRedo();
        // don't disable redoing anymore
        history.canRedo = true;
      }

      item = history.undo();
    }

    setState(() {
      switch (item!.type) {
        case .draw:
          for (final stroke in item.strokes) {
            coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
          }
          for (final image in item.images) {
            coreInfo.pages[image.pageIndex].images.remove(image);
          }
          removeExcessPages();

        case .erase:
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            coreInfo.pages[image.pageIndex].images.add(image);
            image.newImage = true;
          }

        case .eraseArea:
          for (final stroke in item.replacementStrokes) {
            coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
          }
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            coreInfo.pages[image.pageIndex].images.add(image);
            image.newImage = true;
          }

        case .deletePage:
          // make sure we already have a (blank/otherwise) page at this index
          createPage(item.pageIndex - 1);

          // insert the page at the correct index
          coreInfo.pages.insert(item.pageIndex, item.page!);

          // fix the page indices of all pages after this one
          for (int i = item.pageIndex + 1; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            page.updatePageIndex(i);
          }

        case .insertPage:
          // remove the page at the given index
          coreInfo.pages.removeAt(item.pageIndex);

          // fix the page indices of all pages after this one
          for (int i = item.pageIndex; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            page.updatePageIndex(i);
          }

        case .move:
          for (final stroke in item.strokes) {
            stroke.shift(Offset(-item.offset!.left, -item.offset!.top));
            if (item.pageIndex != item.pageIndexStart) {
              moveStrokeToPage(stroke, item.pageIndex, item.pageIndexStart!);
            }
          }
          final select = Select.current;
          if (select.doneSelecting && select.selectResult.owner == this) {
            select.selectResult.path = select.selectResult.path.shift(
              Offset(-item.offset!.left, -item.offset!.top),
            );
            if (item.pageIndex != item.pageIndexStart) {
              select.selectResult.pageIndexStart = item.pageIndexStart!;
              select.selectResult.pageIndex = item.pageIndexStart!;
            }
            _fitSelectionBox(select);
          }
          for (final image in item.images) {
            image.dstRect = .fromLTRB(
              image.dstRect.left - item.offset!.left,
              image.dstRect.top - item.offset!.top,
              image.dstRect.right - item.offset!.right,
              image.dstRect.bottom - item.offset!.bottom,
            );
            if (item.pageIndex != item.pageIndexStart) {
              moveImageToPage(image, item.pageIndex, item.pageIndexStart!);
            }
          }

        case .quillChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.undo();

        case .quillUndoneChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.redo();

        case .changeColor:
          for (final stroke in item.strokes) {
            stroke.color = item.colorChange![stroke]!.previous;
          }

        case .backgroundPattern:
          coreInfo.backgroundPattern = item.backgroundPatternChange!.previous;

        case .replaceImage:
          for (var i = 0; i < item.images.length; ++i) {
            _swapImage(item.replacementImages[i], item.images[i]);
          }

        case .transform:
          _swapStrokes(item.replacementStrokes, item.strokes);
          for (final MapEntry(key: image, value: change)
              in item.imageRectChange!.entries) {
            image.dstRect = change.previous;
          }
      }

      if (item.type != .move) {
        SelectLasso.currentSelect.unselect();
        SelectBox.currentSelect.unselect();
      }
    });

    autosaveAfterDelay();
  }

  void redo() {
    if (!history.canRedo) return;
    final item = history.redo();

    switch (item.type) {
      case .draw:
        undo(item.copyWith(type: .erase));
      case .erase:
        undo(item.copyWith(type: .draw));
      case .eraseArea:
        for (final stroke in item.strokes) {
          coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
        }
        for (final stroke in item.replacementStrokes) {
          createPage(stroke.pageIndex);
          coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
        }
      case .deletePage:
        undo(item.copyWith(type: .insertPage));
      case .insertPage:
        undo(item.copyWith(type: .deletePage));
      case .move:
        undo(
          item.copyWith(
            pageIndex: item.pageIndexStart,
            pageIndexStart: item.pageIndex,
            offset: .fromLTRB(
              -item.offset!.left,
              -item.offset!.top,
              -item.offset!.right,
              -item.offset!.bottom,
            ),
          ),
        );
      case .quillChange:
        undo(item.copyWith(type: .quillUndoneChange));
      case .quillUndoneChange: // this will never happen
        throw Exception('history should not contain quillUndoneChange items');
      case .changeColor:
        undo(
          item.copyWith(
            colorChange: item.colorChange!.map(
              (key, value) => MapEntry(key, value.reverse()),
            ),
          ),
        );
      case .backgroundPattern:
        undo(
          item.copyWith(
            backgroundPatternChange: item.backgroundPatternChange!.reverse(),
          ),
        );
      case .replaceImage:
        undo(
          item.copyWith(
            images: item.replacementImages,
            replacementImages: item.images,
          ),
        );
      case .transform:
        undo(
          item.copyWith(
            strokes: item.replacementStrokes,
            replacementStrokes: item.strokes,
            imageRectChange: item.imageRectChange!.map(
              (image, change) => MapEntry(image, change.reverse()),
            ),
          ),
        );
    }
  }

  int? onWhichPageIsFocalPoint(Offset focalPoint) {
    for (int i = 0; i < coreInfo.pages.length; ++i) {
      if (coreInfo.pages[i].renderBox == null) continue;
      final pageBounds = Offset.zero & coreInfo.pages[i].size;
      if (pageBounds.contains(
        coreInfo.pages[i].renderBox!.globalToLocal(focalPoint),
      ))
        return i;
    }
    return null;
  }

  /// The position of the previous draw gesture event.
  /// Used to move a selection.
  Offset previousPosition = .zero;

  /// The total offset of the current move gesture.
  /// Used to record a move in the history.
  Offset moveOffset = .zero;

  var isHovering = true;
  int? dragPageIndex;
  PointerDeviceKind? currentPointerKind;
  double? currentPressure;
  bool isDrawGesture(ScaleStartDetails details) {
    if (coreInfo.readOnly) return false;
    if (widget.embedding case final embedding? when !embedding.writable) {
      return false;
    }

    CanvasImage.activeListener
        .notifyListenersPlease(); // un-select active image

    _lastSeenPointerCountTimer?.cancel();
    if (lastSeenPointerCount >= 2) {
      // was a zoom gesture, ignore
      lastSeenPointerCount = lastSeenPointerCount;
      return false;
    } else if (details.pointerCount >= 2) {
      // is a zoom gesture, remove accidental stroke
      if (lastSeenPointerCount == 1 &&
          stows.editorFingerDrawing.value &&
          (currentTool is Pen || currentTool is Eraser)) {
        final item = history.removeAccidentalStroke();
        if (item != null) undo(item);
      }
      lastSeenPointerCount = details.pointerCount;
      return false;
    } else {
      // is a stroke
      lastSeenPointerCount = details.pointerCount;
    }

    dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);
    if (dragPageIndex == null) return false;

    if (currentTool == Tool.textEditing) {
      return false;
    } else if (stows.editorFingerDrawing.value ||
        currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus ||
        currentPressure != null) {
      return true;
    } else {
      log.fine('Non-stylus found, rejected stroke');
      return false;
    }
  }

  static const changePageThreshold = 50.0;

  /// Outlines the eraser on [page] at [center], or hides it if null.
  void _setEraserOutline(EditorPage page, Offset? center) {
    page.eraserOutline = center == null
        ? null
        : (center: center, radius: (currentTool as Eraser).size);
    page.redrawStrokes();
  }

  /// [globalPosition] moved onto [_rulerSnap], if the pen is against the
  /// ruler, so that the stroke runs along it and touches it.
  Offset _alongRuler(Offset globalPosition, EditorPage page) {
    final snap = _rulerSnap;
    if (snap == null) return globalPosition;
    final halfWidth =
        (currentTool as Pen).options.size / 2 * _screenScaleOf(page);
    return snap.project(globalPosition, gap: halfWidth);
  }

  void onDrawStart(ScaleStartDetails details) {
    _shortcutTarget = this;
    if (details.sourceTimeStamp case final time?) {
      _recentDrawStarts.add((time: time, historyLength: history.length));
      if (_recentDrawStarts.length > _recentDrawStartsKept) {
        _recentDrawStarts.removeAt(0);
      }
    }
    // The shape preview updates the editor being drawn in.
    Pen.onDetectedShapeChanged = _setState;
    final page = coreInfo.pages[dragPageIndex!];
    _rulerSnap = currentTool is Pen && !_drawingInZoomWindow
        ? ruler.snapFor(details.focalPoint)
        : null;
    final position = page.renderBox!.globalToLocal(
      _alongRuler(details.focalPoint, page),
    );
    history.canRedo = false;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragStart(
        position,
        page,
        dragPageIndex!,
        currentPressure,
      );
    } else if (currentTool is Eraser) {
      _setEraserOutline(page, position);
      for (final stroke in (currentTool as Eraser).checkForOverlappingStrokes(
        position,
        page.strokes,
      )) {
        page.strokes.remove(stroke);
      }
      removeExcessPages();
    } else if (currentTool is SelectLasso || currentTool is SelectBox) {
      final Select select = currentTool as Select;
      final result = select.selectResult;
      final selectedHere =
          select.doneSelecting &&
          result.owner == this &&
          result.pageIndex == dragPageIndex!;
      final box = selectedHere
          ? result.box?.copyWith(pixel: 1 / _screenScaleOf(page))
          : null;
      if (box?.handleAt(position) case final handle?) {
        // resize or rotate in onDrawUpdate
        _selectionChange = _SelectionChange(
          select,
          handle: handle,
          box: box,
          start: position,
        );
      } else if (selectedHere &&
          (result.path.contains(position) ||
              (box?.rect.contains(position) ?? false))) {
        // drag selection in onDrawUpdate
      } else {
        select.onDragStart(position, dragPageIndex!);
        select.selectResult.owner = this;
        history.canRedo = true; // selection doesn't affect history
      }
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragStart(position, page, dragPageIndex!);
    }

    previousPosition = position;
    moveOffset = .zero;

    if (currentTool is! SelectLasso) {
      SelectLasso.currentSelect.unselect();
    }
    if (currentTool is! SelectBox) {
      SelectBox.currentSelect.unselect();
    }

    // setState to let canvas know about currentStroke
    setState(() {});
  }

  void onDrawUpdate(ScaleUpdateDetails details) {
    if (dragPageIndex == null) {
      return;
    }
    final page = coreInfo.pages[dragPageIndex!];
    if (currentTool is Pen && !_drawingInZoomWindow) {
      _rulerSnap = ruler.snapFor(details.focalPoint, current: _rulerSnap);
    }
    Offset position = page.renderBox!.globalToLocal(
      _alongRuler(details.focalPoint, page),
    );
    Offset offset = position - previousPosition;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragUpdate(position, currentPressure);
      page.redrawStrokes();
    } else if (currentTool is Eraser) {
      for (final stroke in (currentTool as Eraser).checkForOverlappingStrokes(
        position,
        page.strokes,
      )) {
        page.strokes.remove(stroke);
      }
      _setEraserOutline(page, position);
      removeExcessPages();
    } else if (_selectionChange case final change? when change.handle != null) {
      change.update(
        page,
        change.box!.drag(change.handle!, change.start!, position),
      );
    } else if (currentTool is SelectLasso || currentTool is SelectBox) {
      final Select select = currentTool as Select;
      if (select.doneSelecting) {
        // Between -1 and 1
        int pageOffset = 0;
        if (position.dy > page.size.height + changePageThreshold) {
          // Selection is dragged past the bottom of the original page
          if (coreInfo.pages.length > select.selectResult.pageIndex + 1) {
            offset = Offset(
              offset.dx,
              offset.dy - (page.size.height + changePageThreshold),
            );
            pageOffset = 1;
          }
        } else if (position.dy < -changePageThreshold) {
          // Selection is dragged past the top of the original page
          if (select.selectResult.pageIndex > 0) {
            offset = Offset(
              offset.dx,
              offset.dy + (page.size.height + changePageThreshold),
            );
            pageOffset = -1;
          }
        }
        for (final stroke in select.selectResult.strokes) {
          stroke.shift(offset);
        }
        for (final image in select.selectResult.images) {
          image.dstRect = image.dstRect.shift(offset);
        }
        select.selectResult.path = select.selectResult.path.shift(offset);
        if (select.selectResult.box case final box?) {
          select.selectResult.box = box.copyWith(rect: box.rect.shift(offset));
        }

        if (pageOffset != 0) {
          offset = position - previousPosition;
          selectionOffsetPage(pageOffset);
          dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);

          if (dragPageIndex == null) {
            return;
          }
          final pageNew = coreInfo.pages[dragPageIndex!];
          // Recalculate position according new drag page
          position = pageNew.renderBox!.globalToLocal(details.focalPoint);
          // Recalculate the offset as if the selection were always moving to one page. Important for undo/redo
          offset = Offset(
            offset.dx,
            offset.dy - pageOffset * (page.size.height + changePageThreshold),
          );
          pageNew.redrawStrokes();
        }
      } else {
        select.onDragUpdate(position);
      }
      page.redrawStrokes();
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragUpdate(position);
      page.redrawStrokes();
    }
    previousPosition = position;
    moveOffset += offset;
  }

  bool moveStrokeToPage(Stroke stroke, int pageIndexOrig, int pageIndexDest) {
    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.strokes.remove(stroke);
    stroke.pageIndex = pageIndexDest;
    stroke.page = pageDest;
    pageDest.insertStroke(stroke);
    return true;
  }

  bool moveImageToPage(
    EditorImage image,
    int pageIndexOrig,
    int pageIndexDest,
  ) {
    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.images.remove(image);
    image.pageIndex = pageIndexDest;
    pageDest.images.add(image);
    return true;
  }

  void selectionOffsetPage(int pageOffset) {
    Select select = currentTool as Select;
    final int oldPage = select.selectResult.pageIndex;
    final int newPage = select.selectResult.pageIndex + pageOffset;
    if (oldPage < 0 || oldPage > coreInfo.pages.length - 1) {
      return;
    }
    if (newPage < 0 || newPage > coreInfo.pages.length - 1) {
      return;
    }
    final strokes = select.selectResult.strokes;
    final images = select.selectResult.images;

    setState(() {
      for (Stroke stroke in strokes) {
        moveStrokeToPage(stroke, oldPage, newPage);
      }
      for (EditorImage image in images) {
        moveImageToPage(image, oldPage, newPage);
      }
      select.selectResult.pageIndex += pageOffset;
    });
  }

  /// The canvas on screen, in global coordinates.
  Rect? get _canvasArea {
    final box = _canvasGestureDetectorKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Shows the [zoomWindow] at the top left of the page in the middle of
  /// the screen, or hides it.
  void _toggleZoomWindow() {
    if (zoomWindow.visible) return zoomWindow.hide();
    final area = _canvasArea;
    if (area == null) return;
    final pageIndex =
        onWhichPageIsFocalPoint(area.center) ??
        coreInfo.pages.indexWhere((page) => page.renderBox != null);
    if (pageIndex == -1) return;
    final page = coreInfo.pages[pageIndex];
    final box = page.renderBox!;
    zoomWindow.show(
      pageIndex: pageIndex,
      pageSize: page.size,
      onScreen: Rect.fromPoints(
        box.globalToLocal(area.topLeft),
        box.globalToLocal(area.bottomRight),
      ).intersect(Offset.zero & page.size),
      lineHeight: coreInfo.lineHeight.toDouble(),
    );
  }

  void _onZoomWindowChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepZoomBoxOnScreen());
  }

  /// Scrolls the canvas so the zoom window's box is on screen.
  void _keepZoomBoxOnScreen() {
    if (!mounted || !zoomWindow.visible) return;
    final canvas = _canvasGestureDetectorKey.currentContext?.findRenderObject();
    final box = coreInfo.pages.elementAtOrNull(zoomWindow.pageIndex)?.renderBox;
    if (canvas is! RenderBox || !canvas.hasSize || box == null) return;
    // In the canvas's coordinates, which the transformation moves in.
    final area = Offset.zero & canvas.size;
    Offset onCanvas(Offset onPage) =>
        canvas.globalToLocal(box.localToGlobal(onPage));
    final rect = Rect.fromPoints(
      onCanvas(zoomWindow.rect.topLeft),
      onCanvas(zoomWindow.rect.bottomRight),
    );
    double into(double start, double end, double areaStart, double areaEnd) =>
        start < areaStart
        ? areaStart - start
        : end > areaEnd
        ? areaEnd - end
        : 0;
    final dx = into(rect.left, rect.right, area.left, area.right);
    final dy = into(rect.top, rect.bottom, area.top, area.bottom);
    if (dx == 0 && dy == 0) return;
    _transformationController.value =
        Matrix4.translationValues(dx, dy, 0) * _transformationController.value;
  }

  /// [main] with the [sideBySide] pane next to it (right, or below when the
  /// space is taller than wide), when something is open in it.
  Widget _withSideBySide(Widget main) {
    if (sideBySide.path == null) return main;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= constraints.maxHeight;
        final length = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final colorScheme = ColorScheme.of(context);
        return Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          children: [
            Expanded(child: main),
            // The divider, dragged to share the space differently.
            MouseRegion(
              cursor: horizontal
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: .opaque,
                onHorizontalDragUpdate: horizontal
                    ? (details) =>
                          sideBySide.fraction -= details.delta.dx / length
                    : null,
                onVerticalDragUpdate: horizontal
                    ? null
                    : (details) =>
                          sideBySide.fraction -= details.delta.dy / length,
                child: SizedBox(
                  width: horizontal ? _dividerThickness : null,
                  height: horizontal ? null : _dividerThickness,
                  child: Center(
                    child: ColoredBox(
                      color: colorScheme.outlineVariant,
                      child: SizedBox(
                        width: horizontal ? 1 : null,
                        height: horizontal ? null : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: horizontal ? length * sideBySide.fraction : null,
              height: horizontal ? null : length * sideBySide.fraction,
              child: SideBySidePane(
                sideBySide: sideBySide,
                getTool: () => currentTool,
                setTool: (tool) => setState(() => currentTool = tool),
                changed: _setState,
              ),
            ),
          ],
        );
      },
    );
  }

  /// How wide the divider between side-by-side panes is to grab.
  static const _dividerThickness = kMinInteractiveDimension / 4;

  /// Lets the user pick a note to open side by side.
  Future<void> _openNoteSideBySide() async {
    final path = await showSearch(
      context: context,
      delegate: NotesSearchDelegate(FileManager.getAllFiles()),
    );
    if (path == null || !mounted) return;
    if (path == coreInfo.filePath) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.editor.sideBySide.alreadyOpen)));
      return;
    }
    sideBySide.openNote(path);
  }

  /// Lets the user pick a PDF file to open side by side.
  Future<void> _openPdfSideBySide() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file?.path case final path?) sideBySide.openPdf(path);
  }

  /// [canvas] with the zoom window's panel below it, when it's shown.
  Widget _withZoomWindow(Widget canvas) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Expanded(child: canvas),
        if (zoomWindow.visible)
          SizedBox(
            height: constraints.maxHeight * zoomWindow.panelFraction,
            child: ZoomWindowPanel(
              zoomWindow: zoomWindow,
              coreInfo: coreInfo,
              currentStroke:
                  identical(
                    Pen.currentStroke?.page,
                    coreInfo.pages.elementAtOrNull(zoomWindow.pageIndex),
                  )
                  ? Pen.currentStroke
                  : null,
              onPointer: _onZoomWindowPointer,
              onResize: (dy) =>
                  zoomWindow.panelFraction -= dy / constraints.maxHeight,
            ),
          ),
      ],
    ),
  );

  /// Draws with a pointer in the zoom window's panel, at [onPage] on the
  /// box's page, like on the canvas; a stroke ending [inMargin] moves the box
  /// on (if it auto-advances).
  void _onZoomWindowPointer(PointerEvent event, Offset onPage, bool inMargin) {
    final pageIndex = zoomWindow.pageIndex;
    final box = coreInfo.pages.elementAtOrNull(pageIndex)?.renderBox;
    if (box == null) return;
    final global = box.localToGlobal(onPage);
    final isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    // The stylus button switches to the eraser, as on the canvas.
    if (isStylus) {
      final pressed =
          event.buttons == kSecondaryButton ||
          event.kind == PointerDeviceKind.invertedStylus;
      if (event is PointerHoverEvent) {
        event.synthesized ? onHoveringEnd() : onHovering();
      }
      if (pressed != _zoomWindowStylusButton) {
        _zoomWindowStylusButton = pressed;
        onStylusButtonChanged(pressed);
      }
    }

    switch (event) {
      case PointerDownEvent():
        if (_zoomWindowPointer != null || coreInfo.readOnly) return;
        if (currentTool is! Pen && currentTool is! Eraser) return;
        if (!isStylus && !stows.editorFingerDrawing.value) return;
        _zoomWindowPointer = event.pointer;
        _drawingInZoomWindow = true;
        updatePointerData(event.kind, CanvasGestureDetector.pressureOf(event));
        dragPageIndex = pageIndex;
        onDrawStart(
          ScaleStartDetails(focalPoint: global, localFocalPoint: global),
        );
      case PointerMoveEvent() when event.pointer == _zoomWindowPointer:
        updatePointerData(event.kind, CanvasGestureDetector.pressureOf(event));
        onDrawUpdate(
          ScaleUpdateDetails(focalPoint: global, localFocalPoint: global),
        );
      case PointerUpEvent() || PointerCancelEvent()
          when event.pointer == _zoomWindowPointer:
        final wasPen = currentTool is Pen;
        onDrawEnd(ScaleEndDetails());
        updatePointerData(event.kind, null);
        _zoomWindowPointer = null;
        _drawingInZoomWindow = false;
        if (_zoomWindowStylusButton) {
          _zoomWindowStylusButton = false;
          onStylusButtonChanged(false);
        }
        if (event is PointerUpEvent &&
            wasPen &&
            inMargin &&
            zoomWindow.autoAdvance) {
          zoomWindow.forward(coreInfo.lineHeight.toDouble());
        }
      default:
    }
  }

  /// The editor whose selection the toolbar's selection actions act on:
  /// this one, or the one side by side if the selection was made there.
  EditorState get _selectionOwner {
    final owner = switch (currentTool) {
      final Select select => select.selectResult.owner,
      _ => null,
    };
    return owner is EditorState && owner.mounted ? owner : this;
  }

  void _duplicateSelection() {
    final Select select = currentTool as Select;
    if (!select.doneSelecting) return;

    setState(() {
      final page = coreInfo.pages[select.selectResult.pageIndex];
      final strokes = select.selectResult.strokes;
      final images = select.selectResult.images;

      const duplicationFeedbackOffset = Offset(25, -25);

      final List<Stroke> duplicatedStrokes = strokes.map((stroke) {
        return stroke.copy()..shift(duplicationFeedbackOffset);
      }).toList();

      final duplicatedImages = images.map((image) {
        return image.copy()
          ..id = coreInfo.nextImageId++
          ..dstRect = image.dstRect.shift(duplicationFeedbackOffset);
      }).toList();

      page.strokes.addAll(duplicatedStrokes);
      page.images.addAll(duplicatedImages);

      select.selectResult = select.selectResult.copyWith(
        strokes: duplicatedStrokes,
        images: duplicatedImages,
        path: select.selectResult.path.shift(duplicationFeedbackOffset),
      );
      _fitSelectionBox(select);

      history.recordChange(
        EditorHistoryItem(
          type: .draw,
          pageIndex: select.selectResult.pageIndex,
          strokes: duplicatedStrokes,
          images: duplicatedImages,
        ),
      );
      autosaveAfterDelay();
    });
  }

  void _deleteSelection() {
    final Select select = currentTool as Select;
    if (!select.doneSelecting) {
      return;
    }

    setState(() {
      final page = coreInfo.pages[select.selectResult.pageIndex];
      final strokes = select.selectResult.strokes;
      final images = select.selectResult.images;

      for (final stroke in strokes) {
        page.strokes.remove(stroke);
      }
      for (final image in images) {
        page.images.remove(image);
      }

      select.unselect();

      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: strokes.first.pageIndex,
          strokes: strokes,
          images: images,
        ),
      );
      autosaveAfterDelay();
    });
  }

  /// Changes the colour of the selected strokes to [color].
  void _recolorSelection(Color color) {
    final Select select = currentTool as Select;
    if (!select.doneSelecting) return;
    setState(() {
      final strokes = select.selectResult.strokes;

      final colorChange = <Stroke, Change<Color>>{};
      for (final stroke in strokes) {
        // Each stroke keeps its own opacity (e.g. highlighter's).
        final newColor = color.withValues(alpha: stroke.color.a);
        colorChange[stroke] = Change(previous: stroke.color, current: newColor);
        stroke.color = newColor;
      }

      history.recordChange(
        EditorHistoryItem(
          type: .changeColor,
          pageIndex: strokes.first.pageIndex,
          strokes: strokes,
          colorChange: colorChange,
          images: [],
        ),
      );
      autosaveAfterDelay();
    });
  }

  /// The tape on [page] at [point], if any (the top one).
  static Stroke? _tapeAt(EditorPage page, Offset point) => page.strokes
      .where((stroke) => stroke.isTape && stroke.lowQualityPath.contains(point))
      .lastOrNull;

  /// Tapping tape (with anything) shows what's under it, or hides it again.
  void _onTap(PointerDeviceKind kind, Offset position) {
    // After the tap's own gesture, which may have drawn a dot (see
    // [onDrawEnd]).
    scheduleMicrotask(() {
      if (!mounted) return;
      final pageIndex = onWhichPageIsFocalPoint(position);
      if (pageIndex == null) return;
      final page = coreInfo.pages[pageIndex];
      final tape = _tapeAt(page, page.renderBox!.globalToLocal(position));
      if (tape == null) return;
      tape.tapeRevealed = !tape.tapeRevealed;
      page.redrawStrokes();
    });
  }

  /// When recent drawing gestures started (as pointer event time stamps)
  /// and how much there was to undo then, so a double tap can take back
  /// what its taps did (see [_onDoubleTap]).
  final _recentDrawStarts = <({Duration time, int historyLength})>[];

  /// How many [_recentDrawStarts] are kept: a double tap is two gestures.
  static const _recentDrawStartsKept = 2;

  /// Switches to the eraser, or back, if [kind] double-tapping does so (see
  /// [Stows.doubleTapToErase]), taking back what the taps (starting [since])
  /// drew or erased. Not on tape at [position], whose taps open and close it
  /// (see [_onTap]).
  void _onDoubleTap(PointerDeviceKind kind, Offset position, Duration since) {
    if (!DoubleTapToErase.fromJson(stows.doubleTapToErase.value)
        .accepts(kind)) {
      return;
    }
    if (onWhichPageIsFocalPoint(position) case final pageIndex?) {
      final page = coreInfo.pages[pageIndex];
      if (_tapeAt(page, page.renderBox!.globalToLocal(position)) != null) {
        return;
      }
    }
    // The gesture of the second tap may end after this.
    scheduleMicrotask(() {
      if (!mounted) return;
      final firstTap = _recentDrawStarts
          .where((start) => start.time >= since)
          .firstOrNull;
      if (firstTap != null) {
        while (history.length > firstTap.historyLength) {
          undo(history.dropLast());
        }
      }
      _recentDrawStarts.clear();
      setState(() {
        currentTool = currentTool is Eraser
            ? _lastNonEraserTool
            : Eraser.currentEraser;
      });
    });
  }

  /// A resize, rotation or thickness change of the selection in progress.
  _SelectionChange? _selectionChange;

  /// How many screen pixels a unit of [page] takes up (the zoom times how
  /// much the page is scaled to fit), or the zoom if it isn't laid out.
  double _screenScaleOf(EditorPage page) {
    final box = page.renderBox;
    if (box == null) return _transformationController.value.approxScale;
    return (box.localToGlobal(const Offset(1, 0)) - box.localToGlobal(.zero))
        .distance;
  }

  /// Fits [select]'s box (see [SelectionBox]) to what's selected now.
  void _fitSelectionBox(Select select) {
    final result = select.selectResult;
    final rect = select.doneSelecting
        ? SelectionBox.boundsOf(result.strokes, result.images)
        : null;
    if (rect == null) {
      result.box = null;
      return;
    }
    final pixel = 1 / _screenScaleOf(coreInfo.pages[result.pageIndex]);
    result.box = SelectionBox(
      rect: rect.inflate(SelectionBox.margin * pixel),
      pixel: pixel,
      // Images can't be rotated.
      rotatable: result.images.isEmpty,
    );
  }

  /// Records [change] for undo, or puts the selection back as it was if it
  /// changed nothing, and fits the box to the result.
  void _finishSelectionChange(_SelectionChange change) {
    final result = change.select.selectResult;
    final page = coreInfo.pages[result.pageIndex];
    if (change.transform.isIdentity) {
      change.revert(page);
    } else {
      history.recordChange(
        EditorHistoryItem(
          type: .transform,
          pageIndex: result.pageIndex,
          strokes: change.strokes,
          replacementStrokes: List.of(result.strokes),
          images: change.imageRects.keys.toList(),
          imageRectChange: {
            for (final MapEntry(key: image, value: rect)
                in change.imageRects.entries)
              image: Change(previous: rect, current: image.dstRect),
          },
        ),
      );
    }
    _fitSelectionBox(change.select);
  }

  /// Scales the widths of the selected strokes by [factor] (relative to when
  /// the change started), see [_finishSelectionThickness].
  void _changeSelectionThickness(double factor) {
    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return;
    final change = _selectionChange ??= _SelectionChange(select);
    setState(() {
      change.update(
        coreInfo.pages[select.selectResult.pageIndex],
        SelectionTransform(widthScale: factor),
      );
    });
  }

  void _finishSelectionThickness() {
    final change = _selectionChange;
    if (change == null || change.handle != null) return;
    _selectionChange = null;
    setState(() => _finishSelectionChange(change));
    autosaveAfterDelay();
  }

  /// Puts each of [to] in place of the stroke of [from] at the same index
  /// (in its place on its page, keeping the order strokes are drawn in).
  void _swapStrokes(List<Stroke> from, List<Stroke> to) {
    for (var i = 0; i < from.length; i++) {
      final page = coreInfo.pages[from[i].pageIndex];
      final index = page.strokes.indexOf(from[i]);
      if (index == -1) {
        page.insertStroke(to[i]);
      } else {
        page.strokes[index] = to[i];
      }
      page.redrawStrokes();
    }
  }

  /// Erases the strokes that [stroke], just drawn with [pen] on [page],
  /// scribbles over, if [Stows.scribbleToErase] is on (see [ScribbleErase]).
  /// Returns whether it did, and so whether [stroke] is dropped.
  bool _scribbleErase(Pen pen, Stroke stroke, EditorPage page) {
    if (!stows.scribbleToErase.value) return false;
    // Only writing pens: scribbling with a highlighter or tape covers
    // things up, and shapes (e.g. from hold to shape) aren't scribbles.
    if (pen is Highlighter || pen is Tape || pen is ShapePen) return false;
    if (stroke is CircleStroke || stroke is RectangleStroke) return false;

    final erased = ScribbleErase.erasedBy(stroke, page.strokes);
    if (erased.isEmpty) return false;
    for (final erasedStroke in erased) {
      page.strokes.remove(erasedStroke);
    }
    page.redrawStrokes();
    removeExcessPages();
    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: stroke.pageIndex,
        strokes: erased,
        images: [],
      ),
    );
    return true;
  }

  void onDrawEnd(ScaleEndDetails details) {
    _rulerSnap = null;
    if (dragPageIndex == null) {
      return;
    }
    final page = coreInfo.pages[dragPageIndex!];
    bool shouldSave = true;
    setState(() {
      if (currentTool is Pen) {
        final pen = currentTool as Pen;
        final newStroke = pen.onDragEnd();
        if (newStroke == null) return;
        if (newStroke.isEmpty) return;

        if (_scribbleErase(pen, newStroke, page)) return;
        // A tap on tape opens or closes it (see [_onTap]) instead.
        if (newStroke.isDot &&
            _tapeAt(page, newStroke.pointVectors.first) != null) {
          return;
        }

        if (stows.autoStraightenLines.value &&
            currentTool is! ShapePen &&
            newStroke.isStraightLine()) {
          newStroke.convertToLine();
        }

        createPage(newStroke.pageIndex);
        page.insertStroke(newStroke);
        history.recordChange(
          EditorHistoryItem(
            type: .draw,
            pageIndex: dragPageIndex!,
            strokes: [newStroke],
            images: [],
          ),
        );
      } else if (currentTool is Eraser) {
        _setEraserOutline(page, null);
        final erased = (currentTool as Eraser).onDragEnd();
        if (stylusButtonWasPressed || stows.disableEraserAfterUse.value) {
          // restore previous tool
          stylusButtonWasPressed = false;
          currentTool = _lastNonEraserTool;
        }
        if (erased.erasedStrokes.isEmpty && erased.replacementStrokes.isEmpty)
          return;
        history.recordChange(
          EditorHistoryItem(
            type: erased.replacementStrokes.isNotEmpty ? .eraseArea : .erase,
            pageIndex: dragPageIndex!,
            strokes: erased.erasedStrokes,
            replacementStrokes: erased.replacementStrokes,
            images: [],
          ),
        );
      } else if (_selectionChange case final change?
          when change.handle != null) {
        _selectionChange = null;
        _finishSelectionChange(change);
      } else if (currentTool is SelectLasso || currentTool is SelectBox) {
        if (moveOffset == .zero) return;
        final Select select = currentTool as Select;
        if (select.doneSelecting) {
          history.recordChange(
            EditorHistoryItem(
              type: .move,
              pageIndexStart: select.selectResult.pageIndexStart,
              pageIndex: select.selectResult.pageIndex,
              strokes: select.selectResult.strokes,
              images: select.selectResult.images,
              offset: .fromLTRB(
                moveOffset.dx,
                moveOffset.dy,
                moveOffset.dx,
                moveOffset.dy,
              ),
            ),
          );
          select.selectResult.pageIndexStart = select.selectResult.pageIndex;
        } else {
          shouldSave = false;
          select.onDragEnd(page.strokes, page.images);

          if (select.selectResult.isEmpty) {
            SelectLasso.currentSelect.unselect();
            SelectBox.currentSelect.unselect();
          } else {
            _fitSelectionBox(select);
          }
        }
      } else if (currentTool is LaserPointer) {
        shouldSave = false;
        final newStroke = (currentTool as LaserPointer).onDragEnd(
          page.redrawStrokes,
          (Stroke stroke) {
            page.laserStrokes.remove(stroke);
          },
        );
        if (newStroke != null) page.laserStrokes.add(newStroke);
      }
    });

    if (shouldSave) autosaveAfterDelay();
    widget.embedding?.changed();
  }

  void onInteractionEnd(ScaleEndDetails details) {
    // reset after 1ms to keep track of the same gesture only
    _lastSeenPointerCountTimer?.cancel();
    _lastSeenPointerCountTimer = Timer(const Duration(milliseconds: 10), () {
      lastSeenPointerCount = 0;
    });
  }

  void updatePointerData(PointerDeviceKind kind, double? pressure) {
    currentPointerKind = kind;
    currentPressure = pressure;
  }

  void onHovering() {
    isHovering = true;
  }

  void onHoveringEnd() {
    isHovering = false;
  }

  void onStylusButtonChanged(bool buttonIsPressed) {
    stylusButtonWasPressed |= buttonIsPressed;

    if (!isHovering) return;
    if (buttonIsPressed) {
      // button pressed while hovering, switch to Eraser
      if (currentTool is! Eraser) {
        currentTool = Eraser();
      }
    } else {
      // button was released while hovering, switch back to non-Eraser
      if (currentTool is Eraser) {
        currentTool = _lastNonEraserTool;
      }
    }

    if (mounted) setState(() {});
  }

  void onMoveImage(EditorImage image, Rect offset) {
    history.recordChange(
      EditorHistoryItem(
        type: .move,
        pageIndex: image.pageIndex,
        pageIndexStart: image.pageIndex,
        strokes: [],
        images: [image],
        offset: offset,
      ),
    );
    // setState to update undo button
    setState(() {});
    autosaveAfterDelay();
  }

  void onReplaceImage(EditorImage original, EditorImage replacement) {
    replacement.id = coreInfo.nextImageId++;
    history.recordChange(
      EditorHistoryItem(
        type: .replaceImage,
        pageIndex: original.pageIndex,
        strokes: [],
        images: [original],
        replacementImages: [replacement],
      ),
    );
    setState(() => _swapImage(original, replacement));
    autosaveAfterDelay();
  }

  /// Puts [to] in place of [from] on its page, keeping its stacking order.
  void _swapImage(EditorImage from, EditorImage to) {
    final images = coreInfo.pages[from.pageIndex].images;
    final index = images.indexOf(from);
    if (index == -1) {
      images.add(to);
    } else {
      images[index] = to;
    }
    to.newImage = true;
  }

  void onDeleteImage(EditorImage image) {
    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
      ),
    );
    setState(() {
      coreInfo.pages[image.pageIndex].images.remove(image);
    });
    autosaveAfterDelay();
  }

  void listenToQuillChanges(QuillStruct quill, int pageIndex) {
    quill.changeSubscription?.cancel();
    quill.changeSubscription = quill.controller.changes.listen((event) {
      final undoRedoButtonsNeedUpdating = !history.canUndo || history.canRedo;
      _addQuillChangeToHistory(
        quill: quill,
        pageIndex: pageIndex,
        event: event,
      );
      createPage(pageIndex); // create empty last page
      if (undoRedoButtonsNeedUpdating) {
        setState(() {});
      }
      autosaveAfterDelay();
    });
    quill.focusNode.addListener(_onQuillFocusChange);
  }

  void _onQuillFocusChange() {
    for (final page in coreInfo.pages) {
      if (!page.quill.focusNode.hasFocus) continue;
      quillFocus.value = page.quill;
    }
  }

  void _addQuillChangeToHistory({
    required QuillStruct quill,
    required int pageIndex,
    required flutter_quill.DocChange event,
  }) {
    final eventWasUndo = quill.controller.hasRedo;
    if (eventWasUndo) return;

    // the change subscription sometimes fires multiple times for the same change
    // so compare the "before" of each change to merge them
    if (history.canUndo && !history.canRedo) {
      final lastChange = history.peekUndo();
      if (lastChange.type == .quillChange &&
          lastChange.pageIndex == pageIndex &&
          lastChange.quillChange!.before == event.before) {
        history.undo(); // remove the last change, to be replaced
      }
    }

    history.recordChange(
      EditorHistoryItem(
        type: .quillChange,
        pageIndex: pageIndex,
        strokes: const [],
        images: const [],
        quillChange: event,
      ),
    );
  }

  void _refreshCurrentNote() async {
    if (coreInfo.readOnlyReason != .watchingServer) return;
    if (!stows.loggedIn) return;

    final relativeFilePath = coreInfo.filePath;
    assert(relativeFilePath.isNotEmpty, 'Cannot refresh unnamed file');
    final syncFile = await SaberSyncFile.relative(
      relativeFilePath + Editor.extension,
    );

    final bestFile = await SaberSyncInterface.getBestFile(
      syncFile,
      onLocalFileNotFound: .local,
      onEqualFiles: .local,
      preferCache: false,
    );
    if (bestFile != .remote) return;

    late final StreamSubscription<SaberSyncFile> subscription;
    void listener(SaberSyncFile transferred) {
      if (transferred != syncFile) return;
      subscription.cancel();
      log.info('Reloading $relativeFilePath while watching the server');
      unawaited(_reloadInPlace());
    }

    subscription = syncer.downloader.transferStream.listen(listener);

    await syncer.downloader.enqueue(syncFile: syncFile);
    syncer.downloader.bringToFront(syncFile);
  }

  /// Reloads the open note once a newer version of it (and its assets) has
  /// been downloaded, unless it has unsaved changes, which win when saved.
  void _onFileDownloaded(SaberSyncFile file) {
    // Watching the server reloads the note itself, see [_refreshCurrentNote].
    if (coreInfo.readOnlyReason == .watchingServer) return;

    final notePath = coreInfo.filePath + Editor.extension;
    bool isOfThisNote(SaberSyncFile f) =>
        f.relativeLocalPath == notePath ||
        f.relativeLocalPath.startsWith('$notePath.');
    if (!isOfThisNote(file)) return;
    // Wait until the rest of the note has been downloaded too.
    if (syncer.downloader.pending.any(isOfThisNote)) return;
    if (!_canReload) return;

    log.info('Reloading $notePath after it changed on another device');
    unawaited(_reloadInPlace());
  }

  bool get _canReload =>
      savingState.value == .saved && Pen.currentStroke == null;

  /// Replaces the open note with its version on disk without flashing blank:
  /// pages keep their canvases, unchanged PDFs stay open and rendered, and
  /// the images on screen are loaded before the swap.
  ///
  /// If the note on disk doesn't load (e.g. it was cut short), the open note
  /// stays as it is until the next download of it.
  Future<void> _reloadInPlace() async {
    final old = coreInfo;
    final reloaded = await EditorCoreInfo.loadFromFilePath(old.filePath);
    if (reloaded.readOnlyReason == .corrupted ||
        (reloaded.isEmpty && old.isNotEmpty)) {
      log.warning('Reload of ${old.filePath} failed, keeping the open note');
      reloaded.dispose();
      return;
    }
    final oldPdfs = old.assetCache.pdfDocumentCache;
    final reloadedPdfs = reloaded.assetCache.pdfDocumentCache;
    final pdfsOpen = oldPdfs.fileDocumentCount;
    final pdfsKept = await reloadedPdfs.adoptUnchanged(oldPdfs);
    final imagesLoaded = await _loadInShownImages(old: old, reloaded: reloaded);
    log.info(
      'Reload: kept $pdfsKept of $pdfsOpen open PDFs, '
      'loaded $imagesLoaded shown images before swapping',
    );

    // Something changed while loading: keep the note as it is.
    if (!mounted || coreInfo != old || !_canReload) {
      await oldPdfs.adoptUnchanged(reloadedPdfs);
      reloaded.dispose();
      return;
    }

    for (var i = 0; i < old.pages.length && i < reloaded.pages.length; i++) {
      reloaded.pages[i].takeOverCanvasOf(old.pages[i]);
    }
    // Keep watching the server, see [_refreshCurrentNote].
    if (old.readOnlyReason == .watchingServer) {
      reloaded.readOnlyReason ??= .watchingServer;
    }
    await _applyCoreInfo(reloaded);
    history = EditorHistory();
    if (mounted) setState(() {});
    // Close the PDFs that changed, once the old pages are off screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => old.assetCache.dispose(),
    );
  }

  /// Loads the images of [reloaded] on the pages that are on screen,
  /// so they appear straight away when [reloaded] replaces [old].
  /// Returns how many it loaded.
  Future<int> _loadInShownImages({
    required EditorCoreInfo old,
    required EditorCoreInfo reloaded,
  }) async {
    final toLoad = <EditorImage>[
      for (var i = 0; i < old.pages.length && i < reloaded.pages.length; i++)
        if (old.pages[i].isRendered) ...[
          ?reloaded.pages[i].backgroundImage,
          ...reloaded.pages[i].images,
        ],
    ];

    await Future.wait([
      for (final image in toLoad)
        image
            .loadIn()
            .then((_) => mounted ? image.precache(context) : null)
            .catchError((Object e) {
              // It loads again when shown, so don't hold up the reload.
              log.warning('Could not preload image ${image.id}: $e');
            }),
    ]);
    return toLoad.length;
  }

  void autosaveAfterDelay() {
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    late final void Function() callback;

    void startTimer() {
      _delayedSaveTimer?.cancel();
      if (stows.autosaveDelay.value < 0) return;
      _delayedSaveTimer = Timer(
        Duration(milliseconds: stows.autosaveDelay.value),
        callback,
      );
    }

    callback = () {
      if (Pen.currentStroke != null) {
        // don't save yet if the pen is currently drawing
        startTimer();
        return;
      }
      saveToFile();
    };

    savingState.value = .waitingToSave;
    startTimer();
  }

  void cancelAutosaveAndMarkSaved() {
    _delayedSaveTimer?.cancel();
    savingState.value = .saved;
    history.markLastChangeAsSaved();
  }

  Future<void> saveToFile() async {
    if (coreInfo.readOnly) return;

    switch (savingState.value) {
      case .saved:
        // avoid saving if nothing has changed
        return;
      case .saving:
        // avoid saving if already saving
        log.warning('saveToFile() called while already saving');
        return;
      case .waitingToSave:
        // continue
        _delayedSaveTimer?.cancel();
        savingState.value = .saving;
    }
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    await _renameFileNow();

    final filePath = coreInfo.filePath + Editor.extension;
    final Uint8List bson;
    final OrderedAssetCache assets;
    coreInfo.assetCache.allowRemovingAssets = false;
    try {
      (bson, assets) = coreInfo.saveToBinary(
        currentPageIndex: currentPageIndex,
      );
    } finally {
      coreInfo.assetCache.allowRemovingAssets = true;
    }
    try {
      await Future.wait([
        FileManager.writeFile(filePath, bson, awaitWrite: true),
        for (int i = 0; i < assets.length; ++i)
          assets
              .getBytes(i)
              .then(
                (bytes) => FileManager.writeFile(
                  '$filePath.$i',
                  bytes,
                  awaitWrite: true,
                ),
              ),
        FileManager.removeUnusedAssets(filePath, numAssets: assets.length),
      ]);
      savingState.value = .saved;
      history.markLastChangeAsSaved();
      if (stows.syncOnSave.value) SyncScheduler.pull();
    } catch (e, st) {
      log.severe('Failed to save file: $e', e, st);
      savingState.value = .waitingToSave;
      if (kDebugMode) rethrow;
      return;
    }

    if (!mounted) return;
    final page = coreInfo.pages.first;
    final previewHeight = page.previewHeight(lineHeight: coreInfo.lineHeight);
    final thumbnailSize = Size(720, 720 * previewHeight / page.size.width);
    final thumbnail = await EditorExporter.screenshotPage(
      coreInfo: coreInfo,
      pageIndex: 0,
      rasterizeAllStrokes: true,
      targetSize: thumbnailSize,
      cropHeight: previewHeight,
      pixelRatio: 1,
    );
    final thumbnailPng = await thumbnail.toByteData(format: .png);
    thumbnail.dispose();
    await FileManager.writeFile(
      // Note that this ends with .sbn2.p
      '$filePath.p',
      thumbnailPng!.buffer.asUint8List(),
      awaitWrite: true,
    );
  }

  late final _filenameFormKey = GlobalKey<FormState>();
  late final filenameTextEditingController = TextEditingController();
  Timer? _renameTimer;
  void renameFile([String? _]) {
    _renameTimer?.cancel();
    _renameTimer = Timer(const Duration(seconds: 5), _renameFileNow);
  }

  Future<void> _renameFileNow() async {
    final newName = filenameTextEditingController.text.trim();
    if (newName == coreInfo.fileName) return;

    if (_filenameFormKey.currentState?.validate() ??
        _validateFilenameTextField(newName) == null) {
      coreInfo.filePath = await FileManager.moveFile(
        coreInfo.filePath + Editor.extension,
        newName.trim() + Editor.extension,
      );
      coreInfo.filePath = coreInfo.filePath.substring(
        0,
        coreInfo.filePath.lastIndexOf(Editor.extension),
      );
      needsNaming = false;
    }

    final actualName = coreInfo.fileName;
    if (actualName != newName) {
      // update text field if renamed differently
      filenameTextEditingController.value = filenameTextEditingController.value
          .copyWith(
            text: actualName,
            selection: TextSelection.fromPosition(
              TextPosition(offset: actualName.length),
            ),
            composing: TextRange.empty,
          );
    }
  }

  String? _validateFilenameTextField(String? newName) {
    if (newName == null) return null;
    return FileManager.validateFilename(newName);
  }

  void updateColorBar(Color color) {
    if (stows.recentColorsDontSavePresets.value) {
      if (ColorBar.colorPresets.any(
        (colorPreset) => colorPreset.color == color,
      )) {
        return;
      }
    }

    final newColorString = color.toARGB32().toString();

    // migrate from old pref format
    if (stows.recentColorsChronological.value.length !=
        stows.recentColorsPositioned.value.length) {
      log.info(
        'MIGRATING recentColors: ${stows.recentColorsChronological.value.length} vs ${stows.recentColorsPositioned.value.length}',
      );
      stows.recentColorsChronological.value = List.of(
        stows.recentColorsPositioned.value,
      );
    }

    if (stows.pinnedColors.value.contains(newColorString)) {
      // do nothing, color is already pinned
    } else if (stows.recentColorsPositioned.value.contains(newColorString)) {
      // if it's already a recent color, move it to the top
      stows.recentColorsChronological.value.remove(newColorString);
      stows.recentColorsChronological.value.add(newColorString);
      stows.recentColorsChronological.notifyListeners();
    } else {
      if (stows.recentColorsPositioned.value.length >=
          stows.recentColorsLength.value) {
        // if full, replace the oldest color with the new one
        final removedColorString = stows.recentColorsChronological.value
            .removeAt(0);
        stows.recentColorsChronological.value.add(newColorString);
        final int removedColorPosition = stows.recentColorsPositioned.value
            .indexOf(removedColorString);
        stows.recentColorsPositioned.value[removedColorPosition] =
            newColorString;
      } else {
        // if not full, add the new color to the end
        stows.recentColorsChronological.value.add(newColorString);
        stows.recentColorsPositioned.value.insert(0, newColorString);
      }
      stows.recentColorsChronological.notifyListeners();
      stows.recentColorsPositioned.notifyListeners();
    }
  }

  /// Prompts the user to pick photos from their device.
  /// Returns the number of photos picked.
  ///
  /// If [photoInfos] is provided, it will be used instead of the file picker.
  Future<int> _pickPhotos([List<_PhotoInfo>? photoInfos]) async {
    if (coreInfo.readOnly) return 0;

    final currentPageIndex = this.currentPageIndex;

    photoInfos ??= await _pickPhotosWithFilePicker();
    if (photoInfos.isEmpty) return 0;

    // use the Select tool so that the user can move the new image
    currentTool = Select.current;

    var images = <EditorImage>[];
    for (final _PhotoInfo photoInfo in photoInfos) {
      if (photoInfo.extension == '.pdf') {
        //Android allows pdf selection even if not allowed
        showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.editor.photoPdfError.title),
            content: Text(t.editor.photoPdfError.message),
            actions: [
              CupertinoDialogAction(
                child: Text(t.common.done),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
        continue;
      } else if (photoInfo.extension == '.svg') {
        images.add(
          SvgEditorImage(
            id: coreInfo.nextImageId++,
            svgString: utf8.decode(photoInfo.bytes),
            svgFile: null,
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          ),
        );
      } else {
        images.add(
          PngEditorImage(
            id: coreInfo.nextImageId++,
            extension: photoInfo.extension,
            imageProvider: MemoryImage(photoInfo.bytes),
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          ),
        );
      }
    }

    if (images.isEmpty) {
      return 0;
    }

    history.recordChange(
      EditorHistoryItem(
        type: .draw,
        pageIndex: currentPageIndex,
        strokes: [],
        images: images,
      ),
    );
    createPage(currentPageIndex);
    coreInfo.pages[currentPageIndex].images.addAll(images);
    autosaveAfterDelay();

    return images.length;
  }

  Future<List<_PhotoInfo>> _pickPhotosWithFilePicker() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      // Taken from
      // https://github.com/brendan-duncan/image/blob/main/doc/formats.md
      // (plus .svg)
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'tiff',
        'bmp',
        'tga',
        'ico',
        'pvrtc',
        'svg',
        'webp',
        'psd',
        'exr',
      ],
    );
    if (files.isEmpty) return const [];

    return Future.wait([
      for (final file in files)
        () async {
          final extension = p.extension(file.path ?? file.name);
          if (extension.isEmpty) return null;
          final bytes = await file.readAsBytes();
          return (bytes: bytes, extension: extension);
        }(),
    ]).then((list) => list.nonNulls.toList());
  }

  /// Prompts the user to pick a PDF to import.
  /// Returns whether a PDF was picked.
  Future<bool> importPdf() async {
    if (coreInfo.readOnly) return false;
    if (!Editor.canRasterPdf) return false;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return false;

    return importPdfFromFilePath(file.path!);
  }

  Future<bool> importPdfFromFilePath(String path) async {
    final pdfDocument = await coreInfo.assetCache.pdfDocumentCache.load(path);
    if (!mounted) return false;
    final pageNumbers = await choosePdfPages(context, pdfDocument);
    if (pageNumbers == null || !mounted) return false;

    final emptyPage = coreInfo.pages.removeLast();
    assert(emptyPage.isEmpty);

    for (final pageNumber in pageNumbers) {
      final pdfPage = pdfDocument.pages[pageNumber - 1];
      assert(pdfPage.pageNumber >= 1, 'pdfrx page numbers start at 1');

      // resize to [defaultWidth] to keep pen sizes consistent
      final pageSize = Size(
        EditorPage.defaultWidth,
        EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
      );

      final page = EditorPage(
        size: pageSize,
        backgroundImage: PdfEditorImage(
          id: coreInfo.nextImageId++,
          pdfBytes: null,
          pdfFile: File(path),
          pdfPage: pdfPage.pageNumber - 1,
          pageIndex: coreInfo.pages.length,
          pageSize: pageSize,
          naturalSize: pdfPage.size,
          onMoveImage: onMoveImage,
          onDeleteImage: onDeleteImage,
          onMiscChange: autosaveAfterDelay,
          onLoad: () => setState(() {}),
          assetCache: coreInfo.assetCache,
        ),
      );
      coreInfo.pages.add(page);
      // TODO(adil192): Group multiple pages into one atomic change
      history.recordChange(
        EditorHistoryItem(
          type: .insertPage,
          pageIndex: coreInfo.pages.length - 1,
          strokes: const [],
          images: const [],
          page: page,
        ),
      );
    }

    coreInfo.pages.add(emptyPage);
    if (mounted) setState(() {});

    autosaveAfterDelay();

    return true;
  }

  Future paste() async {
    /// Maps image formats to their file extension.
    const Map<SimpleFileFormat, String> formats = {
      Formats.jpeg: '.jpeg',
      Formats.png: '.png',
      Formats.gif: '.gif',
      Formats.tiff: '.tiff',
      Formats.bmp: '.bmp',
      Formats.ico: '.ico',
      Formats.svg: '.svg',
      Formats.webp: '.webp',
    };

    final reader = await SystemClipboard.instance?.read();
    if (reader == null) return;

    final List<_PhotoInfo> photoInfos = [];
    final List<ReadProgress> progresses = [];

    for (final format in formats.keys) {
      if (!reader.canProvide(format)) continue;
      final progress = reader.getFile(format, (file) async {
        final stream = file.getStream();
        final List<int> bytes = [];
        await for (final chunk in stream) {
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) {
          log.warning('Pasted empty file: $file (${formats[format]})');
          return;
        }

        String extension;
        if (file.fileName != null) {
          extension = file.fileName!.substring(file.fileName!.lastIndexOf('.'));
        } else {
          extension = formats[format]!;
        }

        photoInfos.add((
          bytes: Uint8List.fromList(bytes),
          extension: extension,
        ));
      });
      if (progress != null) progresses.add(progress);
    }

    while (progresses.isNotEmpty) {
      progresses.removeWhere((progress) => progress.fraction.value == 1);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await _pickPhotos(photoInfos);
  }

  Future exportAsPdf(BuildContext context) async {
    final pdf = await EditorExporter.generatePdf(coreInfo, context);
    final bytes = await pdf.save();
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.pdf',
      bytes,
      context: context,
    );
  }

  /// Exports the current note as an SBA (Saber Archive) file.
  Future exportAsSba(BuildContext context) async {
    final sba = await coreInfo.saveToSba(currentPageIndex: currentPageIndex);
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.sba',
      Uint8List.fromList(sba),
      context: context,
    );
  }

  /// Exports the current page as a PNG image file.
  ///
  /// This captures the canvas natively via [EditorExporter.screenshotPage],
  /// which guarantees the correct background color and omits UI elements
  /// like selection bounds or the text cursor. It computes a dynamic [pixelRatio]
  /// to ensure high quality while averting Out-Of-Memory exceptions on large canvases.
  Future exportAsPng(BuildContext context) async {
    final page = coreInfo.pages[currentPageIndex];

    const maxRasterizableSize = 3000.0;
    var targetPixelRatio = maxRasterizableSize / page.size.longestSide;
    if (targetPixelRatio > 1) targetPixelRatio = 1;

    try {
      final image = await EditorExporter.screenshotPage(
        coreInfo: coreInfo,
        pageIndex: currentPageIndex,
        rasterizeAllStrokes: true,
        pixelRatio: targetPixelRatio,
      );
      final pngBytes = await image.toByteData(format: .png);
      image.dispose();

      if (!context.mounted) return;
      await FileManager.exportFile(
        '${coreInfo.fileName}_page_${currentPageIndex + 1}.png',
        pngBytes!.buffer.asUint8List(),
        isImage: true,
        context: context,
      );
    } catch (e, st) {
      log.severe('Failed to export PNG', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;

    final Widget canvas = CanvasGestureDetector(
      key: _canvasGestureDetectorKey,
      filePath: coreInfo.filePath,
      isDrawGesture: isDrawGesture,
      onInteractionEnd: onInteractionEnd,
      onDrawStart: onDrawStart,
      onDrawUpdate: onDrawUpdate,
      onDrawEnd: onDrawEnd,
      onHovering: onHovering,
      onHoveringEnd: onHoveringEnd,
      onStylusButtonChanged: onStylusButtonChanged,
      updatePointerData: updatePointerData,
      undo: undo,
      redo: redo,
      pages: coreInfo.pages,
      initialPageIndex: coreInfo.initialPageIndex,
      pageBuilder: pageBuilder,
      isTextEditing: () => currentTool == Tool.textEditing,
      ruler: ruler,
      placeholderPageBuilder: (BuildContext context, int pageIndex) {
        return Canvas(
          path: coreInfo.filePath,
          page: coreInfo.pages[pageIndex],
          pageIndex: 0,
          textEditing: false,
          coreInfo: EditorCoreInfo.placeholder,
          currentStroke: null,
          currentStrokeDetectedShape: null,
          currentSelection: null,
          placeholder: true,
          setAsBackground: null,
          currentTool: currentTool,
          currentScale: double.minPositive,
        );
      },
      transformationController: _transformationController,
      lockPosition: widget.embedding?.lockPosition ?? false,
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
    );
    if (widget.embedding != null) return canvas;

    final readonlyBanner = ReadOnlyBanner(
      coreInfo.readOnlyReason,
      action: coreInfo.readOnlyReason == .versionTooNew
          ? showVersionTooNewDialog
          : null,
    );

    final Widget toolbar = Collapsible(
      axis: isToolbarVertical
          ? CollapsibleAxis.horizontal
          : CollapsibleAxis.vertical,
      collapsed:
          DynamicMaterialApp.isFullscreen &&
          !stows.editorToolbarShowInFullscreen.value,
      maintainState: true,
      // Pad the screen edges the toolbar touches, but not the side facing the
      // canvas: e.g. a bottom toolbar must not get the status bar's padding,
      // which it otherwise does in fullscreen (without the app bar).
      child: SafeArea(
        top: stows.editorToolbarAlignment.value != AxisDirection.down,
        bottom: stows.editorToolbarAlignment.value != AxisDirection.up,
        left: stows.editorToolbarAlignment.value != AxisDirection.right,
        right: stows.editorToolbarAlignment.value != AxisDirection.left,
        child: Toolbar(
          readOnly: coreInfo.readOnly,
          setTool: (tool) {
            if (tool is Eraser && currentTool is Eraser) {
              // setTool(Eraser) is a special case to toggle the eraser on/off
              tool = _lastNonEraserTool;
            }

            currentTool = tool;

            if (tool is Tape) {
              // Its own, see [Tape.currentTape].
            } else if (tool is Highlighter) {
              Highlighter.currentHighlighter = tool;
            } else if (tool is Pencil) {
              Pencil.currentPencil = tool;
            } else if (tool is Pen) {
              Pen.currentPen = tool;
            }

            if (mounted) setState(() {});
          },
          currentTool: currentTool,
          changeSelectionThickness: _changeSelectionThickness,
          finishSelectionThickness: _finishSelectionThickness,
          duplicateSelection: () => _selectionOwner._duplicateSelection(),
          deleteSelection: () => _selectionOwner._deleteSelection(),
          setColor: (color) {
            setState(() {
              updateColorBar(color);

              if (currentTool is Highlighter) {
                (currentTool as Highlighter).color = color.withAlpha(
                  Highlighter.alpha,
                );
              } else if (currentTool is Pen) {
                (currentTool as Pen).color = color;
              } else if (currentTool is SelectLasso ||
                  currentTool is SelectBox) {
                _selectionOwner._recolorSelection(color);
              }
            });
          },
          quillFocus: quillFocus,
          textEditing: currentTool == Tool.textEditing,
          toggleTextEditing: () => setState(() {
            if (currentTool == Tool.textEditing) {
              currentTool = Pen.currentPen;
              for (final page in coreInfo.pages) {
                // unselect text, but maintain cursor position
                page.quill.controller.moveCursorToPosition(
                  page.quill.controller.selection.extentOffset,
                );
                page.quill.focusNode.unfocus();
              }
            } else {
              currentTool = Tool.textEditing;
              quillFocus.value = coreInfo.pages[currentPageIndex].quill
                ..focusNode.requestFocus();
            }
          }),
          undo: undo,
          isUndoPossible: history.canUndo,
          redo: redo,
          isRedoPossible: history.canRedo,
          toggleFingerDrawing: () {
            stows.editorFingerDrawing.value = !stows.editorFingerDrawing.value;
            lastSeenPointerCount = 0;
          },
          ruler: ruler,
          zoomWindow: zoomWindow,
          toggleZoomWindow: _toggleZoomWindow,
          pickPhoto: _pickPhotos,
          paste: paste,
          exportAsSba: exportAsSba,
          exportAsPdf: exportAsPdf,
          exportAsPng: exportAsPng,
          showExportOptions: _showExportOptions,
          importPdf: Editor.canRasterPdf ? importPdf : null,
        ),
      ),
    );

    final Widget body;
    if (isToolbarVertical) {
      body = Row(
        textDirection: stows.editorToolbarAlignment.value == AxisDirection.left
            ? .ltr
            : .rtl,
        children: [
          toolbar,
          Expanded(
            child: Column(
              children: [
                Expanded(child: _withSideBySide(_withZoomWindow(canvas))),
                readonlyBanner,
              ],
            ),
          ),
        ],
      );
    } else {
      body = Column(
        verticalDirection:
            stows.editorToolbarAlignment.value == AxisDirection.up
            ? VerticalDirection.up
            : VerticalDirection.down,
        children: [
          Expanded(child: _withSideBySide(_withZoomWindow(canvas))),
          toolbar,
          readonlyBanner,
        ],
      );
    }

    return ValueListenableBuilder(
      valueListenable: savingState,
      builder: (context, savingState, child) {
        // don't allow user to go back until saving is done
        return PopScope(
          canPop: savingState == .saved,
          onPopInvokedWithResult: (didPop, _) {
            switch (savingState) {
              case .waitingToSave:
                assert(!didPop);
                saveToFile(); // trigger save now
                snackBarNeedsToSaveBeforeExiting();
              case .saving:
                assert(!didPop);
                snackBarNeedsToSaveBeforeExiting();
              case .saved:
                break;
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        appBar: DynamicMaterialApp.isFullscreen
            ? null
            : AppBar(
                toolbarHeight: kToolbarHeight,
                title: widget.customTitle != null
                    ? Text(widget.customTitle!)
                    : Form(
                        key: _filenameFormKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: TextFormField(
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          controller: filenameTextEditingController,
                          onChanged: renameFile,
                          autofocus: needsNaming,
                          validator: _validateFilenameTextField,
                        ),
                      ),
                leading: SaveIndicator(
                  savingState: savingState,
                  triggerSave: saveToFile,
                ),
                actions: [
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.insert_page_break,
                      cupertinoIcon: CupertinoIcons.add,
                    ),
                    tooltip: t.editor.menu.insertPage,
                    onPressed: () => setState(() {
                      final currentPageIndex = this.currentPageIndex;
                      insertPageAfter(currentPageIndex);
                      CanvasGestureDetector.scrollToPage(
                        pageIndex: currentPageIndex + 1,
                        pages: coreInfo.pages,
                        screenWidth: MediaQuery.sizeOf(context).width,
                        transformationController: _transformationController,
                      );
                    }),
                  ),
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.grid_view,
                      cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
                    ),
                    tooltip: t.editor.pages,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AdaptiveAlertDialog(
                          title: Text(t.editor.pages),
                          content: pageManager(context),
                          actions: const [],
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: _showExportOptions,
                    builder: (context, showExportOptions, _) => IconButton(
                      tooltip: t.editor.toolbar.export,
                      isSelected: showExportOptions,
                      onPressed: () =>
                          _showExportOptions.value = !_showExportOptions.value,
                      icon: const AdaptiveIcon(
                        icon: Icons.share,
                        cupertinoIcon: CupertinoIcons.share,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.more_vert,
                      cupertinoIcon: CupertinoIcons.ellipsis_vertical,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => bottomSheet(context),
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: colorScheme.surface,
                        constraints: const BoxConstraints(maxWidth: 500),
                      );
                    },
                  ),
                ],
              ),
        body: body,
        floatingActionButton:
            (DynamicMaterialApp.isFullscreen &&
                !stows.editorToolbarShowInFullscreen.value)
            ? FloatingActionButton(
                shape: platform.isCupertino ? const CircleBorder() : null,
                onPressed: () {
                  DynamicMaterialApp.setFullscreen(false, updateSystem: true);
                },
                child: const Icon(Icons.fullscreen_exit),
              )
            : null,
      ),
    );
  }

  void snackBarNeedsToSaveBeforeExiting() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.editor.needsToSaveBeforeExiting)));
  }

  Widget bottomSheet(BuildContext context) {
    final Brightness brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;
    final int currentPageIndex = this.currentPageIndex;

    return EditorBottomSheet(
      invert: invert,
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      setBackgroundPattern: (pattern) => setState(() {
        if (coreInfo.readOnly) return;
        final previous = coreInfo.backgroundPattern;
        coreInfo.backgroundPattern = pattern;
        stows.lastBackgroundPattern.value = pattern;
        history.recordChange(
          EditorHistoryItem(
            type: .backgroundPattern,
            pageIndex: currentPageIndex,
            backgroundPatternChange: Change(
              previous: previous,
              current: pattern,
            ),
            strokes: [],
            images: [],
          ),
        );
        autosaveAfterDelay();
      }),
      setLineHeight: (lineHeight) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineHeight = lineHeight;
        stows.lastLineHeight.value = lineHeight;
        autosaveAfterDelay();
      }),
      setLineThickness: (lineThickness) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineThickness = lineThickness;
        stows.lastLineThickness.value = lineThickness;
        autosaveAfterDelay();
      }),
      removeBackgroundImage: () => setState(() {
        if (coreInfo.readOnly) return;

        final page = coreInfo.pages[currentPageIndex];
        if (page.backgroundImage == null) return;
        page.images.add(page.backgroundImage!);
        page.backgroundImage = null;

        autosaveAfterDelay();
      }),
      redrawImage: () => setState(() {}),
      clearPage: () {
        clearPage(currentPageIndex);
      },
      clearAllPages: clearAllPages,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      pickPhotos: _pickPhotos,
      importPdf: importPdf,
      openNoteSideBySide: _openNoteSideBySide,
      openPdfSideBySide: _openPdfSideBySide,
      canRasterPdf: Editor.canRasterPdf,
      getIsWatchingServer: () => _watchServerTimer?.isActive ?? false,
      setIsWatchingServer: (bool watch) {
        if (watch) {
          _watchServerTimer ??= Timer.periodic(
            const Duration(seconds: 5),
            (_) => _refreshCurrentNote(),
          );
          if (coreInfo.readOnlyReason != .watchingServer) {
            assert(coreInfo.readOnlyReason == null);
            coreInfo.readOnlyReason = .watchingServer;
            if (mounted) setState(() {});
          }
        } else {
          _watchServerTimer?.cancel();
          _watchServerTimer = null;
          if (coreInfo.readOnlyReason == .watchingServer) {
            coreInfo.readOnlyReason = null;
            if (mounted) setState(() {});
          }
        }
      },
    );
  }

  Widget pageBuilder(BuildContext context, int pageIndex) {
    final page = coreInfo.pages[pageIndex];
    // The page itself, not its number: another editor (side by side) has
    // pages with the same numbers.
    final currentStroke = identical(Pen.currentStroke?.page, page)
        ? Pen.currentStroke
        : null;
    return Canvas(
      path: coreInfo.filePath,
      page: page,
      pageIndex: pageIndex,
      textEditing: currentTool == Tool.textEditing,
      coreInfo: coreInfo,
      currentStroke: currentStroke,
      currentStrokeDetectedShape: currentStroke != null
          ? Pen.detectedShape
          : null,
      currentSelection: () {
        final SelectResult selectResult;
        if (currentTool is SelectLasso || currentTool is SelectBox) {
          selectResult = (currentTool as Select).selectResult;
        } else {
          return null;
        }
        if (selectResult.owner != this) return null;
        if (selectResult.pageIndex != pageIndex) return null;
        return selectResult;
      }(),
      setAsBackground: (EditorImage image) {
        if (page.backgroundImage != null) {
          // restore previous background image as normal image
          page.images.add(page.backgroundImage!);
        }
        page.images.remove(image);
        page.backgroundImage = image;

        CanvasImage.activeListener
            .notifyListenersPlease(); // un-select active image

        autosaveAfterDelay();
        setState(() {});
      },
      currentTool: currentTool,
      currentScale: _transformationController.value.approxScale,
      overlay: zoomWindow.visible && zoomWindow.pageIndex == pageIndex
          ? (screenScale) =>
                ZoomWindowBox(zoomWindow: zoomWindow, scale: screenScale)
          : null,
    );
  }

  Widget pageManager(BuildContext context) {
    return EditorPageManager(
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      insertPageAfter: insertPageAfter,
      duplicatePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages[pageIndex];
        final newPage = page.copyWith(
          strokes: page.strokes
              .map((stroke) => stroke.copy()..pageIndex += 1)
              .toList(),
          images: page.images
              .map((image) => image.copy()..pageIndex += 1)
              .toList(),
          quill: QuillStruct(
            controller: flutter_quill.QuillController(
              document: flutter_quill.Document.fromDelta(
                page.quill.controller.document.toDelta(),
              ),
              selection: const TextSelection.collapsed(offset: 0),
            ),
            focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
          ),
          backgroundImage: page.backgroundImage?.copy()?..pageIndex += 1,
        );
        coreInfo.pages.insert(pageIndex + 1, newPage);
        listenToQuillChanges(newPage.quill, pageIndex + 1);
        history.recordChange(
          EditorHistoryItem(
            type: .insertPage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: newPage,
          ),
        );
        autosaveAfterDelay();
      }),
      clearPage: clearPage,
      deletePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages.removeAt(pageIndex);
        createPage(pageIndex - 1);
        history.recordChange(
          EditorHistoryItem(
            type: .deletePage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: page,
          ),
        );
        autosaveAfterDelay();
      }),
      transformationController: _transformationController,
    );
  }

  void insertPageAfter(int pageIndex) => setState(() {
    if (coreInfo.readOnly) return;
    final page = EditorPage();
    coreInfo.pages.insert(pageIndex + 1, page);
    listenToQuillChanges(page.quill, pageIndex + 1);
    history.recordChange(
      EditorHistoryItem(
        type: .insertPage,
        pageIndex: pageIndex + 1,
        strokes: const [],
        images: const [],
        page: page,
      ),
    );
    autosaveAfterDelay();
  });

  void clearPage(int pageIndex) {
    if (coreInfo.readOnly) return;
    final page = coreInfo.pages[pageIndex];
    setState(() {
      final removedStrokes = page.strokes.toList();
      final removedImages = page.images.toList();
      page.strokes.clear();
      page.images.clear();
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: pageIndex,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
      autosaveAfterDelay();
    });
  }

  void clearAllPages() {
    if (coreInfo.readOnly) return;
    setState(() {
      final removedStrokes = <Stroke>[];
      final removedImages = <EditorImage>[];
      for (final page in coreInfo.pages) {
        removedStrokes.addAll(page.strokes);
        removedImages.addAll(page.images);
        page.strokes.clear();
        page.images.clear();
      }
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: 0,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
    });
    autosaveAfterDelay();
  }

  Future<void> showVersionTooNewDialog() async {
    final disableReadOnly =
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.editor.versionTooNew.title),
            content: Text(t.editor.versionTooNew.subtitle),
            actions: [
              CupertinoDialogAction(
                child: Text(t.common.cancel),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                child: Text(t.editor.versionTooNew.allowEditing),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!disableReadOnly) return;

    if (coreInfo.readOnlyReason == .versionTooNew) {
      coreInfo.readOnlyReason = null;
      if (mounted) setState(() {});
    }
  }

  late int _lastCurrentPageIndex = coreInfo.initialPageIndex ?? 0;

  /// The index of the page that is currently centered on screen.
  int get currentPageIndex {
    if (!mounted) return _lastCurrentPageIndex;

    final screenWidth = MediaQuery.sizeOf(context).width;

    return _lastCurrentPageIndex = getPageIndexFromScrollPosition(
      scrollY: -scrollY,
      screenWidth: screenWidth,
      pages: coreInfo.pages,
    );
  }

  @visibleForTesting
  static int getPageIndexFromScrollPosition({
    required double scrollY,
    required double screenWidth,
    required List<EditorPage> pages,
  }) {
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final bottomOfPage = CanvasGestureDetector.getTopOfPage(
        pageIndex: pageIndex + 1, // top of next page
        pages: pages,
        screenWidth: screenWidth,
      );

      if (scrollY < bottomOfPage) {
        return pageIndex;
      }
    }
    // below the last page
    return pages.length - 1;
  }

  @override
  void dispose() {
    unawaited(_cleanUpAsync());

    DynamicMaterialApp.removeFullscreenListener(_setState);

    _delayedSaveTimer?.cancel();
    _watchServerTimer?.cancel();
    unawaited(_noteDownloadSubscription?.cancel());
    if (Pen.onDetectedShapeChanged == _setState) {
      Pen.onDetectedShapeChanged = null;
    }
    _lastSeenPointerCountTimer?.cancel();
    ruler.dispose();
    zoomWindow.dispose();
    sideBySide.dispose();
    _showExportOptions.dispose();

    _removeKeybindings();
    if (_shortcutTarget == this) _shortcutTarget = null;

    // manually save pen properties since the listeners don't fire if a property is changed
    stows.lastFountainPenOptions.notifyListeners();
    stows.lastBallpointPenOptions.notifyListeners();
    stows.lastHighlighterOptions.notifyListeners();
    stows.lastPencilOptions.notifyListeners();
    stows.lastShapePenOptions.notifyListeners();

    super.dispose();
  }

  Future<void> _cleanUpAsync() async {
    try {
      if (_renameTimer?.isActive ?? false) {
        _renameTimer!.cancel();
        await _renameFileNow();
        filenameTextEditingController.dispose();
      }
      await saveToFile();
    } finally {
      coreInfo.dispose();
    }
  }
}

/// A resize, rotation or thickness change of a selection in progress: the
/// selection as it was when it started, which each step transforms anew.
class _SelectionChange {
  new(this.select, {this.handle, this.box, this.start})
    : strokes = List.of(select.selectResult.strokes),
      imageRects = {
        for (final image in select.selectResult.images) image: image.dstRect,
      },
      path = select.selectResult.path;

  final Select select;

  /// The handle being dragged, the box it's on and where the drag started,
  /// or null for a thickness change.
  final SelectionHandle? handle;
  final SelectionBox? box;
  final Offset? start;

  /// The selection as it was.
  final List<Stroke> strokes;
  final Map<EditorImage, Rect> imageRects;
  final Path path;

  /// The change so far.
  var transform = SelectionTransform.identity;

  /// Changes the selection (on [page]) as it was by [transform].
  void update(EditorPage page, SelectionTransform transform) {
    this.transform = transform;
    _replaceSelected(page, [
      for (final stroke in strokes) transform.apply(stroke),
    ]);
    if (transform.rotation == 0) {
      for (final MapEntry(key: image, value: rect) in imageRects.entries) {
        image.dstRect = transform.applyToRect(rect);
      }
    }
    final result = select.selectResult;
    result.path = path.transform(transform.matrix);
    if (box case final box?) result.box = box.copyWith(transform: transform);
  }

  /// Puts the selection (on [page]) back as it was.
  void revert(EditorPage page) {
    transform = SelectionTransform.identity;
    _replaceSelected(page, strokes);
    for (final MapEntry(key: image, value: rect) in imageRects.entries) {
      image.dstRect = rect;
    }
    select.selectResult.path = path;
  }

  /// Puts [replacements] in place of the selected strokes on [page].
  void _replaceSelected(EditorPage page, List<Stroke> replacements) {
    final selected = select.selectResult.strokes;
    for (var i = 0; i < replacements.length; i++) {
      final index = page.strokes.indexOf(selected[i]);
      if (index != -1) page.strokes[index] = replacements[i];
    }
    selected
      ..clear()
      ..addAll(replacements);
    page.redrawStrokes();
  }
}
