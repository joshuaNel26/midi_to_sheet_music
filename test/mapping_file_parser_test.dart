import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_to_drum/src/services/mapping_file_parser.dart';

void main() {
  test('parses the SAMPLER_IOMapInfo payload from an iom file', () {
    final parser = SamplerIoMapParser();
    final bytes = latin1.encode(
      'VC2!\u00AE\u001C\u0000\u0000'
      '<SAMPLER_IOMapInfo '
      'IOMapInfoVersion="2" '
      'IOMapName="custom_map" '
      'Nv2_38Cnt="1" '
      'Nv2_38-0="42" '
      'Nv2_40Cnt="2" '
      'Nv2_40-0="38" '
      'Nv2_40-1="49" '
      '/>\u0000\u0000',
    );

    final result = parser.parse(bytes, sourceName: 'custom.iom');

    expect(result.mapName, 'custom_map');
    expect(result.version, '2');
    expect(result.primaryTargetFor(38), 42);
    expect(result.noteTargets[40], [38, 49]);
  });
}
