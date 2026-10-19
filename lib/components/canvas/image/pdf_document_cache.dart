import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfDocumentCache {
  new({@visibleForTesting this.openFile = _openFile});

  /// Opens the PDF at a path. Tests replace it, since they can't load PDFium.
  final Future<PdfDocument> Function(String filePath) openFile;

  static Future<PdfDocument> _openFile(String filePath) =>
      PdfDocument.openFile(filePath, useProgressiveLoading: true);

  final Map<String, FutureOr<PdfDocument>> _cache = {};

  /// The content of each file when its document was opened, see
  /// [adoptUnchanged]. Content, not dates: saving a note rewrites (and syncs)
  /// all of its assets, changed or not.
  final Map<String, Future<Digest?>> _fingerprints = {};

  /// Loads a PDF document from [filePath].
  /// If the bytes are provided, they are used instead of reading from disk.
  FutureOr<PdfDocument> load(String filePath, {Uint8List? pdfBytes}) {
    return _cache[filePath] ??= _loadCacheMiss(filePath, pdfBytes: pdfBytes);
  }

  Future<PdfDocument> _loadCacheMiss(
    String filePath, {
    Uint8List? pdfBytes,
  }) async {
    final Future<PdfDocument> document;
    if (pdfBytes == null) {
      final fingerprint = _fingerprints[filePath] = _fingerprint(filePath);
      // Done once the file is read, so the fingerprint is of what was opened.
      document = openFile(filePath).then((opened) async {
        await fingerprint;
        return opened;
      });
    } else {
      document = PdfDocument.openData(
        pdfBytes,
        useProgressiveLoading: true,
        sourceName: filePath,
      );
    }
    _cache[filePath] = document;
    return document;
  }

  /// Takes over [other]'s documents whose files haven't changed since they
  /// were opened, so they aren't opened and rendered again.
  /// Returns how many it took over.
  Future<int> adoptUnchanged(PdfDocumentCache other) async {
    var adopted = 0;
    for (final MapEntry(key: filePath, value: fingerprint)
        in other._fingerprints.entries.toList()) {
      final opened = await fingerprint;
      if (opened == null || _cache.containsKey(filePath)) continue;
      if (await _fingerprint(filePath) != opened) continue;
      // [other] may have let go of it while we were reading the file.
      final document = other._cache.remove(filePath);
      if (document == null) continue;
      _cache[filePath] = document;
      _fingerprints[filePath] = other._fingerprints.remove(filePath)!;
      adopted++;
    }
    return adopted;
  }

  /// How many documents this cache has opened from files.
  int get fileDocumentCount => _fingerprints.length;

  /// A hash of the file's content, or null if it can't be read.
  static Future<Digest?> _fingerprint(String filePath) async {
    try {
      return sha1.convert(await File(filePath).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  void dispose() {
    for (final documentFuture in _cache.values) {
      Future.value(documentFuture).then((document) => document.dispose());
    }
    _cache.clear();
    _fingerprints.clear();
  }
}
