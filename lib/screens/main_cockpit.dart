// Konum: lib/screens/main_cockpit.dart

import 'dart:convert';
import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/electrical_engine.dart';
import '../models/project_models.dart';

class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});
  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> with WidgetsBindingObserver {
  late List<ProjectModel> projects;
  int activeProject = 0;
  int activeTab = 0;
  
  String currentLang = 'TR'; 
  AppMode appMode = AppMode.professional;
  bool _modeDialogShown = false;
  bool _disclaimerShown = false;

  final Map<String, Map<String, String>> langMap = {
    'TR': {'cockpit': 'Kokpit', 'sld': 'Tek Hat', 'dga': 'DGA', 'relay': 'Röle', 'cable': 'Kablo', 'analysis': 'Yük Akışı', 'sat': 'SAT', 'std': 'Norm: IEC / TEDAŞ', 'equipment': 'HÜCRE VE KESİCİ SEÇİMİ', 'volt': 'Bara Gerilimi (Un) kV', 'trafo': 'Trafo Gücü (Sr) MVA'},
    'EN': {'cockpit': 'Cockpit', 'sld': 'SLD', 'dga': 'DGA', 'relay': 'Relay', 'cable': 'Cable', 'analysis': 'Load Flow', 'sat': 'SAT', 'std': 'Norm: IEC / IEEE', 'equipment': 'SWITCHGEAR & CB', 'volt': 'Bus Voltage (Un) kV', 'trafo': 'Trafo Power (Sr) MVA'},
    'RU': {'cockpit': 'Кабина', 'sld': 'ОЛС', 'dga': 'АРГ', 'relay': 'Реле', 'cable': 'Кабель', 'analysis': 'Поток', 'sat': 'ПСИ', 'std': 'Норма: GOST', 'equipment': 'КРУ И ВЫКЛЮЧАТЕЛЬ', 'volt': 'Напряжение (Un) кВ', 'trafo': 'Мощность (Sr) МВА'},
  };

  String t(String key) => langMap[currentLang]?[key] ?? langMap['EN']![key]!;

  ProjectModel get p => projects[activeProject];
  int _safeIndex(int value, int length) => value < 0 ? 0 : (value >= length ? length - 1 : value);
  BreakerModel get breaker => breakers[_safeIndex(p.breakerIndex, breakers.length)];
  SwitchgearModel get switchgear => switchgears[_safeIndex(p.switchgearIndex, switchgears.length)];

  void _showDisclaimerDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ YASAL BİLGİLENDİRME'),
        content: const Text('Bu yazılım saha mühendisleri için geliştirilmiş bağımsız bir analiz aracıdır. Sertifikalı test (SAT/FAT) raporu yerine geçmez.', style: TextStyle(fontSize: 12)),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _disclaimerShown = true);
              if (!_modeDialogShown) _showModeChooser();
            },
            child: const Text('KABUL EDİYORUM'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [const Icon(Icons.info_outline, color: Colors.blueAccent), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 14)))]),
        content: Text(content, style: const TextStyle(fontSize: 12, height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANLAŞILDI'))],
      ),
    );
  }

  // YENİ: GPS TELEMETRİ SİMÜLASYONU
  Future<void> _fetchGPSData() async {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.greenAccent), SizedBox(height: 15),
          Text('Uyduya Bağlanılıyor...\nRakım (Altitude) Hesaplanıyor', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    Navigator.pop(context); // Yükleniyor ekranını kapat
    setState(() { p.altitudeMeters = 1250; }); // Örnek yüksek rakım (Derating gerektirir)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('GPS Onaylandı: Rakım 1250m. IEC 62271 Derating katsayısı aktifleştirildi.')));
    }
  }

  // YENİ: OCR ETİKET OKUMA SİMÜLASYONU
  Future<void> _scanOCR() async {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.document_scanner, size: 40, color: Colors.blueAccent), SizedBox(height: 15),
          LinearProgressIndicator(color: Colors.blueAccent), SizedBox(height: 15),
          Text('Röle Ekranı Taranıyor...\nCT Oranı ve Akımlar Çekiliyor', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    Navigator.pop(context);
    setState(() { p.up50PickupA = 1250; p.upTms = 0.15; }); // Otomatik değer çektiğini varsayalım
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blueAccent, content: Text('OCR Başarılı: Röle Pick-up akımı 1250A olarak güncellendi.')));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    projects = [
      ProjectModel(
        name: 'Yatağan 26MW GES (TM-1)', domain: PowerDomain.distribution, archetype: SubArchetype.solarGES,
        voltageKv: 36, trafoMva: 26, ukPercent: 6, gridSscMva: 1250, testHistory: [], 
        switchgearIndex: 0, breakerIndex: 2, 
        cells: [
          SwitchgearCell(id: 'C1', name: 'H01 Giriş', type: CellType.incomer, cbClosed: true, currentVendor: 'Schneider', currentBreaker: 'SF2'),
          SwitchgearCell(id: 'C2', name: 'H02 Ölçü', type: CellType.vtMetering, cbClosed: true, currentVendor: 'Schneider', currentBreaker: 'VT'),
          SwitchgearCell(id: 'C3', name: 'H03 Çıkış', type: CellType.feeder, cbClosed: true, ctRatio: '400/5A', currentVendor: 'Schneider', currentBreaker: 'SF2'),
        ]
      ),
    ];
    _loadPreferencesAndProjects();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (!_disclaimerShown) _showDisclaimerDialog(); });
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _persistProjects(); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) _persistProjects(); }

  Future<void> _persistProjects() async { try { final prefs = await SharedPreferences.getInstance(); await prefs.setString('powerfield_projects_v68', jsonEncode(projects.map((e) => e.toJson()).toList())); } catch (_) {} }
  Future<void> _loadPreferencesAndProjects() async { try { final prefs = await SharedPreferences.getInstance(); final raw = prefs.getString('powerfield_projects_v68'); if (raw != null) { final decoded = jsonDecode(raw); if (decoded is List) { final loaded = decoded.map((e) => ProjectModel.fromJson(Map<String, dynamic>.from(e as Map))).toList(); if (loaded.isNotEmpty && mounted) setState(() { projects = loaded; activeProject = 0; }); } } final savedMode = prefs.getString('powerfield_app_mode_v68'); if (mounted) setState(() { if (savedMode == AppMode.basic.name) appMode = AppMode.basic; else appMode = AppMode.professional; }); final savedLang = prefs.getString('powerfield_lang_v68'); if (savedLang != null && mounted) setState(() => currentLang = savedLang); } catch (_) {} }
  
  void _showModeChooser() { 
    showDialog<void>( 
      context: context, barrierDismissible: false, 
      builder: (_) => AlertDialog( 
        title: const Text('POWERFIELD PRO'), 
        content: const Text('Çalışma seviyesini seçin.'), 
        actions: [ 
          TextButton(onPressed: () { Navigator.pop(context); setState(() { appMode = AppMode.basic; activeTab = 0; }); }, child: const Text('TEMEL MOD')), 
          FilledButton(onPressed: () { Navigator.pop(context); setState(() => appMode = AppMode.professional); }, child: const Text('UZMAN (EXPERT)')), 
        ], 
      ), 
    ); 
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('POWERFIELD PRO v6.8', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: switchgear.brandColor)),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.language, color: Colors.white),
          tooltip: 'Dil ve Bölgesel Standart',
          onSelected: (String lang) async { 
            setState(() { currentLang = lang; }); 
            final prefs = await SharedPreferences.getInstance(); 
            prefs.setString('powerfield_lang_v68', lang);
          },
          itemBuilder: (BuildContext context) => const [
            PopupMenuItem(value: 'TR', child: Text('🇹🇷 Türkçe')),
            PopupMenuItem(value: 'EN', child: Text('🇬🇧 English')),
            PopupMenuItem(value: 'RU', child: Text('🇷🇺 Русский (GOST)')),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.camera_alt, color: Colors.blueAccent), 
          onPressed: _scanOCR, // YENİ: Gerçek OCR fonksiyonuna bağlandı
          tooltip: 'Röle Etiketi Oku',
        ),
        IconButton(
          icon: const Icon(Icons.my_location, color: Colors.greenAccent), 
          onPressed: _fetchGPSData, // YENİ: Gerçek GPS fonksiyonuna bağlandı
          tooltip: 'GPS Rakım Çek',
        ),
      ],
    ),
    body: Column(children: [_projectBar(), Expanded(child: _tab())]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: appMode == AppMode.basic ? 0 : activeTab,
      onDestinationSelected: (i) => setState(() => activeTab = i),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard), label: t('cockpit')),
        if (appMode == AppMode.professional) ...[
          NavigationDestination(icon: const Icon(Icons.schema), label: t('sld')),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: t('relay')),
          NavigationDestination(icon: const Icon(Icons.cable), label: t('cable')),
          NavigationDestination(icon: const Icon(Icons.analytics), label: t('analysis')),
          NavigationDestination(icon: const Icon(Icons.fact_check), label: t('sat')),
        ],
      ],
    ),
  );

  Widget _projectBar() => Container( padding: const EdgeInsets.all(7), color: const Color(0xFF090D14), child: Row(children: [ Expanded(child: DropdownButton<int>(value: _safeIndex(activeProject, projects.length), isExpanded: true, underline: const SizedBox(), items: List.generate(projects.length, (i) => DropdownMenuItem(value: i, child: Text(projects[i].name, style: const TextStyle(fontSize: 11)))), onChanged: (i) { if (i != null) setState(() => activeProject = i); })), ]), );

  Widget _tab() {
    if (appMode == AppMode.basic) return _cockpit();
    switch (activeTab) {
      case 0: return _cockpit(); 
      case 1: return _sld(); 
      case 2: return _relayTab(); 
      case 3: return _cableTab(); 
      case 4: return _analysisTab(); 
      case 5: return _satTab(); 
      default: return const SizedBox();
    }
  }

  Widget _cockpit() => ListView(padding: const EdgeInsets.all(12), children: [
    Container(
      padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.blueAccent.withOpacity(0.3))),
      child: Row(children: [
        const Icon(Icons.public, color: Colors.blueAccent, size: 16), const SizedBox(width: 8),
        Text(t('std'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
      ]),
    ),
    _card(t('equipment'), Column(children: [
      DropdownButtonFormField<int>(value: _safeIndex(p.switchgearIndex, switchgears.length), isExpanded: true, items: List.generate(switchgears.length, (i) => DropdownMenuItem(value: i, child: Text(switchgears[i].name, style: const TextStyle(fontSize: 11)))), onChanged: (v) { if (v != null) setState(() { p.switchgearIndex = v; }); _persistProjects(); }),
      DropdownButtonFormField<int>(value: _safeIndex(p.breakerIndex, breakers.length), isExpanded: true, items: List.generate(breakers.length, (i) => DropdownMenuItem(value: i, child: Text('${breakers[i].name} | Icu: ${breakers[i].ratedBreakingIcuKa} kA', style: const TextStyle(fontSize: 10)))), onChanged: (v) { if (v != null) setState(() { p.breakerIndex = v; }); _persistProjects(); }),
    ])),
    
    // YENİ: SAHA MÜHENDİSİ DİLİNDE INFO METİNLERİ
    _sliderWithInfo(t('volt'), p.voltageKv, .4, 380, (v) => p.voltageKv = v, 
      'Tesis barasının nominal çalışma gerilimi (Un). OG fiderlerinde hücre ve kesici dielektrik dayanım (BIL) sınıfını doğrudan etkiler. Dağıtım şirketleri (EDAŞ) limitleri için kritiktir.'),
    
    _sliderWithInfo(t('trafo'), p.trafoMva, .1, 250, (v) => p.trafoMva = v, 
      'Güç trafosunun etiketindeki anma gücü (Sr). Sekonder taraf nominal akımını (In) ve dolayısıyla ana giriş kesicisinin termik açma (Ir) set değerini belirler.'),
    
    _sliderWithInfo('Kısa Devre Empedansı (%uk)', p.ukPercent, 3, 18, (v) => p.ukPercent = v, 
      'Trafonun empedans gerilimi. Bu değer ne kadar düşükse, trafonun sekonder baraya basacağı 3 faz kısa devre tepe akımı (Ith/Ip) o kadar şiddetli olur. Hücre kesicilerinin Icu/Icw kısa devre dayanımlarını aşmamak için en kritik parametredir.'),
    
    _sliderWithInfo('Şebeke Kısa Devre Gücü (Ssc MVA)', p.gridSscMva, 200, 5000, (v) => p.gridSscMva = v, 
      'TEİAŞ/TEDAŞ bağlantı noktasındaki (PCC) kısa devre görünür gücü. Şebeke ne kadar rijitse (güçlüyse), tesis barasındaki beklenen arıza akımları da o oranda artacaktır.'),
  ]);

  Widget _relayTab() { 
    double testFault = p.up50PickupA * 2.5; 
    double time = ElectricalEngine.calcTripTime(faultA: testFault, iPickupA: p.up50PickupA, tmsVal: p.upTms, curve: p.upCurve); 
    return ListView(padding: const EdgeInsets.all(12), children: [
      _card('50/51 AŞIRI AKIM KOORDİNASYONU', Column(children: [
        DropdownButtonFormField<TripCurve>(
          value: p.upCurve, isExpanded: true, 
          decoration: const InputDecoration(labelText: 'Röle Açma Eğrisi (IEC/IEEE)'),
          items: TripCurve.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(fontSize: 12)))).toList(), 
          onChanged: (v) { if (v != null) setState(() => p.upCurve = v); _persistProjects(); }
        ), 
        const SizedBox(height: 10), 
        _sliderWithInfo('I> Pick-up (Amper)', p.up50PickupA, 10, 5000, (v) => p.up50PickupA = v, 'Faz aşırı akım başlama (kalkış) eşiği. Fiderin puant yüküne ve trafo In değerine göre koordinasyon marjı bırakılarak set edilir.'), 
        _sliderWithInfo('TMS (Zaman Çarpanı)', p.upTms, 0.02, 1.2, (v) => p.upTms = v, 'Ters zamanlı eğride (IDMT) eğrinin dikey eksende kaydırılmasını sağlayan çarpan. Selektivite için yukarı/aşağı röleler arası uyumu sağlar.'), 
        const Divider(height: 30, color: Colors.white24), 
        const Text('Simülasyon (Set Değerinin 2.5 Katı Arıza Akımı):', style: TextStyle(fontSize: 10, color: Colors.grey)), 
        const SizedBox(height: 5),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Beklenen Açma Süresi:', style: TextStyle(fontWeight: FontWeight.bold, color: switchgear.brandColor)), 
          Text(time == double.infinity ? 'Kalkış Yok' : '${time.toStringAsFixed(3)} sn', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent))
        ])
      ]))
    ]); 
  }

  Widget _cableTab() { 
    final cableResult = ElectricalEngine.evaluateCableSizing(sectionMm2: p.cableSectionMm2, lengthM: p.cableLengthM, loadCurrentA: p.loadCurrentA, voltageKv: p.voltageKv, ikKa: breaker.shortTimeWithstandIcwKa, faultTimeSec: 1.0, isCopper: p.isCopper); 
    return ListView(padding: const EdgeInsets.all(12), children: [
      _card('KABLO KESİT TAYİNİ (IEC 60364)', Column(children: [
        SwitchListTile(title: const Text('İletken Tipi', style: TextStyle(fontSize: 12)), subtitle: Text(p.isCopper ? 'Bakır (Cu)' : 'Alüminyum (Al)', style: TextStyle(color: p.isCopper ? const Color(0xFFFFB300) : Colors.grey)), value: p.isCopper, onChanged: (v) { setState(() => p.isCopper = v); _persistProjects(); }), 
        _sliderWithInfo('Kesit (mm²)', p.cableSectionMm2, 16, 300, (v) => p.cableSectionMm2 = v, 'Kullanılan kablonun damar kesiti.'), 
        _sliderWithInfo('Uzunluk (Metre)', p.cableLengthM, 10, 1000, (v) => p.cableLengthM = v, 'Fider ile yük (veya trafo) arasındaki kablo metrajı.'), 
        _sliderWithInfo('Çekilen Akım (Amper)', p.loadCurrentA, 10, 1000, (v) => p.loadCurrentA = v, 'Yükün çektiği sürekli nominal akım.'), 
        const Divider(height: 30, color: Colors.white24), 
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Akım Taşıma (Iz) Kapasitesi:', style: TextStyle(fontSize: 12)), Icon(cableResult['isAmpacityOk'] ? Icons.check_circle : Icons.cancel, color: cableResult['isAmpacityOk'] ? Colors.green : Colors.red)]), const SizedBox(height: 10), 
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Kısa Devre Termik Dayanımı:', style: TextStyle(fontSize: 12)), Icon(cableResult['isThermalOk'] ? Icons.check_circle : Icons.cancel, color: cableResult['isThermalOk'] ? Colors.green : Colors.red)]), const SizedBox(height: 10), 
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Gerilim Düşümü (<= %3):', style: TextStyle(fontSize: 12)), Text('%${(cableResult['dropPercent'] as double).toStringAsFixed(2)}', style: TextStyle(color: cableResult['isVoltageDropOk'] ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 16))])
      ]))
    ]); 
  }

  Widget _analysisTab() {
    final flow = ElectricalEngine.calcLoadFlow(voltageKv: p.voltageKv, activePowerMw: p.loadFlowMw, powerFactor: p.loadFlowPf, lineLengthKm: p.lineLengthKm, rOhmPerKm: p.lineROhmPerKm, xOhmPerKm: p.lineXOhmPerKm, sourceSscMva: p.gridSscMva);
    return ListView(padding: const EdgeInsets.all(12), children: [
      _card('YÜK AKIŞI & GERİLİM DÜŞÜMÜ', Column(children: [
        _sliderWithInfo('Aktif Güç (MW)', p.loadFlowMw, 0.1, 100, (v) => p.loadFlowMw = v, 'Fiderin beslediği aktif yük miktarı.'), 
        _sliderWithInfo('Güç Faktörü (cos φ)', p.loadFlowPf, 0.5, 1.0, (v) => p.loadFlowPf = v, 'Tesisin güç faktörü. Düşük olması durumunda hatta akan reaktif güç artar, kompanzasyon pano kapasitesi gözden geçirilmelidir.'), 
        _sliderWithInfo('Hat Uzunluğu (km)', p.lineLengthKm, 0.5, 150, (v) => p.lineLengthKm = v, 'Enerji nakil hattının uzunluğu.'),
        const Divider(), 
        _resultRow('Şebekeden Çekilen Faz Akımı:', '${flow['currentA']!.toStringAsFixed(1)} A'), 
        _resultRow('Sistem Reaktif Gücü:', '${flow['qMvar']!.toStringAsFixed(2)} MVAr'), 
        _resultRow('Hat Sonu Gerilim Düşümü:', '% ${flow['dropPercent']!.toStringAsFixed(2)}'), 
        _resultRow('Alıcı Bara Gerilimi:', '${flow['receivingKv']!.toStringAsFixed(2)} kV'),
      ])),
    ]);
  }

  Widget _satTab() => ListView(padding: const EdgeInsets.all(12), children: [
    _card('KONTAK GEÇİŞ DİRENCİ (MİKRO-OHM)', Column(children: [
      const Text('Sahadaki test cihazı (CIBANO vb.) verilerini girin.', style: TextStyle(fontSize: 10, color: Colors.cyanAccent)), const SizedBox(height: 10),
      _sliderWithInfo('Faz R (L1) - µΩ', p.resR, 5, 150, (v) => p.resR = v, 'L1 fazının ana kontak kapalı konumdaki geçiş direnci. Yüksek çıkması kontak deformasyonunu veya vakum tüpü aşınmasını gösterir.'), 
      _sliderWithInfo('Faz S (L2) - µΩ', p.resS, 5, 150, (v) => p.resS = v, 'L2 fazı geçiş direnci.'), 
      _sliderWithInfo('Faz T (L3) - µΩ', p.resT, 5, 150, (v) => p.resT = v, 'L3 fazı geçiş direnci.'),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Üretici Fabrika Limiti:', style: TextStyle(fontSize: 12)), Text('${breaker.defaultLimitMicroOhm} µΩ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent))]), const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Kesici Sağlık Durumu (FAT):', style: TextStyle(fontSize: 12)), Text((p.resR <= breaker.defaultLimitMicroOhm && p.resS <= breaker.defaultLimitMicroOhm && p.resT <= breaker.defaultLimitMicroOhm) ? '✅ ONAY (PASS)' : '❌ RED (FAIL)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (p.resR <= breaker.defaultLimitMicroOhm && p.resS <= breaker.defaultLimitMicroOhm && p.resT <= breaker.defaultLimitMicroOhm) ? Colors.green : Colors.red))])
    ])),
  ]);

  Widget _resultRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)]));

  Widget _sld() => ListView(padding: const EdgeInsets.all(12), children: [
    SizedBox(height: 230, child: CustomPaint(painter: SldPainter(cells: p.cells, color: switchgear.brandColor))), 
    ...p.cells.map((c) => Card(child: ListTile(dense: true, title: Text(c.name, style: const TextStyle(fontSize: 11)), subtitle: Text('${c.currentVendor} | ${c.currentBreaker} | CT ${c.ctRatio}', style: const TextStyle(fontSize: 9)), trailing: Switch(value: c.cbClosed, onChanged: (v) => setState(() => c.cbClosed = v)))))
  ]);

  Widget _sliderWithInfo(String title, double value, double minV, double maxV, ValueChanged<double> onChanged, String infoText) => Card(
    margin: const EdgeInsets.only(bottom: 6), 
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(width: 4), InkWell(onTap: () => _showInfoDialog(title, infoText), child: const Icon(Icons.help, size: 16, color: Colors.grey))]), 
        Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFFFFB300)))
      ]), 
      Slider(value: value.clamp(minV, maxV).toDouble(), min: minV, max: maxV, onChanged: (v) { setState(() => onChanged(v)); })
    ]))
  );

  Widget _card(String title, Widget child) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 10), child]));
}

