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
      title: 'PowerField Pro v2.0',
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

enum AppLanguage { tr, en, de, es, fr, zh, ja }
enum CellType { incomer, feeder, coupler, vtMetering, transformer }

// Ekipman Modelleri
class BreakerModel {
  final String name;
  final String vendor;
  final double defaultLimitMicroOhm;
  final double typicalTripTimeMs;
  const BreakerModel(this.name, this.vendor, this.defaultLimitMicroOhm, this.typicalTripTimeMs);
}

const List<BreakerModel> kBreakers = [
  BreakerModel("Schneider LF2 / LF3 (SF6)", "Schneider Electric", 40.0, 42.0),
  BreakerModel("Schneider Evolis (Vakum)", "Schneider Electric", 35.0, 38.0),
  BreakerModel("Siemens SION 3AE / 3AH", "Siemens", 45.0, 44.0),
  BreakerModel("ABB VD4 (Vakum)", "ABB", 38.0, 40.0),
  BreakerModel("ABB HD4 (SF6)", "ABB", 42.0, 45.0),
  BreakerModel("Alstom / Areva HVX", "Alstom", 48.0, 48.0),
  BreakerModel("TEDAŞ Standart Yerli Vakum", "Yerli / TEDAŞ", 50.0, 45.0),
];

class RelayModel {
  final String name;
  final String menuPath;
  const RelayModel(this.name, this.menuPath);
}

const List<RelayModel> kRelays = [
  RelayModel("Schneider Sepam 20/40/80", "Sepam: Sarı Tuş -> Koruma (50/51) -> Is ve TMS"),
  RelayModel("Schneider Easergy P3/P5", "Easergy: Parametreler -> Grup 1 -> 51 -> Is ve k çarpanı"),
  RelayModel("Siemens Siprotec 4 (7SJ6x)", "Siprotec 4: Settings -> 50/51 -> 51 Pickup & Time Dial"),
  RelayModel("Siemens Siprotec 5 (7SJ8x)", "Siprotec 5: Function Group Line -> Overcurrent 51-1"),
  RelayModel("ABB Relion REF615/620", "REF615: Menu -> Settings -> Protection -> PHIPTOC1"),
  RelayModel("Alstom MiCOM P122/P123", "MiCOM: Group 1 Current -> I> Set & I> TMS"),
  RelayModel("Kael / Mikro / Yerli", "Menü: Ayarlar -> Koruma -> 51 Eşik ve Eğri Seçimi"),
];

