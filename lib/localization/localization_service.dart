import 'app_language.dart';

class LocalizationService {
  final AppLanguage language;

  const LocalizationService({this.language = AppLanguage.tr});

  String text(String key) {
    return _translations[language]?[key] ??
        _translations[AppLanguage.en]?[key] ??
        key;
  }

  static const Map<AppLanguage, Map<String, String>> _translations = {
    AppLanguage.tr: {
      'cockpit': 'Kokpit', 'sld': 'Tek Hat', 'short_circuit': 'Kısa Devre',
      'protection': 'Koruma', 'cable': 'Kablo', 'load_flow': 'Yük Akışı',
      'sat': 'SAT', 'quick_check': 'Hızlı Kontrol', 'field_mode': 'Saha Modu',
      'expert_mode': 'Uzman Modu', 'field_assistant': 'Saha Asistanı',
      'engineering_summary': 'Mühendislik Özeti', 'standard_profile': 'Standart Profili',
      'change_standard': 'Standardı Değiştir', 'language': 'Dil', 'settings': 'Ayarlar',
      'working_mode': 'Çalışma Modu', 'working_mode_body': 'Çalışma seviyesini seçin.',
      'disclaimer_title': 'Yasal Bilgilendirme',
      'disclaimer_body': 'Bu yazılım saha mühendisliği için karar destek aracıdır. Sertifikalı FAT/SAT veya üretici doğrulamasının yerine geçmez.',
      'accept': 'Kabul Ediyorum', 'understood': 'Anlaşıldı', 'cancel': 'İptal',
      'scan_equipment': 'Ekipman Tara', 'field_context': 'Saha Verisi',
      'ocr_demo_body': 'Bu sürümde OCR simülasyonu kullanılır. Gerçek kamera/OCR verisi henüz devrede değildir.',
      'ocr_demo_result': 'DEMO: Röle pick-up 1250 A, TMS 0.15 olarak uygulandı.',
      'gps_demo_body': 'Bu sürümde GPS simülasyonu kullanılır. Örnek olarak 1250 m rakım uygulanacaktır.',
      'gps_demo_result': 'DEMO: Rakım 1250 m olarak uygulandı.', 'apply_demo': 'Demo Verisini Uygula',
      'voltage_kv': 'Bara Gerilimi (kV)', 'grid_ssc_mva': 'Şebeke Ssc (MVA)',
      'trafo_mva': 'Trafo Gücü (MVA)', 'uk_percent': 'Trafo uk (%)',
      'fault_current': 'Arıza Akımı', 'thevenin_impedance': 'Thevenin Empedansı',
      'breaker_capacity': 'Kesici Kesme Kapasitesi', 'curve': 'Röle Eğrisi',
      'pickup_a': 'Pick-up (A)', 'tms': 'TMS', 'simulated_fault': 'Simüle Arıza Akımı',
      'trip_time': 'Açma Süresi', 'no_trip': 'Pick-up aşılmadı', 'copper_conductor': 'Bakır İletken',
      'section_mm2': 'Kesit (mm²)', 'length_m': 'Uzunluk (m)', 'load_current_a': 'Yük Akımı (A)',
      'ampacity': 'Akım Taşıma Kapasitesi', 'voltage_drop': 'Gerilim Düşümü',
      'thermal_check': 'Termik Kontrol', 'active_power_mw': 'Aktif Güç (MW)',
      'power_factor': 'Güç Faktörü', 'line_length_km': 'Hat Uzunluğu (km)',
      'current': 'Akım', 'receiving_voltage': 'Alıcı Gerilim', 'single_line': 'Tek Hat Diyagramı',
      'dga_note': 'DGA alanları hazırdır; gerçek laboratuvar/cihaz verisi girilmelidir.',
      'dga_not_verified': 'DGA sonucu doğrulanmadı.', 'sat_note': 'Saha test cihazı ölçümlerini girin. Üretici limiti ayrıca doğrulanmalıdır.',
      'manufacturer_limit': 'Üretici Limiti', 'country': 'Ülke', 'altitude': 'Rakım',
      'ambient_temperature': 'Ortam Sıcaklığı', 'data_source': 'Veri Kaynağı', 'demo_data': 'DEMO / Simülasyon',
      'direct_numeric_input': 'Saha kullanımında doğrudan sayısal giriş tercih edilir; slider yalnızca hızlı keşif için kullanılmalıdır.',
      'why': 'Neden?', 'input': 'Girdiler', 'short_circuit_explanation': 'Şebeke ve trafo empedansları seri eşdeğer üzerinden değerlendirilmiştir.',
      'pass': 'Uygun', 'fail': 'Uygun Değil', 'warning': 'Uyarı', 'not_verified': 'Doğrulanmadı',
    },
    AppLanguage.en: {
      'cockpit': 'Cockpit', 'sld': 'Single Line', 'short_circuit': 'Short Circuit', 'protection': 'Protection',
      'cable': 'Cable', 'load_flow': 'Load Flow', 'sat': 'SAT', 'quick_check': 'Quick Check',
      'field_mode': 'Field Mode', 'expert_mode': 'Expert Mode', 'field_assistant': 'Field Assistant',
      'engineering_summary': 'Engineering Summary', 'standard_profile': 'Standard Profile',
      'change_standard': 'Change Standard', 'language': 'Language', 'settings': 'Settings',
      'working_mode': 'Working Mode', 'working_mode_body': 'Select the working level.',
      'disclaimer_title': 'Disclaimer', 'disclaimer_body': 'This software is an engineering decision-support tool. It does not replace certified FAT/SAT or manufacturer verification.',
      'accept': 'I Accept', 'understood': 'Understood', 'cancel': 'Cancel', 'scan_equipment': 'Scan Equipment',
      'field_context': 'Field Data', 'ocr_demo_body': 'OCR simulation is used in this build. Real camera/OCR data is not connected yet.',
      'ocr_demo_result': 'DEMO: Relay pickup set to 1250 A and TMS to 0.15.', 'gps_demo_body': 'GPS simulation is used in this build. Example altitude will be set to 1250 m.',
      'gps_demo_result': 'DEMO: Altitude set to 1250 m.', 'apply_demo': 'Apply Demo Data', 'voltage_kv': 'Bus Voltage (kV)',
      'grid_ssc_mva': 'Grid Ssc (MVA)', 'trafo_mva': 'Transformer Rating (MVA)', 'uk_percent': 'Transformer uk (%)',
      'fault_current': 'Fault Current', 'thevenin_impedance': 'Thevenin Impedance', 'breaker_capacity': 'Breaker Capacity',
      'curve': 'Relay Curve', 'pickup_a': 'Pickup (A)', 'tms': 'TMS', 'simulated_fault': 'Simulated Fault Current',
      'trip_time': 'Trip Time', 'no_trip': 'Pickup not exceeded', 'copper_conductor': 'Copper Conductor', 'section_mm2': 'Section (mm²)',
      'length_m': 'Length (m)', 'load_current_a': 'Load Current (A)', 'ampacity': 'Ampacity', 'voltage_drop': 'Voltage Drop',
      'thermal_check': 'Thermal Check', 'active_power_mw': 'Active Power (MW)', 'power_factor': 'Power Factor',
      'line_length_km': 'Line Length (km)', 'current': 'Current', 'receiving_voltage': 'Receiving Voltage', 'single_line': 'Single Line Diagram',
      'dga_note': 'DGA fields are ready; real laboratory/device data must be entered.', 'dga_not_verified': 'DGA result not verified.',
      'sat_note': 'Enter field test measurements. Manufacturer limits must be verified separately.', 'manufacturer_limit': 'Manufacturer Limit',
      'country': 'Country', 'altitude': 'Altitude', 'ambient_temperature': 'Ambient Temperature', 'data_source': 'Data Source',
      'demo_data': 'DEMO / Simulation', 'direct_numeric_input': 'Direct numeric input is preferred in the field; sliders are for quick exploration.',
      'why': 'Why?', 'input': 'Inputs', 'short_circuit_explanation': 'Grid and transformer impedances are evaluated as a series equivalent.',
      'pass': 'Pass', 'fail': 'Fail', 'warning': 'Warning', 'not_verified': 'Not Verified',
    },
    AppLanguage.fr: {'cockpit':'Cockpit','sld':'Schéma unifilaire','short_circuit':'Court-circuit','protection':'Protection','cable':'Câble','load_flow':'Flux de puissance','sat':'SAT','quick_check':'Contrôle rapide','field_mode':'Mode terrain','expert_mode':'Mode expert','field_assistant':'Assistant terrain','standard_profile':'Profil de norme','language':'Langue','settings':'Réglages','working_mode':'Mode de travail','scan_equipment':'Scanner équipement','field_context':'Données terrain','change_standard':'Changer la norme','pass':'Conforme','fail':'Non conforme','warning':'Avertissement','not_verified':'Non vérifié'},
    AppLanguage.de: {'cockpit':'Cockpit','sld':'Einlinienschema','short_circuit':'Kurzschluss','protection':'Schutz','cable':'Kabel','load_flow':'Lastfluss','sat':'SAT','quick_check':'Schnellprüfung','field_mode':'Feldmodus','expert_mode':'Expertenmodus','field_assistant':'Feldassistent','standard_profile':'Normprofil','language':'Sprache','settings':'Einstellungen','working_mode':'Arbeitsmodus','scan_equipment':'Gerät scannen','field_context':'Felddaten','change_standard':'Norm ändern','pass':'Bestanden','fail':'Nicht bestanden','warning':'Warnung','not_verified':'Nicht verifiziert'},
    AppLanguage.es: {'cockpit':'Panel','sld':'Esquema unifilar','short_circuit':'Cortocircuito','protection':'Protección','cable':'Cable','load_flow':'Flujo de carga','sat':'SAT','quick_check':'Comprobación rápida','field_mode':'Modo campo','expert_mode':'Modo experto','field_assistant':'Asistente de campo','standard_profile':'Perfil de norma','language':'Idioma','settings':'Ajustes','working_mode':'Modo de trabajo','scan_equipment':'Escanear equipo','field_context':'Datos de campo','change_standard':'Cambiar norma','pass':'Conforme','fail':'No conforme','warning':'Advertencia','not_verified':'No verificado'},
    AppLanguage.zh: {'cockpit':'控制台','sld':'单线图','short_circuit':'短路','protection':'保护','cable':'电缆','load_flow':'潮流','sat':'SAT','quick_check':'快速检查','field_mode':'现场模式','expert_mode':'专家模式','field_assistant':'现场助手','standard_profile':'标准配置','language':'语言','settings':'设置','working_mode':'工作模式','scan_equipment':'扫描设备','field_context':'现场数据','change_standard':'更改标准','pass':'通过','fail':'不通过','warning':'警告','not_verified':'未验证'},
    AppLanguage.ru: {'cockpit':'Кабина','sld':'Однолинейная схема','short_circuit':'Короткое замыкание','protection':'Защита','cable':'Кабель','load_flow':'Поток мощности','sat':'ПСИ','quick_check':'Быстрая проверка','field_mode':'Полевой режим','expert_mode':'Экспертный режим','field_assistant':'Полевой ассистент','standard_profile':'Профиль стандарта','language':'Язык','settings':'Настройки','working_mode':'Режим работы','scan_equipment':'Сканировать оборудование','field_context':'Полевые данные','change_standard':'Изменить стандарт','pass':'Соответствует','fail':'Не соответствует','warning':'Предупреждение','not_verified':'Не проверено'},
    AppLanguage.ja: {'cockpit':'コックピット','sld':'単線結線図','short_circuit':'短絡','protection':'保護','cable':'ケーブル','load_flow':'潮流','sat':'SAT','quick_check':'クイックチェック','field_mode':'現場モード','expert_mode':'エキスパートモード','field_assistant':'現場アシスタント','standard_profile':'規格プロファイル','language':'言語','settings':'設定','working_mode':'作業モード','scan_equipment':'機器をスキャン','field_context':'現場データ','change_standard':'規格を変更','pass':'適合','fail':'不適合','warning':'警告','not_verified':'未検証'},
  };
}
