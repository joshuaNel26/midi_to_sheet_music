import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/widgets/score_preview.dart';

void main() {
  test('keeps system height consistent on short final pages', () {
    const systemsHeight = 900.0;
    const systemGap = 20.0;

    expect(
      systemHeightForPage(systemsHeight, systemGap, 1),
      systemHeightForPage(systemsHeight, systemGap, 6),
    );
  });

  test('separates stem x positions for simultaneous hits', () {
    const noteCenterX = 200.0;
    const noteWidth = 10.0;

    final leftStem = stemXForIndex(noteCenterX, noteWidth, 0, 3);
    final middleStem = stemXForIndex(noteCenterX, noteWidth, 1, 3);
    final rightStem = stemXForIndex(noteCenterX, noteWidth, 2, 3);

    expect(leftStem, lessThan(middleStem));
    expect(middleStem, lessThan(rightStem));
  });

  test('draws each stem upward from its own notehead', () {
    const noteY = 100.0;
    const lineSpacing = 12.0;

    expect(stemTopYForNote(noteY, lineSpacing), lessThan(noteY));
  });
}
