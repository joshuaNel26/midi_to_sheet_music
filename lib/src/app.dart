import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'models/drum_models.dart';
import 'services/drum_tab_builder.dart';
import 'services/drum_tab_score_converter.dart';
import 'services/external_tool_config_store.dart';
import 'services/external_tool_service.dart';
import 'services/mapping_config_store.dart';
import 'services/mapping_file_parser.dart';
import 'services/midi_parser.dart';
import 'services/musicxml_export_service.dart';
import 'services/score_builder.dart';
import 'theme.dart';
import 'widgets/drum_tab_preview.dart';

const _midiFileTypes = [
  XTypeGroup(label: 'MIDI Files', extensions: ['mid', 'midi']),
];

const _tabFileTypes = [
  XTypeGroup(label: 'Text Documents', extensions: ['txt']),
];

const _musicXmlFileTypes = [
  XTypeGroup(label: 'MusicXML Documents', extensions: ['musicxml', 'xml']),
];

const _programFileTypes = [
  XTypeGroup(label: 'Programs', extensions: ['exe', 'bat', 'cmd', 'py']),
];

const _mappingFileTypes = [
  XTypeGroup(label: 'Mapping Files', extensions: ['iom']),
];

class MidiToDrumApp extends StatelessWidget {
  const MidiToDrumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIDI to Drum Tab',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MidiToDrumHomePage(),
    );
  }
}

class MidiToDrumHomePage extends StatefulWidget {
  const MidiToDrumHomePage({super.key});

  @override
  State<MidiToDrumHomePage> createState() => _MidiToDrumHomePageState();
}

class _MidiToDrumHomePageState extends State<MidiToDrumHomePage> {
  final DrumTabBuilder _tabBuilder = DrumTabBuilder();
  final DrumTabScoreConverter _tabScoreConverter = DrumTabScoreConverter();
  final ExternalToolConfigStore _externalToolConfigStore =
      ExternalToolConfigStore();
  final ExternalToolService _externalToolService = ExternalToolService();
  final MappingConfigStore _mappingConfigStore = MappingConfigStore();
  final MidiFileParser _midiParser = MidiFileParser();
  final SamplerIoMapParser _ioMapParser = SamplerIoMapParser();
  final ScoreBuilder _scoreBuilder = ScoreBuilder();
  final ScrollController _sidebarScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();

  ParsedMidiFile? _parsedMidi;
  ScoreDocument? _score;
  DrumTabDocument? _tabDocument;
  List<DrumSourceNote> _sourceNotes = const [];
  Map<int, String> _noteMapping = const {};
  String? _loadedFileName;
  String? _loadedFilePath;
  String? _statusMessage;
  String? _errorMessage;
  Map<int, String> _savedMappingConfig = const {};
  ExternalToolConfig _externalToolConfig = const ExternalToolConfig.empty();
  int _startOffsetSlots = 0;
  String _generatedTabText = '';
  bool _isLoading = false;
  bool _isDetectingTools = false;
  bool _isExportingTab = false;
  bool _isExportingMusicXml = false;
  bool _isImportingMapping = false;
  bool _isEditingTab = false;
  bool _isLaunchingCrescendo = false;
  bool _isLaunchingMuseScore = false;
  bool _isRenderingWithLilyPond = false;
  bool _isSavingConfig = false;

