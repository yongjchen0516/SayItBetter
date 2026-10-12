import 'package:flutter/material.dart';

/// 活潑插畫風：奶黃、珊瑚粉、天藍，搭配深藍黑文字與粗描邊。
/// 可讀性原則：文字一律深藍黑、不在彩色上放白字；大面積用很淡的底色，濃色只給按鈕與重點。
class Palette {
  static const cream = Color(0xFFFFE9A8);
  static const coral = Color(0xFFFF9E9E);
  static const sky = Color(0xFF9ED8F2);
  static const ink = Color(0xFF22304A);

  static const paper = Color(0xFFFFFBEF); // 頁面底色
  static const creamSoft = Color(0xFFFFF4D2);
  static const coralSoft = Color(0xFFFFE3E3);
  static const skySoft = Color(0xFFE1F3FB);
  static const inkSoft = Color(0xFF4A5874); // 次要文字（對比仍 > 7:1）
}

/// 描邊粗細與硬陰影（貼紙感：不模糊、往右下偏移）
const double kStroke = 2.5;
const List<BoxShadow> kStickerShadow = [
  BoxShadow(color: Palette.ink, offset: Offset(3, 4), blurRadius: 0),
];

ThemeData buildTheme() {
  const ink = Palette.ink;
  const side = BorderSide(color: ink, width: kStroke);
  const scheme = ColorScheme.light(
    primary: Palette.coral,
    onPrimary: ink,
    primaryContainer: Palette.coralSoft,
    onPrimaryContainer: ink,
    secondary: Palette.sky,
    onSecondary: ink,
    secondaryContainer: Palette.skySoft,
    onSecondaryContainer: ink,
    tertiary: Palette.cream,
    onTertiary: ink,
    tertiaryContainer: Palette.creamSoft,
    onTertiaryContainer: ink,
    surface: Palette.paper,
    onSurface: ink,
    onSurfaceVariant: Palette.inkSoft,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: Colors.white,
    outline: ink,
    outlineVariant: Color(0x4022304A),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD4),
    onErrorContainer: ink,
    inverseSurface: ink,
    onInverseSurface: Palette.paper,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(color: ink, fontWeight: FontWeight.w800),
        titleMedium: base.textTheme.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
        titleSmall: base.textTheme.titleSmall?.copyWith(color: ink, fontWeight: FontWeight.w700),
        labelLarge: base.textTheme.labelLarge?.copyWith(color: ink, fontWeight: FontWeight.w800),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: ink, height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: ink, height: 1.5),
      );
  const pill = StadiumBorder(side: side);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: ink, width: 2),
  );

  return base.copyWith(
    scaffoldBackgroundColor: Palette.paper,
    canvasColor: Colors.white,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.cream,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800),
      shape: Border(bottom: side),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: side),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.coral,
        foregroundColor: ink,
        disabledBackgroundColor: const Color(0xFFF3E9D2),
        disabledForegroundColor: Palette.inkSoft,
        shape: pill,
        side: side,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: Colors.white,
        shape: pill,
        side: side,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: ink, width: 3)),
      labelStyle: const TextStyle(color: Palette.inkSoft, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w800),
      hintStyle: const TextStyle(color: Palette.inkSoft),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Palette.sky : Colors.white),
        foregroundColor: const WidgetStatePropertyAll(ink),
        side: const WidgetStatePropertyAll(BorderSide(color: ink, width: 2)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Palette.coral,
      indicatorShape: StadiumBorder(side: BorderSide(color: ink, width: 2)),
      labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 12)),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: ink)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Palette.coral : Colors.white),
      thumbColor: const WidgetStatePropertyAll(ink),
      trackOutlineColor: const WidgetStatePropertyAll(ink),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: const TextStyle(color: Palette.paper, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.paper,
      dragHandleColor: ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: side,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: side),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: side),
    ),
    dividerTheme: const DividerThemeData(color: Color(0x4022304A), thickness: 2),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
    listTileTheme: const ListTileThemeData(iconColor: ink, textColor: ink),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: ink,
      collapsedIconColor: ink,
      textColor: ink,
      collapsedTextColor: ink,
    ),
  );
}
