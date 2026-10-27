import 'package:flutter/material.dart';

class AppMotion {
  static const Duration pageTransition = Duration(milliseconds: 260);
  static const Duration pageTransitionReverse = Duration(milliseconds: 220);
  static const Duration tabTransition = Duration(milliseconds: 170);
  static const Duration expansionTransition = Duration(milliseconds: 240);
  static const Duration expansionTransitionReverse =
      Duration(milliseconds: 200);

  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;

  const AppMotion._();
}

class _SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.pageTransition;

  @override
  Duration get reverseTransitionDuration => AppMotion.pageTransitionReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enterCurve,
      reverseCurve: AppMotion.exitCurve,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.82, end: 1).animate(curvedAnimation),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}

class AppTheme {
  static Color primaryColor = const Color(0xFFFFD500);
  static const Color backgroundColor = Colors.black;
  static const Color surfaceColor =
      Color(0xFF121212); // Slightly lighter black for miniplayer
  static const Color surfaceVariant =
      Color(0xFF2C2C2C); // For chips and selected items
  static const Color textMain = Colors.white;
  static const Color textSecondary = Colors.grey;

  static ThemeData get darkTheme => darkThemeFor(primaryColor);

  static ThemeData darkThemeFor(Color accent) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: accent,
        scaffoldBackgroundColor: backgroundColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundColor,
          foregroundColor: textMain,
          elevation: 0,
          iconTheme: IconThemeData(color: textMain),
        ),
        colorScheme: ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: surfaceColor,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: textMain, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: textMain),
          bodyMedium: TextStyle(color: textSecondary),
        ),
        iconTheme: const IconThemeData(color: textMain),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _SmoothPageTransitionsBuilder(),
            TargetPlatform.fuchsia: _SmoothPageTransitionsBuilder(),
          },
        ),
        expansionTileTheme: const ExpansionTileThemeData(
          expansionAnimationStyle: AnimationStyle(
            duration: AppMotion.expansionTransition,
            reverseDuration: AppMotion.expansionTransitionReverse,
            curve: AppMotion.enterCurve,
            reverseCurve: AppMotion.exitCurve,
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: accent,
          unselectedLabelColor: textSecondary,
          indicatorColor: accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: Colors.black,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: backgroundColor,
        ),
      );

  static ThemeData lightThemeFor(Color accent) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: accent,
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        colorScheme: ColorScheme.light(
          primary: accent,
          secondary: accent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: accent,
          unselectedLabelColor: Colors.black54,
          indicatorColor: accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: Colors.black,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _SmoothPageTransitionsBuilder(),
            TargetPlatform.fuchsia: _SmoothPageTransitionsBuilder(),
          },
        ),
      );
}
