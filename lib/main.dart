// PowerField Pro v6.8 - Faz 1 Güncellemesi
// UTF-8, BOM'suz kaydedin.
// Gerekli pubspec bağımlılığı: shared_preferences
// GitHub Actions'ta Flutter bağımlılıklarını kurmadan önce 'flutter pub get' çalıştırılmalıdır.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const PowerFieldProApp());

class PowerFieldProApp extends StatelessWidget {
  const PowerFieldProApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PowerField Pro v6.8',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF070A0E),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFB300),
            secondary: Color(0xFF00E676),
            error: Color(0xFFFF3D00),
            surface: Color(0xFF111622),
          ),
        ),
        home: const MainCockpit(),
      );
}

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
enum ProtectionStandard { iec60255, ieeeC37112 }
enum TripCurve { standardInverse, veryInverse, extremelyInverse, longTimeInverse }

class ElectricalEngine {
  static Map<String, double> calcIec60909FaultCurrents({
    required double voltageKv, required double trafoMva, required double ukPercent,
    double gridSscMva = 1000, double xrRatio = 8,
  }) {
    if (voltageKv <= 0 || trafoMva <= 0 || ukPercent <= 0) {
      return {'Ik_max': 0, 'Ik_min': 0, 'Ip_peak': 0};
    }
    final v = voltageKv;
    final zQ = gridSscMva > 0 ? (v * v) / gridSscMva : 0.0;
    final zT = (ukPercent / 100) * (v * v / trafoMva);
    final rT = zT / sqrt(1 + xrRatio * xrRatio);
    final xT = rT * xrRatio;
    final zMax = zQ + zT;
    final ikMax = (1.10 * v) / (sqrt(3) * zMax);
    final rHot = rT * 1.24;
    final zTHot = sqrt(rHot * rHot + xT * xT);
    final zMin = zQ + zTHot;
    final ikMin = v / (sqrt(3) * zMin);
    final rx = xrRatio <= 0 ? 1.0 : 1.0 / xrRatio;
    final kappa = 1.02 + 0.98 * exp(-3.0 * rx);
    final ipPeak = sqrt(2) * kappa * ikMax;
    return {'Ik_max': ikMax, 'Ik_min': ikMin, 'Ip_peak': ipPeak, 'kappa': kappa};
  }

  static double calcNominalCurrentA(double mva, double voltageKv) =>
      voltageKv <= 0 ? 0 : (mva * 1000) / (sqrt(3) * voltageKv);

  static double calcRocofHzSec({required double deltaP_Mw, required double generatorMw, double inertiaH_Sec = 3.5, double cosPhi = .85, double f0 = 50}) {
    final sg = generatorMw / cosPhi;
    if (sg <= 0 || inertiaH_Sec <= 0) return 0;
    return (f0 * deltaP_Mw) / (2 * inertiaH_Sec * sg);
  }

  static Map<String, double> calcDistanceZones({required double lineLengthKm, required double rOhmPerKm, required double xOhmPerKm}) {
    final z = lineLengthKm * sqrt(rOhmPerKm * rOhmPerKm + xOhmPerKm * xOhmPerKm);
    return {'Z_line': z, 'Zone1': z * .85, 'Zone2': z * 1.20, 'Zone3': z * 1.50};
  }

  static double calcCompensatedSf6Pressure({required double measuredPressureMpa, required double ambientTempC, double referenceTempC = 20}) {
    final t = ambientTempC + 273.15;
    final tref = referenceTempC + 273.15;
    if (t <= 0) return measuredPressureMpa;
    return measuredPressureMpa * tref / t;
  }

  static double calcResonanceOrder(double sscMva, double qcKvar) {
    if (sscMva <= 0 || qcKvar <= 0) return 0;
    return sqrt(sscMva / (qcKvar / 1000));
  }

