import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class EnterpriseColors {
  static const main = Color(0xFF010736);
  static const sidebar = Color(0xFF0D1C42);
  static const substitute = Color(0xFF22396F);
  // Cool white-gray keeps the top pane distinct from the white canvas without
  // introducing a competing accent color.
  static const topNavigation = Color(0xFFF4F6FA);
  static const white = Color(0xFFFFFFFF);

  static const generativeAction = Color(0xFF4C8CE4);
  static const danger = Color(0xFFBE1A1A);
  static const success = Color(0xFF48A111);
  static const warning = Color(0xFFF2B50B);

  static const fleetHealth = Color(0xFF7DC462);
  static const baseVolume = Color(0xFF0D95D0);
  static const driverAlerts = Color(0xFFE72F52);
  static const kMeansClusters = Color(0xFF774FA0);
  static const payroll = Color(0xFFEFB734);
  static const maintenanceAlerts = Color(0xFFD44627);

  // Compatibility aliases for existing widgets while they migrate to tokens.
  static const primary = main;
  static const primaryHover = generativeAction;
  static const information = generativeAction;
  static const lightCanvas = white;
  static const lightSurface = white;
  static const lightSurfaceMuted = Color(0xFFF9F9F9);
  static const lightBorder = substitute;
  static const lightText = main;
  static const lightTextMuted = substitute;
  static const darkCanvas = main;
  static const darkSurface = sidebar;
  static const darkSurfaceMuted = substitute;
  static const darkBorder = substitute;
  static const darkText = white;
  static const darkTextMuted = white;
}

abstract final class EnterpriseGradients {
  static LinearGradient fadingToWhite(Color color) => LinearGradient(
    colors: [
      color,
      Color.lerp(color, EnterpriseColors.white, 0.42)!,
      EnterpriseColors.white,
    ],
    stops: const [0, 0.58, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static final fleetHealth = fadingToWhite(EnterpriseColors.fleetHealth);
  static final baseVolume = fadingToWhite(EnterpriseColors.baseVolume);
  static final driverAlerts = fadingToWhite(EnterpriseColors.driverAlerts);
  static final kMeansClusters = fadingToWhite(EnterpriseColors.kMeansClusters);
  static final payroll = fadingToWhite(EnterpriseColors.payroll);
  static final maintenanceAlerts = fadingToWhite(
    EnterpriseColors.maintenanceAlerts,
  );
}

abstract final class EnterpriseIcons {
  static const double strokeWidth = 1.5;
  static const double size = 20;
  static const double smallSize = 18;
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
      onPrimary: EnterpriseColors.white,
      secondary: EnterpriseColors.information,
      onSecondary: EnterpriseColors.white,
      error: EnterpriseColors.danger,
      onError: EnterpriseColors.white,
      surface: surface,
      onSurface: text,
    );

    final bodyTextTheme = GoogleFonts.interTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );
    final textTheme = bodyTextTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineSmall: GoogleFonts.montserrat(
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleLarge: GoogleFonts.montserrat(
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleMedium: GoogleFonts.montserrat(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: text,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 13,
            height: 1.35,
            color: text,
          ),
          bodySmall: GoogleFonts.inter(fontSize: 12, height: 1.3, color: muted),
          labelLarge: GoogleFonts.inter(
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
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      cardColor: surface,
      dividerColor: border,
      visualDensity: denseVisualDensity,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      iconTheme: IconThemeData(
        color: text,
        size: EnterpriseIcons.size,
        weight: EnterpriseIcons.strokeWidth,
        fill: 0,
      ),
      primaryIconTheme: const IconThemeData(
        color: EnterpriseColors.white,
        size: EnterpriseIcons.size,
        weight: EnterpriseIcons.strokeWidth,
        fill: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? EnterpriseColors.darkSurface
            : EnterpriseColors.topNavigation,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: text,
        ),
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
          backgroundColor: EnterpriseColors.generativeAction,
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
          backgroundColor: EnterpriseColors.generativeAction,
          foregroundColor: Colors.white,
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
          fontFamily: GoogleFonts.inter().fontFamily,
          fontSize: 12,
        ),
      ),
    );
  }
}
