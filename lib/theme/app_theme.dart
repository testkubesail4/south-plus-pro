import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPalette {
  const AppPalette({
    required this.brand,
    required this.brandDark,
    required this.brandSoft,
    required this.background,
    required this.surface,
    required this.surfaceTint,
    required this.header,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.link,
    required this.inkSoft,
    required this.success,
    required this.successSoft,
    required this.successBorder,
  });

  final Color brand;
  final Color brandDark;
  final Color brandSoft;
  final Color background;
  final Color surface;
  final Color surfaceTint;
  final Color header;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color link;
  final Color inkSoft;
  final Color success;
  final Color successSoft;
  final Color successBorder;
}

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors(this.palette);

  final AppPalette palette;

  @override
  AppThemeColors copyWith({AppPalette? palette}) {
    return AppThemeColors(palette ?? this.palette);
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      AppPalette(
        brand: Color.lerp(palette.brand, other.palette.brand, t)!,
        brandDark: Color.lerp(palette.brandDark, other.palette.brandDark, t)!,
        brandSoft: Color.lerp(palette.brandSoft, other.palette.brandSoft, t)!,
        background:
            Color.lerp(palette.background, other.palette.background, t)!,
        surface: Color.lerp(palette.surface, other.palette.surface, t)!,
        surfaceTint:
            Color.lerp(palette.surfaceTint, other.palette.surfaceTint, t)!,
        header: Color.lerp(palette.header, other.palette.header, t)!,
        border: Color.lerp(palette.border, other.palette.border, t)!,
        borderStrong:
            Color.lerp(palette.borderStrong, other.palette.borderStrong, t)!,
        text: Color.lerp(palette.text, other.palette.text, t)!,
        textMuted: Color.lerp(palette.textMuted, other.palette.textMuted, t)!,
        textFaint: Color.lerp(palette.textFaint, other.palette.textFaint, t)!,
        link: Color.lerp(palette.link, other.palette.link, t)!,
        inkSoft: Color.lerp(palette.inkSoft, other.palette.inkSoft, t)!,
        success: Color.lerp(palette.success, other.palette.success, t)!,
        successSoft:
            Color.lerp(palette.successSoft, other.palette.successSoft, t)!,
        successBorder:
            Color.lerp(palette.successBorder, other.palette.successBorder, t)!,
      ),
    );
  }
}

class AppColors {
  static const lightPalette = AppPalette(
    brand: Color(0xFFFF5F6D),
    brandDark: Color(0xFFB93445),
    brandSoft: Color(0xFFFFEEF0),
    background: Color(0xFFF6F6F7),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFFFF7F8),
    header: Color(0xFFFAFAFA),
    border: Color(0xFFE2E2E4),
    borderStrong: Color(0xFFD2D2D5),
    text: Color(0xFF171717),
    textMuted: Color(0xFF6B6F76),
    textFaint: Color(0xFF9A9CA3),
    link: Color(0xFF4D6078),
    inkSoft: Color(0xFFF0F1F3),
    success: Color(0xFF168A46),
    successSoft: Color(0xFFEAF7EF),
    successBorder: Color(0xFFB8EBC8),
  );

  static const darkPalette = AppPalette(
    brand: Color(0xFFFF7180),
    brandDark: Color(0xFFFFA3AD),
    brandSoft: Color(0xFF3A1A20),
    background: Color(0xFF111114),
    surface: Color(0xFF1A1B20),
    surfaceTint: Color(0xFF242126),
    header: Color(0xFF17181D),
    border: Color(0xFF34363D),
    borderStrong: Color(0xFF4B4E57),
    text: Color(0xFFF3F4F6),
    textMuted: Color(0xFFB8BCC6),
    textFaint: Color(0xFF858B97),
    link: Color(0xFFA9C7F7),
    inkSoft: Color(0xFF24262D),
    success: Color(0xFF65D48E),
    successSoft: Color(0xFF143423),
    successBorder: Color(0xFF2E6B45),
  );

  static AppPalette get current {
    return effectiveBrightness(AppThemeController.themeMode) == Brightness.dark
        ? darkPalette
        : lightPalette;
  }

  static Brightness effectiveBrightness(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }

  static Color get brand => current.brand;
  static Color get brandDark => current.brandDark;
  static Color get brandSoft => current.brandSoft;
  static Color get background => current.background;
  static Color get surface => current.surface;
  static Color get surfaceTint => current.surfaceTint;
  static Color get header => current.header;
  static Color get border => current.border;
  static Color get borderStrong => current.borderStrong;
  static Color get text => current.text;
  static Color get textMuted => current.textMuted;
  static Color get textFaint => current.textFaint;
  static Color get link => current.link;
  static Color get inkSoft => current.inkSoft;
  static Color get success => current.success;
  static Color get successSoft => current.successSoft;
  static Color get successBorder => current.successBorder;
}

class AppThemeController {
  AppThemeController._();

  static const _prefKey = 'app.themeMode';

  static final ValueNotifier<ThemeMode> notifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeMode get themeMode => notifier.value;

  static Brightness get effectiveBrightness =>
      AppColors.effectiveBrightness(themeMode);

  static bool get isDark => effectiveBrightness == Brightness.dark;

  static void toggle() {
    setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefKey);
    notifier.value = ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  static Future<void> setMode(ThemeMode mode) async {
    notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }
}

class AppTheme {
  static ThemeData get light =>
      _build(AppColors.lightPalette, Brightness.light);

  static ThemeData get dark => _build(AppColors.darkPalette, Brightness.dark);

  static ThemeData _build(AppPalette colors, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.brand,
      brightness: brightness,
      primary: colors.brand,
      surface: colors.surface,
    );

    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(
        primary: colors.brand,
        onPrimary: Colors.white,
        secondary: colors.brandDark,
        surface: colors.surface,
        onSurface: colors.text,
        surfaceContainerHighest: colors.surfaceTint,
        outline: colors.borderStrong,
        outlineVariant: colors.border,
        error: isDark ? const Color(0xFFFFB4AB) : null,
      ),
      scaffoldBackgroundColor: colors.background,
      fontFamily: 'Roboto',
      extensions: [AppThemeColors(colors)],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.header,
        foregroundColor: colors.text,
        titleTextStyle: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: colors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.link,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.brandSoft,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
              color: selected ? colors.brand : colors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? colors.brand : colors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceTint,
        selectedColor: colors.brandSoft,
        disabledColor: colors.inkSoft,
        labelStyle: TextStyle(color: colors.text),
        secondaryLabelStyle: TextStyle(color: colors.brand),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.text,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: colors.textMuted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.brand, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? colors.surfaceTint : colors.text,
        contentTextStyle: TextStyle(
          color: isDark ? colors.text : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          color: colors.text,
          fontSize: 21,
          height: 1.32,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: colors.text,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: colors.text,
          fontSize: 17,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          color: colors.text,
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: colors.text,
          fontSize: 16,
          height: 1.62,
        ),
        bodySmall: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          height: 1.45,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
