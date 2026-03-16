import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/drum_models.dart';
import '../theme.dart';

const a4AspectRatio = 1 / 1.41421356237;

int systemLayoutSlotsForPage(int pageSystemCount) {
  return math.max(scoreSystemsPerPage, pageSystemCount);
}

double systemHeightForPage(
  double systemsHeight,
  double systemGap,
  int pageSystemCount,
) {
  final layoutSlots = systemLayoutSlotsForPage(pageSystemCount);
  return (systemsHeight - (layoutSlots - 1) * systemGap) / layoutSlots;
}

double stemXForIndex(
  double noteCenterX,
  double noteWidth,
  int stemIndex,
  int stemCount,
) {
  final baseStemX = noteCenterX + noteWidth * 0.42;
  if (stemCount <= 1) {
    return baseStemX;
  }

  final spread = noteWidth * 0.18;
  final offset = (stemIndex - ((stemCount - 1) / 2)) * spread;
  return baseStemX + offset;
}

double stemTopYForNote(double noteY, double lineSpacing) {
  return noteY - lineSpacing * 3.15;
}

Rect rhythmBarRectForStem(
  double stemX,
  double stemTop,
  double lineSpacing,
  int barIndex,
) {
  final barTop = stemTop + barIndex * lineSpacing * 0.46;
  final barWidth = lineSpacing * 0.78;
  return Rect.fromLTWH(
    stemX - barWidth + lineSpacing * 0.04,
    barTop,
    barWidth,
    lineSpacing * 0.18,
  );
}

class ScorePageWidget extends StatelessWidget {
  const ScorePageWidget({super.key, required this.score, required this.page});

