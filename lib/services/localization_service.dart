import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported app languages
enum AppLanguage { chinese, english }

/// Extension for easy locale conversion
extension AppLanguageExtension on AppLanguage {
  Locale get locale {
    switch (this) {
      case AppLanguage.chinese:
        return const Locale('zh', '');
      case AppLanguage.english:
        return const Locale('en', '');
    }
  }

  String get displayName {
    switch (this) {
      case AppLanguage.chinese:
        return '中文';
      case AppLanguage.english:
        return 'English';
    }
  }

  String get code {
    switch (this) {
      case AppLanguage.chinese:
        return 'zh';
      case AppLanguage.english:
        return 'en';
    }
  }
}

/// Localization service for managing app language
class LocalizationService {
  static const String _languageKey = 'app_language';
  static LocalizationService? _instance;
  static SharedPreferences? _prefs;

  AppLanguage _currentLanguage = AppLanguage.chinese;

  LocalizationService._();

  static Future<LocalizationService> getInstance() async {
    if (_instance == null) {
      _instance = LocalizationService._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadLanguage();
  }

  AppLanguage get currentLanguage => _currentLanguage;

  /// Load saved language or detect from device
  /// Only save language when user explicitly selects it
  Future<void> _loadLanguage() async {
    final savedCode = _prefs?.getString(_languageKey);

    if (savedCode != null) {
      // User has manually set a language preference, use it
      _currentLanguage = _codeToLanguage(savedCode);
    } else {
      // No user preference, detect from device (but don't save yet)
      _currentLanguage = _detectDeviceLanguage();
    }
  }

  /// Detect device language - use Chinese if device language is Chinese-related
  AppLanguage _detectDeviceLanguage() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final languageCode = deviceLocale.languageCode.toLowerCase();

    // Check if device language is Chinese (including zh-CN, zh-TW, zh-HK, zh-Hans, zh-Hant, etc.)
    if (languageCode.startsWith('zh')) {
      return AppLanguage.chinese;
    }

    return AppLanguage.english;
  }

  /// Check if device language is Chinese (for initial setup)
  static bool isDeviceLanguageChinese() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final languageCode = deviceLocale.languageCode.toLowerCase();
    return languageCode.startsWith('zh');
  }

  AppLanguage _codeToLanguage(String code) {
    switch (code.toLowerCase()) {
      case 'zh':
        return AppLanguage.chinese;
      case 'en':
        return AppLanguage.english;
      default:
        return AppLanguage.chinese;
    }
  }

  /// Set app language
  Future<void> setLanguage(AppLanguage language) async {
    if (_currentLanguage == language) return;

    _currentLanguage = language;
    await _saveLanguage(language);
  }

  Future<void> _saveLanguage(AppLanguage language) async {
    await _prefs?.setString(_languageKey, language.code);
  }

  /// Get current locale
  Locale get currentLocale => _currentLanguage.locale;

  /// Translate a key to the current language
  String translate(String key) {
    final localizations = AppLocalizations(currentLocale);
    return localizations.translate(key);
  }
}

