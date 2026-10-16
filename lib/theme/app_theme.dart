import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPalette {
  const AppPalette({
    required this.brand,
    required this.onBrand,
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
  final Color onBrand;
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
        onBrand: Color.lerp(palette.onBrand, other.palette.onBrand, t)!,
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
    // White on brand is 4.57:1 (AA).
    brand: Color(0xFFD83A40),
    onBrand: Color(0xFFFFFFFF),
    brandDark: Color(0xFFB93445),
    brandSoft: Color(0xFFFFEEF0),
    background: Color(0xFFF6F6F7),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFF2F2F4),
    header: Color(0xFFFAFAFA),
    border: Color(0xFFE2E2E4),
    borderStrong: Color(0xFFD2D2D5),
    text: Color(0xFF171717),
    textMuted: Color(0xFF6B6F76),
    textFaint: Color(0xFF9A9CA3),
    link: Color(0xFF3A63B8),
    inkSoft: Color(0xFFF0F1F3),
    success: Color(0xFF168A46),
    successSoft: Color(0xFFEAF7EF),
    successBorder: Color(0xFFB8EBC8),
  );

  static const darkPalette = AppPalette(
    brand: Color(0xFFFF7180),
    // White on the light dark-mode brand is 2.6:1; dark text is 7:1.
    onBrand: Color(0xFF3A0D16),
    brandDark: Color(0xFFFFA3AD),
    brandSoft: Color(0xFF3A1A20),
    background: Color(0xFF111114),
    surface: Color(0xFF1A1B20),
    surfaceTint: Color(0xFF23242A),
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

  /// Unread and new marks: an 8px dot on a neutral icon (see [Badge]).
  static const noticeDot = Color(0xFFE5484D);

  static Color get brand => current.brand;
  static Color get onBrand => current.onBrand;
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

/// Spacing steps (DESIGN.md §4). Every padding and gap is one of these.
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii (DESIGN.md §5); pills use [StadiumBorder].
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Maximum content widths, centred on wider windows (DESIGN.md §4).
abstract final class AppWidths {
  static const double form = 720;
  static const double list = 840;
  static const double reading = 760;
  static const double home = 1200;
  static const double sheet = 640;
  static const double dialog = 400;
}

/// Durations and curves (DESIGN.md §12).
abstract final class AppMotion {
  static const short = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const long = Duration(milliseconds: 350);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve move = Curves.easeInOutCubic;
}

/// The app's card surface: radius 16, a soft shadow in light mode, no border.
BoxDecoration appSurface(BuildContext context) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      boxShadow: Theme.of(context).brightness == Brightness.dark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
    );

class AppThemeController {
  AppThemeController._();

  static const _prefKey = 'app.themeMode';

  static final ValueNotifier<ThemeMode> notifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeMode get themeMode => notifier.value;

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

// Component styles name the family too: ThemeData.fontFamily reaches only
// the text themes.
const _font = 'Roboto';

class AppTheme {
  static ThemeData get light =>
      _build(AppColors.lightPalette, Brightness.light);

  static ThemeData get dark => _build(AppColors.darkPalette, Brightness.dark);

  static ThemeData _build(AppPalette colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final error = isDark ? const Color(0xFFFFB4AB) : const Color(0xFFC62828);
    // Raised surfaces (sheets, menus, dialogs) are neutral, never brand-cast.
    final raised = isDark ? const Color(0xFF222329) : colors.surface;
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.brand,
      brightness: brightness,
    ).copyWith(
      primary: colors.brand,
      onPrimary: colors.onBrand,
      primaryContainer: colors.brandSoft,
      onPrimaryContainer: colors.brandDark,
      secondary: colors.brandDark,
      secondaryContainer: colors.surfaceTint,
      onSecondaryContainer: colors.text,
      surface: colors.surface,
      onSurface: colors.text,
      onSurfaceVariant: colors.textMuted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: raised,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: colors.surfaceTint,
      outline: colors.borderStrong,
      outlineVariant: colors.border,
      error: error,
    );

    TextStyle label(double size) => TextStyle(
          fontFamily: _font,
          fontSize: size,
          height: 1.2,
          fontWeight: FontWeight.w600,
        );
    final pill = const StadiumBorder();
    ButtonStyle sized(ButtonStyle style) => style.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpace.lg)),
          iconSize: const WidgetStatePropertyAll(18),
          shape: WidgetStatePropertyAll(pill),
          textStyle: WidgetStatePropertyAll(label(14)),
        );
    // Secondary: neutral fill, text-coloured label (DESIGN.md §6).
    final tonal = sized(FilledButton.styleFrom(
      backgroundColor: colors.surfaceTint,
      foregroundColor: colors.text,
      disabledBackgroundColor: colors.inkSoft,
      disabledForegroundColor: colors.textFaint,
      elevation: 0,
    ));

    final textTheme = TextTheme(
      headlineSmall: TextStyle(
          color: colors.text,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w700),
      titleLarge: TextStyle(
          color: colors.text,
          fontSize: 20,
          height: 1.35,
          fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
          color: colors.text,
          fontSize: 17,
          height: 1.35,
          fontWeight: FontWeight.w600),
      titleSmall: TextStyle(
          color: colors.text,
          fontSize: 15,
          height: 1.45,
          fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: colors.text, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(color: colors.text, fontSize: 15, height: 1.55),
      bodySmall:
          TextStyle(color: colors.textMuted, fontSize: 13, height: 1.45),
      labelLarge: label(14),
      labelMedium: TextStyle(
          fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(
          fontSize: 11, height: 1.2, fontWeight: FontWeight.w500),
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: colors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          // The default fade fades both pages through blank between them.
          TargetPlatform.android: const ZoomPageTransitionsBuilder(),
        },
      ),
      fontFamily: _font,
      extensions: [AppThemeColors(colors)],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.text,
        titleTextStyle: textTheme.titleMedium,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.noticeDot,
        smallSize: 8,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      // Shape and size only: colours come from the scheme, so
      // FilledButton is brand and FilledButton.tonal stays neutral.
      filledButtonTheme: FilledButtonThemeData(style: sized(const ButtonStyle())),
      // Outlined buttons look like the tonal secondary until migrated.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: tonal.copyWith(
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: sized(TextButton.styleFrom(
          foregroundColor: colors.text,
          disabledForegroundColor: colors.textFaint,
        )).copyWith(
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpace.md)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textMuted,
          minimumSize: const Size(40, 40),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.brand,
        foregroundColor: colors.onBrand,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          textStyle: WidgetStatePropertyAll(label(14)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? colors.brandSoft
                  : colors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? colors.brandDark
                  : colors.textMuted),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.text,
        unselectedLabelColor: colors.textMuted,
        labelStyle: label(14),
        unselectedLabelStyle: label(14),
        indicatorColor: colors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: colors.brand, width: 3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
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
            fontFamily: _font,
            color: selected ? colors.brand : colors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.brandSoft,
        selectedIconTheme: IconThemeData(color: colors.brand),
        unselectedIconTheme: IconThemeData(color: colors.textMuted),
        selectedLabelTextStyle: TextStyle(
          fontFamily: _font,
          color: colors.brand,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: _font,
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceTint,
        selectedColor: colors.brandSoft,
        disabledColor: colors.inkSoft,
        labelStyle:
            TextStyle(fontFamily: _font, color: colors.text, fontSize: 13),
        secondaryLabelStyle:
            TextStyle(fontFamily: _font, color: colors.brand, fontSize: 13),
        side: BorderSide.none,
        shape: pill,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? colors.brand : null),
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? colors.onBrand : null),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        modalBackgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colors.textFaint.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
        constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.textMuted,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          )),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: 14),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.brand, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2C2D34) : colors.text,
        contentTextStyle: TextStyle(
          fontFamily: _font,
          color: isDark ? colors.text : Colors.white,
          fontSize: 14,
        ),
        actionTextColor: isDark ? colors.brand : const Color(0xFFFFA3AD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
