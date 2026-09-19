import 'package:flutter/material.dart';

abstract final class EnterpriseColors {
  static const primary = Color(0xFF155EEF);
  static const primaryHover = Color(0xFF004EEB);
  static const success = Color(0xFF067647);
  static const warning = Color(0xFFB54708);
  static const danger = Color(0xFFB42318);
  static const information = Color(0xFF175CD3);

  static const lightCanvas = Color(0xFFF6F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceMuted = Color(0xFFF2F4F7);
  static const lightBorder = Color(0xFFD0D5DD);
  static const lightText = Color(0xFF101828);
  static const lightTextMuted = Color(0xFF475467);

  static const darkCanvas = Color(0xFF0C111D);
  static const darkSurface = Color(0xFF161B26);
  static const darkSurfaceMuted = Color(0xFF1F2633);
  static const darkBorder = Color(0xFF344054);
  static const darkText = Color(0xFFF2F4F7);
  static const darkTextMuted = Color(0xFF98A2B3);
}

abstract final class EnterpriseSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

abstract final class EnterpriseTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark
        ? EnterpriseColors.darkSurface
        : EnterpriseColors.lightSurface;
    final canvas = isDark
        ? EnterpriseColors.darkCanvas
        : EnterpriseColors.lightCanvas;
    final border = isDark
        ? EnterpriseColors.darkBorder
        : EnterpriseColors.lightBorder;
    final text = isDark
        ? EnterpriseColors.darkText
        : EnterpriseColors.lightText;
    final muted = isDark
        ? EnterpriseColors.darkTextMuted
        : EnterpriseColors.lightTextMuted;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: EnterpriseColors.primary,
      onPrimary: Colors.white,
      secondary: EnterpriseColors.information,
      onSecondary: Colors.white,
      error: EnterpriseColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );

    final baseTextTheme = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final textTheme = baseTextTheme
        .apply(fontFamily: 'Arial', bodyColor: text, displayColor: text)
        .copyWith(
          headlineSmall: TextStyle(
            fontFamily: 'Arial',
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Arial',
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Arial',
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: text,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Arial',
            fontSize: 13,
            height: 1.35,
            color: text,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Arial',
            fontSize: 12,
            height: 1.3,
            color: muted,
          ),
          labelLarge: const TextStyle(
            fontFamily: 'Arial',
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        );

    const denseVisualDensity = VisualDensity(horizontal: -2, vertical: -2);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Arial',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      cardColor: surface,
      dividerColor: border,
      visualDensity: denseVisualDensity,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: EnterpriseColors.primary,
            width: 2,
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: EnterpriseColors.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: EnterpriseColors.danger,
            width: 2,
          ),
        ),
        helperStyle: TextStyle(fontSize: 12, color: muted),
        errorStyle: const TextStyle(
          fontSize: 12,
          color: EnterpriseColors.danger,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: EnterpriseColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(34),
          maximumSize: const Size.square(36),
          padding: const EdgeInsets.all(7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          isDark
              ? EnterpriseColors.darkSurfaceMuted
              : EnterpriseColors.lightSurfaceMuted,
        ),
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        headingRowHeight: 40,
        horizontalMargin: 12,
        columnSpacing: 20,
        dividerThickness: 1,
        headingTextStyle: textTheme.labelLarge,
        dataTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? EnterpriseColors.lightSurface
              : EnterpriseColors.darkSurface,
          borderRadius: BorderRadius.circular(3),
        ),
        textStyle: TextStyle(
          color: isDark
              ? EnterpriseColors.lightText
              : EnterpriseColors.darkText,
          fontSize: 12,
        ),
      ),
    );
  }
}
