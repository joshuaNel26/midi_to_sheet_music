import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';
import 'package:midi_to_drum/src/services/drum_tab_builder.dart';
import 'package:midi_to_drum/src/services/drum_tab_score_converter.dart';

void main() {
  test('rebuilds sheet music from the edited tab state', () {
    final sourceScore = ScoreDocument(
      title: 'Pattern',
      tempoBpm: 120,
      timeSignature: const MidiTimeSignature(numerator: 4, denominator: 4),
      measures: [
        ScoreMeasure(
          index: 0,
          slotsPerMeasure: 16,
          beatsPerMeasure: 4,
          slotsPerBeat: 4,
          slots: const [
            ScoreSlot(
              index: 0,
              hits: [
                ScoreHit(piece: DrumLibrary.kick, midiNote: 36, velocity: 112),
              ],
            ),
            ScoreSlot(
              index: 4,
              hits: [
                ScoreHit(piece: DrumLibrary.snare, midiNote: 38, velocity: 96),
              ],
            ),
          ],
        ),
      ],
      pages: const [ScorePageData(index: 0, systems: [])],
      usedPieces: const [
        DrumLibrary.kick,
        DrumLibrary.snare,
        DrumLibrary.crash,
      ],
      totalHits: 2,
    );

    final document = DrumTabBuilder().build(sourceScore);
    document.blocks.first.toggleCell(
      pieceId: DrumLibrary.snare.id,
      measureOffset: 0,
      slotIndex: 4,
    );
    document.blocks.first.toggleCell(
      pieceId: DrumLibrary.crash.id,
      measureOffset: 0,
      slotIndex: 8,
    );

    final converted = DrumTabScoreConverter().build(document);

    expect(document.metadataLine, '4/4 | 120 BPM | 2 hits | 2 mapped drums');
    expect(converted.totalHits, 2);
    expect(converted.usedPieces.map((piece) => piece.id), [
      DrumLibrary.crash.id,
      DrumLibrary.kick.id,
    ]);
    expect(converted.measures, hasLength(1));
    expect(converted.measures.first.slots.map((slot) => slot.index), [0, 8]);
    expect(converted.measures.first.slots.first.hits.single.velocity, 112);

    final crashHit = converted.measures.first.slots.last.hits.single;
    expect(crashHit.piece.id, DrumLibrary.crash.id);
    expect(crashHit.midiNote, 49);
    expect(crashHit.velocity, 96);
  });
}
