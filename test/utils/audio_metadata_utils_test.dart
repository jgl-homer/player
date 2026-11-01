import 'package:flutter_test/flutter_test.dart';
import 'package:player/utils/audio_metadata_utils.dart';

void main() {
  test('rejects a bogus reported bitrate in favor of the file average', () {
    final bitrate = resolveBitrateKbps(
      reportedBitsPerSecond: '32000',
      sizeBytes: 4068475,
      durationMs: 252000,
    );

    expect(bitrate, 129);
  });

  test('keeps a credible bitrate reported by the audio stream', () {
    final bitrate = resolveBitrateKbps(
      reportedBitsPerSecond: '130000',
      sizeBytes: 4068475,
      durationMs: 252000,
    );

    expect(bitrate, 130);
  });

  test('does not invent bitrate when no technical data exists', () {
    expect(
      resolveBitrateKbps(
        reportedBitsPerSecond: null,
        sizeBytes: 0,
        durationMs: 0,
      ),
      isNull,
    );
  });
}
