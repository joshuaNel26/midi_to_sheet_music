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

    final piece = pieces
        .where((candidate) => candidate.id == pieceId)
        .cast<DrumTabPiece?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
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
    required this.metadataLine,
    required this.blocks,
  });

  final String title;
  final String metadataLine;
  final List<DrumTabBlock> blocks;

  int get blockCount => blocks.length;

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
    final blocks = <DrumTabBlock>[];

    for (
      var index = 0;
      index < score.measures.length;
      index += scoreMeasuresPerSystem
    ) {
      final blockMeasures = score.measures.sublist(
        index,
        math.min(index + scoreMeasuresPerSystem, score.measures.length),
      );
      final segments = [
        for (final measure in blockMeasures)
          DrumTabMeasureSegment(
            measureIndex: measure.index,
            countTokens: _renderCountTokens(measure),
            pieceCells: {
              for (final piece in pieces)
                piece.id: _renderPieceCells(piece, measure),
            },
          ),
      ];

      blocks.add(
        DrumTabBlock(
          startMeasureIndex: blockMeasures.first.index,
          endMeasureIndex: blockMeasures.last.index,
          labelWidth: labelWidth,
          pieces: pieces,
          measures: segments,
        ),
      );
    }

    return DrumTabDocument(
      title: score.title,
      metadataLine:
          '${score.timeSignature.label} | ${score.tempoBpm} BPM | ${score.totalHits} hits | ${score.usedPieces.length} mapped drums',
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
