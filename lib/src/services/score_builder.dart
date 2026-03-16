import 'dart:math' as math;

import '../models/drum_models.dart';

class ScoreBuilder {
  ScoreDocument build({
    required ParsedMidiFile midi,
    required String title,
    required Map<int, String> mappingIds,
    int startOffsetSlots = 0,
  }) {
    final slotsPerMeasure = slotsPerMeasureForTimeSignature(midi.timeSignature);
    final slotsPerBeat = slotsPerBeatForTimeSignature(midi.timeSignature);
    final normalizedStartOffset = math.max(
      0,
      math.min(startOffsetSlots, slotsPerMeasure - 1),
    );

    final slotMapByMeasure = <int, Map<int, List<ScoreHit>>>{};
    final usedPieces = <String, DrumPiece>{};
    var maxGlobalSlot = 0;
    var totalHits = 0;
    final renderedEvents =
        <(int globalSlot, DrumPiece piece, int note, int velocity)>[];
    int? firstRenderedGlobalSlot;

    for (final noteEvent in midi.noteEvents) {
      final pieceId =
          mappingIds[noteEvent.note] ??
          DrumLibrary.defaultForMidiNote(noteEvent.note).id;
      final piece = DrumLibrary.pieceForId(pieceId);
      if (piece == DrumLibrary.ignore) {
        continue;
      }

      final globalSlot =
          ((noteEvent.startTick / midi.ticksPerQuarterNote) *
                  scoreSlotsPerQuarter)
              .round();
      firstRenderedGlobalSlot = firstRenderedGlobalSlot == null
          ? globalSlot
          : math.min(firstRenderedGlobalSlot, globalSlot);
      renderedEvents.add((
        globalSlot,
        piece,
        noteEvent.note,
        noteEvent.velocity,
      ));
      usedPieces[piece.id] = piece;
      totalHits += 1;
    }

    final alignmentShift = firstRenderedGlobalSlot ?? 0;

    for (final event in renderedEvents) {
      final effectiveGlobalSlot =
          (event.$1 - alignmentShift) + normalizedStartOffset;
      final measureIndex = effectiveGlobalSlot ~/ slotsPerMeasure;
      final slotIndex = effectiveGlobalSlot % slotsPerMeasure;

      maxGlobalSlot = math.max(maxGlobalSlot, effectiveGlobalSlot);

      final measureMap = slotMapByMeasure.putIfAbsent(measureIndex, () => {});
      final hits = measureMap.putIfAbsent(slotIndex, () => <ScoreHit>[]);
      final alreadyPresent = hits.any(
        (hit) => hit.midiNote == event.$3 && hit.piece.id == event.$2.id,
      );
      if (!alreadyPresent) {
        hits.add(
          ScoreHit(piece: event.$2, midiNote: event.$3, velocity: event.$4),
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
