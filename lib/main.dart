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
      title: 'PowerField Pro v5.0 Master Edition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A0F),
        cardColor: const Color(0xFF131822),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF3D00),
          surface: Color(0xFF131822),
        ),
        useMaterial3: true,
      ),
      home: const MainCockpit(),
    );
  }
}

enum AppLanguage { tr, en, de, es, fr, zh, ja, ru }
enum PowerDomain { generation, transmission, distribution }
enum SubArchetype {
  // Üretim
  hydroHES, solarGES, windRES, thermalCoal,
  // İletim
  hvSubstation154, hvGis380,
  // Dağıtım
  heavyIndustry, hospital, airport, commercialMall, standardSubstation
}
enum CellType { incomer, feeder, coupler, vtMetering, transformer }

// ==========================================
// 1. MERKEZİ MÜHENDİSLİK HESAP MOTORU
// ==========================================
class ElectricalEngine {
  static double calcShortCircuitKa(double voltageKv, double trafoMva, double ukPercent) {
    if (trafoMva <= 0 || ukPercent <= 0 || voltageKv <= 0) return 0.0;
    final zt = (ukPercent / 100.0) * (pow(voltageKv, 2) / trafoMva);
    if (zt <= 0) return 0.0;
    return (1.10 * voltageKv) / (sqrt(3) * zt);
  }

  static double calcNominalCurrentA(double trafoMva, double voltageKv) {
    if (voltageKv <= 0) return 0.0;
    return (trafoMva * 1000.0) / (sqrt(3) * voltageKv);
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

  static double calcVoltageDropPercent(double voltageKv, double currentA, double lengthM, double sectionMm2, bool isCopper) {
    if (voltageKv <= 0 || sectionMm2 <= 0) return 0.0;
    final rho = isCopper ? 0.0175 : 0.028;
    final r = (rho * lengthM) / sectionMm2;
    final x = 0.08 * (lengthM / 1000.0);
    const cosPhi = 0.85;
    final sinPhi = sqrt(1 - pow(cosPhi, 2));
    final deltaU = sqrt(3) * currentA * (r * cosPhi + x * sinPhi);
    return (deltaU / (voltageKv * 1000.0)) * 100.0;
  }

  // Harmonik Rezonans Frekansı (nr = sqrt(Ssc / Qc))
  static double calcResonanceOrder(double sscMva, double qcKvar) {
    if (qcKvar <= 0) return 0.0;
    final qcMva = qcKvar / 1000.0;
    return sqrt(sscMva / qcMva);
  }
}

// ==========================================
// 2. EKİPMAN MODELLERİ (MARKA VE KÜNYELER)
// ==========================================
class BreakerModel {
  final String name;
  final String vendor;
  final String medium;
  final double defaultLimitMicroOhm;
  final double typicalTripTimeMs;
  final String standardCode;
  final Color brandColor;

  const BreakerModel(this.name, this.vendor, this.medium, this.defaultLimitMicroOhm, this.typicalTripTimeMs, this.standardCode, this.brandColor);
}

const List<BreakerModel> kBreakers = [
  BreakerModel("Schneider Evolis (Vakum)", "Schneider", "Vacuum", 35.0, 38.0, "IEC 62271-100", Color(0xFF009639)),
  BreakerModel("Schneider FB4 (Fluarc Santral)", "Schneider", "SF6", 32.0, 45.0, "IEC 62271 / IEEE C37", Color(0xFF009639)),
  BreakerModel("Schneider SF1 / SF2 (Fluarc)", "Schneider", "SF6", 38.0, 42.0, "IEC 62271-100", Color(0xFF009639)),
  BreakerModel("Schneider LF1 / LF2 / LF3", "Schneider", "SF6", 40.0, 42.0, "IEC 62271-100", Color(0xFF009639)),
  BreakerModel("Siemens SION 3AE / 3AH", "Siemens", "Vacuum", 45.0, 44.0, "IEC / DIN VDE 0671", Color(0xFF00646E)),
  BreakerModel("ABB VD4 (Vakum)", "ABB", "Vacuum", 38.0, 40.0, "IEC 62271-100", Color(0xFFFF000F)),
  BreakerModel("ABB HD4 (SF6)", "ABB", "SF6", 42.0, 45.0, "IEC 62271-100", Color(0xFFFF000F)),
  BreakerModel("Eaton W-VACi / Power Xpert", "Eaton", "Vacuum", 36.0, 42.0, "IEC 62271-100 / ANSI", Color(0xFF003882)),
  BreakerModel("Magrini Galileo Fluvid / G10", "Magrini Galileo", "SF6", 36.0, 46.0, "IEC 62271 / CEI 17-1", Color(0xFF008080)),
  BreakerModel("Mitsubishi MS-V / MEKAR", "Mitsubishi", "Vacuum", 34.0, 38.0, "JEC-2300 / IEC 62271", Color(0xFFD9001B)),
  BreakerModel("Ormazabal CPG / CGS", "Ormazabal", "Vacuum", 42.0, 45.0, "IEC 62271-100", Color(0xFFE35205)),
  BreakerModel("Tavrida BB/TEL (ВВ/TEL ГОСТ)", "Tavrida", "Vacuum", 35.0, 32.0, "ГОСТ Р 52565 / ПУЭ", Color(0xFF4A90E2)),
  BreakerModel("TEDAŞ Standart Yerli Vakum", "Yerli/TEDAŞ", "Vacuum", 50.0, 45.0, "TEDAŞ-MLZ/96-015", Color(0xFFFFB300)),
];

class SwitchgearModel {
  final String name;
  final String vendor;
  final String type;
  final String standard;
  final Color brandColor;

