// app_theme.dart
// 全局 UI 风格配置 — 轻量简约医疗工具风格（参考豆包App）
// 使用方式：在 main.dart 中 MaterialApp(theme: AppTheme.light)

import 'package:flutter/material.dart';

// ─────────────────────────────────────────
// 1. 色彩系统
// ─────────────────────────────────────────
class AppColors {
  AppColors._();

  // 背景
  static const Color bgPrimary   = Color(0xFFFFFFFF);
  static const Color bgSecondary = Color(0xFFF5F5F7);
  static const Color bgCard      = Color(0xFFFFFFFF);

  // 分割线
  static const Color divider     = Color(0xFFF3F4F6);

  // 主强调色（蓝）—— 仅用于选中态、主按钮、链接
  static const Color primary     = Color(0xFF3B82F6);
  static const Color primaryLight= Color(0xFFEFF6FF);

  // 语义色
  static const Color success     = Color(0xFF10B981);
  static const Color warning     = Color(0xFFF59E0B);
  static const Color danger      = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEF2F2);

  // 文字
  static const Color textPrimary   = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint      = Color(0xFF9CA3AF);
  static const Color textDisabled  = Color(0xFFD1D5DB);

  // 头像占位色（低饱和柔色，循环使用）
  static const List<Map<String, Color>> avatarPalette = [
    {'bg': Color(0xFFF2E8FF), 'dot': Color(0xFFC084FC)}, // 紫
    {'bg': Color(0xFFFEF3C7), 'dot': Color(0xFFF59E0B)}, // 黄
    {'bg': Color(0xFFDCFCE7), 'dot': Color(0xFF4ADE80)}, // 绿
    {'bg': Color(0xFFFCE7F3), 'dot': Color(0xFFF472B6)}, // 粉
    {'bg': Color(0xFFE0F2FE), 'dot': Color(0xFF38BDF8)}, // 蓝
    {'bg': Color(0xFFFFF7ED), 'dot': Color(0xFFFB923C)}, // 橙
  ];
}

// ─────────────────────────────────────────
// 2. 间距 & 圆角
// ─────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 20.0;   // 页面水平边距
  static const double xxl  = 24.0;

  static const double radiusCard   = 14.0;
  static const double radiusButton = 10.0;
  static const double radiusTag    = 6.0;
  static const double radiusInput  = 10.0;
}

// ─────────────────────────────────────────
// 3. 字体规范
// ─────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle pageTitle = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
  );
  static const TextStyle listTitle = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary,
    height: 1.6,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
    height: 1.6,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textHint,
  );
  static const TextStyle label = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static const TextStyle navLabel = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400,
  );
}

// ─────────────────────────────────────────
// 4. 阴影
// ─────────────────────────────────────────
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> modal = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 4)),
  ];
}

// ─────────────────────────────────────────
// 5. ThemeData
// ─────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bgSecondary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.bgPrimary,
    ),

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgPrimary,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppTextStyles.pageTitle,
      surfaceTintColor: Colors.transparent,
    ),

    // Card
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      margin: EdgeInsets.zero,
    ),

    // 主按钮
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        ),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // 次级按钮
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(double.infinity, 48),
        side: BorderSide.none,
        backgroundColor: AppColors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),

    // 输入框
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: AppTextStyles.caption,
    ),

    // 分割线
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 0,
    ),

    // 底部导航
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bgPrimary,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textHint,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    ),

    // ListTile
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      minVerticalPadding: 12,
      titleTextStyle: AppTextStyles.listTitle,
      subtitleTextStyle: AppTextStyles.caption,
    ),

    // Chip / 标签
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bgSecondary,
      labelStyle: AppTextStyles.label,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusTag),
      ),
      side: BorderSide.none,
    ),
  );
}
