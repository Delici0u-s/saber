import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/canvas_background_pattern.dart';
import 'package:sbn/change.dart';

class EditorHistory {
  static const maxHistoryLength = 100;

  /// A stack of the changes that have been made in the editor.
  /// The last element is used when undoing.
  ///
  /// See also: [_future]
  final List<EditorHistoryItem> _past = [];

  /// A stack of the changes that have been undone in the editor.
  /// The last element is used when redoing.
  ///
  /// See also: [_past]
  final List<EditorHistoryItem> _future = [];

  /// The last saved state in the history.
  /// This is used to determine whether an autosave is needed.
  EditorHistoryItem? _lastSaved;

  /// True if redo is possible.
  /// We don't directly clear [_future] because we sometimes need to
  /// reject strokes (i.e. accidental strokes when zooming).
  var _isRedoPossible = false;

  /// Removes an element from the [_past] stack,
  /// adds it to the [_future] stack, and returns it.
  ///
  /// Please check [canUndo] first: this method will
  /// throw an exception if there is nothing to undo.
  EditorHistoryItem undo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    final item = _past.removeLast();
    _future.add(item);
    return item;
  }

  /// Removes an element from the [_future] stack,
  /// adds it to the [_past] stack, and returns it.
  ///
  /// Please check [canRedo] first: this method will
  /// throw an exception if there is nothing to redo.
  EditorHistoryItem redo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    final item = _future.removeLast();
    _past.add(item);
    return item;
  }

  /// Allows you to see the last item in the [_past] stack
  /// without removing it.
  ///
  /// Please check [canUndo] first: this method will
  /// throw an exception if there is nothing to undo.
  EditorHistoryItem peekUndo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    return _past.last;
  }

  /// Allows you to see the last item in the [_future] stack
  /// without removing it.
  ///
  /// Please check [canRedo] first: this method will
  /// throw an exception if there is nothing to redo.
  EditorHistoryItem peekRedo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    return _future.last;
  }

  /// Adds an item to the [_past] stack.
  void recordChange(EditorHistoryItem item) {
    assert(
      item.type != .quillUndoneChange,
      'EditorHistoryItemType.quillUndoneChange is just a hack to make undoing quill changes easier. It should just be recorded as a quill change.',
    );

    _past.add(item);
    if (_past.length > maxHistoryLength) _past.removeAt(0);
    _isRedoPossible = false;
  }

  /// Marks the last change as saved to disk.
  /// This does not modify the history stacks, but allows us to know
  /// whether the current state is saved or not.
  void markLastChangeAsSaved() {
    _lastSaved = _past.lastOrNull;
  }

  /// Whether the current state is saved to disk.
  ///
  /// Note that this explicitly checks the last change in the history,
  /// not whether _past is empty. This is because _past items can be discarded
  /// if the history exceeds [maxHistoryLength].
  bool get isCurrentStateSaved {
    return _past.lastOrNull == _lastSaved;
  }

  /// Removes the last history item due to a rejected stroke.
  /// This does essentially the opposite of [recordChange].
  EditorHistoryItem? removeAccidentalStroke() {
    _isRedoPossible = true;
    if (_past.isEmpty) return null;
    assert(_past.last.type == .draw, 'Accidental stroke is not a draw');
    assert(
      _past.last.strokes.length == 1,
      'Accidental strokes should be single-stroke',
    );
    assert(
      _past.last.images.isEmpty,
      'Accidental strokes should not contain images',
    );
    return _past.removeLast();
  }

  /// How many changes [undo] can undo.
  int get length => _past.length;

  /// Forgets the last change, without it being redoable (e.g. the dots a
  /// double tap drew), and returns it so it can be reverted.
  EditorHistoryItem dropLast() => _past.removeLast();

  /// Returns true if there is something to undo.
  bool get canUndo {
    return _past.isNotEmpty;
  }

  /// Returns true if there is something to redo.
  bool get canRedo {
    return _isRedoPossible && _future.isNotEmpty;
  }

  set canRedo(bool isRedoPossible) {
    _isRedoPossible = isRedoPossible;
  }

  void clearRedo() {
    _future.clear();
  }
}