/// Translation strings for the app
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static final Map<String, Map<String, String>> _translations = {
    'zh': {
      // Main screen
      'appTitle': 'KyrieLock',
      'openFile': '打开文件',
      'encryptFile': '加密文件',
      'decryptFile': '解密文件',

      // Dialogs
      'setPassword': '设置加密密码',
      'password': '密码',
      'confirmPassword': '确认密码',
      'passwordHint': '密码提示(可选)',
      'passwordHintPlaceholder': '输入密码提示词,帮助回忆',
      'passwordPlaceholder': '请输入密码',
      'confirmPasswordPlaceholder': '请再次输入密码',
      'passwordLengthHint': '4~32位',
      'enterPassword': '输入密码',
      'cancel': '取消',
      'confirm': '确定',

      // Messages
      'passwordEmpty': '密码不能为空',
      'passwordLengthInvalid': '密码长度必须为4~32位',
      'passwordMismatch': '两次输入的密码不一致',
      'fileNotFound': '文件不存在: ',
      'openFileFailed': '打开文件失败: ',

      // Encrypt/Decrypt
      'selectOutputDirectory': '选择输出目录',
      'aboutToEncrypt': '即将加密 ',
      'filesSelectOutputDir': ' 个文件\n请选择加密后文件的保存目录',
      'batchEncrypt': '批量加密文件',
      'encryptCompleted': '加密完成: 成功 ',
      'skipped': ' 个, 跳过 ',
      'encryptFailed': '加密失败: ',

      // Decrypt
      'notEncryptedFile': '不是加密文件，已跳过',
      'noDecryptableFiles': '没有可解密的文件',
      'noOutputDirectory': '未选择保存目录',
      'batchDecrypt': '批量解密文件',
      'decryptCompleted': '解密完成: 成功 ',
      'failed': ' 个, 失败 ',
      'decryptFailed': '解密失败: ',

      // Password hint
      'hint': '提示: ',

      // Menu
      'about': '关于',
      'language': '中文/English',
      'languageSettings': '语言设置',
      'selectLanguage': '选择语言',

      // About screen
      'aboutTitle': '关于 KyrieLock',
      'aboutDescription': '一款开源跨平台高性能文件加密GUI客户端。加密器支持对任意类型的文件进行加密保护,内置的查看器支持视频、图片、音频、文本和PDF文件的查看。',
      'version': '版本',
      'openSourceProject': '开源项目',
      'visitGithub': '访问 GitHub',

      // Language selection
      'chinese': '中文',
      'english': 'English',
    },
    'en': {
      // Main screen
      'appTitle': 'KyrieLock',
      'openFile': 'Open File',
      'encryptFile': 'Encrypt File',
      'decryptFile': 'Decrypt File',

      // Dialogs
      'setPassword': 'Set Encryption Password',
      'password': 'Password',
      'confirmPassword': 'Confirm Password',
      'passwordHint': 'Password Hint (Optional)',
      'passwordHintPlaceholder': 'Enter a hint to help remember your password',
      'passwordPlaceholder': 'Enter password',
      'confirmPasswordPlaceholder': 'Enter password again',
      'passwordLengthHint': '4~32 characters',
      'enterPassword': 'Enter Password',
      'cancel': 'Cancel',
      'confirm': 'Confirm',

      // Messages
      'passwordEmpty': 'Password cannot be empty',
      'passwordLengthInvalid': 'Password must be 4~32 characters',
      'passwordMismatch': 'Passwords do not match',
      'fileNotFound': 'File not found: ',
      'openFileFailed': 'Failed to open file: ',

      // Encrypt/Decrypt
      'selectOutputDirectory': 'Select Output Directory',
      'aboutToEncrypt': 'About to encrypt ',
      'filesSelectOutputDir': ' file(s)\nPlease select the save directory for encrypted files',
      'batchEncrypt': 'Batch Encrypt Files',
      'encryptCompleted': 'Encryption completed: ',
      'skipped': ' success, ',
      'encryptFailed': 'Encryption failed: ',

      // Decrypt
      'notEncryptedFile': 'is not an encrypted file, skipped',
      'noDecryptableFiles': 'No decryptable files',
      'noOutputDirectory': 'No output directory selected',
      'batchDecrypt': 'Batch Decrypt Files',
      'decryptCompleted': 'Decryption completed: ',
      'failed': ' success, ',
      'decryptFailed': 'Decryption failed: ',

      // Password hint
      'hint': 'Hint: ',

      // Menu
      'about': 'About',
      'language': '中文/English',
      'languageSettings': 'Language Settings',
      'selectLanguage': 'Select Language',

      // About screen
      'aboutTitle': 'About KyrieLock',
      'aboutDescription':
          'An open-source cross-platform high-performance file encryption GUI client. The encryption tool supports encrypting files of any type, and the built-in viewer supports viewing video, images, audio, text, and PDF files.',
      'version': 'Version',
      'openSourceProject': 'Open Source Project',
      'visitGithub': 'Visit GitHub',

      // Language selection
      'chinese': '中文',
      'english': 'English',
    },
  };

  String translate(String key) {
    final langCode = locale.languageCode.toLowerCase().startsWith('zh')
        ? 'zh'
        : 'en';
    return _translations[langCode]?[key] ?? _translations['en']?[key] ?? key;
  }
}