  @override
  void initState() {
    super.initState();
    _loadSavedMappingConfig();
    _loadExternalToolConfig();
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedMappingConfig() async {
    try {
      final savedConfig = await _mappingConfigStore.load();
      if (!mounted) {
        return;
      }

      if (_parsedMidi == null || _sourceNotes.isEmpty) {
        setState(() {
          _savedMappingConfig = savedConfig.noteMapping;
          _startOffsetSlots = savedConfig.startOffsetSlots;
          if (savedConfig.noteMapping.isNotEmpty) {
            _statusMessage =
                'Loaded saved mapping config with ${savedConfig.noteMapping.length} note assignments.';
          }
        });
        return;
      }

      final nextMapping = _buildInitialMapping(
        _sourceNotes,
        savedConfig.noteMapping,
      );
      final startOffsetSlots = _normalizedStartOffsetForMidi(
        _parsedMidi!,
        savedConfig.startOffsetSlots,
      );
      final (score, tabDocument) = _buildOutputs(
        midi: _parsedMidi!,
        title: displayTitleFromFileName(_parsedMidi!.sourceName),
        mappingIds: nextMapping,
        startOffsetSlots: startOffsetSlots,
      );
      _generatedTabText = tabDocument.toPlainText();

      setState(() {
        _savedMappingConfig = savedConfig.noteMapping;
        _startOffsetSlots = startOffsetSlots;
        _noteMapping = nextMapping;
        _score = score;
        _tabDocument = tabDocument;
        _isEditingTab = false;
        if (savedConfig.noteMapping.isNotEmpty) {
          _statusMessage =
              'Loaded saved mapping config with ${savedConfig.noteMapping.length} note assignments.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The saved mapping config could not be loaded. ${error.toString()}';
      });
    }
  }

  Future<void> _loadExternalToolConfig() async {
    try {
      final savedConfig = await _externalToolConfigStore.load();
      final detectedConfig = await _externalToolService.detectInstalledTools(
        preferred: savedConfig,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _externalToolConfig = detectedConfig;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The external tool configuration could not be loaded. ${error.toString()}';
      });
    }
  }

  Future<void> _selectMidiFile() async {
    final selection = await openFile(
      acceptedTypeGroups: _midiFileTypes,
      confirmButtonText: 'Load MIDI',
    );

    if (selection == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final fileBytes = await selection.readAsBytes();
      final parsedMidi = _midiParser.parse(
        fileBytes,
        sourceName: selection.name,
      );
      final sourceNotes = extractSourceNotes(parsedMidi);
      final defaultMapping = _buildInitialMapping(
        sourceNotes,
        _savedMappingConfig,
      );
      final startOffsetSlots = _normalizedStartOffsetForMidi(
        parsedMidi,
        _startOffsetSlots,
      );

      final (score, tabDocument) = _buildOutputs(
        midi: parsedMidi,
        title: displayTitleFromFileName(selection.name),
        mappingIds: defaultMapping,
        startOffsetSlots: startOffsetSlots,
      );
      _generatedTabText = tabDocument.toPlainText();

      if (!mounted) {
        return;
      }

      setState(() {
        _parsedMidi = parsedMidi;
        _sourceNotes = sourceNotes;
        _noteMapping = defaultMapping;
        _startOffsetSlots = startOffsetSlots;
        _score = score;
        _tabDocument = tabDocument;
        _isEditingTab = false;
        _loadedFileName = selection.name;
        _loadedFilePath = selection.path;
        _statusMessage = parsedMidi.usedPercussionChannelOnly
            ? 'Loaded ${selection.name} from the MIDI percussion channel.'
            : 'Loaded ${selection.name}. No dedicated percussion channel was found, so all note events are available for mapping.';
      });
    } on MidiParseException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'The MIDI file could not be loaded. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportTab() async {
    final tabDocument = _tabDocument;
    if (tabDocument == null) {
      return;
    }

    setState(() {
      _isExportingTab = true;
      _errorMessage = null;
    });

    try {
      final saveLocation = await getSaveLocation(
        acceptedTypeGroups: _tabFileTypes,
        suggestedName: '${tabDocument.title.replaceAll(' ', '_')}.txt',
        confirmButtonText: 'Export Tab',
      );

      if (saveLocation == null) {
        return;
      }

      final targetPath = saveLocation.path.toLowerCase().endsWith('.txt')
          ? saveLocation.path
          : '${saveLocation.path}.txt';

      await File(
        targetPath,
      ).writeAsString(tabDocument.toPlainText(), flush: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Drum tab exported to $targetPath';
      });
      _showMessage('Drum tab exported to $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'The tab export failed. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExportingTab = false;
        });
      }
    }
  }

  Future<void> _exportMusicXml() async {
    final score = _score;
    final tabDocument = _tabDocument;
    if (score == null || tabDocument == null) {
      return;
    }

    setState(() {
      _isExportingMusicXml = true;
      _errorMessage = null;
    });

    try {
      final saveLocation = await getSaveLocation(
        acceptedTypeGroups: _musicXmlFileTypes,
        suggestedName: '${tabDocument.title.replaceAll(' ', '_')}.musicxml',
        confirmButtonText: 'Export MusicXML',
      );

      if (saveLocation == null) {
        return;
      }

      final lowerPath = saveLocation.path.toLowerCase();
      final targetPath =
          lowerPath.endsWith('.musicxml') || lowerPath.endsWith('.xml')
          ? saveLocation.path
          : '${saveLocation.path}.musicxml';
      final document = MusicXmlExportService.build(score);
      await File(targetPath).writeAsString(document, flush: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'MusicXML exported to $targetPath';
      });
      _showMessage('MusicXML exported to $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'The MusicXML export failed. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExportingMusicXml = false;
        });
      }
    }
  }

  Future<void> _detectExternalTools({bool announce = true}) async {
    setState(() {
      _isDetectingTools = true;
      _errorMessage = null;
    });

    try {
      final detectedConfig = await _externalToolService.detectInstalledTools(
        preferred: _externalToolConfig,
      );
      await _externalToolConfigStore.save(detectedConfig);
      if (!mounted) {
        return;
      }

      final connectedTools = <String>[
        if (detectedConfig.hasMuseScore) 'MuseScore Studio',
        if (detectedConfig.hasCrescendo) 'Crescendo',
        if (detectedConfig.hasLilyPond) 'LilyPond',
        if (detectedConfig.hasMusicXmlToLy) 'musicxml2ly',
      ];
      setState(() {
        _externalToolConfig = detectedConfig;
        if (announce) {
          _statusMessage = connectedTools.isEmpty
              ? 'No external tools were detected automatically. You can set the executable paths manually below.'
              : 'Detected: ${connectedTools.join(', ')}.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'The external tool scan failed. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDetectingTools = false;
        });
      }
    }
  }

  Future<void> _pickMuseScorePath() async {
    final selection = await openFile(
      acceptedTypeGroups: _programFileTypes,
      confirmButtonText: 'Select MuseScore',
    );
    if (selection == null) {
      return;
    }

    final nextConfig = _externalToolConfig.copyWith(
      museScorePath: selection.path,
    );
    await _externalToolConfigStore.save(nextConfig);
    if (!mounted) {
      return;
    }

    setState(() {
      _externalToolConfig = nextConfig;
      _statusMessage = 'MuseScore Studio path updated.';
    });
  }

  Future<void> _pickCrescendoPath() async {
    final selection = await openFile(
      acceptedTypeGroups: _programFileTypes,
      confirmButtonText: 'Select Crescendo',
    );
    if (selection == null) {
      return;
    }

    final nextConfig = _externalToolConfig.copyWith(
      crescendoPath: selection.path,
    );
    await _externalToolConfigStore.save(nextConfig);
    if (!mounted) {
      return;
    }

    setState(() {
      _externalToolConfig = nextConfig;
      _statusMessage = 'Crescendo path updated.';
    });
  }

  Future<void> _pickLilyPondPath() async {
    final selection = await openFile(
      acceptedTypeGroups: _programFileTypes,
      confirmButtonText: 'Select LilyPond',
    );
    if (selection == null) {
      return;
    }

    final inferredMusicXmlToLyPath =
        await ExternalToolService.inferMusicXmlToLyPath(selection.path);
    final nextConfig = _externalToolConfig.copyWith(
      lilyPondPath: selection.path,
      musicXmlToLyPath:
          _externalToolConfig.musicXmlToLyPath ?? inferredMusicXmlToLyPath,
    );
    await _externalToolConfigStore.save(nextConfig);
    if (!mounted) {
      return;
    }

    setState(() {
      _externalToolConfig = nextConfig;
      _statusMessage = inferredMusicXmlToLyPath == null
          ? 'LilyPond path updated.'
          : 'LilyPond path updated and musicxml2ly was inferred automatically.';
    });
  }

  Future<void> _pickMusicXmlToLyPath() async {
    final selection = await openFile(
      acceptedTypeGroups: _programFileTypes,
      confirmButtonText: 'Select musicxml2ly',
    );
    if (selection == null) {
      return;
    }

    final nextConfig = _externalToolConfig.copyWith(
      musicXmlToLyPath: selection.path,
    );
    await _externalToolConfigStore.save(nextConfig);
    if (!mounted) {
      return;
    }

    setState(() {
      _externalToolConfig = nextConfig;
      _statusMessage = 'musicxml2ly path updated.';
    });
  }

  Future<void> _openInMuseScore() async {
    final score = _score;
    final museScorePath = _externalToolConfig.museScorePath;
    if (score == null || museScorePath == null) {
      return;
    }

    setState(() {
      _isLaunchingMuseScore = true;
      _errorMessage = null;
    });

    try {
      final musicXmlPath = await _externalToolService.launchMuseScore(
        score: score,
        museScorePath: museScorePath,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Opened the current score in MuseScore Studio via $musicXmlPath';
      });
      _showMessage('MuseScore Studio opened the current MusicXML file.');
    } on ExternalToolException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'MuseScore Studio could not be launched. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLaunchingMuseScore = false;
        });
      }
    }
  }

  Future<void> _openInCrescendo() async {
    final score = _score;
    final crescendoPath = _externalToolConfig.crescendoPath;
    if (score == null || crescendoPath == null) {
      return;
    }

    setState(() {
      _isLaunchingCrescendo = true;
      _errorMessage = null;
    });

    try {
      final musicXmlPath = await _externalToolService.launchCrescendo(
        score: score,
        crescendoPath: crescendoPath,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Opened the current score in Crescendo via $musicXmlPath';
      });
      _showMessage('Crescendo opened the current MusicXML file.');
    } on ExternalToolException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Crescendo could not be launched. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLaunchingCrescendo = false;
        });
      }
    }
  }

  Future<void> _renderWithLilyPond() async {
    final score = _score;
    final lilyPondPath = _externalToolConfig.lilyPondPath;
    final musicXmlToLyPath = _externalToolConfig.musicXmlToLyPath;
    if (score == null || lilyPondPath == null || musicXmlToLyPath == null) {
      return;
    }

    setState(() {
      _isRenderingWithLilyPond = true;
      _errorMessage = null;
    });

    try {
      final pdfPath = await _externalToolService.renderWithLilyPond(
        score: score,
        lilyPondPath: lilyPondPath,
        musicXmlToLyPath: musicXmlToLyPath,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'LilyPond rendered a PDF to $pdfPath';
      });
      _showMessage('LilyPond rendered the current score.');
    } on ExternalToolException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'LilyPond could not render the score. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRenderingWithLilyPond = false;
        });
      }
    }
  }

  Future<void> _importMappingFile() async {
    final parsedMidi = _parsedMidi;
    if (parsedMidi == null) {
      _showMessage('Load a MIDI file before importing a mapping file.');
      return;
    }

    final selection = await openFile(
      acceptedTypeGroups: _mappingFileTypes,
      confirmButtonText: 'Import Mapping',
    );

    if (selection == null) {
      return;
    }

    setState(() {
      _isImportingMapping = true;
      _errorMessage = null;
    });

    try {
      final bytes = await selection.readAsBytes();
      final importedMap = _ioMapParser.parse(bytes, sourceName: selection.name);

      final nextMapping = Map<int, String>.from(_noteMapping);
      var appliedCount = 0;
      var multiTargetCount = 0;

      for (final note in _sourceNotes) {
        final targets = importedMap.noteTargets[note.midiNote];
        if (targets == null || targets.isEmpty) {
          continue;
        }

        if (targets.length > 1) {
          multiTargetCount += 1;
        }

        nextMapping[note.midiNote] = DrumLibrary.defaultForMidiNote(
          targets.first,
        ).id;
        appliedCount += 1;
      }

      final (score, tabDocument) = _buildOutputs(
        midi: parsedMidi,
        title: displayTitleFromFileName(parsedMidi.sourceName),
        mappingIds: nextMapping,
        startOffsetSlots: _startOffsetSlots,
      );
      _generatedTabText = tabDocument.toPlainText();

      if (!mounted) {
        return;
      }

      setState(() {
        _noteMapping = nextMapping;
        _score = score;
        _tabDocument = tabDocument;
        _isEditingTab = false;
        _statusMessage =
            'Imported ${importedMap.mapName} and applied $appliedCount note mapping${appliedCount == 1 ? '' : 's'}.'
            '${multiTargetCount > 0 ? ' $multiTargetCount source note${multiTargetCount == 1 ? ' has' : 's have'} multiple targets; the first target was used.' : ''}';
      });
    } on MappingFileParseException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The mapping file could not be imported. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImportingMapping = false;
        });
      }
    }
  }

  Future<void> _saveCurrentMappingConfig() async {
    if (_sourceNotes.isEmpty) {
      _showMessage('Load a MIDI file and set up a mapping first.');
      return;
    }

    final mappingToSave = {
      for (final note in _sourceNotes)
        note.midiNote:
            _noteMapping[note.midiNote] ??
            DrumLibrary.defaultForMidiNote(note.midiNote).id,
    };

    setState(() {
      _isSavingConfig = true;
      _errorMessage = null;
    });

    try {
      await _mappingConfigStore.save(
        mapping: mappingToSave,
        startOffsetSlots: _startOffsetSlots,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _savedMappingConfig = mappingToSave;
        _statusMessage =
            'Saved mapping config with ${mappingToSave.length} note assignments.';
      });
      _showMessage('Mapping config saved.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The mapping config could not be saved. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingConfig = false;
        });
      }
    }
  }

  void _resetMapping() {
    final parsedMidi = _parsedMidi;
    if (parsedMidi == null) {
      return;
    }

    final defaultMapping = {
      for (final note in _sourceNotes)
        note.midiNote: DrumLibrary.defaultForMidiNote(note.midiNote).id,
    };

    final (score, tabDocument) = _buildOutputs(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: defaultMapping,
      startOffsetSlots: _startOffsetSlots,
    );
    _generatedTabText = tabDocument.toPlainText();

    setState(() {
      _noteMapping = defaultMapping;
      _score = score;
      _tabDocument = tabDocument;
      _isEditingTab = false;
      _statusMessage = 'Mapping reset to the General MIDI drum defaults.';
    });
  }

  void _updateMapping(int midiNote, String? pieceId) {
    final parsedMidi = _parsedMidi;
    final selectedPieceId = pieceId;
    if (parsedMidi == null || selectedPieceId == null) {
      return;
    }

    final nextMapping = Map<int, String>.from(_noteMapping)
      ..[midiNote] = selectedPieceId;

    final (score, tabDocument) = _buildOutputs(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: nextMapping,
      startOffsetSlots: _startOffsetSlots,
    );
    _generatedTabText = tabDocument.toPlainText();

    setState(() {
      _noteMapping = nextMapping;
      _score = score;
      _tabDocument = tabDocument;
      _isEditingTab = false;
      _statusMessage =
          'Updated MIDI note $midiNote to ${DrumLibrary.pieceForId(selectedPieceId).label}.';
    });
  }

  void _updateStartOffset(int? startOffsetSlots) {
    final parsedMidi = _parsedMidi;
    if (parsedMidi == null || startOffsetSlots == null) {
      return;
    }

    final (score, tabDocument) = _buildOutputs(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: _noteMapping,
      startOffsetSlots: startOffsetSlots,
    );
    _generatedTabText = tabDocument.toPlainText();

    final slotsPerBeat = slotsPerBeatForTimeSignature(parsedMidi.timeSignature);
    setState(() {
      _startOffsetSlots = startOffsetSlots;
      _score = score;
      _tabDocument = tabDocument;
      _isEditingTab = false;
      _statusMessage =
          'Aligned the first hit to ${slotLabelForIndex(startOffsetSlots, slotsPerBeat)} of measure 1.';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<int, String> _buildInitialMapping(
    List<DrumSourceNote> sourceNotes,
    Map<int, String> savedConfig,
  ) {
    return {
      for (final note in sourceNotes)
        note.midiNote:
            savedConfig[note.midiNote] ??
            DrumLibrary.defaultForMidiNote(note.midiNote).id,
    };
  }

  int _normalizedStartOffsetForMidi(ParsedMidiFile midi, int startOffsetSlots) {
    final maxStartOffset =
        slotsPerMeasureForTimeSignature(midi.timeSignature) - 1;
    return math.max(0, math.min(startOffsetSlots, maxStartOffset));
  }

  (ScoreDocument, DrumTabDocument) _buildOutputs({
    required ParsedMidiFile midi,
    required String title,
    required Map<int, String> mappingIds,
    required int startOffsetSlots,
  }) {
    final score = _scoreBuilder.build(
      midi: midi,
      title: title,
      mappingIds: mappingIds,
      startOffsetSlots: startOffsetSlots,
    );
    final tabDocument = _tabBuilder.build(score);
    return (score, tabDocument);
  }

  bool get _hasManualTabEdits =>
      _tabDocument != null &&
      _generatedTabText.isNotEmpty &&
      _tabDocument!.toPlainText() != _generatedTabText;

  void _toggleTabEditing() {
    if (_tabDocument == null) {
      return;
    }

    setState(() {
      _isEditingTab = !_isEditingTab;
      _statusMessage = _isEditingTab
          ? 'Cell editing is enabled for the tab preview.'
          : 'Returned to the tab preview.';
    });
  }

  void _resetTabEdits() {
    final parsedMidi = _parsedMidi;
    if (parsedMidi == null) {
      return;
    }

    final (score, tabDocument) = _buildOutputs(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: _noteMapping,
      startOffsetSlots: _startOffsetSlots,
    );
    _generatedTabText = tabDocument.toPlainText();

    setState(() {
      _score = score;
      _tabDocument = tabDocument;
      _isEditingTab = false;
      _statusMessage = 'Tab text reset to the generated output.';
    });
  }

  void _toggleTabCell(
    int blockIndex,
    String pieceId,
    int measureOffset,
    int slotIndex,
  ) {
    final tabDocument = _tabDocument;
    if (tabDocument == null ||
        blockIndex < 0 ||
        blockIndex >= tabDocument.blocks.length) {
      return;
    }

    setState(() {
      tabDocument.blocks[blockIndex].toggleCell(
        pieceId: pieceId,
        measureOffset: measureOffset,
        slotIndex: slotIndex,
      );
      _score = _tabScoreConverter.build(tabDocument);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111723), Color(0xFF172236), Color(0xFF0F1724)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sidebar = _buildSidebar(theme);
              final preview = _buildPreviewPane(theme);
              final isWide = constraints.maxWidth >= 1220;

              return Padding(
                padding: const EdgeInsets.all(24),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 360, child: sidebar),
                          const SizedBox(width: 24),
                          Expanded(child: preview),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(height: 360, child: sidebar),
                          const SizedBox(height: 18),
                          Expanded(child: preview),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    return Scrollbar(
      controller: _sidebarScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _sidebarScrollController,
        primary: false,
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          children: [
            _PanelCard(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF22324A), Color(0xFF182334)],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MIDI to Drum Tab',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Load a MIDI file, review the detected note map, edit the generated drum tab, and export the tab or MusicXML.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppPalette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _selectMidiFile,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.accent,
                            foregroundColor: AppPalette.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.library_music_outlined),
                          label: Text(
                            _isLoading ? 'Loading...' : 'Open MIDI File',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _parsedMidi == null ? null : _resetMapping,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textPrimary,
                            side: const BorderSide(color: AppPalette.divider),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt_outlined),
                          label: const Text('Reset to GM'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _parsedMidi == null || _isSavingConfig
                              ? null
                              : _saveCurrentMappingConfig,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textPrimary,
                            side: const BorderSide(color: AppPalette.divider),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: _isSavingConfig
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _isSavingConfig ? 'Saving...' : 'Save Config',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _parsedMidi == null || _isImportingMapping
                              ? null
                              : _importMappingFile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textPrimary,
                            side: const BorderSide(color: AppPalette.divider),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: _isImportingMapping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _isImportingMapping
                                ? 'Importing Map...'
                                : 'Import Mapping',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_statusMessage != null)
              _MessageBanner(
                message: _statusMessage!,
                tone: BannerTone.success,
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _MessageBanner(message: _errorMessage!, tone: BannerTone.danger),
            ],
            if (_statusMessage != null || _errorMessage != null)
              const SizedBox(height: 18),
            _PanelCard(child: _buildStats(theme)),
            const SizedBox(height: 18),
            _PanelCard(child: _buildTimingSection(theme)),
            const SizedBox(height: 18),
            _PanelCard(child: _buildExportSection(theme)),
            const SizedBox(height: 18),
            _PanelCard(child: _buildExternalToolsSection(theme)),
            const SizedBox(height: 18),
            _PanelCard(child: _buildMappingSection(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(ThemeData theme) {
    final parsedMidi = _parsedMidi;
    final score = _score;

    if (parsedMidi == null || score == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Text(
            'No MIDI file is loaded yet. Once a file is open, this panel shows the time signature, detected tempo, measures, tab blocks, and how the source notes were interpreted.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppPalette.textMuted,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        _StatRow(
          label: 'File',
          value: _loadedFileName ?? parsedMidi.sourceName,
        ),
        _StatRow(label: 'Path', value: _loadedFilePath ?? 'Unknown'),
        _StatRow(label: 'Format', value: 'MIDI ${parsedMidi.format}'),
        _StatRow(label: 'Tracks', value: '${parsedMidi.trackCount}'),
        _StatRow(label: 'Tempo', value: '${parsedMidi.tempoBpm} BPM'),
        _StatRow(label: 'Meter', value: parsedMidi.timeSignature.label),
        _StatRow(label: 'Measures', value: '${score.measures.length}'),
        _StatRow(
          label: 'Starts on',
          value: slotLabelForIndex(
            _startOffsetSlots,
            slotsPerBeatForTimeSignature(parsedMidi.timeSignature),
          ),
        ),
        _StatRow(
          label: 'Tab blocks',
          value: '${_tabDocument?.blockCount ?? 0}',
        ),
        _StatRow(label: 'Mapped hits', value: '${score.totalHits}'),
        const SizedBox(height: 10),
        Text(
          parsedMidi.usedPercussionChannelOnly
              ? 'Preview is using channel 10 percussion events only.'
              : 'No channel 10 drum track was found, so all note events remain available for manual mapping.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildTimingSection(ThemeData theme) {
    final parsedMidi = _parsedMidi;
    final score = _score;
    if (parsedMidi == null || score == null || score.measures.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timing', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Text(
            'The earliest rendered hit is aligned to beat 1 by default. Load a MIDI file to adjust where the pattern begins inside the first measure.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppPalette.textMuted,
            ),
          ),
        ],
      );
    }

    final slotsPerMeasure = score.measures.first.slotsPerMeasure;
    final slotsPerBeat = score.measures.first.slotsPerBeat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timing', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Text(
          'By default the first rendered hit is moved to 1 of measure 1. Change this if the groove should start later in the bar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'First hit starts on',
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: ValueKey('start-offset-$_startOffsetSlots-$slotsPerMeasure'),
              value: math.max(
                0,
                math.min(_startOffsetSlots, slotsPerMeasure - 1),
              ),
              isExpanded: true,
              items: [
                for (
                  var slotIndex = 0;
                  slotIndex < slotsPerMeasure;
                  slotIndex++
                )
                  DropdownMenuItem<int>(
                    value: slotIndex,
                    child: Text(slotLabelForIndex(slotIndex, slotsPerBeat)),
                  ),
              ],
              onChanged: _updateStartOffset,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExportSection(ThemeData theme) {
    final score = _score;
    final tabDocument = _tabDocument;
    final canExportTab = tabDocument != null && !_isExportingTab;
    final canExportMusicXml = score != null && !_isExportingMusicXml;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Text(
          'The tab text and MusicXML both come from the same edited tab. MusicXML is the best handoff if you want polished engraving in MuseScore, Crescendo, LilyPond, or another notation tool.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: canExportTab ? _exportTab : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: AppPalette.accentSoft,
            foregroundColor: AppPalette.ink,
          ),
          icon: _isExportingTab
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.text_snippet_outlined),
          label: Text(
            _isExportingTab ? 'Exporting Tab...' : 'Export Drum Tab as TXT',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canExportMusicXml ? _exportMusicXml : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: AppPalette.accent,
            foregroundColor: AppPalette.ink,
          ),
          icon: _isExportingMusicXml
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.library_books_outlined),
          label: Text(
            _isExportingMusicXml
                ? 'Exporting MusicXML...'
                : 'Export Sheet Music as MusicXML',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tabDocument == null
              ? 'Load a MIDI file first to enable export.'
              : 'Current tab: ${score?.measures.length ?? 0} measures across ${tabDocument.blockCount} block${tabDocument.blockCount == 1 ? '' : 's'}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _externalToolConfig.hasMuseScore || _externalToolConfig.hasCrescendo
              ? 'A notation app is connected, so you can open the exported MusicXML directly from the External Tools section.'
              : 'No notation app is connected yet, so MusicXML is exported as a file for now. You can set the executable path below when you are ready.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildExternalToolsSection(ThemeData theme) {
    final scoreLoaded = _score != null;
    final toolConfig = _externalToolConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('External Tools', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Text(
          'Connect MuseScore Studio, Crescendo, or LilyPond if you want to hand off the edited tab to external engraving tools directly from the app.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        _ExternalToolRow(
          label: 'MuseScore Studio',
          path: toolConfig.museScorePath,
          unavailableLabel: 'Not detected yet',
        ),
        const SizedBox(height: 10),
        _ExternalToolRow(
          label: 'Crescendo',
          path: toolConfig.crescendoPath,
          unavailableLabel: 'Not detected yet',
        ),
        const SizedBox(height: 10),
        _ExternalToolRow(
          label: 'LilyPond',
          path: toolConfig.lilyPondPath,
          unavailableLabel: 'Not detected yet',
        ),
        const SizedBox(height: 10),
        _ExternalToolRow(
          label: 'musicxml2ly',
          path: toolConfig.musicXmlToLyPath,
          unavailableLabel: 'Needed for LilyPond conversion',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _isDetectingTools
                  ? null
                  : () => _detectExternalTools(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.textPrimary,
                side: const BorderSide(color: AppPalette.divider),
              ),
              icon: _isDetectingTools
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search_outlined),
              label: Text(_isDetectingTools ? 'Detecting...' : 'Auto-Detect'),
            ),
            OutlinedButton.icon(
              onPressed: _pickMuseScorePath,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.textPrimary,
                side: const BorderSide(color: AppPalette.divider),
              ),
              icon: const Icon(Icons.piano_outlined),
              label: const Text('Locate MuseScore'),
            ),
            OutlinedButton.icon(
              onPressed: _pickCrescendoPath,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.textPrimary,
                side: const BorderSide(color: AppPalette.divider),
              ),
              icon: const Icon(Icons.queue_music_outlined),
              label: const Text('Locate Crescendo'),
            ),
            OutlinedButton.icon(
              onPressed: _pickLilyPondPath,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.textPrimary,
                side: const BorderSide(color: AppPalette.divider),
              ),
              icon: const Icon(Icons.music_note_outlined),
              label: const Text('Locate LilyPond'),
            ),
            OutlinedButton.icon(
              onPressed: _pickMusicXmlToLyPath,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.textPrimary,
                side: const BorderSide(color: AppPalette.divider),
              ),
              icon: const Icon(Icons.code_outlined),
              label: const Text('Locate musicxml2ly'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed:
                  scoreLoaded &&
                      toolConfig.hasCrescendo &&
                      !_isLaunchingCrescendo
                  ? _openInCrescendo
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.accentSoft,
                foregroundColor: AppPalette.ink,
              ),
              icon: _isLaunchingCrescendo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new_outlined),
              label: Text(
                _isLaunchingCrescendo
                    ? 'Opening Crescendo...'
                    : 'Open in Crescendo',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  scoreLoaded &&
                      toolConfig.hasMuseScore &&
                      !_isLaunchingMuseScore
                  ? _openInMuseScore
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.accentSoft,
                foregroundColor: AppPalette.ink,
              ),
              icon: _isLaunchingMuseScore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.launch_outlined),
              label: Text(
                _isLaunchingMuseScore
                    ? 'Opening MuseScore...'
                    : 'Open in MuseScore',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  scoreLoaded &&
                      toolConfig.hasLilyPondPipeline &&
                      !_isRenderingWithLilyPond
                  ? _renderWithLilyPond
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.accent,
                foregroundColor: AppPalette.ink,
              ),
              icon: _isRenderingWithLilyPond
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_motion_outlined),
              label: Text(
                _isRenderingWithLilyPond
                    ? 'Rendering with LilyPond...'
                    : 'Render with LilyPond',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          scoreLoaded
              ? 'These actions use the current edited tab state, the same way MusicXML export does.'
              : 'Load a MIDI file first, then these hooks can use the current edited tab state.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildMappingSection(ThemeData theme) {
    if (_sourceNotes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Note Mapping', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Text(
            'Each MIDI note used by the file will appear here so you can choose which drum sound should be written into the tab.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppPalette.textMuted,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Note Mapping', style: theme.textTheme.titleLarge),
            ),
            Text(
              '${_sourceNotes.length} notes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final note in _sourceNotes) ...[
          _MappingRow(
            sourceNote: note,
            selectedPieceId:
                _noteMapping[note.midiNote] ?? DrumLibrary.auxiliary.id,
            onChanged: (pieceId) => _updateMapping(note.midiNote, pieceId),
          ),
          if (note != _sourceNotes.last) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPreviewPane(ThemeData theme) {
    final score = _score;
    final tabDocument = _tabDocument;
    const previewTitle = 'Drum Tab';
    const previewDescription =
        'This preview uses the same drum-tab layout that is written into the exported text file.';
    final previewCountLabel =
        '${tabDocument?.blockCount ?? 0} block${tabDocument?.blockCount == 1 ? '' : 's'}';

    return _PanelCard(
      padding: const EdgeInsets.all(20),
      child: score == null || tabDocument == null
          ? _PreviewPlaceholder(theme: theme)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            previewTitle,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            previewDescription,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppPalette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InfoChip(
                          label: score.timeSignature.label,
                          icon: Icons.music_note_outlined,
                        ),
                        _InfoChip(
                          label: '${score.tempoBpm} BPM',
                          icon: Icons.speed_outlined,
                        ),
                        _InfoChip(
                          label: previewCountLabel,
                          icon: Icons.view_week_outlined,
                        ),
                        OutlinedButton.icon(
                          onPressed: _toggleTabEditing,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textPrimary,
                            side: const BorderSide(color: AppPalette.divider),
                          ),
                          icon: Icon(
                            _isEditingTab
                                ? Icons.visibility_outlined
                                : Icons.grid_view_outlined,
                          ),
                          label: Text(
                            _isEditingTab ? 'Preview Tab' : 'Edit Cells',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _hasManualTabEdits ? _resetTabEdits : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textPrimary,
                            side: const BorderSide(color: AppPalette.divider),
                          ),
                          icon: const Icon(Icons.undo_outlined),
                          label: const Text('Reset Edits'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _isEditingTab
                      ? Scrollbar(
                          controller: _previewScrollController,
                          thumbVisibility: true,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final previewWidth = math.min(
                                1140.0,
                                constraints.maxWidth - 20,
                              );
                              return SingleChildScrollView(
                                controller: _previewScrollController,
                                primary: false,
                                padding: const EdgeInsets.only(right: 6),
                                child: Center(
                                  child: SizedBox(
                                    width: previewWidth,
                                    child: EditableDrumTabEditor(
                                      document: tabDocument,
                                      onToggleCell: _toggleTabCell,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : Scrollbar(
                          controller: _previewScrollController,
                          thumbVisibility: true,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final previewWidth = math.min(
                                980.0,
                                constraints.maxWidth - 20,
                              );
                              return SingleChildScrollView(
                                controller: _previewScrollController,
                                primary: false,
                                padding: const EdgeInsets.only(right: 6),
                                child: Center(
                                  child: SizedBox(
                                    width: previewWidth,
                                    child: DrumTabPreview(
                                      document: tabDocument,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppPalette.divider.withValues(alpha: 0.8)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ExternalToolRow extends StatelessWidget {
  const _ExternalToolRow({
    required this.label,
    required this.path,
    required this.unavailableLabel,
  });

  final String label;
  final String? path;
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = path != null && path!.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider.withValues(alpha: 0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isAvailable
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
              color: isAvailable ? AppPalette.success : AppPalette.textMuted,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path ?? unavailableLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isAvailable
                          ? AppPalette.textMuted
                          : AppPalette.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BannerTone { success, danger }

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.tone});

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = tone == BannerTone.success
        ? AppPalette.success
        : AppPalette.danger;
    final icon = tone == BannerTone.success
        ? Icons.check_circle_outline
        : Icons.error_outline;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: backgroundColor.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: backgroundColor),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.sourceNote,
    required this.selectedPieceId,
    required this.onChanged,
  });

  final DrumSourceNote sourceNote;
  final String selectedPieceId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedPiece = DrumLibrary.pieceForId(selectedPieceId);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider.withValues(alpha: 0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MIDI ${sourceNote.midiNote} - ${midiNoteName(sourceNote.midiNote)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${sourceNote.hitCount} hit${sourceNote.hitCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Assigned to ${selectedPiece.label}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Drum part',
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('${sourceNote.midiNote}-$selectedPieceId'),
                  value: selectedPieceId,
                  isExpanded: true,
                  items: [
                    for (final piece in DrumLibrary.assignablePieces)
                      DropdownMenuItem<String>(
                        value: piece.id,
                        child: Text(piece.label),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.panelRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppPalette.accentSoft),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        primary: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppPalette.panelRaised,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.queue_music_outlined,
                  size: 42,
                  color: AppPalette.accentSoft,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Ready for a MIDI file',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Open a drum MIDI file to inspect the detected note numbers, adjust the General MIDI drum map, edit the generated tab, and export the tab or MusicXML.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
