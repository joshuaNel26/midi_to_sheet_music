import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'models/drum_models.dart';
import 'services/midi_parser.dart';
import 'services/pdf_export_service.dart';
import 'services/score_builder.dart';
import 'theme.dart';
import 'widgets/score_preview.dart';

const _midiFileTypes = [
  XTypeGroup(label: 'MIDI Files', extensions: ['mid', 'midi']),
];

const _pdfFileTypes = [
  XTypeGroup(label: 'PDF Documents', extensions: ['pdf']),
];

class MidiToDrumApp extends StatelessWidget {
  const MidiToDrumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIDI to Drum Sheet',
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
  final MidiFileParser _midiParser = MidiFileParser();
  final ScoreBuilder _scoreBuilder = ScoreBuilder();
  final ScrollController _sidebarScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();

  ParsedMidiFile? _parsedMidi;
  ScoreDocument? _score;
  List<DrumSourceNote> _sourceNotes = const [];
  Map<int, String> _noteMapping = const {};
  String? _loadedFileName;
  String? _loadedFilePath;
  String? _statusMessage;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isExporting = false;

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
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
      final defaultMapping = {
        for (final note in sourceNotes)
          note.midiNote: DrumLibrary.defaultForMidiNote(note.midiNote).id,
      };

      final score = _scoreBuilder.build(
        midi: parsedMidi,
        title: displayTitleFromFileName(selection.name),
        mappingIds: defaultMapping,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _parsedMidi = parsedMidi;
        _sourceNotes = sourceNotes;
        _noteMapping = defaultMapping;
        _score = score;
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

  Future<void> _exportPdf() async {
    final score = _score;
    if (score == null) {
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final saveLocation = await getSaveLocation(
        acceptedTypeGroups: _pdfFileTypes,
        suggestedName: '${score.title.replaceAll(' ', '_')}.pdf',
        confirmButtonText: 'Export PDF',
      );

      if (saveLocation == null) {
        return;
      }

      final pdfBytes = await PdfExportService.buildPdf(score);
      final targetPath = saveLocation.path.toLowerCase().endsWith('.pdf')
          ? saveLocation.path
          : '${saveLocation.path}.pdf';

      await File(targetPath).writeAsBytes(pdfBytes, flush: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'PDF exported to $targetPath';
      });
      _showMessage('PDF exported to $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'The PDF export failed. ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
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

    final score = _scoreBuilder.build(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: defaultMapping,
    );

    setState(() {
      _noteMapping = defaultMapping;
      _score = score;
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

    final score = _scoreBuilder.build(
      midi: parsedMidi,
      title: displayTitleFromFileName(parsedMidi.sourceName),
      mappingIds: nextMapping,
    );

    setState(() {
      _noteMapping = nextMapping;
      _score = score;
      _statusMessage =
          'Updated MIDI note $midiNote to ${DrumLibrary.pieceForId(selectedPieceId).label}.';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                      'MIDI to Drum Sheet',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Load a MIDI file, review the detected note map, preview the drum notation, and export the finished chart to PDF.',
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
                            _isLoading ? 'Loading…' : 'Open MIDI File',
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
            _PanelCard(child: _buildExportSection(theme)),
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
            'No MIDI file is loaded yet. Once a file is open, this panel shows the time signature, detected tempo, measures, pages, and how the source notes were interpreted.',
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
        _StatRow(label: 'Preview pages', value: '${score.totalPages}'),
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

  Widget _buildExportSection(ThemeData theme) {
    final score = _score;
    final exportEnabled = score != null && !_isExporting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Text(
          'The preview and PDF use the same score painter, so the exported document matches what you see on screen.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: exportEnabled ? _exportPdf : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: AppPalette.accentSoft,
            foregroundColor: AppPalette.ink,
          ),
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(
            _isExporting ? 'Exporting PDF…' : 'Export Preview as PDF',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          score == null
              ? 'Load a MIDI file first to enable export.'
              : 'Current score: ${score.measures.length} measures across ${score.totalPages} page${score.totalPages == 1 ? '' : 's'}.',
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
            'Each MIDI note used by the file will appear here so you can choose which drum sound should be engraved on the staff.',
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

    return _PanelCard(
      padding: const EdgeInsets.all(20),
      child: score == null
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
                          Text('Preview', style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 6),
                          Text(
                            'Each page below is the same layout used during PDF export.',
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
                          label:
                              '${score.totalPages} page${score.totalPages == 1 ? '' : 's'}',
                          icon: Icons.auto_stories_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Scrollbar(
                    controller: _previewScrollController,
                    thumbVisibility: true,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final pageWidth = math.min(
                          900.0,
                          constraints.maxWidth - 20,
                        );
                        return SingleChildScrollView(
                          controller: _previewScrollController,
                          primary: false,
                          padding: const EdgeInsets.only(right: 6),
                          child: Center(
                            child: Column(
                              children: [
                                for (final page in score.pages) ...[
                                  SizedBox(
                                    width: pageWidth,
                                    child: ScorePageWidget(
                                      score: score,
                                      page: page,
                                    ),
                                  ),
                                  if (page != score.pages.last)
                                    const SizedBox(height: 28),
                                ],
                              ],
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
                    'MIDI ${sourceNote.midiNote} • ${midiNoteName(sourceNote.midiNote)}',
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
            DropdownButtonFormField<String>(
              initialValue: selectedPieceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Drum part',
                isDense: true,
              ),
              items: [
                for (final piece in DrumLibrary.assignablePieces)
                  DropdownMenuItem<String>(
                    value: piece.id,
                    child: Text(piece.label),
                  ),
              ],
              onChanged: onChanged,
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
                'Open a drum MIDI file to inspect the detected note numbers, adjust the General MIDI drum map, preview a five-line percussion staff, and export that layout as a PDF.',
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