class EditorHistoryItem {
  new({
    required this.type,
    required this.pageIndex,
    this.pageIndexStart,
    required this.strokes,
    this.replacementStrokes = const [],
    required this.images,
    this.replacementImages = const [],
    this.offset,
    this.page,
    this.quillChange,
    this.colorChange,
    this.backgroundPatternChange,
    this.imageRectChange,
    this.quarterTurns,
    this.backgroundFitChange,
  }) : assert(
         type != .move || offset != null,
         'Offset must be provided for move',
       ),
       assert(
         type != .move || pageIndexStart != null,
         'pageIndexStart must be provided for move',
       ),
       assert(
         type != .deletePage || page != null,
         'Page must be provided for deletePage',
       ),
       assert(
         type != .insertPage || page != null,
         'Page must be provided for insertPage',
       ),
       assert(
         type != .quillChange || quillChange != null,
         'Quill change must be provided for quillChange',
       ),
       assert(
         type != .quillUndoneChange || quillChange != null,
         'Quill change must be provided for quillUndoneChange',
       ),
       assert(
         type != .changeColor || colorChange?.length == strokes.length,
         'colorChange must be provided and contain each of strokes',
       ),
       assert(
         type != .backgroundPattern || backgroundPatternChange != null,
         'Background pattern change must be provided for backgroundPattern',
       ),
       assert(
         type != .replaceImage || replacementImages.length == images.length,
         'Each image needs a replacement for replaceImage',
       ),
       assert(
         type != .transform ||
             (replacementStrokes.length == strokes.length &&
                 imageRectChange?.length == images.length),
         'Each stroke needs a replacement and each image its change of place '
         'for transform',
       ),
       assert(
         type != .reshapePage ||
             (replacementStrokes.length == strokes.length &&
                 imageRectChange?.length == images.length &&
                 quarterTurns != null),
         'Each stroke needs a replacement, each image its change of place and '
         'the page its quarter turns for reshapePage',
       );

  final EditorHistoryItemType type;
  final int pageIndex;
  final int? pageIndexStart;
  final List<Stroke> strokes;
  final List<Stroke> replacementStrokes;
  final List<EditorImage> images;

  /// For [EditorHistoryItemType.replaceImage]: what each of [images] became.
  final List<EditorImage> replacementImages;
  final Rect? offset;
  final EditorPage? page;
  final DocChange? quillChange;
  final Map<Stroke, Change<Color>>? colorChange;
  final Change<CanvasBackgroundPattern>? backgroundPatternChange;

  /// For [EditorHistoryItemType.transform] and
  /// [EditorHistoryItemType.reshapePage]: where each of [images] was and
  /// went.
  final Map<EditorImage, Change<Rect>>? imageRectChange;

  /// For [EditorHistoryItemType.reshapePage]: how many quarter turns
  /// clockwise the page's background was turned by (negative: anticlockwise;
  /// 0 when it was stretched).
  final int? quarterTurns;

  /// For [EditorHistoryItemType.reshapePage]: how the page's background was
  /// fitted before and after, if that changed.
  final Change<BoxFit>? backgroundFitChange;

  EditorHistoryItem copyWith({
    EditorHistoryItemType? type,
    int? pageIndex,
    int? pageIndexStart,
    List<Stroke>? strokes,
    List<Stroke>? replacementStrokes,
    List<EditorImage>? images,
    List<EditorImage>? replacementImages,
    Rect? offset,
    EditorPage? page,
    DocChange? quillChange,
    Map<Stroke, Change<Color>>? colorChange,
    Change<CanvasBackgroundPattern>? backgroundPatternChange,
    Map<EditorImage, Change<Rect>>? imageRectChange,
    int? quarterTurns,
    Change<BoxFit>? backgroundFitChange,
  }) {
    return EditorHistoryItem(
      type: type ?? this.type,
      pageIndex: pageIndex ?? this.pageIndex,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
      strokes: strokes ?? this.strokes,
      replacementStrokes: replacementStrokes ?? this.replacementStrokes,
      images: images ?? this.images,
      replacementImages: replacementImages ?? this.replacementImages,
      offset: offset ?? this.offset,
      page: page ?? this.page,
      quillChange: quillChange ?? this.quillChange,
      colorChange: colorChange ?? this.colorChange,
      backgroundPatternChange:
          backgroundPatternChange ?? this.backgroundPatternChange,
      imageRectChange: imageRectChange ?? this.imageRectChange,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      backgroundFitChange: backgroundFitChange ?? this.backgroundFitChange,
    );
  }
}

enum EditorHistoryItemType {
  draw,
  erase,
  eraseArea,
  deletePage,
  insertPage,
  move,
  quillChange,
  quillUndoneChange,
  changeColor,
  backgroundPattern,
  replaceImage,

  /// Resizing, rotating or changing the thickness of a selection: [strokes]
  /// were swapped for [replacementStrokes], and images moved.
  transform,

  /// Turning or stretching page [pageIndex] to the other orientation: its
  /// width and height swapped, its background turned by [quarterTurns] and
  /// refitted by [backgroundFitChange], its [strokes] were swapped for
  /// [replacementStrokes] and its images moved.
  reshapePage,
}
