import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/services/external_tool_config_store.dart';
import 'package:midi_to_drum/src/services/external_tool_service.dart';

void main() {
  test('saves and loads external tool paths from disk', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'external_tool_config_store_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = ExternalToolConfigStore(
      directoryResolver: () async => tempDir,
    );
    const config = ExternalToolConfig(
      museScorePath: r'C:\Tools\MuseScore4.exe',
      crescendoPath: r'C:\Tools\crescendo.exe',
      lilyPondPath: r'C:\Tools\lilypond.exe',
      musicXmlToLyPath: r'C:\Tools\musicxml2ly.py',
    );

    await store.save(config);
    final loaded = await store.load();

    expect(loaded.museScorePath, config.museScorePath);
    expect(loaded.crescendoPath, config.crescendoPath);
    expect(loaded.lilyPondPath, config.lilyPondPath);
    expect(loaded.musicXmlToLyPath, config.musicXmlToLyPath);
  });
}
