import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';
import 'package:midi_to_drum/src/services/score_builder.dart';

void main() {
  final midi = ParsedMidiFile(
    sourceName: 'pattern.mid',
    format: 1,
    trackCount: 1,
    ticksPerQuarterNote: 480,
    tempoMicrosecondsPerQuarter: 500000,
    timeSignature: const MidiTimeSignature(numerator: 4, denominator: 4),
    noteEvents: const [
      MidiNoteEvent(
        startTick: 480,
        durationTicks: 120,
        channel: 9,
        note: 36,
        velocity: 110,
      ),
      MidiNoteEvent(
        startTick: 960,
        durationTicks: 120,
        channel: 9,
        note: 38,
        velocity: 96,
      ),
    ],
    usedPercussionChannelOnly: true,
  );

  test('aligns the earliest rendered hit to beat 1 by default', () {
    final score = ScoreBuilder().build(
      midi: midi,
      title: 'Pattern',
      mappingIds: const {36: 'kick', 38: 'snare'},
    );

    expect(score.measures.first.slots.first.index, 0);
  });

  test('supports shifting the earliest rendered hit later in measure 1', () {
    final score = ScoreBuilder().build(
      midi: midi,
      title: 'Pattern',
      mappingIds: const {36: 'kick', 38: 'snare'},
      startOffsetSlots: 4,
    );

    expect(score.measures.first.slots.first.index, 4);
  });
}
