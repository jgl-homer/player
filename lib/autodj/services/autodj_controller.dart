import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/autodj_settings.dart';
import '../models/track_analysis.dart';
import '../models/transition_plan.dart';
import 'autodj_analyzer.dart';
import 'autodj_preferences.dart';
import 'transition_planner.dart';

enum AutoDjStatus { disabled, idle, analyzing, ready, mixing, error }

class AutoDjQueueSelection {
  final List<String> paths;
  final int currentIndex;

  const AutoDjQueueSelection(this.paths, this.currentIndex);
}

typedef AutoDjNextTrackSelector = Future<AutoDjQueueSelection?> Function(
  String currentPath,
);

class AutoDjController extends ChangeNotifier {
  static const _mediaChannel = MethodChannel('com.jglhomer.player/media_utils');

  final AudioPlayer primary;
  final AudioPlayer _secondary;
  final AutoDjAnalyzer analyzer;
  final TransitionPlanner planner;
  final AutoDjPreferences preferences;
  final AutoDjNextTrackSelector? selectNextTrack;
  final StreamSubscription<Duration> _positionSubscription;
  StreamSubscription<AutoDjAnalysisProgress>? _analysisProgressSubscription;

  AutoDjSettings _settings = AutoDjSettings.defaults;
  AutoDjStatus _status = AutoDjStatus.disabled;
  AutoDjAnalysisProgress? _analysisProgress;
  TransitionPlan? _preparedPlan;
  String? _error;
  List<String> _queue = const [];
  int _currentIndex = -1;
  int _generation = 0;
  int? _handoffTargetIndex;
  bool _transitionStarted = false;
  bool _disposed = false;
  bool _backgroundAnalysisRunning = false;
  bool _selectingNextTrack = false;
  List<String> _library = const [];
  int _analysisCount = 0;
  double _visualBpm = 0;
  double _visualEnergy = 0;
  int _firstBeatMs = 0;