  static double calcMotorStartVoltageDipPercent({required double motorKw, required double sscMva, double startCurrentMultiplier = 6, double cosPhi = .85, double efficiency = .94}) {
    if (sscMva <= 0 || motorKw <= 0) return 0;
    final sNom = (motorKw / 1000) / (cosPhi * efficiency);
    final sStart = sNom * startCurrentMultiplier;
    return 100 * sStart / (sscMva + sStart);
  }

  static double calcPrimaryPickupAmps({required double ctPrimaryA, required double ctSecondaryA, required double secondarySettingA}) =>
      ctSecondaryA <= 0 ? 0 : secondarySettingA * ctPrimaryA / ctSecondaryA;

  static double calcTripTime({required double faultA, required double iPickupA, required double tmsVal, required TripCurve curve, ProtectionStandard standard = ProtectionStandard.iec60255}) {
    if (faultA <= iPickupA || iPickupA <= 0 || tmsVal <= 0) return double.infinity;
    final m = faultA / iPickupA;
    if (standard == ProtectionStandard.iec60255) {
      double k = .14, alpha = .02;
      switch (curve) {
        case TripCurve.veryInverse: k = 13.5; alpha = 1;
        case TripCurve.extremelyInverse: k = 80; alpha = 2;
        case TripCurve.longTimeInverse: k = 120; alpha = 1;
        case TripCurve.standardInverse: break;
      }
      final d = pow(m, alpha) - 1;
      return d <= 0 ? double.infinity : tmsVal * k / d;
    }
    double a = .0515, b = .114, p = .02;
    switch (curve) {
      case TripCurve.veryInverse: a = 19.61; b = .491; p = 2;
      case TripCurve.extremelyInverse: a = 28.2; b = .1217; p = 2;
      case TripCurve.longTimeInverse: a = 120; b = 0; p = 1;
      case TripCurve.standardInverse: break;
    }
    final d = pow(m, p) - 1;
    return d <= 0 ? double.infinity : tmsVal * (a / d + b);
  }

  static Map<String, dynamic> evaluateCableSizing({required double sectionMm2, required double lengthM, required double loadCurrentA, required double voltageKv, required double ikKa, required double faultTimeSec, required bool isCopper, double ambientTempC = 30, double groupingFactor = .85, double installationFactor = 1.0, double powerFactor = .85}) {
    final k = isCopper ? 143.0 : 94.0;
    final sMin = ikKa * 1000 * sqrt(max(faultTimeSec, 0)) / k;
    final thermal = sectionMm2 >= sMin;
    const ampacity = <int, double>{35: 145, 50: 175, 70: 215, 95: 260, 120: 295, 150: 335, 185: 380, 240: 440, 300: 495};
    final baseIz = ampacity[sectionMm2.round()] ?? sectionMm2 * 2.2;
    final kt = ambientTempC <= 20 ? 1.05 : max(.50, 1 - (ambientTempC - 20) * .005);
    final iz = baseIz * kt * groupingFactor * installationFactor;
    final ampacityOk = loadCurrentA <= iz;
    final rho = isCopper ? .0175 : .028;
    final r = rho * lengthM / max(sectionMm2, .1);
    const xOhmPerKm = .08;
    final x = xOhmPerKm * lengthM / 1000;
    final sinPhi = sqrt(max(0, 1 - powerFactor * powerFactor));
    final du = sqrt(3) * loadCurrentA * (r * powerFactor + x * sinPhi);
    final drop = voltageKv <= 0 ? double.infinity : du / (voltageKv * 1000) * 100;
    return {'sMin': sMin, 'isThermalOk': thermal, 'deratedIz': iz, 'isAmpacityOk': ampacityOk, 'dropPercent': drop, 'isVoltageDropOk': drop <= 3, 'isOverallPass': thermal && ampacityOk && drop <= 3};
  }

