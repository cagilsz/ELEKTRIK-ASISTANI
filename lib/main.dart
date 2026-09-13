import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const PowerFieldProApp());
}

class PowerFieldProApp extends StatelessWidget {
  const PowerFieldProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerField Pro v3.2 Global',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        cardColor: const Color(0xFF151921),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF3D00),
          surface: Color(0xFF151921),
        ),
        useMaterial3: true,
      ),
      home: const MainCockpit(),
    );
  }
}

enum AppLanguage { tr, en, de, es, fr, zh, ja, ru }
enum CellType { incomer, feeder, coupler, vtMetering, transformer }

// ==========================================
// 1. MERKEZİ MÜHENDİSLİK HESAPLAMA MOTORU
// ==========================================
class ElectricalEngine {
  static double calcShortCircuitKa(double voltageKv, double trafoMva, double ukPercent) {
    if (trafoMva <= 0 || ukPercent <= 0) return 0.0;
    final zt = (ukPercent / 100.0) * (pow(voltageKv, 2) / trafoMva);
    if (zt <= 0) return 0.0;
    return (1.10 * voltageKv) / (sqrt(3) * zt);
  }

  static double calcNominalCurrentA(double trafoMva, double voltageKv) {
    if (voltageKv <= 0) return 0.0;
    return (trafoMva * 1000.0) / (sqrt(3) * voltageKv);
  }

  static double calcInrushCurrentA(double trafoMva, double voltageKv) {
    return calcNominalCurrentA(trafoMva, voltageKv) * 10.0;
  }

  static double calcAltitudeDeratingKa(double altitudeMeters) {
    if (altitudeMeters <= 1000) return 1.0;
    return exp((altitudeMeters - 1000) / 8150.0);
  }

  static double calcTripTime(double faultA, double iSetting, double tmsVal, String curve) {
    if (faultA <= iSetting || iSetting <= 0 || tmsVal <= 0) return double.infinity;
    double k = 0.14, alpha = 0.02;
    if (curve == "VI") { k = 13.5; alpha = 1.0; }
    else if (curve == "EI") { k = 80.0; alpha = 2.0; }
    else if (curve == "LTI") { k = 120.0; alpha = 1.0; }
    
    final m = faultA / iSetting;
    final denom = pow(m, alpha) - 1.0;
    if (denom <= 0) return double.infinity;
    return tmsVal * (k / denom);
  }

  static double calcAdiabaticSection(double ikKa, double durationSec, bool isCopper) {
    final k = isCopper ? 143.0 : 94.0;
    return ((ikKa * 1000.0) * sqrt(durationSec)) / k;
  }
}

