import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const PowerFieldProApp());
}

class PowerFieldProApp extends StatelessWidget {
  const PowerFieldProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerField Pro',
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

enum AppLanguage { tr, en, de }
enum CellType { incomer, feeder, coupler, vtMetering, transformer }

// Bağımsız Kesici Kataloğu
class BreakerModel {
  final String name;
  final String vendor;
  final String type; // Vakum / SF6
  final double defaultLimitMicroOhm;
  final double typicalTripTimeMs;

  const BreakerModel(this.name, this.vendor, this.type, this.defaultLimitMicroOhm, this.typicalTripTimeMs);
}

const List<BreakerModel> kBreakers = [
  BreakerModel("Schneider LF2 / LF3 (SF6)", "Schneider Electric", "SF6 Gazlı", 40.0, 42.0),
  BreakerModel("Schneider Evolis (Vakum)", "Schneider Electric", "Vakum", 35.0, 38.0),
  BreakerModel("Siemens SION 3AE / 3AH", "Siemens", "Vakum", 45.0, 44.0),
  BreakerModel("ABB VD4 (Vakum)", "ABB", "Vakum", 38.0, 40.0),
  BreakerModel("ABB HD4 (SF6)", "ABB", "SF6 Gazlı", 42.0, 45.0),
  BreakerModel("Alstom / Areva HVX", "Alstom", "Vakum", 48.0, 48.0),
  BreakerModel("TEDAŞ Standart Yerli Vakum", "Yerli / TEDAŞ", "Vakum", 50.0, 45.0),
  BreakerModel("Özel Kesici (Manuel Giriş)", "Özel", "Belirtilmemiş", 50.0, 45.0),
];

// Bağımsız Röle Kataloğu ve Sahadaki Menü Yolları
class RelayModel {
  final String name;
  final String vendor;
  final String menuPath;

  const RelayModel(this.name, this.vendor, this.menuPath);
}

const List<RelayModel> kRelays = [
  RelayModel(
    "Schneider Sepam 20 / 40 / 80",
    "Schneider Electric",
    "Sepam Tuş Takımı: Sarı Koruma Tuşu -> Koruma (Protection) -> Faz Aşırı Akım (50/51) -> Is (A) ve TMS değerleri.",
  ),
  RelayModel(
    "Schneider Easergy P3 / P5",
    "Schneider Electric",
    "Easergy Menü: Parametreler -> Koruma Grubu 1 -> 51 Aşırı Akım -> Is (A) ve Zaman Eğrisi (k katsayısı).",
  ),
  RelayModel(
    "Siemens Siprotec 4 (7SJ61/62/64)",
    "Siemens",
    "Siprotec 4: Menü -> Settings -> P.System Data -> Function 50/51 -> 51 Pickup (Is) & 51 Time Dial (TMS).",
  ),
  RelayModel(
    "Siemens Siprotec 5 (7SJ82/85)",
    "Siemens",
    "Siprotec 5: Ana Menü -> Function Group Line -> Overcurrent 51-1 -> Settings values (I> ve t> gecikmesi).",
  ),
  RelayModel(
    "ABB Relion REF615 / REF620",
    "ABB",
    "REF615 HMI: Main Menu -> Settings -> Protection -> PHIPTOC1 (51) -> Start value & Time multiplier.",
  ),
  RelayModel(
    "Alstom / Areva MiCOM P122 / P123",
    "Alstom",
    "MiCOM Menü: Configuration -> Group 1 Current Protection -> I> Set (A) & I> TMS çarpanı.",
  ),
  RelayModel(
    "Kael / Mikro / Yerli Röle",
    "Yerli",
    "Ön Panel Menü: Ayarlar -> Koruma -> 51 Eşik Akımı ve Eğri Seçimi (SI/VI/EI).",
  ),
  RelayModel(
    "Özel / Bilinmeyen Röle",
    "Özel",
    "Cihaz üzerindeki ANSI 50/51 ayar menüsüne veya tek hat üzerindeki röle ayar tablosuna bakınız.",
  ),
];

const List<String> kSwitchgears = [
  "Schneider SM6-36 (Hava Yalıtımlı / Metal-Enclosed)",
  "Schneider MCset (Metal-Clad Çekmeceli)",
  "Siemens 8BT2 (Metal-Clad 36 kV)",
  "Siemens NXAIR (Hava Yalıtımlı Metal-Clad)",
  "ABB UniGear ZS1 (Metal-Clad)",
  "Alstom Fluokit M24",
  "Ulusoy HMH-36 / Astor (TEDAŞ Modüler)",
  "Özel / Açık Şalt Tipi",
];

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  String ctRatio;

