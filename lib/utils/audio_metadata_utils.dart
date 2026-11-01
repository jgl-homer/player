int? resolveBitrateKbps({
  String? reportedBitsPerSecond,
  required int sizeBytes,
  required int durationMs,
}) {
  final reported = int.tryParse(reportedBitsPerSecond ?? '');
  final calculated = sizeBytes > 0 && durationMs > 0
      ? (sizeBytes * 8 * 1000 / durationMs).round()
      : null;

  if (reported != null && reported > 0) {
    if (calculated == null || calculated <= 0) {
      return (reported / 1000).round();
    }
    final ratio = reported / calculated;
    if (ratio >= 0.75 && ratio <= 1.25) {
      return (reported / 1000).round();
    }
  }

  if (calculated != null && calculated > 0) {
    return (calculated / 1000).round();
  }
  return null;
}
