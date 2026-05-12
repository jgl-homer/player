import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFC9A84C); // Gold
  static const Color backgroundColor = Color(0xFF080604); // Deep Dark
  static const Color surfaceColor = Color(0xFF0E0B06); // Panel Dark
  static const Color surfaceVariant = Color(0xFF1A1208); // Accent Dark
  static const Color textMain = Color(0xFFF0E6CC); // Cream/Cream White
  static const Color textSecondary = Color(0xFF7A6030); // Dim Gold/Bronze

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
    tabBarTheme: const TabBarThemeData(
      labelColor: primaryColor,
      unselectedLabelColor: textSecondary,
      indicatorColor: primaryColor,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
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