  AutoDjController({
    required this.primary,
    AutoDjAnalyzer? analyzer,
    TransitionPlanner? planner,
    AutoDjPreferences? preferences,
    this.selectNextTrack,
  })  : _secondary = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        ),
        analyzer = analyzer ?? AutoDjAnalyzer(),
        planner = planner ?? TransitionPlanner(),
        preferences = preferences ?? AutoDjPreferences(),
        _positionSubscription = primary.positionStream.listen((_) {}) {
    _positionSubscription.onData(_onPosition);
    _analysisProgressSubscription = this.analyzer.progress.listen((progress) {
      _analysisProgress = progress;
      notifyListeners();
    });
    unawaited(_load());
  }

  AutoDjSettings get settings => _settings;
  AutoDjStatus get status => _status;
  AutoDjAnalysisProgress? get analysisProgress => _analysisProgress;
  TransitionPlan? get preparedPlan => _preparedPlan;
  String? get error => _error;
  bool get isMixing => _status == AutoDjStatus.mixing;
  int get analysisCount => _analysisCount;
  double get visualEnergy => _visualEnergy;

  double visualPulse(Duration position) {
    if (_visualBpm <= 0) return 0;
    final interval = 60000 / _visualBpm;
    final delta = max(0, position.inMilliseconds - _firstBeatMs);
    final phase = (delta % interval) / interval;
    return exp(-phase * 7).toDouble();
  }

  double transitionProgress(Duration position) {
    final plan = _preparedPlan;
    if (plan == null || !_transitionStarted) return 0;
    return ((position.inMilliseconds - plan.outgoingStartMs) / plan.durationMs)
        .clamp(0, 1);
  }

  Future<void> _load() async {
    _settings = await preferences.load();
    _analysisCount = await analyzer.database.count();
    _status = _settings.enabled ? AutoDjStatus.idle : AutoDjStatus.disabled;
    await _applyOutputGain();
    if (_settings.enabled) unawaited(_prepareNext());
    notifyListeners();
  }

  Future<void> updateSettings(AutoDjSettings value) async {
    final wasEnabled = _settings.enabled;
    _settings = value;
    await preferences.save(value);
    await _applyOutputGain();
    if (!value.enabled) {
      await _cancelTransition();
      _status = AutoDjStatus.disabled;
    } else {
      _status = AutoDjStatus.idle;
      if (wasEnabled) {
        await _cancelTransition();
      }
      // Preparing the song that will actually play always has priority over
      // the low-priority whole-library scan.
      unawaited(_prepareNext());
    }
    notifyListeners();
  }

  Future<void> _applyOutputGain() async {
    if (!Platform.isAndroid) return;
    try {
      await _mediaChannel.invokeMethod<void>('set_output_gain', {
        'enabled': _settings.audioGainEnabled,
        'gainDb': _settings.audioGainDb,
        'limiterEnabled': _settings.limiterEnabled,
      });
    } on MissingPluginException {
      // Allows unit/widget tests to use the controller without Android.
    }
  }

  void updateQueue(List<String> paths, int currentIndex) {
    final normalized = List<String>.unmodifiable(paths);
    final sameTrack = currentIndex >= 0 &&
        currentIndex < normalized.length &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        normalized[currentIndex] == _queue[_currentIndex];
    _queue = normalized;
    _currentIndex = currentIndex;

    // The provider may replace the player queue while it inserts the global
    // AutoDJ candidate. Let the in-flight preparation continue with the new
    // snapshot instead of starting a second analysis.
    if (_selectingNextTrack) return;

    if (_handoffTargetIndex == currentIndex) return;
    if (sameTrack && _preparedPlan != null) return;
    unawaited(_cancelTransition().then((_) {
      if (_settings.enabled &&
          _settings.backgroundAnalysis &&
          !_backgroundAnalysisRunning) {
        return _runBackgroundAnalysis();
      }
      if (_settings.enabled) return _prepareNext();
    }));
  }

  void updateLibrary(Iterable<String> paths) {
    final next = List<String>.unmodifiable(paths);
    if (listEquals(_library, next)) return;
    _library = next;
    if (_library.isNotEmpty && !_backgroundAnalysisRunning) {
      unawaited(_runBackgroundAnalysis());
    }
  }

  Future<void> _runBackgroundAnalysis() async {
    final paths = _library.isNotEmpty ? _library : _queue;
    if (_backgroundAnalysisRunning || paths.isEmpty) return;
    _backgroundAnalysisRunning = true;
    try {
      await analyzer.analyzeBatch(paths);
      _analysisCount = await analyzer.database.count();
    } catch (_) {
      // Background indexing is best effort. Foreground preparation cancels it
      // whenever the next transition needs immediate analysis.
    } finally {
      _backgroundAnalysisRunning = false;
      notifyListeners();
    }
  }

  Future<List<TrackAnalysis>> analyzeLibrary(Iterable<String> paths) async {
    _status = AutoDjStatus.analyzing;
    _error = null;
    notifyListeners();
    try {
      final results = await analyzer.analyzeBatch(paths);
      _analysisCount = await analyzer.database.count();
      _status = _settings.enabled ? AutoDjStatus.idle : AutoDjStatus.disabled;
      return results;
    } catch (exception) {
      _error = exception.toString();
      _status = AutoDjStatus.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> cancelAnalysis() => analyzer.cancel();

  Future<void> cancelActiveTransition() async {
    if (_transitionStarted || _preparedPlan != null) {
      await _cancelTransition();
      _status = _settings.enabled ? AutoDjStatus.idle : AutoDjStatus.disabled;
      notifyListeners();
      if (_settings.enabled) unawaited(_prepareNext());
    }
  }

  Future<void> clearAnalysis() async {
    await analyzer.cancel();
    await analyzer.database.clear();
    _analysisCount = 0;
    await _cancelTransition();
    _status = _settings.enabled ? AutoDjStatus.idle : AutoDjStatus.disabled;
    notifyListeners();
  }

  Future<void> mixNow() async {
    if (!_settings.enabled) return;
    if (_preparedPlan == null) await _prepareNext();
    if (_preparedPlan != null && !_transitionStarted) {
      await _startTransition();
    }
  }

  Future<void> _prepareNext() async {
    if (_backgroundAnalysisRunning) {
      await analyzer.cancel();
      while (_backgroundAnalysisRunning && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    if (_settings.enabled &&
        selectNextTrack != null &&
        !_selectingNextTrack &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length) {
      _selectingNextTrack = true;
      try {
        final selection = await selectNextTrack!(_queue[_currentIndex]);
        if (selection != null) {
          _queue = List<String>.unmodifiable(selection.paths);
          _currentIndex = selection.currentIndex;
        }
      } finally {
        _selectingNextTrack = false;
      }
    }

    final generation = ++_generation;
    _transitionStarted = false;
    _preparedPlan = null;
    _error = null;
    if (!_settings.enabled ||
        _currentIndex < 0 ||
        _currentIndex + 1 >= _queue.length) {
      _status = _settings.enabled ? AutoDjStatus.idle : AutoDjStatus.disabled;
      notifyListeners();
      return;
    }

    final outgoingPath = _queue[_currentIndex];
    final incomingPath = _queue[_currentIndex + 1];
    if (!File(outgoingPath).existsSync() || !File(incomingPath).existsSync()) {
      _status = AutoDjStatus.error;
      _error = 'AutoDJ sólo puede preparar archivos locales disponibles';
      notifyListeners();
      return;
    }

    _status = AutoDjStatus.analyzing;
    notifyListeners();
    try {
      final outgoing = await analyzer.analyze(outgoingPath);
      final incoming = await analyzer.analyze(incomingPath);
      if (_disposed || generation != _generation || !_settings.enabled) return;
      final plan = planner.plan(
        outgoing: outgoing,
        incoming: incoming,
        settings: _settings,
      );
      _visualBpm = outgoing.bpm;
      _visualEnergy = outgoing.energy;
      _firstBeatMs =
          outgoing.beatGridMs.isEmpty ? 0 : outgoing.beatGridMs.first;
      await _secondary.setAudioSource(
        AudioSource.uri(Uri.file(incomingPath)),
        initialPosition: Duration(milliseconds: plan.incomingStartMs),
      );
      await _secondary.setSpeed(plan.incomingTempoRatio);
      await _secondary.setVolume(0);
      if (_disposed || generation != _generation || !_settings.enabled) return;
      _preparedPlan = plan;
      _status = AutoDjStatus.ready;
      notifyListeners();
      if (_settings.backgroundAnalysis && _library.isNotEmpty) {
        unawaited(_runBackgroundAnalysis());
      }
      if (primary.position.inMilliseconds >= plan.outgoingStartMs) {
        unawaited(_startTransition());
      }
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      _error = exception.toString();
      _status = AutoDjStatus.error;
      notifyListeners();
    }
  }

  void _onPosition(Duration position) {
    final plan = _preparedPlan;
    if (!_settings.enabled || plan == null || _transitionStarted) return;
    if (position.inMilliseconds >= plan.outgoingStartMs) {
      unawaited(_startTransition());
    }
  }

  Future<void> _startTransition() async {
    final plan = _preparedPlan;
    if (plan == null ||
        _transitionStarted ||
        _currentIndex + 1 >= _queue.length) {
      return;
    }
    _transitionStarted = true;
    _status = AutoDjStatus.mixing;
    _error = null;
    final generation = _generation;
    final targetIndex = _currentIndex + 1;
    _handoffTargetIndex = targetIndex;
    notifyListeners();

    try {
      unawaited(_secondary.play());
      final outgoingVolume = _volumeForDb(plan.outgoingGainDb);
      final incomingVolume = _volumeForDb(plan.incomingGainDb);
      await primary.crossfadeTo(
        _secondary,
        duration: Duration(milliseconds: plan.durationMs),
        fromStartVolume: outgoingVolume,
        toEndVolume: incomingVolume,
        quickCut: plan.type == AutoDjTransitionType.quickCut,
        effect: plan.type.name,
        effectIntensity: _settings.effectIntensity,
      );
      if (_disposed || generation != _generation) return;

      final handoffPosition = _secondary.position;
      await primary.setVolume(0);
      await primary.setSpeed(plan.incomingTempoRatio);
      await primary.seek(handoffPosition, index: targetIndex);
      if (!primary.playing) unawaited(primary.play());
      await _secondary.crossfadeTo(
        primary,
        duration: const Duration(milliseconds: 240),
        fromStartVolume: incomingVolume,
        toEndVolume: incomingVolume,
      );
      await _secondary.stop();
      await _secondary.setVolume(0);
      await _secondary.setSpeed(1);
      await primary.setVolume(incomingVolume);

      _currentIndex = targetIndex;
      _handoffTargetIndex = null;
      _preparedPlan = null;
      _transitionStarted = false;
      _status = AutoDjStatus.idle;
      notifyListeners();
      unawaited(_prepareNext());
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      _handoffTargetIndex = null;
      _transitionStarted = false;
      _error = exception.toString();
      _status = AutoDjStatus.error;
      await _secondary.stop();
      await primary.setVolume(1);
      notifyListeners();
    }
  }

  double _volumeForDb(double db) => pow(10, min(0, db) / 20).toDouble();

  Future<void> _cancelTransition({bool resetPrimary = true}) async {
    _generation++;
    _handoffTargetIndex = null;
    _transitionStarted = false;
    _preparedPlan = null;
    try {
      await AudioPlayer.cancelNativeCrossfade();
    } catch (_) {}
    await _secondary.stop();
    await _secondary.setVolume(0);
    await _secondary.setSpeed(1);
    if (resetPrimary) {
      await primary.setVolume(1);
      await primary.setSpeed(1);
    }
  }

  Future<void> _disposeResources() async {
    _disposed = true;
    await _positionSubscription.cancel();
    await _analysisProgressSubscription?.cancel();
    await _cancelTransition();
    await analyzer.dispose();
    await _secondary.dispose();
  }

  @override
  void dispose() {
    unawaited(_disposeResources());
    super.dispose();
  }
}