  final ScoreDocument score;
  final ScorePageData page;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: a4AspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppPalette.page,
            boxShadow: [
              BoxShadow(
                color: Color(0x1C000000),
                blurRadius: 24,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: CustomPaint(
            painter: ScorePagePainter(score: score, page: page),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class ScorePagePainter extends CustomPainter {
  ScorePagePainter({required this.score, required this.page});

  final ScoreDocument score;
  final ScorePageData page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppPalette.page);

    final paddingX = size.width * 0.075;
    final paddingY = size.height * 0.055;
    final contentWidth = size.width - paddingX * 2;

    final titlePainter = _layoutText(
      score.title,
      TextStyle(
        color: AppPalette.pageInk,
        fontFamily: 'Cambria',
        fontSize: size.width * 0.036,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: contentWidth,
    );
    titlePainter.paint(canvas, Offset(paddingX, paddingY));

    final metaPainter = _layoutText(
      '${score.timeSignature.label} - ${score.tempoBpm} BPM - ${score.totalHits} hits - ${score.usedPieces.length} mapped drums',
      TextStyle(
        color: AppPalette.pageInk.withValues(alpha: 0.74),
        fontSize: size.width * 0.015,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: contentWidth,
    );
    final metaOffset = Offset(paddingX, paddingY + titlePainter.height + 10);
    metaPainter.paint(canvas, metaOffset);

    final headerBottom = metaOffset.dy + metaPainter.height + 26;
    final footerTop = size.height - paddingY - 18;
    final systemsHeight = footerTop - headerBottom;
    final systemGap = size.height * 0.016;
    final systemHeight = systemHeightForPage(
      systemsHeight,
      systemGap,
      page.systems.length,
    );

    for (var index = 0; index < page.systems.length; index++) {
      final top = headerBottom + index * (systemHeight + systemGap);
      _drawSystem(
        canvas,
        Rect.fromLTWH(paddingX, top, contentWidth, systemHeight),
        page.systems[index],
        showTimeSignature: page.index == 0 && index == 0,
      );
    }

    final footerPainter = _layoutText(
      'Page ${page.index + 1} of ${score.totalPages}',
      TextStyle(
        color: AppPalette.pageInk.withValues(alpha: 0.62),
        fontSize: size.width * 0.013,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: contentWidth,
    );
    footerPainter.paint(
      canvas,
      Offset(size.width - paddingX - footerPainter.width, footerTop),
    );
  }

  void _drawSystem(
    Canvas canvas,
    Rect rect,
    ScoreSystem system, {
    required bool showTimeSignature,
  }) {
    if (system.measures.isEmpty) {
      return;
    }

    final staffTop = rect.top + rect.height * 0.33;
    final lineSpacing = rect.height * 0.12;
    final staffBottom = staffTop + lineSpacing * 4;
    final barPaint = Paint()
      ..color = AppPalette.pageInk.withValues(alpha: 0.82)
      ..strokeWidth = 1.35;
    final guidePaint = Paint()
      ..color = AppPalette.pageInk.withValues(alpha: 0.14)
      ..strokeWidth = 0.8;

    for (var line = 0; line < 5; line++) {
      final y = staffTop + line * lineSpacing;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), barPaint);
    }

    final measureWidth = rect.width / system.measures.length;
    final clefWidth = showTimeSignature
        ? measureWidth * 0.27
        : measureWidth * 0.16;

    _drawPercussionClef(canvas, rect.left + 12, staffTop, lineSpacing);
    if (showTimeSignature) {
      _drawTimeSignature(
        canvas,
        Offset(rect.left + 36, staffTop - lineSpacing * 0.18),
        score.timeSignature,
        lineSpacing,
      );
    }

    final labelPainter = _layoutText(
      'M${system.measures.first.index + 1}',
      TextStyle(
        color: AppPalette.pageInk.withValues(alpha: 0.66),
        fontSize: rect.height * 0.11,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: measureWidth,
    );
    labelPainter.paint(canvas, Offset(rect.left, rect.top + 4));

    for (
      var measureIndex = 0;
      measureIndex < system.measures.length;
      measureIndex++
    ) {
      final measure = system.measures[measureIndex];
      final measureLeft = rect.left + measureIndex * measureWidth;
      final measureRight = measureLeft + measureWidth;

      if (measureIndex > 0) {
        canvas.drawLine(
          Offset(measureLeft, staffTop - 8),
          Offset(measureLeft, staffBottom + 8),
          barPaint,
        );
      }

      final innerLeft = measureLeft + (measureIndex == 0 ? clefWidth : 14);
      final innerRight = measureRight - 10;
      final innerWidth = math.max(32.0, innerRight - innerLeft);

      if (measure.isEmpty) {
        _drawWholeMeasureRest(
          canvas,
          Rect.fromLTRB(innerLeft, staffTop, innerRight, staffBottom),
          lineSpacing,
        );
        continue;
      }

      for (var beat = 1; beat < measure.beatsPerMeasure; beat++) {
        final beatX =
            innerLeft +
            (beat * measure.slotsPerBeat / measure.slotsPerMeasure) *
                innerWidth;
        canvas.drawLine(
          Offset(beatX, staffTop),
          Offset(beatX, staffBottom),
          guidePaint,
        );
      }

      for (final slot in measure.slots) {
        final x =
            innerLeft +
            ((slot.index + 0.5) / measure.slotsPerMeasure) * innerWidth;
        _drawSlot(canvas, x, slot, measure, staffTop, lineSpacing);
      }
    }

    canvas.drawLine(
      Offset(rect.right, staffTop - 8),
      Offset(rect.right, staffBottom + 8),
      barPaint,
    );

    if (system.measures.last.index == score.measures.last.index) {
      canvas.drawLine(
        Offset(rect.right - 4, staffTop - 8),
        Offset(rect.right - 4, staffBottom + 8),
        Paint()
          ..color = AppPalette.pageInk
          ..strokeWidth = 2.4,
      );
    }
  }

  void _drawSlot(
    Canvas canvas,
    double x,
    ScoreSlot slot,
    ScoreMeasure measure,
    double staffTop,
    double lineSpacing,
  ) {
    final sortedHits = [...slot.hits]
      ..sort(
        (left, right) =>
            left.piece.staffPosition.compareTo(right.piece.staffPosition),
      );
    final stemmedHits = sortedHits.where((hit) => hit.piece.showStem).toList();
    final noteWidth = lineSpacing * 1.05;
    final noteHeight = lineSpacing * 0.72;
    final notePaint = Paint()..color = AppPalette.pageInk;
    final noteSpec = _noteSpecForSlot(measure, slot.index);
    final stemPaint = Paint()
      ..color = AppPalette.pageInk
      ..strokeWidth = 1.35;
    final stemTops = <double>[];
    var stemIndex = 0;

    for (final hit in sortedHits) {
      final y = _yForPosition(hit.piece.staffPosition, staffTop, lineSpacing);
      _drawLedgerLines(
        canvas,
        x,
        hit.piece.staffPosition,
        staffTop,
        lineSpacing,
        noteWidth,
      );
      _drawNotehead(canvas, x, y, hit.piece, noteWidth, noteHeight, notePaint);

      if (hit.piece.openMarker) {
        canvas.drawCircle(
          Offset(x + noteWidth * 0.72, y - lineSpacing * 0.9),
          lineSpacing * 0.18,
          Paint()
            ..color = AppPalette.pageInk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      if (!hit.piece.showStem) {
        continue;
      }

      final stemX = stemXForIndex(x, noteWidth, stemIndex, stemmedHits.length);
      final stemTop = stemTopYForNote(y, lineSpacing);
      stemTops.add(stemTop);
      stemIndex += 1;

      canvas.drawLine(Offset(stemX, y), Offset(stemX, stemTop), stemPaint);

      for (var barIndex = 0; barIndex < noteSpec.flagCount; barIndex++) {
        _drawRhythmBar(
          canvas,
          rhythmBarRectForStem(stemX, stemTop, lineSpacing, barIndex),
        );
      }

      if (noteSpec.dotted) {
        canvas.drawCircle(
          Offset(x + noteWidth * 1.15, y - lineSpacing * 0.12),
          lineSpacing * 0.11,
          Paint()..color = AppPalette.pageInk,
        );
      }
    }

    if (slot.isAccent) {
      final accentPaint = Paint()
        ..color = AppPalette.pageInk
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      final accentY =
          (stemTops.isEmpty ? staffTop : stemTops.reduce(math.min)) -
          lineSpacing * 0.46;
      final accentWidth = lineSpacing * 0.75;
      final accentStemX = stemTops.isEmpty
          ? x + noteWidth * 0.62
          : stemXForIndex(x, noteWidth, 0, math.max(stemmedHits.length, 1));
      canvas.drawLine(
        Offset(accentStemX - accentWidth * 0.5, accentY),
        Offset(accentStemX + accentWidth * 0.5, accentY - lineSpacing * 0.22),
        accentPaint,
      );
      canvas.drawLine(
        Offset(accentStemX - accentWidth * 0.5, accentY + lineSpacing * 0.1),
        Offset(accentStemX + accentWidth * 0.5, accentY - lineSpacing * 0.12),
        accentPaint,
      );
    }
  }

  void _drawLedgerLines(
    Canvas canvas,
    double x,
    int staffPosition,
    double staffTop,
    double lineSpacing,
    double noteWidth,
  ) {
    final ledgerPaint = Paint()
      ..color = AppPalette.pageInk
      ..strokeWidth = 1.2;
    final left = x - noteWidth * 0.8;
    final right = x + noteWidth * 0.8;

    if (staffPosition < 0) {
      for (var position = -2; position >= staffPosition; position -= 2) {
        final y = _yForPosition(position, staffTop, lineSpacing);
        canvas.drawLine(Offset(left, y), Offset(right, y), ledgerPaint);
      }
    } else if (staffPosition > 8) {
      for (var position = 10; position <= staffPosition; position += 2) {
        final y = _yForPosition(position, staffTop, lineSpacing);
        canvas.drawLine(Offset(left, y), Offset(right, y), ledgerPaint);
      }
    }
  }

  void _drawNotehead(
    Canvas canvas,
    double x,
    double y,
    DrumPiece piece,
    double width,
    double height,
    Paint paint,
  ) {
    if (piece.noteheadStyle == DrumNoteheadStyle.cross) {
      final crossPaint = Paint()
        ..color = AppPalette.pageInk
        ..strokeWidth = 1.45;
      canvas.drawLine(
        Offset(x - width * 0.45, y - height * 0.45),
        Offset(x + width * 0.45, y + height * 0.45),
        crossPaint,
      );
      canvas.drawLine(
        Offset(x - width * 0.45, y + height * 0.45),
        Offset(x + width * 0.45, y - height * 0.45),
        crossPaint,
      );
      return;
    }

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.32);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      paint,
    );
    canvas.restore();
  }

  void _drawRhythmBar(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = AppPalette.pageInk);
  }

  void _drawWholeMeasureRest(Canvas canvas, Rect rect, double lineSpacing) {
    final restWidth = math.min(rect.width * 0.22, lineSpacing * 2.5);
    final restHeight = lineSpacing * 0.45;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.top + lineSpacing * 1.9),
        width: restWidth,
        height: restHeight,
      ),
      Paint()..color = AppPalette.pageInk,
    );
  }

