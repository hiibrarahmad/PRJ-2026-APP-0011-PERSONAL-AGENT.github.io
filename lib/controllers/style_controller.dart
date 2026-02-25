import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Mode { light, dark }

class ThemeNotifier extends ChangeNotifier {
  // Keep a single dark visual style to avoid low-contrast combinations.
  Mode _mode = Mode.dark;

  Mode get mode => _mode;

  ThemeNotifier() {
    loadThemePreference();
  }

  void setMode(String modeValue) {
    // Force dark mode for stable readability.
    _mode = Mode.dark;
    notifyListeners();
  }

  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('isDarkMode') ?? true;
    setMode(isDarkMode ? "dark" : "dark");
    if (!isDarkMode) {
      await _saveThemePreference(true);
    }
  }

  Future<void> toggleTheme() async {
    setMode("dark");
    await _saveThemePreference(true);
  }

  Future<void> _saveThemePreference(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }
}
