import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/image/pdf_document_cache.dart';
import 'package:saber/data/list_eq.dart';

/// A cache for assets that are loaded from disk.
///
/// This is the analogue to Flutter's image cache,
/// but for non-image assets.
///
/// There should be one instance of this class per
/// [EditorCoreInfo] instance.
class AssetCache {
  final log = Logger('AssetCache');

  final pdfDocumentCache = PdfDocumentCache();

  /// Maps a file path to its value.
  final Map<String, Object> _cache = {};

  /// Maps a file path to the visible images that use it.
  final Map<String, Set<EditorImage>> _images = {};

  /// Whether items from the cache can be removed:
  /// set to false during file save.
  var allowRemovingAssets = true;

  /// The note's own asset files (e.g. `note.sbn2.3`) that images were loaded
  /// from, mapped to their number.
  final Map<String, int> _noteAssetNumbers = {};

  /// The note's own asset files that images were loaded from, mapped to their
  /// number. Images (also deleted ones, which undo can bring back) keep
  /// reading these files, so saving keeps them at their numbers, see
  /// [OrderedAssetCache.new].
  Map<String, int> get noteAssetNumbers => Map.unmodifiable(_noteAssetNumbers);

  /// Returns [file], the note's own asset number [number], and remembers that
  /// an image was loaded from it (see [noteAssetNumbers]).
  File noteAsset(File file, int number) {
    _noteAssetNumbers[file.path] = number;
    return file;
  }

  /// Marks [image] as currently visible.
  ///
  /// It's safe to call this method multiple times.
  ///
  /// [file] is allowed to be null for convenience,
  /// in which case this function does nothing.
  void addImage<T extends Object>(EditorImage image, File? file, T value) {
    if (file == null) return;
    _images.putIfAbsent(file.path, () => {}).add(image);
    _cache[file.path] = value;
  }

  /// Returns null if [file] is not found.
  T? get<T extends Object>(File file) {
    return _cache[file.path] as T?;
  }

  /// Marks [image] as no longer visible.
  ///
  /// It's safe to call this method multiple times.
  ///
  /// If [image] is the last image using its file,
  /// the file is also removed from the cache.
  ///
  /// Returns whether the image was present in the cache.
  bool removeImage(EditorImage image) {
    if (!allowRemovingAssets) return false;

    for (final filePath in _images.keys) {
      final imagesUsingFile = _images[filePath]!;
      imagesUsingFile.remove(image);

      if (imagesUsingFile.isEmpty) {
        _images.remove(filePath);
        _cache.remove(filePath);
        return true;
      }
    }

    return false;
  }

  void dispose() {
    _images.clear();
    _cache.clear();
    _noteAssetNumbers.clear();
    pdfDocumentCache.dispose();
  }
}

class OrderedAssetCache {
  /// Numbers the assets of a note as they are added.
  ///
  /// [keptNumbers] maps the note's own asset files that are already on disk
  /// to their numbers (see [AssetCache.noteAssetNumbers]). Each of them keeps
  /// its number, and the other assets get numbers none of them has, so the
  /// files stay as they are and [changedIndices] leaves them out. Without
  /// [keptNumbers] (e.g. for an archive), assets are numbered from 0.
  new({Map<String, int> keptNumbers = const {}})
    : _keptNumbers = keptNumbers,
      _reserved = keptNumbers.values.toSet();

  final log = Logger('OrderedAssetCache');

  /// The assets by number; null where no asset has that number (yet).
  final List<Object?> _cache = [];

  final Map<String, int> _keptNumbers;

  /// The numbers of [_keptNumbers]: only their own file may have them.
  final Set<int> _reserved;

  /// Numbers whose file is already on disk (from [_keptNumbers]).
  final Set<int> _kept = {};

  /// Puts [item] at the lowest number that's free and returns it.
  int _add(Object item) {
    var index = 0;
    while ((index < _cache.length && _cache[index] != null) ||
        _reserved.contains(index)) {
      index++;
    }
    while (index >= _cache.length) {
      _cache.add(null);
    }
    _cache[index] = item;
    return index;
  }

  /// Adds [file] to the cache if not already present
  /// and returns the index of the added item.
  int addFile(File file) {
    final kept = _keptNumbers[file.path];
    if (kept != null) {
      while (kept >= _cache.length) {
        _cache.add(null);
      }
      _cache[kept] = file;
      _kept.add(kept);
      log.fine('OrderedAssetCache.addFile($file): kept index $kept');
      return kept;
    }

    final index = _cache.indexWhere(
      (other) => other is File && other.path == file.path,
    );
    log.fine('OrderedAssetCache.addFile($file): index = $index');

    if (index == -1) {
      return _add(file);
    } else {
      return index;
    }
  }

  /// Adds [bytes] to the cache if not already present
  /// and returns the index of the added item.
  int addBytes(List<int> bytes) {
    var index = _cache.indexOf(bytes);
    if (index == -1) {
      index = _cache.indexWhere(
        (other) => other is List<int> && listEq(bytes, other),
      );
    }
    log.fine('OrderedAssetCache.addBytes(...): index = $index');

    if (index == -1) {
      return _add(bytes);
    } else {
      return index;
    }
  }

  /// Adds [string] to the cache if not already present
  /// and returns the index of the added item.
  int addString(String string) {
    final index = _cache.indexOf(string);
    log.fine('OrderedAssetCache.addString(...): index = $index');

    if (index == -1) {
      return _add(string);
    } else {
      return index;
    }
  }

  /// Adds [image] to the cache if not already present
  /// and returns the index of the added item.
  int addImage(ImageProvider image) {
    if (image is MemoryImage) {
      return addBytes(image.bytes);
    } else if (image is FileImage) {
      return addFile(image.file);
    } else {
      throw ArgumentError.value(
        image,
        'image',
        'Unsupported ImageProvider type',
      );
    }
  }

  /// The number of asset files the note needs: one more than the highest
  /// number in use or kept (see [OrderedAssetCache.new]). Files with a higher
  /// number aren't needed any more.
  int get length => max(_cache.length, _reserved.fold(-1, max) + 1);

  /// The numbers whose file has to be written by [getBytes]. Kept files are
  /// already right, and numbers without an asset keep their file as it is.
  Iterable<int> get changedIndices sync* {
    for (var i = 0; i < _cache.length; i++) {
      if (_cache[i] != null && !_kept.contains(i)) yield i;
    }
  }

  /// Converts the item at position [index]
  /// to bytes and returns them.
  Future<List<int>> getBytes(int index) async {
    final item = _cache[index];
    if (item is List<int>) {
      return item;
    } else if (item is File) {
      return item.readAsBytes();
    } else if (item is String) {
      return utf8.encode(item);
    } else {
      throw Exception(
        'OrderedAssetCache.getBytes: unknown type ${item.runtimeType}',
      );
    }
  }
}