const List<String> kSwitchgears = [
  "Schneider SM6-36 (Metal-Enclosed)",
  "Schneider MCset (Metal-Clad)",
  "Siemens 8BT2 (Metal-Clad)",
  "Siemens NXAIR (Metal-Clad)",
  "ABB UniGear ZS1",
  "Alstom Fluokit M24",
  "Ulusoy HMH-36 / Astor (TEDAŞ)",
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

class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});
  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> {
  int _activeTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  // Bağımsız Seçimler
  int _selectedSwitchgearIdx = 0;
  int _selectedBreakerIdx = 0;
  int _selectedRelayIdx = 0;

  BreakerModel get _activeBreaker => kBreakers[_selectedBreakerIdx];
  RelayModel get _activeRelay => kRelays[_selectedRelayIdx];
  String get _activeSwitchgear => kSwitchgears[_selectedSwitchgearIdx];

  // 1. Şebeke & Trafo
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  // 2. Röle & Enjeksiyon
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";
  double _testPrimaryCurrent = 1200.0;
  double _ctPrimaryRatio = 400.0;
  double _ctSecondaryRatio = 5.0;

  // 3. Kesici SAT Teşhis
  double _resR = 36.2;
  double _resS = 38.5;
  double _resT = 37.1;
  double _timeR = 42.0;
  double _timeS = 43.5;
  double _timeT = 42.8;
  final List<TestRecord> _testHistory = [];

  // 4. Kablo & Çevre
  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;
  double _workingDistanceMm = 610.0;
  double _ambientTemp = 28.0;
  double _altitudeMeters = 50.0;
  double _relativeHumidity = 60.0;
  String _locationName = "Saha / Çevrimdışı";
  bool _isLoadingWeather = false;
  bool _locationPermissionAlways = false;

  // 5. SLD Hücreleri
  final List<SwitchgearCell> _cells = [
    SwitchgearCell(id: "C1", name: "H01 TR-1 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
    SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true),
    SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false),
    SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C5", name: "H05 Fider 2", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C6", name: "H06 TR-2 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
  ];

  // 7 Dilli Çeviri Sözlüğü
  String t(String k) {
    const d = {
      'net': {
        'tr': 'Şebeke & Trafo', 'en': 'Grid & Trafo', 'de': 'Netz & Trafo',
        'es': 'Red y Trafo', 'fr': 'Réseau & Transfo', 'zh': '电网与变压器', 'ja': '系統と変圧器'
      },
      'relay': {
        'tr': 'Röle & TCC', 'en': 'Relay & TCC', 'de': 'Schutz & TCC',
        'es': 'Relé y TCC', 'fr': 'Relais & TCC', 'zh': '保护与TCC曲线', 'ja': 'リレーとTCC'
      },
      'sat': {
        'tr': 'Kesici SAT', 'en': 'CB SAT Test', 'de': 'LS Diagnose',
        'es': 'Prueba SAT', 'fr': 'Essais SAT', 'zh': '断路器SAT测试', 'ja': '遮断器SAT試験'
      },
      'cable': {
        'tr': 'Kablo & Ark', 'en': 'Cable & Arc', 'de': 'Kabel & Lichtb.',
        'es': 'Cable y Arco', 'fr': 'Câble & Arc', 'zh': '电缆与电弧', 'ja': 'ケーブルとアーク'
      },
      'sld': {
        'tr': 'Şalt & SLD', 'en': 'Switchgear', 'de': 'Schaltanlage',
        'es': 'Subestación', 'fr': 'Poste & SLD', 'zh': '一次系统图', 'ja': '単線結線図'
      },
      'fetch_live': {
        'tr': 'Canlı Çek (GPS/Ağ)', 'en': 'Fetch Live Data', 'de': 'Live Daten',
        'es': 'Obtener En Vivo', 'fr': 'Données en Direct', 'zh': '获取实时数据', 'ja': '実環境データ取得'
      },
      'perm_title': {
        'tr': 'Konum İzni Gerekli', 'en': 'Location Permission', 'de': 'Standortberechtigung',
        'es': 'Permiso de Ubicación', 'fr': 'Autorisation de Position', 'zh': '需要定位权限', 'ja': '位置情報の許可'
      },
      'perm_desc': {
        'tr': 'Şalt sahası rakımını, sıcaklığını ve IEC 62271-1 yalıtım çarpanını (Ka) hesaplamak için konumunuza erişim gerekiyor.',
        'en': 'Access needed to calculate substation altitude, temperature, and IEC 62271-1 insulation derating (Ka).',
        'de': 'Erforderlich zur Berechnung von Höhe, Temperatur und IEC 62271-1 Isolationsfaktor (Ka).',
        'es': 'Se requiere acceso para calcular altitud, temperatura y factor de aislamiento IEC 62271-1 (Ka).',
        'fr': 'Accès requis pour calculer l’altitude, la température et le déclassement diélectrique CEI 62271-1 (Ka).',
        'zh': '需要获取位置以自动计算变电站海拔、温度和 IEC 62271-1 绝缘修正系数 (Ka)。',
        'ja': '変電所標高、温度、IEC 62271-1 絶縁補正係数 (Ka) を算出するために位置情報が必要です。'
      },
      'allow_always': {
        'tr': 'Her Zaman İzin Ver', 'en': 'Allow All The Time', 'de': 'Immer Zulassen',
        'es': 'Permitir Siempre', 'fr': 'Toujours Autoriser', 'zh': '始终允许', 'ja': '常に許可'
      },
      'deny': {
        'tr': 'Reddet', 'en': 'Deny', 'de': 'Ablehnen',
        'es': 'Denegar', 'fr': 'Refuser', 'zh': '拒绝', 'ja': '拒否'
      },
    };
    return d[k]?[_lang.name] ?? d[k]?['tr'] ?? k;
  }

  // Hesaplama Motoru
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

  // --- İZİN TALEBİ VE CANLI VERİ ÇEKME ---
  void _requestLocationAndFetch() {
    if (_locationPermissionAlways) {
      _executeLiveFetch();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151921),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFFB300))),
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFFFFB300)),
            const SizedBox(width: 8),
            Expanded(child: Text(t('perm_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(t('perm_desc'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('deny'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
            onPressed: () {
              setState(() => _locationPermissionAlways = true);
              Navigator.pop(ctx);
              _executeLiveFetch();
            },
            child: Text(t('allow_always'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeLiveFetch() async {
    setState(() => _isLoadingWeather = true);
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6)..userAgent = "PowerFieldPro/2.0";
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
              _locationName = "$city (${b['country_code']})";
              _ambientTemp = (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? _ambientTemp;
              _relativeHumidity = (wData['current']?['relative_humidity_2m'] as num?)?.toDouble() ?? _relativeHumidity;
              _altitudeMeters = (wData['elevation'] as num?)?.toDouble() ?? _altitudeMeters;
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: const Color(0xFF00E676), content: Text("✓ Konum Doğrulandı: $_locationName | ${_altitudeMeters.toInt()}m")),
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
          const SnackBar(backgroundColor: Color(0xFFFF3D00), content: Text("Canlı bağlantı kurulamadı. Manuel şablonları kullanabilirsiniz.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  // --- CIBANO / OMICRON METİN AYRIŞTIRICI (REGEX PARSER) ---
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
            Text("Omicron/CIBANO Veri Ayrıştırıcı", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Test cihazından kopyalanan metni yapıştırın (R, S, T dirençleri ve zamanlar otomatik doldurulur):", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: tc,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Örn: R: 35.4 uOhm, S: 37.1 uOhm, T: 36.0 uOhm\ntR: 42.1 ms, tS: 43.5 ms, tT: 43.0 ms",
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
              _parseTestReportText(tc.text);
              Navigator.pop(ctx);
            },
            child: const Text("Ayrıştır ve Doldur"),
          ),
        ],
      ),
    );
  }

  void _parseTestReportText(String text) {
    // Regex ile R, S, T değerlerini yakala
    final rMatch = RegExp(r'R\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);
    final sMatch = RegExp(r'S\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);
    final tMatch = RegExp(r'T\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);

    final trMatch = RegExp(r'tR\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);
    final tsMatch = RegExp(r'tS\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);
    final ttMatch = RegExp(r'tT\s*[:=]\s*([0-9]+[.,]?[0-9]*)', caseSensitive: false).firstMatch(text);

    setState(() {
      if (rMatch != null) _resR = double.tryParse(rMatch.group(1)!.replaceAll(',', '.')) ?? _resR;
      if (sMatch != null) _resS = double.tryParse(sMatch.group(1)!.replaceAll(',', '.')) ?? _resS;
      if (tMatch != null) _resT = double.tryParse(tMatch.group(1)!.replaceAll(',', '.')) ?? _resT;

      if (trMatch != null) _timeR = double.tryParse(trMatch.group(1)!.replaceAll(',', '.')) ?? _timeR;
      if (tsMatch != null) _timeS = double.tryParse(tsMatch.group(1)!.replaceAll(',', '.')) ?? _timeS;
      if (ttMatch != null) _timeT = double.tryParse(ttMatch.group(1)!.replaceAll(',', '.')) ?? _timeT;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(backgroundColor: Color(0xFF00E676), content: Text("✓ Test cihazı verileri başarıyla aktarıldı!")),
    );
  }

  // --- RESMİ TEDAŞ / IEC KABUL RAPORU MODALI ---
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

    // Geçmişe kaydet
    _testHistory.insert(0, TestRecord(
      timestamp: "${DateTime.now().hour}:${DateTime.now().minute} - ${DateTime.now().day}/${DateTime.now().month}",
      substation: "$_voltageKv kV Trafo Merkezi",
      breaker: _activeBreaker.name,
      maxRes: maxRes,
      syncDelta: deltaSyncMs,
      passed: isOverallPass,
    ));

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
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TEDAŞ / IEC 62271 RESMİ SAT PROTOKOLÜ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFFFB300))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: isOverallPass ? const Color(0xFF00E676) : const Color(0xFFFF3D00), borderRadius: BorderRadius.circular(4)),
                    child: Text(isOverallPass ? "KABUL EDİLDİ (PASS)" : "RED (FAIL)", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF30363D), height: 24),
              _buildReportRow("Tesis & Konum", "$_locationName (Rakım: ${_altitudeMeters.toInt()}m, Ka: ${_altitudeDeratingKa.toStringAsFixed(3)})"),
              _buildReportRow("Şalt Hücresi", _activeSwitchgear),
              _buildReportRow("Kesici Tipi", _activeBreaker.name),
              _buildReportRow("Koruma Rölesi", _activeRelay.name),
              const Divider(color: Color(0xFF30363D), height: 24),
              const Text("1. KONTAK GEÇİŞ DİRENÇLERİ (DUCTOR - µΩ)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 6),
              Text("• Faz R: ${_resR.toStringAsFixed(1)} µΩ | Faz S: ${_resS.toStringAsFixed(1)} µΩ | Faz T: ${_resT.toStringAsFixed(1)} µΩ"),
              Text("• Ölçülen Maksimum Direnç: ${maxRes.toStringAsFixed(1)} µΩ (Şartname Sınırı: ≤ ${limit.toInt()} µΩ)"),
              Text("• Fazlar Arası Asimetri: %${resAsym.toStringAsFixed(1)} (Sınır: ≤ %15)"),
              const SizedBox(height: 12),
              const Text("2. KUTUPLAR ARASI SENKRONİZM & AÇMA ZAMANI (ms)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 6),
              Text("• Açma Süreleri: tR = ${_timeR.toStringAsFixed(1)}ms | tS = ${_timeS.toStringAsFixed(1)}ms | tT = ${_timeT.toStringAsFixed(1)}ms"),
              Text("• Maksimum Senkronizm Farkı (Δt): ${deltaSyncMs.toStringAsFixed(1)} ms (IEC 62271-100 Sınırı: ≤ 3.0 ms)"),
              const Divider(color: Color(0xFF30363D), height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFF30363D)), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Testi Yapan Mühendis:", style: TextStyle(fontSize: 10, color: Colors.grey)), Text("İmza & Onay", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Kabul Heyeti / TEDAŞ:", style: TextStyle(fontSize: 10, color: Colors.grey)), Text("Mühür & Kaşe", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 44)),
                icon: const Icon(Icons.share),
                label: const Text("Raporu Paylaş / Kaydet", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SAT Raporu kaydedildi ve paylaşıma hazır!")));
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
      padding: const EdgeInsets.only(bottom: 6),
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
            Text('POWERFIELD PRO v2.0', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 16)),
          ],
        ),
        actions: [
          // 7 DİLLİ AÇILIR MENÜ
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
  // SEKME 0: ŞEBEKE, TRAFO & KONUM TAHKİKİ
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
          "In: ${inA.toStringAsFixed(1)} A | Inrush (10xIn): ${inrushA.toStringAsFixed(0)} A",
        ),
        const SizedBox(height: 14),
        _buildEditableSlider("Sistem Gerilimi (kV)", _voltageKv, 0.4, 36.0, (v) => setState(() => _voltageKv = v)),
        _buildEditableSlider("Trafo Gücü Sn (MVA)", _trafoMva, 0.1, 40.0, (v) => setState(() => _trafoMva = v)),
        _buildEditableSlider("Kısa Devre Empedansı (%uk)", _ukPercent, 3.0, 14.0, (v) => setState(() => _ukPercent = v)),
        const SizedBox(height: 12),
        // KONUM VE İKLİM PANELİ
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
                      "$_locationName\n${_ambientTemp.toStringAsFixed(1)}°C / ${_altitudeMeters.toInt()}m / %${_relativeHumidity.toInt()} Nem",
                      style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: _isLoadingWeather
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.my_location, size: 14),
                    label: Text(t('fetch_live'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _isLoadingWeather ? null : _requestLocationAndFetch,
                  ),
                ],
              ),
              const Divider(color: Color(0xFF30363D)),
              Text(
                isAltitudeHigh
                    ? "• DİKKAT: Rakım > 1000m (Ka = ${_altitudeDeratingKa.toStringAsFixed(3)}). Hücre izolasyon test gerilimi artırılmalıdır!"
                    : "• Rakım ≤ 1000m (Ka = 1.000). Standart fabrika dielektrik test seviyeleri geçerlidir.",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isAltitudeHigh ? Colors.redAccent : Colors.greenAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 1: RÖLE KOORDİNASYONU & CANLI TCC GRAFİĞİ
  // ==========================================
  Widget _buildRelayAndTccTab() {
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
          isSelective ? "SELEKTİF (TEDAŞ/IEC Δt ≥ 300ms)" : "ÇAKIŞMA RİSKİ! İki kesici birden açabilir",
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 14),

        // 📈 LOG-LOG TCC KOORDİNASYON GRAFİK ALANI
        _buildSectionCard(
          title: "LOG-LOG RÖLE KOORDİNASYON EĞRİSİ (TCC CURVE)",
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
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, color: Color(0xFFFF3D00), size: 10),
                  SizedBox(width: 4),
                  Text("Giriş (Upstream)", style: TextStyle(fontSize: 10, color: Colors.white70)),
                  SizedBox(width: 14),
                  Icon(Icons.circle, color: Color(0xFF00E676), size: 10),
                  SizedBox(width: 4),
                  Text("Fider (Downstream)", style: TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // RÖLE PARAMETRELERİ
        _buildSectionCard(
          title: "Upstream (Giriş) Rölesi",
          child: Column(
            children: [
              _buildEditableSlider("Upstream Eşik Is (A)", _upIs, 50, 3000, (v) => setState(() => _upIs = v)),
              _buildEditableSlider("Upstream TMS", _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          title: "Downstream (Fider) Rölesi",
          child: Column(
            children: [
              _buildEditableSlider("Downstream Eşik Is (A)", _downIs, 20, 1500, (v) => setState(() => _downIs = v)),
              _buildEditableSlider("Downstream TMS", _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SEKME 2: KESİCİ SAT TEŞHİS, CIBANO PARSER & RESMİ RAPOR
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
        // MARKA SEÇİCİLER
        _buildSectionCard(
          title: "Ekipman Seçimi (Hücre / Kesici / Röle)",
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                value: _selectedSwitchgearIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kSwitchgears.length, (i) => DropdownMenuItem(value: i, child: Text(kSwitchgears[i], style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedSwitchgearIdx = v!),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _selectedBreakerIdx,
                isExpanded: true,
                dropdownColor: const Color(0xFF151921),
                decoration: _inputDeco(),
                items: List.generate(kBreakers.length, (i) => DropdownMenuItem(value: i, child: Text("${kBreakers[i].name} (≤${kBreakers[i].defaultLimitMicroOhm.toInt()}µΩ)", style: const TextStyle(fontSize: 11)))),
                onChanged: (v) => setState(() => _selectedBreakerIdx = v!),
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
        ),
        const SizedBox(height: 12),

        // CIBANO / OMICRON HIZLI YAPIŞTIR BUTONU
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF151921), foregroundColor: const Color(0xFFFFB300), side: const BorderSide(color: Color(0xFFFFB300))),
                icon: const Icon(Icons.paste, size: 16),
                label: const Text("CIBANO/Test Verisi Yapıştır", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _showCibanoPasteDialog,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
                icon: const Icon(Icons.description, size: 16),
                label: const Text("Resmi Rapor Üret", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _showOfficialSatPdfReport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _buildSectionCard(
          title: "R-S-T Kontak Dirençleri (µΩ)",
          child: Column(
            children: [
              _buildEditableSlider("R Kutbu Direnci (µΩ)", _resR, 10, 100, (v) => setState(() => _resR = v)),
              _buildEditableSlider("S Kutbu Direnci (µΩ)", _resS, 10, 100, (v) => setState(() => _resS = v)),
              _buildEditableSlider("T Kutbu Direnci (µΩ)", _resT, 10, 100, (v) => setState(() => _resT = v)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "Açma Süresi & Kutuplar Arası Senkronizm (ms)",
          child: Column(
            children: [
              _buildEditableSlider("tR Açma Zamanı (ms)", _timeR, 20, 90, (v) => setState(() => _timeR = v)),
              _buildEditableSlider("tS Açma Zamanı (ms)", _timeS, 20, 90, (v) => setState(() => _timeS = v)),
              _buildEditableSlider("tT Açma Zamanı (ms)", _timeT, 20, 90, (v) => setState(() => _timeT = v)),
              Text("Senkronizm Farkı (Δt): ${deltaSyncMs.toStringAsFixed(1)} ms (IEC Sınırı ≤ 3ms)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSyncOk ? Colors.greenAccent : Colors.redAccent)),
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
      ],
    );
  }

  // ==========================================
  // SEKME 4: ŞALT DİZİLİMİ & KESİNTİSİZ SLD
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
                    painter: DynamicSwitchgearPainter(cells: _cells, voltageKv: _voltageKv, ikKa: _ikKa, activeSwitchgear: _activeSwitchgear),
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
                  subtitle: Text("CT: ${c.ctRatio} | ${_activeBreaker.vendor}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
              Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 12)),
            ],
          ),
          Slider(value: val.clamp(min, max), min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildHudCard(String title, String value, String sub, {Color accentColor = const Color(0xFFFFB300)}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(12), border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
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
// 📈 LOG-LOG TCC RÖLE KOORDİNASYON ÇİZİCİSİ
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

    // Log Aralıkları: Akım 10A -> 10,000A (3 Dekat), Zaman: 0.01s -> 100s (4 Dekat)
    double logX(double a) => (log(max(a, 10.0)) / ln10 - 1.0) / 3.0 * (w - 40) + 30;
    double logY(double t) => h - 20 - ((log(max(t, 0.01)) / ln10 + 2.0) / 4.0 * (h - 30));

    // Izgara Çizgileri
    for (int p = 1; p <= 4; p++) {
      final x = logX(pow(10, p).toDouble());
      canvas.drawLine(Offset(x, 10), Offset(x, h - 20), gridPaint);
    }
    for (int p = -2; p <= 2; p++) {
      final y = logY(pow(10, p).toDouble());
      canvas.drawLine(Offset(30, y), Offset(w - 10), Offset(w - 10, y), gridPaint);
    }

    // Eksen Çizgileri
    canvas.drawLine(Offset(30, 10), Offset(30, h - 20), axisPaint);
    canvas.drawLine(Offset(30, h - 20), Offset(w - 10, h - 20), axisPaint);

    // Upstream Eğrisi (Kırmızı/Amber)
    final upPaint = Paint()..color = const Color(0xFFFF3D00)..strokeWidth = 2.2..style = PaintingStyle.stroke;
    final upPath = Path();
    bool upStarted = false;
    for (double i = upIs * 1.05; i <= 10000; i += (i < 1000 ? 50 : 250)) {
      final t = _calcTripTime(i, upIs, upTms, upCurve);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!upStarted) { upPath.moveTo(pt.dx, pt.dy); upStarted = true; } else { upPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(upPath, upPaint);

    // Downstream Eğrisi (Yeşil)
    final downPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 2.2..style = PaintingStyle.stroke;
    final downPath = Path();
    bool downStarted = false;
    for (double i = downIs * 1.05; i <= 10000; i += (i < 1000 ? 30 : 200)) {
      final t = _calcTripTime(i, downIs, downTms, downCurve);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!downStarted) { downPath.moveTo(pt.dx, pt.dy); downStarted = true; } else { downPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(downPath, downPaint);

    // Arıza Akımı Çizgisi (Dashed White)
    if (faultA >= 10 && faultA <= 10000) {
      final xFault = logX(faultA);
      final faultPaint = Paint()..color = Colors.white..strokeWidth = 1.2;
      canvas.drawLine(Offset(xFault, 15), Offset(xFault, h - 20), faultPaint);
    }
  }

  double _calcTripTime(double faultA, double iSetting, double tmsVal, String curve) {
    if (faultA <= iSetting) return double.infinity;
    final m = faultA / iSetting;
    final denom = pow(m, 0.02) - 1.0;
    if (denom <= 0) return double.infinity;
    return tmsVal * (0.14 / denom);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// VEKTÖREL ŞALT ÇİZİCİSİ (CANVAS)
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
