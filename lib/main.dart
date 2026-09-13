import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const PowerEngineeringSuite());
}

class PowerEngineeringSuite extends StatelessWidget {
  const PowerEngineeringSuite({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Power Engineering Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300), // Industrial Amber
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF3D00),
          surface: Color(0xFF161B22),
        ),
        useMaterial3: true,
      ),
      home: const MainCockpitScreen(),
    );
  }
}

enum AppLanguage { tr, en, de }

class MainCockpitScreen extends StatefulWidget {
  const MainCockpitScreen({super.key});

  @override
  State<MainCockpitScreen> createState() => _MainCockpitScreenState();
}

class _MainCockpitScreenState extends State<MainCockpitScreen> {
  int _currentTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  // --- 1. RÖLE PARAMETRELERİ (IEC 60255) ---
  double _faultCurrent = 4500;
  double _pickupCurrent = 400;
  double _tms = 0.20;
  String _selectedCurve = "SI"; // SI, VI, EI, LTI

  // --- 2. KABLO & GERİLİM DÜŞÜMÜ (IEC 60364 / DIN VDE 0298) ---
  final List<double> _standardSections = const [
    2.5, 4, 6, 10, 16, 25, 35, 50, 70, 95, 120, 150, 185, 240, 300
  ];
  double _selectedSection = 16.0;
  double _cableLength = 120.0;
  double _loadCurrent = 55.0;
  bool _isCopper = true; // true: Cu, false: Al

  // --- 3. SAHA KABUL (SAT) TEST KAYITLARI ---
  final TextEditingController _substationController = TextEditingController(text: "TM-01 / Trafo 1");
  final TextEditingController _breakerController = TextEditingController(text: "HVX-36kV");
  double _resR = 38.5; // µΩ
  double _resS = 41.0; // µΩ
  double _resT = 39.8; // µΩ
  double _maxAllowedRes = 50.0; // µΩ limit
  double _openTimeR = 42.0; // ms
  double _openTimeS = 43.1; // ms
  double _openTimeT = 42.8; // ms
  bool _lotoVerified = true;

  // Çeviri Sözlüğü
  String t(String key) {
    const dict = {
      'relay': {'tr': 'IEC 60255 Röle', 'en': 'IEC 60255 Relay', 'de': 'IEC 60255 Schutz'},
      'cable': {'tr': 'Kablo & ΔU', 'en': 'Cable & ΔV', 'de': 'Kabel & Sp.Fall'},
      'sat': {'tr': 'Saha Kabul (SAT)', 'en': 'SAT Comm.', 'de': 'Inbetriebnahme'},
      'trip_time': {'tr': 'AÇMA SÜRESİ', 'en': 'TRIP TIME', 'de': 'AUSLÖSEZEIT'},
      'curve_type': {'tr': 'Eğri Karakteristiği', 'en': 'Curve Characteristic', 'de': 'Kennlinientyp'},
      'fault_i': {'tr': 'Arıza Akımı I (A)', 'en': 'Fault Current I (A)', 'de': 'Fehlerstrom I (A)'},
      'pickup_is': {'tr': 'Aşırı Akım Eşiği Is (A)', 'en': 'Pickup Current Is (A)', 'de': 'Ansprechwert Is (A)'},
      'tms': {'tr': 'Zaman Çarpanı (TMS)', 'en': 'Time Multiplier (TMS)', 'de': 'Zeitempfindlichkeit (TMS)'},
      'volt_drop': {'tr': 'GERİLİM DÜŞÜMÜ (3~ 400V)', 'en': 'VOLTAGE DROP (3~ 400V)', 'de': 'SPANNUNGSFALL (3~ 400V)'},
      'section': {'tr': 'Standart Kesit', 'en': 'Nominal Cross-Section', 'de': 'Nennquerschnitt'},
      'conductor': {'tr': 'İletken Malzemesi', 'en': 'Conductor Material', 'de': 'Leitermaterial'},
      'length': {'tr': 'Hat Uzunluğu (m)', 'en': 'Line Length (m)', 'de': 'Leitungslänge (m)'},
      'load_i': {'tr': 'İşletme Akımı Ib (A)', 'en': 'Operating Current Ib (A)', 'de': 'Betriebsstrom Ib (A)'},
      'contact_res': {'tr': 'Kontak Geçiş Direnci (µΩ)', 'en': 'Contact Resistance (µΩ)', 'de': 'Übergangswiderstand (µΩ)'},
      'breaker_timing': {'tr': 'Açma Zamanı & Senkronizm (ms)', 'en': 'Opening Time & Sync (ms)', 'de': 'Eigenzeit & Synchronität (ms)'},
      'pass': {'tr': 'UYGUN (PASS)', 'en': 'PASSED', 'de': 'BESTANDEN'},
      'fail': {'tr': 'UYGUN DEĞİL (FAIL)', 'en': 'FAILED', 'de': 'NICHT BESTANDEN'},
      'summary': {'tr': 'Rapor Özeti', 'en': 'Report Summary', 'de': 'Prüfprotokoll'},
    };
    return dict[key]?[_lang.name] ?? key;
  }

