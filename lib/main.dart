import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/audio_handler.dart';
import 'services/state_persistence.dart';

import 'providers/audio_provider.dart';
import 'providers/app_settings_provider.dart';
import 'screens/car_mode_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

import 'package:flutter/services.dart';

late AudioHandler _audioHandler;
late bool _initialAutoMode;
late AppSettingsProvider _appSettings;
const bool _devicePreviewEnabled = bool.fromEnvironment('DEVICE_PREVIEW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Activar modo inmersivo y transparencia
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  _initialAutoMode = await StatePersistence.loadAutoMode();
  _appSettings = await AppSettingsProvider.load();
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
      enabled: _devicePreviewEnabled,
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
        ChangeNotifierProvider.value(value: _appSettings),
      ],
      child: Consumer<AppSettingsProvider>(builder: (context, settings, _) {
        return MaterialApp(
          locale: _devicePreviewEnabled
              ? DevicePreview.locale(context)
              : settings.locale,
          supportedLocales: const [
            Locale('es'),
            Locale('en'),
            Locale('pt'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final viewport = _AppViewport(
              normalNavigator: child ?? const SizedBox.shrink(),
            );
            return _devicePreviewEnabled
                ? DevicePreview.appBuilder(context, viewport)
                : viewport;
          },
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.lightThemeFor(settings.accentColor),
          darkTheme: AppTheme.darkThemeFor(settings.accentColor),
          home: const HomeScreen(),
        );
      }),
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
