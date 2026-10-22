import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI never reaches through AudioProvider to the raw audio player', () {
    final roots = <Directory>[
      Directory('lib/screens'),
      Directory('lib/widgets'),
    ];

    final offenders = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('audioProvider.player')) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Playback must flow UI -> AudioProvider -> PlaybackEngine -> AudioHandler.',
    );
  });

  test('AudioProvider does not own raw AudioPlayer or MyAudioHandler anymore', () {
    final source = File('lib/providers/audio_provider.dart').readAsStringSync();

    expect(RegExp(r'\bAudioPlayer\s+_player\b').hasMatch(source), isFalse);
    expect(RegExp(r'\bMyAudioHandler\s+_handler\b').hasMatch(source), isFalse);
    expect(source.contains('_handler.'), isFalse);
  });
}