  // IEC 60255 Matematik Motoru
  double get _tripTimeSeconds {
    if (_faultCurrent <= _pickupCurrent) return double.infinity;
    double k = 0.14, alpha = 0.02;
    if (_selectedCurve == "VI") { k = 13.5; alpha = 1.0; }
    else if (_selectedCurve == "EI") { k = 80.0; alpha = 2.0; }
    else if (_selectedCurve == "LTI") { k = 120.0; alpha = 1.0; }

    final m = _faultCurrent / _pickupCurrent;
    final denom = pow(m, alpha) - 1.0;
    if (denom <= 0) return double.infinity;
    return _tms * (k / denom);
  }

  // IEC 60364 Gerilim Düşümü Motoru
  double get _voltDropPercent {
    final rho = _isCopper ? 0.0175 : 0.028; // ohm*mm²/m
    final r = (rho * _cableLength) / _selectedSection;
    final deltaU = sqrt(3) * _loadCurrent * r * 0.85; // cos phi ~ 0.85
    return (deltaU / 400.0) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFFFFB300), size: 26),
            const SizedBox(width: 8),
            const Text(
              'POWER SUITE',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF30363D)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<AppLanguage>(
              value: _lang,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF161B22),
              items: const [
                DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 13))),
              ],
              onChanged: (l) => setState(() => _lang = l!),
            ),
          )
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF30363D), width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: const Color(0xFF161B22),
          indicatorColor: const Color(0xFFFFB300).withValues(alpha: 0.2),
          selectedIndex: _currentTab,
          onDestinationSelected: (i) => setState(() => _currentTab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.speed, color: Colors.grey),
              selectedIcon: const Icon(Icons.speed, color: Color(0xFFFFB300)),
              label: t('relay'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.cable, color: Colors.grey),
              selectedIcon: const Icon(Icons.cable, color: Color(0xFFFFB300)),
              label: t('cable'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.fact_check, color: Colors.grey),
              selectedIcon: const Icon(Icons.fact_check, color: Color(0xFFFFB300)),
              label: t('sat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTab) {
      case 0:
        return _buildRelayProtectionView();
      case 1:
        return _buildCableSizingView();
      case 2:
        return _buildCommissioningSatView();
      default:
        return const SizedBox();
    }
  }

  // --- SEKME 1: RÖLE ARAYÜZÜ ---
  Widget _buildRelayProtectionView() {
    final tSec = _tripTimeSeconds;
    final isTrip = tSec.isFinite && tSec > 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudDisplayCard(
          title: t('trip_time'),
          value: isTrip ? '${tSec.toStringAsFixed(3)} s' : 'NO TRIP (I ≤ Is)',
          subValue: isTrip ? '${(tSec * 1000).toStringAsFixed(0)} ms' : '---',
          isWarning: !isTrip,
          accentColor: const Color(0xFFFFB300),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: t('curve_type'),
          child: DropdownButtonFormField<String>(
            value: _selectedCurve,
            dropdownColor: const Color(0xFF161B22),
            decoration: _inputDecoration(),
            items: const [
              DropdownMenuItem(value: "SI", child: Text("Standard Inverse (SI)")),
              DropdownMenuItem(value: "VI", child: Text("Very Inverse (VI)")),
              DropdownMenuItem(value: "EI", child: Text("Extremely Inverse (EI)")),
              DropdownMenuItem(value: "LTI", child: Text("Long Time Inverse (LTI)")),
            ],
            onChanged: (v) => setState(() => _selectedCurve = v!),
          ),
        ),
        const SizedBox(height: 12),
        _buildSliderCard(t('fault_i'), _faultCurrent, 100, 25000, 100, (v) => setState(() => _faultCurrent = v)),
        _buildSliderCard(t('pickup_is'), _pickupCurrent, 50, 2500, 10, (v) => setState(() => _pickupCurrent = v)),
        _buildSliderCard(t('tms'), _tms, 0.05, 1.20, 0.01, (v) => setState(() => _tms = v)),
      ],
    );
  }

  // --- SEKME 2: KABLO & ΔU ARAYÜZÜ ---
  Widget _buildCableSizingView() {
    final drop = _voltDropPercent;
    final isOk = drop <= 3.0; // IEC / TEDAŞ %3 Kriteri

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudDisplayCard(
          title: t('volt_drop'),
          value: '%${drop.toStringAsFixed(2)}',
          subValue: isOk ? '${t('pass')} (ΔU ≤ 3.0%)' : '${t('fail')} (ΔU > 3.0%)',
          isWarning: !isOk,
          accentColor: isOk ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: t('section'),
          child: DropdownButtonFormField<double>(
            value: _selectedSection,
            dropdownColor: const Color(0xFF161B22),
            decoration: _inputDecoration(),
            items: _standardSections.map((s) {
              return DropdownMenuItem(value: s, child: Text('$s mm²', style: const TextStyle(fontWeight: FontWeight.bold)));
            }).toList(),
            onChanged: (v) => setState(() => _selectedSection = v!),
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('conductor'),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("Bakır / Cu")),
                  selected: _isCopper,
                  selectedColor: const Color(0xFFFFB300),
                  onSelected: (val) => setState(() => _isCopper = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("Alüminyum / Al")),
                  selected: !_isCopper,
                  selectedColor: const Color(0xFFFFB300),
                  onSelected: (val) => setState(() => _isCopper = false),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSliderCard(t('length'), _cableLength, 10, 800, 5, (v) => setState(() => _cableLength = v)),
        _buildSliderCard(t('load_i'), _loadCurrent, 5, 400, 1, (v) => setState(() => _loadCurrent = v)),
      ],
    );
  }

  // --- SEKME 3: SAHA KABUL & DEVREYE ALMA (SAT) ---
  Widget _buildCommissioningSatView() {
    final maxRes = max(_resR, max(_resS, _resT));
    final isResOk = maxRes <= _maxAllowedRes;
    final deltaSyncMs = [
      (_openTimeR - _openTimeS).abs(),
      (_openTimeS - _openTimeT).abs(),
      (_openTimeR - _openTimeT).abs()
    ].reduce(max);
    final isSyncOk = deltaSyncMs <= 3.0; // IEC 62271 Δt ≤ 3ms kriteri

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: "Ekipman & Lokasyon",
          child: Column(
            children: [
              TextField(controller: _substationController, decoration: _inputDecoration(label: "Trafo Merkezi")),
              const SizedBox(height: 8),
              TextField(controller: _breakerController, decoration: _inputDecoration(label: "Hücre / Kesici Kodu")),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('contact_res'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildValueInput("R (µΩ)", _resR, (v) => setState(() => _resR = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildValueInput("S (µΩ)", _resS, (v) => setState(() => _resS = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildValueInput("T (µΩ)", _resT, (v) => setState(() => _resT = v))),
                ],
              ),
              const SizedBox(height: 8),
              _buildStatusBadge(isResOk ? "Direnç Uygun (≤ $_maxAllowedRes µΩ)" : "Yüksek Geçiş Direnci!", isResOk),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: t('breaker_timing'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildValueInput("tR (ms)", _openTimeR, (v) => setState(() => _openTimeR = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildValueInput("tS (ms)", _openTimeS, (v) => setState(() => _openTimeS = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildValueInput("tT (ms)", _openTimeT, (v) => setState(() => _openTimeT = v))),
                ],
              ),
              const SizedBox(height: 8),
              _buildStatusBadge("Δt Kutuplar Arası: ${deltaSyncMs.toStringAsFixed(1)} ms (Limit ≤ 3ms)", isSyncOk),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF30363D)),
          ),
          tileColor: const Color(0xFF161B22),
          activeColor: const Color(0xFFFFB300),
          title: const Text("5 Altın Kural / LOTO Teyidi", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text(_lotoVerified ? "Topraklama ve kilitler uygulandı" : "Güvenlik adımları eksik!", style: TextStyle(fontSize: 12, color: _lotoVerified ? Colors.grey : Colors.red)),
          value: _lotoVerified,
          onChanged: (v) => setState(() => _lotoVerified = v),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.share, color: Colors.black),
          label: Text(t('summary'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          onPressed: () {
            _showSummaryDialog(context, isResOk && isSyncOk && _lotoVerified);
          },
        ),
      ],
    );
  }

  // --- YARDIMCI GÖRSEL BİLEŞENLER (HUD ELEMANLARI) ---
  Widget _buildHudDisplayCard({
    required String title,
    required String value,
    required String subValue,
    required bool isWarning,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isWarning ? const Color(0xFFFF3D00) : accentColor.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: isWarning ? const Color(0xFFFF3D00) : accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(subValue, style: TextStyle(color: isWarning ? Colors.redAccent : Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSliderCard(String title, double val, double min, double max, double step, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70)),
              Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
            ],
          ),
          Slider(
            value: val,
            min: min,
            max: max,
            activeColor: const Color(0xFFFFB300),
            inactiveColor: const Color(0xFF30363D),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildValueInput(String label, double initialVal, ValueChanged<double> onChanged) {
    return TextFormField(
      initialValue: initialVal.toString(),
      keyboardType: TextInputType.number,
      decoration: _inputDecoration(label: label),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _buildStatusBadge(String text, bool isPass) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: isPass ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPass ? Colors.green : Colors.red),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: isPass ? Colors.greenAccent : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  InputDecoration _inputDecoration({String? label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: const Color(0xFF0D1117),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFB300))),
    );
  }

  void _showSummaryDialog(BuildContext context, bool overallPass) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF30363D))),
        title: Text(t('summary'), style: const TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tesis: ${_substationController.text}"),
            Text("Ekipman: ${_breakerController.text}"),
            const Divider(color: Color(0xFF30363D)),
            Text("Kontak R-S-T: $_resR / $_resS / $_resT µΩ"),
            Text("Zaman tR-tS-tT: $_openTimeR / $_openTimeS / $_openTimeT ms"),
            Text("LOTO: ${_lotoVerified ? 'UYGULANDI' : 'YAPILMADI'}"),
            const SizedBox(height: 12),
            _buildStatusBadge(overallPass ? "TESTTEN GEÇTİ (PASSED)" : "UYGUN DEĞİL (FAILED)", overallPass),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("KAPAT", style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}