  static Map<String, double> calcLoadFlow({required double voltageKv, required double activePowerMw, required double powerFactor, required double lineLengthKm, required double rOhmPerKm, required double xOhmPerKm, double sourceSscMva = 1000}) {
    final pf = powerFactor.clamp(.2, 1.0).toDouble();
    if (voltageKv <= 0 || activePowerMw < 0 || lineLengthKm < 0) return {'currentA': 0, 'qMvar': 0, 'sendingKv': 0, 'receivingKv': 0, 'dropPercent': 0, 'lossMw': 0};
    final qMvar = activePowerMw * sqrt(max(0, 1 / (pf * pf) - 1));
    final sMva = sqrt(activePowerMw * activePowerMw + qMvar * qMvar);
    final currentA = sMva * 1000 / (sqrt(3) * voltageKv);
    final r = rOhmPerKm * lineLengthKm;
    final x = xOhmPerKm * lineLengthKm;
    final sinPhi = sqrt(max(0, 1 - pf * pf));
    final duKv = sqrt(3) * currentA * (r * pf + x * sinPhi) / 1000;
    final receivingKv = max(0.001, voltageKv - duKv);
    final drop = 100 * duKv / voltageKv;
    final lossMw = 3 * pow(currentA, 2) * r / 1e6;
    final sourceLimited = sourceSscMva > 0 ? min(1.0, sourceSscMva / max(sourceSscMva, sMva)) : 1.0;
    return {'currentA': currentA, 'qMvar': qMvar, 'sendingKv': voltageKv, 'receivingKv': receivingKv, 'dropPercent': drop, 'lossMw': lossMw * sourceLimited};
  }

  static Map<String, double> calcHarmonics({required double fundamentalCurrentA, required List<double> harmonicOrders, required List<double> harmonicPercentOfFundamental, required double shortCircuitMva, required double systemVoltageKv, double backgroundThdvPercent = 0}) {
    final n = min(harmonicOrders.length, harmonicPercentOfFundamental.length);
    double sumI2 = 0;
    double thdv2 = backgroundThdvPercent * backgroundThdvPercent;
    for (int i = 0; i < n; i++) {
      final ih = fundamentalCurrentA * harmonicPercentOfFundamental[i] / 100;
      sumI2 += ih * ih;
      final order = max(2.0, harmonicOrders[i]);
      final impedanceOhm = systemVoltageKv <= 0 || shortCircuitMva <= 0 ? 0 : (systemVoltageKv * systemVoltageKv / shortCircuitMva) * order;
      final vhPercent = systemVoltageKv <= 0 ? 0 : 100 * ih * impedanceOhm / (systemVoltageKv * 1000 / sqrt(3));
      thdv2 += vhPercent * vhPercent;
    }
    final thdi = fundamentalCurrentA <= 0 ? 0 : 100 * sqrt(sumI2) / fundamentalCurrentA;
    return {'thdiPercent': thdi, 'thdvPercent': sqrt(thdv2)};
  }

  static double calcAltitudeDeratingFactor(double altitudeMeters) {
    if (altitudeMeters <= 1000) return 1;
    return max(.60, 1 - (altitudeMeters - 1000) * .00004);
  }
}

class EngineeringVerdict {
  final bool shortCircuitIcu, shortCircuitIcw, shortCircuitIp, selectivityMargin;
  final bool instantaneousCoordination, cableThermal, cableAmpacity, cableVoltageDrop, satDuctor, satSync;
  const EngineeringVerdict({required this.shortCircuitIcu, required this.shortCircuitIcw, required this.shortCircuitIp, required this.selectivityMargin, required this.instantaneousCoordination, required this.cableThermal, required this.cableAmpacity, required this.cableVoltageDrop, required this.satDuctor, required this.satSync});
  bool get isReadyForCommissioning => shortCircuitIcu && shortCircuitIcw && shortCircuitIp && selectivityMargin && instantaneousCoordination && cableThermal && cableAmpacity && cableVoltageDrop && satDuctor && satSync;
}

