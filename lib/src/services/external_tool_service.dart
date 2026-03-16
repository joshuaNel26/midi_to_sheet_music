import 'dart:async';
import 'dart:io';

import 'musicxml_export_service.dart';
import '../models/drum_models.dart';

class ExternalToolConfig {
  const ExternalToolConfig({
    this.museScorePath,
    this.crescendoPath,
    this.lilyPondPath,
    this.musicXmlToLyPath,
  });

  const ExternalToolConfig.empty()
    : museScorePath = null,
      crescendoPath = null,
      lilyPondPath = null,
      musicXmlToLyPath = null;

  final String? museScorePath;
  final String? crescendoPath;
  final String? lilyPondPath;
  final String? musicXmlToLyPath;

  bool get hasMuseScore => museScorePath != null && museScorePath!.isNotEmpty;
  bool get hasCrescendo => crescendoPath != null && crescendoPath!.isNotEmpty;
  bool get hasLilyPond => lilyPondPath != null && lilyPondPath!.isNotEmpty;
  bool get hasMusicXmlToLy =>
      musicXmlToLyPath != null && musicXmlToLyPath!.isNotEmpty;
  bool get hasLilyPondPipeline => hasLilyPond && hasMusicXmlToLy;

  ExternalToolConfig copyWith({
    String? museScorePath,
    String? crescendoPath,
    String? lilyPondPath,
    String? musicXmlToLyPath,
    bool clearMuseScorePath = false,
    bool clearCrescendoPath = false,
    bool clearLilyPondPath = false,
    bool clearMusicXmlToLyPath = false,
  }) {
    return ExternalToolConfig(
      museScorePath: clearMuseScorePath
          ? null
          : (museScorePath ?? this.museScorePath),
      crescendoPath: clearCrescendoPath
          ? null
          : (crescendoPath ?? this.crescendoPath),
      lilyPondPath: clearLilyPondPath
          ? null
          : (lilyPondPath ?? this.lilyPondPath),
      musicXmlToLyPath: clearMusicXmlToLyPath
          ? null
          : (musicXmlToLyPath ?? this.musicXmlToLyPath),
    );
  }
}

class ExternalToolService {
  Future<ExternalToolConfig> detectInstalledTools({
    ExternalToolConfig preferred = const ExternalToolConfig.empty(),
  }) async {
    final museScorePath = await _resolveExecutable(
      preferredPath: preferred.museScorePath,
      commandNames: const [
        'MuseScore4.exe',
        'MuseScore-Studio.exe',
        'MuseScore.exe',
        'mscore.exe',
      ],
      fallbackPaths: _museScoreFallbackPaths(),
    );
    final crescendoPath = await _resolveExecutable(
      preferredPath: preferred.crescendoPath,
      commandNames: const ['crescendo.exe', 'crescendo64.exe'],
      fallbackPaths: _crescendoFallbackPaths(),
    );
    final lilyPondPath = await _resolveExecutable(
      preferredPath: preferred.lilyPondPath,
      commandNames: const ['lilypond.exe'],
      fallbackPaths: _lilyPondFallbackPaths(),
    );
    var musicXmlToLyPath = await _resolveExecutable(
      preferredPath: preferred.musicXmlToLyPath,
      commandNames: const [
        'musicxml2ly.exe',
        'musicxml2ly.py',
        'musicxml2ly.bat',
        'musicxml2ly.cmd',
      ],
      fallbackPaths: _musicXmlToLyFallbackPaths(),
    );
    if (musicXmlToLyPath == null && lilyPondPath != null) {
      musicXmlToLyPath = await inferMusicXmlToLyPath(lilyPondPath);
    }

    return ExternalToolConfig(
      museScorePath: museScorePath,
      crescendoPath: crescendoPath,
      lilyPondPath: lilyPondPath,
      musicXmlToLyPath: musicXmlToLyPath,
    );
  }

  Future<String> launchMuseScore({
    required ScoreDocument score,
    required String museScorePath,
  }) async {
    final sessionDirectory = await Directory.systemTemp.createTemp(
      'midi_to_drum_musescore_',
    );
    final musicXmlPath = await _writeMusicXmlFile(score, sessionDirectory);
    await Process.start(museScorePath, [
      musicXmlPath,
    ], mode: ProcessStartMode.detached);
    return musicXmlPath;
  }

