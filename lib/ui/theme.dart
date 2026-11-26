import 'package:flutter/material.dart';

class KimTheme {
  KimTheme._();

  static const Color bg = Color(0xFF111418);
  static const Color cardBg = Color(0xFF1B1F24);
  static const Color headerBg = Color(0xFF0E1114);
  static const Color toolbarBg = Color(0xFF161A1F);
  static const Color inputBg = Color(0xFF12161B);
  static const Color deepBg = Color(0xFF0B0D10);
  static const Color posterBg = Color(0xFF14171A);
  static const Color accent = Color(0xFFE50914);
  static const Color accentHover = Color(0xFFF40612);
  static const Color text = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF8C9BA5);
  static const Color border = Color(0xFF2C3239);
  static const Color borderHover = Color(0xFF434C56);
  static const Color secondaryBtn = Color(0xFF2A313A);
  static const Color secondaryBtnHover = Color(0xFF38424E);
  static const Color ghostBtn = Color(0xFF232A32);
  static const Color ghostBtnHover = Color(0xFF3A2226);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color cyanText = Color(0xFF5EEAD4);
  static const Color cyanLight = Color(0xFF67E8F9);
  static const Color cyanTextDark = Color(0xFF052A33);
  static const Color starGold = Color(0xFFFFCE3A);
  static const Color remarksGold = Color(0xFFFFC107);
  static const Color srcBlue = Color(0xFF5FA8D3);
  static const Color green = Color(0xFF6BD47A);
  static const Color amber = Color(0xFFE0A45C);
  static const Color warnOrange = Color(0xFFF6A94A);
  static const Color debugYellow = Color(0xFFFFD479);
  static const Color debugBlue = Color(0xFF7FD4FF);
  static const Color danger = Color(0xFFFF6B6B);

  static ThemeData buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: cyan,
        surface: cardBg,
        onPrimary: Colors.white,
        onSurface: text,
      ),
      fontFamily: 'Microsoft YaHei',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: text, fontSize: 14),
        bodySmall: TextStyle(color: textMuted, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFF3D4550)),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xEE181C22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(color: text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
    );
  }
}
