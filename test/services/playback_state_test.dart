import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:player/services/state_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('concurrent saves restore one complete snapshot', () async {
    await Future.wait([
      StatePersistence.savePlaybackState(
          mode: PlaybackMode.folder,
          songPath: '/a/one.mp3',
          folderPath: '/a',
          positionMs: 100,
          playlistPaths: ['/a/one.mp3']),
      StatePersistence.savePlaybackState(
          mode: PlaybackMode.global,
          songPath: '/b/two.mp3',
          positionMs: 200,
          playlistPaths: ['/b/two.mp3']),
    ]);
    final state = await StatePersistence.loadPlaybackState();
    expect(state['songPath'], '/b/two.mp3');
    expect(state['positionMs'], 200);
    expect(state['folderPath'], isNull);
    expect(state['playlistPaths'], ['/b/two.mp3']);
    expect(state['mode'], PlaybackMode.global);
    // Simulate a kill during later legacy-key writes: snapshot stays coherent.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_song_path', '/partial.mp3');
    expect(
        (await StatePersistence.loadPlaybackState())['songPath'], '/b/two.mp3');
  });
  test('legacy installations still restore', () async {
    SharedPreferences.setMockInitialValues({
      'current_song_path': '/old.mp3',
      'position_ms': 123,
      'playback_mode': 'PlaybackMode.folder',
      'active_folder_path': '/',
    });
    final state = await StatePersistence.loadPlaybackState();
    expect(state['songPath'], '/old.mp3');
    expect(state['positionMs'], 123);
    expect(state['mode'], PlaybackMode.folder);
  });
  test('clearing after a pending save cannot resurrect the deleted track', () async {
    final saving = StatePersistence.savePlaybackState(
        mode: PlaybackMode.global, songPath: '/gone.mp3', positionMs: 9);
    final clearing = StatePersistence.clearPlaybackState();
    await Future.wait([saving, clearing]);
    final state = await StatePersistence.loadPlaybackState();
    expect(state['songPath'], isNull);
    expect(state['playlistPaths'], isEmpty);
  });
}