// ==========================================
// 2. GÜVENLİ CIBANO REGEX PARSER
// ==========================================
class CibanoParser {
  static Map<String, double> parse(String text) {
    final Map<String, double> res = {};
    final rMatch = RegExp(r'\b[R|r]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);
    final sMatch = RegExp(r'\b[S|s]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);
    final tMatch = RegExp(r'\b[T|t]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);

    final trMatch = RegExp(r'\b[tT][R|r]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);
    final tsMatch = RegExp(r'\b[tT][S|s]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);
    final ttMatch = RegExp(r'\b[tT][T|t]\b\s*[:=]\s*([0-9]+[.,]?[0-9]*)').firstMatch(text);

    if (rMatch != null) res['R'] = double.tryParse(rMatch.group(1)!.replaceAll(',', '.')) ?? 0;
    if (sMatch != null) res['S'] = double.tryParse(sMatch.group(1)!.replaceAll(',', '.')) ?? 0;
    if (tMatch != null) res['T'] = double.tryParse(tMatch.group(1)!.replaceAll(',', '.')) ?? 0;

    if (trMatch != null) res['tR'] = double.tryParse(trMatch.group(1)!.replaceAll(',', '.')) ?? 0;
    if (tsMatch != null) res['tS'] = double.tryParse(tsMatch.group(1)!.replaceAll(',', '.')) ?? 0;
    if (ttMatch != null) res['tT'] = double.tryParse(ttMatch.group(1)!.replaceAll(',', '.')) ?? 0;

    return res;
  }
}

// ==========================================
// 3. EKİPMAN MODELLERİ
// ==========================================
class BreakerModel {
  final String name;
  final String vendor;
  final String medium;
  final double defaultLimitMicroOhm;
  final double typicalTripTimeMs;
  final String standardCode;

  const BreakerModel(this.name, this.vendor, this.medium, this.defaultLimitMicroOhm, this.typicalTripTimeMs, this.standardCode);
}

const List<BreakerModel> kBreakers = [
  BreakerModel("Schneider FB4 (Fluarc Santral)", "Schneider Electric", "SF6", 32.0, 45.0, "IEC 62271 / IEEE C37"),
  BreakerModel("Schneider SF1 / SF2 (Fluarc)", "Schneider Electric", "SF6", 38.0, 42.0, "IEC 62271-100"),
  BreakerModel("Schneider LF1 / LF2 / LF3", "Schneider Electric", "SF6", 40.0, 42.0, "IEC 62271-100"),
  BreakerModel("Schneider Evolis", "Schneider Electric", "Vacuum", 35.0, 38.0, "IEC 62271-100"),
  BreakerModel("Schneider EasyPact EXE", "Schneider Electric", "Vacuum", 38.0, 40.0, "IEC 62271-100"),
  BreakerModel("Siemens SION 3AE / 3AH", "Siemens", "Vacuum", 45.0, 44.0, "IEC / DIN VDE 0671"),
  BreakerModel("ABB VD4", "ABB", "Vacuum", 38.0, 40.0, "IEC 62271-100"),
  BreakerModel("ABB HD4", "ABB", "SF6", 42.0, 45.0, "IEC 62271-100"),
  BreakerModel("Alstom / Areva HVX", "Alstom", "Vacuum", 46.0, 48.0, "IEC 62271-100"),
  BreakerModel("Ormazabal CPG / CGS", "Ormazabal", "Vacuum", 42.0, 45.0, "IEC 62271-100"),
  BreakerModel("Tavrida BB/TEL (ВВ/TEL ГОСТ)", "Tavrida", "Vacuum", 35.0, 32.0, "ГОСТ Р 52565 / ПУЭ 7"),
  BreakerModel("TEDAŞ Standart Yerli Vakum", "Yerli / TEDAŞ", "Vacuum", 50.0, 45.0, "TEDAŞ-MLZ/96-015"),
];

class SwitchgearModel {
  final String name;
  final String type;
  final String standard;
  const SwitchgearModel(this.name, this.type, this.standard);
}

const List<SwitchgearModel> kSwitchgears = [
  SwitchgearModel("Schneider SM6-36", "AIS", "IEC 62271-200 / TEDAŞ"),
  SwitchgearModel("Schneider Premset (2SI)", "SSIS", "IEC 62271-200"),
  SwitchgearModel("Schneider AirSeT (SF6-Free)", "Pure Air + Vacuum", "IEC 62271-200 / EU F-Gas"),
  SwitchgearModel("Schneider RM6 / FBX", "RMU (GIS)", "IEC 62271-200"),
  SwitchgearModel("Schneider GHA", "GIS", "IEC 62271-200"),
  SwitchgearModel("Schneider MCset / Fluair F400", "Metal-Clad", "IEC 62271-200"),
  SwitchgearModel("Ormazabal CGMcosmos / CGM.3", "RMU / GIS", "IEC 62271-200 / UNE 211026"),
  SwitchgearModel("Ormazabal GAE", "Metal-Enclosed", "IEC 62271-200"),
  SwitchgearModel("Siemens 8BT2 / NXAIR", "Metal-Clad", "IEC 62271-200"),
  SwitchgearModel("Siemens 8DJH / SIMOSEC", "RMU / Compact", "IEC 62271-200"),
  SwitchgearModel("ABB UniGear ZS1 / UniSec", "Metal-Clad / AIS", "IEC 62271-200"),
  SwitchgearModel("ABB SafeRing / SafePlus", "Compact RMU", "IEC 62271-200"),
  SwitchgearModel("Alstom Fluokit M24", "AIS", "IEC 62271-200"),
  SwitchgearModel("Ulusoy HMH-36 / Astor", "AIS", "TEDAŞ MYD/96-015"),
  SwitchgearModel("КРУ / КСО Серия (ГОСТ)", "КРУ/КСО (ЗРУ)", "ГОСТ 14693 / ПУЭ 7"),
  SwitchgearModel("KYN28A-12 / XGN (GB/T)", "Armoured Metal-Clad", "GB/T 3906 / DL/T 404"),
];

class RelayModel {
  final String name;
  final String menuPath;
  final String standardCode;
  const RelayModel(this.name, this.menuPath, this.standardCode);
}

const List<RelayModel> kRelays = [
  RelayModel("Schneider Sepam 20/40/80", "Sepam: Sarı Tuş -> Koruma (50/51) -> Is & TMS", "IEC 60255"),
  RelayModel("Schneider Easergy P3/P5", "Easergy: Settings -> Group 1 -> 51 -> Is & k", "IEC 60255"),
  RelayModel("Siemens Siprotec 4 (7SJ6x)", "Siprotec 4: Settings -> 50/51 -> 51 Pickup & Time Dial", "IEC 60255 / IEEE C37"),
  RelayModel("Siemens Siprotec 5 (7SJ8x)", "Siprotec 5: Group Line -> Overcurrent 51-1", "IEC 60255 / IEEE C37"),
  RelayModel("ABB Relion REF615/620", "REF615: Menu -> Protection -> PHIPTOC1 (51)", "IEC 60255"),
  RelayModel("Alstom MiCOM P122/P123", "MiCOM: Group 1 Current -> I> Set & I> TMS", "IEC 60255"),
  RelayModel("БМРЗ / Сириус (ГОСТ)", "БМРЗ: Уставки -> МТЗ-1/2 -> Ток и время", "ГОСТ Р 59302 (ПУЭ)"),
  RelayModel("Nari / Sifang (国网 GB/T)", "保护定值 -> 过流一段/二段 -> 定值电流与延时", "GB/T 14598 / DL/T"),
  RelayModel("Mitsubishi / Toshiba (JEC)", "設定 -> 過電流(51) -> 限時タップ・レバー", "JEC-2500 / JIS C 4602"),
  RelayModel("Kael / Mikro / Yerli", "Ayarlar -> Koruma -> 51 Eşik ve Eğri", "TEDAŞ / IEC 60255"),
];

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  String ctRatio;
  SwitchgearCell({required this.id, required this.name, required this.type, this.cbClosed = false, this.ctRatio = "400/5A"});
}

class TestRecord {
  final String timestamp;
  final String substation;
  final String breaker;
  final double maxRes;
  final double syncDelta;
  final bool passed;
  TestRecord({required this.timestamp, required this.substation, required this.breaker, required this.maxRes, required this.syncDelta, required this.passed});
}

// ==========================================
// 4. ANA EKRAN KONTROLCÜSÜ (COCKPIT)
// ==========================================
class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});
  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> {
  int _activeTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  int _selectedSwitchgearIdx = 0;
  int _selectedBreakerIdx = 0;
  int _selectedRelayIdx = 0;

  BreakerModel get _activeBreaker => kBreakers[_selectedBreakerIdx];
  RelayModel get _activeRelay => kRelays[_selectedRelayIdx];
  SwitchgearModel get _activeSwitchgear => kSwitchgears[_selectedSwitchgearIdx];

  // Parametreler
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";
  double _testPrimaryCurrent = 1200.0;
  double _ctPrimaryRatio = 400.0;
  double _ctSecondaryRatio = 5.0;

  double _resR = 34.2;
  double _resS = 35.8;
  double _resT = 34.9;
  double _timeR = 41.5;
  double _timeS = 42.8;
  double _timeT = 42.1;
  final List<TestRecord> _testHistory = [];

  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;
  double _workingDistanceMm = 610.0;
  double _ambientTemp = 25.0;
  double _altitudeMeters = 50.0;
  double _relativeHumidity = 55.0;
  String _locationName = "Saha / Çevrimdışı";
  bool _isLoadingWeather = false;

  final List<SwitchgearCell> _cells = [
    SwitchgearCell(id: "C1", name: "H01 TR-1 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
    SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true),
    SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false),
    SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C5", name: "H05 Fider 2", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C6", name: "H06 TR-2 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
  ];

  // Motor Değerleri
  double get _ikKa => ElectricalEngine.calcShortCircuitKa(_voltageKv, _trafoMva, _ukPercent);
  double get _trafoNominalCurrentA => ElectricalEngine.calcNominalCurrentA(_trafoMva, _voltageKv);
  double get _trafoInrushCurrentA => ElectricalEngine.calcInrushCurrentA(_trafoMva, _voltageKv);
  double get _altitudeDeratingKa => ElectricalEngine.calcAltitudeDeratingKa(_altitudeMeters);
  double get _testSecondaryCurrent => _testPrimaryCurrent * (_ctSecondaryRatio / _ctPrimaryRatio);

  // ==========================================
  // %100 EKSİKSİZ 8 DİLLİ SÖZLÜK
  // ==========================================
  String t(String k) {
    const d = {
      // Sekmeler
      'net': {'tr': 'Şebeke & Trafo', 'en': 'Grid & Trafo', 'de': 'Netz & Trafo', 'es': 'Red y Trafo', 'fr': 'Réseau & Transfo', 'zh': '电网与变压器', 'ja': '系統と変圧器', 'ru': 'Сеть и Трансф.'},
      'relay': {'tr': 'Röle & TCC', 'en': 'Relay & TCC', 'de': 'Schutz & TCC', 'es': 'Relé y TCC', 'fr': 'Relais & TCC', 'zh': '保护与TCC曲线', 'ja': 'リレーとTCC', 'ru': 'РЗиА и ВТХ'},
      'sat': {'tr': 'Kesici SAT', 'en': 'CB SAT Test', 'de': 'LS Diagnose', 'es': 'Prueba SAT', 'fr': 'Essais SAT', 'zh': '断路器SAT测试', 'ja': '遮断器SAT試験', 'ru': 'Испытания SAT'},
      'cable': {'tr': 'Kablo & Ark', 'en': 'Cable & Arc', 'de': 'Kabel & Lichtb.', 'es': 'Cable y Arco', 'fr': 'Câble & Arc', 'zh': '电缆与电弧', 'ja': 'ケーブルとアーク', 'ru': 'Кабель и Дуга'},
      'sld': {'tr': 'Şalt & SLD', 'en': 'Switchgear', 'de': 'Schaltanlage', 'es': 'Subestación', 'fr': 'Poste & SLD', 'zh': '一次系统图', 'ja': '単線結線図', 'ru': 'ОРУ/ЗРУ и Схема'},

      // 1. Şebeke & Trafo Sekmesi
      'ik_title': {'tr': '3 FAZ KISA DEVRE AKIMI (Ik\'\')', 'en': '3-PHASE SHORT CIRCUIT (Ik\'\')', 'de': '3-POL. KURZSCHLUSSSTROM (Ik\'\')', 'es': 'CORRIENTE CORTOCIRCUITO 3F (Ik\'\')', 'fr': 'COURANT COURT-CIRCUIT (Ik\'\')', 'zh': '三相短路电流 (Ik\'\')', 'ja': '三相短絡電流 (Ik\'\')', 'ru': 'ТОК ТРЕХФАЗНОГО КЗ (Iк\'\')'},
      'sys_voltage': {'tr': 'Sistem Gerilimi (kV)', 'en': 'System Voltage (kV)', 'de': 'Netzspannung (kV)', 'es': 'Tensión del Sistema (kV)', 'fr': 'Tension du Réseau (kV)', 'zh': '系统额定电压 (kV)', 'ja': '公称系統電圧 (kV)', 'ru': 'Номинальное напряжение (кВ)'},
      'trafo_power': {'tr': 'Trafo Gücü Sn (MVA)', 'en': 'Trafo Power Sn (MVA)', 'de': 'Trafoleistung Sn (MVA)', 'es': 'Potencia Trafo Sn (MVA)', 'fr': 'Puissance Transfo Sn (MVA)', 'zh': '变压器容量 Sn (MVA)', 'ja': '変圧器容量 Sn (MVA)', 'ru': 'Мощность трансф. Sn (МВА)'},
      'trafo_uk': {'tr': 'Kısa Devre Empedansı (%uk)', 'en': 'Impedance Voltage (%uk)', 'de': 'Kurzschlussspannung (%uk)', 'es': 'Impedancia (%uk)', 'fr': 'Tension Court-Circuit (%uk)', 'zh': '阻抗电压 (%uk)', 'ja': '短絡インピーダンス (%uk)', 'ru': 'Напряжение КЗ (%uk)'},
      'climate_title': {'tr': 'Saha İklim & Rakım Düzeltmesi (IEC 62271-1)', 'en': 'Field Climate & Altitude Derating', 'de': 'Klima & Höhenkorrektur', 'es': 'Clima y Altitud', 'fr': 'Climat & Altitude', 'zh': '现场气候与高海拔绝缘修正', 'ja': '気候と標高補正', 'ru': 'Климат и высота над уровнем моря'},
      'fetch_ip': {'tr': 'Ağ/IP Konumunu Al', 'en': 'Fetch IP Location', 'de': 'IP-Standort abrufen', 'es': 'Obtener Ubicación IP', 'fr': 'Obtenir Position IP', 'zh': '通过网络获取大致位置', 'ja': 'IP経由で位置取得', 'ru': 'Определить по сети'},
      'quick_presets': {'tr': 'Hızlı Şalt Şablonları:', 'en': 'Quick Templates:', 'de': 'Schnellvorlagen:', 'es': 'Plantillas Rápidas:', 'fr': 'Modèles Rapides:', 'zh': '快速预设:', 'ja': 'クイック設定:', 'ru': 'Быстрые шаблоны:'},
      'alt_warning_high': {'tr': '• DİKKAT: Rakım > 1000m. Yalıtım test seviyesi Ka ile artırılmalı!', 'en': '• WARNING: Altitude > 1000m. Insulation level must be increased by Ka!', 'de': '• ACHTUNG: Höhe > 1000m. Isolationspegel muss um Ka erhöht werden!', 'es': '• ATENCIÓN: Altitud > 1000m. Nivel de aislamiento debe aumentarse por Ka!', 'fr': '• ATTENTION: Altitude > 1000m. Niveau d\'isolement à majorer par Ka!', 'zh': '• 注意: 海拔 > 1000m。外绝缘耐受电压必须按 Ka 修正增加！', 'ja': '• 注意: 標高1000m超。絶縁耐力をKa係数で補正する必要があります！', 'ru': '• ВНИМАНИЕ: Высота > 1000м. Испытательное напряжение изоляции должно быть увеличено на Ka!'},
      'alt_ok': {'tr': '• Rakım ≤ 1000m (Ka = 1.000). Standart fabrika dielektrik testleri geçerlidir.', 'en': '• Altitude ≤ 1000m (Ka = 1.000). Standard factory dielectric ratings apply.', 'de': '• Höhe ≤ 1000m (Ka = 1.000). Standard-Isolationspegel gültig.', 'es': '• Altitud ≤ 1000m (Ka = 1.000). Ensayos dieléctricos estándar válidos.', 'fr': '• Altitude ≤ 1000m (Ka = 1.000). Niveaux d\'isolement standard applicables.', 'zh': '• 海拔 ≤ 1000m (Ka = 1.000)。适用标准出厂绝缘试验水平。', 'ja': '• 標高 ≤ 1000m (Ka = 1.000)。標準の工場絶縁試験電圧が適用されます。', 'ru': '• Высота ≤ 1000м (Ka = 1.000). Применяются стандартные заводские нормы испытаний.'},

      // 2. Röle Sekmesi
      'margin_title': {'tr': 'SELEKTİVİTE MARJİNİ (Δt)', 'en': 'SELECTIVITY MARGIN (Δt)', 'de': 'STAFFELZEITSPANNE (Δt)', 'es': 'MARGEN SELECTIVIDAD (Δt)', 'fr': 'MARGE DE SÉLECTIVITÉ (Δt)', 'zh': '级差配合时间 (Δt)', 'ja': '協調時間差 (Δt)', 'ru': 'СТУПЕНЬ СЕЛЕКТИВНОСТИ (Δt)'},
      'tcc_chart_title': {'tr': 'LOG-LOG RÖLE KOORDİNASYON EĞRİSİ (TCC)', 'en': 'LOG-LOG COORDINATION CURVE (TCC)', 'de': 'LOG-LOG STAFFELPLAN (TCC)', 'es': 'CURVA DE COORDINACIÓN (TCC)', 'fr': 'COURBE LOG-LOG (TCC)', 'zh': '双对数保护配合曲线 (TCC)', 'ja': '対数座標系 保護協調曲線 (TCC)', 'ru': 'ВТХ КАРТА СЕЛЕКТИВНОСТИ'},
      'selective_ok': {'tr': 'SELEKTİF (IEC/GOST/GB Δt ≥ 300ms)', 'en': 'SELECTIVE (IEC/GOST/GB Δt ≥ 300ms)', 'de': 'SELEKTIV (Δt ≥ 300ms)', 'es': 'SELECTIVO (Δt ≥ 300ms)', 'fr': 'SÉLECTIF (Δt ≥ 300ms)', 'zh': '选择性配合良好 (Δt ≥ 300ms)', 'ja': '選択協調成立 (Δt ≥ 300ms)', 'ru': 'СЕЛЕКТИВНО (Δt ≥ 300мс)'},
      'selective_risk': {'tr': 'ÇAKIŞMA RİSKİ (Δt < 300ms)', 'en': 'MISCOORDINATION RISK (Δt < 300ms)', 'de': 'STAFFELFEHLER-RISIKO (Δt < 300ms)', 'es': 'RIESGO DE SOLAPAMIENTO (Δt < 300ms)', 'fr': 'RISQUE DE DÉCLENCHEMENT INTEMPESTIF', 'zh': '级差不足越级跳闸风险 (Δt < 300ms)', 'ja': '協調マージン不足 (Δt < 300ms)', 'ru': 'НЕСЕЛЕКТИВНО (Δt < 300мс)'},
      'up_relay_title': {'tr': 'Upstream (Giriş) Rölesi', 'en': 'Upstream (Incomer) Relay', 'de': 'Übergeordnetes Schutzrelais', 'es': 'Relé Aguas Arriba (Entrada)', 'fr': 'Relais Amont (Arrivée)', 'zh': '上级进线保护装置', 'ja': '上位（受電）保護リレー', 'ru': 'Вышестоящее реле (Ввод)'},
      'down_relay_title': {'tr': 'Downstream (Fider) Rölesi', 'en': 'Downstream (Feeder) Relay', 'de': 'Untergeordnetes Schutzrelais', 'es': 'Relé Aguas Abajo (Salida)', 'fr': 'Relais Aval (Départ)', 'zh': '下级出线保护装置', 'ja': '下位（フィーダー）保護リレー', 'ru': 'Нижестоящее реле (Отходящая)'},
      'up_is': {'tr': 'Giriş Eşik Akımı Is (A)', 'en': 'Incomer Pickup Is (A)', 'de': 'Ansprechstrom Is (A)', 'es': 'Corriente Arranque Is (A)', 'fr': 'Courant de Seuil Is (A)', 'zh': '进线动作定值 Is (A)', 'ja': '受電整定電流 Is (A)', 'ru': 'Ток срабатывания Is (А)'},
      'up_tms': {'tr': 'Giriş Zaman Çarpanı (TMS)', 'en': 'Incomer Time Dial (TMS)', 'de': 'Zeitfaktor (TMS)', 'es': 'Multiplicador Tiempo (TMS)', 'fr': 'Facteur de Temps (TMS)', 'zh': '进线时间乘数 (TMS)', 'ja': '受電タイムレバー (TMS)', 'ru': 'Множитель времени (TMS)'},
      'down_is': {'tr': 'Fider Eşik Akımı Is (A)', 'en': 'Feeder Pickup Is (A)', 'de': 'Abgang Ansprechstrom (A)', 'es': 'Fíder Arranque Is (A)', 'fr': 'Départ Seuil Is (A)', 'zh': '出线动作定值 Is (A)', 'ja': 'フィーダー整定電流 (A)', 'ru': 'Фидер Ток сраб. Is (А)'},
      'down_tms': {'tr': 'Fider Zaman Çarpanı (TMS)', 'en': 'Feeder Time Dial (TMS)', 'de': 'Abgang Zeitfaktor (TMS)', 'es': 'Fíder Multiplicador (TMS)', 'fr': 'Départ Facteur Temps (TMS)', 'zh': '出线时间乘数 (TMS)', 'ja': 'フィーダータイムレバー (TMS)', 'ru': 'Фидер Множитель (TMS)'},

      // 3. SAT Sekmesi
      'sat_hud_title': {'tr': 'SAT TEŞHİS', 'en': 'SAT DIAGNOSTICS', 'de': 'SAT DIAGNOSE', 'es': 'DIAGNÓSTICO SAT', 'fr': 'DIAGNOSTIC SAT', 'zh': '现场验收诊断 (SAT)', 'ja': 'SAT試験診断', 'ru': 'ДИАГНОСТИКА SAT'},
      'sat_pass': {'tr': 'TESTTEN GEÇTİ (PASS)', 'en': 'TEST PASSED', 'de': 'BESTANDEN (PASS)', 'es': 'APROBADO (PASS)', 'fr': 'TEST VALIDE (PASS)', 'zh': '验收合格 (PASS)', 'ja': '合格 (PASS)', 'ru': 'ГОДЕН (PASS)'},
      'sat_fail': {'tr': 'KUSURLU (FAIL)', 'en': 'TEST FAILED', 'de': 'FEHLERHAFT (FAIL)', 'es': 'RECHAZADO (FAIL)', 'fr': 'ÉCHEC (FAIL)', 'zh': '不合格 (FAIL)', 'ja': '不合格 (FAIL)', 'ru': 'ДЕФЕКТ (FAIL)'},
      'gear_select': {'tr': 'Şalt Hücresi Tipi:', 'en': 'Switchgear Bay Type:', 'de': 'Schaltfeld-Typ:', 'es': 'Tipo de Celda:', 'fr': 'Type de Tableau HTA:', 'zh': '开关柜型号:', 'ja': 'スイッチギア形式:', 'ru': 'Тип ячейки КРУ/КСО:'},
      'breaker_select': {'tr': 'Kesici Modeli & Ortamı:', 'en': 'Breaker Model & Medium:', 'de': 'Leistungsschalter-Typ:', 'es': 'Modelo Interruptor:', 'fr': 'Disjoncteur HTA:', 'zh': '断路器型号与介质:', 'ja': '遮断器形式・消弧媒体:', 'ru': 'Выключатель и среда:'},
      'relay_select': {'tr': 'Koruma Rölesi & Standart:', 'en': 'Protection Relay & Std:', 'de': 'Schutzrelais & Norm:', 'es': 'Relé de Protección:', 'fr': 'Relais de Protection:', 'zh': '微机保护装置与标准:', 'ja': '保護継電器・準拠規格:', 'ru': 'Реле защиты и стандарт:'},
      'cibano_btn': {'tr': 'CIBANO/Test Verisi', 'en': 'CIBANO/Test Data', 'de': 'CIBANO Prüfdaten', 'es': 'Datos CIBANO', 'fr': 'Données CIBANO', 'zh': '粘贴CIBANO数据', 'ja': '試験器データ貼付', 'ru': 'Вставить из CIBANO'},
      'report_btn': {'tr': 'Raporu Aç & Paylaş', 'en': 'View & Share Report', 'de': 'Bericht anzeigen', 'es': 'Ver y Compartir', 'fr': 'Voir et Partager', 'zh': '生成并分享报告', 'ja': '成績書作成・共有', 'ru': 'Протокол и экспорт'},
      'res_title': {'tr': 'R-S-T Kontak Geçiş Dirençleri (µΩ)', 'en': 'R-S-T Contact Resistance (µΩ)', 'de': 'R-S-T Übergangswiderstände (µΩ)', 'es': 'Resistencia de Contacto R-S-T (µΩ)', 'fr': 'Résistance de Contact R-S-T (µΩ)', 'zh': 'R-S-T 三相主触头导电回路电阻 (µΩ)', 'ja': 'R-S-T 主回路接触抵抗 (µΩ)', 'ru': 'Переходное сопротивление R-S-T (мкОм)'},
      'res_r': {'tr': 'R Kutbu Direnci (µΩ)', 'en': 'Pole R Resistance (µΩ)', 'de': 'Pol R Widerstand (µΩ)', 'es': 'Polo R Resistencia (µΩ)', 'fr': 'Résistance Pôle R (µΩ)', 'zh': 'A/R 相回路电阻 (µΩ)', 'ja': 'R相主回路接触抵抗 (µΩ)', 'ru': 'Сопротивление полюса R (мкОм)'},
      'res_s': {'tr': 'S Kutbu Direnci (µΩ)', 'en': 'Pole S Resistance (µΩ)', 'de': 'Pol S Widerstand (µΩ)', 'es': 'Polo S Resistencia (µΩ)', 'fr': 'Résistance Pôle S (µΩ)', 'zh': 'B/S 相回路电阻 (µΩ)', 'ja': 'S相主回路接触抵抗 (µΩ)', 'ru': 'Сопротивление полюса S (мкОм)'},
      'res_t': {'tr': 'T Kutbu Direnci (µΩ)', 'en': 'Pole T Resistance (µΩ)', 'de': 'Pol T Widerstand (µΩ)', 'es': 'Polo T Resistencia (µΩ)', 'fr': 'Résistance Pôle T (µΩ)', 'zh': 'C/T 相回路电阻 (µΩ)', 'ja': 'T相主回路接触抵抗 (µΩ)', 'ru': 'Сопротивление полюса T (мкОм)'},
      'time_title': {'tr': 'Açma Süresi & Kutuplar Arası Senkronizm (ms)', 'en': 'Opening Time & Pole Synchronism (ms)', 'de': 'Ausschaltzeit & Gleichzeitigkeit (ms)', 'es': 'Tiempo Apertura y Sincronismo (ms)', 'fr': 'Temps d\'Ouverture et Synchronisme (ms)', 'zh': '分闸固有时间与三相同期性 (ms)', 'ja': '開閉時間及び相間同期性 (ms)', 'ru': 'Время отключения и разновременность (мс)'},
      'time_r': {'tr': 'tR Açma Zamanı (ms)', 'en': 'tR Trip Time (ms)', 'de': 'tR Ausschaltzeit (ms)', 'es': 'tR Tiempo (ms)', 'fr': 'tR Temps (ms)', 'zh': 'A/R 相分闸时间 (ms)', 'ja': 'R相遮断時間 (ms)', 'ru': 'tR Время откл. (мс)'},
      'time_s': {'tr': 'tS Açma Zamanı (ms)', 'en': 'tS Trip Time (ms)', 'de': 'tS Ausschaltzeit (ms)', 'es': 'tS Tiempo (ms)', 'fr': 'tS Temps (ms)', 'zh': 'B/S 相分闸时间 (ms)', 'ja': 'S相遮断時間 (ms)', 'ru': 'tS Время откл. (мс)'},
      'time_t': {'tr': 'tT Açma Zamanı (ms)', 'en': 'tT Trip Time (ms)', 'de': 'tT Ausschaltzeit (ms)', 'es': 'tT Tiempo (ms)', 'fr': 'tT Temps (ms)', 'zh': 'C/T 相分闸时间 (ms)', 'ja': 'T相遮断時間 (ms)', 'ru': 'tT Время откл. (мс)'},
      'sync_ok': {'tr': 'Senkronizm Uygun (Δt ≤ 3ms)', 'en': 'Synchronism Compliant (Δt ≤ 3ms)', 'de': 'Gleichzeitigkeit i.O. (Δt ≤ 3ms)', 'es': 'Sincronismo Conforme (Δt ≤ 3ms)', 'fr': 'Synchronisme Conforme (Δt ≤ 3ms)', 'zh': '同期性符合规范 (Δt ≤ 3ms)', 'ja': '同期性適合 (Δt ≤ 3ms)', 'ru': 'Синхронность в норме (Δt ≤ 3мс)'},
      'sync_fail': {'tr': 'Senkronizm Hatası (Δt > 3ms)', 'en': 'Synchronism Violation (Δt > 3ms)', 'de': 'Gleichzeitigkeit verletzt (Δt > 3ms)', 'es': 'Fallo de Sincronismo (Δt > 3ms)', 'fr': 'Défaut de Synchronisme (Δt > 3ms)', 'zh': '同期性超标警告 (Δt > 3ms)', 'ja': '相間不揃い異常 (Δt > 3ms)', 'ru': 'Недопустимая разновременность!'},
      'history_title': {'tr': 'Kayıtlı Test Geçmişi', 'en': 'Saved Test History', 'de': 'Gespeicherte Historie', 'es': 'Historial Guardado', 'fr': 'Historique Enregistré', 'zh': '历史试验记录', 'ja': '保存済み試験履歴', 'ru': 'Архив испытаний'},

      // 4. Kablo Sekmesi
      'cable_hud_title': {'tr': 'ADYABATİK KABLO TAHKİKİ', 'en': 'ADIABATIC SIZING', 'de': 'ADIABATISCHE AUSLEGUNG', 'es': 'CÁLCULO ADIABÁTICO', 'fr': 'DIMENSIONNEMENT ADIABATIQUE', 'zh': '热稳定截面校验 (绝热)', 'ja': '短絡熱容量照査', 'ru': 'ТЕРМИЧЕСКАЯ СТОЙКОСТЬ'},
      'selected_section': {'tr': 'Seçilen Kesit (mm²)', 'en': 'Selected Cross-Section (mm²)', 'de': 'Gewählter Querschnitt (mm²)', 'es': 'Sección Elegida (mm²)', 'fr': 'Section Choisie (mm²)', 'zh': '选用电缆截面 (mm²)', 'ja': '選定ケーブル断面積 (mm²)', 'ru': 'Сечение кабеля (мм²)'},
      'line_length': {'tr': 'Hat Boyu (m)', 'en': 'Line Length (m)', 'de': 'Leitungslänge (m)', 'es': 'Longitud Línea (m)', 'fr': 'Longueur Ligne (m)', 'zh': '线路长度 (m)', 'ja': 'こう長 (m)', 'ru': 'Длина линии (м)'},
      'load_current': {'tr': 'Yük Akımı (A)', 'en': 'Load Current (A)', 'de': 'Laststrom (A)', 'es': 'Corriente Carga (A)', 'fr': 'Courant de Charge (A)', 'zh': '负荷电流 (A)', 'ja': '負荷電流 (A)', 'ru': 'Ток нагрузки (А)'},
      'arc_distance': {'tr': 'Ark Mesafesi (mm)', 'en': 'Arc Distance (mm)', 'de': 'Lichtbogenabstand (mm)', 'es': 'Distancia de Arco (mm)', 'fr': 'Distance Éclair d\'Arc (mm)', 'zh': '电弧作业距离 (mm)', 'ja': 'アーク作業距離 (mm)', 'ru': 'Расстояние до дуги (мм)'},

      // Saha Kılavuzu Başlıkları
      'guide_logic': {'tr': '1. Mühendislik Mantığı', 'en': '1. Engineering Logic', 'de': '1. Technische Logik', 'es': '1. Lógica Técnica', 'fr': '1. Logique Technique', 'zh': '1. 工程计算原理', 'ja': '1. 工学理論と計算根拠', 'ru': '1. Инженерный принцип'},
      'guide_where': {'tr': '2. Sahada Nereye Bakılır?', 'en': '2. Where to look on site?', 'de': '2. Wo vor Ort prüfen?', 'es': '2. ¿Dónde mirar en campo?', 'fr': '2. Où regarder sur site ?', 'zh': '2. 现场实物铭牌位置', 'ja': '2. 現地確認箇所・銘板位置', 'ru': '2. Где смотреть на объекте?'},
      'guide_menu': {'tr': '3. Cihaz Menü Yolu', 'en': '3. Device Menu Path', 'de': '3. Gerätemenüpfad', 'es': '3. Ruta Menú Equipo', 'fr': '3. Navigation Menu', 'zh': '3. 装置内部菜单路径', 'ja': '3. リレー画面メニュー遷移', 'ru': '3. Меню устройства'},
      'guide_std': {'tr': '4. Standart & Kural', 'en': '4. Standard & Rule', 'de': '4. Normen & Regeln', 'es': '4. Norma y Criterio', 'fr': '4. Norme & Règle', 'zh': '4. 遵循国际标准规范', 'ja': '4. 適用規格・合否判定基準', 'ru': '4. Нормативный стандарт'},
      'understand_btn': {'tr': 'Anladım, Kapat', 'en': 'Understood, Close', 'de': 'Verstanden, Schließen', 'es': 'Entendido, Cerrar', 'fr': 'Compris, Fermer', 'zh': '了解并关闭', 'ja': '確認して閉じる', 'ru': 'Понятно, закрыть'},
    };
    return d[k]?[_lang.name] ?? d[k]?['en'] ?? k;
  }

  // ==========================================
  // SAHA KILAVUZU POPUP MOTORU (FIELD GUIDE)
  // ==========================================
  void _showFieldGuide(String titleKey, String logicKey, String whereKey, String stdKey) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151921),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFFFB300), size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text(t(titleKey), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)))),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 20),
            _buildGuideItem(t('guide_logic'), t(logicKey)),
            _buildGuideItem(t('guide_where'), t(whereKey)),
            _buildGuideItem("${t('guide_menu')} (${_activeRelay.name})", _activeRelay.menuPath, isHighlight: true),
            _buildGuideItem(t('guide_std'), t(stdKey)),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('understand_btn'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideItem(String heading, String content, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isHighlight ? const Color(0xFFFFB300) : Colors.grey)),
          const SizedBox(height: 2),
          Text(content, style: TextStyle(fontSize: 12, color: isHighlight ? Colors.white : Colors.white70, height: 1.3)),
        ],
      ),
    );
  }

  // --- İNTERNETTEN AĞ/IP KONUMU ALMA ---
  Future<void> _fetchNetworkLocation() async {
    setState(() => _isLoadingWeather = true);
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5)..userAgent = "PowerFieldPro/3.2";
      final r = await client.getUrl(Uri.parse('https://ipwho.is/'));
      final res = await r.close();
      if (res.statusCode == 200) {
        final b = jsonDecode(await res.transform(utf8.decoder).join());
        if (b['success'] == true) {
          final lat = (b['latitude'] as num).toDouble();
          final lon = (b['longitude'] as num).toDouble();
          final city = b['city'] ?? "Saha";

          final wUri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m&elevation=nan');
          final wReq = await client.getUrl(wUri);
          final wRes = await wReq.close();
          if (wRes.statusCode == 200) {
            final wData = jsonDecode(await wRes.transform(utf8.decoder).join());
            setState(() {
              _locationName = "$city (${b['country_code']}) [IP]";
              _ambientTemp = (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? _ambientTemp;
              _relativeHumidity = (wData['current']?['relative_humidity_2m'] as num?)?.toDouble() ?? _relativeHumidity;
              _altitudeMeters = (wData['elevation'] as num?)?.toDouble() ?? _altitudeMeters;
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: const Color(0xFF00E676), content: Text("✓ $_locationName | ${_altitudeMeters.toInt()}m")),
              );
            }
            return;
          }
        }
      }
      throw Exception();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFFF3D00), content: Text("Ağ bağlantısı kurulamadı. Şablon şehirleri kullanabilirsiniz.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  void _applyCityPreset(String name, double temp, double alt, double humidity) {
    setState(() {
      _locationName = name;
      _ambientTemp = temp;
      _altitudeMeters = alt;
      _relativeHumidity = humidity;
    });
  }

  // --- CIBANO PARSER DİYALOĞU ---
  void _showCibanoPasteDialog() {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151921),
        title: const Row(
          children: [
            Icon(Icons.content_paste, color: Color(0xFFFFB300)),
            SizedBox(width: 8),
            Text("CIBANO/Omicron Parser", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("R, S, T ve tR, tS, tT değerlerini içeren test çıktısını yapıştırın:", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: tc,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Örn: R: 34.2 uOhm, S: 35.8 uOhm, T: 34.9 uOhm\ntR: 41.5 ms, tS: 42.8 ms, tT: 42.1 ms",
                hintStyle: TextStyle(fontSize: 11, color: Colors.white30),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
            onPressed: () {
              final parsed = CibanoParser.parse(tc.text);
              setState(() {
                if (parsed.containsKey('R')) _resR = parsed['R']!;
                if (parsed.containsKey('S')) _resS = parsed['S']!;
                if (parsed.containsKey('T')) _resT = parsed['T']!;
                if (parsed.containsKey('tR')) _timeR = parsed['tR']!;
                if (parsed.containsKey('tS')) _timeS = parsed['tS']!;
                if (parsed.containsKey('tT')) _timeT = parsed['tT']!;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF00E676), content: Text("✓ Test verileri güvenle aktarıldı!")));
            },
            child: const Text("Ayrıştır"),
          ),
        ],
      ),
    );
  }

  // --- KÜRESEL SAT PROTOKOL RAPORU & PANOYA KOPYALAMA ---
  void _showOfficialSatPdfReport() {
    final limit = _activeBreaker.defaultLimitMicroOhm;
    final maxRes = max(_resR, max(_resS, _resT));
    final minRes = min(_resR, min(_resS, _resT));
    final avgRes = (_resR + _resS + _resT) / 3.0;
    final resAsym = avgRes > 0 ? ((maxRes - minRes) / avgRes) * 100.0 : 0.0;
    final isResOk = maxRes <= limit;
    final isAsymOk = resAsym <= 15.0;

    final deltaSyncMs = [(_timeR - _timeS).abs(), (_timeS - _timeT).abs(), (_timeR - _timeT).abs()].reduce(max);
    final isSyncOk = deltaSyncMs <= 3.0;
    final isOverallPass = isResOk && isAsymOk && isSyncOk;

    final record = TestRecord(
      timestamp: "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')} - ${DateTime.now().day}/${DateTime.now().month}",
      substation: "$_voltageKv kV Şalt",
      breaker: _activeBreaker.name,
      maxRes: maxRes,
      syncDelta: deltaSyncMs,
      passed: isOverallPass,
    );
    setState(() => _testHistory.insert(0, record));

    final reportString = """
========================================
⚡ POWERFIELD PRO - SAT COMMISSIONING REPORT
========================================
Timestamp: ${record.timestamp}
Result: ${isOverallPass ? 'PASS / ГОДЕН' : 'FAIL / ДЕФЕКТ'}
Location / Alt: $_locationName (Alt: ${_altitudeMeters.toInt()}m, Ka: ${_altitudeDeratingKa.toStringAsFixed(3)})
Switchgear: ${_activeSwitchgear.name} (${_activeSwitchgear.type})
Circuit Breaker: ${_activeBreaker.name} [${_activeBreaker.medium}]
Protection Relay: ${_activeRelay.name}

1. CONTACT RESISTANCE (DUCTOR - µΩ):
• Phase R: ${_resR.toStringAsFixed(1)} µΩ | Phase S: ${_resS.toStringAsFixed(1)} µΩ | Phase T: ${_resT.toStringAsFixed(1)} µΩ
• Max Measured: ${maxRes.toStringAsFixed(1)} µΩ (Limit: ≤ ${limit.toInt()} µΩ)
• Phase Asymmetry: %${resAsym.toStringAsFixed(1)} (Max limit: ≤ %15)

2. TIMING & POLE SYNCHRONISM (ms):
• Trip Times: tR=${_timeR.toStringAsFixed(1)}ms, tS=${_timeS.toStringAsFixed(1)}ms, tT=${_timeT.toStringAsFixed(1)}ms
• Discrepancy (Δt): ${deltaSyncMs.toStringAsFixed(1)} ms (IEC/GOST/GB Limit: ≤ 3.0 ms)
========================================
Standards: ${_activeBreaker.standardCode} & ${_activeSwitchgear.standard}
""";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151921),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("SAT COMMISSIONING PROTOCOL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFFFB300))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: isOverallPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00), borderRadius: BorderRadius.circular(4)),
                    child: Text(isOverallPass ? "PASS / ГОДЕН" : "FAIL / ДЕФЕКТ", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF30363D), height: 20),
              _buildReportRow("Norm / Standard", "${_activeBreaker.standardCode} & ${_activeSwitchgear.standard}"),
              _buildReportRow("Location / Alt", "$_locationName (Alt: ${_altitudeMeters.toInt()}m, Ka: ${_altitudeDeratingKa.toStringAsFixed(3)})"),
              _buildReportRow("Switchgear", "${_activeSwitchgear.name} [${_activeSwitchgear.type}]"),
              _buildReportRow("Breaker", "${_activeBreaker.name} (${_activeBreaker.medium})"),
              _buildReportRow("Relay", "${_activeRelay.name} [${_activeRelay.standardCode}]"),
              const Divider(color: Color(0xFF30363D), height: 20),
              const Text("1. CONTACT RESISTANCE (µΩ)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text("• Phase R: ${_resR.toStringAsFixed(1)} µΩ | Phase S: ${_resS.toStringAsFixed(1)} µΩ | Phase T: ${_resT.toStringAsFixed(1)} µΩ"),
              Text("• Max: ${maxRes.toStringAsFixed(1)} µΩ (Limit: ≤ ${limit.toInt()} µΩ) | Asym: %${resAsym.toStringAsFixed(1)}"),
              const SizedBox(height: 10),
              const Text("2. TIMING & SYNCHRONISM (ms)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text("• tR=${_timeR.toStringAsFixed(1)}ms | tS=${_timeS.toStringAsFixed(1)}ms | tT=${_timeT.toStringAsFixed(1)}ms"),
              Text("• Pole Discrepancy (Δt): ${deltaSyncMs.toStringAsFixed(1)} ms (Limit: ≤ 3.0 ms)"),
              const Divider(color: Color(0xFF30363D), height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 44)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text("Metni Kopyala (WhatsApp / Email)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: reportString));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF00E676), content: Text("✓ Rapor kopyalandı!")));
                },
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF151921),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFFFB300), size: 24),
            SizedBox(width: 8),
            Text('POWERFIELD PRO v3.2', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 15)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF30363D)), borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<AppLanguage>(
              value: _lang,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF151921),
              items: const [
                DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.es, child: Text('ES 🇪🇸', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.fr, child: Text('FR 🇫🇷', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.zh, child: Text('ZH 🇨🇳', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.ja, child: Text('JA 🇯🇵', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: AppLanguage.ru, child: Text('RU 🇷🇺', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (l) => setState(() => _lang = l!),
            ),
          )
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF151921),
        indicatorColor: const Color(0xFFFFB300).withValues(alpha: 0.25),
        selectedIndex: _activeTab,
        onDestinationSelected: (i) => setState(() => _activeTab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.power_input), label: t('net')),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: t('relay')),
          NavigationDestination(icon: const Icon(Icons.fact_check_outlined), label: t('sat')),
          NavigationDestination(icon: const Icon(Icons.cable), label: t('cable')),
          NavigationDestination(icon: const Icon(Icons.schema), label: t('sld')),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_activeTab) {
      case 0: return _buildGridTab();
      case 1: return _buildRelayAndTccTab();
      case 2: return _buildBreakerDiagnosticsTab();
      case 3: return _buildCableArcTab();
      case 4: return _buildSwitchgearSldTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // SEKME 0: ŞEBEKE, TRAFO & KÜRESEL İKLİM
  // ==========================================
  Widget _buildGridTab() {
    final inA = _trafoNominalCurrentA;
    final inrushA = _trafoInrushCurrentA;
    final isAltitudeHigh = _altitudeMeters > 1000;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          t('ik_title'),
          "${_ikKa.toStringAsFixed(2)} kA",
          "In: ${inA.toStringAsFixed(1)} A | Inrush (10xIn): ${inrushA.toStringAsFixed(0)} A",
          onInfoTap: () => _showFieldGuide(
            'ik_title',
            'guide_logic',
            'guide_where',
            'guide_std',
          ),
        ),
        const SizedBox(height: 14),
        _buildEditableSlider(
          t('sys_voltage'), _voltageKv, 0.4, 36.0, (v) => setState(() => _voltageKv = v),
          infoTap: () => _showFieldGuide('sys_voltage', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        _buildEditableSlider(
          t('trafo_power'), _trafoMva, 0.1, 40.0, (v) => setState(() => _trafoMva = v),
          infoTap: () => _showFieldGuide('trafo_power', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        _buildEditableSlider(
          t('trafo_uk'), _ukPercent, 3.0, 14.0, (v) => setState(() => _ukPercent = v),
          infoTap: () => _showFieldGuide('trafo_uk', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('climate_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "$_locationName\n${_ambientTemp.toStringAsFixed(1)}°C / ${_altitudeMeters.toInt()}m / %${_relativeHumidity.toInt()}",
                      style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    icon: _isLoadingWeather ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.wifi, size: 14),
                    label: Text(t('fetch_ip'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    onPressed: _isLoadingWeather ? null : _fetchNetworkLocation,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(t('quick_presets'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ActionChip(label: const Text("İzmir (34.5kV / 25m)", style: TextStyle(fontSize: 9)), onPressed: () => _applyCityPreset("İzmir (TEDAŞ)", 30.0, 25.0, 65.0)),
                  ActionChip(label: const Text("Moscow (10kV / 150m)", style: TextStyle(fontSize: 9)), onPressed: () => _applyCityPreset("Москва (ГОСТ)", 18.0, 150.0, 60.0)),
                  ActionChip(label: const Text("Beijing (10kV / 45m)", style: TextStyle(fontSize: 9)), onPressed: () => _applyCityPreset("北京 (GB/T)", 26.0, 45.0, 55.0)),
                  ActionChip(label: const Text("Tokyo (6.6kV / 20m)", style: TextStyle(fontSize: 9)), onPressed: () => _applyCityPreset("Tokyo (JEC)", 24.0, 20.0, 70.0)),
                  ActionChip(label: const Text("Erzurum (1890m)", style: TextStyle(fontSize: 9)), onPressed: () => _applyCityPreset("Erzurum Yüksek İrtifa", 12.0, 1890.0, 45.0)),
                ],
              ),
              const Divider(color: Color(0xFF30363D)),
              Text(
                isAltitudeHigh ? t('alt_warning_high') : t('alt_ok'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isAltitudeHigh ? Colors.redAccent : Colors.greenAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 1: RÖLE KOORDİNASYONU & TCC EĞRİSİ
  // ==========================================
  Widget _buildRelayAndTccTab() {
    final faultA = _ikKa * 1000.0;
    final tUp = ElectricalEngine.calcTripTime(faultA, _upIs, _upTms, _upCurve);
    final tDown = ElectricalEngine.calcTripTime(faultA, _downIs, _downTms, _downCurve);
    final deltaT = (tUp.isFinite && tDown.isFinite) ? (tUp - tDown) : 0.0;
    final isSelective = deltaT >= 0.30;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          t('margin_title'),
          "${(deltaT * 1000).toStringAsFixed(0)} ms",
          isSelective ? t('selective_ok') : t('selective_risk'),
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide('margin_title', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('tcc_chart_title'),
          child: Column(
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
                child: CustomPaint(
                  painter: LogLogTccPainter(
                    upIs: _upIs,
                    upTms: _upTms,
                    upCurve: _upCurve,
                    downIs: _downIs,
                    downTms: _downTms,
                    downCurve: _downCurve,
                    faultA: faultA,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.circle, color: Color(0xFFFF3D00), size: 10),
                  const SizedBox(width: 4),
                  Text(t('up_relay_title'), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(width: 14),
                  const Icon(Icons.circle, color: Color(0xFF00E676), size: 10),
                  const SizedBox(width: 4),
                  Text(t('down_relay_title'), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('up_relay_title'),
          child: Column(
            children: [
              _buildEditableSlider(
                t('up_is'), _upIs, 50, 3000, (v) => setState(() => _upIs = v),
                infoTap: () => _showFieldGuide('up_is', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('up_tms'), _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v),
                infoTap: () => _showFieldGuide('up_tms', 'guide_logic', 'guide_where', 'guide_std'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          title: t('down_relay_title'),
          child: Column(
            children: [
              _buildEditableSlider(
                t('down_is'), _downIs, 20, 1500, (v) => setState(() => _downIs = v),
                infoTap: () => _showFieldGuide('down_is', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('down_tms'), _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v),
                infoTap: () => _showFieldGuide('down_tms', 'guide_logic', 'guide_where', 'guide_std'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 2: KESİCİ SAT TEŞHİS & TEST GEÇMİŞİ
  // ==========================================
  Widget _buildBreakerDiagnosticsTab() {
    final limit = _activeBreaker.defaultLimitMicroOhm;
    final maxRes = max(_resR, max(_resS, _resT));
    final minRes = min(_resR, min(_resS, _resT));
    final avgRes = (_resR + _resS + _resT) / 3.0;
    final resAsym = avgRes > 0 ? ((maxRes - minRes) / avgRes) * 100.0 : 0.0;
    final isResOk = maxRes <= limit;
    final isAsymOk = resAsym <= 15.0;

    final deltaSyncMs = [(_timeR - _timeS).abs(), (_timeS - _timeT).abs(), (_timeR - _timeT).abs()].reduce(max);
    final isSyncOk = deltaSyncMs <= 3.0;
    final isOverallPass = isResOk && isAsymOk && isSyncOk;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: "${_activeSwitchgear.standard} | ${_activeBreaker.standardCode}",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('gear_select'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedSwitchgearIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kSwitchgears.length, (i) => DropdownMenuItem(value: i, child: Text("${kSwitchgears[i].name} (${kSwitchgears[i].type})", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedSwitchgearIdx = v!),
              ),
              const SizedBox(height: 6),
              Text(t('breaker_select'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedBreakerIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kBreakers.length, (i) => DropdownMenuItem(value: i, child: Text("${kBreakers[i].name} [${kBreakers[i].medium}] (≤${kBreakers[i].defaultLimitMicroOhm.toInt()}µΩ)", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedBreakerIdx = v!),
              ),
              const SizedBox(height: 6),
              Text(t('relay_select'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedRelayIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kRelays.length, (i) => DropdownMenuItem(value: i, child: Text("${kRelays[i].name} (${kRelays[i].standardCode})", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedRelayIdx = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildHudCard(
          "${t('sat_hud_title')}: ${_activeBreaker.name}",
          isOverallPass ? t('sat_pass') : t('sat_fail'),
          "Limit: ≤ ${limit.toInt()} µΩ | Max: ${maxRes.toStringAsFixed(1)} µΩ | Asym: %${resAsym.toStringAsFixed(1)}",
          accentColor: isOverallPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide('sat_hud_title', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF151921), foregroundColor: const Color(0xFFFFB300), side: const BorderSide(color: Color(0xFFFFB300))),
                icon: const Icon(Icons.paste, size: 14),
                label: Text(t('cibano_btn'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: _showCibanoPasteDialog,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
                icon: const Icon(Icons.description, size: 14),
                label: Text(t('report_btn'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: _showOfficialSatPdfReport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('res_title'),
          child: Column(
            children: [
              _buildEditableSlider(
                t('res_r'), _resR, 10, 100, (v) => setState(() => _resR = v),
                infoTap: () => _showFieldGuide('res_r', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('res_s'), _resS, 10, 100, (v) => setState(() => _resS = v),
                infoTap: () => _showFieldGuide('res_s', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('res_t'), _resT, 10, 100, (v) => setState(() => _resT = v),
                infoTap: () => _showFieldGuide('res_t', 'guide_logic', 'guide_where', 'guide_std'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          title: t('time_title'),
          child: Column(
            children: [
              _buildEditableSlider(
                t('time_r'), _timeR, 20, 90, (v) => setState(() => _timeR = v),
                infoTap: () => _showFieldGuide('time_r', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('time_s'), _timeS, 20, 90, (v) => setState(() => _timeS = v),
                infoTap: () => _showFieldGuide('time_s', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              _buildEditableSlider(
                t('time_t'), _timeT, 20, 90, (v) => setState(() => _timeT = v),
                infoTap: () => _showFieldGuide('time_t', 'guide_logic', 'guide_where', 'guide_std'),
              ),
              Text("Δt: ${deltaSyncMs.toStringAsFixed(1)} ms | ${isSyncOk ? t('sync_ok') : t('sync_fail')}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSyncOk ? Colors.greenAccent : Colors.redAccent)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_testHistory.isNotEmpty)
          _buildSectionCard(
            title: "${t('history_title')} (${_testHistory.length})",
            child: Column(
              children: _testHistory.take(4).map((r) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF0B0E14), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF30363D))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${r.substation} - ${r.breaker}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text("${r.timestamp} | Max R: ${r.maxRes.toStringAsFixed(1)} µΩ | Δt: ${r.syncDelta.toStringAsFixed(1)}ms", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: r.passed ? const Color(0xFF00E676) : const Color(0xFFFF3D00), borderRadius: BorderRadius.circular(4)),
                      child: Text(r.passed ? "PASS" : "FAIL", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // SEKME 3: KABLO & ARK
  // ==========================================
  Widget _buildCableArcTab() {
    final sMin = ElectricalEngine.calcAdiabaticSection(_ikKa, 0.15, _isCopper);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          t('cable_hud_title'),
          "${_cableSection.toInt()} mm²",
          "Smin: ${sMin.toStringAsFixed(1)} mm²",
          onInfoTap: () => _showFieldGuide('cable_hud_title', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        const SizedBox(height: 14),
        _buildEditableSlider(
          t('selected_section'), _cableSection, 16, 400, (v) => setState(() => _cableSection = v),
          infoTap: () => _showFieldGuide('selected_section', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        _buildEditableSlider(
          t('line_length'), _cableLength, 10, 1000, (v) => setState(() => _cableLength = v),
          infoTap: () => _showFieldGuide('line_length', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        _buildEditableSlider(
          t('load_current'), _loadCurrent, 10, 600, (v) => setState(() => _loadCurrent = v),
          infoTap: () => _showFieldGuide('load_current', 'guide_logic', 'guide_where', 'guide_std'),
        ),
        _buildEditableSlider(
          t('arc_distance'), _workingDistanceMm, 300, 1200, (v) => setState(() => _workingDistanceMm = v),
          infoTap: () => _showFieldGuide('arc_distance', 'guide_logic', 'guide_where', 'guide_std'),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 4: ŞALT DİZİLİMİ & SLD
  // ==========================================
  Widget _buildSwitchgearSldTab() {
    final canvasWidth = max(MediaQuery.of(context).size.width * 1.6, _cells.length * 115.0 + 100.0);
    const canvasHeight = 330.0;

    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF30363D), width: 1.5)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                constrained: false,
                boundaryMargin: const EdgeInsets.symmetric(horizontal: 200, vertical: 80),
                minScale: 0.4,
                maxScale: 2.5,
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasHeight,
                  child: CustomPaint(
                    size: Size(canvasWidth, canvasHeight),
                    painter: DynamicSwitchgearPainter(cells: _cells, voltageKv: _voltageKv, ikKa: _ikKa, activeSwitchgear: _activeSwitchgear.name),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _cells.length,
            itemBuilder: (ctx, i) {
              final c = _cells[i];
              return Card(
                color: const Color(0xFF151921),
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF30363D)), borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  dense: true,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: Text("CT: ${c.ctRatio} | ${_activeBreaker.name}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  trailing: IconButton(
                    icon: Icon(c.cbClosed ? Icons.power : Icons.power_off, color: c.cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)),
                    onPressed: () => setState(() => c.cbClosed = !c.cbClosed),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- YARDIMCI WIDGETLAR ---
  Widget _buildEditableSlider(String title, double val, double min, double max, ValueChanged<double> onChanged, {VoidCallback? infoTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  if (infoTap != null)
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 16, color: Color(0xFFFFB300)),
                      padding: const EdgeInsets.only(left: 6),
                      constraints: const BoxConstraints(),
                      onPressed: infoTap,
                    ),
                ],
              ),
              Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 12)),
            ],
          ),
          Slider(value: val.clamp(min, max), min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildHudCard(String title, String value, String sub, {Color accentColor = const Color(0xFFFFB300), VoidCallback? onInfoTap}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(12), border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              if (onInfoTap != null)
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 16, color: Color(0xFFFFB300)),
                  padding: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(),
                  onPressed: onInfoTap,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: accentColor)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 8), child]),
    );
  }

  InputDecoration _inputDeco() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: const Color(0xFF0B0E14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFB300))),
    );
  }
}

// ==========================================
// 5. TCC ÇİZİCİSİ
// ==========================================
class LogLogTccPainter extends CustomPainter {
  final double upIs;
  final double upTms;
  final String upCurve;
  final double downIs;
  final double downTms;
  final String downCurve;
  final double faultA;

  LogLogTccPainter({
    required this.upIs,
    required this.upTms,
    required this.upCurve,
    required this.downIs,
    required this.downTms,
    required this.downCurve,
    required this.faultA,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()..color = const Color(0xFF21262D)..strokeWidth = 1.0;
    final axisPaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 1.5;

    double logX(double a) => (log(max(a, 10.0)) / ln10 - 1.0) / 3.0 * (w - 40) + 30;
    double logY(double t) => h - 20 - ((log(max(t, 0.01)) / ln10 + 2.0) / 4.0 * (h - 30));

    for (int p = 1; p <= 4; p++) {
      final x = logX(pow(10, p).toDouble());
      canvas.drawLine(Offset(x, 10), Offset(x, h - 20), gridPaint);
    }
    for (int p = -2; p <= 2; p++) {
      final y = logY(pow(10, p).toDouble());
      canvas.drawLine(Offset(30, y), Offset(w - 10, y), gridPaint);
    }

    canvas.drawLine(Offset(30, 10), Offset(30, h - 20), axisPaint);
    canvas.drawLine(Offset(30, h - 20), Offset(w - 10, h - 20), axisPaint);

    final upPaint = Paint()..color = const Color(0xFFFF3D00)..strokeWidth = 2.2..style = PaintingStyle.stroke;
    final upPath = Path();
    bool upStarted = false;
    for (double i = upIs * 1.05; i <= 10000; i += (i < 1000 ? 50 : 250)) {
      final t = ElectricalEngine.calcTripTime(i, upIs, upTms, upCurve);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!upStarted) { upPath.moveTo(pt.dx, pt.dy); upStarted = true; } else { upPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(upPath, upPaint);

    final downPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 2.2..style = PaintingStyle.stroke;
    final downPath = Path();
    bool downStarted = false;
    for (double i = downIs * 1.05; i <= 10000; i += (i < 1000 ? 30 : 200)) {
      final t = ElectricalEngine.calcTripTime(i, downIs, downTms, downCurve);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!downStarted) { downPath.moveTo(pt.dx, pt.dy); downStarted = true; } else { downPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(downPath, downPaint);

    if (faultA >= 10 && faultA <= 10000) {
      final xFault = logX(faultA);
      final faultPaint = Paint()..color = Colors.white..strokeWidth = 1.2;
      canvas.drawLine(Offset(xFault, 15), Offset(xFault, h - 20), faultPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// 6. VEKTÖREL ŞALT ÇİZİCİSİ
// ==========================================
class DynamicSwitchgearPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final double voltageKv;
  final double ikKa;
  final String activeSwitchgear;

  DynamicSwitchgearPainter({required this.cells, required this.voltageKv, required this.ikKa, required this.activeSwitchgear});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final busY = h * 0.42;
    const bayWidth = 115.0;

    final busPaint = Paint()..color = const Color(0xFFFFB300)..strokeWidth = 4.5;
    final linePaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(25, busY), Offset(totalBusWidth - 25, busY), busPaint);

    for (int i = 0; i < cells.length; i++) {
      final x = 60.0 + (i * bayWidth);
      final cell = cells[i];

      final borderPaint = Paint()..color = const Color(0xFF21262D)..style = PaintingStyle.stroke..strokeWidth = 1.2;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 32, bayWidth - 12, h - 45), borderPaint);

      final tp = TextPainter(text: TextSpan(text: cell.name, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(x - 38, 38));

      if (cell.type == CellType.incomer) {
        canvas.drawLine(Offset(x, 55), Offset(x, busY - 16), linePaint);
        _drawBreaker(canvas, Offset(x, busY - 24), cell.cbClosed);
        canvas.drawLine(Offset(x, busY - 16), Offset(x, busY), linePaint);
      } else if (cell.type == CellType.coupler) {
        _drawBreaker(canvas, Offset(x, busY), cell.cbClosed);
      } else {
        canvas.drawLine(Offset(x, busY), Offset(x, busY + 22), linePaint);
        _drawBreaker(canvas, Offset(x, busY + 30), cell.cbClosed);
        canvas.drawLine(Offset(x, busY + 38), Offset(x, h * 0.82), linePaint);
      }
    }
  }

  void _drawBreaker(Canvas canvas, Offset center, bool isClosed) {
    final rect = Rect.fromCenter(center: center, width: 16, height: 16);
    final fill = Paint()..color = isClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676);
    final stroke = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.4;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
