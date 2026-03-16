import '../models/drum_models.dart';

class MusicXmlExportService {
  static String build(ScoreDocument score) {
    final instruments = <_InstrumentSpec>[
      for (var index = 0; index < score.usedPieces.length; index++)
        _InstrumentSpec(
          id: 'P1-I${index + 1}',
          piece: score.usedPieces[index],
          midiNote: DrumLibrary.defaultMidiNoteForPieceId(
            score.usedPieces[index].id,
          ),
        ),
    ];
    final instrumentByPieceId = {
      for (final instrument in instruments) instrument.piece.id: instrument,
    };
    final xml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<score-partwise version="4.0">')
      ..writeln('  <work>')
      ..writeln('    <work-title>${_escape(score.title)}</work-title>')
      ..writeln('  </work>')
      ..writeln('  <identification>')
      ..writeln('    <encoding>')
      ..writeln('      <software>midi_to_drum</software>')
      ..writeln('      <encoding-date>2026-03-16</encoding-date>')
      ..writeln('    </encoding>')
      ..writeln('  </identification>')
      ..writeln('  <part-list>')
      ..writeln('    <score-part id="P1">')
      ..writeln('      <part-name>Drumset</part-name>')
      ..writeln('      <part-abbreviation>Drs.</part-abbreviation>');

    for (final instrument in instruments) {
      xml
        ..writeln('      <score-instrument id="${instrument.id}">')
        ..writeln(
          '        <instrument-name>${_escape(instrument.piece.label)}</instrument-name>',
        )
        ..writeln('      </score-instrument>')
        ..writeln('      <midi-instrument id="${instrument.id}">')
        ..writeln('        <midi-channel>10</midi-channel>')
        ..writeln(
          '        <midi-unpitched>${instrument.midiNote + 1}</midi-unpitched>',
        )
        ..writeln('      </midi-instrument>');
    }

    xml
      ..writeln('    </score-part>')
      ..writeln('  </part-list>')
      ..writeln('  <part id="P1">');

    for (final measure in score.measures) {
      xml.writeln('    <measure number="${measure.index + 1}">');
      if (measure.index == 0) {
        xml
          ..writeln('      <attributes>')
          ..writeln('        <divisions>$scoreSlotsPerQuarter</divisions>')
          ..writeln('        <time>')
          ..writeln('          <beats>${score.timeSignature.numerator}</beats>')
          ..writeln(
            '          <beat-type>${score.timeSignature.denominator}</beat-type>',
          )
          ..writeln('        </time>')
          ..writeln('        <staves>1</staves>')
          ..writeln('        <staff-details>')
          ..writeln('          <staff-lines>5</staff-lines>')
          ..writeln('        </staff-details>')
          ..writeln('        <clef>')
          ..writeln('          <sign>percussion</sign>')
          ..writeln('          <line>2</line>')
          ..writeln('        </clef>')
          ..writeln('      </attributes>')
          ..writeln('      <direction placement="above">')
          ..writeln('        <direction-type>')
          ..writeln('          <metronome>')
          ..writeln('            <beat-unit>quarter</beat-unit>')
          ..writeln('            <per-minute>${score.tempoBpm}</per-minute>')
          ..writeln('          </metronome>')
          ..writeln('        </direction-type>')
          ..writeln('        <sound tempo="${score.tempoBpm}"/>')
          ..writeln('      </direction>');
      }

      if (measure.slots.isEmpty) {
        xml
          ..writeln('      <note>')
          ..writeln('        <rest measure="yes"/>')
          ..writeln('        <duration>${measure.slotsPerMeasure}</duration>')
          ..writeln('        <voice>1</voice>')
          ..writeln('      </note>');
      } else {
        final upperVoiceSlots = <int, List<ScoreHit>>{};
        final lowerVoiceSlots = <int, List<ScoreHit>>{};

        for (final slot in measure.slots) {
          for (final hit in slot.hits) {
            final target = _isUpperVoice(hit.piece)
                ? upperVoiceSlots
                : lowerVoiceSlots;
            target.putIfAbsent(slot.index, () => <ScoreHit>[]).add(hit);
          }
        }

        if (upperVoiceSlots.isNotEmpty) {
          _writeVoice(
            xml: xml,
            measure: measure,
            voiceNumber: 1,
            stem: 'up',
            hitsBySlot: upperVoiceSlots,
            instrumentByPieceId: instrumentByPieceId,
          );
        }

        if (upperVoiceSlots.isNotEmpty && lowerVoiceSlots.isNotEmpty) {
          xml
            ..writeln('      <backup>')
            ..writeln('        <duration>${measure.slotsPerMeasure}</duration>')
            ..writeln('      </backup>');
        }

        if (lowerVoiceSlots.isNotEmpty) {
          _writeVoice(
            xml: xml,
            measure: measure,
            voiceNumber: upperVoiceSlots.isEmpty ? 1 : 2,
            stem: 'down',
            hitsBySlot: lowerVoiceSlots,
            instrumentByPieceId: instrumentByPieceId,
          );
        }
      }

      if (measure.index == score.measures.last.index) {
        xml
          ..writeln('      <barline location="right">')
          ..writeln('        <bar-style>light-heavy</bar-style>')
          ..writeln('      </barline>');
      }
      xml.writeln('    </measure>');
    }

    xml
      ..writeln('  </part>')
      ..writeln('</score-partwise>');
    return xml.toString();
  }

