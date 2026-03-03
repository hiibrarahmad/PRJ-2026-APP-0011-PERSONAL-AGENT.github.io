import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loads default runtime configuration from `env`.
///
/// These values are fallback defaults only. User settings can override them.
class DefaultConfig {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await dotenv.load(fileName: 'env');
      _isInitialized = true;
      if (kDebugMode) {
        print('DefaultConfig: env file loaded successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('DefaultConfig: failed to load env file: $e');
        print('DefaultConfig: using hardcoded fallback defaults');
      }
      _isInitialized = true;
    }
  }

  static String _getEnvValue(String key, String fallback) {
    if (!_isInitialized) {
      if (kDebugMode) {
        print('DefaultConfig: config not initialized, returning fallback');
      }
      return fallback;
    }

    try {
      return dotenv.env[key] ?? fallback;
    } catch (e) {
      if (kDebugMode) {
        print('DefaultConfig: failed to read env key $key: $e');
      }
      return fallback;
    }
  }

  // ----- Default custom LLM config -----

  static String get defaultLlmToken => _getEnvValue('DEFAULT_LLM_TOKEN', '');

  static String get defaultLlmUrl => _getEnvValue(
    'DEFAULT_LLM_URL',
    'https://api.openai.com/v1/chat/completions',
  );

  static String get defaultLlmModel =>
      _getEnvValue('DEFAULT_LLM_MODEL', 'gpt-4o');

  // ----- Default Alibaba config -----

  static String get defaultAlibabaApiKey =>
      _getEnvValue('DEFAULT_ALIBABA_API_KEY', '');

  // ----- Default Tencent ASR config -----

  static String get defaultTencentSecretId =>
      _getEnvValue('DEFAULT_TENCENT_SECRET_ID', '');

  static String get defaultTencentSecretKey =>
      _getEnvValue('DEFAULT_TENCENT_SECRET_KEY', '');

  static String get defaultTencentToken =>
      _getEnvValue('DEFAULT_TENCENT_TOKEN', '');

  static bool get hasValidDefaultLlmConfig {
    return defaultLlmToken.isNotEmpty &&
        defaultLlmUrl.isNotEmpty &&
        defaultLlmModel.isNotEmpty;
  }

  static bool get hasValidDefaultAlibabaConfig {
    return defaultAlibabaApiKey.isNotEmpty;
  }

  static bool get hasValidDefaultTencentConfig {
    return defaultTencentSecretId.isNotEmpty &&
        defaultTencentSecretKey.isNotEmpty &&
        defaultTencentToken.isNotEmpty;
  }

  static void printConfigStatus() {
    if (!kDebugMode) return;

    print('=== DefaultConfig Status ===');
    print('Initialized: $_isInitialized');
    print('Default LLM config: ${hasValidDefaultLlmConfig ? "yes" : "no"}');
    print(
      'Default Alibaba config: ${hasValidDefaultAlibabaConfig ? "yes" : "no"}',
    );
    print(
      'Default Tencent config: ${hasValidDefaultTencentConfig ? "yes" : "no"}',
    );
    print('LLM URL: $defaultLlmUrl');
    print('LLM Model: $defaultLlmModel');
    print('============================');
  }
}
