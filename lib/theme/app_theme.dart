import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFFFD500); // Yellow from Muzio
  static const Color backgroundColor = Colors.black;
  static const Color surfaceColor = Color(0xFF121212); // Slightly lighter black for miniplayer
  static const Color surfaceVariant = Color(0xFF2C2C2C); // For chips and selected items
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