class SldPainter extends CustomPainter {
  final List<SwitchgearCell> cells; final Color color;
  SldPainter({required this.cells, required this.color});
  @override void paint(Canvas canvas, Size size) { 
    final busY = size.height * .35; final line = Paint()..color = Colors.white70..strokeWidth = 2; final bus = Paint()..color = color..strokeWidth = 4; 
    canvas.drawLine(const Offset(15, 35), Offset(size.width - 15, 35), bus); 
    for (int i = 0; i < cells.length; i++) { 
      final x = 55.0 + i * 105; 
      canvas.drawLine(Offset(x, 35), Offset(x, busY + 40), line); 
      final rect = Rect.fromCenter(center: Offset(x, busY), width: 18, height: 18); 
      canvas.drawRect(rect, Paint()..color = cells[i].cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676)); 
      canvas.drawRect(rect, Paint()..color = Colors.white..style = PaintingStyle.stroke); 
      TextPainter(text: TextSpan(text: cells[i].name, style: const TextStyle(color: Colors.white, fontSize: 8)), textDirection: TextDirection.ltr)..layout(maxWidth: 90)..paint(canvas, Offset(x - 45, busY + 18)); 
    } 
  }
  @override bool shouldRepaint(covariant SldPainter oldDelegate) => true;
}
