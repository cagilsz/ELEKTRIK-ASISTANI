import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/electrical_engine.dart';
import '../localization/app_language.dart';
import '../localization/localization_service.dart';
import '../models/project_models.dart';
import '../standards/standard_engine.dart';
import '../standards/standard_models.dart';
import '../standards/standard_registry.dart';

class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});

  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit>
    with WidgetsBindingObserver {
  static const _projectsKey = 'powerfield_projects_v69';
  static const _languageKey = 'powerfield_lang_v69';
  static const _modeKey = 'powerfield_app_mode_v69';

  late List<ProjectModel> projects;
  int activeProject = 0;
  int activeTab = 0;

  AppLanguage currentLanguage = AppLanguage.tr;
  AppMode appMode = AppMode.professional;
  bool _disclaimerShown = false;
  bool _modeDialogShown = false;

  LocalizationService get loc => LocalizationService(language: currentLanguage);

  ProjectModel get p => projects[_safeIndex(activeProject, projects.length)];

  BreakerModel get breaker =>
      breakers[_safeIndex(p.breakerIndex, breakers.length)];

  SwitchgearModel get switchgear =>
      switchgears[_safeIndex(p.switchgearIndex, switchgears.length)];

  StandardEngine get standardEngine =>
      StandardEngine.fromProfileId(p.standardProfileId);

  int _safeIndex(int value, int length) {
    if (length <= 0) return 0;
    if (value < 0) return 0;
    if (value >= length) return length - 1;
    return value;
  }

  String t(String key) => loc.text(key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    projects = [
      ProjectModel(
        name: 'Yatağan 26MW GES (TM-1)',
        domain: PowerDomain.distribution,
        archetype: SubArchetype.solarGES,
        voltageKv: 36,
        trafoMva: 26,
        ukPercent: 6,
        gridSscMva: 1250,
        testHistory: const [],
        switchgearIndex: 0,
        breakerIndex: 2,
        standardProfileId: 'turkey_teias_iec',
        uiLanguage: 'tr',
        countryCode: 'TR',
        expertMode: true,
        cells: [
          SwitchgearCell(
            id: 'C1',
            name: 'H01 Giriş',
            type: CellType.incomer,
            cbClosed: true,
            currentVendor: 'Schneider',
            currentBreaker: 'SF2',
          ),
          SwitchgearCell(
            id: 'C2',
            name: 'H02 Ölçü',
            type: CellType.vtMetering,
            cbClosed: true,
            currentVendor: 'Schneider',
            currentBreaker: 'VT',
          ),
          SwitchgearCell(
            id: 'C3',
            name: 'H03 Çıkış',
            type: CellType.feeder,
            cbClosed: true,
            ctRatio: '400/5A',
            currentVendor: 'Schneider',
            currentBreaker: 'SF2',
          ),
        ],
      ),
    ];

    _loadState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disclaimerShown && mounted) {
        _showDisclaimerDialog();
      }
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistProjects();
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_projectsKey);

      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = decoded
              .map((e) => ProjectModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList();

          if (loaded.isNotEmpty && mounted) {
            setState(() {
              projects = loaded;
              activeProject = 0;
            });
          }
        }
      }

      final savedLanguage = prefs.getString(_languageKey);
      final savedMode = prefs.getString(_modeKey);

      if (mounted) {
        setState(() {
          currentLanguage = AppLanguageExtension.fromCode(
            savedLanguage?.toLowerCase(),
          );

          appMode = savedMode == AppMode.basic.name
              ? AppMode.basic
              : AppMode.professional;
        });
      }
    } catch (_) {
      // Corrupt local state must not prevent the application from starting.
    }
  }

  Future<void> _persistProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _projectsKey,
        jsonEncode(projects.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(_languageKey, currentLanguage.code);
      await prefs.setString(_modeKey, appMode.name);
    } catch (_) {}
  }

  void _showDisclaimerDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('⚠️ ${t('disclaimer_title')}'),
        content: Text(t('disclaimer_body')),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _disclaimerShown = true);
              if (!_modeDialogShown) _showModeChooser();
            },
            child: Text(t('accept')),
          ),
        ],
      ),
    );
  }

  void _showModeChooser() {
    _modeDialogShown = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(t('working_mode')),
        content: Text(t('working_mode_body')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                appMode = AppMode.basic;
                p.expertMode = false;
                activeTab = 0;
              });
              _persistProjects();
            },
            child: Text(t('field_mode')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                appMode = AppMode.professional;
                p.expertMode = true;
              });
              _persistProjects();
            },
            child: Text(t('expert_mode')),
          ),
        ],
      ),
    );
  }

  Future<void> _changeLanguage(AppLanguage language) async {
    setState(() {
      currentLanguage = language;
      p.uiLanguage = language.code;
    });
    await _persistProjects();
  }

  Future<void> _changeStandard(String profileId) async {
    setState(() {
      p.standardProfileId = profileId;
    });
    await _persistProjects();
  }

  Future<void> _changeCountry(String countryCode) async {
    setState(() {
      p.countryCode = countryCode;
    });
    await _persistProjects();
  }

  void _showInfoDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('understood')),
          ),
        ],
      ),
    );
  }

  Future<void> _scanOCR() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('scan_equipment')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.document_scanner_outlined, size: 52),
            const SizedBox(height: 14),
            Text(t('ocr_demo_body')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                p.up50PickupA = 1250;
                p.upTms = 0.15;
              });
              Navigator.pop(context);
              _persistProjects();
              _snack(t('ocr_demo_result'));
            },
            child: Text(t('apply_demo')),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchGPSData() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('field_context')),
        content: Text(t('gps_demo_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                p.altitudeMeters = 1250;
              });
              Navigator.pop(context);
              _persistProjects();
              _snack(t('gps_demo_result'));
            },
            child: Text(t('apply_demo')),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = standardEngine.profile;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'POWERFIELD PRO',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            Text(
              '${p.countryCode} • ${profile.name}',
              style: const TextStyle(fontSize: 9),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: t('scan_equipment'),
            onPressed: _scanOCR,
          ),
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            tooltip: t('field_context'),
            onPressed: _fetchGPSData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: t('settings'),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'profile',
                child: Text(t('standard_profile')),
              ),
              PopupMenuItem(
                value: 'language',
                child: Text(t('language')),
              ),
              PopupMenuItem(
                value: 'mode',
                child: Text(t('working_mode')),
              ),
            ],
            onSelected: (value) {
              if (value == 'profile') _showProfileDialog();
              if (value == 'language') _showLanguageDialog();
              if (value == 'mode') _showModeChooser();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _projectHeader(profile),
          Expanded(child: _tabBody()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _safeIndex(activeTab, _visibleTabs().length),
        onDestinationSelected: (index) {
          setState(() => activeTab = index);
        },
        destinations: _visibleTabs()
            .map(
              (tab) => NavigationDestination(
                icon: Icon(tab.icon),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }

  List<_TabDefinition> _visibleTabs() {
    if (appMode == AppMode.basic) {
      return [
        _TabDefinition(Icons.dashboard_outlined, t('quick_check')),
        _TabDefinition(Icons.bolt_outlined, t('short_circuit')),
        _TabDefinition(Icons.cable_outlined, t('cable')),
      ];
    }

    return [
      _TabDefinition(Icons.dashboard_outlined, t('cockpit')),
      _TabDefinition(Icons.account_tree_outlined, t('sld')),
      _TabDefinition(Icons.bolt_outlined, t('short_circuit')),
      _TabDefinition(Icons.shield_outlined, t('protection')),
      _TabDefinition(Icons.cable_outlined, t('cable')),
      _TabDefinition(Icons.show_chart_outlined, t('load_flow')),
      _TabDefinition(Icons.science_outlined, 'DGA'),
      _TabDefinition(Icons.fact_check_outlined, t('sat')),
    ];
  }

  Widget _tabBody() {
    final tabs = _visibleTabs();
    if (activeTab >= tabs.length) activeTab = 0;

    if (appMode == AppMode.basic) {
      switch (activeTab) {
        case 1:
          return _shortCircuitTab();
        case 2:
          return _cableTab();
        default:
          return _quickCheckTab();
      }
    }

    switch (activeTab) {
      case 1:
        return _sldTab();
      case 2:
        return _shortCircuitTab();
      case 3:
        return _protectionTab();
      case 4:
        return _cableTab();
      case 5:
        return _loadFlowTab();
      case 6:
        return _dgaTab();
      case 7:
        return _satTab();
      default:
        return _cockpitTab();
    }
  }

  Widget _projectHeader(StandardProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111622),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${p.voltageKv.toStringAsFixed(1)} kV • ${p.trafoMva.toStringAsFixed(1)} MVA • ${profile.name}',
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ),
          ),
          _statusChip(
            appMode == AppMode.basic ? t('field_mode') : t('expert_mode'),
            appMode == AppMode.basic ? Icons.flash_on : Icons.engineering,
          ),
        ],
      ),
    );
  }

  Widget _cockpitTab() {
    final sc = _shortCircuitData();
    final cable = _cableData();
    final flow = _loadFlowData();
    final protection = _protectionData();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle(t('field_assistant')),
        _quickActionGrid(),
        _card(
          t('engineering_summary'),
          Column(
            children: [
              _summaryRow(t('short_circuit'), '${sc['ikKa']!.toStringAsFixed(2)} kA', _status(sc['breakerOk'] as bool)),
              _summaryRow(t('protection'), '${protection.tripTimeS.toStringAsFixed(3)} s', _status(protection.status == ComplianceStatus.pass)),
              _summaryRow(t('cable'), '${cable.voltageDropPercent.toStringAsFixed(2)} %', _status(cable.status != ComplianceStatus.fail)),
              _summaryRow(t('load_flow'), '${flow.voltageDropPercent.toStringAsFixed(2)} %', _status(flow.status != ComplianceStatus.fail)),
            ],
          ),
        ),
        _standardContextCard(),
        _fieldContextCard(),
      ],
    );
  }

  Widget _quickCheckTab() {
    final sc = _shortCircuitData();
    final cable = _cableData();
    final breakerOk = sc['breakerOk'] as bool;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle(t('quick_check')),
        _bigStatusCard(
          title: t('short_circuit'),
          value: '${sc['ikKa']!.toStringAsFixed(2)} kA',
          ok: breakerOk,
          subtitle: '${t('breaker_capacity')}: ${breaker.ratedBreakingIcuKa.toStringAsFixed(1)} kA',
        ),
        _bigStatusCard(
          title: t('cable'),
          value: '${cable.voltageDropPercent.toStringAsFixed(2)} %',
          ok: cable.status != ComplianceStatus.fail,
          subtitle: '${t('ampacity')}: ${cable.ampacityA.toStringAsFixed(0)} A',
        ),
        _standardContextCard(),
      ],
    );
  }

  Widget _quickActionGrid() {
    final actions = [
      _Action(t('scan_equipment'), Icons.document_scanner_outlined, _scanOCR),
      _Action(t('short_circuit'), Icons.bolt, () => setState(() => activeTab = 2)),
      _Action(t('protection'), Icons.shield_outlined, () => setState(() => activeTab = 3)),
      _Action(t('cable'), Icons.cable_outlined, () => setState(() => activeTab = 4)),
      _Action(t('load_flow'), Icons.show_chart, () => setState(() => activeTab = 5)),
      _Action(t('field_context'), Icons.location_on_outlined, _fetchGPSData),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.7,
      ),
      itemBuilder: (_, index) {
        final action = actions[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: action.onTap,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(action.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shortCircuitTab() {
    final data = _shortCircuitData();
    final result = standardEngine.verify<double>(
      domain: AnalysisDomain.shortCircuit,
      value: data['ikKa'] as double,
      explanation: t('short_circuit_explanation'),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          '${t('short_circuit')} • ${standardEngine.standardFor(AnalysisDomain.shortCircuit)?.code ?? 'N/A'}',
          Column(
            children: [
              _numberField(
                label: t('voltage_kv'),
                value: p.voltageKv,
                onChanged: (v) => p.voltageKv = v,
              ),
              _numberField(
                label: t('grid_ssc_mva'),
                value: p.gridSscMva,
                onChanged: (v) => p.gridSscMva = v,
              ),
              _numberField(
                label: t('trafo_mva'),
                value: p.trafoMva,
                onChanged: (v) => p.trafoMva = v,
              ),
              _numberField(
                label: t('uk_percent'),
                value: p.ukPercent,
                onChanged: (v) => p.ukPercent = v,
              ),
              const Divider(height: 24),
              _resultRow(t('fault_current'), '${(data['ikKa'] as double).toStringAsFixed(2)} kA'),
              _resultRow(t('thevenin_impedance'), '${(data['zOhm'] as double).toStringAsFixed(4)} Ω'),
              _resultRow(t('breaker_capacity'), '${breaker.ratedBreakingIcuKa.toStringAsFixed(1)} kA'),
              _statusBanner(
                result.status,
                result.explanation,
              ),
              if (appMode == AppMode.professional)
                _whyButton(
                  t('short_circuit'),
                  '${t('input')}: ${p.voltageKv} kV, Ssc ${p.gridSscMva} MVA, Trafo ${p.trafoMva} MVA, uk ${p.ukPercent}%\n\n${result.explanation}',
                ),
            ],
          ),
        ),
      ],
    );
  }

  ProtectionResult _protectionData() {
    final faultA = p.up50PickupA * 2.5;
    return ElectricalEngine.calculateTripTime(
      faultCurrentA: faultA,
      pickupCurrentA: p.up50PickupA,
      timeMultiplier: p.upTms,
      curve: p.upCurve,
    );
  }

  Map<String, dynamic> _shortCircuitData() {
    final zGrid = ElectricalEngine.calculateGridImpedance(
      voltageKv: p.voltageKv,
      shortCircuitMva: p.gridSscMva,
    );
    final zTrafo = ElectricalEngine.calculateTransformerImpedance(
      ratedMva: p.trafoMva,
      ukPercent: p.ukPercent,
      voltageKv: p.voltageKv,
    );
    final z = zGrid + zTrafo;
    final ikKa = z.magnitude <= 0
        ? 0.0
        : (p.voltageKv * 1000.0) / (math.sqrt(3.0) * z.magnitude) / 1000.0;

    return {
      'ikKa': ikKa,
      'zOhm': z.magnitude,
      'breakerOk': breaker.ratedBreakingIcuKa >= ikKa,
    };
  }

  Widget _protectionTab() {
    final faultA = p.up50PickupA * 2.5;
    final result = ElectricalEngine.calculateTripTime(
      faultCurrentA: faultA,
      pickupCurrentA: p.up50PickupA,
      timeMultiplier: p.upTms,
      curve: p.upCurve,
    );

    final std = standardEngine.standardFor(AnalysisDomain.protection);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          '${t('protection')} • ${std?.code ?? 'N/A'}',
          Column(
            children: [
              DropdownButtonFormField<TripCurve>(
                value: p.upCurve,
                decoration: InputDecoration(labelText: t('curve')),
                items: TripCurve.values
                    .map(
                      (curve) => DropdownMenuItem(
                        value: curve,
                        child: Text(curve.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => p.upCurve = value);
                  _persistProjects();
                },
              ),
              _numberField(
                label: t('pickup_a'),
                value: p.up50PickupA,
                onChanged: (v) => p.up50PickupA = v,
              ),
              _numberField(
                label: t('tms'),
                value: p.upTms,
                onChanged: (v) => p.upTms = v,
              ),
              const Divider(height: 24),
              _resultRow(t('simulated_fault'), '${faultA.toStringAsFixed(0)} A'),
              _resultRow(
                t('trip_time'),
                result.tripTimeS.isFinite
                    ? '${result.tripTimeS.toStringAsFixed(3)} s'
                    : t('no_trip'),
              ),
              _statusBanner(result.status, result.message),
              if (appMode == AppMode.professional)
                _whyButton(
                  t('protection'),
                  '${std?.code ?? 'N/A'}\n${result.message}',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cableTab() {
    final result = _cableData();
    final std = standardEngine.standardFor(AnalysisDomain.cable);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          '${t('cable')} • ${std?.code ?? 'N/A'}',
          Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('copper_conductor')),
                value: p.isCopper,
                onChanged: (value) {
                  setState(() => p.isCopper = value);
                  _persistProjects();
                },
              ),
              _numberField(
                label: t('section_mm2'),
                value: p.cableSectionMm2,
                onChanged: (v) => p.cableSectionMm2 = v,
              ),
              _numberField(
                label: t('length_m'),
                value: p.cableLengthM,
                onChanged: (v) => p.cableLengthM = v,
              ),
              _numberField(
                label: t('load_current_a'),
                value: p.loadCurrentA,
                onChanged: (v) => p.loadCurrentA = v,
              ),
              const Divider(height: 24),
              _resultRow(t('ampacity'), '${result.ampacityA.toStringAsFixed(0)} A'),
              _resultRow(t('voltage_drop'), '${result.voltageDropPercent.toStringAsFixed(2)} %'),
              _resultRow(t('thermal_check'), result.status == ComplianceStatus.fail ? t('fail') : t('pass')),
              _statusBanner(result.status, result.message),
            ],
          ),
        ),
      ],
    );
  }

  CableSizeResult _cableData() {
    return CableEngine.sizeCable(
      designCurrentA: p.loadCurrentA,
      lengthM: p.cableLengthM,
      voltageV: p.voltageKv * 1000.0,
      powerFactor: p.cablePowerFactor,
      aluminium: !p.isCopper,
      method: CableInstallationMethod.methodCOnWall,
      resistanceOhmPerKm: p.isCopper ? 0.268 : 0.443,
      reactanceOhmPerKm: 0.08,
      maxVoltageDropPercent: 3.0,
    );
  }

  Widget _loadFlowTab() {
    final result = _loadFlowData();
    final std = standardEngine.standardFor(AnalysisDomain.loadFlow);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          '${t('load_flow')} • ${std?.code ?? 'N/A'}',
          Column(
            children: [
              _numberField(
                label: t('active_power_mw'),
                value: p.loadFlowMw,
                onChanged: (v) => p.loadFlowMw = v,
              ),
              _numberField(
                label: t('power_factor'),
                value: p.loadFlowPf,
                onChanged: (v) => p.loadFlowPf = v.clamp(.1, 1.0).toDouble(),
              ),
              _numberField(
                label: t('line_length_km'),
                value: p.lineLengthKm,
                onChanged: (v) => p.lineLengthKm = v,
              ),
              const Divider(height: 24),
              _resultRow(t('current'), '${result.currentA.toStringAsFixed(1)} A'),
              _resultRow(t('voltage_drop'), '${result.voltageDropPercent.toStringAsFixed(2)} %'),
              _resultRow(t('receiving_voltage'), '${result.receivingVoltageV.toStringAsFixed(0)} V'),
              _statusBanner(result.status, result.message),
            ],
          ),
        ),
      ],
    );
  }

  LoadFlowResult _loadFlowData() {
    final z = ElectricalEngine.calculateGridImpedance(
      voltageKv: p.voltageKv,
      shortCircuitMva: p.gridSscMva,
    ) + ElectricalEngine.calculateTransformerImpedance(
      ratedMva: p.trafoMva,
      ukPercent: p.ukPercent,
      voltageKv: p.voltageKv,
    ) + ImpedanceFactory.cable(
      lengthKm: p.lineLengthKm,
      resistanceOhmPerKm: p.lineROhmPerKm,
      reactanceOhmPerKm: p.lineXOhmPerKm,
    );

    return LoadFlowEngine.calculate(
      voltageV: p.voltageKv * 1000.0,
      powerW: p.loadFlowMw * 1000000.0,
      powerFactor: p.loadFlowPf,
      pathImpedance: z,
    );
  }

  Widget _sldTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          t('single_line'),
          SizedBox(
            height: 240,
            child: CustomPaint(
              painter: SldPainter(
                cells: p.cells,
                color: switchgear.brandColor,
              ),
            ),
          ),
        ),
        ...p.cells.map(
          (cell) => Card(
            child: ListTile(
              dense: true,
              title: Text(cell.name),
              subtitle: Text(
                '${cell.currentVendor} • ${cell.currentBreaker} • CT ${cell.ctRatio}',
              ),
              trailing: Switch(
                value: cell.cbClosed,
                onChanged: (value) {
                  setState(() => cell.cbClosed = value);
                  _persistProjects();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dgaTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          'DGA',
          Column(
            children: [
              Text(t('dga_note')),
              const SizedBox(height: 12),
              _resultRow('H₂', '— ppm'),
              _resultRow('CH₄', '— ppm'),
              _resultRow('C₂H₆', '— ppm'),
              _resultRow('C₂H₄', '— ppm'),
              _resultRow('C₂H₂', '— ppm'),
              const Divider(),
              _statusBanner(
                ComplianceStatus.notVerified,
                t('dga_not_verified'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _satTab() {
    final passed = p.resR <= breaker.defaultLimitMicroOhm &&
        p.resS <= breaker.defaultLimitMicroOhm &&
        p.resT <= breaker.defaultLimitMicroOhm;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          t('sat'),
          Column(
            children: [
              Text(t('sat_note')),
              const SizedBox(height: 12),
              _numberField(label: 'R (µΩ)', value: p.resR, onChanged: (v) => p.resR = v),
              _numberField(label: 'S (µΩ)', value: p.resS, onChanged: (v) => p.resS = v),
              _numberField(label: 'T (µΩ)', value: p.resT, onChanged: (v) => p.resT = v),
              _resultRow(t('manufacturer_limit'), '${breaker.defaultLimitMicroOhm.toStringAsFixed(0)} µΩ'),
              _statusBanner(
                passed ? ComplianceStatus.pass : ComplianceStatus.fail,
                passed ? t('pass') : t('fail'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _standardContextCard() {
    final profile = standardEngine.profile;

    return _card(
      t('standard_profile'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(profile.description, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 10),
          ...profile.standards.map(
            (standard) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, size: 15),
                  const SizedBox(width: 7),
                  Expanded(child: Text('${standard.domain.name}: ${standard.code} • ${standard.edition}', style: const TextStyle(fontSize: 10))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showProfileDialog,
            icon: const Icon(Icons.swap_horiz),
            label: Text(t('change_standard')),
          ),
        ],
      ),
    );
  }

  Widget _fieldContextCard() {
    return _card(
      t('field_context'),
      Column(
        children: [
          _resultRow(t('country'), p.countryCode),
          _resultRow(t('altitude'), '${p.altitudeMeters.toStringAsFixed(0)} m'),
          _resultRow(t('ambient_temperature'), '${p.ambientTempC.toStringAsFixed(1)} °C'),
          _resultRow(t('data_source'), t('demo_data')), 
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('language')),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: AppLanguage.values
                .map(
                  (language) => RadioListTile<AppLanguage>(
                    value: language,
                    groupValue: currentLanguage,
                    title: Text(language.nativeName),
                    onChanged: (value) {
                      if (value == null) return;
                      Navigator.pop(context);
                      _changeLanguage(value);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void _showProfileDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('standard_profile')),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: StandardRegistry.profiles
                .map(
                  (profile) => RadioListTile<String>(
                    value: profile.id,
                    groupValue: p.standardProfileId,
                    title: Text(profile.name),
                    subtitle: Text(profile.description),
                    onChanged: (value) {
                      if (value == null) return;
                      Navigator.pop(context);
                      _changeStandard(value);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _numberField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final controller = TextEditingController(text: _formatNumber(value));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.help_outline, size: 17),
            onPressed: () => _showInfoDialog(label, t('direct_numeric_input')),
          ),
        ),
        onSubmitted: (text) {
          final parsed = double.tryParse(text.replaceAll(',', '.'));
          if (parsed != null) {
            setState(() => onChanged(parsed));
            _persistProjects();
          }
        },
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3);
  }

  Widget _card(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _statusChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _bigStatusCard({
    required String title,
    required String value,
    required bool ok,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.warning_rounded, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white60)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(Object status, String message) {
    final statusName = status.toString().split('.').last;
    final text = switch (statusName) {
      'pass' => t('pass'),
      'fail' => t('fail'),
      'warning' => t('warning'),
      _ => t('not_verified'),
    };

    final icon = switch (statusName) {
      'pass' => Icons.check_circle,
      'fail' => Icons.cancel,
      'warning' => Icons.warning_amber,
      _ => Icons.help_outline,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('$text — $message', style: const TextStyle(fontSize: 10))),
        ],
      ),
    );
  }

  bool _status(bool ok) => ok;

  Widget _whyButton(String title, String content) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => _showInfoDialog(title, content),
        icon: const Icon(Icons.help_outline, size: 16),
        label: Text(t('why')),
      ),
    );
  }
}

class _TabDefinition {
  final IconData icon;
  final String label;

  const _TabDefinition(this.icon, this.label);
}

class _Action {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _Action(this.title, this.icon, this.onTap);
}

class SldPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final Color color;

  SldPainter({required this.cells, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final busY = size.height * .28;
    final line = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;
    final bus = Paint()
      ..color = color
      ..strokeWidth = 4;

    canvas.drawLine(
      const Offset(15, 30),
      Offset(size.width - 15, 30),
      bus,
    );

    for (int i = 0; i < cells.length; i++) {
      final x = 55.0 + i * 105;

      canvas.drawLine(
        Offset(x, 30),
        Offset(x, busY + 45),
        line,
      );

      final rect = Rect.fromCenter(
        center: Offset(x, busY),
        width: 20,
        height: 20,
      );

      final statePaint = Paint()
        ..color = cells[i].cbClosed
            ? const Color(0xFFFF3D00)
            : const Color(0xFF00E676);

      canvas.drawRect(rect, statePaint);

      final outline = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, outline);

      final painter = TextPainter(
        text: TextSpan(
          text: cells[i].name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);

      painter.paint(canvas, Offset(x - 45, busY + 24));
    }
  }

  @override
  bool shouldRepaint(covariant SldPainter oldDelegate) => true;
}
