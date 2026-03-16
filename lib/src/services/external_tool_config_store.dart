import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'external_tool_service.dart';

typedef ExternalToolDirectoryResolver = Future<Directory> Function();

class ExternalToolConfigStore {
  ExternalToolConfigStore({ExternalToolDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final ExternalToolDirectoryResolver _directoryResolver;

  Future<ExternalToolConfig> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return const ExternalToolConfig.empty();
    }

    final rawText = await file.readAsString();
    final rawJson = jsonDecode(rawText);
    if (rawJson is! Map<String, dynamic>) {
      return const ExternalToolConfig.empty();
    }

    return ExternalToolConfig(
      museScorePath: _stringOrNull(rawJson['museScorePath']),
      crescendoPath: _stringOrNull(rawJson['crescendoPath']),
      lilyPondPath: _stringOrNull(rawJson['lilyPondPath']),
      musicXmlToLyPath: _stringOrNull(rawJson['musicXmlToLyPath']),
    );
  }

  Future<void> save(ExternalToolConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);

    final payload = {
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'museScorePath': config.museScorePath,
      'crescendoPath': config.crescendoPath,
      'lilyPondPath': config.lilyPondPath,
      'musicXmlToLyPath': config.musicXmlToLyPath,
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  String? _stringOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  Future<File> _configFile() async {
    final directory = await _directoryResolver();
    return File(
      '${directory.path}${Platform.pathSeparator}external_tools.json',
    );
  }
}
