import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/home/search_notes_button.dart';

void main() {
  const notes = [
    '/Maths/Week 1',
    '/Maths/Week 2',
    '/Physics/Optics',
    '/shopping list',
  ];

  test('finds notes by name or folder, ignoring case', () {
    expect(NotesSearchDelegate.matching(notes, 'week'), [
      '/Maths/Week 1',
      '/Maths/Week 2',
    ]);
    expect(NotesSearchDelegate.matching(notes, 'PHYSICS'), ['/Physics/Optics']);
  });

  test('every word has to match, in any order', () {
    expect(NotesSearchDelegate.matching(notes, '2 maths'), ['/Maths/Week 2']);
    expect(NotesSearchDelegate.matching(notes, 'maths optics'), isEmpty);
  });

  test('an empty query lists every note', () {
    expect(NotesSearchDelegate.matching(notes, '  '), hasLength(notes.length));
  });
}
