import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'playback_engine.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'native_audio_bridge.dart';
import 'replay_gain_repository.dart';
import 'state_persistence.dart';

/// Owns every non-visual playback effect/control.
///
/// AudioProvider remains the UI-facing facade, while this controller owns the
/// native DSP contract, persisted settings and ReplayGain lifecycle. It does
/// not know anything about folder navigation.
class AudioEffectsController extends ChangeNotifier {
  final PlaybackEngine playback;
  final NativeAudioBridge nativeAudio;
  final ReplayGainRepository replayGainRepository;
  final String? Function() currentSongPath;
  final SongModel? Function() nextSong;

  bool _isEpicenterEnabled = false;
  EpicenterEngineMode _epicenterEngine = EpicenterEngineMode.hybrid;
  double _epicenterSweepFreq = StatePersistence.defaultEpicenterSweepFreq;
  double _epicenterWidth = StatePersistence.defaultEpicenterWidth;
  double _epicenterIntensity = StatePersistence.defaultEpicenterIntensity;
  double _epicenterVolume = StatePersistence.defaultEpicenterVolume;
  bool _epicenterPeakProtectionEnabled =
      StatePersistence.defaultEpicenterPeakProtectionEnabled;

  bool _equalizerEnabled = false;
  List<double> _equalizerBandGains =
      List<double>.from(StatePersistence.defaultEqualizerBandGains);

  bool _replayGainEnabled = false;
  ReplayGainMode _replayGainMode = ReplayGainMode.track;
  double _activeReplayGainDb = 0;
  double _activeReplayPeak = 0;
  bool _currentReplayGainAvailable = false;
  int _replayGainRequestSerial = 0;

  double _playbackSpeed = 1.0;
  double _playbackPitchSemitones = 0.0;
  Timer? _playbackRateSaveDebounce;
  bool _disposed = false;

  AudioEffectsController({
    required this.playback,
    required this.nativeAudio,
    required this.replayGainRepository,
    required this.currentSongPath,
    required this.nextSong,
  });

  bool get isEpicenterEnabled => _isEpicenterEnabled;
  EpicenterEngineMode get epicenterEngine => _epicenterEngine;
  double get epicenterSweepFreq => _epicenterSweepFreq;
  double get epicenterWidth => _epicenterWidth;
  double get epicenterIntensity => _epicenterIntensity;
  double get epicenterVolume => _epicenterVolume;
  bool get epicenterPeakProtectionEnabled => _epicenterPeakProtectionEnabled;

  bool get equalizerEnabled => _equalizerEnabled;
  List<double> get equalizerBandGains =>
      List<double>.unmodifiable(_equalizerBandGains);

  bool get replayGainEnabled => _replayGainEnabled;
  ReplayGainMode get replayGainMode => _replayGainMode;
  bool get currentReplayGainAvailable => _currentReplayGainAvailable;

  double get playbackSpeed => _playbackSpeed;
  double get playbackPitchSemitones => _playbackPitchSemitones;

  Future<void> initialize() async {
    _isEpicenterEnabled = await StatePersistence.loadEpicenterEnabled();
    _epicenterEngine = await StatePersistence.loadEpicenterEngine();
    _epicenterPeakProtectionEnabled =
        await StatePersistence.loadEpicenterPeakProtectionEnabled();
    _equalizerEnabled = await StatePersistence.loadEqualizerEnabled();
    _equalizerBandGains = await StatePersistence.loadEqualizerBandGains();
    _replayGainEnabled = await StatePersistence.loadReplayGainEnabled();
    _replayGainMode = await StatePersistence.loadReplayGainMode();
    _playbackSpeed = await StatePersistence.loadPlaybackSpeed();
    _playbackPitchSemitones =
        await StatePersistence.loadPlaybackPitchSemitones();

    try {
      final params = await StatePersistence.loadEpicenterParams();
      _epicenterSweepFreq = params['sweepFreq'] ?? _epicenterSweepFreq;
      _epicenterWidth = params['width'] ?? _epicenterWidth;
      _epicenterIntensity = params['intensity'] ?? _epicenterIntensity;
      _epicenterVolume = params['volume'] ?? _epicenterVolume;
    } catch (error) {
      debugPrint('Error loading epicenter params: $error');
    }

    try {
      await Future.wait([
        playback.setSpeed(_playbackSpeed),
        playback.setPitch(
          pow(2.0, _playbackPitchSemitones / 12.0).toDouble(),
        ),
      ]);
    } catch (error) {
      debugPrint('Error restoring playback speed/pitch: $error');
    }

    notifyListeners();
  }

  Future<void> onAudioSessionReady() async {
    await nativeAudio.setEpicenterEnabled(_isEpicenterEnabled);
    await setEpicenterParams(
      sweepFreq: _epicenterSweepFreq,
      width: _epicenterWidth,
      intensity: _epicenterIntensity,
      volume: _epicenterVolume,
      peakProtectionEnabled: _epicenterPeakProtectionEnabled,
    );
    await _sendToneControls();
  }

