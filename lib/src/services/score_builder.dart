import 'dart:math' as math;

import '../models/drum_models.dart';

class ScoreBuilder {
  ScoreDocument build({
    required ParsedMidiFile midi,
    required String title,
    required Map<int, String> mappingIds,
  }) {
    const slotsPerQuarter = 4;
    final slotsPerMeasure = math.max(
      1,
      ((midi.timeSignature.numerator * slotsPerQuarter * 4) /
              midi.timeSignature.denominator)
          .round(),
    );

    final slotsPerBeat = math.max(
      1,
      (slotsPerMeasure / midi.timeSignature.numerator).round(),
    );

    final slotMapByMeasure = <int, Map<int, List<ScoreHit>>>{};
    final usedPieces = <String, DrumPiece>{};
    var maxGlobalSlot = 0;
    var totalHits = 0;

    for (final noteEvent in midi.noteEvents) {
      final pieceId =
          mappingIds[noteEvent.note] ??
          DrumLibrary.defaultForMidiNote(noteEvent.note).id;
      final piece = DrumLibrary.pieceForId(pieceId);
      if (piece == DrumLibrary.ignore) {
        continue;
      }

      final globalSlot =
          ((noteEvent.startTick / midi.ticksPerQuarterNote) * slotsPerQuarter)
              .round();
      final measureIndex = globalSlot ~/ slotsPerMeasure;
      final slotIndex = globalSlot % slotsPerMeasure;

      maxGlobalSlot = math.max(maxGlobalSlot, globalSlot);
      usedPieces[piece.id] = piece;
      totalHits += 1;

      final measureMap = slotMapByMeasure.putIfAbsent(measureIndex, () => {});
      final hits = measureMap.putIfAbsent(slotIndex, () => <ScoreHit>[]);
      final alreadyPresent = hits.any(
        (hit) => hit.midiNote == noteEvent.note && hit.piece.id == piece.id,
      );
      if (!alreadyPresent) {
        hits.add(
          ScoreHit(
            piece: piece,
            midiNote: noteEvent.note,
            velocity: noteEvent.velocity,
          ),
        );
      }
    }

    final totalMeasures = math.max(1, (maxGlobalSlot ~/ slotsPerMeasure) + 1);

    final measures = List<ScoreMeasure>.generate(totalMeasures, (measureIndex) {
      final measureMap =
          slotMapByMeasure[measureIndex] ?? <int, List<ScoreHit>>{};
      final slotIndices = measureMap.keys.toList()..sort();

      return ScoreMeasure(
        index: measureIndex,
        slotsPerMeasure: slotsPerMeasure,
        beatsPerMeasure: midi.timeSignature.numerator,
        slotsPerBeat: slotsPerBeat,
        slots: [
          for (final slotIndex in slotIndices)
            ScoreSlot(
              index: slotIndex,
              hits: (measureMap[slotIndex]!
                ..sort(
                  (left, right) => left.piece.staffPosition.compareTo(
                    right.piece.staffPosition,
                  ),
                )),
            ),
        ],
      );
    });

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

    final orderedPieces = usedPieces.values.toList()
      ..sort(
        (left, right) => left.staffPosition.compareTo(right.staffPosition),
      );

    return ScoreDocument(
      title: title,
      tempoBpm: midi.tempoBpm,
      timeSignature: midi.timeSignature,
      measures: measures,
      pages: pages.isEmpty
          ? [const ScorePageData(index: 0, systems: [])]
          : pages,
      usedPieces: orderedPieces,
      totalHits: totalHits,
    );
  }
}
