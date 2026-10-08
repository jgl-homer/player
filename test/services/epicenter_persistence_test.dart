import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/state_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SMART defaults and peak protection on a new installation', () async {
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
