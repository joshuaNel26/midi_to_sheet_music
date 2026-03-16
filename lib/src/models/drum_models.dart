import 'dart:math' as math;

enum DrumNoteheadStyle { regular, cross }

const scoreMeasuresPerSystem = 4;
const scoreSystemsPerPage = 6;
const scoreSlotsPerQuarter = 4;

class DrumPiece {
  const DrumPiece({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.staffPosition,
    this.noteheadStyle = DrumNoteheadStyle.regular,
    this.openMarker = false,
    this.showStem = true,
  });

  final String id;
  final String label;
  final String shortLabel;
  final int staffPosition;
  final DrumNoteheadStyle noteheadStyle;
  final bool openMarker;
  final bool showStem;
}

class DrumLibrary {
  static const ignore = DrumPiece(
    id: 'ignore',
    label: 'Ignore',
    shortLabel: 'Off',
    staffPosition: 4,
    showStem: false,
  );

  static const kick = DrumPiece(
    id: 'kick',
    label: 'Kick',
    shortLabel: 'Kick',
    staffPosition: 7,
  );

  static const snare = DrumPiece(
    id: 'snare',
    label: 'Snare',
    shortLabel: 'Sn',
    staffPosition: 4,
  );

  static const sideStick = DrumPiece(
    id: 'sidestick',
    label: 'Side Stick',
    shortLabel: 'SS',
    staffPosition: 4,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const clap = DrumPiece(
    id: 'clap',
    label: 'Clap',
    shortLabel: 'Clp',
    staffPosition: 2,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const closedHiHat = DrumPiece(
    id: 'closed_hihat',
    label: 'Closed Hi-Hat',
    shortLabel: 'CH',
    staffPosition: -1,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const openHiHat = DrumPiece(
    id: 'open_hihat',
    label: 'Open Hi-Hat',
    shortLabel: 'OH',
    staffPosition: -1,
    noteheadStyle: DrumNoteheadStyle.cross,
    openMarker: true,
  );

  static const pedalHiHat = DrumPiece(
    id: 'pedal_hihat',
    label: 'Pedal Hi-Hat',
    shortLabel: 'PH',
    staffPosition: 9,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const crash = DrumPiece(
    id: 'crash',
    label: 'Crash Cymbal',
    shortLabel: 'Cr',
    staffPosition: -2,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const ride = DrumPiece(
    id: 'ride',
    label: 'Ride Cymbal',
    shortLabel: 'Rd',
    staffPosition: -1,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const highTom = DrumPiece(
    id: 'high_tom',
    label: 'High Tom',
    shortLabel: 'HT',
    staffPosition: 0,
  );

  static const midTom = DrumPiece(
    id: 'mid_tom',
    label: 'Mid Tom',
    shortLabel: 'MT',
    staffPosition: 2,
  );

  static const lowTom = DrumPiece(
    id: 'low_tom',
    label: 'Low Tom',
    shortLabel: 'LT',
    staffPosition: 6,
  );

  static const floorTom = DrumPiece(
    id: 'floor_tom',
    label: 'Floor Tom',
    shortLabel: 'FT',
    staffPosition: 8,
  );

  static const cowbell = DrumPiece(
    id: 'cowbell',
    label: 'Cowbell',
    shortLabel: 'Cow',
    staffPosition: 0,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const auxiliary = DrumPiece(
    id: 'auxiliary',
    label: 'Aux Percussion',
    shortLabel: 'Aux',
    staffPosition: 2,
    noteheadStyle: DrumNoteheadStyle.cross,
  );

  static const assignablePieces = <DrumPiece>[
    ignore,
    kick,
    snare,
    sideStick,
    clap,
    closedHiHat,
    openHiHat,
    pedalHiHat,
    crash,
    ride,
    highTom,
    midTom,
    lowTom,
    floorTom,
    cowbell,
    auxiliary,
  ];

  static final Map<String, DrumPiece> byId = {
    for (final piece in assignablePieces) piece.id: piece,
  };

  static final Map<int, DrumPiece> generalMidiMap = {
    35: kick,
    36: kick,
    37: sideStick,
    38: snare,
    39: clap,
    40: snare,
    41: floorTom,
    42: closedHiHat,
    43: floorTom,
    44: pedalHiHat,
    45: lowTom,
    46: openHiHat,
    47: midTom,
    48: highTom,
    49: crash,
    50: highTom,
    51: ride,
    52: crash,
    53: ride,
    54: auxiliary,
    55: crash,
    56: cowbell,
    57: crash,
    58: auxiliary,
    59: ride,
    60: auxiliary,
    61: auxiliary,
    62: auxiliary,
    63: auxiliary,
    64: auxiliary,
    65: auxiliary,
    66: auxiliary,
    67: auxiliary,
    68: auxiliary,
    69: auxiliary,
    70: auxiliary,
    71: auxiliary,
    72: auxiliary,
    73: auxiliary,
    74: auxiliary,
    75: auxiliary,
    76: auxiliary,
    77: auxiliary,
    78: auxiliary,
    79: auxiliary,
    80: auxiliary,
    81: auxiliary,
  };

  static DrumPiece pieceForId(String id) => byId[id] ?? auxiliary;

  static DrumPiece defaultForMidiNote(int midiNote) =>
      generalMidiMap[midiNote] ?? auxiliary;
}

class MidiTimeSignature {
  const MidiTimeSignature({required this.numerator, required this.denominator});

  final int numerator;
  final int denominator;

  String get label => '$numerator/$denominator';
}

int slotsPerMeasureForTimeSignature(MidiTimeSignature timeSignature) {
  return math.max(
    1,
    ((timeSignature.numerator * scoreSlotsPerQuarter * 4) /
            timeSignature.denominator)
        .round(),
  );
}

int slotsPerBeatForTimeSignature(MidiTimeSignature timeSignature) {
  return math.max(
    1,
    (slotsPerMeasureForTimeSignature(timeSignature) / timeSignature.numerator)
        .round(),
  );
}

String slotLabelForIndex(int slotIndex, int slotsPerBeat) {
  final beatNumber = (slotIndex ~/ slotsPerBeat) + 1;
  final slotInBeat = slotIndex % slotsPerBeat;
  if (slotInBeat == 0) {
    return '$beatNumber';
  }

  return '$beatNumber${_subdivisionLabel(slotInBeat, slotsPerBeat)}';
}

String _subdivisionLabel(int slotInBeat, int slotsPerBeat) {
  switch (slotsPerBeat) {
    case 2:
      return '&';
    case 3:
      return slotInBeat == 1 ? '&' : 'a';
    case 4:
      return switch (slotInBeat) {
        1 => 'e',
        2 => '+',
        _ => 'a',
      };
    default:
      return '+';
  }
}

class MidiNoteEvent {
  const MidiNoteEvent({
    required this.startTick,
    required this.durationTicks,
    required this.channel,
    required this.note,
    required this.velocity,
  });

  final int startTick;
  final int durationTicks;
  final int channel;
  final int note;
  final int velocity;
}

class ParsedMidiFile {
  const ParsedMidiFile({
    required this.sourceName,
    required this.format,
    required this.trackCount,
    required this.ticksPerQuarterNote,
    required this.tempoMicrosecondsPerQuarter,
    required this.timeSignature,
    required this.noteEvents,
    required this.usedPercussionChannelOnly,
  });

  final String sourceName;
  final int format;
  final int trackCount;
  final int ticksPerQuarterNote;
  final int tempoMicrosecondsPerQuarter;
  final MidiTimeSignature timeSignature;
  final List<MidiNoteEvent> noteEvents;
  final bool usedPercussionChannelOnly;

  int get tempoBpm =>
      (60000000 / math.max(1, tempoMicrosecondsPerQuarter)).round();
}

class DrumSourceNote {
  const DrumSourceNote({required this.midiNote, required this.hitCount});

  final int midiNote;
  final int hitCount;
}

class ScoreHit {
  const ScoreHit({
    required this.piece,
    required this.midiNote,
    required this.velocity,
  });

  final DrumPiece piece;
  final int midiNote;
  final int velocity;
}

class ScoreSlot {
  const ScoreSlot({required this.index, required this.hits});

  final int index;
  final List<ScoreHit> hits;

  bool get isAccent => hits.any((hit) => hit.velocity >= 110);
}

class ScoreMeasure {
  const ScoreMeasure({
    required this.index,
    required this.slotsPerMeasure,
    required this.beatsPerMeasure,
    required this.slotsPerBeat,
    required this.slots,
  });

  final int index;
  final int slotsPerMeasure;
  final int beatsPerMeasure;
  final int slotsPerBeat;
  final List<ScoreSlot> slots;

  bool get isEmpty => slots.isEmpty;
}

class ScoreSystem {
  const ScoreSystem({required this.index, required this.measures});

  final int index;
  final List<ScoreMeasure> measures;
}

class ScorePageData {
  const ScorePageData({required this.index, required this.systems});

  final int index;
  final List<ScoreSystem> systems;
}

class ScoreDocument {
  const ScoreDocument({
    required this.title,
    required this.tempoBpm,
    required this.timeSignature,
    required this.measures,
    required this.pages,
    required this.usedPieces,
    required this.totalHits,
  });

  final String title;
  final int tempoBpm;
  final MidiTimeSignature timeSignature;
  final List<ScoreMeasure> measures;
  final List<ScorePageData> pages;
  final List<DrumPiece> usedPieces;
  final int totalHits;

  int get totalPages => pages.length;
}

List<DrumSourceNote> extractSourceNotes(ParsedMidiFile midi) {
  final counts = <int, int>{};

  for (final event in midi.noteEvents) {
    counts.update(event.note, (count) => count + 1, ifAbsent: () => 1);
  }

  final notes = [
    for (final entry in counts.entries)
      DrumSourceNote(midiNote: entry.key, hitCount: entry.value),
  ];

  notes.sort((left, right) => left.midiNote.compareTo(right.midiNote));
  return notes;
}

String midiNoteName(int note) {
  const names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  // FL Studio labels middle C (MIDI 60) as C5, so shift the displayed octave.
  final octave = note ~/ 12;
  return '${names[note % 12]}$octave';
}

String displayTitleFromFileName(String fileName) {
  final trimmed = fileName.trim();
  final dotIndex = trimmed.lastIndexOf('.');
  if (dotIndex <= 0) {
    return trimmed;
  }

  return trimmed.substring(0, dotIndex);
}
