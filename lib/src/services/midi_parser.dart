import 'dart:collection';
import 'dart:typed_data';

import '../models/drum_models.dart';

class MidiParseException implements Exception {
  const MidiParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MidiFileParser {
  ParsedMidiFile parse(Uint8List bytes, {required String sourceName}) {
    final reader = _ByteReader(bytes);

    final headerChunk = reader.readAscii(4);
    if (headerChunk != 'MThd') {
      throw const MidiParseException('This file is not a standard MIDI file.');
    }

    final headerLength = reader.readUint32();
    if (headerLength < 6) {
      throw const MidiParseException('The MIDI header is incomplete.');
    }

    final format = reader.readUint16();
    final trackCount = reader.readUint16();
    final division = reader.readUint16();

    if ((division & 0x8000) != 0) {
      throw const MidiParseException(
        'SMPTE-timed MIDI files are not supported yet.',
      );
    }

    if (headerLength > 6) {
      reader.skip(headerLength - 6);
    }

    final allNotes = <MidiNoteEvent>[];
    int? tempoMicrosecondsPerQuarter;
    MidiTimeSignature? timeSignature;

    for (var trackIndex = 0; trackIndex < trackCount; trackIndex++) {
      final trackResult = _parseTrack(reader, division);
      allNotes.addAll(trackResult.noteEvents);
      tempoMicrosecondsPerQuarter ??= trackResult.tempoMicrosecondsPerQuarter;
      timeSignature ??= trackResult.timeSignature;
    }

    allNotes.sort((left, right) {
      final byStart = left.startTick.compareTo(right.startTick);
      if (byStart != 0) {
        return byStart;
      }

      return left.note.compareTo(right.note);
    });

    final percussionNotes = allNotes
        .where((event) => event.channel == 9)
        .toList(growable: false);

    final usedPercussionChannelOnly = percussionNotes.isNotEmpty;
    final filteredNotes = usedPercussionChannelOnly
        ? percussionNotes
        : allNotes;

    if (filteredNotes.isEmpty) {
      throw const MidiParseException(
        'No note events were found in this MIDI file.',
      );
    }

    return ParsedMidiFile(
      sourceName: sourceName,
      format: format,
      trackCount: trackCount,
      ticksPerQuarterNote: division,
      tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter ?? 500000,
      timeSignature:
          timeSignature ??
          const MidiTimeSignature(numerator: 4, denominator: 4),
      noteEvents: filteredNotes,
      usedPercussionChannelOnly: usedPercussionChannelOnly,
    );
  }

  _TrackParseResult _parseTrack(_ByteReader reader, int ticksPerQuarter) {
    final chunkType = reader.readAscii(4);
    if (chunkType != 'MTrk') {
      throw const MidiParseException('A MIDI track chunk is missing.');
    }

    final length = reader.readUint32();
    final trackEnd = reader.offset + length;

    final noteEvents = <MidiNoteEvent>[];
    final pendingNotes = <int, ListQueue<_PendingNote>>{};
    int? runningStatus;
    var tick = 0;
    int? tempoMicrosecondsPerQuarter;
    MidiTimeSignature? timeSignature;

    while (reader.offset < trackEnd) {
      tick += reader.readVariableLengthQuantity();

      final raw = reader.readByte();
      int status;
      int? firstDataByte;

      if ((raw & 0x80) == 0) {
        if (runningStatus == null) {
          throw const MidiParseException(
            'The MIDI file uses running status before a status byte appears.',
          );
        }
        status = runningStatus;
        firstDataByte = raw;
      } else {
        status = raw;
        if (status < 0xF0) {
          runningStatus = status;
        } else {
          runningStatus = null;
        }
      }

      if (status == 0xFF) {
        final type = reader.readByte();
        final dataLength = reader.readVariableLengthQuantity();
        final data = reader.readBytes(dataLength);

        switch (type) {
          case 0x2F:
            reader.offset = trackEnd;
            break;
          case 0x51:
            if (data.length >= 3) {
              tempoMicrosecondsPerQuarter ??=
                  (data[0] << 16) | (data[1] << 8) | data[2];
            }
            break;
          case 0x58:
            if (data.length >= 2) {
              timeSignature ??= MidiTimeSignature(
                numerator: data[0],
                denominator: 1 << data[1],
              );
            }
            break;
          default:
            break;
        }

        continue;
      }

      if (status == 0xF0 || status == 0xF7) {
        final dataLength = reader.readVariableLengthQuantity();
        reader.skip(dataLength);
        continue;
      }

      final eventType = status & 0xF0;
      final channel = status & 0x0F;
      final data1 = firstDataByte ?? reader.readByte();

      switch (eventType) {
        case 0x80:
          reader.readByte();
          _closePendingNote(
            pendingNotes: pendingNotes,
            noteEvents: noteEvents,
            tick: tick,
            channel: channel,
            note: data1,
            fallbackDuration: ticksPerQuarter ~/ 4,
          );
          break;
        case 0x90:
          final velocity = reader.readByte();
          if (velocity == 0) {
            _closePendingNote(
              pendingNotes: pendingNotes,
              noteEvents: noteEvents,
              tick: tick,
              channel: channel,
              note: data1,
              fallbackDuration: ticksPerQuarter ~/ 4,
            );
          } else {
            final key = (channel << 8) | data1;
            pendingNotes
                .putIfAbsent(key, ListQueue.new)
                .add(_PendingNote(startTick: tick, velocity: velocity));
          }
          break;
        case 0xA0:
        case 0xB0:
        case 0xE0:
          reader.readByte();
          break;
        case 0xC0:
        case 0xD0:
          break;
        default:
          throw MidiParseException(
            'Encountered an unsupported MIDI event: 0x${status.toRadixString(16)}.',
          );
      }
    }

    for (final entry in pendingNotes.entries) {
      while (entry.value.isNotEmpty) {
        final pending = entry.value.removeFirst();
        noteEvents.add(
          MidiNoteEvent(
            startTick: pending.startTick,
            durationTicks: ticksPerQuarter ~/ 4,
            channel: entry.key >> 8,
            note: entry.key & 0xFF,
            velocity: pending.velocity,
          ),
        );
      }
    }

    return _TrackParseResult(
      noteEvents: noteEvents,
      tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter,
      timeSignature: timeSignature,
    );
  }

  void _closePendingNote({
    required Map<int, ListQueue<_PendingNote>> pendingNotes,
    required List<MidiNoteEvent> noteEvents,
    required int tick,
    required int channel,
    required int note,
    required int fallbackDuration,
  }) {
    final key = (channel << 8) | note;
    final queue = pendingNotes[key];
    if (queue == null || queue.isEmpty) {
      return;
    }

    final pending = queue.removeFirst();
    final duration = tick - pending.startTick;

    noteEvents.add(
      MidiNoteEvent(
        startTick: pending.startTick,
        durationTicks: duration > 0 ? duration : fallbackDuration,
        channel: channel,
        note: note,
        velocity: pending.velocity,
      ),
    );
  }
}

class _TrackParseResult {
  const _TrackParseResult({
    required this.noteEvents,
    required this.tempoMicrosecondsPerQuarter,
    required this.timeSignature,
  });

  final List<MidiNoteEvent> noteEvents;
  final int? tempoMicrosecondsPerQuarter;
  final MidiTimeSignature? timeSignature;
}

class _PendingNote {
  const _PendingNote({required this.startTick, required this.velocity});

  final int startTick;
  final int velocity;
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int offset = 0;

  int readByte() {
    _ensureAvailable(1);
    return _bytes[offset++];
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final slice = Uint8List.sublistView(_bytes, offset, offset + length);
    offset += length;
    return slice;
  }

  int readUint16() => (readByte() << 8) | readByte();

  int readUint32() =>
      (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();

  String readAscii(int length) =>
      String.fromCharCodes(readBytes(length), 0, length);

  int readVariableLengthQuantity() {
    var value = 0;

    while (true) {
      final byte = readByte();
      value = (value << 7) | (byte & 0x7F);
      if ((byte & 0x80) == 0) {
        return value;
      }
    }
  }

  void skip(int length) {
    _ensureAvailable(length);
    offset += length;
  }

  void _ensureAvailable(int length) {
    if (offset + length > _bytes.length) {
      throw const MidiParseException(
        'The MIDI file ended before parsing completed.',
      );
    }
  }
}
