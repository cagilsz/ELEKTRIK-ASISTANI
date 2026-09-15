// Konum: lib/models/powerfield_models.dart

import 'package:flutter/material.dart';
import '../engine/electrical_engine.dart'; // Motor bloğumuzdan referans alıyoruz

enum AppLanguage { tr, en }
enum AppMode { basic, professional }
enum PowerDomain { generation, transmission, distribution }
enum SubArchetype {
  solarGES, windRES, hydroHES, thermalCoal, biomass, naturalGas,
  hvSubstation154, hvGis380, hvSubstation400,
  heavyIndustry, factory, osb, hospital, airport, commercialMall,
  dataCenter, railway, waterTreatment, standardSubstation
}
enum RelayType {
  overcurrent50_51, earthFault50N_51N, directional67, distance21,
  transformerDifferential87T, restrictedEarthFault87N, voltage27_59,
  frequency81, rocof81R, motor49_46_48, synchCheck25
}
enum CellType { incomer, feeder, coupler, vtMetering }

class EngineeringVerdict {
  final bool shortCircuitIcu, shortCircuitIcw, shortCircuitIp, selectivityMargin;
  final bool instantaneousCoordination, cableThermal, cableAmpacity, cableVoltageDrop, satDuctor, satSync;
  
  const EngineeringVerdict({
    required this.shortCircuitIcu, required this.shortCircuitIcw, required this.shortCircuitIp, 
    required this.selectivityMargin, required this.instantaneousCoordination, required this.cableThermal, 
    required this.cableAmpacity, required this.cableVoltageDrop, required this.satDuctor, required this.satSync
  });
  
  bool get isReadyForCommissioning => 
      shortCircuitIcu && shortCircuitIcw && shortCircuitIp && selectivityMargin && 
      instantaneousCoordination && cableThermal && cableAmpacity && cableVoltageDrop && 
      satDuctor && satSync;
}

class BreakerModel {
  final String name, vendor, medium, standardCode;
  final double defaultLimitMicroOhm, ratedBreakingIcuKa, serviceBreakingIcsKa, shortTimeWithstandIcwKa, peakMakingIpKa;
  final Color brandColor;
  
  const BreakerModel({
    required this.name, required this.vendor, required this.medium, 
    required this.defaultLimitMicroOhm, required this.ratedBreakingIcuKa, 
    required this.serviceBreakingIcsKa, required this.shortTimeWithstandIcwKa, 
    required this.peakMakingIpKa, required this.standardCode, required this.brandColor
  });
}

