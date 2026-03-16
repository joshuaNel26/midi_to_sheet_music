import 'package:flutter_test/flutter_test.dart';

import 'package:midi_to_drum/src/app.dart';

void main() {
  testWidgets('shows the desktop title before a file is loaded', (
    tester,
  ) async {
    await tester.pumpWidget(const MidiToDrumApp());

    expect(find.text('MIDI to Drum Tab'), findsOneWidget);
    expect(find.text('Ready for a MIDI file'), findsOneWidget);
  });
}