  SwitchgearCell({
    required this.id,
    required this.name,
    required this.type,
    this.cbClosed = false,
    this.ctRatio = "400/5A",
  });
}

class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});

  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> {
  int _activeTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  // --- BAĞIMSIZ MARKA SEÇİMLERİ ---
  int _selectedSwitchgearIdx = 0;
  int _selectedBreakerIdx = 0;
  int _selectedRelayIdx = 0;

  BreakerModel get _activeBreaker => kBreakers[_selectedBreakerIdx];
  RelayModel get _activeRelay => kRelays[_selectedRelayIdx];
  String get _activeSwitchgear => kSwitchgears[_selectedSwitchgearIdx];

  // --- 1. ŞEBEKE & TRAFO ---
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  // --- 2. RÖLE, SELEKTİVİTE & TEST ---
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";
  double _testPrimaryCurrent = 1200.0;
  double _ctPrimaryRatio = 400.0;
  double _ctSecondaryRatio = 5.0;

  // --- 3. KESİCİ SAHA KABUL (SAT) ---
  double _resR = 36.2;
  double _resS = 38.5;
  double _resT = 37.1;
  double _timeR = 42.0;
  double _timeS = 43.5;
  double _timeT = 42.8;

  // --- 4. KABLO, ARK & İKLİM ---
  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;
  double _workingDistanceMm = 610.0;
  double _ambientTemp = 28.0;
  double _altitudeMeters = 50.0;
  double _relativeHumidity = 60.0;
  String _locationName = "İzmir, TR (Varsayılan)";
  bool _isLoadingWeather = false;

  // --- 5. HÜCRE DİZİLİMİ ---
  final List<SwitchgearCell> _cells = [
    SwitchgearCell(id: "C1", name: "H01 TR-1 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
    SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true),
    SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false),
    SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C5", name: "H05 Fider 2", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C6", name: "H06 TR-2 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
  ];

  String t(String k) {
    const d = {
      'net': {'tr': 'Şebeke & Trafo', 'en': 'Grid & Trafo', 'de': 'Netz & Trafo'},
      'relay': {'tr': 'Röle & Enjeksiyon', 'en': 'Relay & Test', 'de': 'Schutz & Prüf.'},
      'sat': {'tr': 'Kesici SAT Teşhis', 'en': 'CB Diagnostics', 'de': 'LS Diagnose'},
      'cable': {'tr': 'Kablo & Ark', 'en': 'Cable & Arc', 'de': 'Kabel & Lichtb.'},
      'sld': {'tr': 'Şalt & SLD', 'en': 'Switchgear', 'de': 'Schaltanlage'},
    };
    return d[k]?[_lang.name] ?? k;
  }

  // --- HESAPLAMALAR ---
  double get _ikKa {
    final zt = (_ukPercent / 100.0) * (pow(_voltageKv, 2) / _trafoMva);
    if (zt <= 0) return 0.0;
    return (1.10 * _voltageKv) / (sqrt(3) * zt);
  }

  double get _trafoNominalCurrentA => (_trafoMva * 1000.0) / (sqrt(3) * _voltageKv);
  double get _trafoInrushCurrentA => _trafoNominalCurrentA * 10.0;
  double get _testSecondaryCurrent => _testPrimaryCurrent * (_ctSecondaryRatio / _ctPrimaryRatio);

  double get _altitudeDeratingKa {
    if (_altitudeMeters <= 1000) return 1.0;
    return exp((_altitudeMeters - 1000) / 8150.0);
  }

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

  // --- ÇOKLU YEDEKLİ CANLI İKLİM & RAKIM MOTORU ---
  Future<void> _fetchLiveEnvironment() async {
    setState(() => _isLoadingWeather = true);
    String errorDetail = "";
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..userAgent = "Mozilla/5.0 (Mobile; PowerFieldPro)";

      double? lat, lon;
      String city = "Saha";

      // Deneme 1: ipwho.is
      try {
        final r = await client.getUrl(Uri.parse('https://ipwho.is/'));
        final res = await r.close();
        if (res.statusCode == 200) {
          final b = jsonDecode(await res.transform(utf8.decoder).join());
          if (b['success'] == true) {
            lat = (b['latitude'] as num).toDouble();
            lon = (b['longitude'] as num).toDouble();
            city = b['city'] ?? city;
          }
        }
      } catch (e) {
        errorDetail = e.toString();
      }

      // Deneme 2: freeipapi.com (Yedek)
      if (lat == null) {
        try {
          final r = await client.getUrl(Uri.parse('https://freeipapi.com/api/json'));
          final res = await r.close();
          if (res.statusCode == 200) {
            final b = jsonDecode(await res.transform(utf8.decoder).join());
            lat = (b['latitude'] as num?)?.toDouble();
            lon = (b['longitude'] as num?)?.toDouble();
            city = b['cityName'] ?? city;
          }
        } catch (e) {
          errorDetail = e.toString();
        }
      }

      if (lat != null && lon != null) {
        // Open-Meteo ile kesin rakım ve sıcaklık
        final wUri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m&elevation=nan');
        final wReq = await client.getUrl(wUri);
        final wRes = await wReq.close();
        if (wRes.statusCode == 200) {
          final wData = jsonDecode(await wRes.transform(utf8.decoder).join());
          setState(() {
            _locationName = "$city";
            _ambientTemp = (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? _ambientTemp;
            _relativeHumidity = (wData['current']?['relative_humidity_2m'] as num?)?.toDouble() ?? _relativeHumidity;
            _altitudeMeters = (wData['elevation'] as num?)?.toDouble() ?? _altitudeMeters;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: const Color(0xFF00E676), content: Text("✓ Konum Alındı: $_locationName | ${_altitudeMeters.toInt()}m")),
            );
          }
          return;
        }
      }
      throw Exception(errorDetail.isNotEmpty ? errorDetail : "Sunucuya ulaşılamadı.");
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF3D00),
            duration: const Duration(seconds: 4),
            content: Text("Canlı veri hatası: $err\n(AndroidManifest internet iznini veya aşağıdaki hazır şehirleri kullanın)"),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFFFFB300), content: Text("Yüklendi: $name (${alt.toInt()} m)")),
    );
  }

  // --- SAHA REHBERİ (FIELD GUIDE) ---
  void _showFieldGuide(String title, String whatIsIt, String whereToLook, String vendorHint, String standardRule) {
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
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)))),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 20),
            _buildGuideItem("1. Mühendislik Mantığı", whatIsIt),
            _buildGuideItem("2. Sahada Nereye Bakılır?", whereToLook),
            _buildGuideItem("3. Seçili Rölede Menü Yolu (${_activeRelay.name})", _activeRelay.menuPath, isHighlight: true),
            _buildGuideItem("4. Standart & Kural", standardRule),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF151921),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFFFB300), size: 24),
            SizedBox(width: 8),
            Text('POWERFIELD PRO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 17)),
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
                DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 12))),
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
          NavigationDestination(icon: const Icon(Icons.tune), label: t('relay')),
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
      case 1: return _buildRelayAndTestTab();
      case 2: return _buildBreakerDiagnosticsTab();
      case 3: return _buildCableArcTab();
      case 4: return _buildSwitchgearSldTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // SEKME 0: ŞEBEKE, TRAFO & İKLİM
  // ==========================================
  Widget _buildGridTab() {
    final inA = _trafoNominalCurrentA;
    final inrushA = _trafoInrushCurrentA;
    final isAltitudeHigh = _altitudeMeters > 1000;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "3 FAZ KISA DEVRE AKIMI (Ik'')",
          "${_ikKa.toStringAsFixed(2)} kA",
          "Anma: ${inA.toStringAsFixed(1)} A | Demeraj (10xIn): ${inrushA.toStringAsFixed(0)} A",
          onInfoTap: () => _showFieldGuide(
            "Kısa Devre Akımı (Ik'')",
            "Trafo empedansı üzerinden oluşacak simetrik tepe arıza akımıdır.",
            "Trafo ve hücre kapağındaki etiketlere bakılır.",
            _activeRelay.menuPath,
            "IEC 60909 Standardı.",
          ),
        ),
        const SizedBox(height: 14),
        _buildEditableSlider("Sistem Gerilimi (kV)", _voltageKv, 0.4, 36.0, (v) => setState(() => _voltageKv = v)),
        _buildEditableSlider("Trafo Gücü Sn (MVA)", _trafoMva, 0.1, 40.0, (v) => setState(() => _trafoMva = v)),
        _buildEditableSlider("Kısa Devre Empedansı (%uk)", _ukPercent, 3.0, 14.0, (v) => setState(() => _ukPercent = v)),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Saha İklim, Sıcaklık & Rakım (IEC 62271-1)",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "$_locationName (${_ambientTemp.toStringAsFixed(1)}°C / ${_altitudeMeters.toInt()}m / %${_relativeHumidity.toInt()})",
                      style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: _isLoadingWeather
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.gps_fixed, size: 14),
                    label: const Text("Canlı Çek", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _isLoadingWeather ? null : _fetchLiveEnvironment,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text("Bodrum/Çevrimdışı Hızlı Şehir Şablonları:", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(label: const Text("İzmir (25m / 30°C)", style: TextStyle(fontSize: 10)), onPressed: () => _applyCityPreset("İzmir", 30.0, 25.0, 65.0)),
                  ActionChip(label: const Text("İstanbul (40m / 24°C)", style: TextStyle(fontSize: 10)), onPressed: () => _applyCityPreset("İstanbul", 24.0, 40.0, 72.0)),
                  ActionChip(label: const Text("Ankara (950m / 22°C)", style: TextStyle(fontSize: 10)), onPressed: () => _applyCityPreset("Ankara", 22.0, 950.0, 45.0)),
                  ActionChip(label: const Text("Erzurum (1890m / 14°C)", style: TextStyle(fontSize: 10)), onPressed: () => _applyCityPreset("Erzurum / Yüksek İrtifa", 14.0, 1890.0, 40.0)),
                ],
              ),
              const Divider(color: Color(0xFF30363D)),
              Text(
                isAltitudeHigh
                    ? "• DİKKAT: Rakım > 1000m (Ka = ${_altitudeDeratingKa.toStringAsFixed(3)}). Şalt test gerilimi artırılmalı!"
                    : "• Rakım ≤ 1000m (Ka = 1.000). Standart fabrika test gerilimleri geçerlidir.",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isAltitudeHigh ? Colors.redAccent : Colors.greenAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 1: RÖLE & ENJEKSİYON TESTİ
  // ==========================================
  Widget _buildRelayAndTestTab() {
    final faultA = _ikKa * 1000.0;
    final tUp = _calcTripTime(faultA, _upIs, _upTms, _upCurve);
    final tDown = _calcTripTime(faultA, _downIs, _downTms, _downCurve);
    final deltaT = (tUp.isFinite && tDown.isFinite) ? (tUp - tDown) : 0.0;
    final isSelective = deltaT >= 0.30;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "SELEKTİVİTE MARJİNİ (Δt)",
          "${(deltaT * 1000).toStringAsFixed(0)} ms",
          isSelective ? "UYGUN (TEDAŞ Δt ≥ 300ms)" : "RİSKLİ! İki kesici aynı anda açabilir",
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide(
            "Selektivite Marjini (Δt)",
            "Fider arızasında sadece fiderin açması, girişin bekletilmesi için gereken emniyet farkıdır.",
            "Röle koordinasyon grafiğindeki düşey zaman aralığıdır.",
            _activeRelay.menuPath,
            "TEDAŞ ve IEC standardına göre asgari fark 300 ms olmalıdır.",
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: "Sekonder Enjeksiyon Test Çevirici (Omicron / CIBANO)",
          child: Row(
            children: [
              Expanded(child: _buildEditableSlider("Primer Akım (A)", _testPrimaryCurrent, 10, 5000, (v) => setState(() => _testPrimaryCurrent = v))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF0B0E14), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFB300))),
                child: Column(
                  children: [
                    const Text("Röleye Basılacak", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("${_testSecondaryCurrent.toStringAsFixed(2)} A", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
                    Text("(${_ctPrimaryRatio.toInt()}/${_ctSecondaryRatio.toInt()}A)", style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Upstream (Giriş) & Downstream (Fider) Röleleri",
          child: Column(
            children: [
              _buildEditableSlider("Upstream Eşik Is (A)", _upIs, 50, 3000, (v) => setState(() => _upIs = v)),
              _buildEditableSlider("Upstream TMS", _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v)),
              const Divider(color: Color(0xFF30363D)),
              _buildEditableSlider("Downstream Eşik Is (A)", _downIs, 20, 1500, (v) => setState(() => _downIs = v)),
              _buildEditableSlider("Downstream TMS", _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 2: KESİCİ SAHA KABUL & BAĞIMSIZ MARKA SEÇİMİ
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
        // 1. BAĞIMSIZ MARKA VE DONANIM SEÇİM KARTI
        _buildSectionCard(
          title: "Saha Ekipman Yapılandırması (Bağımsız Seçim)",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Hücre Modeli:", style: TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedSwitchgearIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kSwitchgears.length, (i) => DropdownMenuItem(value: i, child: Text(kSwitchgears[i], style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedSwitchgearIdx = v!),
              ),
              const SizedBox(height: 8),
              const Text("Kesici Modeli (Limit Direnç Otomatik Güncellenir):", style: TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedBreakerIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kBreakers.length, (i) => DropdownMenuItem(value: i, child: Text("${kBreakers[i].name} (≤${kBreakers[i].defaultLimitMicroOhm.toInt()}µΩ)", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedBreakerIdx = v!),
              ),
              const SizedBox(height: 8),
              const Text("Koruma Rölesi Modeli ((i) Butonu Menü Yolunu Verir):", style: TextStyle(fontSize: 10, color: Colors.grey)),
              DropdownButtonFormField<int>(
                value: _selectedRelayIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kRelays.length, (i) => DropdownMenuItem(value: i, child: Text(kRelays[i].name, style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedRelayIdx = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildHudCard(
          "SAT TEŞHİS: ${_activeBreaker.name}",
          isOverallPass ? "TESTTEN GEÇTİ (PASS)" : "KUSURLU (FAIL)",
          "Limit: ≤ ${limit.toInt()} µΩ | Ölçülen: ${maxRes.toStringAsFixed(1)} µΩ | Asimetri: %${resAsym.toStringAsFixed(1)}",
          accentColor: isOverallPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide(
            "Ductor Kontak Direnci Ölçümü",
            "Kesici ana kontaklarının birbirine temas kalitesidir.",
            "Kesici kutup başlarına mikro-ohmmetre ile 100A DC basılarak ölçülür.",
            _activeRelay.menuPath,
            "TEDAŞ-MLZ ve IEC 62271-100 gereği faz asimetrisi %15'i geçemez.",
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: "R-S-T Kontak Geçiş Dirençleri (µΩ)",
          child: Column(
            children: [
              _buildEditableSlider("R Kutbu Direnci (µΩ)", _resR, 10, 100, (v) => setState(() => _resR = v)),
              _buildEditableSlider("S Kutbu Direnci (µΩ)", _resS, 10, 100, (v) => setState(() => _resS = v)),
              _buildEditableSlider("T Kutbu Direnci (µΩ)", _resT, 10, 100, (v) => setState(() => _resT = v)),
              if (!isAsymOk)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text("UYARI: Kutuplar arası direnç farkı > %15! Yay baskısı bozuk veya kontak aşınmış.", style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Açma Süresi & Kutuplar Arası Senkronizm (ms)",
          child: Column(
            children: [
              _buildEditableSlider("tR Açma Zamanı (ms)", _timeR, 20, 90, (v) => setState(() => _timeR = v)),
              _buildEditableSlider("tS Açma Zamanı (ms)", _timeS, 20, 90, (v) => setState(() => _timeS = v)),
              _buildEditableSlider("tT Açma Zamanı (ms)", _timeT, 20, 90, (v) => setState(() => _timeT = v)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Senkronizm Farkı (Δt): ${deltaSyncMs.toStringAsFixed(1)} ms", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSyncOk ? Colors.greenAccent : Colors.redAccent)),
                  Text(isSyncOk ? "Uygun (Δt ≤ 3ms)" : "Senkronizm Hatası!", style: TextStyle(fontSize: 11, color: isSyncOk ? Colors.green : Colors.red)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 3: KABLO & ARK
  // ==========================================
  Widget _buildCableArcTab() {
    final ikAmps = _ikKa * 1000.0;
    final sMin = (ikAmps * sqrt(0.15)) / (_isCopper ? 143.0 : 94.0);
    final isSafe = _cableSection >= sMin;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard("ADYABATİK KABLO TAHKİKİ", "${_cableSection.toInt()} mm²", "Kısa Devrede Erimeyen Asgari Smin: ${sMin.toStringAsFixed(1)} mm²"),
        const SizedBox(height: 14),
        _buildEditableSlider("Seçilen Kesit (mm²)", _cableSection, 16, 400, (v) => setState(() => _cableSection = v)),
        _buildEditableSlider("Hat Boyu (m)", _cableLength, 10, 1000, (v) => setState(() => _cableLength = v)),
        _buildEditableSlider("Yük Akımı (A)", _loadCurrent, 10, 600, (v) => setState(() => _loadCurrent = v)),
        _buildEditableSlider("Ark Mesafesi (mm)", _workingDistanceMm, 300, 1200, (v) => setState(() => _workingDistanceMm = v)),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Termik Dayanım Kararı",
          child: Text(
            isSafe ? "Seçilen kesit kısa devre süresince erimez, güvenlidir." : "TEHLİKE! Kısa devrede kablo aşırı ısınır veya patlar!",
            style: TextStyle(fontWeight: FontWeight.bold, color: isSafe ? Colors.greenAccent : Colors.redAccent),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 4: ŞALT DİZİLİMİ & KİLİTLENMEYEN RAHAT SLD
  // ==========================================
  Widget _buildSwitchgearSldTab() {
    final canvasWidth = max(MediaQuery.of(context).size.width * 1.6, _cells.length * 115.0 + 100.0);
    const canvasHeight = 330.0;

    return Column(
      children: [
        // RAHAT KAYDIRILABİLİR (PAN & ZOOM) ÇİZİM ALANI
        Expanded(
          flex: 6,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF30363D), width: 1.5)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                constrained: false, // KİLİTLENMEYİ BİTİREN KOD
                boundaryMargin: const EdgeInsets.symmetric(horizontal: 200, vertical: 80),
                minScale: 0.4,
                maxScale: 2.5,
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasHeight,
                  child: CustomPaint(
                    size: Size(canvasWidth, canvasHeight),
                    painter: DynamicSwitchgearPainter(cells: _cells, voltageKv: _voltageKv, ikKa: _ikKa, activeSwitchgear: _activeSwitchgear),
                  ),
                ),
              ),
            ),
          ),
        ),
        // HÜCRE LİSTESİ & KESİCİ KONTROLLERİ
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("HÜCRELER (SAĞA-SOLA KAYDIRILABİLİR)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Hücre Ekle", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _showAddCellDialog,
                    ),
                  ],
                ),
              ),
              Expanded(
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
                        subtitle: Text("CT: ${c.ctRatio} | ${_activeBreaker.vendor}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        trailing: IconButton(
                          icon: Icon(c.cbClosed ? Icons.power : Icons.power_off, color: c.cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)),
                          tooltip: "Kesici Aç/Kapa",
                          onPressed: () => _toggleCellBreaker(i),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleCellBreaker(int index) {
    final cell = _cells[index];
    if (cell.type == CellType.coupler && !cell.cbClosed) {
      final incomersClosed = _cells.where((c) => c.type == CellType.incomer && c.cbClosed).length;
      if (incomersClosed >= 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFFF3D00), content: Text("2/3 KİLİTLEME İHLALİ: Girişler devredeyken Kuplaj kapatılamaz!")),
        );
        return;
      }
    }
    setState(() => cell.cbClosed = !cell.cbClosed);
  }

  void _showAddCellDialog() {
    String name = "H0${_cells.length + 1} Yeni Fider";
    CellType type = CellType.feeder;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF151921),
          title: const Text("Yeni Hücre Ekle", style: TextStyle(color: Color(0xFFFFB300), fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: const InputDecoration(labelText: "Hücre Adı"), onChanged: (v) => name = v),
              const SizedBox(height: 10),
              DropdownButtonFormField<CellType>(
                value: type,
                dropdownColor: const Color(0xFF151921),
                items: const [
                  DropdownMenuItem(value: CellType.feeder, child: Text("Çıkış / Fider")),
                  DropdownMenuItem(value: CellType.incomer, child: Text("Giriş Hücresi")),
                  DropdownMenuItem(value: CellType.coupler, child: Text("Bara Kuplaj")),
                ],
                onChanged: (v) => setDState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
              onPressed: () {
                setState(() => _cells.add(SwitchgearCell(id: "C${_cells.length + 1}", name: name, type: type, cbClosed: true)));
                Navigator.pop(ctx);
              },
              child: const Text("Ekle"),
            ),
          ],
        ),
      ),
    );
  }

  // --- YARDIMCI BİLEŞENLER ---
  Widget _buildEditableSlider(String title, double val, double min, double max, ValueChanged<double> onChanged) {
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
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              InkWell(
                onTap: () => _showManualInputDialog(title, val, onChanged),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFB300)), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 12)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: Color(0xFFFFB300)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Slider(value: val.clamp(min, max), min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  void _showManualInputDialog(String title, double current, ValueChanged<double> onEntered) {
    final c = TextEditingController(text: current.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151921),
        title: Text(title, style: const TextStyle(fontSize: 14, color: Color(0xFFFFB300))),
        content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
            onPressed: () {
              final parsed = double.tryParse(c.text);
              if (parsed != null) onEntered(parsed);
              Navigator.pop(ctx);
            },
            child: const Text("Tamam"),
          ),
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
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: accentColor)),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 8), child]),
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
// VEKTÖREL VE AKICI SLD ÇİZİM MOTORU
// ==========================================
class DynamicSwitchgearPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final double voltageKv;
  final double ikKa;
  final String activeSwitchgear;

  DynamicSwitchgearPainter({
    required this.cells,
    required this.voltageKv,
    required this.ikKa,
    required this.activeSwitchgear,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final busY = h * 0.42;
    const bayWidth = 115.0;

    final busPaint = Paint()..color = const Color(0xFFFFB300)..strokeWidth = 4.5;
    final linePaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(25, busY), Offset(totalBusWidth - 25, busY), busPaint);
    _drawText(canvas, "ANA BARA: ${voltageKv.toStringAsFixed(1)} kV | Ik'': ${ikKa.toStringAsFixed(1)} kA | [$activeSwitchgear]", const Offset(25, 12), const Color(0xFFFFB300), 10);

    for (int i = 0; i < cells.length; i++) {
      final x = 60.0 + (i * bayWidth);
      final cell = cells[i];

      // Hücre Çerçevesi
      final borderPaint = Paint()..color = const Color(0xFF21262D)..style = PaintingStyle.stroke..strokeWidth = 1.2;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 32, bayWidth - 12, h - 45), borderPaint);

      _drawText(canvas, cell.name, Offset(x - 40, 38), Colors.white70, 9);

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
        canvas.drawCircle(Offset(x, busY + 54), 5, linePaint);
        canvas.drawCircle(Offset(x, busY + 62), 5, linePaint);
        canvas.drawCircle(Offset(x, h * 0.82), 3.5, Paint()..color = const Color(0xFFFFB300));
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

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