  Future<String> launchCrescendo({
    required ScoreDocument score,
    required String crescendoPath,
  }) async {
    final sessionDirectory = await Directory.systemTemp.createTemp(
      'midi_to_drum_crescendo_',
    );
    final musicXmlPath = await _writeMusicXmlFile(score, sessionDirectory);
    await Process.start(crescendoPath, [
      musicXmlPath,
    ], mode: ProcessStartMode.detached);
    return musicXmlPath;
  }

  Future<String> renderWithLilyPond({
    required ScoreDocument score,
    required String lilyPondPath,
    required String musicXmlToLyPath,
  }) async {
    final sessionDirectory = await Directory.systemTemp.createTemp(
      'midi_to_drum_lilypond_',
    );
    final baseName = _safeFileBaseName(score.title);
    final musicXmlPath = await _writeMusicXmlFile(score, sessionDirectory);
    final lyPath =
        '${sessionDirectory.path}${Platform.pathSeparator}$baseName.ly';
    await _runMusicXmlToLy(
      musicXmlToLyPath: musicXmlToLyPath,
      musicXmlPath: musicXmlPath,
      lyPath: lyPath,
      workingDirectory: sessionDirectory.path,
    );

    final outputPrefix =
        '${sessionDirectory.path}${Platform.pathSeparator}$baseName';
    final lilyPondResult = await Process.run(lilyPondPath, [
      '--pdf',
      '--output=$outputPrefix',
      lyPath,
    ], workingDirectory: sessionDirectory.path);
    if (lilyPondResult.exitCode != 0) {
      throw ExternalToolException(
        'LilyPond failed to render the score. ${_stderrText(lilyPondResult)}',
      );
    }

    return '$outputPrefix.pdf';
  }

  Future<void> _runMusicXmlToLy({
    required String musicXmlToLyPath,
    required String musicXmlPath,
    required String lyPath,
    required String workingDirectory,
  }) async {
    final extension = _lowerCaseExtension(musicXmlToLyPath);
    late ProcessResult result;

    if (extension == '.py') {
      final pythonPath = await _resolvePythonExecutable();
      if (pythonPath == null) {
        throw const ExternalToolException(
          'musicxml2ly.py was found, but Python could not be located on this machine.',
        );
      }

      result = await Process.run(pythonPath, [
        musicXmlToLyPath,
        '--output=$lyPath',
        musicXmlPath,
      ], workingDirectory: workingDirectory);
    } else {
      result = await Process.run(musicXmlToLyPath, [
        '--output=$lyPath',
        musicXmlPath,
      ], workingDirectory: workingDirectory);
    }

    if (result.exitCode != 0) {
      throw ExternalToolException(
        'musicxml2ly failed to convert the score. ${_stderrText(result)}',
      );
    }
  }

  static Future<String?> inferMusicXmlToLyPath(String lilyPondPath) async {
    final lilyPondFile = File(lilyPondPath);
    final parentDirectory = lilyPondFile.parent;
    final candidates = [
      '${parentDirectory.path}${Platform.pathSeparator}musicxml2ly.exe',
      '${parentDirectory.path}${Platform.pathSeparator}musicxml2ly.py',
      '${parentDirectory.path}${Platform.pathSeparator}musicxml2ly.bat',
      '${parentDirectory.path}${Platform.pathSeparator}musicxml2ly.cmd',
    ];

    return _firstExistingPath(candidates);
  }

  Future<String?> _resolveExecutable({
    required String? preferredPath,
    required List<String> commandNames,
    required List<String> fallbackPaths,
  }) async {
    if (preferredPath != null && await File(preferredPath).exists()) {
      return preferredPath;
    }

    for (final commandName in commandNames) {
      final fromWhere = await _where(commandName);
      if (fromWhere != null) {
        return fromWhere;
      }
    }

    return _firstExistingPath(fallbackPaths);
  }

  Future<String?> _resolvePythonExecutable() async {
    final environment = Platform.environment;
    final windowsDirectory = environment['WINDIR'];
    final fallbackPaths = [
      if (windowsDirectory != null)
        '$windowsDirectory${Platform.pathSeparator}py.exe',
    ];

    return _resolveExecutable(
      preferredPath: null,
      commandNames: const ['python.exe', 'py.exe', 'python3.exe'],
      fallbackPaths: fallbackPaths,
    );
  }