const breakers = <BreakerModel>[
  BreakerModel(name: 'Schneider Evolis (Vakum)', vendor: 'Schneider', medium: 'Vacuum', defaultLimitMicroOhm: 35, ratedBreakingIcuKa: 25, serviceBreakingIcsKa: 25, shortTimeWithstandIcwKa: 25, peakMakingIpKa: 65, standardCode: 'IEC 62271-100', brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Schneider FB4', vendor: 'Schneider', medium: 'SF6', defaultLimitMicroOhm: 32, ratedBreakingIcuKa: 40, serviceBreakingIcsKa: 40, shortTimeWithstandIcwKa: 40, peakMakingIpKa: 104, standardCode: 'IEC 62271 / IEEE C37', brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Schneider SF1 / SF2', vendor: 'Schneider', medium: 'SF6', defaultLimitMicroOhm: 38, ratedBreakingIcuKa: 25, serviceBreakingIcsKa: 25, shortTimeWithstandIcwKa: 25, peakMakingIpKa: 65, standardCode: 'IEC 62271-100', brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Siemens SION 3AE / 3AH', vendor: 'Siemens', medium: 'Vacuum', defaultLimitMicroOhm: 45, ratedBreakingIcuKa: 31.5, serviceBreakingIcsKa: 31.5, shortTimeWithstandIcwKa: 31.5, peakMakingIpKa: 82, standardCode: 'IEC / DIN VDE', brandColor: Color(0xFF00646E)),
  BreakerModel(name: 'ABB VD4', vendor: 'ABB', medium: 'Vacuum', defaultLimitMicroOhm: 38, ratedBreakingIcuKa: 31.5, serviceBreakingIcsKa: 31.5, shortTimeWithstandIcwKa: 31.5, peakMakingIpKa: 82, standardCode: 'IEC 62271-100', brandColor: Color(0xFFFF000F)),
  BreakerModel(name: 'Eaton W-VACi', vendor: 'Eaton', medium: 'Vacuum', defaultLimitMicroOhm: 40, ratedBreakingIcuKa: 31.5, serviceBreakingIcsKa: 31.5, shortTimeWithstandIcwKa: 31.5, peakMakingIpKa: 82, standardCode: 'IEC 62271-100', brandColor: Color(0xFF005EB8)),
  BreakerModel(name: 'Mitsubishi VPR', vendor: 'Mitsubishi', medium: 'Vacuum', defaultLimitMicroOhm: 35, ratedBreakingIcuKa: 25, serviceBreakingIcsKa: 25, shortTimeWithstandIcwKa: 25, peakMakingIpKa: 65, standardCode: 'IEC / JIS', brandColor: Color(0xFFE60012)),
  BreakerModel(name: 'TEDAŞ Standart Vakum', vendor: 'Yerli/TEDAŞ', medium: 'Vacuum', defaultLimitMicroOhm: 50, ratedBreakingIcuKa: 16, serviceBreakingIcsKa: 16, shortTimeWithstandIcwKa: 16, peakMakingIpKa: 41.6, standardCode: 'TEDAŞ', brandColor: Color(0xFFFFB300)),
];

class SwitchgearModel {
  final String name, vendor, type, standard;
  final Color brandColor;
  const SwitchgearModel(this.name, this.vendor, this.type, this.standard, this.brandColor);
}

const switchgears = <SwitchgearModel>[
  SwitchgearModel('Schneider SM6-36', 'Schneider', 'AIS Modüler', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Schneider AirSeT', 'Schneider', 'SF6-Free', 'IEC 62271-200', Color(0xFF00B050)),
  SwitchgearModel('Schneider GHA', 'Schneider', 'GIS', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Schneider PremSeT', 'Schneider', 'SSIS', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Schneider RM6 / RMU', 'Schneider', 'RMU', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Siemens 8BT2 / NXAIR', 'Siemens', 'Metal-Clad', 'IEC 62271-200', Color(0xFF00646E)),
  SwitchgearModel('ABB UniGear ZS1', 'ABB', 'Metal-Clad', 'IEC 62271-200', Color(0xFFFF000F)),
  SwitchgearModel('Ormazabal cpg.0', 'Ormazabal', 'GIS', 'IEC 62271-200', Color(0xFF00558C)),
  SwitchgearModel('Ulusoy HMH-36 / Astor', 'TEDAŞ', 'Modüler Hücre', 'TEDAŞ', Color(0xFFFFB300)),
];

class DgaRecord {
  final String date;
  final double h2, ch4, c2h6, c2h4, c2h2, co, co2;
  final String diagnosticResult;
  const DgaRecord({required this.date, required this.h2, required this.ch4, required this.c2h6, required this.c2h4, required this.c2h2, required this.co, required this.co2, required this.diagnosticResult});
}

class TestRecord {
  final String timestamp, substation, breaker;
  final double maxRes, syncDelta;
  final bool passed;
  const TestRecord({required this.timestamp, required this.substation, required this.breaker, required this.maxRes, required this.syncDelta, required this.passed});
  Map<String, dynamic> toJson() => {'timestamp': timestamp, 'substation': substation, 'breaker': breaker, 'maxRes': maxRes, 'syncDelta': syncDelta, 'passed': passed};
  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(timestamp: j['timestamp'] as String? ?? '', substation: j['substation'] as String? ?? '', breaker: j['breaker'] as String? ?? '', maxRes: (j['maxRes'] as num?)?.toDouble() ?? 0, syncDelta: (j['syncDelta'] as num?)?.toDouble() ?? 0, passed: j['passed'] as bool? ?? false);
}

class SwitchgearCell {
  String id, name, ctRatio, currentVendor, currentBreaker;
  CellType type;
  bool cbClosed;
  SwitchgearCell({required this.id, required this.name, required this.type, this.cbClosed = false, this.ctRatio = '400/5A', this.currentVendor = 'Schneider', this.currentBreaker = 'Evolis'});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type.name, 'cbClosed': cbClosed, 'ctRatio': ctRatio, 'currentVendor': currentVendor, 'currentBreaker': currentBreaker};
  factory SwitchgearCell.fromJson(Map<String, dynamic> j) => SwitchgearCell(id: j['id'] as String? ?? 'C', name: j['name'] as String? ?? 'Cell', type: CellType.values.firstWhere((e) => e.name == j['type'], orElse: () => CellType.feeder), cbClosed: j['cbClosed'] as bool? ?? false, ctRatio: j['ctRatio'] as String? ?? '400/5A', currentVendor: j['currentVendor'] as String? ?? 'Schneider', currentBreaker: j['currentBreaker'] as String? ?? 'Evolis');
}

class ProjectModel {
  String name;
  PowerDomain domain;
  SubArchetype archetype;
  double voltageKv, trafoMva, ukPercent, gridSscMva;
  int switchgearIndex, breakerIndex;
  double ctPri, ctSec, upSettingSecA, upTms, downSettingSecA, downTms;
  TripCurve upCurve, downCurve;
  ProtectionStandard protectionStandard;
  bool up50Enabled, down50Enabled;
  double up50PickupA, down50PickupA;
  List<RelayType> relayTypes;
  double loadFlowMw, loadFlowPf, harmonicBackgroundThdv, harmonicH3Pct, harmonicH5Pct, harmonicH7Pct, harmonicH11Pct;
  double generatorMw, inertiaH, powerMismatchMw, motorKw, compensationKvar, hospitalRisoKOhm, airportCcrAmps, lineLengthKm, lineROhmPerKm, lineXOhmPerKm, sf6MeasuredMpa, ambientTempC, altitudeMeters;
  double resR, resS, resT, timeR, timeS, timeT;
  double cableLengthM, loadCurrentA, cableSectionMm2;
  bool isCopper;
  double cableGroupingFactor, cableInstallationFactor, cablePowerFactor;
  List<TestRecord> testHistory;
  List<SwitchgearCell> cells;

  ProjectModel({
    required this.name, required this.domain, required this.archetype, required this.voltageKv, required this.trafoMva, required this.ukPercent, required this.gridSscMva, required this.testHistory, required this.cells,
    this.switchgearIndex = 0, this.breakerIndex = 0, this.ctPri = 400, this.ctSec = 5, this.upSettingSecA = 7.5, this.upTms = .25, this.upCurve = TripCurve.standardInverse, this.downSettingSecA = 3.125, this.downTms = .15, this.downCurve = TripCurve.standardInverse, this.protectionStandard = ProtectionStandard.iec60255, this.up50Enabled = true, this.up50PickupA = 3000, this.down50Enabled = true, this.down50PickupA = 1500, this.relayTypes = const [RelayType.overcurrent50_51, RelayType.earthFault50N_51N], this.loadFlowMw = 5, this.loadFlowPf = .90, this.harmonicBackgroundThdv = 1.5, this.harmonicH3Pct = 8, this.harmonicH5Pct = 18, this.harmonicH7Pct = 7, this.harmonicH11Pct = 3, this.generatorMw = 20, this.inertiaH = 3.5, this.powerMismatchMw = 3, this.motorKw = 400, this.compensationKvar = 600, this.hospitalRisoKOhm = 85, this.airportCcrAmps = 6.6, this.lineLengthKm = 42, this.lineROhmPerKm = .08, this.lineXOhmPerKm = .30, this.sf6MeasuredMpa = .61, this.ambientTempC = 28, this.altitudeMeters = 50, this.resR = 33.2, this.resS = 34.8, this.resT = 33.9, this.timeR = 41.5, this.timeS = 42.8, this.timeT = 42.1, this.cableLengthM = 220, this.loadCurrentA = 110, this.cableSectionMm2 = 70, this.isCopper = true, this.cableGroupingFactor = .85, this.cableInstallationFactor = 1, this.cablePowerFactor = .85,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'domain': domain.name, 'archetype': archetype.name, 'voltageKv': voltageKv, 'trafoMva': trafoMva, 'ukPercent': ukPercent, 'gridSscMva': gridSscMva, 'switchgearIndex': switchgearIndex, 'breakerIndex': breakerIndex, 'ctPri': ctPri, 'ctSec': ctSec, 'upSettingSecA': upSettingSecA, 'upTms': upTms, 'upCurve': upCurve.name, 'downSettingSecA': downSettingSecA, 'downTms': downTms, 'downCurve': downCurve.name, 'protectionStandard': protectionStandard.name, 'up50Enabled': up50Enabled, 'up50PickupA': up50PickupA, 'down50Enabled': down50Enabled, 'down50PickupA': down50PickupA, 'relayTypes': relayTypes.map((e) => e.name).toList(), 'loadFlowMw': loadFlowMw, 'loadFlowPf': loadFlowPf, 'harmonicBackgroundThdv': harmonicBackgroundThdv, 'harmonicH3Pct': harmonicH3Pct, 'harmonicH5Pct': harmonicH5Pct, 'harmonicH7Pct': harmonicH7Pct, 'harmonicH11Pct': harmonicH11Pct, 'generatorMw': generatorMw, 'inertiaH': inertiaH, 'powerMismatchMw': powerMismatchMw, 'motorKw': motorKw, 'compensationKvar': compensationKvar, 'hospitalRisoKOhm': hospitalRisoKOhm, 'airportCcrAmps': airportCcrAmps, 'lineLengthKm': lineLengthKm, 'lineROhmPerKm': lineROhmPerKm, 'lineXOhmPerKm': lineXOhmPerKm, 'sf6MeasuredMpa': sf6MeasuredMpa, 'ambientTempC': ambientTempC, 'altitudeMeters': altitudeMeters, 'resR': resR, 'resS': resS, 'resT': resT, 'timeR': timeR, 'timeS': timeS, 'timeT': timeT, 'cableLengthM': cableLengthM, 'loadCurrentA': loadCurrentA, 'cableSectionMm2': cableSectionMm2, 'isCopper': isCopper, 'cableGroupingFactor': cableGroupingFactor, 'cableInstallationFactor': cableInstallationFactor, 'cablePowerFactor': cablePowerFactor, 'testHistory': testHistory.map((e) => e.toJson()).toList(), 'cells': cells.map((e) => e.toJson()).toList(),
  };

  factory ProjectModel.fromJson(Map<String, dynamic> j) => ProjectModel(
    name: j['name'] as String? ?? 'Project', domain: PowerDomain.values.firstWhere((e) => e.name == j['domain'], orElse: () => PowerDomain.distribution), archetype: SubArchetype.values.firstWhere((e) => e.name == j['archetype'], orElse: () => SubArchetype.standardSubstation), voltageKv: (j['voltageKv'] as num?)?.toDouble() ?? 34.5, trafoMva: (j['trafoMva'] as num?)?.toDouble() ?? 2.5, ukPercent: (j['ukPercent'] as num?)?.toDouble() ?? 6, gridSscMva: (j['gridSscMva'] as num?)?.toDouble() ?? 1000, switchgearIndex: (j['switchgearIndex'] as num?)?.toInt() ?? 0, breakerIndex: (j['breakerIndex'] as num?)?.toInt() ?? 0, ctPri: (j['ctPri'] as num?)?.toDouble() ?? 400, ctSec: (j['ctSec'] as num?)?.toDouble() ?? 5, upSettingSecA: (j['upSettingSecA'] as num?)?.toDouble() ?? 7.5, upTms: (j['upTms'] as num?)?.toDouble() ?? .25, upCurve: TripCurve.values.firstWhere((e) => e.name == j['upCurve'], orElse: () => TripCurve.standardInverse), downSettingSecA: (j['downSettingSecA'] as num?)?.toDouble() ?? 3.125, downTms: (j['downTms'] as num?)?.toDouble() ?? .15, downCurve: TripCurve.values.firstWhere((e) => e.name == j['downCurve'], orElse: () => TripCurve.standardInverse), protectionStandard: ProtectionStandard.values.firstWhere((e) => e.name == j['protectionStandard'], orElse: () => ProtectionStandard.iec60255), up50Enabled: j['up50Enabled'] as bool? ?? true, up50PickupA: (j['up50PickupA'] as num?)?.toDouble() ?? 3000, down50Enabled: j['down50Enabled'] as bool? ?? true, down50PickupA: (j['down50PickupA'] as num?)?.toDouble() ?? 1500, relayTypes: ((j['relayTypes'] as List?) ?? ['overcurrent50_51', 'earthFault50N_51N']).map((e) => RelayType.values.firstWhere((r) => r.name == e, orElse: () => RelayType.overcurrent50_51)).toSet().toList(), loadFlowMw: (j['loadFlowMw'] as num?)?.toDouble() ?? 5, loadFlowPf: (j['loadFlowPf'] as num?)?.toDouble() ?? .90, harmonicBackgroundThdv: (j['harmonicBackgroundThdv'] as num?)?.toDouble() ?? 1.5, harmonicH3Pct: (j['harmonicH3Pct'] as num?)?.toDouble() ?? 8, harmonicH5Pct: (j['harmonicH5Pct'] as num?)?.toDouble() ?? 18, harmonicH7Pct: (j['harmonicH7Pct'] as num?)?.toDouble() ?? 7, harmonicH11Pct: (j['harmonicH11Pct'] as num?)?.toDouble() ?? 3, generatorMw: (j['generatorMw'] as num?)?.toDouble() ?? 20, inertiaH: (j['inertiaH'] as num?)?.toDouble() ?? 3.5, powerMismatchMw: (j['powerMismatchMw'] as num?)?.toDouble() ?? 3, motorKw: (j['motorKw'] as num?)?.toDouble() ?? 400, compensationKvar: (j['compensationKvar'] as num?)?.toDouble() ?? 600, hospitalRisoKOhm: (j['hospitalRisoKOhm'] as num?)?.toDouble() ?? 85, airportCcrAmps: (j['airportCcrAmps'] as num?)?.toDouble() ?? 6.6, lineLengthKm: (j['lineLengthKm'] as num?)?.toDouble() ?? 42, lineROhmPerKm: (j['lineROhmPerKm'] as num?)?.toDouble() ?? .08, lineXOhmPerKm: (j['lineXOhmPerKm'] as num?)?.toDouble() ?? .30, sf6MeasuredMpa: (j['sf6MeasuredMpa'] as num?)?.toDouble() ?? .61, ambientTempC: (j['ambientTempC'] as num?)?.toDouble() ?? 28, altitudeMeters: (j['altitudeMeters'] as num?)?.toDouble() ?? 50, resR: (j['resR'] as num?)?.toDouble() ?? 33.2, resS: (j['resS'] as num?)?.toDouble() ?? 34.8, resT: (j['resT'] as num?)?.toDouble() ?? 33.9, timeR: (j['timeR'] as num?)?.toDouble() ?? 41.5, timeS: (j['timeS'] as num?)?.toDouble() ?? 42.8, timeT: (j['timeT'] as num?)?.toDouble() ?? 42.1, cableLengthM: (j['cableLengthM'] as num?)?.toDouble() ?? 220, loadCurrentA: (j['loadCurrentA'] as num?)?.toDouble() ?? 110, cableSectionMm2: (j['cableSectionMm2'] as num?)?.toDouble() ?? 70, isCopper: j['isCopper'] as bool? ?? true, cableGroupingFactor: (j['cableGroupingFactor'] as num?)?.toDouble() ?? .85, cableInstallationFactor: (j['cableInstallationFactor'] as num?)?.toDouble() ?? 1, cablePowerFactor: (j['cablePowerFactor'] as num?)?.toDouble() ?? .85, testHistory: ((j['testHistory'] as List?) ?? []).map((e) => TestRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(), cells: ((j['cells'] as List?) ?? []).map((e) => SwitchgearCell.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
  );
}
