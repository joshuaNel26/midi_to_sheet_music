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
    final singleStem = stemXForIndex(noteCenterX, noteWidth, 0, 1);

    final leftStem = stemXForIndex(noteCenterX, noteWidth, 0, 3);
    final middleStem = stemXForIndex(noteCenterX, noteWidth, 1, 3);
    final rightStem = stemXForIndex(noteCenterX, noteWidth, 2, 3);

    expect(singleStem, greaterThan(noteCenterX));
    expect(singleStem, lessThan(noteCenterX + noteWidth * 0.5));
    expect(leftStem, lessThan(middleStem));
    expect(middleStem, lessThan(rightStem));
  });

  test('draws each stem upward from its own notehead', () {
    const noteY = 100.0;
    const lineSpacing = 12.0;

    expect(stemTopYForNote(noteY, lineSpacing), lessThan(noteY));
  });

  test('places stacked rhythm bars lower for additional subdivisions', () {
    const stemX = 120.0;
    const stemTop = 80.0;
    const lineSpacing = 12.0;

    final eighthBar = rhythmBarRectForStem(stemX, stemTop, lineSpacing, 0);
    final sixteenthBar = rhythmBarRectForStem(stemX, stemTop, lineSpacing, 1);

    expect(eighthBar.right, closeTo(stemX + lineSpacing * 0.04, 0.5));
    expect(eighthBar.top, lessThan(sixteenthBar.top));
    expect(eighthBar.width, greaterThan(0));
  });
}
