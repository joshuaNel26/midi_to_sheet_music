import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';
import 'package:midi_to_drum/src/services/drum_tab_builder.dart';

void main() {
  test('builds drum tab text from a quantized score', () {
    final score = ScoreDocument(
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
                ScoreHit(
                  piece: DrumLibrary.closedHiHat,
                  midiNote: 42,
                  velocity: 96,
                ),
                ScoreHit(piece: DrumLibrary.kick, midiNote: 36, velocity: 112),
              ],
            ),
            ScoreSlot(
              index: 4,
              hits: [
                ScoreHit(piece: DrumLibrary.snare, midiNote: 38, velocity: 98),
              ],
            ),
            ScoreSlot(
              index: 8,
              hits: [
                ScoreHit(
                  piece: DrumLibrary.closedHiHat,
                  midiNote: 42,
                  velocity: 96,
                ),
              ],
            ),
          ],
        ),
      ],
      pages: const [ScorePageData(index: 0, systems: [])],
      usedPieces: const [
        DrumLibrary.closedHiHat,
        DrumLibrary.snare,
        DrumLibrary.kick,
      ],
      totalHits: 4,
    );

    final document = DrumTabBuilder().build(score);

    expect(document.blockCount, 1);
    expect(document.metadataLine, '4/4 | 120 BPM | 4 hits | 3 mapped drums');
    expect(document.blocks.first.lines.first, contains('Count'));
    expect(document.blocks.first.lines.first, contains('1e+a2e+a3e+a4e+a'));
    expect(document.blocks.first.lines[1], contains('CH'));
    expect(document.blocks.first.lines[1], contains('x-------x-------'));
    expect(document.blocks.first.lines[2], contains('Sn'));
    expect(document.blocks.first.lines[2], contains('----o-----------'));
    expect(document.blocks.first.lines[3], contains('Kick'));
    expect(document.blocks.first.lines[3], contains('O---------------'));
  });

  test('toggles a tab cell on and off inside a block', () {
    final score = ScoreDocument(
      title: 'Pattern',
      tempoBpm: 120,
      timeSignature: const MidiTimeSignature(numerator: 4, denominator: 4),
      measures: [
        const ScoreMeasure(
          index: 0,
          slotsPerMeasure: 16,
          beatsPerMeasure: 4,
          slotsPerBeat: 4,
          slots: [],
        ),
      ],
      pages: const [ScorePageData(index: 0, systems: [])],
      usedPieces: const [DrumLibrary.kick],
      totalHits: 0,
    );

    final document = DrumTabBuilder().build(score);

    document.blocks.first.toggleCell(
      pieceId: DrumLibrary.kick.id,
      measureOffset: 0,
      slotIndex: 0,
    );
    expect(document.totalHits, 1);
    expect(document.metadataLine, '4/4 | 120 BPM | 1 hits | 1 mapped drums');
    expect(document.blocks.first.lines[1], contains('o---------------'));

    document.blocks.first.toggleCell(
      pieceId: DrumLibrary.kick.id,
      measureOffset: 0,
      slotIndex: 0,
    );
    expect(document.totalHits, 0);
    expect(document.metadataLine, '4/4 | 120 BPM | 0 hits | 0 mapped drums');
    expect(document.blocks.first.lines[1], contains('----------------'));
  });
}
