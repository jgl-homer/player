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
  static const Color primaryColor = Color(0xFFFFD500); // Yellow from Muzio
  static const Color backgroundColor = Colors.black;
  static const Color surfaceColor =
      Color(0xFF121212); // Slightly lighter black for miniplayer
  static const Color surfaceVariant =
      Color(0xFF2C2C2C); // For chips and selected items
  static const Color textMain = Colors.white;
  static const Color textSecondary = Colors.grey;

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundColor,
      foregroundColor: textMain,
      elevation: 0,
      iconTheme: IconThemeData(color: textMain),
    ),
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: primaryColor,
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
    tabBarTheme: const TabBarThemeData(
      labelColor: primaryColor,
      unselectedLabelColor: textSecondary,
      indicatorColor: primaryColor,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      unselectedLabelStyle:
          TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.black,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: backgroundColor,
    ),
  );
}
