import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/services/mapping_config_store.dart';

void main() {
  test('saves and loads mapping config from disk', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mapping-config-store',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final store = MappingConfigStore(
      directoryResolver: () async => tempDirectory,
    );
    final savedMapping = {36: 'kick', 38: 'snare', 42: 'closed_hihat'};

    await store.save(mapping: savedMapping, startOffsetSlots: 6);
    final loadedConfig = await store.load();

    expect(loadedConfig.noteMapping, savedMapping);
    expect(loadedConfig.startOffsetSlots, 6);
  });
}
