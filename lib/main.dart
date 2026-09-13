// PowerField Pro v6.7
// UTF-8, BOM'suz kaydedin.
// Gerekli pubspec baÄŸÄ±mlÄ±lÄ±ÄŸÄ±: shared_preferences
// GitHub Actions'ta Flutter baÄŸÄ±mlÄ±lÄ±klarÄ±nÄ± kurmadan Ã¶nce 'flutter pub get' Ã§alÄ±ÅŸtÄ±rÄ±lmalÄ±dÄ±r.
// Bu kaynak Ã¶n mÃ¼hendislik/simÃ¼lasyon amaÃ§lÄ±dÄ±r; sertifikalÄ± saha Ã§alÄ±ÅŸmasÄ±nÄ±n yerine geÃ§mez.

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
        title: 'PowerField Pro v6.7',
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
  /// Simplified preliminary IEC 60909 model.
  /// For certified studies, replace with a full network model.
  static Map<String, double> calcIec60909FaultCurrents({
    required double voltageKv,
    required double trafoMva,
    required double ukPercent,
    double gridSscMva = 1000,
    double xrRatio = 8,
  }) {
    if (voltageKv <= 0 || trafoMva <= 0 || ukPercent <= 0) {
      return {'Ik_max': 0, 'Ik_min': 0, 'Ip_peak': 0};
    }

    final v = voltageKv;
    final zQ = gridSscMva > 0 ? (v * v) / gridSscMva : 0.0;
    final zT = (ukPercent / 100) * (v * v / trafoMva);

    final rT = zT / sqrt(1 + xrRatio * xrRatio);
    final xT = rT * xrRatio;

    // Maximum: cmax = 1.10, transformer impedance at cold reference.
    final zMax = zQ + zT;
    final ikMax = (1.10 * v) / (sqrt(3) * zMax);

    // Minimum: cmin = 1.00 and transformer resistance increased.
    final rHot = rT * 1.24;
    final zTHot = sqrt(rHot * rHot + xT * xT);
    final zMin = zQ + zTHot;
    final ikMin = v / (sqrt(3) * zMin);

    // Îº approximation derived from R/X instead of fixed 1.80.
    // This remains a simplified preliminary model.
    final rx = xrRatio <= 0 ? 1.0 : 1.0 / xrRatio;
    final kappa = 1.02 + 0.98 * exp(-3.0 * rx);
    final ipPeak = sqrt(2) * kappa * ikMax;

    return {
      'Ik_max': ikMax,
      'Ik_min': ikMin,
      'Ip_peak': ipPeak,
      'kappa': kappa,
    };
  }

  static double calcNominalCurrentA(double mva, double voltageKv) =>
      voltageKv <= 0 ? 0 : (mva * 1000) / (sqrt(3) * voltageKv);

  static double calcRocofHzSec({
    required double deltaP_Mw,
    required double generatorMw,
    double inertiaH_Sec = 3.5,
    double cosPhi = .85,
    double f0 = 50,
  }) {
    final sg = generatorMw / cosPhi;
    if (sg <= 0 || inertiaH_Sec <= 0) return 0;
    return (f0 * deltaP_Mw) / (2 * inertiaH_Sec * sg);
  }

  static Map<String, double> calcDistanceZones({
    required double lineLengthKm,
    required double rOhmPerKm,
    required double xOhmPerKm,
  }) {
    final z = lineLengthKm * sqrt(rOhmPerKm * rOhmPerKm + xOhmPerKm * xOhmPerKm);
    return {
      'Z_line': z,
      'Zone1': z * .85,
      'Zone2': z * 1.20,
      'Zone3': z * 1.50,
    };
  }

  static double calcCompensatedSf6Pressure({
    required double measuredPressureMpa,
    required double ambientTempC,
    double referenceTempC = 20,
  }) {
    final t = ambientTempC + 273.15;
    final tref = referenceTempC + 273.15;
    if (t <= 0) return measuredPressureMpa;
    return measuredPressureMpa * tref / t;
  }

  static double calcResonanceOrder(double sscMva, double qcKvar) {
    if (sscMva <= 0 || qcKvar <= 0) return 0;
    return sqrt(sscMva / (qcKvar / 1000));
  }

  static double calcMotorStartVoltageDipPercent({
    required double motorKw,
    required double sscMva,
    double startCurrentMultiplier = 6,
    double cosPhi = .85,
    double efficiency = .94,
  }) {
    if (sscMva <= 0 || motorKw <= 0) return 0;
    final sNom = (motorKw / 1000) / (cosPhi * efficiency);
    final sStart = sNom * startCurrentMultiplier;
    return 100 * sStart / (sscMva + sStart);
  }

  static double calcPrimaryPickupAmps({
    required double ctPrimaryA,
    required double ctSecondaryA,
    required double secondarySettingA,
  }) =>
      ctSecondaryA <= 0 ? 0 : secondarySettingA * ctPrimaryA / ctSecondaryA;

  static double calcTripTime({
    required double faultA,
    required double iPickupA,
    required double tmsVal,
    required TripCurve curve,
    ProtectionStandard standard = ProtectionStandard.iec60255,
  }) {
    if (faultA <= iPickupA || iPickupA <= 0 || tmsVal <= 0) return double.infinity;
    final m = faultA / iPickupA;

    if (standard == ProtectionStandard.iec60255) {
      double k = .14, alpha = .02;
      switch (curve) {
        case TripCurve.veryInverse:
          k = 13.5; alpha = 1;
        case TripCurve.extremelyInverse:
          k = 80; alpha = 2;
        case TripCurve.longTimeInverse:
          k = 120; alpha = 1;
        case TripCurve.standardInverse:
          break;
      }
      final d = pow(m, alpha) - 1;
      return d <= 0 ? double.infinity : tmsVal * k / d;
    }

    double a = .0515, b = .114, p = .02;
    switch (curve) {
      case TripCurve.veryInverse:
        a = 19.61; b = .491; p = 2;
      case TripCurve.extremelyInverse:
        a = 28.2; b = .1217; p = 2;
      case TripCurve.longTimeInverse:
        a = 120; b = 0; p = 1;
      case TripCurve.standardInverse:
        break;
    }
    final d = pow(m, p) - 1;
    return d <= 0 ? double.infinity : tmsVal * (a / d + b);
  }

  static Map<String, dynamic> evaluateCableSizing({
    required double sectionMm2,
    required double lengthM,
    required double loadCurrentA,
    required double voltageKv,
    required double ikKa,
    required double faultTimeSec,
    required bool isCopper,
    double ambientTempC = 30,
    double groupingFactor = .85,
    double installationFactor = 1.0,
    double powerFactor = .85,
  }) {
    final k = isCopper ? 143.0 : 94.0;
    final sMin = ikKa * 1000 * sqrt(max(faultTimeSec, 0)) / k;
    final thermal = sectionMm2 >= sMin;

    const ampacity = <int, double>{
      35: 145, 50: 175, 70: 215, 95: 260, 120: 295,
      150: 335, 185: 380, 240: 440, 300: 495,
    };

    final baseIz = ampacity[sectionMm2.round()] ?? sectionMm2 * 2.2;
    final kt = ambientTempC <= 20
        ? 1.05
        : max(.50, 1 - (ambientTempC - 20) * .005);
    final iz = baseIz * kt * groupingFactor * installationFactor;
    final ampacityOk = loadCurrentA <= iz;

    final rho = isCopper ? .0175 : .028;
    final r = rho * lengthM / max(sectionMm2, .1);
    const xOhmPerKm = .08;
    final x = xOhmPerKm * lengthM / 1000;
    final sinPhi = sqrt(max(0, 1 - powerFactor * powerFactor));
    final du = sqrt(3) * loadCurrentA * (r * powerFactor + x * sinPhi);
    final drop = voltageKv <= 0 ? double.infinity : du / (voltageKv * 1000) * 100;

    return {
      'sMin': sMin,
      'isThermalOk': thermal,
      'deratedIz': iz,
      'isAmpacityOk': ampacityOk,
      'dropPercent': drop,
      'isVoltageDropOk': drop <= 3,
      'isOverallPass': thermal && ampacityOk && drop <= 3,
    };
  }

  static Map<String, double> calcLoadFlow({
    required double voltageKv,
    required double activePowerMw,
    required double powerFactor,
    required double lineLengthKm,
    required double rOhmPerKm,
    required double xOhmPerKm,
    double sourceSscMva = 1000,
  }) {
    final pf = powerFactor.clamp(.2, 1.0).toDouble();
    if (voltageKv <= 0 || activePowerMw < 0 || lineLengthKm < 0) {
      return {'currentA': 0, 'qMvar': 0, 'sendingKv': 0, 'receivingKv': 0, 'dropPercent': 0, 'lossMw': 0};
    }
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
    return {
      'currentA': currentA,
      'qMvar': qMvar,
      'sendingKv': voltageKv,
      'receivingKv': receivingKv,
      'dropPercent': drop,
      'lossMw': lossMw * sourceLimited,
    };
  }

  static Map<String, double> calcHarmonics({
    required double fundamentalCurrentA,
    required List<double> harmonicOrders,
    required List<double> harmonicPercentOfFundamental,
    required double shortCircuitMva,
    required double systemVoltageKv,
    double backgroundThdvPercent = 0,
  }) {
    final n = min(harmonicOrders.length, harmonicPercentOfFundamental.length);
    double sumI2 = 0;
    double thdv2 = backgroundThdvPercent * backgroundThdvPercent;
    for (int i = 0; i < n; i++) {
      final ih = fundamentalCurrentA * harmonicPercentOfFundamental[i] / 100;
      sumI2 += ih * ih;
      final order = max(2.0, harmonicOrders[i]);
      final impedanceOhm = systemVoltageKv <= 0 || shortCircuitMva <= 0
          ? 0
          : (systemVoltageKv * systemVoltageKv / shortCircuitMva) * order;
      final vhPercent = systemVoltageKv <= 0 ? 0 : 100 * ih * impedanceOhm / (systemVoltageKv * 1000 / sqrt(3));
      thdv2 += vhPercent * vhPercent;
    }
    final thdi = fundamentalCurrentA <= 0 ? 0 : 100 * sqrt(sumI2) / fundamentalCurrentA;
    return {'thdiPercent': thdi, 'thdvPercent': sqrt(thdv2)};
  }

  /// Returns a derating factor <= 1 above 1000 m.
  static double calcAltitudeDeratingFactor(double altitudeMeters) {
    if (altitudeMeters <= 1000) return 1;
    return max(.60, 1 - (altitudeMeters - 1000) * .00004);
  }
}