  Future<void> toggleEpicenter() async {
    _isEpicenterEnabled = !_isEpicenterEnabled;
    notifyListeners();
    await StatePersistence.saveEpicenterEnabled(_isEpicenterEnabled);

    try {
      await nativeAudio.setEpicenterEnabled(_isEpicenterEnabled);
      if (_isEpicenterEnabled) {
        await setEpicenterParams(
          sweepFreq: _epicenterSweepFreq,
          width: _epicenterWidth,
          intensity: _epicenterIntensity,
          volume: _epicenterVolume,
          peakProtectionEnabled: _epicenterPeakProtectionEnabled,
        );
      }
    } catch (error) {
      debugPrint('Epicenter error: $error');
      _isEpicenterEnabled = false;
      await StatePersistence.saveEpicenterEnabled(false);
      notifyListeners();
    }
  }

  Future<void> setEpicenterParams({
    EpicenterEngineMode? engine,
    double? sweepFreq,
    double? width,
    double? intensity,
    double? volume,
    bool? peakProtectionEnabled,
  }) {
    return nativeAudio.setEpicenterParams(
      engine: engine ?? _epicenterEngine,
      sweepFreq: sweepFreq,
      width: width,
      intensity: intensity,
      volume: volume,
      peakProtectionEnabled: peakProtectionEnabled,
    );
  }

  Future<void> setEpicenterEngine(EpicenterEngineMode engine) async {
    await setEpicenterParams(engine: engine);
    _epicenterEngine = engine;
    notifyListeners();
    await StatePersistence.saveEpicenterEngine(engine);
  }

  Future<void> updateEpicenterSettings({
    double? sweepFreq,
    double? width,
    double? intensity,
    double? volume,
    bool? peakProtectionEnabled,
  }) async {
    if (sweepFreq != null) _epicenterSweepFreq = sweepFreq;
    if (width != null) _epicenterWidth = width;
    if (intensity != null) _epicenterIntensity = intensity;
    if (volume != null) _epicenterVolume = volume;
    if (peakProtectionEnabled != null) {
      _epicenterPeakProtectionEnabled = peakProtectionEnabled;
    }

    notifyListeners();

    try {
      await StatePersistence.saveEpicenterParams(
        sweepFreq: _epicenterSweepFreq,
        width: _epicenterWidth,
        intensity: _epicenterIntensity,
        volume: _epicenterVolume,
      );
      await StatePersistence.saveEpicenterPeakProtectionEnabled(
        _epicenterPeakProtectionEnabled,
      );
    } catch (error) {
      debugPrint('Error saving epicenter params: $error');
    }

    try {
      await setEpicenterParams(
        sweepFreq: _epicenterSweepFreq,
        width: _epicenterWidth,
        intensity: _epicenterIntensity,
        volume: _epicenterVolume,
        peakProtectionEnabled: _epicenterPeakProtectionEnabled,
      );
    } catch (error) {
      debugPrint('Error applying epicenter params to native: $error');
    }
  }

  Future<void> resetEpicenterSettingsToDefault() {
    return updateEpicenterSettings(
      sweepFreq: StatePersistence.defaultEpicenterSweepFreq,
      width: StatePersistence.defaultEpicenterWidth,
      intensity: StatePersistence.defaultEpicenterIntensity,
      volume: StatePersistence.defaultEpicenterVolume,
      peakProtectionEnabled:
          StatePersistence.defaultEpicenterPeakProtectionEnabled,
    );
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (_equalizerEnabled == enabled) return;
    _equalizerEnabled = enabled;
    notifyListeners();
    await StatePersistence.saveEqualizerSettings(
      enabled: enabled,
      bandGains: _equalizerBandGains,
    );
    await _sendToneControls();
  }

  Future<void> setEqualizerBandGain(int index, double gainDb) async {
    if (index < 0 || index >= _equalizerBandGains.length) return;
    final normalized = gainDb.clamp(-6.0, 6.0);
    if ((_equalizerBandGains[index] - normalized).abs() < 0.001) return;

    final updated = List<double>.from(_equalizerBandGains);
    updated[index] = normalized;
    _equalizerBandGains = updated;
    notifyListeners();

    await StatePersistence.saveEqualizerSettings(
      enabled: _equalizerEnabled,
      bandGains: updated,
    );
    await _sendToneControls();
  }

  Future<void> setEqualizerPreset(List<double> bandGains) async {
    _equalizerBandGains = List<double>.generate(
      StatePersistence.defaultEqualizerBandGains.length,
      (index) => index < bandGains.length && bandGains[index].isFinite
          ? bandGains[index].clamp(-6.0, 6.0)
          : 0.0,
      growable: false,
    );
    notifyListeners();

    await StatePersistence.saveEqualizerSettings(
      enabled: _equalizerEnabled,
      bandGains: _equalizerBandGains,
    );
    await _sendToneControls();
  }