  void _drawPercussionClef(
    Canvas canvas,
    double x,
    double staffTop,
    double lineSpacing,
  ) {
    final paint = Paint()..color = AppPalette.pageInk;
    canvas.drawRect(
      Rect.fromLTWH(x, staffTop + lineSpacing * 0.4, 3.5, lineSpacing * 2.8),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        x + 8,
        staffTop + lineSpacing * 0.4,
        3.5,
        lineSpacing * 2.8,
      ),
      paint,
    );
  }

  void _drawTimeSignature(
    Canvas canvas,
    Offset origin,
    MidiTimeSignature timeSignature,
    double lineSpacing,
  ) {
    final numeratorPainter = _layoutText(
      '${timeSignature.numerator}',
      TextStyle(
        color: AppPalette.pageInk,
        fontSize: lineSpacing * 1.2,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: lineSpacing * 2,
    );
    final denominatorPainter = _layoutText(
      '${timeSignature.denominator}',
      TextStyle(
        color: AppPalette.pageInk,
        fontSize: lineSpacing * 1.2,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: lineSpacing * 2,
    );

    numeratorPainter.paint(canvas, origin);
    denominatorPainter.paint(
      canvas,
      Offset(origin.dx, origin.dy + lineSpacing * 1.4),
    );
  }

  _NoteSpec _noteSpecForSlot(ScoreMeasure measure, int slotIndex) {
    final slotIndices = measure.slots.map((slot) => slot.index).toList()
      ..sort();
    final current = slotIndices.indexOf(slotIndex);
    final nextSlot = current >= 0 && current < slotIndices.length - 1
        ? slotIndices[current + 1]
        : measure.slotsPerMeasure;

    var span = nextSlot - slotIndex;
    if (slotIndex.isOdd) {
      span = 1;
    } else if ((slotIndex % 4) == 2 && span > 2) {
      span = 2;
    } else {
      span = span.clamp(1, 4);
    }

    if (span >= 4) {
      return const _NoteSpec(flagCount: 0);
    }
    if (span == 3) {
      return const _NoteSpec(flagCount: 1, dotted: true);
    }
    if (span == 2) {
      return const _NoteSpec(flagCount: 1);
    }
    return const _NoteSpec(flagCount: 2);
  }

  double _yForPosition(int staffPosition, double staffTop, double lineSpacing) {
    return staffTop + (staffPosition * lineSpacing / 2);
  }

  TextPainter _layoutText(
    String text,
    TextStyle style, {
    required double maxWidth,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
  }

  @override
  bool shouldRepaint(covariant ScorePagePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.page != page;
  }
}

class _NoteSpec {
  const _NoteSpec({required this.flagCount, this.dotted = false});

  final int flagCount;
  final bool dotted;
}