  static void _writeVoice({
    required StringBuffer xml,
    required ScoreMeasure measure,
    required int voiceNumber,
    required String stem,
    required Map<int, List<ScoreHit>> hitsBySlot,
    required Map<String, _InstrumentSpec> instrumentByPieceId,
  }) {
    final slotIndices = hitsBySlot.keys.toList()..sort();
    var cursor = 0;

    for (var index = 0; index < slotIndices.length; index++) {
      final slotIndex = slotIndices[index];
      final gapBefore = slotIndex - cursor;
      if (gapBefore > 0) {
        _writeRests(
          xml: xml,
          startSlot: cursor,
          span: gapBefore,
          measureSlots: measure.slotsPerMeasure,
          voiceNumber: voiceNumber,
        );
      }

      final nextSlot = index < slotIndices.length - 1
          ? slotIndices[index + 1]
          : measure.slotsPerMeasure;
      final noteDuration = _bestDuration(
        startSlot: slotIndex,
        maxSpan: nextSlot - slotIndex,
        measureSlots: measure.slotsPerMeasure,
      );
      final hits = [...hitsBySlot[slotIndex]!]
        ..sort(
          (left, right) =>
              left.piece.staffPosition.compareTo(right.piece.staffPosition),
        );

      for (var noteIndex = 0; noteIndex < hits.length; noteIndex++) {
        final hit = hits[noteIndex];
        final instrument = instrumentByPieceId[hit.piece.id]!;
        final (step, octave) = _displayPitchForStaffPosition(
          hit.piece.staffPosition,
        );

        xml.writeln('      <note>');
        if (noteIndex > 0) {
          xml.writeln('        <chord/>');
        }
        xml
          ..writeln('        <unpitched>')
          ..writeln('          <display-step>$step</display-step>')
          ..writeln('          <display-octave>$octave</display-octave>')
          ..writeln('        </unpitched>')
          ..writeln('        <duration>${noteDuration.duration}</duration>')
          ..writeln('        <instrument id="${instrument.id}"/>')
          ..writeln('        <voice>$voiceNumber</voice>')
          ..writeln('        <type>${noteDuration.type}</type>');
        if (noteDuration.dotted) {
          xml.writeln('        <dot/>');
        }
        xml
          ..writeln('        <stem>$stem</stem>')
          ..writeln('        <staff>1</staff>');
        if (hit.piece.noteheadStyle == DrumNoteheadStyle.cross) {
          xml.writeln('        <notehead>x</notehead>');
        }
        if (hit.velocity >= 110) {
          xml
            ..writeln('        <notations>')
            ..writeln('          <articulations>')
            ..writeln('            <accent/>')
            ..writeln('          </articulations>')
            ..writeln('        </notations>');
        }
        xml.writeln('      </note>');
      }

      cursor = slotIndex + noteDuration.duration;
    }

    final gapAfter = measure.slotsPerMeasure - cursor;
    if (gapAfter > 0) {
      _writeRests(
        xml: xml,
        startSlot: cursor,
        span: gapAfter,
        measureSlots: measure.slotsPerMeasure,
        voiceNumber: voiceNumber,
      );
    }
  }

