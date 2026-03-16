import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef MappingConfigDirectoryResolver = Future<Directory> Function();

class MappingConfigStore {
  MappingConfigStore({MappingConfigDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final MappingConfigDirectoryResolver _directoryResolver;

  Future<Map<int, String>> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return {};
    }

    final rawText = await file.readAsString();
    final rawJson = jsonDecode(rawText);
    if (rawJson is! Map<String, dynamic>) {
      return {};
    }

    final rawMapping = rawJson['noteMapping'];
    if (rawMapping is! Map) {
      return {};
    }

    final mapping = <int, String>{};
    for (final entry in rawMapping.entries) {
      final note = int.tryParse(entry.key.toString());
      final drumId = entry.value?.toString();
      if (note != null && drumId != null && drumId.isNotEmpty) {
        mapping[note] = drumId;
      }
    }

    return mapping;
  }

  Future<void> save(Map<int, String> mapping) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);

    final payload = {
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
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