  Future<void> setReplayGainEnabled(
      bool enabled, SongModel? currentSong) async {
    if (_replayGainEnabled == enabled) return;
    _replayGainEnabled = enabled;
    await StatePersistence.saveReplayGainSettings(
      enabled: enabled,
      mode: _replayGainMode,
    );

    if (!enabled || currentSong == null) {
      _replayGainRequestSerial++;
      _activeReplayGainDb = 0;
      _activeReplayPeak = 0;
      _currentReplayGainAvailable = false;
      await _sendToneControls();
      notifyListeners();
      return;
    }

    notifyListeners();
    await applyReplayGainForSong(currentSong);
  }

  Future<void> setReplayGainMode(
    ReplayGainMode mode,
    SongModel? currentSong,
  ) async {
    if (_replayGainMode == mode) return;
    _replayGainMode = mode;
    await StatePersistence.saveReplayGainSettings(
      enabled: _replayGainEnabled,
      mode: mode,
    );
    notifyListeners();

    if (_replayGainEnabled && currentSong != null) {
      await applyReplayGainForSong(currentSong);
    }
  }

  Future<void> resetToneControls() async {
    _equalizerEnabled = false;
    _equalizerBandGains =
        List<double>.from(StatePersistence.defaultEqualizerBandGains);
    _replayGainEnabled = false;
    _replayGainMode = ReplayGainMode.track;
    _activeReplayGainDb = 0;
    _activeReplayPeak = 0;
    _currentReplayGainAvailable = false;
    _replayGainRequestSerial++;

    await Future.wait([
      StatePersistence.saveEqualizerSettings(
        enabled: false,
        bandGains: _equalizerBandGains,
      ),
      StatePersistence.saveReplayGainSettings(
        enabled: false,
        mode: ReplayGainMode.track,
      ),
    ]);
    await _sendToneControls();
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final normalized = speed.clamp(0.5, 2.0).toDouble();
    if ((_playbackSpeed - normalized).abs() < 0.001) return;
    _playbackSpeed = normalized;
    notifyListeners();
    await playback.setSpeed(normalized);
    _schedulePlaybackRateSave();
  }

  Future<void> setPlaybackPitchSemitones(double semitones) async {
    final normalized = semitones.clamp(-12.0, 12.0).toDouble();
    if ((_playbackPitchSemitones - normalized).abs() < 0.001) return;
    _playbackPitchSemitones = normalized;
    notifyListeners();
    await playback.setPitch(pow(2.0, normalized / 12.0).toDouble());
    _schedulePlaybackRateSave();
  }

  void _schedulePlaybackRateSave() {
    _playbackRateSaveDebounce?.cancel();
    _playbackRateSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      () => StatePersistence.savePlaybackRate(
        speed: _playbackSpeed,
        pitchSemitones: _playbackPitchSemitones,
      ),
    );
  }

  Future<void> resetPlaybackRate() async {
    _playbackRateSaveDebounce?.cancel();
    _playbackSpeed = 1.0;
    _playbackPitchSemitones = 0.0;
    notifyListeners();

    await Future.wait([
      playback.setSpeed(1.0),
      playback.setPitch(1.0),
      StatePersistence.savePlaybackRate(speed: 1.0, pitchSemitones: 0.0),
    ]);
  }

  Future<void> applyReplayGainForSong(SongModel song) async {
    final serial = ++_replayGainRequestSerial;
    if (!_replayGainEnabled) return;

    _activeReplayGainDb = 0;
    _activeReplayPeak = 0;
    _currentReplayGainAvailable = false;
    await _sendToneControls();

    final metadata = await replayGainRepository.read(song.data);
    if (_disposed ||
        serial != _replayGainRequestSerial ||
        !_replayGainEnabled ||
        currentSongPath() != song.data) {
      return;
    }

    if (_replayGainMode == ReplayGainMode.album) {
      _activeReplayGainDb = metadata.albumGainDb ?? metadata.trackGainDb ?? 0;
      _activeReplayPeak = metadata.albumGainDb != null
          ? metadata.albumPeak ?? metadata.trackPeak ?? 0
          : metadata.trackPeak ?? metadata.albumPeak ?? 0;
    } else {
      _activeReplayGainDb = metadata.trackGainDb ?? metadata.albumGainDb ?? 0;
      _activeReplayPeak = metadata.trackGainDb != null
          ? metadata.trackPeak ?? metadata.albumPeak ?? 0
          : metadata.albumPeak ?? metadata.trackPeak ?? 0;
    }

    _currentReplayGainAvailable = metadata.hasGain;
    await _sendToneControls();
    notifyListeners();

    final upcoming = nextSong();
    if (upcoming != null) {
      unawaited(replayGainRepository.read(upcoming.data));
    }
  }

  Future<Map<String, double?>> getReplayGainInfo(String path) =>
      replayGainRepository.info(path);

  Future<void> _sendToneControls() {
    return nativeAudio.setToneControls(
      equalizerEnabled: _equalizerEnabled,
      bandGainsDb: _equalizerBandGains,
      replayGainEnabled: _replayGainEnabled,
      replayGainDb: _activeReplayGainDb,
      replayPeak: _activeReplayPeak,
    );
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _replayGainRequestSerial++;
    _playbackRateSaveDebounce?.cancel();
    super.dispose();
  }
}
