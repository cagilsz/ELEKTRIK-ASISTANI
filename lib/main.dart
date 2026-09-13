import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const PowerEngineMasterApp());
}

class PowerEngineMasterApp extends StatelessWidget {
  const PowerEngineMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerField Engineering Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        cardColor: const Color(0xFF151921),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300), // Industrial Amber
          secondary: Color(0xFF00E676), // Safety Green
          error: Color(0xFFFF3D00), // Alert Red
          surface: Color(0xFF151921),
        ),
        useMaterial3: true,
      ),
      home: const MainEngineDashboard(),
    );
  }
}

enum AppLanguage { tr, en, de }

class MainEngineDashboard extends StatefulWidget {
  const MainEngineDashboard({super.key});

  @override
  State<MainEngineDashboard> createState() => _MainEngineDashboardState();
}

class _MainEngineDashboardState extends State<MainEngineDashboard> {
  int _activeTabIndex = 0;
  AppLanguage _lang = AppLanguage.tr;

  // --- 1. ŞEBEKE & TRAFO PARAMETRELERİ (IEC 60076 / IEC 60909) ---
  double _systemVoltageKv = 34.5; // kV (34.5, 31.5, 15, 10.5, 6.3, 0.4)
  double _trafoMva = 1.6; // MVA (1600 kVA)
  double _ukPercent = 6.0; // %uk
  double _cFactor = 1.10; // IEC 60909 Gerilim Faktörü

  // --- 2. ÇİFT KADEMELİ RÖLE SELEKTİVİTESİ (IEC 60255 / TEDAŞ) ---
  // Upstream (Giriş Rölesi)
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  // Downstream (Fider Rölesi)
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";

  // --- 3. ARK PARLAMASI ANALİZİ (IEEE 1584 / NFPA 70E) ---
  double _workingDistanceMm = 610.0; // Tipik OG hücresi çalışma mesafesi (mm)
  double _breakerMechTimeMs = 50.0; // Kesici mekanik açma süresi (ms)

  // --- 4. KABLO, ÇEVRESEL DÜZELTME & ADYABATİK TAHKİK (IEC 60364 / DIN VDE) ---
  double _cableLength = 180.0;
  double _loadCurrent = 95.0;
  double _selectedSection = 50.0; // mm²
  bool _isCopper = true;
  double _ambientTemp = 40.0; // °C
  int _groupedCircuits = 3; // Yan yana kablo sayısı

  // --- 5. TEK HAT ŞEMASI (SLD) VE KİLİTLEME DURUMLARI ---
  bool _cb1Closed = true; // TR-1 Giriş Kesicisi
  bool _cb2Closed = true; // TR-2 Giriş Kesicisi
  bool _cbCouplerClosed = false; // Kuplaj Kesicisi
  bool _earthSwitchClosed = false; // Fider Topraklama Ayırıcısı
  bool _atsGenActive = false; // Jeneratör Şalteri

  // Çeviri Tablosu
  String t(String key) {
    const dict = {
      'nav_grid': {'tr': 'Trafo & Şebeke', 'en': 'Grid & Trafo', 'de': 'Netz & Trafo'},
      'nav_relay': {'tr': 'Röle Selektivite', 'en': 'Selectivity', 'de': 'Staffelung'},
      'nav_arc': {'tr': 'IEEE 1584 Ark', 'en': 'Arc Flash', 'de': 'Störlichtbogen'},
      'nav_cable': {'tr': 'Kablo & Termik', 'en': 'Cable & Thermal', 'de': 'Kabelauslegung'},
      'nav_sld': {'tr': 'Tek Hat (SLD)', 'en': 'SLD Schematic', 'de': 'Einliniendiagramm'},
      'ik_title': {'tr': '3 FAZ BAŞLANGIÇ KISA DEVRE AKIMI', 'en': '3-PHASE SHORT CIRCUIT CURRENT', 'de': '3-POL. KURZSCHLUSSSTROM'},
      'calc_engine': {'tr': 'Hesaplama Motoru (IEC / IEEE)', 'en': 'Calculation Engine', 'de': 'Berechnungsmotor'},
      'interlock_warn': {'tr': '2/3 KİLİTLEME İHLALİ: TR1, TR2 ve Kuplaj aynı anda kapalı olamaz!', 'en': '2/3 INTERLOCK VIOLATION: Paralleling prohibited!', 'de': '2/3 VERRIEGELUNG: Parallelschaltung verboten!'},
      'earth_warn': {'tr': 'GÜVENLİK İHLALİ: Kesici kapalıyken topraklama kapatılamaz!', 'en': 'SAFETY INTERLOCK: Breaker must be OPEN before Earthing!', 'de': 'SICHERHEITSVERRIEGELUNG: Vor Erdung Leistungsschalter ÖFFNEN!'},
    };
    return dict[key]?[_lang.name] ?? key;
  }

