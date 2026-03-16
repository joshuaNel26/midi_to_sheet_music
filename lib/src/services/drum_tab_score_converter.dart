import 'dart:math' as math;

import '../models/drum_models.dart';
import 'drum_tab_builder.dart';

class DrumTabScoreConverter {
  ScoreDocument build(DrumTabDocument document) {
    final measures = <ScoreMeasure>[];
    final pieceById = {
      for (final piece in document.pieces)
        piece.id: DrumLibrary.pieceForId(piece.id),
    };
    final activePieceIds = <String>{};
    var totalHits = 0;

    for (final measure in document.measures) {
      final slots = <ScoreSlot>[];

      for (
        var slotIndex = 0;
        slotIndex < measure.slotsPerMeasure;
        slotIndex++
      ) {
        final hits = <ScoreHit>[];

        for (final tabPiece in document.pieces) {
          final cell = measure.pieceCells[tabPiece.id]![slotIndex];
          if (cell == '-') {
            continue;
          }

          final piece = pieceById[tabPiece.id]!;
          hits.add(
            ScoreHit(
              piece: piece,
              midiNote: DrumLibrary.defaultMidiNoteForPieceId(tabPiece.id),
              velocity: cell == cell.toUpperCase() ? 112 : 96,
            ),
          );
          activePieceIds.add(tabPiece.id);
          totalHits += 1;
        }

        if (hits.isEmpty) {
          continue;
        }

        hits.sort(
          (left, right) =>
              left.piece.staffPosition.compareTo(right.piece.staffPosition),
        );
        slots.add(ScoreSlot(index: slotIndex, hits: hits));
      }

      measures.add(
        ScoreMeasure(
          index: measure.measureIndex,
          slotsPerMeasure: measure.slotsPerMeasure,
          beatsPerMeasure: document.timeSignature.numerator,
          slotsPerBeat: document.slotsPerBeat,
          slots: slots,
        ),
      );
    }

    final systems = <ScoreSystem>[];
    for (
      var index = 0;
      index < measures.length;
      index += scoreMeasuresPerSystem
    ) {
      systems.add(
        ScoreSystem(
          index: systems.length,
          measures: measures.sublist(
            index,
            math.min(index + scoreMeasuresPerSystem, measures.length),
          ),
        ),
      );
    }

    final pages = <ScorePageData>[];
    for (var index = 0; index < systems.length; index += scoreSystemsPerPage) {
      pages.add(
        ScorePageData(
          index: pages.length,
          systems: systems.sublist(
            index,
            math.min(index + scoreSystemsPerPage, systems.length),
          ),
        ),
      );
    }

    final orderedPieces = [
      for (final piece in document.pieces)
        if (activePieceIds.contains(piece.id)) pieceById[piece.id]!,
    ]..sort((left, right) => left.staffPosition.compareTo(right.staffPosition));

    return ScoreDocument(
      title: document.title,
      tempoBpm: document.tempoBpm,
      timeSignature: document.timeSignature,
      measures: measures,
      pages: pages.isEmpty
          ? [const ScorePageData(index: 0, systems: [])]
          : pages,
      usedPieces: orderedPieces,
      totalHits: totalHits,
    );
  }
}