  static void _writeRests({
    required StringBuffer xml,
    required int startSlot,
    required int span,
    required int measureSlots,
    required int voiceNumber,
  }) {
    var cursor = startSlot;
    var remaining = span;

    while (remaining > 0) {
      final restDuration = _bestDuration(
        startSlot: cursor,
        maxSpan: remaining,
        measureSlots: measureSlots,
      );
      xml
        ..writeln('      <note>')
        ..writeln('        <rest/>')
        ..writeln('        <duration>${restDuration.duration}</duration>')
        ..writeln('        <voice>$voiceNumber</voice>')
        ..writeln('        <type>${restDuration.type}</type>');
      if (restDuration.dotted) {
        xml.writeln('        <dot/>');
      }
      xml
        ..writeln('        <staff>1</staff>')
        ..writeln('      </note>');
      cursor += restDuration.duration;
      remaining -= restDuration.duration;
    }
  }

  static bool _isUpperVoice(DrumPiece piece) =>
      piece.noteheadStyle == DrumNoteheadStyle.cross;

  static _DurationSpec _bestDuration({
    required int startSlot,
    required int maxSpan,
    required int measureSlots,
  }) {
    const options = [
      _DurationSpec(duration: 16, type: 'whole'),
      _DurationSpec(duration: 12, type: 'half', dotted: true),
      _DurationSpec(duration: 8, type: 'half'),
      _DurationSpec(duration: 6, type: 'quarter', dotted: true),
      _DurationSpec(duration: 4, type: 'quarter'),
      _DurationSpec(duration: 3, type: 'eighth', dotted: true),
      _DurationSpec(duration: 2, type: 'eighth'),
      _DurationSpec(duration: 1, type: '16th'),
    ];

    for (final option in options) {
      if (option.duration > maxSpan ||
          option.duration > measureSlots - startSlot) {
        continue;
      }
      if (_isAlignedForDuration(startSlot, option.duration, measureSlots)) {
        return option;
      }
    }

    return const _DurationSpec(duration: 1, type: '16th');
  }

  static bool _isAlignedForDuration(
    int startSlot,
    int duration,
    int measureSlots,
  ) {
    switch (duration) {
      case 16:
        return measureSlots == 16 && startSlot == 0;
      case 12:
        return startSlot == 0;
      case 8:
        return startSlot % 8 == 0;
      case 6:
      case 4:
      case 3:
        return startSlot % 4 == 0;
      case 2:
        return startSlot % 2 == 0;
      default:
        return true;
    }
  }

  static (String, int) _displayPitchForStaffPosition(int staffPosition) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    final diatonicIndex = 38 - staffPosition;
    final octave = diatonicIndex ~/ 7;
    final step = letters[diatonicIndex % 7];
    return (step, octave);
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _InstrumentSpec {
  const _InstrumentSpec({
    required this.id,
    required this.piece,
    required this.midiNote,
  });

  final String id;
  final DrumPiece piece;
  final int midiNote;
}

class _DurationSpec {
  const _DurationSpec({
    required this.duration,
    required this.type,
    this.dotted = false,
  });

  final int duration;
  final String type;
  final bool dotted;
}