class EngineeringVerdict {
  final bool shortCircuitIcu, shortCircuitIcw, shortCircuitIp, selectivityMargin;
  final bool instantaneousCoordination;
  final bool cableThermal, cableAmpacity, cableVoltageDrop;
  final bool satDuctor, satSync;

  const EngineeringVerdict({
    required this.shortCircuitIcu,
    required this.shortCircuitIcw,
    required this.shortCircuitIp,
    required this.selectivityMargin,
    required this.instantaneousCoordination,
    required this.cableThermal,
    required this.cableAmpacity,
    required this.cableVoltageDrop,
    required this.satDuctor,
    required this.satSync,
  });

  bool get isReadyForCommissioning =>
      shortCircuitIcu &&
      shortCircuitIcw &&
      shortCircuitIp &&
      selectivityMargin &&
      instantaneousCoordination &&
      cableThermal &&
      cableAmpacity &&
      cableVoltageDrop &&
      satDuctor &&
      satSync;
}

class BreakerModel {
  final String name, vendor, medium, standardCode;
  final double defaultLimitMicroOhm, ratedBreakingIcuKa,
      serviceBreakingIcsKa, shortTimeWithstandIcwKa, peakMakingIpKa;
  final Color brandColor;

  const BreakerModel({
    required this.name,
    required this.vendor,
    required this.medium,
    required this.defaultLimitMicroOhm,
    required this.ratedBreakingIcuKa,
    required this.serviceBreakingIcsKa,
    required this.shortTimeWithstandIcwKa,
    required this.peakMakingIpKa,
    required this.standardCode,
    required this.brandColor,
  });
}

const breakers = <BreakerModel>[
  BreakerModel(name: 'Schneider Evolis (Vakum)', vendor: 'Schneider', medium: 'Vacuum',
      defaultLimitMicroOhm: 35, ratedBreakingIcuKa: 25, serviceBreakingIcsKa: 25,
      shortTimeWithstandIcwKa: 25, peakMakingIpKa: 65, standardCode: 'IEC 62271-100',
      brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Schneider FB4', vendor: 'Schneider', medium: 'SF6',
      defaultLimitMicroOhm: 32, ratedBreakingIcuKa: 40, serviceBreakingIcsKa: 40,
      shortTimeWithstandIcwKa: 40, peakMakingIpKa: 104, standardCode: 'IEC 62271 / IEEE C37',
      brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Schneider SF1 / SF2', vendor: 'Schneider', medium: 'SF6',
      defaultLimitMicroOhm: 38, ratedBreakingIcuKa: 25, serviceBreakingIcsKa: 25,
      shortTimeWithstandIcwKa: 25, peakMakingIpKa: 65, standardCode: 'IEC 62271-100',
      brandColor: Color(0xFF009639)),
  BreakerModel(name: 'Siemens SION 3AE / 3AH', vendor: 'Siemens', medium: 'Vacuum',
      defaultLimitMicroOhm: 45, ratedBreakingIcuKa: 31.5, serviceBreakingIcsKa: 31.5,
      shortTimeWithstandIcwKa: 31.5, peakMakingIpKa: 82, standardCode: 'IEC / DIN VDE',
      brandColor: Color(0xFF00646E)),
  BreakerModel(name: 'ABB VD4', vendor: 'ABB', medium: 'Vacuum',
      defaultLimitMicroOhm: 38, ratedBreakingIcuKa: 31.5, serviceBreakingIcsKa: 31.5,
      shortTimeWithstandIcwKa: 31.5, peakMakingIpKa: 82, standardCode: 'IEC 62271-100',
      brandColor: Color(0xFFFF000F)),
  BreakerModel(name: 'TEDAÅž Standart Vakum', vendor: 'Yerli/TEDAÅž', medium: 'Vacuum',
      defaultLimitMicroOhm: 50, ratedBreakingIcuKa: 16, serviceBreakingIcsKa: 16,
      shortTimeWithstandIcwKa: 16, peakMakingIpKa: 41.6, standardCode: 'TEDAÅž',
      brandColor: Color(0xFFFFB300)),
];

class SwitchgearModel {
  final String name, vendor, type, standard;
  final Color brandColor;
  const SwitchgearModel(this.name, this.vendor, this.type, this.standard, this.brandColor);
}

