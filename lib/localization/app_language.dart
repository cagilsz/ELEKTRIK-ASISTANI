enum AppLanguage {
  tr,
  en,
  fr,
  de,
  es,
  zh,
  ru,
  ja,
}

extension AppLanguageExtension on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.tr:
        return 'tr';
      case AppLanguage.en:
        return 'en';
      case AppLanguage.fr:
        return 'fr';
      case AppLanguage.de:
        return 'de';
      case AppLanguage.es:
        return 'es';
      case AppLanguage.zh:
        return 'zh';
      case AppLanguage.ru:
        return 'ru';
      case AppLanguage.ja:
        return 'ja';
    }
  }

  String get nativeName {
    switch (this) {
      case AppLanguage.tr:
        return 'Türkçe';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.fr:
        return 'Français';
      case AppLanguage.de:
        return 'Deutsch';
      case AppLanguage.es:
        return 'Español';
      case AppLanguage.zh:
        return '中文';
      case AppLanguage.ru:
        return 'Русский';
      case AppLanguage.ja:
        return '日本語';
    }
  }

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.tr,
    );
  }
}
