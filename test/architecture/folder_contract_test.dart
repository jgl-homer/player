import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Only line endings are normalized. Keep the protected method text intact.
String method(String source, String name) {
  source = source.replaceAll('\r\n', '\n');
  final start = RegExp(r'^  (?:Future<void>|void|String) ' + name + r'\(',
          multiLine: true)
      .firstMatch(source)!;
  final tail = source.substring(start.start);
  final end = tail.indexOf('\n  }');
  final arrow = tail.indexOf('=>');
  final body = tail.indexOf(') {');
  if (arrow >= 0 && (body < 0 || arrow < body) && (end < 0 || arrow < end)) {
    return tail.substring(0, tail.indexOf(';') + 1);
  }
  return tail.substring(0, end + 4);
}

void main() {
  test('folder methods remain identical to main', () {
    final source = File('lib/providers/audio_provider.dart').readAsStringSync();
    for (final ref in ['main', 'origin/main']) {
      final result = Process.runSync(
          'git', ['show', '$ref:lib/providers/audio_provider.dart']);
      expect(result.exitCode, 0, reason: '$ref must be available locally');
      for (final name in [
        'setPlaybackMode',
        'playFolderSongs',
        '_normalizeFolderPath',
        '_getParentPathForString',
        '_getParentPath',
        'playNextFolder',
        'playPreviousFolder',
        '_changeFolder',
        'deleteFolder',
      ]) {
        expect(method(source, name), method(result.stdout as String, name),
            reason: '$name differs from $ref');
      }
    }
  });
}