const switchgears = <SwitchgearModel>[
  SwitchgearModel('Schneider SM6-36', 'Schneider', 'AIS ModÃ¼ler', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Schneider AirSeT', 'Schneider', 'SF6-Free', 'IEC 62271-200', Color(0xFF00B050)),
  SwitchgearModel('Schneider GHA', 'Schneider', 'GIS', 'IEC 62271-200', Color(0xFF009639)),
  SwitchgearModel('Siemens 8BT2 / NXAIR', 'Siemens', 'Metal-Clad', 'IEC 62271-200', Color(0xFF00646E)),
  SwitchgearModel('ABB UniGear ZS1', 'ABB', 'Metal-Clad', 'IEC 62271-200', Color(0xFFFF000F)),
  SwitchgearModel('Ulusoy HMH-36 / Astor', 'TEDAÅž', 'ModÃ¼ler HÃ¼cre', 'TEDAÅž', Color(0xFFFFB300)),
];

class TestRecord {
  final String timestamp, substation, breaker;
  final double maxRes, syncDelta;
  final bool passed;

  const TestRecord({
    required this.timestamp, required this.substation, required this.breaker,
    required this.maxRes, required this.syncDelta, required this.passed,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp, 'substation': substation, 'breaker': breaker,
    'maxRes': maxRes, 'syncDelta': syncDelta, 'passed': passed,
  };

  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(
    timestamp: j['timestamp'] as String? ?? '',
    substation: j['substation'] as String? ?? '',
    breaker: j['breaker'] as String? ?? '',
    maxRes: (j['maxRes'] as num?)?.toDouble() ?? 0,
    syncDelta: (j['syncDelta'] as num?)?.toDouble() ?? 0,
    passed: j['passed'] as bool? ?? false,
  );
}

class SwitchgearCell {
  String id, name, ctRatio, currentVendor, currentBreaker;
  CellType type;
  bool cbClosed;

  SwitchgearCell({
    required this.id, required this.name, required this.type,
    this.cbClosed = false, this.ctRatio = '400/5A',
    this.currentVendor = 'Schneider', this.currentBreaker = 'Evolis',
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'type': type.name, 'cbClosed': cbClosed,
    'ctRatio': ctRatio, 'currentVendor': currentVendor, 'currentBreaker': currentBreaker,
  };

  factory SwitchgearCell.fromJson(Map<String, dynamic> j) => SwitchgearCell(
    id: j['id'] as String? ?? 'C',
    name: j['name'] as String? ?? 'Cell',
    type: CellType.values.firstWhere(
      (e) => e.name == j['type'], orElse: () => CellType.feeder),
    cbClosed: j['cbClosed'] as bool? ?? false,
    ctRatio: j['ctRatio'] as String? ?? '400/5A',
    currentVendor: j['currentVendor'] as String? ?? 'Schneider',
    currentBreaker: j['currentBreaker'] as String? ?? 'Evolis',
  );
}

class ProjectModel {
  String name;
  PowerDomain domain;
  SubArchetype archetype;
  double voltageKv, trafoMva, ukPercent, gridSscMva;
  int switchgearIndex, breakerIndex;
  double ctPri, ctSec;
  double upSettingSecA, upTms, downSettingSecA, downTms;
  TripCurve upCurve, downCurve;
  ProtectionStandard protectionStandard;
  bool up50Enabled, down50Enabled;
  double up50PickupA, down50PickupA;
  List<RelayType> relayTypes;
  double loadFlowMw, loadFlowPf, harmonicBackgroundThdv;
  double harmonicH3Pct, harmonicH5Pct, harmonicH7Pct, harmonicH11Pct;

  // Project-specific physical parameters.
  double generatorMw, inertiaH, powerMismatchMw;
  double motorKw, compensationKvar;
  double hospitalRisoKOhm, airportCcrAmps;
  double lineLengthKm, lineROhmPerKm, lineXOhmPerKm;
  double sf6MeasuredMpa, ambientTempC, altitudeMeters;

  double resR, resS, resT, timeR, timeS, timeT;
  double cableLengthM, loadCurrentA, cableSectionMm2;
  bool isCopper;
  double cableGroupingFactor, cableInstallationFactor, cablePowerFactor;

  List<TestRecord> testHistory;
  List<SwitchgearCell> cells;

  ProjectModel({
    required this.name, required this.domain, required this.archetype,
    required this.voltageKv, required this.trafoMva, required this.ukPercent,
    required this.gridSscMva, required this.testHistory, required this.cells,
    this.switchgearIndex = 0, this.breakerIndex = 0,
    this.ctPri = 400, this.ctSec = 5,
    this.upSettingSecA = 7.5, this.upTms = .25,
    this.upCurve = TripCurve.standardInverse,
    this.downSettingSecA = 3.125, this.downTms = .15,
    this.downCurve = TripCurve.standardInverse,
    this.protectionStandard = ProtectionStandard.iec60255,
    this.up50Enabled = true, this.up50PickupA = 3000,
    this.down50Enabled = true, this.down50PickupA = 1500,
    this.relayTypes = const [RelayType.overcurrent50_51, RelayType.earthFault50N_51N],
    this.loadFlowMw = 5, this.loadFlowPf = .90, this.harmonicBackgroundThdv = 1.5,
    this.harmonicH3Pct = 8, this.harmonicH5Pct = 18, this.harmonicH7Pct = 7, this.harmonicH11Pct = 3,
    this.generatorMw = 20, this.inertiaH = 3.5, this.powerMismatchMw = 3,
    this.motorKw = 400, this.compensationKvar = 600,
    this.hospitalRisoKOhm = 85, this.airportCcrAmps = 6.6,
    this.lineLengthKm = 42, this.lineROhmPerKm = .08, this.lineXOhmPerKm = .30,
    this.sf6MeasuredMpa = .61, this.ambientTempC = 28, this.altitudeMeters = 50,
    this.resR = 33.2, this.resS = 34.8, this.resT = 33.9,
    this.timeR = 41.5, this.timeS = 42.8, this.timeT = 42.1,
    this.cableLengthM = 220, this.loadCurrentA = 110, this.cableSectionMm2 = 70,
    this.isCopper = true, this.cableGroupingFactor = .85,
    this.cableInstallationFactor = 1, this.cablePowerFactor = .85,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'domain': domain.name, 'archetype': archetype.name,
    'voltageKv': voltageKv, 'trafoMva': trafoMva, 'ukPercent': ukPercent,
    'gridSscMva': gridSscMva, 'switchgearIndex': switchgearIndex,
    'breakerIndex': breakerIndex, 'ctPri': ctPri, 'ctSec': ctSec,
    'upSettingSecA': upSettingSecA, 'upTms': upTms, 'upCurve': upCurve.name,
    'downSettingSecA': downSettingSecA, 'downTms': downTms, 'downCurve': downCurve.name,
    'protectionStandard': protectionStandard.name, 'up50Enabled': up50Enabled,
    'up50PickupA': up50PickupA, 'down50Enabled': down50Enabled,
    'down50PickupA': down50PickupA,
    'relayTypes': relayTypes.map((e) => e.name).toList(),
    'loadFlowMw': loadFlowMw, 'loadFlowPf': loadFlowPf, 'harmonicBackgroundThdv': harmonicBackgroundThdv,
    'harmonicH3Pct': harmonicH3Pct, 'harmonicH5Pct': harmonicH5Pct, 'harmonicH7Pct': harmonicH7Pct, 'harmonicH11Pct': harmonicH11Pct,
    'generatorMw': generatorMw,
    'inertiaH': inertiaH, 'powerMismatchMw': powerMismatchMw, 'motorKw': motorKw,
    'compensationKvar': compensationKvar, 'hospitalRisoKOhm': hospitalRisoKOhm,
    'airportCcrAmps': airportCcrAmps, 'lineLengthKm': lineLengthKm,
    'lineROhmPerKm': lineROhmPerKm, 'lineXOhmPerKm': lineXOhmPerKm,
    'sf6MeasuredMpa': sf6MeasuredMpa, 'ambientTempC': ambientTempC,
    'altitudeMeters': altitudeMeters, 'resR': resR, 'resS': resS, 'resT': resT,
    'timeR': timeR, 'timeS': timeS, 'timeT': timeT, 'cableLengthM': cableLengthM,
    'loadCurrentA': loadCurrentA, 'cableSectionMm2': cableSectionMm2,
    'isCopper': isCopper, 'cableGroupingFactor': cableGroupingFactor,
    'cableInstallationFactor': cableInstallationFactor, 'cablePowerFactor': cablePowerFactor,
    'testHistory': testHistory.map((e) => e.toJson()).toList(),
    'cells': cells.map((e) => e.toJson()).toList(),
  };

  factory ProjectModel.fromJson(Map<String, dynamic> j) => ProjectModel(
    name: j['name'] as String? ?? 'Project',
    domain: PowerDomain.values.firstWhere((e) => e.name == j['domain'], orElse: () => PowerDomain.distribution),
    archetype: SubArchetype.values.firstWhere((e) => e.name == j['archetype'], orElse: () => SubArchetype.standardSubstation),
    voltageKv: (j['voltageKv'] as num?)?.toDouble() ?? 34.5,
    trafoMva: (j['trafoMva'] as num?)?.toDouble() ?? 2.5,
    ukPercent: (j['ukPercent'] as num?)?.toDouble() ?? 6,
    gridSscMva: (j['gridSscMva'] as num?)?.toDouble() ?? 1000,
    switchgearIndex: (j['switchgearIndex'] as num?)?.toInt() ?? 0,
    breakerIndex: (j['breakerIndex'] as num?)?.toInt() ?? 0,
    ctPri: (j['ctPri'] as num?)?.toDouble() ?? 400,
    ctSec: (j['ctSec'] as num?)?.toDouble() ?? 5,
    upSettingSecA: (j['upSettingSecA'] as num?)?.toDouble() ?? 7.5,
    upTms: (j['upTms'] as num?)?.toDouble() ?? .25,
    upCurve: TripCurve.values.firstWhere((e) => e.name == j['upCurve'], orElse: () => TripCurve.standardInverse),
    downSettingSecA: (j['downSettingSecA'] as num?)?.toDouble() ?? 3.125,
    downTms: (j['downTms'] as num?)?.toDouble() ?? .15,
    downCurve: TripCurve.values.firstWhere((e) => e.name == j['downCurve'], orElse: () => TripCurve.standardInverse),
    protectionStandard: ProtectionStandard.values.firstWhere((e) => e.name == j['protectionStandard'], orElse: () => ProtectionStandard.iec60255),
    up50Enabled: j['up50Enabled'] as bool? ?? true,
    up50PickupA: (j['up50PickupA'] as num?)?.toDouble() ?? 3000,
    down50Enabled: j['down50Enabled'] as bool? ?? true,
    down50PickupA: (j['down50PickupA'] as num?)?.toDouble() ?? 1500,
    relayTypes: ((j['relayTypes'] as List?) ?? ['overcurrent50_51', 'earthFault50N_51N']).map((e) => RelayType.values.firstWhere((r) => r.name == e, orElse: () => RelayType.overcurrent50_51)).toSet().toList(),
    loadFlowMw: (j['loadFlowMw'] as num?)?.toDouble() ?? 5,
    loadFlowPf: (j['loadFlowPf'] as num?)?.toDouble() ?? .90,
    harmonicBackgroundThdv: (j['harmonicBackgroundThdv'] as num?)?.toDouble() ?? 1.5,
    harmonicH3Pct: (j['harmonicH3Pct'] as num?)?.toDouble() ?? 8,
    harmonicH5Pct: (j['harmonicH5Pct'] as num?)?.toDouble() ?? 18,
    harmonicH7Pct: (j['harmonicH7Pct'] as num?)?.toDouble() ?? 7,
    harmonicH11Pct: (j['harmonicH11Pct'] as num?)?.toDouble() ?? 3,
    generatorMw: (j['generatorMw'] as num?)?.toDouble() ?? 20,
    inertiaH: (j['inertiaH'] as num?)?.toDouble() ?? 3.5,
    powerMismatchMw: (j['powerMismatchMw'] as num?)?.toDouble() ?? 3,
    motorKw: (j['motorKw'] as num?)?.toDouble() ?? 400,
    compensationKvar: (j['compensationKvar'] as num?)?.toDouble() ?? 600,
    hospitalRisoKOhm: (j['hospitalRisoKOhm'] as num?)?.toDouble() ?? 85,
    airportCcrAmps: (j['airportCcrAmps'] as num?)?.toDouble() ?? 6.6,
    lineLengthKm: (j['lineLengthKm'] as num?)?.toDouble() ?? 42,
    lineROhmPerKm: (j['lineROhmPerKm'] as num?)?.toDouble() ?? .08,
    lineXOhmPerKm: (j['lineXOhmPerKm'] as num?)?.toDouble() ?? .30,
    sf6MeasuredMpa: (j['sf6MeasuredMpa'] as num?)?.toDouble() ?? .61,
    ambientTempC: (j['ambientTempC'] as num?)?.toDouble() ?? 28,
    altitudeMeters: (j['altitudeMeters'] as num?)?.toDouble() ?? 50,
    resR: (j['resR'] as num?)?.toDouble() ?? 33.2,
    resS: (j['resS'] as num?)?.toDouble() ?? 34.8,
    resT: (j['resT'] as num?)?.toDouble() ?? 33.9,
    timeR: (j['timeR'] as num?)?.toDouble() ?? 41.5,
    timeS: (j['timeS'] as num?)?.toDouble() ?? 42.8,
    timeT: (j['timeT'] as num?)?.toDouble() ?? 42.1,
    cableLengthM: (j['cableLengthM'] as num?)?.toDouble() ?? 220,
    loadCurrentA: (j['loadCurrentA'] as num?)?.toDouble() ?? 110,
    cableSectionMm2: (j['cableSectionMm2'] as num?)?.toDouble() ?? 70,
    isCopper: j['isCopper'] as bool? ?? true,
    cableGroupingFactor: (j['cableGroupingFactor'] as num?)?.toDouble() ?? .85,
    cableInstallationFactor: (j['cableInstallationFactor'] as num?)?.toDouble() ?? 1,
    cablePowerFactor: (j['cablePowerFactor'] as num?)?.toDouble() ?? .85,
    testHistory: ((j['testHistory'] as List?) ?? []).map((e) => TestRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    cells: ((j['cells'] as List?) ?? []).map((e) => SwitchgearCell.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
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

  String tr(String trText, String enText) => language == AppLanguage.tr ? trText : enText;

  ProjectModel get p => projects[activeProject];
  int _safeIndex(int value, int length) => value < 0 ? 0 : (value >= length ? length - 1 : value);
  BreakerModel get breaker => breakers[_safeIndex(p.breakerIndex, breakers.length)];
  SwitchgearModel get switchgear => switchgears[_safeIndex(p.switchgearIndex, switchgears.length)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    projects = [
      ProjectModel(
        name: 'AliaÄŸa OSB DaÄŸÄ±tÄ±m TM-1',
        domain: PowerDomain.distribution,
        archetype: SubArchetype.heavyIndustry,
        voltageKv: 34.5, trafoMva: 2.5, ukPercent: 6, gridSscMva: 1000,
        switchgearIndex: 0, breakerIndex: 0,
        testHistory: const [
          TestRecord(timestamp: '12/03/2025', substation: 'AliaÄŸa OSB TM-1', breaker: 'Schneider Evolis', maxRes: 31.4, syncDelta: 1.2, passed: true),
        ],
        cells: _cells('Schneider', 'Schneider Evolis (Vakum)'),
      ),
      ProjectModel(
        name: 'TorbalÄ± GES 15 MW',
        domain: PowerDomain.generation,
        archetype: SubArchetype.solarGES,
        voltageKv: 34.5, trafoMva: 16, ukPercent: 6.5, gridSscMva: 750,
        switchgearIndex: 2, breakerIndex: 2,
        testHistory: const [],
        cells: _cells('Schneider', 'Schneider SF1 / SF2'),
      ),
      ProjectModel(
        name: 'Menemen 154 kV TM',
        domain: PowerDomain.transmission,
        archetype: SubArchetype.hvSubstation154,
        voltageKv: 154, trafoMva: 50, ukPercent: 12, gridSscMva: 2500,
        switchgearIndex: 3, breakerIndex: 3,
        testHistory: const [],
        cells: _cells('Siemens', 'Siemens SION 3AE / 3AH'),
      ),
    ];
    _loadPreferencesAndProjects();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistProjects();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _persistProjects();
    }
  }

  static List<SwitchgearCell> _cells(String vendor, String breaker) => [
    SwitchgearCell(id: 'C1', name: 'H01 Incomer', type: CellType.incomer, cbClosed: true, currentVendor: vendor, currentBreaker: breaker),
    SwitchgearCell(id: 'C2', name: 'H02 VT Meter', type: CellType.vtMetering, cbClosed: true, currentVendor: vendor, currentBreaker: 'VT'),
    SwitchgearCell(id: 'C3', name: 'H03 Bus Coupler', type: CellType.coupler, currentVendor: vendor, currentBreaker: breaker),
    SwitchgearCell(id: 'C4', name: 'H04 Feeder 1', type: CellType.feeder, cbClosed: true, ctRatio: '200/5A', currentVendor: vendor, currentBreaker: breaker),
    SwitchgearCell(id: 'C5', name: 'H05 Feeder 2', type: CellType.feeder, cbClosed: true, ctRatio: '200/5A', currentVendor: vendor, currentBreaker: breaker),
  ];

  Map<String, double> get fault => ElectricalEngine.calcIec60909FaultCurrents(
    voltageKv: p.voltageKv, trafoMva: p.trafoMva, ukPercent: p.ukPercent,
    gridSscMva: p.gridSscMva,
  );

  double get ikMax => fault['Ik_max'] ?? 0;
  double get ipPeak => fault['Ip_peak'] ?? 0;

  double primary(double secondary) => ElectricalEngine.calcPrimaryPickupAmps(
    ctPrimaryA: p.ctPri, ctSecondaryA: p.ctSec, secondarySettingA: secondary);

  double trip(double faultA, double pickup, double tms, TripCurve curve) =>
      ElectricalEngine.calcTripTime(
        faultA: faultA, iPickupA: pickup, tmsVal: tms,
        curve: curve, standard: p.protectionStandard);

  /// Sweep coordination across a fault-current range and return the minimum finite margin.
  double get selectivityMarginSec {
    final start = max(1.05 * min(primary(p.downSettingSecA), primary(p.upSettingSecA)), 10);
    final end = max(ikMax * 1000, start * 1.01);
    double minMargin = double.infinity;

    for (int n = 0; n <= 160; n++) {
      final ratio = n / 160;
      final current = start * pow(end / start, ratio);
      final tu = trip(current, primary(p.upSettingSecA), p.upTms, p.upCurve);
      final td = trip(current, primary(p.downSettingSecA), p.downTms, p.downCurve);
      if (tu.isFinite && td.isFinite) {
        minMargin = min(minMargin, tu - td);
      }
    }
    return minMargin.isFinite ? minMargin : double.negativeInfinity;
  }

  bool get instantaneousCoordination {
    if (!p.down50Enabled) return true;
    if (!p.up50Enabled) return p.down50PickupA >= ikMax * 1000;
    // Downstream instantaneous must not operate before upstream at the same fault.
    return p.down50PickupA < p.up50PickupA &&
        p.up50PickupA >= ikMax * 1000;
  }

  Map<String, double> get loadFlow => ElectricalEngine.calcLoadFlow(
    voltageKv: p.voltageKv, activePowerMw: p.loadFlowMw, powerFactor: p.loadFlowPf,
    lineLengthKm: p.lineLengthKm, rOhmPerKm: p.lineROhmPerKm, xOhmPerKm: p.lineXOhmPerKm,
    sourceSscMva: p.gridSscMva,
  );

  Map<String, double> get harmonics => ElectricalEngine.calcHarmonics(
    fundamentalCurrentA: p.loadCurrentA,
    harmonicOrders: const [3.0, 5.0, 7.0, 11.0],
    harmonicPercentOfFundamental: [p.harmonicH3Pct, p.harmonicH5Pct, p.harmonicH7Pct, p.harmonicH11Pct],
    shortCircuitMva: p.gridSscMva,
    systemVoltageKv: p.voltageKv,
    backgroundThdvPercent: p.harmonicBackgroundThdv,
  );

  Map<String, dynamic> get cable => ElectricalEngine.evaluateCableSizing(
    sectionMm2: p.cableSectionMm2, lengthM: p.cableLengthM,
    loadCurrentA: p.loadCurrentA, voltageKv: p.voltageKv, ikKa: ikMax,
    faultTimeSec: .15, isCopper: p.isCopper, ambientTempC: p.ambientTempC,
    groupingFactor: p.cableGroupingFactor,
    installationFactor: p.cableInstallationFactor,
    powerFactor: p.cablePowerFactor,
  );

  EngineeringVerdict get verdict {
    final satMax = max(p.resR, max(p.resS, p.resT));
    final sync = max((p.timeR-p.timeS).abs(), max((p.timeS-p.timeT).abs(), (p.timeR-p.timeT).abs()));

    return EngineeringVerdict(
      shortCircuitIcu: ikMax <= breaker.ratedBreakingIcuKa,
      shortCircuitIcw: ikMax <= breaker.shortTimeWithstandIcwKa,
      shortCircuitIp: ipPeak <= breaker.peakMakingIpKa,
      selectivityMargin: selectivityMarginSec >= .30,
      instantaneousCoordination: instantaneousCoordination,
      cableThermal: cable['isThermalOk'] as bool,
      cableAmpacity: cable['isAmpacityOk'] as bool,
      cableVoltageDrop: cable['isVoltageDropOk'] as bool,
      satDuctor: satMax <= breaker.defaultLimitMicroOhm,
      satSync: sync <= 3,
    );
  }

  Future<void> _persistProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(projects.map((e) => e.toJson()).toList());
      await prefs.setString('powerfield_projects_v67', json);
    } catch (_) {
      // Persistence must never block the engineering UI.
    }
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
      if (!selected && mounted && !_modeDialogShown) {
        _modeDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showModeChooser());
      }
    } catch (_) {
      await _loadSavedProjects();
    }
  }

  Future<void> _setAppMode(AppMode mode) async {
    setState(() {
      appMode = mode;
      activeTab = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('powerfield_app_mode_v67', mode.name);
    await prefs.setBool('powerfield_mode_selected_v67', true);
  }

  void _showModeChooser() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('POWERFIELD PRO'),
        content: const Text('Ã‡alÄ±ÅŸma seviyesini seÃ§in. Profesyonel mod ayrÄ±ntÄ±lÄ± mÃ¼hendislik kontrollerini ve analiz sekmelerini aÃ§ar.'),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _setAppMode(AppMode.basic); },
            child: const Text('TEMEL'),
          ),
          FilledButton(
            onPressed: () { Navigator.pop(context); _setAppMode(AppMode.professional); },
            child: const Text('PROFESYONEL'),
          ),
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
      final loaded = decoded
          .map((e) => ProjectModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loaded.isNotEmpty && mounted) {
        setState(() {
          projects = loaded;
          activeProject = 0;
        });
      }
    } catch (_) {
      // Keep built-in demo projects if stored data is invalid.
    } finally {
      _loadingSavedProjects = false;
    }
  }

  void saveJson() {
    final json = const JsonEncoder.withIndent('  ')
        .convert(projects.map((e) => e.toJson()).toList());
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Proje JSON verisi panoya kopyalandÄ±.', 'Project JSON copied to clipboard.'))),
    );
  }

  double? get satResistanceTrendPercent {
    if (p.testHistory.length < 2) return null;
    final latest = p.testHistory[0].maxRes;
    final previous = p.testHistory[1].maxRes;
    if (previous == 0) return null;
    return ((latest - previous) / previous) * 100;
  }

  void addSatRecord() {
    final maxRes = max(p.resR, max(p.resS, p.resT));
    final sync = max((p.timeR-p.timeS).abs(), max((p.timeS-p.timeT).abs(), (p.timeR-p.timeT).abs()));
    setState(() => p.testHistory.insert(0, TestRecord(
      timestamp: DateTime.now().toIso8601String().substring(0, 10),
      substation: p.name, breaker: breaker.name,
      maxRes: maxRes, syncDelta: sync,
      passed: verdict.satDuctor && verdict.satSync,
    )));
    _persistProjects();
  }

  Future<void> importJsonFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('JSON root must be a list');
      final loaded = decoded
          .map((e) => ProjectModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loaded.isEmpty) throw const FormatException('No projects');
      setState(() { projects = loaded; activeProject = 0; });
      await _persistProjects();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Projeler iÃ§e aktarÄ±ldÄ±.', 'Projects imported.'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('GeÃ§ersiz proje JSON'u.', 'Invalid project JSON.'))));
    }
  }

  void addProject() {
    setState(() {
      projects.add(ProjectModel(
        name: '${tr('Yeni Proje', 'New Project')} ${projects.length + 1}',
        domain: PowerDomain.distribution, archetype: SubArchetype.standardSubstation,
        voltageKv: 34.5, trafoMva: 2.5, ukPercent: 6, gridSscMva: 1000,
        testHistory: [], cells: _cells('Schneider', 'Schneider Evolis (Vakum)'),
      ));
      activeProject = projects.length - 1;
    });
    _persistProjects();
  }

  void deleteActiveProject() {
    if (projects.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('En az bir proje kalmalÄ±.', 'At least one project must remain.'))));
      return;
    }
    final removed = p.name;
    setState(() {
      projects.removeAt(activeProject);
      activeProject = _safeIndex(activeProject, projects.length);
    });
    _persistProjects();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$removed ${tr('silindi.', 'deleted.')}')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('POWERFIELD PRO v6.7',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: switchgear.brandColor)),
      actions: [
        IconButton(onPressed: saveJson, icon: const Icon(Icons.save_alt), tooltip: 'JSON'),
      ],
    ),
    body: Column(children: [
      _projectBar(),
      _verdictBar(),
      Expanded(child: _tab()),
    ]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: activeTab,
      onDestinationSelected: (i) => setState(() => activeTab = i),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard), label: tr('Kokpit', 'Cockpit')),
        if (appMode == AppMode.professional) ...[
          NavigationDestination(icon: const Icon(Icons.show_chart), label: tr('TCC / RÃ¶le', 'TCC / Relay')),
          NavigationDestination(icon: const Icon(Icons.account_tree), label: tr('YÃ¼k AkÄ±ÅŸÄ±', 'Load Flow')),
          NavigationDestination(icon: const Icon(Icons.graphic_eq), label: tr('Harmonik', 'Harmonics')),
          NavigationDestination(icon: const Icon(Icons.fact_check), label: 'SAT'),
          NavigationDestination(icon: const Icon(Icons.cable), label: tr('Kablo', 'Cable')),
          NavigationDestination(icon: const Icon(Icons.schema), label: 'SLD'),
        ],
      ],
    ),
  );

  void _applyEquipmentToCells() {
    final sw = switchgear;
    final br = breaker;
    for (final cell in p.cells) {
      cell.currentVendor = sw.vendor;
      if (cell.type != CellType.vtMetering) cell.currentBreaker = br.name;
    }
  }

  Widget _projectBar() => Container(
    padding: const EdgeInsets.all(7),
    color: const Color(0xFF090D14),
    child: Row(children: [
      Expanded(
        child: DropdownButton<int>(
          value: _safeIndex(activeProject, projects.length),
          isExpanded: true, underline: const SizedBox(),
          items: List.generate(projects.length, (i) => DropdownMenuItem(
            value: i, child: Text(projects[i].name, style: const TextStyle(fontSize: 11)))),
          onChanged: (i) { if (i != null) setState(() => activeProject = i); },
        ),
      ),
      IconButton(onPressed: addProject, icon: const Icon(Icons.add, size: 18), tooltip: tr('Yeni proje', 'New project')),
      IconButton(onPressed: deleteActiveProject, icon: const Icon(Icons.delete_outline, size: 18), tooltip: tr('Projeyi sil', 'Delete project')),
      PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'export') saveJson();
          if (v == 'import') importJsonFromClipboard();
          if (v == 'lang') setState(() => language = language == AppLanguage.tr ? AppLanguage.en : AppLanguage.tr);
          if (v == 'mode') _showModeChooser();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'export', child: Text(tr('JSON dÄ±ÅŸa aktar / panoya kopyala', 'Export JSON / copy to clipboard'))),
          PopupMenuItem(value: 'import', child: Text(tr('Panodan JSON iÃ§e aktar', 'Import JSON from clipboard'))),
          PopupMenuItem(value: 'lang', child: Text(language == AppLanguage.tr ? 'English' : 'TÃ¼rkÃ§e')),
          PopupMenuItem(value: 'mode', child: Text(tr('Ã‡alÄ±ÅŸma modu: ${appMode == AppMode.basic ? 'Temel' : 'Profesyonel'}', 'Mode: ${appMode == AppMode.basic ? 'Basic' : 'Professional'}'))),
        ],
      ),
      _domainChip('ÃœRETÄ°M', PowerDomain.generation),
      _domainChip('Ä°LETÄ°M', PowerDomain.transmission),
      _domainChip('DAÄžITIM', PowerDomain.distribution),
    ]),
  );

  Widget _domainChip(String label, PowerDomain domain) {
    final selected = p.domain == domain;
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 8)),
        backgroundColor: selected ? const Color(0xFFFFB300) : const Color(0xFF111622),
        labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
        onPressed: () {
          setState(() {
            p.domain = domain;
            // Prevent invalid equipment combinations when the engineering domain changes.
            if (domain == PowerDomain.generation) {
              p.archetype = SubArchetype.solarGES;
              p.voltageKv = 34.5;
              p.switchgearIndex = 1;
              p.breakerIndex = 1;
            }
            if (domain == PowerDomain.transmission) {
              p.archetype = SubArchetype.hvSubstation154;
              p.voltageKv = 154;
              p.switchgearIndex = 3;
              p.breakerIndex = 3;
            }
            if (domain == PowerDomain.distribution) {
              p.archetype = SubArchetype.osb;
              p.voltageKv = 34.5;
              p.switchgearIndex = 0;
              p.breakerIndex = 0;
            }
            _applyEquipmentToCells();
          });
          _persistProjects();
        },
      ),
    );
  }

  Widget _verdictBar() {
    final v = verdict;
    return Material(
      color: v.isReadyForCommissioning ? const Color(0xFF00A844) : const Color(0xFFB00020),
      child: InkWell(
        onTap: _showVerdict,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(v.isReadyForCommissioning
                  ? tr('DEVREYE ALMA Ã–N KONTROLÃœ: UYGUN', 'PRE-COMMISSIONING CHECK: PASS')
                  : tr('DEVREYE ALMA Ã–N KONTROLÃœ: UYGUN DEÄžÄ°L', 'PRE-COMMISSIONING CHECK: FAIL'),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              Text(tr('Detay â€º', 'Details â€º'), style: TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab() {
    if (appMode == AppMode.basic) return _cockpit();
    switch (activeTab) {
      case 0: return _cockpit();
      case 1: return _tcc();
      case 2: return _loadFlowTab();
      case 3: return _harmonicTab();
      case 4: return _sat();
      case 5: return _cable();
      case 6: return _sld();
      default: return const SizedBox();
    }
  }

  Widget _cockpit() => ListView(padding: const EdgeInsets.all(12), children: [
    _card(tr('Ã‡ALIÅžMA MODU', 'WORK MODE'), Row(children: [
      Expanded(child: ChoiceChip(label: Text(tr('Temel', 'Basic')), selected: appMode == AppMode.basic, onSelected: (_) => _setAppMode(AppMode.basic))),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(label: Text(tr('Profesyonel', 'Professional')), selected: appMode == AppMode.professional, onSelected: (_) => _setAppMode(AppMode.professional))),
    ])),
    _hud(tr('KISA DEVRE', 'SHORT-CIRCUIT'),
      '${ikMax.toStringAsFixed(2)} kA',
      "Ik''min ${(fault['Ik_min'] ?? 0).toStringAsFixed(2)} kA | Ip ${(ipPeak).toStringAsFixed(1)} kA | Îº ${(fault['kappa'] ?? 0).toStringAsFixed(2)}"),
    const SizedBox(height: 10),
    _card(tr('PROJE EKÄ°PMANI', 'PROJECT EQUIPMENT'), Column(children: [
      DropdownButtonFormField<int>(
        value: _safeIndex(p.switchgearIndex, switchgears.length),
        isExpanded: true,
        items: List.generate(switchgears.length, (i) => DropdownMenuItem(
          value: i, child: Text(switchgears[i].name, style: const TextStyle(fontSize: 11)))),
        onChanged: (v) { if (v == null) return; setState(() { p.switchgearIndex = v; _applyEquipmentToCells(); }); _persistProjects(); },
      ),
      DropdownButtonFormField<int>(
        value: _safeIndex(p.breakerIndex, breakers.length),
        isExpanded: true,
        items: List.generate(breakers.length, (i) => DropdownMenuItem(
          value: i, child: Text('${breakers[i].name} | Icu ${breakers[i].ratedBreakingIcuKa} kA',
            style: const TextStyle(fontSize: 10)))),
        onChanged: (v) { if (v == null) return; setState(() { p.breakerIndex = v; _applyEquipmentToCells(); }); _persistProjects(); },
      ),
    ])),
    _card(tr('PROJE ARKETÄ°PÄ°', 'PROJECT ARCHETYPE'), DropdownButtonFormField<SubArchetype>(
      value: p.archetype,
      isExpanded: true,
      items: SubArchetype.values.map((a) => DropdownMenuItem(value: a, child: Text(_archetypeName(a), style: const TextStyle(fontSize: 11)))).toList(),
      onChanged: (v) { if (v != null) setState(() => p.archetype = v); _persistProjects(); },
    )),
    _slider('System Voltage kV', p.voltageKv, .4, 380, (v) => p.voltageKv = v),
    _slider('Transformer / Plant MVA', p.trafoMva, .1, 250, (v) => p.trafoMva = v),
    _slider('%uk', p.ukPercent, 3, 18, (v) => p.ukPercent = v),
    _slider('Grid Ssc MVA', p.gridSscMva, 200, 5000, (v) => p.gridSscMva = v),
    _slider('Ambient Â°C', p.ambientTempC, -10, 70, (v) => p.ambientTempC = v),
    _slider('Altitude m', p.altitudeMeters, 0, 5000, (v) => p.altitudeMeters = v),
    _buildDynamicArchetypePanel(),
  ]);

  String _archetypeName(SubArchetype a) {
    switch (a) {
      case SubArchetype.solarGES: return 'GES â€¢ Solar';
      case SubArchetype.windRES: return 'RES â€¢ Wind';
      case SubArchetype.hydroHES: return 'HES â€¢ Hydro';
      case SubArchetype.thermalCoal: return 'KÃ¶mÃ¼r â€¢ Termik';
      case SubArchetype.biomass: return 'BiyokÃ¼tle Santrali';
      case SubArchetype.naturalGas: return 'DoÄŸalgaz Santrali';
      case SubArchetype.hvSubstation154: return '154 kV TM';
      case SubArchetype.hvGis380: return '380 kV GIS';
      case SubArchetype.hvSubstation400: return '400 kV TM';
      case SubArchetype.heavyIndustry: return 'AÄŸÄ±r Sanayi';
      case SubArchetype.factory: return 'Fabrika';
      case SubArchetype.osb: return 'OSB';
      case SubArchetype.hospital: return 'Hastane';
      case SubArchetype.airport: return 'HavalimanÄ±';
      case SubArchetype.commercialMall: return 'AVM';
      case SubArchetype.dataCenter: return 'Veri Merkezi';
      case SubArchetype.railway: return 'Demiryolu / Cer';
      case SubArchetype.waterTreatment: return 'Su / AtÄ±ksu Tesisi';
      case SubArchetype.standardSubstation: return 'Standart TM';
    }
  }

  Widget _buildDynamicArchetypePanel() {
    switch (p.archetype) {
      case SubArchetype.hospital:
        return _card(tr('HASTANE â€¢ RISO', 'HOSPITAL â€¢ RISO'), Column(children: [
          _slider('Ä°zolasyon direnci kÎ©', p.hospitalRisoKOhm, 10, 500, (v) => p.hospitalRisoKOhm = v),
          _row('Riso Ã¶n kontrol', '${p.hospitalRisoKOhm.toStringAsFixed(1)} kÎ©', p.hospitalRisoKOhm >= 100),
          const Text('Ã–n kontrol eÅŸiÄŸi: 100 kÎ©. TÄ±bbi IT sistemleri iÃ§in proje/standart doÄŸrulamasÄ± ayrÄ±ca yapÄ±lmalÄ±dÄ±r.', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ]));
      case SubArchetype.airport:
        return _card(tr('HAVALÄ°MANI â€¢ CCR', 'AIRPORT â€¢ CCR'), Column(children: [
          _slider('CCR akÄ±mÄ± A', p.airportCcrAmps, 1, 20, (v) => p.airportCcrAmps = v),
          _row('CCR nominal Ã¶n kontrol', '${p.airportCcrAmps.toStringAsFixed(2)} A', p.airportCcrAmps > 0),
          const Text('CCR/AGL uyumluluÄŸu Ã¼retici ve havacÄ±lÄ±k standartlarÄ±na gÃ¶re ayrÄ±ca doÄŸrulanmalÄ±dÄ±r.', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ]));
      case SubArchetype.commercialMall:
        return _card(tr('AVM â€¢ YANGIN POMPASI', 'MALL â€¢ FIRE PUMP'), Column(children: [
          SwitchListTile(dense: true, title: const Text('51 bypass', style: TextStyle(fontSize: 11)), value: p.down50Enabled, onChanged: (v) => setState(() => p.down50Enabled = v)),
          _row('YangÄ±n pompasÄ± 51 durumu', p.down50Enabled ? 'AKTÄ°F' : 'BYPASS', !p.down50Enabled),
          const Text('YangÄ±n pompasÄ± koruma mantÄ±ÄŸÄ± NFPA 20/proje felsefesi ile ayrÄ±ca doÄŸrulanmalÄ±dÄ±r.', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ]));
      case SubArchetype.solarGES:
      case SubArchetype.windRES:
      case SubArchetype.hydroHES:
      case SubArchetype.thermalCoal:
      case SubArchetype.biomass:
      case SubArchetype.naturalGas:
        final rocof = ElectricalEngine.calcRocofHzSec(deltaP_Mw: p.powerMismatchMw, generatorMw: p.generatorMw, inertiaH_Sec: p.inertiaH);
        return _card('${p.archetype == SubArchetype.windRES ? 'RES' : 'ÃœRETÄ°M'} â€¢ FREKANS', Column(children: [
          _slider('Generator MW', p.generatorMw, 1, 500, (v) => p.generatorMw = v),
          _slider('Inertia H s', p.inertiaH, .5, 10, (v) => p.inertiaH = v),
          _slider('Power mismatch MW', p.powerMismatchMw, .1, 100, (v) => p.powerMismatchMw = v),
          _row('ROCOF', '${rocof.toStringAsFixed(2)} Hz/s', rocof <= 1),
        ]));
      case SubArchetype.heavyIndustry:
      case SubArchetype.factory:
      case SubArchetype.osb:
      case SubArchetype.dataCenter:
      case SubArchetype.railway:
      case SubArchetype.waterTreatment:
        final dip = ElectricalEngine.calcMotorStartVoltageDipPercent(motorKw: p.motorKw, sscMva: p.gridSscMva);
        final resonance = ElectricalEngine.calcResonanceOrder(p.gridSscMva, p.compensationKvar);
        return _card(tr('SANAYÄ° â€¢ MOTOR / REZONANS', 'INDUSTRY â€¢ MOTOR / RESONANCE'), Column(children: [
          _slider('Motor kW', p.motorKw, 10, 5000, (v) => p.motorKw = v),
          _slider('Kompanzasyon kvar', p.compensationKvar, 0, 5000, (v) => p.compensationKvar = v),
          _row('Motor kalkÄ±ÅŸ gerilim Ã§Ã¶kmesi', '${dip.toStringAsFixed(1)} %', dip <= 10),
          _row('Paralel rezonans mertebesi', resonance.isFinite ? resonance.toStringAsFixed(2) : 'â€”', resonance >= 3 && resonance <= 15),
        ]));
      case SubArchetype.hvSubstation154:
      case SubArchetype.hvGis380:
      case SubArchetype.hvSubstation400:
      case SubArchetype.standardSubstation:
        final zones = ElectricalEngine.calcDistanceZones(lineLengthKm: p.lineLengthKm, rOhmPerKm: p.lineROhmPerKm, xOhmPerKm: p.lineXOhmPerKm);
        final sf6 = ElectricalEngine.calcCompensatedSf6Pressure(measuredPressureMpa: p.sf6MeasuredMpa, ambientTempC: p.ambientTempC);
        return _card(tr('TM â€¢ HAT / SF6', 'SUBSTATION â€¢ LINE / SF6'), Column(children: [
          _slider('Hat uzunluÄŸu km', p.lineLengthKm, 1, 300, (v) => p.lineLengthKm = v),
          _slider('R Î©/km', p.lineROhmPerKm, .001, 1, (v) => p.lineROhmPerKm = v),
          _slider('X Î©/km', p.lineXOhmPerKm, .001, 2, (v) => p.lineXOhmPerKm = v),
          _slider('SF6 Ã¶lÃ§Ã¼len MPa', p.sf6MeasuredMpa, .1, 1, (v) => p.sf6MeasuredMpa = v),
          _row('Zone 1', '${zones['Zone1']!.toStringAsFixed(2)} Î©', true),
          _row('SF6 sÄ±caklÄ±k komp.', '${sf6.toStringAsFixed(3)} MPa', true),
          const Text('SF6 deÄŸeri basÄ±nÃ§ sÄ±caklÄ±k kompanzasyonudur; gerÃ§ek density/switchgear alarm teÅŸhisi yerine geÃ§mez.', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ]));
    }
  }

  Widget _loadFlowTab() => ListView(padding: const EdgeInsets.all(12), children: [
    _hud('LOAD FLOW', '${loadFlow['receivingKv']!.toStringAsFixed(2)} kV',
      '${p.loadFlowMw.toStringAsFixed(2)} MW | PF ${p.loadFlowPf.toStringAsFixed(2)} | Î”U ${loadFlow['dropPercent']!.toStringAsFixed(2)}%'),
    _card(tr('GÃœÃ‡ AKIÅžI / GÃœÃ‡ AKIÅžI', 'POWER FLOW'), Column(children: [
      _slider('Aktif gÃ¼Ã§ MW', p.loadFlowMw, 0, 500, (v) => p.loadFlowMw = v),
      _slider('Power factor', p.loadFlowPf, .5, 1, (v) => p.loadFlowPf = v),
      _row('Hat akÄ±mÄ±', '${loadFlow['currentA']!.toStringAsFixed(1)} A', loadFlow['currentA']!.isFinite),
      _row('Reaktif gÃ¼Ã§ Q', '${loadFlow['qMvar']!.toStringAsFixed(2)} MVAr', true),
      _row('AlÄ±cÄ± uÃ§ gerilimi', '${loadFlow['receivingKv']!.toStringAsFixed(2)} kV', loadFlow['receivingKv']! >= p.voltageKv * .90),
      _row('Gerilim dÃ¼ÅŸÃ¼mÃ¼', '${loadFlow['dropPercent']!.toStringAsFixed(2)} %', loadFlow['dropPercent']! <= 5),
      _row('Hat IÂ²R kaybÄ±', '${loadFlow['lossMw']!.toStringAsFixed(3)} MW', loadFlow['lossMw']! <= p.loadFlowMw * .05),
    ])),
    const Text('Bu tek-hatlÄ± Ã¶n yÃ¼k akÄ±ÅŸÄ±; Ã§ok baralÄ± Newton-Raphson/BFS ÅŸebeke Ã§Ã¶zÃ¼mÃ¼nÃ¼n yerine geÃ§mez.', style: TextStyle(fontSize: 9, color: Colors.grey)),
  ]);

  Widget _harmonicTab() => ListView(padding: const EdgeInsets.all(12), children: [
    _hud('HARMONIC STUDY', 'THDi ${harmonics['thdiPercent']!.toStringAsFixed(2)} %',
      'THDv ${harmonics['thdvPercent']!.toStringAsFixed(2)} % | I1 ${p.loadCurrentA.toStringAsFixed(0)} A'),
    _card(tr('HARMONÄ°K AKIM SPEKTRUMU', 'HARMONIC CURRENT SPECTRUM'), Column(children: [
      _slider('Fundamental I1 A', p.loadCurrentA, 1, 2000, (v) => p.loadCurrentA = v),
      _slider('H3 % I1', p.harmonicH3Pct, 0, 30, (v) => p.harmonicH3Pct = v),
      _slider('H5 % I1', p.harmonicH5Pct, 0, 50, (v) => p.harmonicH5Pct = v),
      _slider('H7 % I1', p.harmonicH7Pct, 0, 30, (v) => p.harmonicH7Pct = v),
      _slider('H11 % I1', p.harmonicH11Pct, 0, 20, (v) => p.harmonicH11Pct = v),
      _slider('Background THDv %', p.harmonicBackgroundThdv, 0, 10, (v) => p.harmonicBackgroundThdv = v),
    ])),
    _row('THDi', '${harmonics['thdiPercent']!.toStringAsFixed(2)} %', harmonics['thdiPercent']! <= 20),
    _row('THDv', '${harmonics['thdvPercent']!.toStringAsFixed(2)} %', harmonics['thdvPercent']! <= 5),
    const Text('Harmonik sonuÃ§larÄ± Ã¶n tarama modelidir; gerÃ§ek rezonans/frekans empedansÄ±, PCC ve standart limitleri iÃ§in tam ÅŸebeke/frekans taramasÄ± gerekir.', style: TextStyle(fontSize: 9, color: Colors.grey)),
  ]);

  String _relayName(RelayType r) {
    switch (r) {
      case RelayType.overcurrent50_51: return '50/51 Overcurrent';
      case RelayType.earthFault50N_51N: return '50N/51N Earth Fault';
      case RelayType.directional67: return '67 Directional';
      case RelayType.distance21: return '21 Distance';
      case RelayType.transformerDifferential87T: return '87T Trafo Diff.';
      case RelayType.restrictedEarthFault87N: return '87N REF';
      case RelayType.voltage27_59: return '27/59 Voltage';
      case RelayType.frequency81: return '81 Frequency';
      case RelayType.rocof81R: return '81R ROCOF';
      case RelayType.motor49_46_48: return '49/46/48 Motor';
      case RelayType.synchCheck25: return '25 Sync Check';
    }
  }

  Widget _tcc() => ListView(padding: const EdgeInsets.all(12), children: [
    _hud('SELECTIVITY SWEEP',
      '${(selectivityMarginSec * 1000).toStringAsFixed(0)} ms',
      selectivityMarginSec >= .30 ? 'Minimum sweep margin â‰¥ 300 ms' : 'Minimum sweep margin < 300 ms'),
    _card('CT / 51 SETTINGS', Column(children: [
      _slider('CT Primary A', p.ctPri, 50, 2000, (v) => p.ctPri = v),
      _slider('CT Secondary A', p.ctSec, 1, 5, (v) => p.ctSec = v),
      _slider('Upstream 51 Secondary A', p.upSettingSecA, 1, 15, (v) => p.upSettingSecA = v),
      _slider('Upstream TMS', p.upTms, .05, 1.2, (v) => p.upTms = v),
      _slider('Downstream 51 Secondary A', p.downSettingSecA, .5, 10, (v) => p.downSettingSecA = v),
      _slider('Downstream TMS', p.downTms, .05, 1, (v) => p.downTms = v),
    ])),
    _card(tr('RÃ–LE TÄ°PÄ° / KORUMA FONKSÄ°YONLARI', 'RELAY TYPE / PROTECTION FUNCTIONS'), Column(children: [
      Wrap(spacing: 5, runSpacing: 4, children: RelayType.values.map((r) => FilterChip(
        label: Text(_relayName(r), style: const TextStyle(fontSize: 9)),
        selected: p.relayTypes.contains(r),
        onSelected: (selected) => setState(() {
          final next = List<RelayType>.from(p.relayTypes);
          if (selected) { if (!next.contains(r)) next.add(r); }
          else { next.remove(r); }
          p.relayTypes = next;
          _persistProjects();
        }),
      )).toList()),
    ])),
    _card(tr('ANSI 50', 'ANSI 50'), Column(children: [
      SwitchListTile(
        dense: true, title: const Text('Downstream 50 Active', style: TextStyle(fontSize: 11)),
        value: p.down50Enabled, onChanged: (v) => setState(() => p.down50Enabled = v)),
      if (p.down50Enabled)
        _slider('Downstream 50 Pickup A', p.down50PickupA, 500, 10000, (v) => p.down50PickupA = v),
      Text('Upstream 50: ${p.up50Enabled ? p.up50PickupA.toStringAsFixed(0) : "OFF"} A',
        style: const TextStyle(fontSize: 10, color: Colors.grey)),
    ])),
    _card(tr('KOORDÄ°NASYON SONUCU', 'COORDINATION RESULT'), Column(children: [
      _row('Minimum 51 margin', '${(selectivityMarginSec*1000).toStringAsFixed(0)} ms', selectivityMarginSec >= .30),
      _row('50 coordination', instantaneousCoordination ? 'OK' : 'CHECK', instantaneousCoordination),
    ])),
  ]);

  Widget _sat() {
    final maxRes = max(p.resR, max(p.resS, p.resT));
    final sync = max((p.timeR-p.timeS).abs(), max((p.timeS-p.timeT).abs(), (p.timeR-p.timeT).abs()));
    return ListView(padding: const EdgeInsets.all(12), children: [
      _hud('BREAKER SAT', breaker.name,
        'Max R ${maxRes.toStringAsFixed(1)} ÂµÎ© | Pole Î”t ${sync.toStringAsFixed(1)} ms'),
      _slider('R pole ÂµÎ©', p.resR, 10, 100, (v) => p.resR = v),
      _slider('S pole ÂµÎ©', p.resS, 10, 100, (v) => p.resS = v),
      _slider('T pole ÂµÎ©', p.resT, 10, 100, (v) => p.resT = v),
      _slider('R time ms', p.timeR, 20, 90, (v) => p.timeR = v),
      _slider('S time ms', p.timeS, 20, 90, (v) => p.timeS = v),
      _slider('T time ms', p.timeT, 20, 90, (v) => p.timeT = v),
      ElevatedButton.icon(
        onPressed: addSatRecord,
        icon: const Icon(Icons.save),
        label: const Text('SAT KaydÄ±nÄ± Proje GeÃ§miÅŸine Ekle')),
      if (satResistanceTrendPercent != null)
        _row('Kontak direnci trendi', '${satResistanceTrendPercent! >= 0 ? '+' : ''}${satResistanceTrendPercent!.toStringAsFixed(1)} %', satResistanceTrendPercent! <= 0),
      if (p.testHistory.isNotEmpty)
        _card(tr('SAT GEÃ‡MÄ°ÅžÄ°', 'SAT HISTORY'), Column(children: p.testHistory.take(6).map((r) =>
          ListTile(dense: true, title: Text(r.timestamp, style: const TextStyle(fontSize: 10)),
            subtitle: Text('${r.breaker} | ${r.maxRes.toStringAsFixed(1)} ÂµÎ© | Î”t ${r.syncDelta.toStringAsFixed(1)} ms',
              style: const TextStyle(fontSize: 9)),
            trailing: Icon(r.passed ? Icons.check : Icons.close,
              color: r.passed ? Colors.greenAccent : Colors.redAccent))).toList())),
    ]);
  }

  Widget _cable() => ListView(padding: const EdgeInsets.all(12), children: [
    _hud('CABLE PRE-CHECK', '${p.cableSectionMm2.toInt()} mmÂ² ${p.isCopper ? "Cu" : "Al"}',
      'Iz ${(cable["deratedIz"] as double).toStringAsFixed(0)} A | Î”U ${(cable["dropPercent"] as double).toStringAsFixed(2)}%'),
    _card(tr('KABLO PARAMETRELERÄ°', 'CABLE PARAMETERS'), Column(children: [
      _slider('Section mmÂ²', p.cableSectionMm2, 35, 300, (v) => p.cableSectionMm2 = v),
      _slider('Length m', p.cableLengthM, 10, 2000, (v) => p.cableLengthM = v),
      _slider('Load A', p.loadCurrentA, 10, 800, (v) => p.loadCurrentA = v),
      _slider('Ambient Â°C', p.ambientTempC, -10, 70, (v) => p.ambientTempC = v),
      _slider('Grouping factor', p.cableGroupingFactor, .5, 1, (v) => p.cableGroupingFactor = v),
    ])),
    _row('Thermal Smin', '${(cable["sMin"] as double).toStringAsFixed(1)} mmÂ²', cable['isThermalOk'] as bool),
    _row('Continuous Iz', '${(cable["deratedIz"] as double).toStringAsFixed(0)} A', cable['isAmpacityOk'] as bool),
    _row('Voltage drop', '${(cable["dropPercent"] as double).toStringAsFixed(2)} %', cable['isVoltageDropOk'] as bool),
  ]);

  Widget _sld() => ListView(padding: const EdgeInsets.all(12), children: [
    _hud('SLD', switchgear.name, '${p.voltageKv} kV | Ik ${ikMax.toStringAsFixed(1)} kA'),
    SizedBox(
      height: 230,
      child: CustomPaint(
        painter: SldPainter(cells: p.cells, color: switchgear.brandColor),
      ),
    ),
    ...p.cells.map((c) => Card(
      child: ListTile(
        dense: true,
        title: Text(c.name, style: const TextStyle(fontSize: 11)),
        subtitle: Text('${c.currentVendor} | ${c.currentBreaker} | CT ${c.ctRatio}',
          style: const TextStyle(fontSize: 9)),
        trailing: Switch(
          value: c.cbClosed,
          onChanged: (v) => setState(() => c.cbClosed = v),
        ),
      ),
    )),
  ]);

  Widget _slider(String title, double value, double minV, double maxV, ValueChanged<double> onChanged) =>
      Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: const TextStyle(fontSize: 10)),
              Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
            ]),
            Slider(value: value.clamp(minV, maxV).toDouble(), min: minV, max: maxV, onChanged: (v) {
              setState(() => onChanged(v));
            }),
          ]),
        ),
      );

  Widget _hud(String title, String value, String sub) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF111622),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: switchgear.brandColor.withValues(alpha: .55)),
    ),
    child: Column(children: [
      Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
      Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: switchgear.brandColor)),
      Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.grey)),
    ]),
  );

  Widget _card(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF111622),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF30363D)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      child,
    ]),
  );

  Widget _row(String title, String value, bool ok) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 10, color: Colors.white70))),
      Text('$value ${ok ? "âœ“ PASS" : "âœ— FAIL"}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
          color: ok ? Colors.greenAccent : Colors.redAccent)),
    ]),
  );

  void _showVerdict() {
    final v = verdict;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111622),
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(shrinkWrap: true, children: [
          Text(tr('POWERFIELD DEVREYE ALMA Ã–N KONTROLÃœ', 'POWERFIELD PRE-COMMISSIONING VERDICT'),
            style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFB300))),
          const SizedBox(height: 10),
          _row('Icu', '${ikMax.toStringAsFixed(2)} / ${breaker.ratedBreakingIcuKa} kA', v.shortCircuitIcu),
          _row('Icw', '${ikMax.toStringAsFixed(2)} / ${breaker.shortTimeWithstandIcwKa} kA', v.shortCircuitIcw),
          _row('Peak Ip', '${ipPeak.toStringAsFixed(1)} / ${breaker.peakMakingIpKa} kA', v.shortCircuitIp),
          _row('51 minimum sweep margin', '${(selectivityMarginSec*1000).toStringAsFixed(0)} ms', v.selectivityMargin),
          _row('50 coordination', '50/51 interaction', v.instantaneousCoordination),
          _row('Cable thermal', '${(cable["sMin"] as double).toStringAsFixed(1)} mmÂ² required', v.cableThermal),
          _row('Cable ampacity', '${(cable["deratedIz"] as double).toStringAsFixed(0)} A', v.cableAmpacity),
          _row('Voltage drop', '${(cable["dropPercent"] as double).toStringAsFixed(2)} %', v.cableVoltageDrop),
          _row('SAT contact resistance', '${max(p.resR,max(p.resS,p.resT)).toStringAsFixed(1)} ÂµÎ©', v.satDuctor),
          _row('SAT pole synchronism', 'â‰¤ 3 ms', v.satSync),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            color: v.isReadyForCommissioning ? const Color(0xFF00A844) : const Color(0xFFB00020),
            child: Text(v.isReadyForCommissioning
                ? tr('DEVREYE ALMA Ã–N KONTROLÃœ: UYGUN', 'PRE-COMMISSIONING CHECK: PASS')
                : tr('DEVREYE ALMA Ã–N KONTROLÃœ: UYGUN DEÄžÄ°L', 'PRE-COMMISSIONING CHECK: FAIL'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bu sonuÃ§lar Ã¶n mÃ¼hendislik kontrolÃ¼dÃ¼r; saha devreye alma/onay raporu deÄŸildir.',
            style: TextStyle(fontSize: 9, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
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
      final c = cells[i];
      canvas.drawLine(Offset(x, 35), Offset(x, busY + 40), line);

      final rect = Rect.fromCenter(center: Offset(x, busY), width: 18, height: 18);
      final fill = Paint()..color = c.cbClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, Paint()..color = Colors.white..style = PaintingStyle.stroke);

      final tp = TextPainter(
        text: TextSpan(text: c.name, style: const TextStyle(color: Colors.white, fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      tp.paint(canvas, Offset(x - 45, busY + 18));
    }
  }

  @override
  bool shouldRepaint(covariant SldPainter oldDelegate) => true;
}