class BreakerModel {
  final String name, vendor, medium, standardCode;
  final double defaultLimitMicroOhm, ratedBreakingIcuKa, serviceBreakingIcsKa, shortTimeWithstandIcwKa, peakMakingIpKa;
  final Color brandColor;
  const BreakerModel({required this.name, required this.vendor, required this.medium, required this.defaultLimitMicroOhm, required this.ratedBreakingIcuKa, required this.serviceBreakingIcsKa, required this.shortTimeWithstandIcwKa, required this.peakMakingIpKa, required this.standardCode, required this.brandColor});
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
  bool _loadingSavedProjects = false;
  bool _modeDialogShown = false;
  bool _disclaimerShown = false; // YASAL UYARI KONTROLÜ

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
            'Bu yazılım, saha mühendisleri ve teknikerler için geliştirilmiş '
            'bağımsız bir ön mühendislik ve simülasyon aracıdır.\n\n'
            'Adı geçen markalarla (Schneider, Siemens, ABB, Eaton, Mitsubishi, Ormazabal vb.) hiçbir resmi bağı, '
            'ortaklığı veya sponsorluk ilişkisi bulunmamaktadır. Tüm ticari marka isimleri '
            've donanım verileri yalnızca teknik referans amacıyla kullanılmıştır.\n\n'
            'Bu uygulama, sertifikalı saha devreye alma çalışmasının veya resmi '
            'üretici yazılımlarının yerine geçmez. Doğacak riskler kullanıcının sorumluluğundadır.',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    projects = [
      ProjectModel(
        name: 'Aliağa OSB Dağıtım TM-1', domain: PowerDomain.distribution, archetype: SubArchetype.heavyIndustry,
        voltageKv: 34.5, trafoMva: 2.5, ukPercent: 6, gridSscMva: 1000, switchgearIndex: 0, breakerIndex: 0,
        testHistory: const [TestRecord(timestamp: '12/03/2025', substation: 'Aliağa OSB TM-1', breaker: 'Schneider Evolis', maxRes: 31.4, syncDelta: 1.2, passed: true)],
        cells: _cells('Schneider', 'Schneider Evolis (Vakum)'),
      ),
      ProjectModel(
        name: 'Torbalı GES 15 MW', domain: PowerDomain.generation, archetype: SubArchetype.solarGES,
        voltageKv: 34.5, trafoMva: 16, ukPercent: 6.5, gridSscMva: 750, switchgearIndex: 2, breakerIndex: 2,
        testHistory: const [], cells: _cells('Schneider', 'Schneider SF1 / SF2'),
      ),
    ];
    _loadPreferencesAndProjects();

    // AÇILIŞTA YASAL UYARIYI GÖSTER
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

  Map<String, double> get fault => ElectricalEngine.calcIec60909FaultCurrents(voltageKv: p.voltageKv, trafoMva: p.trafoMva, ukPercent: p.ukPercent, gridSscMva: p.gridSscMva);
  double get ikMax => fault['Ik_max'] ?? 0;
  double get ipPeak => fault['Ip_peak'] ?? 0;

  double primary(double secondary) => ElectricalEngine.calcPrimaryPickupAmps(ctPrimaryA: p.ctPri, ctSecondaryA: p.ctSec, secondarySettingA: secondary);
  double trip(double faultA, double pickup, double tms, TripCurve curve) => ElectricalEngine.calcTripTime(faultA: faultA, iPickupA: pickup, tmsVal: tms, curve: curve, standard: p.protectionStandard);

  double get selectivityMarginSec {
    final start = max(1.05 * min(primary(p.downSettingSecA), primary(p.upSettingSecA)), 10);
    final end = max(ikMax * 1000, start * 1.01);
    double minMargin = double.infinity;
    for (int n = 0; n <= 160; n++) {
      final current = start * pow(end / start, n / 160);
      final tu = trip(current, primary(p.upSettingSecA), p.upTms, p.upCurve);
      final td = trip(current, primary(p.downSettingSecA), p.downTms, p.downCurve);
      if (tu.isFinite && td.isFinite) minMargin = min(minMargin, tu - td);
    }
    return minMargin.isFinite ? minMargin : double.negativeInfinity;
  }

