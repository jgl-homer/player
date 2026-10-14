import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/lyrics_service.dart';
import 'package:player/services/state_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lyrics default to internet while preserving an embedded choice',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StatePersistence.loadLyricsSource(), LyricsSource.internet);

    SharedPreferences.setMockInitialValues({'lyrics_source_v1': 'embedded'});
    expect(await StatePersistence.loadLyricsSource(), LyricsSource.embedded);
  });

  test('tone controls default to transparent and persist bounded values',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StatePersistence.loadEqualizerEnabled(), isFalse);
    expect(await StatePersistence.loadEqualizerBandGains(), [0, 0, 0, 0, 0]);
    expect(await StatePersistence.loadReplayGainEnabled(), isFalse);
    expect(await StatePersistence.loadReplayGainMode(), ReplayGainMode.track);

    await StatePersistence.saveEqualizerSettings(
      enabled: true,
      bandGains: [9, 2, 0, -2, -9],
    );
    await StatePersistence.saveReplayGainSettings(
      enabled: true,
      mode: ReplayGainMode.album,
    );
    expect(await StatePersistence.loadEqualizerEnabled(), isTrue);
    expect(await StatePersistence.loadEqualizerBandGains(), [6, 2, 0, -2, -6]);
    expect(await StatePersistence.loadReplayGainEnabled(), isTrue);
    expect(await StatePersistence.loadReplayGainMode(), ReplayGainMode.album);
  });

  test('library sorting and playback rate persist with safe bounds', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StatePersistence.loadLibrarySortModes(), isEmpty);
    expect(await StatePersistence.loadPlaybackSpeed(), 1.0);
    expect(await StatePersistence.loadPlaybackPitchSemitones(), 0.0);

    await StatePersistence.saveLibrarySortModes({
      'songs': 'artist_asc',
      'folders': 'songs_desc',
    });
    await StatePersistence.savePlaybackRate(
      speed: 3.0,
      pitchSemitones: -18.0,
    );

    expect(await StatePersistence.loadLibrarySortModes(), {
      'songs': 'artist_asc',
      'folders': 'songs_desc',
    });
    expect(await StatePersistence.loadPlaybackSpeed(), 2.0);
    expect(await StatePersistence.loadPlaybackPitchSemitones(), -12.0);
  });

  test('engine selection persists independently of tuning and enabled state',
      () async {
    SharedPreferences.setMockInitialValues({'epicenter_intensity': 72.0});
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.hybrid);
    await StatePersistence.saveEpicenterEngine(EpicenterEngineMode.legacy);
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.legacy);
    expect(await StatePersistence.loadEpicenterEnabled(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('epicenter_intensity'), 72.0);
    await StatePersistence.saveEpicenterEngine(EpicenterEngineMode.smart);
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.smart);
    await prefs.setString('epicenter_engine', 'invalid');
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.hybrid);
  });

  test('existing V2 engine choice migrates once to HYBRID default', () async {
    SharedPreferences.setMockInitialValues({'epicenter_engine': 'smart'});
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.hybrid);
    await StatePersistence.saveEpicenterEngine(EpicenterEngineMode.smart);
    expect(await StatePersistence.loadEpicenterEngine(),
        EpicenterEngineMode.smart);
  });

  test('V2.1 defaults and peak protection on a new installation', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StatePersistence.loadEpicenterParams(), {
      'sweepFreq': 40.0,
      'width': 60.0,
      'intensity': 65.0,
      'volume': 100.0,
    });
    expect(await StatePersistence.loadEpicenterPeakProtectionEnabled(), isTrue);
  });

  test('known legacy defaults migrate once; old Balance is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'epicenter_tuning_version': 6,
      'epicenter_sweep_freq': 41.0,
      'epicenter_width': 86.0,
      'epicenter_intensity': 84.0,
      'epicenter_balance': 12.0,
      'epicenter_volume': 83.0,
      'epicenter_peak_protection': false,
    });
    final params = await StatePersistence.loadEpicenterParams();
    expect(params['intensity'], 65.0);
    expect(params['volume'], 83.0);
    expect(params.containsKey('balance'), isFalse);
    expect(
        await StatePersistence.loadEpicenterPeakProtectionEnabled(), isFalse);
    await StatePersistence.saveEpicenterParams(
      sweepFreq: 47,
      width: 71,
      intensity: 22,
      volume: 83,
    );
    expect((await StatePersistence.loadEpicenterParams())['intensity'], 22.0);
  });

  test('custom settings survive V2 migration', () async {
    SharedPreferences.setMockInitialValues({
      'epicenter_tuning_version': 6,
      'epicenter_sweep_freq': 53.0,
      'epicenter_width': 73.0,
      'epicenter_intensity': 39.0,
      'epicenter_volume': 88.0,
    });
    expect(await StatePersistence.loadEpicenterParams(), {
      'sweepFreq': 53.0,
      'width': 73.0,
      'intensity': 39.0,
      'volume': 88.0,
    });
  });

  test('version 6 manual high intensity is not retuned by an old heuristic',
      () async {
    SharedPreferences.setMockInitialValues({
      'epicenter_tuning_version': 6,
      'epicenter_sweep_freq': 36.0,
      'epicenter_width': 55.0,
      'epicenter_intensity': 100.0,
    });
    final params = await StatePersistence.loadEpicenterParams();
    expect(params['sweepFreq'], 36.0);
    expect(params['width'], 55.0);
    expect(params['intensity'], 100.0);
  });
}
