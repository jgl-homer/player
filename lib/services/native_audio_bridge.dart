import 'dart:async';
import 'package:flutter/services.dart';

import 'state_persistence.dart';

/// Single bridge between Flutter playback logic and the Android audio/media layer.
///
/// Keeping platform calls here prevents [AudioProvider] from becoming coupled to
/// MethodChannel method names and payload formats. The UI-facing provider can
/// remain stable while the native audio implementation evolves independently.
class NativeAudioBridge {
  static const MethodChannel _channel =
      MethodChannel('com.jglhomer.player/media_utils');

  void attachCallbacks({
    required FutureOr<void> Function() onMediaChanged,
    required FutureOr<void> Function() onBluetoothConnected,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'media_changed':
          await onMediaChanged();
          return null;
        case 'bluetooth_connected':
          await onBluetoothConnected();
          return null;
        default:
          return null;
      }
    });
  }

  static const _widgetChannel =
      MethodChannel('com.jglhomer.player/widget_actions');

  void attachWidgetActions(Future<void> Function(String) onAction) {
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'widget_action' && call.arguments is String) {
        await onAction(call.arguments as String);
      }
    });
  }

  void detachCallbacks() {
    _channel.setMethodCallHandler(null);
    _widgetChannel.setMethodCallHandler(null);
  }

  Future<void> setEpicenterEnabled(bool enabled) {
    return _channel.invokeMethod<void>(
      'toggle_epicenter',
      {'enabled': enabled},
    );
  }

  Future<void> setEpicenterParams({
    required EpicenterEngineMode engine,
    double? sweepFreq,
    double? width,
    double? intensity,
    double? volume,
    bool? peakProtectionEnabled,
  }) {
    return _channel.invokeMethod<void>('set_epicenter_params', {
      'engine': engine.name,
      if (sweepFreq != null) 'sweepFreq': sweepFreq,
      if (width != null) 'width': width,
      if (intensity != null) 'intensity': intensity,
      if (volume != null) 'volume': volume,
      if (peakProtectionEnabled != null)
        'peakProtectionEnabled': peakProtectionEnabled,
    });
  }

  Future<void> setToneControls({
    required bool equalizerEnabled,
    required List<double> bandGainsDb,
    required bool replayGainEnabled,
    required double replayGainDb,
    required double replayPeak,
  }) {
    return _channel.invokeMethod<void>('set_tone_controls', {
      'equalizerEnabled': equalizerEnabled,
      'bandGainsDb': bandGainsDb,
      'replayGainEnabled': replayGainEnabled,
      'replayGainDb': replayGainDb,
      'replayPeak': replayPeak,
    });
  }

  Future<Map<String, dynamic>> extractReplayGain(String filePath) async {
    final values = await _channel.invokeMapMethod<String, dynamic>(
      'extract_replay_gain',
      {'filePath': filePath},
    );
    return Map<String, dynamic>.from(values ?? const <String, dynamic>{});
  }

  Future<Map<String, String>> extractMetadata(String path) async {
    final values = await _channel.invokeMapMethod<String, String>(
      'extract_metadata',
      {'path': path},
    );
    return Map<String, String>.from(values ?? const <String, String>{});
  }

  Future<bool> deleteMedia(int id) async {
    return await _channel.invokeMethod<bool>('delete_media', {'id': id}) ??
        false;
  }

  Future<bool> openUrl(String url) async {
    return await _channel.invokeMethod<bool>('open_url', {'url': url}) ?? false;
  }

  Future<bool> shareMedia(String path) async {
    return await _channel.invokeMethod<bool>('share_media', {'path': path}) ??
        false;
  }

  Future<Uri?> cacheNotificationArtwork({
    required int songId,
    required Uint8List bytes,
  }) async {
    final uriString = await _channel.invokeMethod<String>(
      'cacheNotificationArtwork',
      {'songId': songId, 'bytes': bytes},
    );
    if (uriString == null || uriString.isEmpty) return null;
    return Uri.tryParse(uriString);
  }

  Future<Uint8List?> extractEmbeddedArtwork(String filePath) {
    return _channel.invokeMethod<Uint8List>(
      'extractEmbeddedArtwork',
      {'filePath': filePath},
    );
  }
}
