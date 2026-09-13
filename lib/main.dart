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

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  bool earthClosed;
  String ctRatio;
  String ctClass;
  String vtRatio;

  SwitchgearCell({
    required this.id,
    required this.name,
    required this.type,
    this.cbClosed = false,
    this.earthClosed = false,
    this.ctRatio = "400-800/5A",
    this.ctClass = "5P20 15VA + 0.2S 10VA",
    this.vtRatio = "34.5/√3 kV / 100/√3 V",
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

  // 1. Şebeke & Trafo
  double _voltageKv = 34.5;
  double _trafoMva = 1.6;
  double _ukPercent = 6.0;

  // 2. Çift Kademeli Röle
  double _upIs = 600.0;
  double _upTms = 0.25;
  String _upCurve = "SI";
  double _downIs = 250.0;
  double _downTms = 0.15;
  String _downCurve = "SI";

  // 3. Kablo & Termik
  double _cableLength = 150.0;
  double _loadCurrent = 85.0;
  double _cableSection = 50.0;
  bool _isCopper = true;

  // 4. Çevre, Rakım & İklim (IEC 62271-1 / IEC 60076)
  double _ambientTemp = 32.0;
  double _altitudeMeters = 850.0; // Rakım (m)
  double _relativeHumidity = 65.0; // % Bağıl Nem
  String _locationName = "İzmir, TR";
  bool _isLoadingWeather = false;

  // 5. Dinamik Hücre Dizilimi (Switchgear Line-up)
  final List<SwitchgearCell> _cells = [
    SwitchgearCell(id: "C1", name: "H01 TR-1 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
    SwitchgearCell(id: "C2", name: "H02 Gerilim Ölçü", type: CellType.vtMetering, cbClosed: true),
    SwitchgearCell(id: "C3", name: "H03 Kuplaj", type: CellType.coupler, cbClosed: false),
    SwitchgearCell(id: "C4", name: "H04 Fider 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A"),
    SwitchgearCell(id: "C5", name: "H05 TR-2 Giriş", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A"),
  ];

  String t(String k) {
    const d = {
      'net': {'tr': 'Şebeke', 'en': 'Grid', 'de': 'Netz'},
      'relay': {'tr': 'Selektivite', 'en': 'Selectivity', 'de': 'Staffelung'},
      'env': {'tr': 'Çevre & Rakım', 'en': 'Climate & Alt.', 'de': 'Klima & Höhe'},
      'cable': {'tr': 'Kablo & Ark', 'en': 'Cable & Arc', 'de': 'Kabel & Lichtb.'},
      'sld': {'tr': 'Şalt & SLD', 'en': 'Switchgear', 'de': 'Schaltanlage'},
    };
    return d[k]?[_lang.name] ?? k;
  }

  // --- HESAPLAMA MOTORU ---
  double get _ikKa {
    final zt = (_ukPercent / 100.0) * (pow(_voltageKv, 2) / _trafoMva);
    if (zt <= 0) return 0.0;
    return (1.10 * _voltageKv) / (sqrt(3) * zt);
  }

  // IEC 62271-1 Rakım Düzeltme Katsayısı Ka (1000m üzeri yalıtım artırımı)
  double get _altitudeDeratingKa {
    if (_altitudeMeters <= 1000) return 1.0;
    return exp((_altitudeMeters - 1000) / 8150.0);
  }

  // Trafo Rakım Güç Düşümü (IEC 60076: 1000m üzeri her 100m için %0.4 kayıp)
  double get _trafoAltitudeCapacityMva {
    if (_altitudeMeters <= 1000) return _trafoMva;
    final reductionFactor = 1.0 - (((_altitudeMeters - 1000) / 100.0) * 0.004);
    return _trafoMva * max(reductionFactor, 0.70);
  }

  // Canlı Hava Durumu & Rakım Çekme (IP & Open-Meteo)
  Future<void> _fetchLiveEnvironment() async {
    setState(() => _isLoadingWeather = true);
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final ipReq = await client.getUrl(Uri.parse('http://ip-api.com/json/'));
      final ipRes = await ipReq.close();
      if (ipRes.statusCode == 200) {
        final ipData = jsonDecode(await ipRes.transform(utf8.decoder).join());
        final lat = ipData['lat'];
        final lon = ipData['lon'];
        final city = ipData['city'] ?? 'Saha';

        final wUri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m&elevation=nan');
        final wReq = await client.getUrl(wUri);
        final wRes = await wReq.close();
        if (wRes.statusCode == 200) {
          final wData = jsonDecode(await wRes.transform(utf8.decoder).join());
          setState(() {
            _locationName = "$city (${ipData['countryCode']})";
            _ambientTemp = (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? _ambientTemp;
            _relativeHumidity = (wData['current']?['relative_humidity_2m'] as num?)?.toDouble() ?? _relativeHumidity;
            _altitudeMeters = (wData['elevation'] as num?)?.toDouble() ?? _altitudeMeters;
          });
        }
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Konum/Hava durumu alınamadı, manuel değerler geçerli.")),
      );
    } finally {
      setState(() => _isLoadingWeather = false);
    }
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
          NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), label: t('env')),
          NavigationDestination(icon: const Icon(Icons.cable), label: t('cable')),
          NavigationDestination(icon: const Icon(Icons.schema), label: t('sld')),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_activeTab) {
      case 0: return _buildGridTab();
      case 1: return _buildRelayTab();
      case 2: return _buildEnvironmentTab();
      case 3: return _buildCableArcTab();
      case 4: return _buildSwitchgearSldTab();
      default: return const SizedBox();
    }
  }

  // --- SEKME 0: ŞEBEKE & TRAFO ---
  Widget _buildGridTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard("3 FAZ KISA DEVRE AKIMI (Ik'')", "${_ikKa.toStringAsFixed(2)} kA", "Gerilim: ${_voltageKv.toStringAsFixed(1)} kV | Trafo: ${_trafoMva.toStringAsFixed(1)} MVA"),
        const SizedBox(height: 14),
        _buildEditableSlider("Sistem Gerilimi (kV)", _voltageKv, 0.4, 36.0, (v) => setState(() => _voltageKv = v)),
        _buildEditableSlider("Trafo Gücü Sn (MVA)", _trafoMva, 0.1, 40.0, (v) => setState(() => _trafoMva = v)),
        _buildEditableSlider("Kısa Devre Empedansı (%uk)", _ukPercent, 3.0, 14.0, (v) => setState(() => _ukPercent = v)),
      ],
    );
  }

  // --- SEKME 1: SELEKTİVİTE ---
  Widget _buildRelayTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard("SELEKTİVİTE KOORDİNASYONU", "TEDAŞ Uyumlu", "Giriş (Upstream) ve Fider (Downstream) Bağımsız Eşleme"),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: "Upstream (Giriş) Rölesi",
          child: Column(
            children: [
              _buildEditableSlider("Giriş Eşik Is (A)", _upIs, 50, 3000, (v) => setState(() => _upIs = v)),
              _buildEditableSlider("Giriş Çarpanı (TMS)", _upTms, 0.05, 1.2, (v) => setState(() => _upTms = v)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Downstream (Fider) Rölesi",
          child: Column(
            children: [
              _buildEditableSlider("Fider Eşik Is (A)", _downIs, 20, 1500, (v) => setState(() => _downIs = v)),
              _buildEditableSlider("Fider Çarpanı (TMS)", _downTms, 0.05, 1.0, (v) => setState(() => _downTms = v)),
            ],
          ),
        ),
      ],
    );
  }

  // --- SEKME 2: ÇEVRE, RAKIM & İKLİM (YENİ MODÜL) ---
  Widget _buildEnvironmentTab() {
    final isAltitudeHigh = _altitudeMeters > 1000;
    final isCondensationRisk = _relativeHumidity >= 75;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard(
          "ORTAM KOŞULLARI (IEC 62271-1)",
          "${_ambientTemp.toStringAsFixed(1)} °C / ${_altitudeMeters.toStringAsFixed(0)} m",
          "Konum: $_locationName | Nem: %${_relativeHumidity.toStringAsFixed(0)}",
          accentColor: isAltitudeHigh ? const Color(0xFFFF3D00) : const Color(0xFFFFB300),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: _isLoadingWeather ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.my_location),
          label: const Text("Konum & İnternetten Canlı Veri Al", style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _isLoadingWeather ? null : _fetchLiveEnvironment,
        ),
        const SizedBox(height: 14),
        _buildEditableSlider("Saha Rakımı / İrtifa (m)", _altitudeMeters, 0, 3000, (v) => setState(() => _altitudeMeters = v)),
        _buildEditableSlider("Ortam Sıcaklığı (°C)", _ambientTemp, -10, 55, (v) => setState(() => _ambientTemp = v)),
        _buildEditableSlider("Bağıl Nem (%RH)", _relativeHumidity, 10, 100, (v) => setState(() => _relativeHumidity = v)),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: "Mühendislik Standart Değerlendirmesi",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "• İzolasyon Düzeltme Faktörü (Ka): ${_altitudeDeratingKa.toStringAsFixed(3)}",
                style: TextStyle(fontWeight: FontWeight.bold, color: isAltitudeHigh ? Colors.redAccent : Colors.greenAccent),
              ),
              Text(
                isAltitudeHigh ? "  (DİKKAT: Rakım > 1000m olduğu için şalt hücrelerinde atlama mesafeleri ve test gerilimi artırılmalıdır!)" : "  (Rakım ≤ 1000m: Standart fabrika test gerilimleri geçerli)",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text("• Efektif Trafo Gücü: ${_trafoAltitudeCapacityMva.toStringAsFixed(2)} MVA (Hava seyrelmesi soğutma kaybı)", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                isCondensationRisk ? "• DİKKAT: Yüksek nem nedeniyle Hücre Pano Isıtıcıları (Anti-condensation heater) MUTLAKA aktif olmalı!" : "• Nem normal seviyede, standart havalandırma yeterli.",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isCondensationRisk ? Colors.amberAccent : Colors.white70),
              ),
            ],
          ),
        )
      ],
    );
  }

  // --- SEKME 3: KABLO & ARK ---
  Widget _buildCableArcTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHudCard("KABLO BOYUTLANDIRMA & IEEE 1584", "${_cableSection.toInt()} mm²", "Akım: ${_loadCurrent.toStringAsFixed(1)} A | Hat: ${_cableLength.toStringAsFixed(0)} m"),
        const SizedBox(height: 14),
        _buildEditableSlider("Kablo Kesiti (mm²)", _cableSection, 16, 400, (v) => setState(() => _cableSection = v)),
        _buildEditableSlider("Hat Uzunluğu (m)", _cableLength, 10, 1000, (v) => setState(() => _cableLength = v)),
        _buildEditableSlider("Yük Akımı (A)", _loadCurrent, 10, 600, (v) => setState(() => _loadCurrent = v)),
      ],
    );
  }

  // --- SEKME 4: ŞALT DİZİLİMİ & SLD (İNTERAKTİF VEKTÖREL ŞEMA) ---
  Widget _buildSwitchgearSldTab() {
    return Column(
      children: [
        // Çizim Kanvası (Pan & Zoom)
        Expanded(
          flex: 6,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF070A0E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D), width: 1.5),
            ),
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
        // Hücre Yönetim Listesi & Ekleme Butonu
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("HÜCRE DİZİLİMİ (SWITCHGEAR BAY)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Hücre Ekle", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("CT: ${c.ctRatio} | ${c.ctClass}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(c.cbClosed ? Icons.power : Icons.power_off, color: c.cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)),
                              tooltip: "Kesici Aç/Kapa",
                              onPressed: () => _toggleCellBreaker(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, size: 18, color: Colors.white70),
                              tooltip: "Ölçü Trafosu Ayarları",
                              onPressed: () => _showCellConfigDialog(i),
                            ),
                          ],
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

  // --- KİLİTLEME VE HÜCRE MANEVRA MANTIĞI ---
  void _toggleCellBreaker(int index) {
    final cell = _cells[index];
    if (cell.type == CellType.coupler && !cell.cbClosed) {
      // 2/3 Kilitlemesi: 2 giriş hücresi kapalıyken kuplaj kapatılamaz
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

  // Yeni Hücre Ekleme Dialogu
  void _showAddCellDialog() {
    String name = "H0${_cells.length + 1} Yeni Fider";
    CellType type = CellType.feeder;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF151921),
          title: const Text("Yeni Hücre Ekle", style: TextStyle(color: Color(0xFFFFB300), fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: "Hücre Adı"),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CellType>(
                value: type,
                dropdownColor: const Color(0xFF151921),
                items: const [
                  DropdownMenuItem(value: CellType.feeder, child: Text("Çıkış / Fider Hücresi")),
                  DropdownMenuItem(value: CellType.incomer, child: Text("Giriş Hücresi")),
                  DropdownMenuItem(value: CellType.coupler, child: Text("Bara Kuplaj Hücresi")),
                  DropdownMenuItem(value: CellType.vtMetering, child: Text("Gerilim Ölçü Hücresi")),
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

  // Hücre İçi CT / VT Ayar Dialogu
  void _showCellConfigDialog(int index) {
    final c = _cells[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151921),
        title: Text("${c.name} - Ölçü Trafoları", style: const TextStyle(color: Color(0xFFFFB300), fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: c.ctRatio,
              decoration: const InputDecoration(labelText: "Akım Trafosu Oranı"),
              dropdownColor: const Color(0xFF151921),
              items: ["50-100/5A", "100-200/5A", "200-400/5A", "400-800/5A", "1000-2000/5A"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => c.ctRatio = v!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: c.ctClass,
              decoration: const InputDecoration(labelText: "CT Nüve Sınıfları (IEC 61869)"),
              dropdownColor: const Color(0xFF151921),
              items: ["5P20 15VA + 0.2S 10VA", "5P10 10VA + 0.5 15VA", "10P10 15VA"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => c.ctClass = v!),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: "Hücreyi Sil",
            onPressed: () {
              setState(() => _cells.removeAt(index));
              Navigator.pop(ctx);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Tamam"),
          ),
        ],
      ),
    );
  }

  // --- SAYIYA DOKUNUP ELLE DEĞER GİRME WIDGETI ---
  Widget _buildEditableSlider(String title, double val, double min, double max, ValueChanged<double> onChanged) {
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
              InkWell(
                onTap: () => _showManualNumberInputDialog(title, val, onChanged),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFB300)), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      Text(val.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 13)),
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

  void _showManualNumberInputDialog(String title, double current, ValueChanged<double> onEntered) {
    final c = TextEditingController(text: current.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151921),
        title: Text(title, style: const TextStyle(fontSize: 14, color: Color(0xFFFFB300))),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: "Net Değer Girin"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
            onPressed: () {
              final parsed = double.tryParse(c.text);
              if (parsed != null) onEntered(parsed);
              Navigator.pop(ctx);
            },
            child: const Text("Uygula"),
          ),
        ],
      ),
    );
  }

  Widget _buildHudCard(String title, String value, String sub, {Color accentColor = const Color(0xFFFFB300)}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151921),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
      ),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 8), child]),
    );
  }
}

