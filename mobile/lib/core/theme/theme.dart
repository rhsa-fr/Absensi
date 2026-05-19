import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Premium Monochrome color scheme with subtle emerald accents
  static const Color carbonBlack = Color(0xFF121212);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color softGrayBg = Color(0xFFF8F9FA);
  static const Color borderGray = Color(0xFFE9ECEF);
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textMuted = Color(0xFF7A7A7A);
  static const Color emeraldSuccess = Color(0xFF10B981);
  static const Color roseDanger = Color(0xFFEF4444);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: carbonBlack,
      scaffoldBackgroundColor: softGrayBg,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      colorScheme: const ColorScheme.light(
        primary: carbonBlack,
        onPrimary: pureWhite,
        secondary: textMuted,
        onSecondary: pureWhite,
        error: roseDanger,
        onError: pureWhite,
        surface: pureWhite,
        onSurface: textDark,
      ),
      
      // Modern sleek typography
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textDark, letterSpacing: -0.5),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark, letterSpacing: -0.2),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
          bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: textDark),
          bodyMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textMuted),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textDark, letterSpacing: 0.5),
        ),
      ),

      // Input Decoration (Text Field styling)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: pureWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: const TextStyle(fontSize: 13, color: textMuted, fontWeight: FontWeight.w500),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderGray, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderGray, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: carbonBlack, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: roseDanger, width: 1.5),
        ),
      ),

      // Sleek Elevate/Solid button styling
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: carbonBlack,
          foregroundColor: pureWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Sleek Outlined button styling
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textDark,
          backgroundColor: pureWhite,
          side: const BorderSide(color: borderGray, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // Card Design
      cardTheme: CardThemeData(
        color: pureWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderGray, width: 1),
        ),
      ),
    );
  }
}
