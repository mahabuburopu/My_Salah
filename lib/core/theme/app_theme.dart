import 'package:flutter/material.dart';
// on for letter, icons etc on the bgnd;   outline for border
class AppTheme {
  static ThemeData get darkTheme => ThemeData( //static for using without any obj
        brightness: Brightness.dark,
        useMaterial3: true, //flutter ui design system 3
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF1A1008), //default bg color
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC9A87C), //primary main color
          secondary: Color(0xFFDEC098),
          surface: Color(0xFF2C1F11),
          onPrimary: Colors.black,
          onSurface: Colors.white,
          outline: Color(0xFF3D2E1A),
        ),
        cardColor: const Color(0xFF2C1F11),
        cardTheme: CardThemeData(
          color: const Color(0xFF2C1F11),
          elevation: 0, // no shadow
          shape: RoundedRectangleBorder( //card shap
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF3D2E1A)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF251A0E),
          selectedItemColor: Color(0xFFC9A87C),
          unselectedItemColor: Color(0xFFA08060),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1008),
          foregroundColor: Color(0xFFC9A87C),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFFA08060)),
          titleLarge: TextStyle(
              color: Color(0xFFC9A87C), fontWeight: FontWeight.bold),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A87C)
                  : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A87C).withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        dividerColor: const Color(0xFF3D2E1A),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C1F11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF3D2E1A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF3D2E1A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFFC9A87C), width: 1.5),
          ),
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFFAF6F0),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFC9A87C),
          secondary: Color(0xFF9E7A4E),
          surface: Color(0xFFFFFFFF),
          onPrimary: Colors.white,
          onSurface: Color(0xFF1A1008),
          outline: Color(0xFFE8DDD0),
        ),
        cardColor: const Color(0xFFFFFFFF),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFFFF),
          elevation: 1,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE8DDD0)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFF5EFE6),
          selectedItemColor: Color(0xFFC9A87C),
          unselectedItemColor: Color(0xFF8B6914),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF6F0),
          foregroundColor: Color(0xFFC9A87C),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1A1008)),
          bodyMedium: TextStyle(color: Color(0xFF8B6914)),
          titleLarge: TextStyle(
              color: Color(0xFFC9A87C), fontWeight: FontWeight.bold),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A87C)
                  : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A87C).withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        dividerColor: const Color(0xFFE8DDD0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8DDD0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8DDD0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFFC9A87C), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8B6914)),
        ),
      );
}