  // --- HESAPLAMA MOTORU FORMÜLLERİ ---

  // IEC 60909 Trafo Empedansı ve Kısa Devre Akımı
  double get _shortCircuitCurrentKa {
    final zt = (_ukPercent / 100.0) * (pow(_systemVoltageKv, 2) / _trafoMva);
    if (zt <= 0) return 0.0;
    return (_cFactor * _systemVoltageKv) / (sqrt(3) * zt);
  }

  double get _peakShortCircuitKa {
    // ip = kappa * sqrt(2) * Ik'' (Tipik kappa ~ 1.8)
    return 1.8 * sqrt(2) * _shortCircuitCurrentKa;
  }

  // IEC 60255 Açma Süresi
  double _calcTripTime(double faultA, double iSetting, double tmsVal, String curve) {
    if (faultA <= iSetting) return double.infinity;
    double k = 0.14, alpha = 0.02;
    if (curve == "VI") { k = 13.5; alpha = 1.0; }
    else if (curve == "EI") { k = 80.0; alpha = 2.0; }
    else if (curve == "LTI") { k = 120.0; alpha = 1.0; }
    final m = faultA / iSetting;
    final denom = pow(m, alpha) - 1.0;
    if (denom <= 0) return double.infinity;
    return tmsVal * (k / denom);
  }

  // Downstream Toplam Arıza Temizleme Süresi (saniye)
  double get _totalClearingTimeSec {
    final faultA = _shortCircuitCurrentKa * 1000.0;
    final tRelay = _calcTripTime(faultA, _downIs, _downTms, _downCurve);
    if (tRelay.isInfinite) return 0.50; // Varsayılan yedek
    return tRelay + (_breakerMechTimeMs / 1000.0);
  }

  // IEEE 1584 Ark Parlaması Olay Enerjisi (cal/cm²)
  double get _incidentEnergyCalCm2 {
    final ik = _shortCircuitCurrentKa;
    final t = _totalClearingTimeSec;
    final d = _workingDistanceMm;
    if (ik <= 0 || t <= 0) return 0.0;
    // IEEE 1584 Amperik Basitleştirilmiş Yaklaşım Modeli
    final energy = 4.184 * (1000.0 / d) * ik * t * 1.5;
    return min(energy, 85.0);
  }

  // NFPA 70E KKD / PPE Seviyesi
  String get _ppeCategory {
    final e = _incidentEnergyCalCm2;
    if (e < 1.2) return "Seviye 0 (Standart İş Kıyafeti)";
    if (e <= 4.0) return "Kategori 1 (4 cal/cm² Yangına Dirençli)";
    if (e <= 8.0) return "Kategori 2 (8 cal/cm² Ark Başlığı)";
    if (e <= 25.0) return "Kategori 3 (25 cal/cm² Tam Takım Zırh)";
    if (e <= 40.0) return "Kategori 4 (40 cal/cm² Bomba İmha Tipi Ark Giysisi)";
    return "TEHLİKELİ! ÇALIŞILAMAZ (> 40 cal/cm²)";
  }

  // Çevresel Katsayılar (IEC 60364 / DIN VDE 0298-4)
  double get _tempCorrectionFactor {
    // 30°C referans XLPE
    if (_ambientTemp <= 30) return 1.0;
    if (_ambientTemp <= 35) return 0.96;
    if (_ambientTemp <= 40) return 0.91;
    if (_ambientTemp <= 45) return 0.87;
    return 0.82;
  }

  double get _groupCorrectionFactor {
    if (_groupedCircuits == 1) return 1.0;
    if (_groupedCircuits == 2) return 0.80;
    if (_groupedCircuits == 3) return 0.70;
    return 0.65;
  }