// ==========================================
// DİNAMİK VEKTÖREL ŞALT VE HÜCRE ÇİZİM MOTORU
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

    // Ana Bara Çizgisi
    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(20, busY), Offset(totalBusWidth - 20, busY), busPaint);
    _drawText(canvas, "ANA BARA: ${voltageKv.toStringAsFixed(1)} kV (Ik'': ${ikKa.toStringAsFixed(1)} kA)", const Offset(24, 15), const Color(0xFFFFB300), 11);

    // Her Hücreyi Dikey Fider Olarak Çiz
    for (int i = 0; i < cells.length; i++) {
      final x = 50.0 + (i * bayWidth);
      final cell = cells[i];

      // Hücre Paneli Sınır Çizgisi (Kesikli gri)
      final borderPaint = Paint()..color = const Color(0xFF21262D)..style = PaintingStyle.stroke..strokeWidth = 1.0;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 35, bayWidth - 12, h - 50), borderPaint);

      // Hücre İsim Etiketi
      _drawText(canvas, cell.name.split(' ').first, Offset(x - 20, 42), Colors.white70, 9);

      if (cell.type == CellType.incomer) {
        // Giriş Hücresi: Yukarıdan Baraya
        canvas.drawLine(Offset(x, 60), Offset(x, busY - 14), linePaint);
        _drawBreaker(canvas, Offset(x, busY - 22), cell.cbClosed);
        canvas.drawLine(Offset(x, busY - 14), Offset(x, busY), linePaint);
      } else if (cell.type == CellType.coupler) {
        // Kuplaj: Barayı kesen kesici
        _drawBreaker(canvas, Offset(x, busY), cell.cbClosed);
      } else {
        // Çıkış Fideri / Ölçü: Baradan Aşağıya
        canvas.drawLine(Offset(x, busY), Offset(x, busY + 20), linePaint);
        _drawBreaker(canvas, Offset(x, busY + 28), cell.cbClosed);
        canvas.drawLine(Offset(x, busY + 36), Offset(x, h * 0.78), linePaint);

        // CT Sembolü
        canvas.drawCircle(Offset(x, busY + 52), 5, linePaint);
        canvas.drawCircle(Offset(x, busY + 60), 5, linePaint);

        // Çıkış Ucu
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
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
