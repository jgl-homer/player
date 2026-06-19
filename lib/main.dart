import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'services/state_persistence.dart';

import 'providers/audio_provider.dart';
import 'screens/car_mode_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

import 'package:flutter/services.dart';

late AudioHandler _audioHandler;
late bool _initialAutoMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Activar modo inmersivo y transparencia
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  _initialAutoMode = await StatePersistence.loadAutoMode();
  await SystemChrome.setPreferredOrientations(
    _initialAutoMode
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [],
  );

  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.jesus.player.media_playback.v2',
      androidNotificationChannelName: 'Reproduccion de musica',
      androidNotificationChannelDescription:
          'Controles multimedia del reproductor',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      androidShowNotificationBadge: true,
      notificationColor: Color(0xFF7B1FA2),
    ),
  );

  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AudioProvider(
            _audioHandler,
            initialAutoMode: _initialAutoMode,
          ),
        ),
      ],
      child: MaterialApp(
        locale: kReleaseMode ? null : DevicePreview.locale(context),
        builder: (context, child) {
          final viewport = _AppViewport(
            normalNavigator: child ?? const SizedBox.shrink(),
          );
          return kReleaseMode
              ? viewport
              : DevicePreview.appBuilder(context, viewport);
        },
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }
}

class _AppViewport extends StatelessWidget {
  final Widget normalNavigator;

  const _AppViewport({required this.normalNavigator});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioProvider, bool>(
      selector: (_, audioProvider) => audioProvider.isAutoModeEnabled,
      builder: (context, isAutoModeEnabled, _) {
        if (isAutoModeEnabled) return const _AutoModeNavigator();
        return normalNavigator;
      },
    );
  }
}

class _AutoModeNavigator extends StatelessWidget {
  const _AutoModeNavigator();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const CarModeScreen(),
      ),
    );
  }
}