  // Adyabatik Kısa Devre Asgari Kablo Kesiti Smin = (Ik * sqrt(t)) / k
  double get _minAdiabaticSectionMm2 {
    final ikAmps = _shortCircuitCurrentKa * 1000.0;
    final t = min(_totalClearingTimeSec, 1.0);
    final k = _isCopper ? 143.0 : 94.0; // Cu/XLPE = 143, Al/XLPE = 94
    return (ikAmps * sqrt(t)) / k;
  }

  // Gerilim Düşümü %
  double get _voltageDropPercent {
    final rho = _isCopper ? 0.0175 : 0.028;
    final r = (rho * _cableLength) / _selectedSection;
    final vNominal = _systemVoltageKv * 1000.0;
    final deltaU = sqrt(3) * _loadCurrent * r * 0.85;
    return (deltaU / vNominal) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF151921),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFFFFB300), size: 26),
            const SizedBox(width: 8),
            const Text(
              'POWERFIELD PRO',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 17),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF30363D)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<AppLanguage>(
              value: _lang,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF151921),
              items: const [
                DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (l) => setState(() => _lang = l!),
            ),
          )
        ],
      ),
      body: _buildCurrentModule(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF30363D), width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: const Color(0xFF151921),
          indicatorColor: const Color(0xFFFFB300).withValues(alpha: 0.25),
          selectedIndex: _activeTabIndex,
          onDestinationSelected: (i) => setState(() => _activeTabIndex = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.power_input), label: t('nav_grid')),
            NavigationDestination(icon: const Icon(Icons.tune), label: t('nav_relay')),
            NavigationDestination(icon: const Icon(Icons.warning_amber), label: t('nav_arc')),
            NavigationDestination(icon: const Icon(Icons.cable), label: t('nav_cable')),
            NavigationDestination(icon: const Icon(Icons.schema), label: t('nav_sld')),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModule() {
    switch (_activeTabIndex) {
      case 0:
        return _buildGridTrafoView();
      case 1:
        return _buildRelayCoordinationView();
      case 2:
        return _buildArcFlashView();
      case 3:
        return _buildCableThermalView();
      case 4:
        return _buildSingleLineDiagramView();
      default:
        return const SizedBox();
    }
  }

  // ==========================================
  // MODÜL 1: ŞEBEKE & TRAFO ANALİZİ
  // ==========================================
  Widget _buildGridTrafoView() {
    final ikKa = _shortCircuitCurrentKa;
    final ipKa = _peakShortCircuitKa;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          title: t('ik_title'),
          value: '${ikKa.toStringAsFixed(2)} kA',
          subValue: 'Tepe Darbe Akımı (ip): ${ipKa.toStringAsFixed(2)} kA',
          accentColor: const Color(0xFFFFB300),
        ),
        const SizedBox(height: 16),
        _buildCardWrapper(
          title: 'Sistem Gerilim Seviyesi (TEDAŞ / IEC)',
          child: DropdownButtonFormField<double>(
            value: _systemVoltageKv,
            dropdownColor: const Color(0xFF151921),
            decoration: _inputDeco(),
            items: const [
              DropdownMenuItem(value: 34.5, child: Text('34.5 kV (TEDAŞ Standart Dağıtım)')),
              DropdownMenuItem(value: 31.5, child: Text('31.5 kV')),
              DropdownMenuItem(value: 15.0, child: Text('15.0 kV')),
              DropdownMenuItem(value: 10.5, child: Text('10.5 kV (Sanayi / Dağıtım)')),
              DropdownMenuItem(value: 6.3, child: Text('6.3 kV (Büyük Motorlar / Santral)')),
              DropdownMenuItem(value: 0.4, child: Text('0.4 kV (Alçak Gerilim 400V)')),
            ],
            onChanged: (v) => setState(() => _systemVoltageKv = v!),
          ),
        ),
        const SizedBox(height: 12),
        _buildSliderCard('Trafo Gücü Sn (MVA)', _trafoMva, 0.1, 25.0, (v) => setState(() => _trafoMva = v)),
        _buildSliderCard('Bağıl Kısa Devre Gerilimi (%uk)', _ukPercent, 3.0, 12.0, (v) => setState(() => _ukPercent = v)),
        _buildSliderCard('IEC 60909 Gerilim Faktörü (c)', _cFactor, 1.0, 1.15, (v) => setState(() => _cFactor = v)),
      ],
    );
  }

  // ==========================================
  // MODÜL 2: ÇİFT KADEMELİ SELEKTİVİTE
  // ==========================================
  Widget _buildRelayCoordinationView() {
    final faultA = _shortCircuitCurrentKa * 1000.0;
    final tUp = _calcTripTime(faultA, _upIs, _upTms, _upCurve);
    final tDown = _calcTripTime(faultA, _downIs, _downTms, _downCurve);
    final deltaT = (tUp.isFinite && tDown.isFinite) ? (tUp - tDown) : 0.0;
    final isSelective = deltaT >= 0.30; // 300 ms TEDAŞ Güvenlik Marjini

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          title: 'SELEKTİVİTE ZAMAN FARKI (Δt)',
          value: '${(deltaT * 1000).toStringAsFixed(0)} ms',
          subValue: isSelective ? 'UYGUN: Selektif (Δt ≥ 300 ms)' : 'RİSKLİ: İki röle çakışabilir (Δt < 300 ms)!',
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          isWarning: !isSelective,
        ),
        const SizedBox(height: 16),
        _buildCardWrapper(
          title: 'Giriş / Upstream Kesici Rölesi',
          child: Column(
            children: [
              _buildDropdown(['SI', 'VI', 'EI', 'LTI'], _upCurve, (v) => setState(() => _upCurve = v)),
              const SizedBox(height: 8),
              _buildSliderCard('Upstream Is (A)', _upIs, 100, 3000, (v) => setState(() => _upIs = v)),
              _buildSliderCard('Upstream TMS', _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v)),
              Text('Açma Süresi t(Up): ${tUp.isFinite ? "${tUp.toStringAsFixed(3)} s" : "Açma Yok"}',
                  style: const TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCardWrapper(
          title: 'Fider / Downstream Kesici Rölesi',
          child: Column(
            children: [
              _buildDropdown(['SI', 'VI', 'EI', 'LTI'], _downCurve, (v) => setState(() => _downCurve = v)),
              const SizedBox(height: 8),
              _buildSliderCard('Downstream Is (A)', _downIs, 50, 1500, (v) => setState(() => _downIs = v)),
              _buildSliderCard('Downstream TMS', _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v)),
              Text('Açma Süresi t(Down): ${tDown.isFinite ? "${tDown.toStringAsFixed(3)} s" : "Açma Yok"}',
                  style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MODÜL 3: ARK PARLAMASI (IEEE 1584 / NFPA 70E)
  // ==========================================
  Widget _buildArcFlashView() {
    final energy = _incidentEnergyCalCm2;
    final isDanger = energy > 40.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          title: 'ARK ENERJİSİ (INCIDENT ENERGY)',
          value: '${energy.toStringAsFixed(1)} cal/cm²',
          subValue: _ppeCategory,
          accentColor: isDanger ? const Color(0xFFFF3D00) : const Color(0xFFFFB300),
          isWarning: isDanger,
        ),
        const SizedBox(height: 16),
        _buildCardWrapper(
          title: 'Ark Güvenlik Parametreleri',
          child: Column(
            children: [
              _buildSliderCard('Çalışma Mesafesi D (mm)', _workingDistanceMm, 300, 1200, (v) => setState(() => _workingDistanceMm = v)),
              _buildSliderCard('Kesici Mekanik Açma Gecikmesi (ms)', _breakerMechTimeMs, 30, 90, (v) => setState(() => _breakerMechTimeMs = v)),
              const Divider(color: Color(0xFF30363D)),
              Text('Arıza Akımı: ${_shortCircuitCurrentKa.toStringAsFixed(2)} kA (Modül 1\'den aktarıldı)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('Toplam Ark Süresi: ${(_totalClearingTimeSec * 1000).toStringAsFixed(0)} ms', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MODÜL 4: KABLO, ÇEVRE & ADYABATİK TAHKİK
  // ==========================================
  Widget _buildCableThermalView() {
    final sMin = _minAdiabaticSectionMm2;
    final isSectionSafe = _selectedSection >= sMin;
    final drop = _voltageDropPercent;
    final isDropSafe = drop <= 3.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          title: 'ADYABATİK ASGARİ KESİT TAHKİKİ',
          value: 'Smin: ${sMin.toStringAsFixed(1)} mm²',
          subValue: isSectionSafe ? 'Seçilen Kesit (${_selectedSection.toInt()} mm²) Isıl Olarak UYGUN' : 'TEHLİKE: Kısa devre anında kablo erir!',
          accentColor: isSectionSafe ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          isWarning: !isSectionSafe,
        ),
        const SizedBox(height: 16),
        _buildCardWrapper(
          title: 'Standart Kesit & İletken',
          child: Column(
            children: [
              DropdownButtonFormField<double>(
                value: _selectedSection,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: [16.0, 25.0, 35.0, 50.0, 70.0, 95.0, 120.0, 150.0, 185.0, 240.0, 300.0, 400.0]
                    .map((s) => DropdownMenuItem(value: s, child: Text('${s.toInt()} mm²'))).toList(),
                onChanged: (v) => setState(() => _selectedSection = v!),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text("Bakır (Cu)")),
                      selected: _isCopper,
                      selectedColor: const Color(0xFFFFB300),
                      onSelected: (v) => setState(() => _isCopper = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text("Alüminyum (Al)")),
                      selected: !_isCopper,
                      selectedColor: const Color(0xFFFFB300),
                      onSelected: (v) => setState(() => _isCopper = false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCardWrapper(
          title: 'Çevresel Düzeltme Katsayıları (DIN VDE 0298-4)',
          child: Column(
            children: [
              _buildSliderCard('Ortam Sıcaklığı (°C)', _ambientTemp, 20, 60, (v) => setState(() => _ambientTemp = v)),
              _buildSliderCard('Yan Yana Devre Sayısı', _groupedCircuits.toDouble(), 1, 6, (v) => setState(() => _groupedCircuits = v.toInt())),
              Text('Düzeltme Çarpanı: ${(_tempCorrectionFactor * _groupCorrectionFactor).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFFFB300), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCardWrapper(
          title: 'Gerilim Düşümü ΔU%',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('%${drop.toStringAsFixed(2)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDropSafe ? Colors.greenAccent : Colors.redAccent)),
              Text(isDropSafe ? 'TEDAŞ Kriterine Uygun (≤ %3)' : 'Limit Aşıldı!', style: TextStyle(color: isDropSafe ? Colors.green : Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MODÜL 5: TEK HAT ŞEMASI & KİLİTLEME SİMÜLATÖRÜ
  // ==========================================
  Widget _buildSingleLineDiagramView() {
    return Column(
      children: [
        // İnteraktif Vektörel Şema Alanı (Pan & Zoom Destekli)
        Expanded(
          flex: 5,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF070A0E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.6,
                maxScale: 2.5,
                child: CustomPaint(
                  size: const Size(double.infinity, double.infinity),
                  painter: SingleLineDiagramPainter(
                    cb1Closed: _cb1Closed,
                    cb2Closed: _cb2Closed,
                    cbCouplerClosed: _cbCouplerClosed,
                    earthSwitchClosed: _earthSwitchClosed,
                    voltageKv: _systemVoltageKv,
                    trafoMva: _trafoMva,
                    ikKa: _shortCircuitCurrentKa,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Şalt & Kesici Kilitleme Kontrol Paneli
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const Text('ŞALT KESİCİ VE KİLİTLEME KONTROLÜ',
                  style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildSwitchButton("TR-1 Giriş", _cb1Closed, () => setState(() => _cb1Closed = !_cb1Closed))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSwitchButton("Kuplaj (BC)", _cbCouplerClosed, _toggleCoupler)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSwitchButton("TR-2 Giriş", _cb2Closed, () => setState(() => _cb2Closed = !_cb2Closed))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildSwitchButton("Topraklama", _earthSwitchClosed, _toggleEarthSwitch, isEarth: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSwitchButton("Jeneratör ATS", _atsGenActive, () => setState(() => _atsGenActive = !_atsGenActive))),
                ],
              ),
              const SizedBox(height: 12),
              // CT/VT Bilgilendirme Kartı
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF151921),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Ölçü Trafoları Konfigürasyonu (IEC 61869)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFFFB300))),
                    SizedBox(height: 4),
                    Text("• Sayaç Nüvesi: Cl 0.2S, FS ≤ 5 | Koruma: 5P20, Burden: 15 VA\n• Gerilim Trafosu: 34.5/√3 kV / 100/√3 V / 100/3 V (Açık Üçgen)", style: TextStyle(fontSize: 10, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- KİLİTLEME MANTIKSAL KURALLARI (INTERLOCK MATRIX) ---
  void _toggleCoupler() {
    // 2/3 Kilitlemesi: TR1 ve TR2 kapalıyken kuplaj kapatılamaz!
    if (!_cbCouplerClosed && _cb1Closed && _cb2Closed) {
      _showInterlockWarning(t('interlock_warn'));
      return;
    }
    setState(() => _cbCouplerClosed = !_cbCouplerClosed);
  }

  void _toggleEarthSwitch() {
    // Toprak Kilitlemesi: Fider/TR1 kesicisi kapalıyken topraklama kapatılamaz!
    if (!_earthSwitchClosed && _cb1Closed) {
      _showInterlockWarning(t('earth_warn'));
      return;
    }
    setState(() => _earthSwitchClosed = !_earthSwitchClosed);
  }

  void _showInterlockWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFFF3D00),
        content: Row(
          children: [
            const Icon(Icons.lock, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          ],
        ),
      ),
    );
  }

  // --- YARDIMCI BİLEŞENLER ---
  Widget _buildSwitchButton(String label, bool state, VoidCallback onTap, {bool isEarth = false}) {
    Color activeColor = isEarth ? const Color(0xFF00E676) : const Color(0xFFFFB300);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: state ? activeColor : const Color(0xFF151921),
        foregroundColor: state ? Colors.black : Colors.white70,
        side: BorderSide(color: state ? activeColor : const Color(0xFF30363D)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text(state ? (isEarth ? "TOPRAKLI" : "KAPALI") : "AÇIK", style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildHudCard({
    required String title,
    required String value,
    required String subValue,
    required Color accentColor,
    bool isWarning = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151921),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isWarning ? const Color(0xFFFF3D00) : accentColor.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isWarning ? const Color(0xFFFF3D00) : accentColor)),
          const SizedBox(height: 4),
          Text(subValue, textAlign: TextAlign.center, style: TextStyle(color: isWarning ? Colors.redAccent : Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCardWrapper({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151921),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSliderCard(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151921),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 13)),
            ],
          ),
          Slider(value: val, min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildDropdown(List<String> items, String current, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      value: current,
      dropdownColor: const Color(0xFF151921),
      decoration: _inputDeco(),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (v) => onChanged(v!),
    );
  }

  InputDecoration _inputDeco() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: const Color(0xFF0B0E14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFB300))),
    );
  }
}

// ==========================================
// VEKTÖREL TEK HAT ŞEMASI ÇİZİM MOTORU (CANVAS)
// ==========================================
class SingleLineDiagramPainter extends CustomPainter {
  final bool cb1Closed;
  final bool cb2Closed;
  final bool cbCouplerClosed;
  final bool earthSwitchClosed;
  final double voltageKv;
  final double trafoMva;
  final double ikKa;

  SingleLineDiagramPainter({
    required this.cb1Closed,
    required this.cb2Closed,
    required this.cbCouplerClosed,
    required this.earthSwitchClosed,
    required this.voltageKv,
    required this.trafoMva,
    required this.ikKa,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintLine = Paint()
      ..color = const Color(0xFF8B949E)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintLiveBus = Paint()
      ..color = const Color(0xFFFFB300) // Enerjili Sarı
      ..strokeWidth = 4.0;

    final paintDeadBus = Paint()
      ..color = const Color(0xFF30363D)
      ..strokeWidth = 4.0;

    final paintEarth = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 2.5;

    // Koordinatlar
    final busY = h * 0.45;
    final xBus1 = w * 0.22;
    final xCoupler = w * 0.50;
    final xBus2 = w * 0.78;

    // 1. Ana Baralar (Busbar 1 ve Busbar 2)
    canvas.drawLine(Offset(w * 0.08, busY), Offset(xCoupler - 20, busY), cb1Closed ? paintLiveBus : paintDeadBus);
    canvas.drawLine(Offset(xCoupler + 20, busY), Offset(w * 0.92, busY), (cb2Closed || (cb1Closed && cbCouplerClosed)) ? paintLiveBus : paintDeadBus);

    // Kuplaj Kesici Hattı
    canvas.drawLine(Offset(xCoupler - 20, busY), Offset(xCoupler - 10, busY), paintLine);
    _drawBreakerSymbol(canvas, Offset(xCoupler, busY), cbCouplerClosed);
    canvas.drawLine(Offset(xCoupler + 10, busY), Offset(xCoupler + 20, busY), paintLine);

    // 2. Trafo 1 Giriş Fideri (Sol Taraf)
    canvas.drawLine(Offset(xBus1, h * 0.10), Offset(xBus1, h * 0.18), paintLine);
    _drawTransformerSymbol(canvas, Offset(xBus1, h * 0.22));
    canvas.drawLine(Offset(xBus1, h * 0.26), Offset(xBus1, h * 0.35), paintLine);
    _drawBreakerSymbol(canvas, Offset(xBus1, h * 0.38), cb1Closed);
    canvas.drawLine(Offset(xBus1, h * 0.41), Offset(xBus1, busY), paintLine);

    // 3. Trafo 2 Giriş Fideri (Sağ Taraf)
    canvas.drawLine(Offset(xBus2, h * 0.10), Offset(xBus2, h * 0.18), paintLine);
    _drawTransformerSymbol(canvas, Offset(xBus2, h * 0.22));
    canvas.drawLine(Offset(xBus2, h * 0.26), Offset(xBus2, h * 0.35), paintLine);
    _drawBreakerSymbol(canvas, Offset(xBus2, h * 0.38), cb2Closed);
    canvas.drawLine(Offset(xBus2, h * 0.41), Offset(xBus2, busY), paintLine);

    // 4. Çıkış Fideri & Topraklama Ayırıcısı (Aşağıya Doğru)
    canvas.drawLine(Offset(xBus1, busY), Offset(xBus1, h * 0.65), paintLine);
    _drawBreakerSymbol(canvas, Offset(xBus1, h * 0.68), cb1Closed);
    canvas.drawLine(Offset(xBus1, h * 0.71), Offset(xBus1, h * 0.82), paintLine);

    // Topraklama Ayırıcısı Sembolü
    if (earthSwitchClosed) {
      canvas.drawLine(Offset(xBus1, h * 0.76), Offset(xBus1 + 30, h * 0.76), paintEarth);
      _drawEarthGlyph(canvas, Offset(xBus1 + 30, h * 0.76));
    }

    // 5. Etiketler & Mühendislik Bilgileri
    _drawText(canvas, "BARA-1 ($voltageKv kV)", Offset(w * 0.08, busY - 18), const Color(0xFFFFB300), 10);
    _drawText(canvas, "BARA-2 ($voltageKv kV)", Offset(w * 0.72, busY - 18), const Color(0xFFFFB300), 10);
    _drawText(canvas, "TR-1: ${trafoMva}MVA", Offset(xBus1 + 16, h * 0.20), Colors.white70, 9);
    _drawText(canvas, "TR-2: ${trafoMva}MVA", Offset(xBus2 + 16, h * 0.20), Colors.white70, 9);
    _drawText(canvas, "Ik'': ${ikKa.toStringAsFixed(1)}kA", Offset(w * 0.08, busY + 8), const Color(0xFFFF3D00), 9);
  }

  void _drawBreakerSymbol(Canvas canvas, Offset center, bool isClosed) {
    final rect = Rect.fromCenter(center: center, width: 18, height: 18);
    final paint = Paint()
      ..color = isClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, border);

    // Çapraz veya düz hat
    if (!isClosed) {
      canvas.drawLine(Offset(center.dx - 6, center.dy - 6), Offset(center.dx + 6, center.dy + 6), border);
    }
  }

  void _drawTransformerSymbol(Canvas canvas, Offset center) {
    final p = Paint()
      ..color = const Color(0xFF8B949E)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(center.dx, center.dy - 6), 9, p);
    canvas.drawCircle(Offset(center.dx, center.dy + 6), 9, p);
  }

  void _drawEarthGlyph(Canvas canvas, Offset point) {
    final p = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(point.dx, point.dy - 8), Offset(point.dx, point.dy + 8), p);
    canvas.drawLine(Offset(point.dx + 5, point.dy - 5), Offset(point.dx + 5, point.dy + 5), p);
    canvas.drawLine(Offset(point.dx + 10, point.dy - 2), Offset(point.dx + 10, point.dy + 2), p);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size) {
    final textSpan = TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold));
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SingleLineDiagramPainter oldDelegate) {
    return oldDelegate.cb1Closed != cb1Closed ||
        oldDelegate.cb2Closed != cb2Closed ||
        oldDelegate.cbCouplerClosed != cbCouplerClosed ||
        oldDelegate.earthSwitchClosed != earthSwitchClosed ||
        oldDelegate.voltageKv != voltageKv ||
        oldDelegate.ikKa != ikKa;
  }
}