  Future<String?> _where(String executableName) async {
    try {
      final result = await Process.run('where', [executableName]);
      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout?.toString() ?? '';
      for (final line in output.split(RegExp(r'[\r\n]+'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        if (await File(trimmed).exists()) {
          return trimmed;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String> _writeMusicXmlFile(
    ScoreDocument score,
    Directory directory,
  ) async {
    final baseName = _safeFileBaseName(score.title);
    final musicXmlPath =
        '${directory.path}${Platform.pathSeparator}$baseName.musicxml';
    await File(
      musicXmlPath,
    ).writeAsString(MusicXmlExportService.build(score), flush: true);
    return musicXmlPath;
  }

  String _safeFileBaseName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return sanitized.isEmpty ? 'drum_score' : sanitized;
  }

  String _lowerCaseExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0) {
      return '';
    }

    return path.substring(dotIndex).toLowerCase();
  }

  List<String> _museScoreFallbackPaths() {
    final environment = Platform.environment;
    final roots = [
      environment['ProgramFiles'],
      environment['ProgramFiles(x86)'],
      environment['LocalAppData'],
    ].whereType<String>();

    final candidates = <String>[];
    for (final root in roots) {
      candidates.addAll([
        '$root\\MuseScore 4\\bin\\MuseScore4.exe',
        '$root\\MuseScore 4\\bin\\MuseScore-Studio.exe',
        '$root\\MuseScore Studio\\bin\\MuseScore4.exe',
        '$root\\MuseScore Studio\\bin\\MuseScore-Studio.exe',
        '$root\\Programs\\MuseScore 4\\bin\\MuseScore4.exe',
        '$root\\Programs\\MuseScore Studio\\bin\\MuseScore-Studio.exe',
      ]);
    }

    return candidates;
  }

  List<String> _lilyPondFallbackPaths() {
    final environment = Platform.environment;
    final roots = [
      environment['ProgramFiles'],
      environment['ProgramFiles(x86)'],
      environment['LocalAppData'],
    ].whereType<String>();

    final candidates = <String>[];
    for (final root in roots) {
      candidates.addAll([
        '$root\\LilyPond\\usr\\bin\\lilypond.exe',
        '$root\\LilyPond\\bin\\lilypond.exe',
        '$root\\Programs\\LilyPond\\usr\\bin\\lilypond.exe',
      ]);
    }

    return candidates;
  }

  List<String> _crescendoFallbackPaths() {
    final environment = Platform.environment;
    final roots = [
      environment['ProgramFiles'],
      environment['ProgramFiles(x86)'],
      environment['LocalAppData'],
    ].whereType<String>();

    final candidates = <String>[];
    for (final root in roots) {
      candidates.addAll([
        '$root\\NCH Software\\Crescendo\\crescendo.exe',
        '$root\\NCH Software\\Crescendo\\crescendo64.exe',
        '$root\\Programs\\NCH Software\\Crescendo\\crescendo.exe',
        '$root\\Programs\\NCH Software\\Crescendo\\crescendo64.exe',
      ]);
    }

    return candidates;
  }

  List<String> _musicXmlToLyFallbackPaths() {
    final environment = Platform.environment;
    final roots = [
      environment['ProgramFiles'],
      environment['ProgramFiles(x86)'],
      environment['LocalAppData'],
    ].whereType<String>();

    final candidates = <String>[];
    for (final root in roots) {
      candidates.addAll([
        '$root\\LilyPond\\usr\\bin\\musicxml2ly.exe',
        '$root\\LilyPond\\usr\\bin\\musicxml2ly.py',
        '$root\\LilyPond\\usr\\bin\\musicxml2ly.bat',
        '$root\\LilyPond\\usr\\bin\\musicxml2ly.cmd',
        '$root\\Programs\\LilyPond\\usr\\bin\\musicxml2ly.py',
      ]);
    }

    return candidates;
  }

  static Future<String?> _firstExistingPath(Iterable<String> candidates) async {
    for (final candidate in candidates) {
      if (candidate.isEmpty) {
        continue;
      }

      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    return null;
  }

  static String _stderrText(ProcessResult result) {
    final stderr = result.stderr?.toString().trim() ?? '';
    if (stderr.isNotEmpty) {
      return stderr;
    }

    final stdout = result.stdout?.toString().trim() ?? '';
    return stdout;
  }
}

class ExternalToolException implements Exception {
  const ExternalToolException(this.message);

  final String message;

  @override
  String toString() => message;
}
