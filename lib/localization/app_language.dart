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
  String get code => name;

  String get nativeName {
    switch (this) {
      case AppLanguage.tr: return 'Türkçe';
      case AppLanguage.en: return 'English';
      case AppLanguage.fr: return 'Français';
      case AppLanguage.de: return 'Deutsch';
      case AppLanguage.es: return 'Español';
      case AppLanguage.zh: return '中文';
      case AppLanguage.ru: return 'Русский';
      case AppLanguage.ja: return '日本語';
    }
  }

  static AppLanguage fromCode(String? code) {
    final normalized = code?.toLowerCase();
    return AppLanguage.values.firstWhere(
      (language) => language.code == normalized,
      orElse: () => AppLanguage.tr,
    );
  }
}