  const SwitchgearModel(this.name, this.vendor, this.type, this.standard, this.brandColor);
}

const List<SwitchgearModel> kSwitchgears = [
  SwitchgearModel("Schneider SM6-36", "Schneider", "AIS Modüler", "IEC 62271-200 / TEDAŞ", Color(0xFF009639)),
  SwitchgearModel("Schneider Premset (2SI)", "Schneider", "Ekranlı Katı (SSIS)", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Schneider AirSeT (SF6-Free)", "Schneider", "Saf Hava + Vakum", "IEC 62271-200 / EU F-Gas", Color(0xFF00B050)),
  SwitchgearModel("Schneider RM6 / FBX", "Schneider", "Kompakt RMU (GIS)", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Schneider GHA (GIS)", "Schneider", "Gaz Yalıtımlı Şalt", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Siemens 8BT2 / NXAIR", "Siemens", "Hava Yalıtımlı Metal-Clad", "IEC 62271-200", Color(0xFF00646E)),
  SwitchgearModel("Siemens 8DJH / SIMOSEC", "Siemens", "Gaz Yalıtımlı RMU", "IEC 62271-200", Color(0xFF00646E)),
  SwitchgearModel("ABB UniGear ZS1 / UniSec", "ABB", "Metal-Clad Çekmeceli", "IEC 62271-200", Color(0xFFFF000F)),
  SwitchgearModel("ABB SafeRing / SafePlus", "ABB", "Kompakt Ring Ana Ünitesi", "IEC 62271-200", Color(0xFFFF000F)),
  SwitchgearModel("Eaton Power Xpert UX", "Eaton", "Metal-Clad 24/36kV", "IEC 62271-200", Color(0xFF003882)),
  SwitchgearModel("Eaton Holec Magnefix", "Eaton", "Döküm Reçineli Kompakt", "IEC 62271 / KEMA", Color(0xFF003882)),
  SwitchgearModel("Magrini Galileo Isolva / Fluvid", "Magrini Galileo", "Klasik Metal-Enclosed", "IEC 62271 / CEI", Color(0xFF008080)),
  SwitchgearModel("Mitsubishi V-Care / MEKAR", "Mitsubishi", "Kompakt Vakum Şalt", "JEC-2300 / JIS C 4603", Color(0xFFD9001B)),
  SwitchgearModel("Ormazabal CGMcosmos / GAE", "Ormazabal", "Modüler Kompakt GIS", "IEC 62271-200", Color(0xFFE35205)),
  SwitchgearModel("Ulusoy HMH-36 / Astor", "TEDAŞ", "TEDAŞ Modüler Hücre", "TEDAŞ MYD/96-015", Color(0xFFFFB300)),
  SwitchgearModel("КРУ / КСО Серия (ГОСТ)", "ГОСТ", "Metal Muhafazalı ЗРУ", "ГОСТ 14693 / ПУЭ 7", Color(0xFF4A90E2)),
];

class RelayModel {
  final String name;
  final String menuPath;
  final String standardCode;
  const RelayModel(this.name, this.menuPath, this.standardCode);
}

const List<RelayModel> kRelays = [
  RelayModel("Schneider Sepam 20/40/80", "Sepam: Sarı Tuş -> Koruma (50/51) -> Is & TMS", "IEC 60255"),
  RelayModel("Schneider Easergy P3/P5", "Easergy: Settings -> Group 1 -> 51 -> Is & k çarpanı", "IEC 60255"),
  RelayModel("Siemens Siprotec 4 (7SJ6x)", "Siprotec 4: Settings -> 50/51 -> 51 Pickup & Time Dial", "IEC 60255 / IEEE C37"),
  RelayModel("Siemens Siprotec 5 (7SJ8x)", "Siprotec 5: Group Line -> Overcurrent 51-1 -> Setting values", "IEC 60255 / IEEE C37"),
  RelayModel("ABB Relion REF615/620", "REF615: Menu -> Protection -> PHIPTOC1 (51) -> Start val & TMS", "IEC 60255"),
  RelayModel("Alstom MiCOM P122/P123", "MiCOM: Group 1 Current -> I> Set & I> TMS", "IEC 60255"),
  RelayModel("Eaton EMR-3000 / 4000", "Eaton HMI: Setpoints -> Protection -> Phase OC (51P)", "IEEE / IEC"),
  RelayModel("Mitsubishi M-PRO / MP", "Mitsubishi: Setting Mode -> Overcurrent OCR (51)", "JEC-2500 / JIS"),
  RelayModel("БМРЗ / Сириус (ГОСТ)", "БМРЗ: Уставки -> МТЗ-1 / МТЗ-2 -> Ток сраб. и время", "ГОСТ Р 59302"),
  RelayModel("Nari / Sifang (国网 GB/T)", "保护定值 -> 过流一段/二段 -> 定值电流与时限", "GB/T 14598 / DL/T"),
  RelayModel("Kael / Mikro / Yerli", "Ön Panel: Ayarlar -> Koruma -> 51 Eşik ve Eğri", "TEDAŞ / IEC 60255"),
];

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  String ctRatio;
  String currentVendor;
  String currentBreaker;

  SwitchgearCell({
    required this.id,
    required this.name,
    required this.type,
    this.cbClosed = false,
    this.ctRatio = "400/5A",
    this.currentVendor = "Schneider",
    this.currentBreaker = "Evolis",
  });
}

// ==========================================
// 3. ANA KOKPİT EKRANI
// ==========================================
class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});
  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> {
  int _activeTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  // Güç Segmenti ve Alt Mimari
  PowerDomain _domain = PowerDomain.distribution;
  SubArchetype _archetype = SubArchetype.standardSubstation;

  int _selectedSwitchgearIdx = 0;
  int _selectedBreakerIdx = 0;
  int _selectedRelayIdx = 0;

  BreakerModel get _activeBreaker => kBreakers[_selectedBreakerIdx];
  RelayModel get _activeRelay => kRelays[_selectedRelayIdx];
  SwitchgearModel get _activeSwitchgear => kSwitchgears[_selectedSwitchgearIdx];

  // Şebeke Değişkenleri
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  // Röle Değişkenleri
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";

  // Kesici SAT Değişkenleri
  double _resR = 34.2;
  double _resS = 35.8;
  double _resT = 34.9;
  double _timeR = 41.5;
  double _timeS = 42.8;
  double _timeT = 42.1;

  // Kablo Değişkenleri
  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;

  // Üretim & İletim Özel Parametreleri
  double _generatorMw = 25.0;
  double _generatorCosPhi = 0.85;
  double _rocofHzSec = 0.85; // TEİAŞ Limiti <= 1.0 Hz/s
  double _reversePowerPercent = 1.2; // ANSI 32 sınırı <= %2
  double _mhoImpedanceOhm = 12.4; // ANSI 40 İkaz Kaybı
  double _distanceZone1Km = 18.5; // ANSI 21 Mesafe Koruma
  double _sf6PressureMpa = 0.61; // Nominal 0.60 MPa

  // Dağıtım Özel Parametreleri
  double _motorKw = 315.0;
  double _compensationKvar = 400.0;
  double _hospitalRisoKOhm = 85.0;
  double _airportCcrAmps = 6.6;

  late List<SwitchgearCell> _cells;

  @override
  void initState() {
    super.initState();
    _syncCells();
  }

  void _syncCells() {
    _cells = [
      SwitchgearCell(id: "C1", name: "H01 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A", currentVendor: _activeSwitchgear.vendor, currentBreaker: _activeBreaker.name),
      SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true, currentVendor: _activeSwitchgear.vendor, currentBreaker: "VT"),
      SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false, currentVendor: _activeSwitchgear.vendor, currentBreaker: _activeBreaker.name),
      SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A", currentVendor: _activeSwitchgear.vendor, currentBreaker: _activeBreaker.name),
      SwitchgearCell(id: "C5", name: "H05 Fider 2", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A", currentVendor: _activeSwitchgear.vendor, currentBreaker: _activeBreaker.name),
    ];
  }

  double get _ikKa => ElectricalEngine.calcShortCircuitKa(_voltageKv, _trafoMva, _ukPercent);
  double get _trafoInrushA => ElectricalEngine.calcNominalCurrentA(_trafoMva, _voltageKv) * 10.0;
  double get _cableVoltageDrop => ElectricalEngine.calcVoltageDropPercent(_voltageKv, _loadCurrent, _cableLength, _cableSection, _isCopper);
  double get _resonanceOrder => ElectricalEngine.calcResonanceOrder(_ikKa * sqrt(3) * _voltageKv, _compensationKvar);

  // ==========================================
  // 📷 GELİŞMİŞ KAMERA / OCR ARAYÜZÜ
  // ==========================================
  void _openCameraOcrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.camera_alt, color: Color(0xFFFFB300)),
                    SizedBox(width: 8),
                    Text("AI PLAKA & ETİKET VİZÖRÜ (OCR)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFFB300))),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 10),
            // Animasyonlu Lazer Kamera Vizörü
            Container(
              height: 170,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF30363D))),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner, size: 80, color: Colors.white24),
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFB300), width: 2), borderRadius: BorderRadius.circular(8)),
                  ),
                  const Positioned(
                    top: 20,
                    child: Text("HÜCRE / TRAFO / KESİCİ ETİKETİNİ HİZALAYIN", style: TextStyle(fontSize: 9, color: Color(0xFFFFB300), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text("Hızlı Saha Tanıma Şablonları (Otomatik Aktar):", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 14, color: Color(0xFFFFB300)),
                  label: const Text("Trafo (34.5kV / 2.5MVA / %6.5uk)", style: TextStyle(fontSize: 10)),
                  onPressed: () {
                    setState(() { _voltageKv = 34.5; _trafoMva = 2.5; _ukPercent = 6.5; });
                    Navigator.pop(ctx);
                    _showSnack("✓ Trafo verileri aktarıldı!");
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.tune, size: 14, color: Color(0xFF00E676)),
                  label: const Text("Akım Trafosu (600/5A 5P20)", style: TextStyle(fontSize: 10)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSnack("✓ 600/5A CT oranı kaydedildi!");
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.flash_on, size: 14, color: Colors.cyanAccent),
                  label: const Text("Kesici Ductor (≤35µΩ / t=38ms)", style: TextStyle(fontSize: 10)),
                  onPressed: () {
                    setState(() { _resR = 32.5; _resS = 33.1; _resT = 32.8; });
                    Navigator.pop(ctx);
                    _showSnack("✓ Ductor kontak dirençleri yüklendi!");
                  },
                ),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 20),
            TextField(
              decoration: const InputDecoration(
                hintText: "OCR Metni Yapıştır (Örn: Un=34.5kV Sn=1600kVA uk=6.0% R=34uOhm)",
                hintStyle: TextStyle(fontSize: 11, color: Colors.white30),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (txt) {
                _parseOcrText(txt);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _parseOcrText(String text) {
    final vMatch = RegExp(r'(\d+[.,]?\d*)\s*kV', caseSensitive: false).firstMatch(text);
    final sMatch = RegExp(r'(\d+[.,]?\d*)\s*MVA', caseSensitive: false).firstMatch(text);
    final ukMatch = RegExp(r'uk\s*[:=]?\s*(\d+[.,]?\d*)', caseSensitive: false).firstMatch(text);
    setState(() {
      if (vMatch != null) _voltageKv = double.tryParse(vMatch.group(1)!.replaceAll(',', '.')) ?? _voltageKv;
      if (sMatch != null) _trafoMva = double.tryParse(sMatch.group(1)!.replaceAll(',', '.')) ?? _trafoMva;
      if (ukMatch != null) _ukPercent = double.tryParse(ukMatch.group(1)!.replaceAll(',', '.')) ?? _ukPercent;
    });
    _showSnack("✓ OCR Plaka verileri projeye aktarıldı!");
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF00E676), content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131822),
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFFFFB300), size: 22),
            const SizedBox(width: 8),
            Text('POWERFIELD PRO v5.0', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _activeSwitchgear.brandColor)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.camera_alt, color: Color(0xFFFFB300)), onPressed: _openCameraOcrScanner),
          DropdownButton<AppLanguage>(
            value: _lang,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF131822),
            items: const [
              DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 11))),
              DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 11))),
              DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 11))),
              DropdownMenuItem(value: AppLanguage.ru, child: Text('RU 🇷🇺', style: TextStyle(fontSize: 11))),
            ],
            onChanged: (l) => setState(() => _lang = l!),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // 3 BÜYÜK GÜÇ SEGMENTİ SEÇİCİSİ (LAUNCHER)
          _buildDomainLauncher(),
          // ALT MİMARİ SEÇİCİSİ
          _buildSubArchetypeSelector(),
          Expanded(child: _buildCurrentTab()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF131822),
        indicatorColor: _activeSwitchgear.brandColor.withValues(alpha: 0.25),
        selectedIndex: _activeTab,
        onDestinationSelected: (i) => setState(() => _activeTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_customize), label: "Kokpit"),
          NavigationDestination(icon: Icon(Icons.show_chart), label: "Röle TCC"),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: "Kesici SAT"),
          NavigationDestination(icon: Icon(Icons.cable), label: "Kablo & PQ"),
          NavigationDestination(icon: Icon(Icons.schema), label: "SLD Şema"),
        ],
      ),
    );
  }

  // ==========================================
  // 1. ÜÇ BÜYÜK GÜÇ SEGMENTİ SEÇİCİSİ
  // ==========================================
  Widget _buildDomainLauncher() {
    return Container(
      color: const Color(0xFF090D14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          _buildDomainTab("⚡ ÜRETİM (Gen)", PowerDomain.generation),
          const SizedBox(width: 6),
          _buildDomainTab("🌐 İLETİM (Trans)", PowerDomain.transmission),
          const SizedBox(width: 6),
          _buildDomainTab("🏢 DAĞITIM (Dist)", PowerDomain.distribution),
        ],
      ),
    );
  }

  Widget _buildDomainTab(String label, PowerDomain domain) {
    final isSel = _domain == domain;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _domain = domain;
            if (domain == PowerDomain.generation) _archetype = SubArchetype.solarGES;
            else if (domain == PowerDomain.transmission) _archetype = SubArchetype.hvSubstation154;
            else _archetype = SubArchetype.standardSubstation;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFFFFB300) : const Color(0xFF131822),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSel ? const Color(0xFFFFB300) : const Color(0xFF30363D)),
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.black : Colors.white70)),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 2. ALT MİMARİ SEÇİCİSİ (ARCHETYPES)
  // ==========================================
  Widget _buildSubArchetypeSelector() {
    List<Widget> chips = [];

    if (_domain == PowerDomain.generation) {
      chips = [
        _buildChip("☀️ GES (Güneş)", SubArchetype.solarGES),
        _buildChip("💨 RES (Rüzgar)", SubArchetype.windRES),
        _buildChip("💧 HES (Hidro)", SubArchetype.hydroHES),
        _buildChip("🔥 Termik / Kömür", SubArchetype.thermalCoal),
      ];
    } else if (_domain == PowerDomain.transmission) {
      chips = [
        _buildChip("⚡ 154 kV Şalt (TEİAŞ)", SubArchetype.hvSubstation154),
        _buildChip("🛡️ 380 kV GIS Merkezi", SubArchetype.hvGis380),
      ];
    } else {
      chips = [
        _buildChip("Standart TM", SubArchetype.standardSubstation),
        _buildChip("🏭 Ağır Sanayi / OSB", SubArchetype.heavyIndustry),
        _buildChip("🏥 Hastane (Medikal IT)", SubArchetype.hospital),
        _buildChip("✈️ Havalimanı (AGL)", SubArchetype.airport),
        _buildChip("🏬 AVM (NFPA 20)", SubArchetype.commercialMall),
      ];
    }

    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips)),
    );
  }

  Widget _buildChip(String label, SubArchetype type) {
    final isSel = _archetype == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
        selected: isSel,
        selectedColor: const Color(0xFFFFB300),
        labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70),
        backgroundColor: const Color(0xFF131822),
        onSelected: (_) => setState(() => _archetype = type),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_activeTab) {
      case 0: return _buildCockpitTab();
      case 1: return _buildRelayAndTccTab();
      case 2: return _buildBreakerDiagnosticsTab();
      case 3: return _buildCablePowerQualityTab();
      case 4: return _buildSwitchgearSldTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // SEKME 0: KOKPİT (GÜÇ VE MİMARİ MASASI)
  // ==========================================
  Widget _buildCockpitTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "3 FAZ KISA DEVRE KAPASİTESİ (Ik'')",
          "${_ikKa.toStringAsFixed(2)} kA",
          "Anma Akımı In: ${ElectricalEngine.calcNominalCurrentA(_trafoMva, _voltageKv).toStringAsFixed(1)} A | Demeraj: ${_trafoInrushA.toStringAsFixed(0)} A",
          accentColor: _activeSwitchgear.brandColor,
        ),
        const SizedBox(height: 12),
        _buildEditableSlider("Sistem Gerilimi (kV)", _voltageKv, 0.4, 380.0, (v) => setState(() => _voltageKv = v)),
        _buildEditableSlider("Güç Kapasitesi (MVA/MW)", _trafoMva, 0.1, 250.0, (v) => setState(() => _trafoMva = v)),
        _buildEditableSlider("Kısa Devre Empedansı (%uk)", _ukPercent, 3.0, 18.0, (v) => setState(() => _ukPercent = v)),
        const SizedBox(height: 10),

        // SEGMENTE ÖZEL MÜHENDİSLİK PANELİ
        _buildDomainSpecificPanel(),
      ],
    );
  }

  Widget _buildDomainSpecificPanel() {
    if (_domain == PowerDomain.generation) {
      final isRocofOk = _rocofHzSec <= 1.0;
      final isRevOk = _reversePowerPercent <= 2.0;

      return _buildSectionCard(
        title: "⚡ Santral & Jeneratör Koruma Matrisi (TEİAŞ / IEEE 1547)",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditableSlider("Jeneratör Gücü (MW)", _generatorMw, 1, 100, (v) => setState(() => _generatorMw = v)),
            _buildEditableSlider("ROCOF df/dt (Hz/s) [ANSI 81R]", _rocofHzSec, 0.1, 2.5, (v) => setState(() => _rocofHzSec = v)),
            _buildEditableSlider("Ters Güç P_rev (%) [ANSI 32]", _reversePowerPercent, 0.2, 5.0, (v) => setState(() => _reversePowerPercent = v)),
            Text("• ANSI 81R Adalanma Durumu: ${isRocofOk ? 'UYGUN (≤ 1.0 Hz/s)' : 'AÇMA VERİR (TEHLİKE)!'}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isRocofOk ? Colors.greenAccent : Colors.redAccent)),
            Text("• ANSI 32 Türbin Koruması: ${isRevOk ? 'Normal İşletme' : 'Ters Güç Açması!'}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isRevOk ? Colors.greenAccent : Colors.orangeAccent)),
            const Text("• ANSI 40 İkaz Kaybı (Mho Dairesi) & ANSI 87G Diferansiyel koruma devrededir.", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );
    } else if (_domain == PowerDomain.transmission) {
      final isSf6Ok = _sf6PressureMpa >= 0.55;
      return _buildSectionCard(
        title: "🌐 İletim Şebekesi & YG Koruma (TEİAŞ 154 / 380 kV)",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditableSlider("ANSI 21 Zone 1 Mesafe (km)", _distanceZone1Km, 5, 120, (v) => setState(() => _distanceZone1Km = v)),
            _buildEditableSlider("GIS SF6 Gaz Basıncı (MPa)", _sf6PressureMpa, 0.40, 0.75, (v) => setState(() => _sf6PressureMpa = v)),
            Text("• GIS SF6 Gaz Durumu: ${isSf6Ok ? 'NORMAL (0.60 MPa)' : 'DÜŞÜK BASINÇ ALARMI!'}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSf6Ok ? Colors.greenAccent : Colors.redAccent)),
            const Text("• ANSI 87T Trafo Diferansiyeli (2. Harmonik Demeraj Blokajı > %15) devrededir.", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );
    } else {
      final isResonanceDangerous = (_resonanceOrder >= 4.7 && _resonanceOrder <= 5.3) || (_resonanceOrder >= 6.7 && _resonanceOrder <= 7.3);
      return _buildSectionCard(
        title: "🏢 Dağıtım & Endüstriyel Tesis Analizi",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditableSlider("Kompanzasyon Gücü (kVAr)", _compensationKvar, 50, 2000, (v) => setState(() => _compensationKvar = v)),
            Text("• Harmonik Rezonans Mertebesi (nr): ${_resonanceOrder.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
            Text(
              isResonanceDangerous
                  ? "⚠ DİKKAT: Sistem 5./7. harmonikte rezonansa giriyor! %7 veya %14 reaktör takılmalıdır."
                  : "✓ Rezonans frekansı kritik harmoniklerden uzaktır.",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isResonanceDangerous ? Colors.redAccent : Colors.greenAccent),
            ),
          ],
        ),
      );
    }
  }

  // ==========================================
  // SEKME 1: RÖLE & TCC EĞRİSİ
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
          "SELEKTİVİTE MARJİNİ (Δt)",
          "${(deltaT * 1000).toStringAsFixed(0)} ms",
          isSelective ? "SELEKTİF (TEDAŞ/IEC Δt ≥ 300ms)" : "ÇAKIŞMA RİSKİ (Δt < 300ms)",
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "LOG-LOG RÖLE KOORDİNASYON EĞRİSİ (TCC)",
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
            child: CustomPaint(
              painter: LogLogTccPainter(upIs: _upIs, upTms: _upTms, upCurve: _upCurve, downIs: _downIs, downTms: _downTms, downCurve: _downCurve, faultA: faultA),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Giriş & Fider Eşikleri",
          child: Column(
            children: [
              _buildEditableSlider("Giriş Is (A)", _upIs, 50, 3000, (v) => setState(() => _upIs = v)),
              _buildEditableSlider("Giriş TMS", _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v)),
              _buildEditableSlider("Fider Is (A)", _downIs, 20, 1500, (v) => setState(() => _downIs = v)),
              _buildEditableSlider("Fider TMS", _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 2: KESİCİ SAT TEŞHİS & RAPORLAMA
  // ==========================================
  Widget _buildBreakerDiagnosticsTab() {
    final limit = _activeBreaker.defaultLimitMicroOhm;
    final maxRes = max(_resR, max(_resS, _resT));
    final deltaSyncMs = [(_timeR - _timeS).abs(), (_timeS - _timeT).abs(), (_timeR - _timeT).abs()].reduce(max);
    final isPass = maxRes <= limit && deltaSyncMs <= 3.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: "Ekipman Seçimi",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                value: _selectedSwitchgearIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF131822),
                decoration: _inputDeco(),
                items: List.generate(kSwitchgears.length, (i) => DropdownMenuItem(value: i, child: Text("${kSwitchgears[i].name} (${kSwitchgears[i].vendor})", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) { setState(() { _selectedSwitchgearIdx = v!; _syncCells(); }); },
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _selectedBreakerIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF131822),
                decoration: _inputDeco(),
                items: List.generate(kBreakers.length, (i) => DropdownMenuItem(value: i, child: Text("${kBreakers[i].name} [${kBreakers[i].medium}]", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) { setState(() { _selectedBreakerIdx = v!; _syncCells(); }); },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildHudCard(
          "SAT TEŞHİS: ${_activeBreaker.name}",
          isPass ? "PASS / TESTTEN GEÇTİ" : "FAIL / KUSURLU",
          "Limit: ≤ ${limit.toInt()} µΩ | Ölçülen: ${maxRes.toStringAsFixed(1)} µΩ | Δt: ${deltaSyncMs.toStringAsFixed(1)}ms",
          accentColor: isPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 42)),
          icon: const Icon(Icons.share, size: 16),
          label: const Text("Resmi SAT Raporunu Kopyala (WhatsApp/Email)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          onPressed: _copySatReport,
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "R-S-T Kontak Geçiş Dirençleri (µΩ)",
          child: Column(
            children: [
              _buildEditableSlider("R Kutbu (µΩ)", _resR, 10, 100, (v) => setState(() => _resR = v)),
              _buildEditableSlider("S Kutbu (µΩ)", _resS, 10, 100, (v) => setState(() => _resS = v)),
              _buildEditableSlider("T Kutbu (µΩ)", _resT, 10, 100, (v) => setState(() => _resT = v)),
            ],
          ),
        ),
      ],
    );
  }

  void _copySatReport() {
    final report = "⚡ POWERFIELD PRO - SAT TEST RAPORU\nEkipman: ${_activeSwitchgear.name} [${_activeBreaker.name}]\nKontak Dirençleri: R=${_resR.toStringAsFixed(1)}µΩ, S=${_resS.toStringAsFixed(1)}µΩ, T=${_resT.toStringAsFixed(1)}µΩ\nStandart: ${_activeBreaker.standardCode}";
    Clipboard.setData(ClipboardData(text: report));
    _showSnack("✓ SAT Raporu panoya kopyalandı!");
  }

  // ==========================================
  // SEKME 3: KABLO, GERİLİM DÜŞÜMÜ & HARMONİK
  // ==========================================
  Widget _buildCablePowerQualityTab() {
    final sMin = ElectricalEngine.calcAdiabaticSection(_ikKa, 0.15, _isCopper);
    final isDropOk = _cableVoltageDrop <= 3.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "ADYABATİK KABLO TAHKİKİ",
          "${_cableSection.toInt()} mm²",
          "Erimeyen Smin: ${sMin.toStringAsFixed(1)} mm² | Gerilim Düşümü: %${_cableVoltageDrop.toStringAsFixed(2)}",
          accentColor: isDropOk ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 12),
        _buildEditableSlider("Kablo Kesiti (mm²)", _cableSection, 16, 400, (v) => setState(() => _cableSection = v)),
        _buildEditableSlider("Hat Boyu (m)", _cableLength, 10, 2000, (v) => setState(() => _cableLength = v)),
        _buildEditableSlider("Yük Akımı (A)", _loadCurrent, 10, 800, (v) => setState(() => _loadCurrent = v)),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "Gerilim Düşümü Durumu",
          child: Text(
            isDropOk ? "✓ Gerilim düşümü %3 standardına uygundur." : "⚠ DİKKAT: Hat uzunluğundan ötürü gerilim düşümü %3 sınırını aşıyor!",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDropOk ? Colors.greenAccent : Colors.orangeAccent),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 4: DİNAMİK VE BAĞLANTILI SLD
  // ==========================================
  Widget _buildSwitchgearSldTab() {
    final canvasWidth = max(MediaQuery.of(context).size.width * 1.6, _cells.length * 125.0 + 100.0);
    const canvasHeight = 330.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: const Color(0xFF131822),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("AKTİF DİZİLİM: ${_activeSwitchgear.name}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _activeSwitchgear.brandColor)),
              Text("${_voltageKv} kV | ${_ikKa.toStringAsFixed(1)} kA", style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF30363D))),
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
                    painter: DynamicSwitchgearPainter(cells: _cells, voltageKv: _voltageKv, ikKa: _ikKa, switchgear: _activeSwitchgear, breaker: _activeBreaker),
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
                color: const Color(0xFF131822),
                margin: const EdgeInsets.only(bottom: 5),
                shape: RoundedRectangleBorder(side: BorderSide(color: _activeSwitchgear.brandColor.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  dense: true,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  subtitle: Text("${c.currentVendor} | ${c.currentBreaker} | CT: ${c.ctRatio}", style: const TextStyle(fontSize: 9, color: Colors.grey)),
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

  // --- YARDIMCI BİLEŞENLER ---
  Widget _buildEditableSlider(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF131822), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 11)),
            ],
          ),
          Slider(value: val.clamp(min, max), min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildHudCard(String title, String value, String sub, {Color accentColor = const Color(0xFFFFB300)}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF131822), borderRadius: BorderRadius.circular(12), border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: accentColor)),
          const SizedBox(height: 2),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131822), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 6), child]),
    );
  }

  InputDecoration _inputDeco() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: const Color(0xFF070A0F),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFB300))),
    );
  }
}

