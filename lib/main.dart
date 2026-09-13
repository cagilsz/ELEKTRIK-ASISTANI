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

// Ekipman & Marka Kataloğu Modeli
class EquipmentPreset {
  final String name;
  final String vendor;
  final String switchgear;
  final String breaker;
  final String relay;
  final double defaultResLimit; // µΩ
  final double typicalTripTime; // ms
  final String relayMenuPath;
  final String ctTerminals;

  const EquipmentPreset({
    required this.name,
    required this.vendor,
    required this.switchgear,
    required this.breaker,
    required this.relay,
    required this.defaultResLimit,
    required this.typicalTripTime,
    required this.relayMenuPath,
    required this.ctTerminals,
  });
}

const List<EquipmentPreset> kEquipmentPresets = [
  EquipmentPreset(
    name: "Schneider Electric (SM6-36 + LF2 + Sepam 40)",
    vendor: "Schneider Electric",
    switchgear: "SM6-36 (Hava Yalıtımlı / SF6 Kesicili)",
    breaker: "LF2 (SF6 Gazlı Kesici)",
    relay: "Sepam Seri 40 / Easergy P3",
    defaultResLimit: 40.0,
    typicalTripTime: 42.0,
    relayMenuPath: "Sepam: Sarı Tuş -> Koruma (Protection) -> Faz Aşırı Akım (50/51) -> Is ve TMS | Easergy: Parametreler -> Grup 1 -> 51 -> Is (A) ve k çarpanı",
    ctTerminals: "Koruma: 2S1 - 2S2 | Sayaç/Ölçü: 1S1 - 1S2 (Kablo kompartımanındaki blok akım trafosu)",
  ),
  EquipmentPreset(
    name: "Schneider Electric (MCset + Evolis + Easergy P5)",
    vendor: "Schneider Electric",
    switchgear: "MCset (Metal-Clad Çekmeceli)",
    breaker: "Evolis (Vakum Kesici)",
    relay: "Easergy P5 / Sepam 80",
    defaultResLimit: 35.0,
    typicalTripTime: 38.0,
    relayMenuPath: "Easergy P5: Setting -> Protection -> Group 1 -> 50/51 Phase Overcurrent",
    ctTerminals: "Toroidal veya döküm CT klemensleri (Hücre içi klemens kutusu)",
  ),
  EquipmentPreset(
    name: "Siemens (8BT2 / NXAIR + SION 3AE + Siprotec)",
    vendor: "Siemens",
    switchgear: "8BT2 / NXAIR (Metal-Clad)",
    breaker: "SION 3AE / 3AH (Vakum Kesici)",
    relay: "Siprotec 4 (7SJ6x) / Siprotec 5 (7SJ8x)",
    defaultResLimit: 45.0,
    typicalTripTime: 45.0,
    relayMenuPath: "Siprotec 4: Settings -> P.System Data -> Function 50/51 -> 51 Pickup & Time Dial | Siprotec 5: Function Group Line -> 51 Phase",
    ctTerminals: "X100 Klemens Bloğu: 1S1-1S2 (Sayaç), 2S1-2S2 (Koruma)",
  ),
  EquipmentPreset(
    name: "ABB (UniGear ZS1 + VD4 + Relion REF615)",
    vendor: "ABB",
    switchgear: "UniGear ZS1 (Metal-Clad)",
    breaker: "VD4 (Vakum Kesici)",
    relay: "Relion REF615 / REF620",
    defaultResLimit: 38.0,
    typicalTripTime: 40.0,
    relayMenuPath: "REF615: Main Menu -> Settings -> Protection -> PHIPTOC1 (51) -> Start value & Time multiplier",
    ctTerminals: "X120 Klemens Grubu (Kısa devre köprülü klemensler)",
  ),
  EquipmentPreset(
    name: "Alstom / Areva (Fluokit M24 + HVX + MiCOM P123)",
    vendor: "Alstom / Areva",
    switchgear: "Fluokit M24 / Alspa (Klasik Hücre)",
    breaker: "HVX (Vakum) / FP Serisi",
    relay: "MiCOM P122 / P123",
    defaultResLimit: 50.0,
    typicalTripTime: 50.0,
    relayMenuPath: "MiCOM: Configuration -> Group 1 Current -> I> Set (A) & I> TMS",
    ctTerminals: "Klemens Paneli: A1-A2, B1-B2",
  ),
  EquipmentPreset(
    name: "TEDAŞ Standart / Yerli (Ulusoy HMH-36 / Astor)",
    vendor: "TEDAŞ Uyumlu (Ulusoy / Astor)",
    switchgear: "HMH-36 (Hava Yalıtımlı Modüler)",
    breaker: "Yerli Vakum / SF6 Kesici",
    relay: "Easergy / REF615 / Kael / Mikro",
    defaultResLimit: 50.0,
    typicalTripTime: 45.0,
    relayMenuPath: "Röle Tuş Takımı: Ayarlar -> Koruma -> Aşırı Akım (50/51) Eşik ve Eğri Seçimi",
    ctTerminals: "TEDAŞ MYD Şartnamesi gereği klemens kapağı mühürlü 0.2S sayaç ve 5P20 koruma terminalleri",
  ),
];

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  bool earthClosed;
  String ctRatio;
  String ctClass;

  SwitchgearCell({
    required this.id,
    required this.name,
    required this.type,
    this.cbClosed = false,
    this.earthClosed = false,
    this.ctRatio = "400/5A",
    this.ctClass = "5P20 15VA + 0.2S 10VA",
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

  // Aktif Ekipman & Marka Şablonu
  int _selectedPresetIndex = 0;
  EquipmentPreset get _activePreset => kEquipmentPresets[_selectedPresetIndex];

  // --- 1. ŞEBEKE & TRAFO ---
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  // --- 2. RÖLE, SELEKTİVİTE & ENJEKSİYON ---
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";
  double _testPrimaryCurrent = 1200.0;
  double _ctPrimaryRatio = 400.0;
  double _ctSecondaryRatio = 5.0;

  // --- 3. KESİCİ SAHA KABUL (SAT) TEŞHİS ---
  double _resR = 36.2;
  double _resS = 38.5;
  double _resT = 37.1;
  double _timeR = 43.2;
  double _timeS = 44.5;
  double _timeT = 43.8;

  // --- 4. KABLO, ARK & ÇEVRESEL KOŞULLAR ---
  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;
  double _workingDistanceMm = 610.0;
  double _ambientTemp = 28.0;
  double _altitudeMeters = 50.0;
  double _relativeHumidity = 60.0;
  String _locationName = "Manuel / Saha";
  bool _isLoadingWeather = false;

  // --- 5. HÜCRE DİZİLİMİ ---
  final List<SwitchgearCell> _cells = [
    SwitchgearCell(id: "C1", name: "H01 TR-1 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
    SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true),
    SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false),
    SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C5", name: "H05 TR-2 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
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

  // --- CANLI İKLİM & RAKIM MOTORU (HTTPS) ---
  Future<void> _fetchLiveEnvironment() async {
    setState(() => _isLoadingWeather = true);
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final ipReq = await client.getUrl(Uri.parse('https://ipwho.is/'));
      final ipRes = await ipReq.close();

      if (ipRes.statusCode == 200) {
        final ipBody = await ipRes.transform(utf8.decoder).join();
        final ipData = jsonDecode(ipBody);

        if (ipData['success'] == true) {
          final lat = ipData['latitude'];
          final lon = ipData['longitude'];
          final city = ipData['city'] ?? 'Saha';

          final wUri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m&elevation=nan');
          final wReq = await client.getUrl(wUri);
          final wRes = await wReq.close();

          if (wRes.statusCode == 200) {
            final wBody = await wRes.transform(utf8.decoder).join();
            final wData = jsonDecode(wBody);

            setState(() {
              _locationName = "$city (${ipData['country_code']})";
              _ambientTemp = (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? _ambientTemp;
              _relativeHumidity = (wData['current']?['relative_humidity_2m'] as num?)?.toDouble() ?? _relativeHumidity;
              _altitudeMeters = (wData['elevation'] as num?)?.toDouble() ?? _altitudeMeters;
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: const Color(0xFF00E676), content: Text("Konum Alındı: $_locationName | ${_altitudeMeters.toInt()}m")),
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
          const SnackBar(backgroundColor: Color(0xFFFF3D00), content: Text("Bağlantı sağlanamadı. Çevrimdışı hazır şablonları kullanabilirsiniz.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  void _applyPresetLocation(String name, double temp, double alt, double humidity) {
    setState(() {
      _locationName = name;
      _ambientTemp = temp;
      _altitudeMeters = alt;
      _relativeHumidity = humidity;
    });
  }

  // --- "SAHADA NEREYE BAKACAĞIM?" BİLGİ PENCERESİ (MODAL) ---
  void _showFieldGuide(String title, String whatIsIt, String whereToLook, String vendorSpecificHint, String standardRule) {
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
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)))),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 24),
            _buildGuideItem("1. Mühendislik Mantığı Nedir?", whatIsIt),
            _buildGuideItem("2. Sahada Fiziksel Olarak Nereye Bakılır?", whereToLook),
            _buildGuideItem("3. Seçili Cihazda Menü Yolu (${_activePreset.vendor})", vendorSpecificHint, isHighlight: true),
            _buildGuideItem("4. TEDAŞ & IEC Standart Kuralı", standardRule),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Anladım, Kapat", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideItem(String heading, String content, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isHighlight ? const Color(0xFFFFB300) : Colors.grey)),
          const SizedBox(height: 3),
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
  // SEKME 0: ŞEBEKE, TRAFO & CANLI ÇEVRE
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
            "3 Faz Kısa Devre Akımı (Ik'')",
            "Trafo empedansı üzerinden geçebilecek en büyük simetrik arıza akımıdır. Kesici kesme kapasitesini belirler.",
            "Trafo ve hücre etiketindeki Icu / Icw değerlerine bakılır. Bu akım kesicinin dayanma sınırını (örn. 16kA / 25kA) aşmamalıdır.",
            "Schneider SM6 veya Siemens 8BT2 hücrelerde tipik bara dayanımı 16 kA / 1s veya 25 kA / 1s olarak etiketlenir.",
            "IEC 60909 standardına göre hesaplanır.",
          ),
        ),
        const SizedBox(height: 14),
        _buildEditableSlider(
          "Sistem Gerilimi (kV)", _voltageKv, 0.4, 36.0, (v) => setState(() => _voltageKv = v),
          infoTap: () => _showFieldGuide(
            "Sistem Gerilimi (Un)",
            "Şebekenin nominal çalışma gerilimidir.",
            "Tek hat şemasındaki fider başlığına veya hücre ön kapağındaki Ur etiketine bakılır.",
            "TEDAŞ dağıtımında 34.5 kV standarttır. Endüstriyel tesislerde 6.3 kV veya 10.5 kV sıkça kullanılır.",
            "TEDAŞ MYD Standartları.",
          ),
        ),
        _buildEditableSlider(
          "Trafo Gücü Sn (MVA)", _trafoMva, 0.1, 40.0, (v) => setState(() => _trafoMva = v),
          infoTap: () => _showFieldGuide(
            "Trafo Anma Gücü (Sn)",
            "Trafonun sürekli taşıyabileceği görünür güç kapasitesidir.",
            "Trafonun üzerindeki pirinç metal plakada (Nameplate) 'Rating / Power: ... kVA' satırında yazar.",
            "Örn: 1600 kVA trafonun 34.5 kV'daki anma akımı yaklaşık 26.8 A'dir.",
            "IEC 60076-1 Güç Transformatörleri Standardı.",
          ),
        ),
        _buildEditableSlider(
          "Kısa Devre Empedansı (%uk)", _ukPercent, 3.0, 14.0, (v) => setState(() => _ukPercent = v),
          infoTap: () => _showFieldGuide(
            "Bağıl Kısa Devre Gerilimi (%uk)",
            "Trafonun iç direncini temsil eder. Bu değer büyüdükçe kısa devre akımı düşer.",
            "Trafo etiketindeki '%uk' veya 'Impedance Voltage' satırına bakılır.",
            "Standart dağıtım trafolarında %4 veya %6 yazar. Büyük güç trafolarında %8 ile %12 arasındadır.",
            "IEC 60076 toleransı: ±%10 sapmaya izin verilir.",
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Saha İklim & Rakım Düzeltmesi (IEC 62271-1)",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "$_locationName (${_ambientTemp.toStringAsFixed(1)}°C / ${_altitudeMeters.toInt()}m / %${_relativeHumidity.toInt()} Nem)",
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
              const Text("Şebekesiz Bodrum İçin Hazır Şablonlar:", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: const Text("Kıyı Şeridi (25m)", style: TextStyle(fontSize: 10)),
                    onPressed: () => _applyPresetLocation("Kıyı Şeridi", 32.0, 25.0, 68.0),
                  ),
                  ActionChip(
                    label: const Text("İç Anadolu (950m)", style: TextStyle(fontSize: 10)),
                    onPressed: () => _applyPresetLocation("İç Anadolu", 26.0, 950.0, 42.0),
                  ),
                  ActionChip(
                    label: const Text("Yüksek Dağ / Santral (1850m)", style: TextStyle(fontSize: 10)),
                    onPressed: () => _applyPresetLocation("Yüksek İrtifa Santral", 18.0, 1850.0, 50.0),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF30363D)),
              Text(
                isAltitudeHigh
                    ? "• DİKKAT: Rakım > 1000m (Ka = ${_altitudeDeratingKa.toStringAsFixed(3)}). Şalt yalıtım test gerilimi artırılmalıdır!"
                    : "• Rakım ≤ 1000m (Ka = 1.000). Standart fabrika dielektrik mesafeleri uygundur.",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isAltitudeHigh ? Colors.redAccent : Colors.greenAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 1: RÖLE SELEKTİVİTESİ & ENJEKSİYON TESTİ
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
          isSelective ? "UYGUN (TEDAŞ/IEC Δt ≥ 300ms)" : "RİSKLİ! İki kesici aynı anda açabilir",
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide(
            "Selektivite Marjini (Δt)",
            "Fider arızasında sadece fider kesicisinin açması, ana giriş kesicisinin beklemesi için gereken zaman emniyet farkıdır.",
            "Koordinasyon eğrisi (TCC) grafiğinde iki eğrinin arıza akımındaki düşey mesafesidir.",
            "TEDAŞ ve TEİAŞ fiderlerinde asgari emniyet marjini Δt ≥ 300 - 400 ms olmalıdır.",
            "IEC 60255 / TEDAŞ Röle Koordinasyon Kılavuzu.",
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: "Sekonder Enjeksiyon Test Çevirici (Omicron / CIBANO)",
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildEditableSlider("Primer Akım (A)", _testPrimaryCurrent, 10, 5000, (v) => setState(() => _testPrimaryCurrent = v)),
                  ),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Giriş (Upstream) & Fider (Downstream) Ayarları",
          child: Column(
            children: [
              _buildEditableSlider(
                "Upstream Eşik Is (A)", _upIs, 50, 3000, (v) => setState(() => _upIs = v),
                infoTap: () => _showFieldGuide(
                  "Eşik Akımı (Is / Pickup Current)",
                  "Rölenin arıza saymaya başladığı asgari akım değeridir.",
                  "Röle ekranında 'Settings -> Protection -> 51 Pickup' menüsünde yazar.",
                  _activePreset.relayMenuPath,
                  "Nominal akımın yaklaşık 1.2 katına ayarlanır.",
                ),
              ),
              _buildEditableSlider(
                "Upstream TMS (Zaman Çarpanı)", _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v),
                infoTap: () => _showFieldGuide(
                  "Zaman Çarpanı (TMS / Time Dial)",
                  "Ters zamanlı eğriyi dikey eksende yukarı-aşağı öteleyerek açma süresini belirler.",
                  "Röle ekranında 'TMS', 'Time Dial' veya 'k çarpanı' olarak geçer.",
                  _activePreset.relayMenuPath,
                  "IEC 60255 Standart Ters Zaman Eğrisi (SI).",
                ),
              ),
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
  // SEKME 2: KESİCİ SAHA KABUL (SAT) VE MARKA SEÇİMİ
  // ==========================================
  Widget _buildBreakerDiagnosticsTab() {
    final limit = _activePreset.defaultResLimit;
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
        // MARKA & ŞALT EKİPMANI SEÇİCİ
        _buildSectionCard(
          title: "Ekipman & Hücre Şablonu",
          child: DropdownButtonFormField<int>(
            value: _selectedPresetIndex,
            isExpanded: true,
            dropdownColor: const Color(0xFF151921),
            decoration: _inputDeco(),
            items: List.generate(
              kEquipmentPresets.length,
              (i) => DropdownMenuItem(
                value: i,
                child: Text(kEquipmentPresets[i].name, style: const TextStyle(fontSize: 12)),
              ),
            ),
            onChanged: (idx) => setState(() => _selectedPresetIndex = idx!),
          ),
        ),
        const SizedBox(height: 12),
        _buildHudCard(
          "SAT TEŞHİS: ${_activePreset.breaker}",
          isOverallPass ? "KABUL EDİLDİ (PASS)" : "UYGUNSUZ (FAIL)",
          "Limit: ≤ ${limit.toInt()} µΩ | Ölçülen Maks: ${maxRes.toStringAsFixed(1)} µΩ | Asimetri: %${resAsym.toStringAsFixed(1)}",
          accentColor: isOverallPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide(
            "Kontak Geçiş Direnci (Ductor Ölçümü)",
            "Kesici ana kontaklarının birbirine basma kalitesini ölçer. Yüksek direnç aşırı ısınmaya ve patlamaya yol açar.",
            "Kesici kutup başlarına 100A DC akım basılarak (mikro-ohmmetre ile) ölçülür.",
            "${_activePreset.breaker} için fabrika üst limiti: ≤ ${limit.toInt()} µΩ. Kutuplar arası asimetri ≤ %15 olmalıdır.",
            "TEDAŞ-MLZ/96-015 ve IEC 62271-100.",
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
                  child: Text("UYARI: Kutuplar arası direnç farkı > %15! Kontak baskı yayları ayarsız veya aşınmış.", style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
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
                  Text(isSyncOk ? "IEC Kuralına Uygun (≤ 3ms)" : "Hata: Senkronizm Aşıldı!", style: TextStyle(fontSize: 11, color: isSyncOk ? Colors.green : Colors.red)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 3: KABLO & ARK PARLAMASI
  // ==========================================
  Widget _buildCableArcTab() {
    final ikAmps = _ikKa * 1000.0;
    final sMin = (ikAmps * sqrt(0.15)) / (_isCopper ? 143.0 : 94.0);
    final isSafe = _cableSection >= sMin;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "ADYABATİK KABLO TAHKİKİ",
          "${_cableSection.toInt()} mm²",
          "Kısa Devrede Erimeyen Asgari Smin: ${sMin.toStringAsFixed(1)} mm²",
          accentColor: isSafe ? const Color(0xFFFFB300) : const Color(0xFFFF3D00),
          onInfoTap: () => _showFieldGuide(
            "Adyabatik Termik Dayanım (Smin)",
            "Kısa devre süresince kablo izolasyonunun aşırı ısınıp kömürleşmemesi için gereken asgari kesittir.",
            "Kablo başlığı montajı öncesinde kablo dış kılıfı üzerindeki '3x... mm² YE3SV' yazısına bakılır.",
            "Bakır/XLPE için k=143, Alüminyum/XLPE için k=94 katsayısı kullanılır.",
            "IEC 60364-5-54 Standardı.",
          ),
        ),
        const SizedBox(height: 14),
        _buildEditableSlider("Seçilen Kesit (mm²)", _cableSection, 16, 400, (v) => setState(() => _cableSection = v)),
        _buildEditableSlider("Hat Boyu (m)", _cableLength, 10, 1000, (v) => setState(() => _cableLength = v)),
        _buildEditableSlider("Yük Akımı (A)", _loadCurrent, 10, 600, (v) => setState(() => _loadCurrent = v)),
        _buildEditableSlider("Ark Çalışma Mesafesi (mm)", _workingDistanceMm, 300, 1200, (v) => setState(() => _workingDistanceMm = v)),
      ],
    );
  }

  // ==========================================
  // SEKME 4: ŞALT DİZİLİMİ & İNTERAKTİF SLD
  // ==========================================
  Widget _buildSwitchgearSldTab() {
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
                boundaryMargin: const EdgeInsets.all(30),
                minScale: 0.5,
                maxScale: 3.0,
                child: CustomPaint(
                  size: Size(max(MediaQuery.of(context).size.width, _cells.length * 90.0 + 40), double.infinity),
                  painter: DynamicSwitchgearPainter(cells: _cells, voltageKv: _voltageKv, ikKa: _ikKa),
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
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text("CT: ${c.ctRatio} | ${_activePreset.vendor}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  trailing: IconButton(
                    icon: Icon(c.cbClosed ? Icons.power : Icons.power_off, color: c.cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)),
                    onPressed: () => _toggleCellBreaker(i),
                  ),
                ),
              );
            },
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
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: infoTap,
                    ),
                ],
              ),
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
// VEKTÖREL ÇİZİM MOTORU (CANVAS)
// ==========================================
class DynamicSwitchgearPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final double voltageKv;
  final double ikKa;

  DynamicSwitchgearPainter({required this.cells, required this.voltageKv, required this.ikKa});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final busY = h * 0.40;
    final bayWidth = 90.0;

    final busPaint = Paint()..color = const Color(0xFFFFB300)..strokeWidth = 4.0;
    final linePaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 1.8..style = PaintingStyle.stroke;

    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(20, busY), Offset(totalBusWidth - 20, busY), busPaint);
    _drawText(canvas, "ANA BARA: ${voltageKv.toStringAsFixed(1)} kV (Ik'': ${ikKa.toStringAsFixed(1)} kA)", const Offset(24, 15), const Color(0xFFFFB300), 11);

    for (int i = 0; i < cells.length; i++) {
      final x = 50.0 + (i * bayWidth);
      final cell = cells[i];

      final borderPaint = Paint()..color = const Color(0xFF21262D)..style = PaintingStyle.stroke..strokeWidth = 1.0;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 35, bayWidth - 12, h - 50), borderPaint);

      _drawText(canvas, cell.name.split(' ').first, Offset(x - 20, 42), Colors.white70, 9);

      if (cell.type == CellType.incomer) {
        canvas.drawLine(Offset(x, 60), Offset(x, busY - 14), linePaint);
        _drawBreaker(canvas, Offset(x, busY - 22), cell.cbClosed);
        canvas.drawLine(Offset(x, busY - 14), Offset(x, busY), linePaint);
      } else if (cell.type == CellType.coupler) {
        _drawBreaker(canvas, Offset(x, busY), cell.cbClosed);
      } else {
        canvas.drawLine(Offset(x, busY), Offset(x, busY + 20), linePaint);
        _drawBreaker(canvas, Offset(x, busY + 28), cell.cbClosed);
        canvas.drawLine(Offset(x, busY + 36), Offset(x, h * 0.78), linePaint);
        canvas.drawCircle(Offset(x, busY + 52), 5, linePaint);
        canvas.drawCircle(Offset(x, busY + 60), 5, linePaint);
        canvas.drawCircle(Offset(x, h * 0.78), 3, Paint()..color = const Color(0xFFFFB300));
      }
    }
  }

  void _drawBreaker(Canvas canvas, Offset center, bool isClosed) {
    final rect = Rect.fromCenter(center: center, width: 14, height: 14);
    final fill = Paint()..color = isClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676);
    final stroke = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
    if (!isClosed) {
      canvas.drawLine(Offset(center.dx - 4, center.dy - 4), Offset(center.dx + 4, center.dy + 4), stroke);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