  bool get instantaneousCoordination {
    if (!p.down50Enabled) return true;
    if (!p.up50Enabled) return p.down50PickupA >= ikMax * 1000;
    return p.down50PickupA < p.up50PickupA && p.up50PickupA >= ikMax * 1000;
  }

  Map<String, double> get loadFlow => ElectricalEngine.calcLoadFlow(voltageKv: p.voltageKv, activePowerMw: p.loadFlowMw, powerFactor: p.loadFlowPf, lineLengthKm: p.lineLengthKm, rOhmPerKm: p.lineROhmPerKm, xOhmPerKm: p.lineXOhmPerKm, sourceSscMva: p.gridSscMva);
  Map<String, double> get harmonics => ElectricalEngine.calcHarmonics(fundamentalCurrentA: p.loadCurrentA, harmonicOrders: const [3.0, 5.0, 7.0, 11.0], harmonicPercentOfFundamental: [p.harmonicH3Pct, p.harmonicH5Pct, p.harmonicH7Pct, p.harmonicH11Pct], shortCircuitMva: p.gridSscMva, systemVoltageKv: p.voltageKv, backgroundThdvPercent: p.harmonicBackgroundThdv);
  Map<String, dynamic> get cable => ElectricalEngine.evaluateCableSizing(sectionMm2: p.cableSectionMm2, lengthM: p.cableLengthM, loadCurrentA: p.loadCurrentA, voltageKv: p.voltageKv, ikKa: ikMax, faultTimeSec: .15, isCopper: p.isCopper, ambientTempC: p.ambientTempC, groupingFactor: p.cableGroupingFactor, installationFactor: p.cableInstallationFactor, powerFactor: p.cablePowerFactor);

  EngineeringVerdict get verdict {
    final satMax = max(p.resR, max(p.resS, p.resT));
    final sync = max((p.timeR-p.timeS).abs(), max((p.timeS-p.timeT).abs(), (p.timeR-p.timeT).abs()));
    return EngineeringVerdict(
      shortCircuitIcu: ikMax <= breaker.ratedBreakingIcuKa, shortCircuitIcw: ikMax <= breaker.shortTimeWithstandIcwKa, shortCircuitIp: ipPeak <= breaker.peakMakingIpKa,
      selectivityMargin: selectivityMarginSec >= .30, instantaneousCoordination: instantaneousCoordination,
      cableThermal: cable['isThermalOk'] as bool, cableAmpacity: cable['isAmpacityOk'] as bool, cableVoltageDrop: cable['isVoltageDropOk'] as bool,
      satDuctor: satMax <= breaker.defaultLimitMicroOhm, satSync: sync <= 3,
    );
  }

