import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef MappingConfigDirectoryResolver = Future<Directory> Function();

class MappingConfigData {
  const MappingConfigData({
    required this.noteMapping,
    this.startOffsetSlots = 0,
  });

  const MappingConfigData.empty()
    : noteMapping = const {},
      startOffsetSlots = 0;

  final Map<int, String> noteMapping;
  final int startOffsetSlots;
}

class MappingConfigStore {
  MappingConfigStore({MappingConfigDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final MappingConfigDirectoryResolver _directoryResolver;

  Future<MappingConfigData> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return const MappingConfigData.empty();
    }

    final rawText = await file.readAsString();
    final rawJson = jsonDecode(rawText);
    if (rawJson is! Map<String, dynamic>) {
      return const MappingConfigData.empty();
    }

    final rawMapping = rawJson['noteMapping'];
    final mapping = <int, String>{};
    if (rawMapping is Map) {
      for (final entry in rawMapping.entries) {
        final note = int.tryParse(entry.key.toString());
        final drumId = entry.value?.toString();
        if (note != null && drumId != null && drumId.isNotEmpty) {
          mapping[note] = drumId;
        }
      }
    }

    final startOffsetSlots =
        int.tryParse(rawJson['startOffsetSlots']?.toString() ?? '') ?? 0;
    return MappingConfigData(
      noteMapping: mapping,
      startOffsetSlots: startOffsetSlots,
    );
  }

  Future<void> save({
    required Map<int, String> mapping,
    int startOffsetSlots = 0,
  }) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);

    final payload = {
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'startOffsetSlots': startOffsetSlots,
      'noteMapping': {
        for (final entry in mapping.entries) '${entry.key}': entry.value,
      },
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Future<File> _configFile() async {
    final directory = await _directoryResolver();
    return File(
      '${directory.path}${Platform.pathSeparator}mapping_config.json',
    );
  }
}
