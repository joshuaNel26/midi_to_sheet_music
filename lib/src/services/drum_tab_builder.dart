import 'dart:math' as math;

import '../models/drum_models.dart';

class DrumTabPiece {
  const DrumTabPiece({
    required this.id,
    required this.label,
    required this.symbol,
  });

  final String id;
  final String label;
  final String symbol;
}

class DrumTabMeasureSegment {
  DrumTabMeasureSegment({
    required this.measureIndex,
    required this.countTokens,
    required this.pieceCells,
  });

  final int measureIndex;
  final List<String> countTokens;
  final Map<String, List<String>> pieceCells;

  int get slotsPerMeasure => countTokens.length;
}

class DrumTabBlock {
  DrumTabBlock({
    required this.startMeasureIndex,
    required this.endMeasureIndex,
    required this.labelWidth,
    required this.pieces,
    required this.measures,
  });

  final int startMeasureIndex;
  final int endMeasureIndex;
  final int labelWidth;
  final List<DrumTabPiece> pieces;
  final List<DrumTabMeasureSegment> measures;

  String get label => startMeasureIndex == endMeasureIndex
      ? 'Measure ${startMeasureIndex + 1}'
      : 'Measures ${startMeasureIndex + 1}-${endMeasureIndex + 1}';

  List<String> get lines {
    return [
      _renderCountLine(),
      for (final piece in pieces) _renderPieceLine(piece),
    ];
  }

  void toggleCell({
    required String pieceId,
    required int measureOffset,
    required int slotIndex,
  }) {
    if (measureOffset < 0 || measureOffset >= measures.length) {
      return;
    }

    DrumTabPiece? piece;
    for (final candidate in pieces) {
      if (candidate.id == pieceId) {
        piece = candidate;
        break;
      }
    }

    if (piece == null) {
      return;
    }

    final cells = measures[measureOffset].pieceCells[pieceId];
    if (cells == null || slotIndex < 0 || slotIndex >= cells.length) {
      return;
    }

    cells[slotIndex] = cells[slotIndex] == '-' ? piece.symbol : '-';
  }

  String _renderCountLine() {
    final segments = measures
        .map((measure) => measure.countTokens.join())
        .join('|');
    return '${'Count'.padRight(labelWidth)} |$segments|';
  }

  String _renderPieceLine(DrumTabPiece piece) {
    final segments = measures
        .map((measure) => measure.pieceCells[piece.id]!.join())
        .join('|');
    return '${piece.label.padRight(labelWidth)} |$segments|';
  }
}

class DrumTabDocument {
  DrumTabDocument({
    required this.title,
    required this.tempoBpm,
    required this.timeSignature,
    required this.slotsPerBeat,
    required this.pieces,
    required this.measures,
    required this.blocks,
  });

  final String title;
  final int tempoBpm;
  final MidiTimeSignature timeSignature;
  final int slotsPerBeat;
  final List<DrumTabPiece> pieces;
  final List<DrumTabMeasureSegment> measures;
  final List<DrumTabBlock> blocks;

  int get blockCount => blocks.length;

  int get totalHits {
    var hitCount = 0;

    for (final measure in measures) {
      for (final cells in measure.pieceCells.values) {
        for (final cell in cells) {
          if (cell != '-') {
            hitCount += 1;
          }
        }
      }
    }

    return hitCount;
  }

  int get activePieceCount {
    var pieceCount = 0;

    for (final piece in pieces) {
      final hasHit = measures.any((measure) {
        final cells = measure.pieceCells[piece.id];
        if (cells == null) {
          return false;
        }

        return cells.any((cell) => cell != '-');
      });
      if (hasHit) {
        pieceCount += 1;
      }
    }

    return pieceCount;
  }

  String get metadataLine =>
      '${timeSignature.label} | $tempoBpm BPM | $totalHits hits | $activePieceCount mapped drums';

  String toPlainText() {
    final sections = <String>[title, metadataLine];

    for (final block in blocks) {
      sections
        ..add('')
        ..add(block.label)
        ..addAll(block.lines);
    }

    return sections.join('\n');
  }
}

class DrumTabBuilder {
  DrumTabDocument build(ScoreDocument score) {
    final pieces = [
      for (final piece in score.usedPieces)
        DrumTabPiece(
          id: piece.id,
          label: piece.shortLabel,
          symbol: piece.noteheadStyle == DrumNoteheadStyle.cross ? 'x' : 'o',
        ),
    ];
    final labelWidth = math.max(
      5,
      pieces.fold<int>(
        0,
        (longest, piece) => math.max(longest, piece.label.length),
      ),
    );
    final segments = <DrumTabMeasureSegment>[
      for (final measure in score.measures)
        DrumTabMeasureSegment(
          measureIndex: measure.index,
          countTokens: _renderCountTokens(measure),
          pieceCells: {
            for (final piece in pieces)
              piece.id: _renderPieceCells(piece, measure),
          },
        ),
    ];
    final blocks = <DrumTabBlock>[];

    for (
      var index = 0;
      index < segments.length;
      index += scoreMeasuresPerSystem
    ) {
      final blockMeasures = segments.sublist(
        index,
        math.min(index + scoreMeasuresPerSystem, segments.length),
      );

      blocks.add(
        DrumTabBlock(
          startMeasureIndex: blockMeasures.first.measureIndex,
          endMeasureIndex: blockMeasures.last.measureIndex,
          labelWidth: labelWidth,
          pieces: pieces,
          measures: blockMeasures,
        ),
      );
    }

    return DrumTabDocument(
      title: score.title,
      tempoBpm: score.tempoBpm,
      timeSignature: score.timeSignature,
      slotsPerBeat: score.measures.first.slotsPerBeat,
      pieces: pieces,
      measures: segments,
      blocks: blocks,
    );
  }

  List<String> _renderCountTokens(ScoreMeasure measure) {
    final tokens = <String>[];

    for (var slotIndex = 0; slotIndex < measure.slotsPerMeasure; slotIndex++) {
      final beatIndex = slotIndex ~/ measure.slotsPerBeat;
      final slotInBeat = slotIndex % measure.slotsPerBeat;
      tokens.add(_countToken(beatIndex, slotInBeat, measure.slotsPerBeat));
    }

    return tokens;
  }

  List<String> _renderPieceCells(DrumTabPiece piece, ScoreMeasure measure) {
    final cells = List<String>.filled(measure.slotsPerMeasure, '-');

    for (final slot in measure.slots) {
      ScoreHit? matchingHit;
      for (final hit in slot.hits) {
        if (hit.piece.id == piece.id) {
          matchingHit = hit;
          break;
        }
      }

      if (matchingHit == null) {
        continue;
      }

      cells[slot.index] = matchingHit.velocity >= 110
          ? piece.symbol.toUpperCase()
          : piece.symbol;
    }

    return cells;
  }

  String _countToken(int beatIndex, int slotInBeat, int slotsPerBeat) {
    if (slotInBeat == 0) {
      return '${beatIndex + 1}';
    }

    switch (slotsPerBeat) {
      case 1:
        return '-';
      case 2:
        return '&';
      case 3:
        return slotInBeat == 1 ? '&' : 'a';
      case 4:
        return switch (slotInBeat) {
          1 => 'e',
          2 => '+',
          _ => 'a',
        };
      default:
        return '+';
    }
  }
}