  Future<void> _persistProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('powerfield_projects_v67', jsonEncode(projects.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadPreferencesAndProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString('powerfield_app_mode_v67');
      final selected = prefs.getBool('powerfield_mode_selected_v67') ?? false;
      if (mounted) {
        setState(() {
          if (savedMode == AppMode.basic.name) appMode = AppMode.basic;
          if (savedMode == AppMode.professional.name) appMode = AppMode.professional;
        });
      }
      await _loadSavedProjects();
      if (!selected && mounted && !_modeDialogShown && _disclaimerShown) {
        _modeDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showModeChooser());
      }
    } catch (_) { await _loadSavedProjects(); }
  }

  Future<void> _setAppMode(AppMode mode) async {
    setState(() { appMode = mode; activeTab = 0; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('powerfield_app_mode_v67', mode.name);
    await prefs.setBool('powerfield_mode_selected_v67', true);
  }

  void _showModeChooser() {
    showDialog<void>(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('POWERFIELD PRO'),
        content: const Text('Çalışma seviyesini seçin. Profesyonel mod ayrıntılı mühendislik kontrollerini açar.'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _setAppMode(AppMode.basic); }, child: const Text('TEMEL')),
          FilledButton(onPressed: () { Navigator.pop(context); _setAppMode(AppMode.professional); }, child: const Text('PROFESYONEL')),
        ],
      ),
    );
  }

  Future<void> _loadSavedProjects() async {
    if (_loadingSavedProjects) return;
    _loadingSavedProjects = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('powerfield_projects_v67');
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = decoded.map((e) => ProjectModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (loaded.isNotEmpty && mounted) setState(() { projects = loaded; activeProject = 0; });
    } catch (_) {} finally { _loadingSavedProjects = false; }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('POWERFIELD PRO v6.8', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: switchgear.brandColor))),
    body: Column(children: [_projectBar(), Expanded(child: _tab())]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: activeTab,
      onDestinationSelected: (i) => setState(() => activeTab = i),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard), label: tr('Kokpit', 'Cockpit')),
        if (appMode == AppMode.professional) ...[
          NavigationDestination(icon: const Icon(Icons.show_chart), label: tr('TCC / Röle', 'TCC / Relay')),
          NavigationDestination(icon: const Icon(Icons.schema), label: 'SLD'),
        ],
      ],
    ),
  );

  void _applyEquipmentToCells() {
    for (final cell in p.cells) {
      cell.currentVendor = switchgear.vendor;
      if (cell.type != CellType.vtMetering) cell.currentBreaker = breaker.name;
    }
  }

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
      case 1: return _tcc();
      case 2: return _sld();
      default: return const SizedBox();
    }
  }

  Widget _cockpit() => ListView(padding: const EdgeInsets.all(12), children: [
    _card(tr('PROJE EKİPMANI', 'PROJECT EQUIPMENT'), Column(children: [
      DropdownButtonFormField<int>(
        value: _safeIndex(p.switchgearIndex, switchgears.length), isExpanded: true,
        items: List.generate(switchgears.length, (i) => DropdownMenuItem(value: i, child: Text(switchgears[i].name, style: const TextStyle(fontSize: 11)))),
        onChanged: (v) { if (v == null) return; setState(() { p.switchgearIndex = v; _applyEquipmentToCells(); }); _persistProjects(); },
      ),
      DropdownButtonFormField<int>(
        value: _safeIndex(p.breakerIndex, breakers.length), isExpanded: true,
        items: List.generate(breakers.length, (i) => DropdownMenuItem(value: i, child: Text('${breakers[i].name} | Icu ${breakers[i].ratedBreakingIcuKa} kA', style: const TextStyle(fontSize: 10)))),
        onChanged: (v) { if (v == null) return; setState(() { p.breakerIndex = v; _applyEquipmentToCells(); }); _persistProjects(); },
      ),
    ])),
    _slider('System Voltage kV', p.voltageKv, .4, 380, (v) => p.voltageKv = v),
    _slider('Grid Ssc MVA', p.gridSscMva, 200, 5000, (v) => p.gridSscMva = v),
  ]);

  Widget _tcc() => ListView(padding: const EdgeInsets.all(12), children: [
    _card('CT / 51 SETTINGS', Column(children: [
      _slider('CT Primary A', p.ctPri, 50, 2000, (v) => p.ctPri = v),
    ])),
  ]);

  Widget _sld() => ListView(padding: const EdgeInsets.all(12), children: [
    SizedBox(height: 230, child: CustomPaint(painter: SldPainter(cells: p.cells, color: switchgear.brandColor))),
    ...p.cells.map((c) => Card(child: ListTile(dense: true, title: Text(c.name, style: const TextStyle(fontSize: 11)), subtitle: Text('${c.currentVendor} | ${c.currentBreaker} | CT ${c.ctRatio}', style: const TextStyle(fontSize: 9)), trailing: Switch(value: c.cbClosed, onChanged: (v) => setState(() => c.cbClosed = v))))),
  ]);

  Widget _slider(String title, double value, double minV, double maxV, ValueChanged<double> onChanged) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 10)), Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFFFFB300)))]),
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
