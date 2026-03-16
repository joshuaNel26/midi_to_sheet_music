import 'dart:convert';
import 'dart:typed_data';

class MappingFileParseException implements Exception {
  const MappingFileParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImportedNoteMap {
  const ImportedNoteMap({
    required this.sourceName,
    required this.mapName,
    required this.version,
    required this.noteTargets,
  });

  final String sourceName;
  final String mapName;
  final String version;
  final Map<int, List<int>> noteTargets;

  int? primaryTargetFor(int sourceNote) {
    final targets = noteTargets[sourceNote];
    if (targets == null || targets.isEmpty) {
      return null;
    }

    return targets.first;
  }
}

class SamplerIoMapParser {
  ImportedNoteMap parse(Uint8List bytes, {required String sourceName}) {
    final xmlText = _extractXmlText(bytes);
    if (!xmlText.startsWith('<SAMPLER_IOMapInfo')) {
      throw const MappingFileParseException(
        'This mapping file does not look like a SAMPLER_IOMapInfo map.',
      );
    }

    final attributes = <String, String>{};
    final attributePattern = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
    for (final match in attributePattern.allMatches(xmlText)) {
      final key = match.group(1);
      final value = match.group(2);
      if (key != null && value != null) {
        attributes[key] = value;
      }
    }

    final noteTargets = <int, List<int>>{};
    final countPattern = RegExp(r'^Nv2_(\d+)Cnt$');

    for (final entry in attributes.entries) {
      final countMatch = countPattern.firstMatch(entry.key);
      if (countMatch == null) {
        continue;
      }

      final sourceNote = int.parse(countMatch.group(1)!);
      final targetCount = int.tryParse(entry.value) ?? 0;
      final targets = <int>[];

      for (var index = 0; index < targetCount; index++) {
        final targetValue = attributes['Nv2_$sourceNote-$index'];
        final parsedTarget = int.tryParse(targetValue ?? '');
        if (parsedTarget != null) {
          targets.add(parsedTarget);
        }
      }

      if (targets.isNotEmpty) {
        noteTargets[sourceNote] = targets;
      }
    }

    if (noteTargets.isEmpty) {
      throw const MappingFileParseException(
        'No note mapping entries were found in this .iom file.',
      );
    }

    return ImportedNoteMap(
      sourceName: sourceName,
      mapName: attributes['IOMapName'] ?? sourceName,
      version: attributes['IOMapInfoVersion'] ?? 'unknown',
      noteTargets: noteTargets,
    );
  }

  String _extractXmlText(Uint8List bytes) {
    final start = bytes.indexOf(60);
    final end = bytes.lastIndexOf(62);
    if (start < 0 || end <= start) {
      throw const MappingFileParseException(
        'The .iom file does not contain a readable XML payload.',
      );
    }

    return latin1.decode(bytes.sublist(start, end + 1)).trim();
  }
}
