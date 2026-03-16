import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/services/external_tool_service.dart';

void main() {
  test('infers musicxml2ly next to a LilyPond executable', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'external_tool_service_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final lilyPondFile = File(
      '${tempDir.path}${Platform.pathSeparator}lilypond.exe',
    );
    final musicXmlToLyFile = File(
      '${tempDir.path}${Platform.pathSeparator}musicxml2ly.py',
    );
    await lilyPondFile.writeAsString('', flush: true);
    await musicXmlToLyFile.writeAsString('', flush: true);

    final inferredPath = await ExternalToolService.inferMusicXmlToLyPath(
      lilyPondFile.path,
    );

    expect(inferredPath, musicXmlToLyFile.path);
  });
}
