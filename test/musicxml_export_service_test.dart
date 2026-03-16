import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';
import 'package:midi_to_drum/src/services/musicxml_export_service.dart';

void main() {
  test('exports percussion MusicXML from the current score', () {
    final score = ScoreDocument(
      title: 'Pattern & Groove',
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
                ScoreHit(piece: DrumLibrary.snare, midiNote: 38, velocity: 96),
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
      totalHits: 3,
    );

    final xml = MusicXmlExportService.build(score);

    expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<score-partwise version="4.0">'));
    expect(xml, contains('<work-title>Pattern &amp; Groove</work-title>'));
    expect(xml, contains('<sign>percussion</sign>'));
    expect(xml, contains('<midi-channel>10</midi-channel>'));
    expect(xml, contains('<notehead>x</notehead>'));
    expect(xml, contains('<accent/>'));
    expect(xml, contains('<backup>'));
    expect(xml, contains('<voice>2</voice>'));
    expect(xml, contains('<bar-style>light-heavy</bar-style>'));
  });
}
