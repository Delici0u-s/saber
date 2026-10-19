import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/image/pdf_document_cache.dart';

void main() {
  group('PdfDocumentCache.adoptUnchanged', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('pdf_document_cache_test');
      file = File('${dir.path}/note.sbn2.0')..writeAsStringSync('%PDF v1');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    PdfDocumentCache newCache() =>
        PdfDocumentCache(openFile: (_) async => _FakePdfDocument());

    test('takes over the document of an unchanged file', () async {
      final old = newCache(), reloaded = newCache();
      final document = await old.load(file.path);

      await reloaded.adoptUnchanged(old);

      expect(await reloaded.load(file.path), same(document));
      // and the old cache no longer owns (or disposes) it
      expect(await old.load(file.path), isNot(same(document)));
    });

    test('opens a changed file again', () async {
      final old = newCache(), reloaded = newCache();
      final document = await old.load(file.path);
      file.writeAsStringSync('%PDF v2, changed on another device');

      await reloaded.adoptUnchanged(old);

      expect(await reloaded.load(file.path), isNot(same(document)));
      expect(await old.load(file.path), same(document));
    });

    test('takes over a file rewritten with the same content', () async {
      // Saving a note rewrites all its assets, so their dates change.
      final old = newCache(), reloaded = newCache();
      final document = await old.load(file.path);
      file.writeAsStringSync(file.readAsStringSync());
      file.setLastModifiedSync(
        file.lastModifiedSync().add(const Duration(seconds: 1)),
      );

      await reloaded.adoptUnchanged(old);

      expect(await reloaded.load(file.path), same(document));
    });

    test('opens a changed file of the same size again', () async {
      final old = newCache(), reloaded = newCache();
      final document = await old.load(file.path);
      file.writeAsStringSync('%PDF v3');

      await reloaded.adoptUnchanged(old);

      expect(await reloaded.load(file.path), isNot(same(document)));
    });

    test('keeps its own document for a path it already has', () async {
      final old = newCache(), reloaded = newCache();
      await old.load(file.path);
      final own = await reloaded.load(file.path);

      await reloaded.adoptUnchanged(old);

      expect(await reloaded.load(file.path), same(own));
    });
  });
}

class _FakePdfDocument implements PdfDocument {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