// ==========================================
// 5. TCC KOORDİNASYON ÇİZİCİSİ
// ==========================================
class LogLogTccPainter extends CustomPainter {
  final double upIs;
  final double upTms;
  final String upCurve;
  final double downIs;
  final double downTms;
  final String downCurve;
  final double faultA;

  LogLogTccPainter({required this.upIs, required this.upTms, required this.upCurve, required this.downIs, required this.downTms, required this.downCurve, required this.faultA});

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
// 6. DİNAMİK VE BAĞLANTILI SLD ÇİZİCİSİ
// ==========================================
class DynamicSwitchgearPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final double voltageKv;
  final double ikKa;
  final SwitchgearModel switchgear;
  final BreakerModel breaker;

  DynamicSwitchgearPainter({required this.cells, required this.voltageKv, required this.ikKa, required this.switchgear, required this.breaker});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final busY = h * 0.42;
    const bayWidth = 125.0;

    final busPaint = Paint()..color = switchgear.brandColor..strokeWidth = 4.5;
    final linePaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(25, busY), Offset(totalBusWidth - 25, busY), busPaint);

    for (int i = 0; i < cells.length; i++) {
      final x = 65.0 + (i * bayWidth);
      final cell = cells[i];

      final borderPaint = Paint()..color = switchgear.brandColor.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.2;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 28, bayWidth - 12, h - 40), borderPaint);

      _drawText(canvas, cell.name, Offset(x - 48, 34), Colors.white, 9, bold: true);
      _drawText(canvas, "[${switchgear.vendor} - ${breaker.name}]", Offset(x - 52, 46), switchgear.brandColor, 7.5);

      if (cell.type == CellType.incomer) {
        canvas.drawLine(Offset(x, 60), Offset(x, busY - 16), linePaint);
        _drawBreaker(canvas, Offset(x, busY - 24), cell.cbClosed);
        canvas.drawLine(Offset(x, busY - 16), Offset(x, busY), linePaint);
      } else if (cell.type == CellType.coupler) {
        _drawBreaker(canvas, Offset(x, busY), cell.cbClosed);
      } else {
        canvas.drawLine(Offset(x, busY), Offset(x, busY + 22), linePaint);
        _drawBreaker(canvas, Offset(x, busY + 30), cell.cbClosed);
        canvas.drawLine(Offset(x, busY + 38), Offset(x, h * 0.82), linePaint);
        canvas.drawCircle(Offset(x, busY + 52), 4.5, linePaint);
        canvas.drawCircle(Offset(x, busY + 60), 4.5, linePaint);
        _drawText(canvas, cell.ctRatio, Offset(x + 8, busY + 50), Colors.grey, 7.5);
      }
    }
  }

  void _drawBreaker(Canvas canvas, Offset center, bool isClosed) {
    final rect = Rect.fromCenter(center: center, width: 16, height: 16);
    final fill = Paint()..color = isClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676);
    final stroke = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.4;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
    if (!isClosed) {
      canvas.drawLine(Offset(center.dx - 5, center.dy - 5), Offset(center.dx + 5, center.dy + 5), stroke);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
