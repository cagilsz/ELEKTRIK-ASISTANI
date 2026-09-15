// Konum: lib/screens/main_cockpit.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Diğer klasörlerdeki beyin ve veritabanı dosyalarımızı çağırıyoruz:
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
  AppLanguage language = AppLanguage.tr;
  AppMode appMode = AppMode.professional;
  bool _modeDialogShown = false;
  bool _disclaimerShown = false;

  String tr(String trText, String enText) => language == AppLanguage.tr ? trText : enText;

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
        content: const SingleChildScrollView(
          child: Text(
            'Bu yazılım, saha mühendisleri ve teknikerler için geliştirilmiş bağımsız bir ön mühendislik aracıdır.\n\n'
            'Schneider, Siemens, ABB, Eaton, Mitsubishi, Ormazabal gibi markalarla resmi bir bağ bulunmamaktadır.\n'
            'Sertifikalı saha devreye alma çalışmasının yerine geçmez.',
            style: TextStyle(fontSize: 12),
          ),
        ),
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

  // SAHA MÜHENDİSİ DİLİYLE YAZILMIŞ "INFO" BUTONU FONKSİYONU
  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.info_outline, color: Colors.blueAccent), 
          const SizedBox(width: 8), 
          Text(title, style: const TextStyle(fontSize: 14))
        ]),
        content: Text(content, style: const TextStyle(fontSize: 12)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANLADIM'))],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    projects = [
      ProjectModel(
        name: 'Aliağa OSB Dağıtım TM-1', domain: PowerDomain.distribution, archetype: SubArchetype.heavyIndustry,
        voltageKv: 34.5, trafoMva: 2.5, ukPercent: 6, gridSscMva: 1000, testHistory: [], 
        cells: _cells('Schneider', 'Schneider Evolis (Vakum)')
      ),
    ];
    _loadPreferencesAndProjects();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disclaimerShown) _showDisclaimerDialog();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistProjects();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) _persistProjects();
  }

  static List<SwitchgearCell> _cells(String vendor, String breaker) => [
    SwitchgearCell(id: 'C1', name: 'H01 Incomer', type: CellType.incomer, cbClosed: true, currentVendor: vendor, currentBreaker: breaker),
    SwitchgearCell(id: 'C2', name: 'H02 VT Meter', type: CellType.vtMetering, cbClosed: true, currentVendor: vendor, currentBreaker: 'VT'),
    SwitchgearCell(id: 'C3', name: 'H03 Bus Coupler', type: CellType.coupler, currentVendor: vendor, currentBreaker: breaker),
    SwitchgearCell(id: 'C4', name: 'H04 Feeder 1', type: CellType.feeder, cbClosed: true, ctRatio: '200/5A', currentVendor: vendor, currentBreaker: breaker),
  ];

  Future<void> _persistProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('powerfield_projects_v68', jsonEncode(projects.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadPreferencesAndProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('powerfield_projects_v68');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = decoded.map((e) => ProjectModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          if (loaded.isNotEmpty && mounted) setState(() { projects = loaded; activeProject = 0; });
        }
      }
      final savedMode = prefs.getString('powerfield_app_mode_v68');
      if (mounted) setState(() { if (savedMode == AppMode.basic.name) appMode = AppMode.basic; else appMode = AppMode.professional; });
    } catch (_) {}
  }

  void _showModeChooser() {
    showDialog<void>(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('POWERFIELD PRO'),
        content: const Text('Çalışma seviyesini seçin.'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); setState(() => appMode = AppMode.basic); }, child: const Text('TEMEL')),
          FilledButton(onPressed: () { Navigator.pop(context); setState(() => appMode = AppMode.professional); }, child: const Text('PROFESYONEL')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('POWERFIELD PRO v6.8', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: switchgear.brandColor)),
      actions: [
        IconButton(
          icon: const Icon(Icons.camera_alt),
          tooltip: 'OCR Etiket Okuma (Yakında)',
          onPressed: () => _showInfoDialog('OCR Etiket Okuma', 'Kamerayı açarak röle ve pano etiketlerindeki akım/gerilim/seri no verilerini otomatik okuma modülü çok yakında aktif olacak.'),
        ),
        IconButton(
          icon: const Icon(Icons.location_on),
          tooltip: 'GPS & Hava Durumu',
          onPressed: () => _showInfoDialog('Sensör Verileri', 'GPS üzerinden anlık rakım (m) ve hava durumu API\'si ile ortam sıcaklığı (°C) verileri yakında otomatik çekilecek.'),
        ),
      ],
    ),
    body: Column(children: [_projectBar(), Expanded(child: _tab())]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: activeTab,
      onDestinationSelected: (i) => setState(() => activeTab = i),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard), label: tr('Kokpit', 'Cockpit')),
        if (appMode == AppMode.professional) ...[
          NavigationDestination(icon: const Icon(Icons.schema), label: 'SLD'),
          NavigationDestination(icon: const Icon(Icons.science), label: 'DGA'),
        ],
      ],
    ),
  );

  Widget _projectBar() => Container(
    padding: const EdgeInsets.all(7), color: const Color(0xFF090D14),
    child: Row(children: [
      Expanded(child: DropdownButton<int>(value: _safeIndex(activeProject, projects.length), isExpanded: true, underline: const SizedBox(), items: List.generate(projects.length, (i) => DropdownMenuItem(value: i, child: Text(projects[i].name, style: const TextStyle(fontSize: 11)))), onChanged: (i) { if (i != null) setState(() => activeProject = i); })),
    ]),
  );

  Widget _tab() {
    if (appMode == AppMode.basic) return _cockpit();
    switch (activeTab) {
      case 0: return _cockpit();
      case 1: return _sld();
      case 2: return _dgaTab(); // Yeni DGA sekmesi eklendi
      default: return const SizedBox();
    }
  }

  Widget _cockpit() => ListView(padding: const EdgeInsets.all(12), children: [
    _card(tr('PROJE EKİPMANI', 'PROJECT EQUIPMENT'), Column(children: [
      DropdownButtonFormField<int>(
        value: _safeIndex(p.switchgearIndex, switchgears.length), isExpanded: true,
        items: List.generate(switchgears.length, (i) => DropdownMenuItem(value: i, child: Text(switchgears[i].name, style: const TextStyle(fontSize: 11)))),
        onChanged: (v) { if (v != null) setState(() { p.switchgearIndex = v; }); _persistProjects(); },
      ),
      DropdownButtonFormField<int>(
        value: _safeIndex(p.breakerIndex, breakers.length), isExpanded: true,
        items: List.generate(breakers.length, (i) => DropdownMenuItem(value: i, child: Text('${breakers[i].name} | Icu ${breakers[i].ratedBreakingIcuKa} kA', style: const TextStyle(fontSize: 10)))),
        onChanged: (v) { if (v != null) setState(() { p.breakerIndex = v; }); _persistProjects(); },
      ),
    ])),
    // INFO BUTONLU YENİ SLİDERLAR
    _sliderWithInfo('System Voltage kV', p.voltageKv, .4, 380, (v) => p.voltageKv = v, 'Tesisin nominal çalışma gerilimi. Yüksek gerilim (154kV) veya orta gerilim (34.5kV) şebeke tipini belirler.'),
    _sliderWithInfo('Transformer MVA', p.trafoMva, .1, 250, (v) => p.trafoMva = v, 'Ana dağıtım transformatörünün veya üretim santralinin (GES/RES) görünür gücü.'),
    _sliderWithInfo('%uk', p.ukPercent, 3, 18, (v) => p.ukPercent = v, 'Trafonun etiketinde yazan kısa devre empedans gerilimidir. Bu değer düştükçe, trafonun baraya basacağı kısa devre akımı artar. Sahada trafoyu yeniliyorsanız kesicilerinizin bu yeni tepe akımına dayanıp dayanamayacağını mutlaka kontrol edin.'),
    _sliderWithInfo('Grid Ssc MVA', p.gridSscMva, 200, 5000, (v) => p.gridSscMva = v, 'Şebeke bağlantı noktasındaki (PCC) maksimum kısa devre gücü. TEİAŞ veya TEDAŞ referans değerlerinden alınır.'),
  ]);

  // YENİ EKLENEN DGA SEKME TASARIMI
  Widget _dgaTab() => ListView(padding: const EdgeInsets.all(12), children: [
    Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.purpleAccent.withOpacity(0.55))),
      child: const Column(children: [
        Text('DGA ANALİZİ', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text('Trafo Yağ Testi', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.purpleAccent)),
        Text('Duval Üçgeni ve IEC 60599 Ön Teşhis Modülü', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey)),
      ]),
    ),
    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Yakında: ppm değerlerini (H2, CH4, C2H6 vb.) girerek, laboratuvar sonuçlarını beklemeden sahada "Kısmi Deşarj" veya "Termik Hata" tespiti yapabileceksin.', style: TextStyle(fontSize: 12, color: Colors.white70)))),
  ]);

  Widget _sld() => ListView(padding: const EdgeInsets.all(12), children: [
    SizedBox(height: 230, child: CustomPaint(painter: SldPainter(cells: p.cells, color: switchgear.brandColor))),
    ...p.cells.map((c) => Card(child: ListTile(dense: true, title: Text(c.name, style: const TextStyle(fontSize: 11)), subtitle: Text('${c.currentVendor} | ${c.currentBreaker} | CT ${c.ctRatio}', style: const TextStyle(fontSize: 9)), trailing: Switch(value: c.cbClosed, onChanged: (v) => setState(() => c.cbClosed = v))))),
  ]);

  Widget _sliderWithInfo(String title, double value, double minV, double maxV, ValueChanged<double> onChanged, String infoText) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          InkWell(onTap: () => _showInfoDialog(title, infoText), child: const Icon(Icons.help_outline, size: 14, color: Colors.grey)),
        ]),
        Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFFFFB300))),
      ]),
      Slider(value: value.clamp(minV, maxV).toDouble(), min: minV, max: maxV, onChanged: (v) { setState(() => onChanged(v)); }),
    ])),
  );

  Widget _card(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), const SizedBox(height: 5), child]),
  );
}

class SldPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final Color color;
  SldPainter({required this.cells, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final busY = size.height * .35;
    final line = Paint()..color = Colors.white70..strokeWidth = 2;
    final bus = Paint()..color = color..strokeWidth = 4;
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
  @override
  bool shouldRepaint(covariant SldPainter oldDelegate) => true;
}
