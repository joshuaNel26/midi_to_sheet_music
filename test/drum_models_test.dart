import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';

void main() {
  test('formats MIDI note names using FL Studio octave labels', () {
    expect(midiNoteName(36), 'C3');
    expect(midiNoteName(38), 'D3');
    expect(midiNoteName(60), 'C5');
  });
}
