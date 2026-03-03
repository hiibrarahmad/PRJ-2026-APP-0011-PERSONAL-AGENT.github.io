import 'package:flutter/material.dart';

class ThemeConstants {
  static const Color primary = Color(0xFF00E5FF);
  static const Color primaryDark = Color(0xFF00B8D4);
  static const Color accent = Color(0xFF00FF9C);

  static const Color background = Color(0xFF05070A);
  static const Color surface = Color(0xFF0B0F14);
  static const Color card = Color(0xFF11161C);
  static const Color panel = Color(0xFF0C131C);
  static const Color panelElevated = Color(0xFF111A24);
  static const Color outline = Color(0x334FC3F7);

  static const Color text = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF9AA4AF);

  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB300);
  static const Color error = Color(0xFFFF5252);

  static const Color neonBlue = Color(0xFF34D7FF);
  static const Color neonMint = Color(0xFF4CFFB0);
  static const Color neonPurple = Color(0xFF8D7BFF);

  static const LinearGradient appBarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xCC0D1722), Color(0xCC111E2B)],
  );

  static const LinearGradient primaryGlowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF01E7FF), Color(0xFF00C2FF), Color(0xFF33FFB8)],
  );
}
