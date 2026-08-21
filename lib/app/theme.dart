import 'package:flutter/material.dart';

class BasaTheme {
  static const Color primaryNavy = Color(0xFF122C5B);
  static const Color darkNavy = Color(0xFF0B234B);
  static const Color basaYellow = Color(0xFFF9A900);
  static const Color background = Color(0xFFEEF4FC);
  static const Color white = Color(0xFFFFFFFF);
  static const Color mutedText = Color(0xFF7D91B2);
  static const Color slate = Color(0xFF5A6D8D);
  static const Color cardBorder = Color(0xFFE5ECF6);
  static const Color softBlue = Color(0xFFEAF1FB);
  static const Color softGray = Color(0xFFF6F8FB);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primaryNavy,
        secondary: basaYellow,
        surface: white,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: darkNavy,
          height: 1.1,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: darkNavy,
          height: 1.1,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: darkNavy,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkNavy,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: darkNavy,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: darkNavy,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
          color: mutedText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softGray,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: cardBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: cardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: primaryNavy, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.6),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: TextStyle(
          color: Color(0xFF9AA9BF),
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: slate,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNavy,
          foregroundColor: white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryNavy,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
