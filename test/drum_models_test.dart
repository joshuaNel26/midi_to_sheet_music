import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/models/drum_models.dart';

void main() {
  test('formats MIDI note names using FL Studio octave labels', () {
    expect(midiNoteName(36), 'C3');
    expect(midiNoteName(38), 'D3');
    expect(midiNoteName(60), 'C5');
  });

  test('uses a standard drum key layout for staff positions', () {
    expect(DrumLibrary.kick.staffPosition, 7);
    expect(DrumLibrary.floorTom.staffPosition, 8);
    expect(DrumLibrary.snare.staffPosition, 4);
    expect(DrumLibrary.midTom.staffPosition, 2);
    expect(DrumLibrary.highTom.staffPosition, 0);
    expect(DrumLibrary.closedHiHat.staffPosition, -1);
    expect(DrumLibrary.ride.staffPosition, -1);
    expect(DrumLibrary.crash.staffPosition, -2);
  });
}
