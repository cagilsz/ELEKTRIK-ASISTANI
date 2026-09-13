import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const PowerFieldProApp());
}

class PowerFieldProApp extends StatelessWidget {
  const PowerFieldProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerField Pro v6.3 Engineering Core',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A0E),
        cardColor: const Color(0xFF111622),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF3D00),
          surface: Color(0xFF111622),
        ),
        useMaterial3: true,
      ),
      home: const MainCockpit(),
    );
  }
}

enum AppLanguage { tr, en, de, es, fr, zh, ja, ru }
enum PowerDomain { generation, transmission, distribution }
enum SubArchetype {
  solarGES, windRES, hydroHES, thermalCoal,
  hvSubstation154, hvGis380,
  heavyIndustry, hospital, airport, commercialMall, standardSubstation
}
enum CellType { incomer, feeder, coupler, vtMetering }

enum ProtectionStandard { iec60255, ieeeC37112 }
enum TripCurve { standardInverse, veryInverse, extremelyInverse, longTimeInverse }

// ============================================================================
// 1. MÜHENDİSLİK FİZİK & HESAP MOTORU (IEC 60909, IEC 60255, IEEE C37.112)
// ============================================================================
class ElectricalEngine {
  // IEC 60909: Max (c=1.10) & Min (c=1.00) Kısa Devre ve Tepe Değeri (Ip)
  static Map<String, double> calcIec60909FaultCurrents({
    required double voltageKv,
    required double trafoMva,
    required double ukPercent,
    double gridSscMva = 1000.0,
    double xrRatio = 8.0,
  }) {
    if (trafoMva <= 0 || ukPercent <= 0 || voltageKv <= 0) {
      return {'Ik_max': 0.0, 'Ik_min': 0.0, 'Ip_peak': 0.0};
    }
    final zQ = gridSscMva > 0 ? (1.10 * pow(voltageKv, 2)) / gridSscMva : 0.0;
    final zT = (ukPercent / 100.0) * (pow(voltageKv, 2) / trafoMva);
    final rT = zT / sqrt(1 + pow(xrRatio, 2));
    final xT = rT * xrRatio;

    // 1. Ik_max (c=1.10, soğuk sargı 20°C)
    final zTotalMax = zQ + zT;
    final ikMaxKa = (1.10 * voltageKv) / (sqrt(3) * zTotalMax);

    // Ip (Peak) IEC 60909: kappa ~ 1.80 (Orta Gerilim Dağıtım Şebekeleri için)
    final ipPeakKa = ikMaxKa * sqrt(2) * 1.80;

    // 2. Ik_min (c=1.00, sıcak sargı 80°C -> R x 1.24)
    final rTHot = rT * 1.24;
    final zTHot = sqrt(pow(rTHot, 2) + pow(xT, 2));
    final zTotalMin = zQ + zTHot;
    final ikMinKa = (1.00 * voltageKv) / (sqrt(3) * zTotalMin);

    return {'Ik_max': ikMaxKa, 'Ik_min': ikMinKa, 'Ip_peak': ipPeakKa};
  }

  static double calcNominalCurrentA(double mva, double voltageKv) {
    if (voltageKv <= 0) return 0.0;
    return (mva * 1000.0) / (sqrt(3) * voltageKv);
  }

  // Jeneratör ROCOF: df/dt = (f0 * DeltaP) / (2 * H * Sg)
  static double calcRocofHzSec({
    required double deltaP_Mw,
    required double generatorMw,
    double inertiaH_Sec = 3.5,
    double cosPhi = 0.85,
    double f0 = 50.0,
  }) {
    final sgMva = generatorMw / cosPhi;
    if (sgMva <= 0 || inertiaH_Sec <= 0) return 0.0;
    return (f0 * deltaP_Mw) / (2.0 * inertiaH_Sec * sgMva);
  }

  // ANSI 21 Mesafe Koruma Kademe Empedansları (Zone 1, 2, 3)
  static Map<String, double> calcDistanceZones({
    required double lineLengthKm,
    required double voltageKv,
  }) {
    final zPerKmOhm = voltageKv >= 300.0 ? 0.28 : 0.36;
    final zLine = lineLengthKm * zPerKmOhm;
    return {
      'Z_line': zLine,
      'Zone1': zLine * 0.85,
      'Zone2': zLine * 1.20,
      'Zone3': zLine * 1.50,
    };
  }

  // SF6 Sıcaklık Telafili Basınç (Gay-Lussac Yasası)
  static double calcCompensatedSf6Pressure({
    required double measuredPressureMpa,
    required double ambientTempC,
  }) {
    final tKelvin = ambientTempC + 273.15;
    if (tKelvin <= 0) return measuredPressureMpa;
    return measuredPressureMpa * (293.15 / tKelvin);
  }

  // IEEE 519 Harmonik Rezonans Mertebesi: nr = sqrt(Ssc / Qc)
  static double calcResonanceOrder(double sscMva, double qcKvar) {
    if (qcKvar <= 0) return 0.0;
    final qcMva = qcKvar / 1000.0;
    return sqrt(sscMva / qcMva);
  }

  // Motor Kalkışında Gerilim Çökmesi (%)
  static double calcMotorStartVoltageDipPercent({
    required double motorKw,
    required double sscMva,
    double startCurrentMultiplier = 6.0,
    double cosPhi = 0.85,
    double efficiency = 0.94,
  }) {
    if (sscMva <= 0 || motorKw <= 0) return 0.0;
    final sNominalMva = (motorKw / 1000.0) / (cosPhi * efficiency);
    final sStartMva = sNominalMva * startCurrentMultiplier;
    return (sStartMva / (sscMva + sStartMva)) * 100.0;
  }

  // Akım Trafosu Dönüştürme Oranı üzerinden Primer Pickup Hesabı
  static double calcPrimaryPickupAmps({
    required double ctPrimaryA,
    required double ctSecondaryA,
    required double secondarySettingA,
  }) {
    if (ctSecondaryA <= 0) return 0.0;
    return secondarySettingA * (ctPrimaryA / ctSecondaryA);
  }

  // IEC 60255 & IEEE C37.112 IDMT Açma Süresi Hesaplayıcı
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
      double k = 0.14, alpha = 0.02;
      if (curve == TripCurve.veryInverse) { k = 13.5; alpha = 1.0; }
      else if (curve == TripCurve.extremelyInverse) { k = 80.0; alpha = 2.0; }
      else if (curve == TripCurve.longTimeInverse) { k = 120.0; alpha = 1.0; }
      final denom = pow(m, alpha) - 1.0;
      if (denom <= 0) return double.infinity;
      return tmsVal * (k / denom);
    } else {
      // IEEE C37.112 Denklemi: t = TD * [ A / (M^p - 1) + B ]
      double a = 0.0515, b = 0.1140, p = 0.02; // IEEE Moderately Inverse
      if (curve == TripCurve.veryInverse) { a = 19.61; b = 0.491; p = 2.0; }
      else if (curve == TripCurve.extremelyInverse) { a = 28.2; b = 0.1217; p = 2.0; }
      final denom = pow(m, p) - 1.0;
      if (denom <= 0) return double.infinity;
      return tmsVal * ((a / denom) + b);
    }
  }

  // IEC 60364-5-54 Dört Kriterli Kablo Değerlendirme Matrisi
  static Map<String, dynamic> evaluateCableSizing({
    required double sectionMm2,
    required double lengthM,
    required double loadCurrentA,
    required double voltageKv,
    required double ikKa,
    required double faultTimeSec,
    required bool isCopper,
    double ambientTempC = 30.0,
  }) {
    final k = isCopper ? 143.0 : 94.0;
    final sMin = ((ikKa * 1000.0) * sqrt(faultTimeSec)) / k;
    final isThermalOk = sectionMm2 >= sMin;

    final Map<int, double> baseAmpacity = {
      35: 145.0, 50: 175.0, 70: 215.0, 95: 260.0,
      120: 295.0, 150: 335.0, 185: 380.0, 240: 440.0, 300: 495.0
    };
    final baseIz = baseAmpacity[sectionMm2.toInt()] ?? (sectionMm2 * 2.2);
    final kt = ambientTempC <= 20 ? 1.05 : (1.0 - (ambientTempC - 20) * 0.005);
    final deratedIz = baseIz * kt * 0.85;
    final isAmpacityOk = loadCurrentA <= deratedIz;

    final rho = isCopper ? 0.0175 : 0.028;
    final r = (rho * lengthM) / sectionMm2;
    final x = 0.08 * (lengthM / 1000.0);
    const cosPhi = 0.85;
    final sinPhi = sqrt(1 - pow(cosPhi, 2));
    final deltaU = sqrt(3) * loadCurrentA * (r * cosPhi + x * sinPhi);
    final dropPercent = (deltaU / (voltageKv * 1000.0)) * 100.0;
    final isVoltageDropOk = dropPercent <= 3.0;

    return {
      'sMin': sMin,
      'isThermalOk': isThermalOk,
      'deratedIz': deratedIz,
      'isAmpacityOk': isAmpacityOk,
      'dropPercent': dropPercent,
      'isVoltageDropOk': isVoltageDropOk,
      'isOverallPass': isThermalOk && isAmpacityOk && isVoltageDropOk,
    };
  }

  static double calcAltitudeDeratingKa(double altitudeMeters) {
    if (altitudeMeters <= 1000) return 1.0;
    return exp((altitudeMeters - 1000) / 8150.0);
  }
}

// ============================================================================
// 2. NİHAİ MÜHENDİSLİK KARAR NESNESİ (VERDICT OBJECT)
// ============================================================================
class EngineeringVerdict {
  final bool shortCircuitIcu;
  final bool shortCircuitIp;
  final bool selectivityMargin;
  final bool cableThermal;
  final bool cableAmpacity;
  final bool cableVoltageDrop;
  final bool satDuctor;
  final bool satSync;

  const EngineeringVerdict({
    required this.shortCircuitIcu,
    required this.shortCircuitIp,
    required this.selectivityMargin,
    required this.cableThermal,
    required this.cableAmpacity,
    required this.cableVoltageDrop,
    required this.satDuctor,
    required this.satSync,
  });

  bool get isReadyForCommissioning =>
      shortCircuitIcu &&
      shortCircuitIp &&
      selectivityMargin &&
      cableThermal &&
      cableAmpacity &&
      cableVoltageDrop &&
      satDuctor &&
      satSync;
}

// ============================================================================
// 3. EKİPMAN MODELLERİ (Icu, Ics, Icw, Ip DAHİL)
// ============================================================================
class BreakerModel {
  final String name;
  final String vendor;
  final String medium;
  final double defaultLimitMicroOhm;
  final double typicalTripTimeMs;
  final double ratedBreakingIcuKa;
  final double serviceBreakingIcsKa;
  final double shortTimeWithstandIcwKa;
  final double peakMakingIpKa;
  final String standardCode;
  final Color brandColor;

  const BreakerModel({
    required this.name,
    required this.vendor,
    required this.medium,
    required this.defaultLimitMicroOhm,
    required this.typicalTripTimeMs,
    required this.ratedBreakingIcuKa,
    required this.serviceBreakingIcsKa,
    required this.shortTimeWithstandIcwKa,
    required this.peakMakingIpKa,
    required this.standardCode,
    required this.brandColor,
  });
}

const List<BreakerModel> kBreakers = [
  BreakerModel(
    name: "Schneider Evolis (Vakum)",
    vendor: "Schneider",
    medium: "Vacuum",
    defaultLimitMicroOhm: 35.0,
    typicalTripTimeMs: 38.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFF009639),
  ),
  BreakerModel(
    name: "Schneider FB4 (Fluarc Santral)",
    vendor: "Schneider",
    medium: "SF6",
    defaultLimitMicroOhm: 32.0,
    typicalTripTimeMs: 45.0,
    ratedBreakingIcuKa: 40.0,
    serviceBreakingIcsKa: 40.0,
    shortTimeWithstandIcwKa: 40.0,
    peakMakingIpKa: 104.0,
    standardCode: "IEC 62271 / IEEE C37",
    brandColor: Color(0xFF009639),
  ),
  BreakerModel(
    name: "Schneider SF1 / SF2 (Fluarc)",
    vendor: "Schneider",
    medium: "SF6",
    defaultLimitMicroOhm: 38.0,
    typicalTripTimeMs: 42.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFF009639),
  ),
  BreakerModel(
    name: "Schneider LF1 / LF2 / LF3",
    vendor: "Schneider",
    medium: "SF6",
    defaultLimitMicroOhm: 40.0,
    typicalTripTimeMs: 42.0,
    ratedBreakingIcuKa: 31.5,
    serviceBreakingIcsKa: 31.5,
    shortTimeWithstandIcwKa: 31.5,
    peakMakingIpKa: 82.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFF009639),
  ),
  BreakerModel(
    name: "Siemens SION 3AE / 3AH",
    vendor: "Siemens",
    medium: "Vacuum",
    defaultLimitMicroOhm: 45.0,
    typicalTripTimeMs: 44.0,
    ratedBreakingIcuKa: 31.5,
    serviceBreakingIcsKa: 31.5,
    shortTimeWithstandIcwKa: 31.5,
    peakMakingIpKa: 82.0,
    standardCode: "IEC / DIN VDE 0671",
    brandColor: Color(0xFF00646E),
  ),
  BreakerModel(
    name: "ABB VD4 (Vakum)",
    vendor: "ABB",
    medium: "Vacuum",
    defaultLimitMicroOhm: 38.0,
    typicalTripTimeMs: 40.0,
    ratedBreakingIcuKa: 31.5,
    serviceBreakingIcsKa: 31.5,
    shortTimeWithstandIcwKa: 31.5,
    peakMakingIpKa: 82.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFFFF000F),
  ),
  BreakerModel(
    name: "ABB HD4 (SF6)",
    vendor: "ABB",
    medium: "SF6",
    defaultLimitMicroOhm: 42.0,
    typicalTripTimeMs: 45.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFFFF000F),
  ),
  BreakerModel(
    name: "Eaton W-VACi / UX",
    vendor: "Eaton",
    medium: "Vacuum",
    defaultLimitMicroOhm: 36.0,
    typicalTripTimeMs: 42.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271-100 / ANSI",
    brandColor: Color(0xFF003882),
  ),
  BreakerModel(
    name: "Magrini Galileo Fluvid / G10",
    vendor: "Magrini Galileo",
    medium: "SF6",
    defaultLimitMicroOhm: 36.0,
    typicalTripTimeMs: 46.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271 / CEI",
    brandColor: Color(0xFF008080),
  ),
  BreakerModel(
    name: "Mitsubishi MS-V / MEKAR",
    vendor: "Mitsubishi",
    medium: "Vacuum",
    defaultLimitMicroOhm: 34.0,
    typicalTripTimeMs: 38.0,
    ratedBreakingIcuKa: 31.5,
    serviceBreakingIcsKa: 31.5,
    shortTimeWithstandIcwKa: 31.5,
    peakMakingIpKa: 82.0,
    standardCode: "JEC-2300 / IEC",
    brandColor: Color(0xFFD9001B),
  ),
  BreakerModel(
    name: "Ormazabal CPG / CGS",
    vendor: "Ormazabal",
    medium: "Vacuum",
    defaultLimitMicroOhm: 42.0,
    typicalTripTimeMs: 45.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "IEC 62271-100",
    brandColor: Color(0xFFE35205),
  ),
  BreakerModel(
    name: "Tavrida BB/TEL (ВВ/TEL)",
    vendor: "Tavrida",
    medium: "Vacuum",
    defaultLimitMicroOhm: 35.0,
    typicalTripTimeMs: 32.0,
    ratedBreakingIcuKa: 25.0,
    serviceBreakingIcsKa: 25.0,
    shortTimeWithstandIcwKa: 25.0,
    peakMakingIpKa: 65.0,
    standardCode: "ГОСТ Р 52565 / ПУЭ",
    brandColor: Color(0xFF4A90E2),
  ),
  BreakerModel(
    name: "TEDAŞ Standart Yerli Vakum",
    vendor: "Yerli/TEDAŞ",
    medium: "Vacuum",
    defaultLimitMicroOhm: 50.0,
    typicalTripTimeMs: 45.0,
    ratedBreakingIcuKa: 16.0,
    serviceBreakingIcsKa: 16.0,
    shortTimeWithstandIcwKa: 16.0,
    peakMakingIpKa: 41.6,
    standardCode: "TEDAŞ-MLZ/96-015",
    brandColor: Color(0xFFFFB300),
  ),
];

class SwitchgearModel {
  final String name;
  final String vendor;
  final String type;
  final String standard;
  final Color brandColor;

  const SwitchgearModel(this.name, this.vendor, this.type, this.standard, this.brandColor);
}

const List<SwitchgearModel> kSwitchgears = [
  SwitchgearModel("Schneider SM6-36", "Schneider", "AIS Modüler", "IEC 62271-200 / TEDAŞ", Color(0xFF009639)),
  SwitchgearModel("Schneider Premset (2SI)", "Schneider", "Ekranlı Katı (SSIS)", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Schneider AirSeT (SF6-Free)", "Schneider", "Saf Hava + Vakum", "IEC 62271-200", Color(0xFF00B050)),
  SwitchgearModel("Schneider RM6 / FBX", "Schneider", "Kompakt RMU (GIS)", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Schneider GHA (GIS)", "Schneider", "Gaz Yalıtımlı Şalt", "IEC 62271-200", Color(0xFF009639)),
  SwitchgearModel("Siemens 8BT2 / NXAIR", "Siemens", "Hava Yalıtımlı Metal-Clad", "IEC 62271-200", Color(0xFF00646E)),
  SwitchgearModel("Siemens 8DJH / SIMOSEC", "Siemens", "Gaz Yalıtımlı RMU", "IEC 62271-200", Color(0xFF00646E)),
  SwitchgearModel("ABB UniGear ZS1", "ABB", "Metal-Clad Çekmeceli", "IEC 62271-200", Color(0xFFFF000F)),
  SwitchgearModel("ABB SafeRing / SafePlus", "ABB", "Kompakt Ring Ana Ünitesi", "IEC 62271-200", Color(0xFFFF000F)),
  SwitchgearModel("Eaton Power Xpert UX", "Eaton", "Metal-Clad 24/36kV", "IEC 62271-200", Color(0xFF003882)),
  SwitchgearModel("Ormazabal CGMcosmos / GAE", "Ormazabal", "Modüler Kompakt GIS", "IEC 62271-200", Color(0xFFE35205)),
  SwitchgearModel("Ulusoy HMH-36 / Astor", "TEDAŞ", "TEDAŞ Modüler Hücre", "TEDAŞ MYD/96-015", Color(0xFFFFB300)),
];

class SwitchgearCell {
  String id;
  String name;
  CellType type;
  bool cbClosed;
  String ctRatio;
  String currentVendor;
  String currentBreaker;

  SwitchgearCell({
    required this.id,
    required this.name,
    required this.type,
    this.cbClosed = false,
    this.ctRatio = "400/5A",
    this.currentVendor = "Schneider",
    this.currentBreaker = "Evolis",
  });
}

class TestRecord {
  final String timestamp;
  final String substation;
  final String breaker;
  final double maxRes;
  final double syncDelta;
  final bool passed;

  TestRecord({required this.timestamp, required this.substation, required this.breaker, required this.maxRes, required this.syncDelta, required this.passed});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'substation': substation,
    'breaker': breaker,
    'maxRes': maxRes,
    'syncDelta': syncDelta,
    'passed': passed,
  };

  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(
    timestamp: j['timestamp'] ?? '',
    substation: j['substation'] ?? '',
    breaker: j['breaker'] ?? '',
    maxRes: (j['maxRes'] as num?)?.toDouble() ?? 0.0,
    syncDelta: (j['syncDelta'] as num?)?.toDouble() ?? 0.0,
    passed: j['passed'] ?? false,
  );
}

// ============================================================================
// 4. PROJE MODELİ (STATE ARTIK TÜM SEÇİMLERİ İÇERİR)
// ============================================================================
class ProjectModel {
  String name;
  PowerDomain domain;
  SubArchetype archetype;
  double voltageKv;
  double trafoMva;
  double ukPercent;
  double gridSscMva;

  int switchgearIndex;
  int breakerIndex;

  double ctPri;
  double ctSec;

  // ANSI 51 (IDMT) Ayarları
  double upSettingSecA;
  double upTms;
  TripCurve upCurve;
  double downSettingSecA;
  double downTms;
  TripCurve downCurve;
  ProtectionStandard protectionStandard;

  // ANSI 50 (Instantaneous) Ayarları
  bool up50Enabled;
  double up50PickupA;
  bool down50Enabled;
  double down50PickupA;

  // SAT Ölçümleri
  double resR;
  double resS;
  double resT;
  double timeR;
  double timeS;
  double timeT;

  // Kablo
  double cableLengthM;
  double loadCurrentA;
  double cableSectionMm2;
  bool isCopper;

  List<TestRecord> testHistory;
  List<SwitchgearCell> cells;

  ProjectModel({
    required this.name,
    required this.domain,
    required this.archetype,
    required this.voltageKv,
    required this.trafoMva,
    required this.ukPercent,
    required this.gridSscMva,
    this.switchgearIndex = 0,
    this.breakerIndex = 0,
    this.ctPri = 400.0,
    this.ctSec = 5.0,
    this.upSettingSecA = 7.5, // 600 A primer
    this.upTms = 0.25,
    this.upCurve = TripCurve.standardInverse,
    this.downSettingSecA = 3.125, // 250 A primer
    this.downTms = 0.15,
    this.downCurve = TripCurve.standardInverse,
    this.protectionStandard = ProtectionStandard.iec60255,
    this.up50Enabled = true,
    this.up50PickupA = 3000.0,
    this.down50Enabled = true,
    this.down50PickupA = 1500.0,
    this.resR = 33.2,
    this.resS = 34.8,
    this.resT = 33.9,
    this.timeR = 41.5,
    this.timeS = 42.8,
    this.timeT = 42.1,
    this.cableLengthM = 220.0,
    this.loadCurrentA = 110.0,
    this.cableSectionMm2 = 70.0,
    this.isCopper = true,
    required this.testHistory,
    required this.cells,
  });
}

// ============================================================================
// 5. ANA KOKPİT EKRANI (COCKPIT)
// ============================================================================
class MainCockpit extends StatefulWidget {
  const MainCockpit({super.key});
  @override
  State<MainCockpit> createState() => _MainCockpitState();
}

class _MainCockpitState extends State<MainCockpit> {
  int _activeTab = 0;
  AppLanguage _lang = AppLanguage.tr;

  late List<ProjectModel> _projects;
  int _activeProjectIdx = 0;
  ProjectModel get p => _projects[_activeProjectIdx];

  BreakerModel get _activeBreaker => kBreakers[p.breakerIndex.clamp(0, kBreakers.length - 1)];
  SwitchgearModel get _activeSwitchgear => kSwitchgears[p.switchgearIndex.clamp(0, kSwitchgears.length - 1)];

  double _ambientTemp = 28.0;
  double _altitudeMeters = 50.0;

  double _generatorMw = 20.0;
  double _inertiaH_Sec = 3.5;
  double _powerMismatchMw = 3.0;
  double _reversePowerPercent = 1.2;
  double _lineLengthKm = 42.0;
  double _sf6MeasuredMpa = 0.61;

  double _motorKw = 400.0;
  double _compensationKvar = 600.0;
  double _hospitalRisoKOhm = 85.0;
  double _airportCcrAmps = 6.6;
  bool _firePump51Bypassed = true;

  @override
  void initState() {
    super.initState();
    _initDefaultProjects();
  }

  void _initDefaultProjects() {
    _projects = [
      ProjectModel(
        name: "Aliağa OSB Dağıtım TM-1",
        domain: PowerDomain.distribution,
        archetype: SubArchetype.heavyIndustry,
        voltageKv: 34.5,
        trafoMva: 2.5,
        ukPercent: 6.0,
        gridSscMva: 1000.0,
        switchgearIndex: 0,
        breakerIndex: 0,
        testHistory: [
          TestRecord(timestamp: "12/03/2025", substation: "Aliağa OSB TM-1", breaker: "Schneider Evolis", maxRes: 31.4, syncDelta: 1.2, passed: true),
          TestRecord(timestamp: "18/09/2024", substation: "Aliağa OSB TM-1", breaker: "Schneider Evolis", maxRes: 29.8, syncDelta: 1.0, passed: true),
        ],
        cells: _createDefaultCells("Schneider", "Schneider Evolis (Vakum)"),
      ),
      ProjectModel(
        name: "Torbalı GES 15 MW Santral",
        domain: PowerDomain.generation,
        archetype: SubArchetype.solarGES,
        voltageKv: 34.5,
        trafoMva: 16.0,
        ukPercent: 6.5,
        gridSscMva: 750.0,
        switchgearIndex: 3,
        breakerIndex: 2,
        testHistory: [],
        cells: _createDefaultCells("Schneider", "Schneider SF1 / SF2 (Fluarc)"),
      ),
      ProjectModel(
        name: "Menemen 154 kV TEİAŞ TM",
        domain: PowerDomain.transmission,
        archetype: SubArchetype.hvSubstation154,
        voltageKv: 154.0,
        trafoMva: 50.0,
        ukPercent: 12.0,
        gridSscMva: 2500.0,
        switchgearIndex: 5,
        breakerIndex: 4,
        testHistory: [],
        cells: _createDefaultCells("Siemens", "Siemens SION 3AE / 3AH"),
      ),
    ];
  }

  List<SwitchgearCell> _createDefaultCells(String vendor, String breaker) {
    return [
      SwitchgearCell(id: "C1", name: "H01 Incomer", type: CellType.incomer, cbClosed: true, ctRatio: "400/5A", currentVendor: vendor, currentBreaker: breaker),
      SwitchgearCell(id: "C2", name: "H02 VT Meter", type: CellType.vtMetering, cbClosed: true, currentVendor: vendor, currentBreaker: "VT"),
      SwitchgearCell(id: "C3", name: "H03 Bus Coupler", type: CellType.coupler, cbClosed: false, currentVendor: vendor, currentBreaker: breaker),
      SwitchgearCell(id: "C4", name: "H04 Feeder 1", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A", currentVendor: vendor, currentBreaker: breaker),
      SwitchgearCell(id: "C5", name: "H05 Feeder 2", type: CellType.feeder, cbClosed: true, ctRatio: "200/5A", currentVendor: vendor, currentBreaker: breaker),
    ];
  }

  Map<String, double> get _faultCalc => ElectricalEngine.calcIec60909FaultCurrents(
    voltageKv: p.voltageKv,
    trafoMva: p.trafoMva,
    ukPercent: p.ukPercent,
    gridSscMva: p.gridSscMva,
  );
  double get _ikMaxKa => _faultCalc['Ik_max']!;
  double get _ikMinKa => _faultCalc['Ik_min']!;
  double get _ipPeakKa => _faultCalc['Ip_peak']!;

  double get _upPrimaryPickupA => ElectricalEngine.calcPrimaryPickupAmps(ctPrimaryA: p.ctPri, ctSecondaryA: p.ctSec, secondarySettingA: p.upSettingSecA);
  double get _downPrimaryPickupA => ElectricalEngine.calcPrimaryPickupAmps(ctPrimaryA: p.ctPri, ctSecondaryA: p.ctSec, secondarySettingA: p.downSettingSecA);

  double get _rocofHzSec => ElectricalEngine.calcRocofHzSec(deltaP_Mw: _powerMismatchMw, generatorMw: _generatorMw, inertiaH_Sec: _inertiaH_Sec);
  double get _compensatedSf6Mpa => ElectricalEngine.calcCompensatedSf6Pressure(measuredPressureMpa: _sf6MeasuredMpa, ambientTempC: _ambientTemp);
  double get _resonanceOrder => ElectricalEngine.calcResonanceOrder(_ikMaxKa * sqrt(3) * p.voltageKv, _compensationKvar);
  double get _motorDipPercent => ElectricalEngine.calcMotorStartVoltageDipPercent(motorKw: _motorKw, sscMva: _ikMaxKa * sqrt(3) * p.voltageKv);

  Map<String, dynamic> get _cableEval => ElectricalEngine.evaluateCableSizing(
    sectionMm2: p.cableSectionMm2,
    lengthM: p.cableLengthM,
    loadCurrentA: p.loadCurrentA,
    voltageKv: p.voltageKv,
    ikKa: _ikMaxKa,
    faultTimeSec: 0.15,
    isCopper: p.isCopper,
    ambientTempC: _ambientTemp,
  );

  // Yapılandırılmış Nihai Mühendislik Kararı
  EngineeringVerdict get _verdict {
    final faultIcuCheck = _ikMaxKa <= _activeBreaker.ratedBreakingIcuKa;
    final faultIpCheck = _ipPeakKa <= _activeBreaker.peakMakingIpKa;

    final tUp = ElectricalEngine.calcTripTime(
      faultA: _ikMaxKa * 1000.0,
      iPickupA: _upPrimaryPickupA,
      tmsVal: p.upTms,
      curve: p.upCurve,
      standard: p.protectionStandard,
    );
    final tDown = ElectricalEngine.calcTripTime(
      faultA: _ikMaxKa * 1000.0,
      iPickupA: _downPrimaryPickupA,
      tmsVal: p.downTms,
      curve: p.downCurve,
      standard: p.protectionStandard,
    );
    final marginCheck = (tUp.isFinite && tDown.isFinite) ? ((tUp - tDown) >= 0.30) : false;

    final cableEval = _cableEval;
    final cableThermal = cableEval['isThermalOk'] as bool;
    final cableAmpacity = cableEval['isAmpacityOk'] as bool;
    final cableVoltageDrop = cableEval['isVoltageDropOk'] as bool;

    final maxRes = max(p.resR, max(p.resS, p.resT));
    final deltaSyncMs = [(p.timeR - p.timeS).abs(), (p.timeS - p.timeT).abs(), (p.timeR - p.timeT).abs()].reduce(max);
    final satDuctor = maxRes <= _activeBreaker.defaultLimitMicroOhm;
    final satSync = deltaSyncMs <= 3.0;

    return EngineeringVerdict(
      shortCircuitIcu: faultIcuCheck,
      shortCircuitIp: faultIpCheck,
      selectivityMargin: marginCheck,
      cableThermal: cableThermal,
      cableAmpacity: cableAmpacity,
      cableVoltageDrop: cableVoltageDrop,
      satDuctor: satDuctor,
      satSync: satSync,
    );
  }

  // ============================================================================
  // %100 8 DİLLİ TAM YERELLEŞTİRME SÖZLÜĞÜ
  // ============================================================================
  String t(String k) {
    const d = {
      'tab_cockpit': {'tr': 'Kokpit', 'en': 'Cockpit', 'de': 'Cockpit', 'es': 'Cabina', 'fr': 'Poste', 'zh': '总控台', 'ja': 'コックピット', 'ru': 'Панель'},
      'tab_relay': {'tr': 'Röle TCC', 'en': 'Relay TCC', 'de': 'Schutz TCC', 'es': 'Relé TCC', 'fr': 'Relais TCC', 'zh': '保护TCC', 'ja': '保護TCC', 'ru': 'РЗиА ВТХ'},
      'tab_sat': {'tr': 'Kesici SAT', 'en': 'CB SAT', 'de': 'LS Diagnose', 'es': 'SAT Disyuntor', 'fr': 'Essais SAT', 'zh': '断路器SAT', 'ja': '遮断器SAT', 'ru': 'Испытания SAT'},
      'tab_cable': {'tr': 'Kablo & PQ', 'en': 'Cable & PQ', 'de': 'Kabel & PQ', 'es': 'Cable y PQ', 'fr': 'Câble & PQ', 'zh': '电缆与电能质量', 'ja': '電線・電力品質', 'ru': 'Кабель и ПКЭ'},
      'tab_sld': {'tr': 'SLD Şema', 'en': 'SLD Diagram', 'de': 'SLD Schema', 'es': 'Diagrama Unifilar', 'fr': 'Schéma SLD', 'zh': '单线图 (SLD)', 'ja': '単線結線図', 'ru': 'Схема ОРУ'},

      'dom_gen': {'tr': '⚡ ÜRETİM (Generation)', 'en': '⚡ GENERATION', 'de': '⚡ ERZEUGUNG', 'es': '⚡ GENERACIÓN', 'fr': '⚡ PRODUCTION', 'zh': '⚡ 发电侧', 'ja': '⚡ 発電部門', 'ru': '⚡ ГЕНЕРАЦИЯ'},
      'dom_trans': {'tr': '🌐 İLETİM (Transmission)', 'en': '🌐 TRANSMISSION', 'de': '🌐 ÜBERTRAGUNG', 'es': '🌐 TRANSMISIÓN', 'fr': '🌐 TRANSPORT', 'zh': '🌐 输电网', 'ja': '🌐 送電部門', 'ru': '🌐 ТРАНСМИССИЯ'},
      'dom_dist': {'tr': '🏢 DAĞITIM (Distribution)', 'en': '🏢 DISTRIBUTION', 'de': '🏢 VERTEILUNG', 'es': '🏢 DISTRIBUCIÓN', 'fr': '🏢 DISTRIBUTION', 'zh': '🏢 配电与设施', 'ja': '🏢 配電・需要家', 'ru': '🏢 РАСПРЕДЕЛЕНИЕ'},

      'lbl_sys_voltage': {'tr': 'Sistem Gerilimi (kV)', 'en': 'System Voltage (kV)', 'de': 'Netzspannung (kV)', 'es': 'Tensión del Sistema (kV)', 'fr': 'Tension Réseau (kV)', 'zh': '系统额定电压 (kV)', 'ja': '公称系統電圧 (kV)', 'ru': 'Номинальное напряжение (кВ)'},
      'lbl_trafo_power': {'tr': 'Trafo / Santral Gücü (MVA)', 'en': 'Transformer/Plant Rating (MVA)', 'de': 'Transformatorleistung (MVA)', 'es': 'Potencia Trafo (MVA)', 'fr': 'Puissance Transfo (MVA)', 'zh': '变压器/机组容量 (MVA)', 'ja': '変圧器/発電容量 (MVA)', 'ru': 'Мощность трансф./станции (МВА)'},
      'lbl_uk_percent': {'tr': 'Empedans Gerilimi (%uk)', 'en': 'Impedance Voltage (%uk)', 'de': 'Kurzschlussspannung (%uk)', 'es': 'Impedancia (%uk)', 'fr': 'Tension Court-Circuit (%uk)', 'zh': '阻抗电压 (%uk)', 'ja': 'インピーダンス電圧 (%uk)', 'ru': 'Напряжение КЗ (%uk)'},
      'lbl_grid_ssc': {'tr': 'Şebeke Kısa Devre Gücü Ssc (MVA)', 'en': 'Grid Short-Circuit Ssc (MVA)', 'de': 'Netzkurzschlussleistung Ssc (MVA)', 'es': 'Potencia Cortocircuito Ssc (MVA)', 'fr': 'Puissance Court-Circuit Ssc (MVA)', 'zh': '电网短路容量 Ssc (MVA)', 'ja': '系統短絡容量 Ssc (MVA)', 'ru': 'Мощность КЗ сети Ssc (МВА)'},
      'lbl_delta_p': {'tr': 'Şebeke Güç Dengesizliği ΔP (MW)', 'en': 'Grid Power Mismatch ΔP (MW)', 'de': 'Netz-Leistungsungleichgewicht ΔP (MW)', 'es': 'Desbalance de Potencia ΔP (MW)', 'fr': 'Déséquilibre Puissance ΔP (MW)', 'zh': '电网功率缺额 ΔP (MW)', 'ja': '系統電力不平衡 ΔP (MW)', 'ru': 'Дисбаланс мощности ΔP (МВт)'},
      'lbl_gen_mw': {'tr': 'Jeneratör Kapasitesi (MW)', 'en': 'Generator Capacity (MW)', 'de': 'Generatorleistung (MW)', 'es': 'Capacidad Generador (MW)', 'fr': 'Capacité Générateur (MW)', 'zh': '发电机额定容量 (MW)', 'ja': '発電機定格容量 (MW)', 'ru': 'Мощность генератора (МВт)'},

      'verdict_ready': {'tr': 'DEVREYE ALMAYA HAZIR (PASS)', 'en': 'READY FOR COMMISSIONING (PASS)', 'de': 'BEREIT ZUR INBETRIEBNAHME (PASS)', 'es': 'LISTO PARA ENERGIZAR (PASS)', 'fr': 'PRÊT POUR MISE EN SERVICE (PASS)', 'zh': '具备送电投运条件 (PASS)', 'ja': '受電・運用開始可能 (PASS)', 'ru': 'ГОТОВ К ВВОДУ В РАБОТУ (ГОДЕН)'},
      'verdict_not_ready': {'tr': 'DEVREYE ALMAYA UYGUN DEĞİL (FAIL)', 'en': 'NOT READY FOR ENERGIZATION (FAIL)', 'de': 'NICHT BETRIEBSBEREIT (FAIL)', 'es': 'NO APTO PARA ENERGIZAR (FAIL)', 'fr': 'NON CONFORME / DÉFAUT (FAIL)', 'zh': '未达到投运标准 (FAIL)', 'ja': '運用基準不適合 (FAIL)', 'ru': 'НЕ ГОТОВ К ВКЛЮЧЕНИЮ (ДЕФЕКТ)'},
      'save_record': {'tr': 'Mevcut SAT Testini Kaydet', 'en': 'Save Current SAT Record', 'de': 'Messung Speichern', 'es': 'Guardar Registro SAT', 'fr': 'Enregistrer Essai SAT', 'zh': '保存当前试验记录', 'ja': '試験結果を履歴保存', 'ru': 'Сохранить протокол SAT'},
      'copy_protocol': {'tr': 'Resmi Raporu Kopyala (WhatsApp)', 'en': 'Copy Official Report (Share)', 'de': 'Prüfbericht Kopieren', 'es': 'Copiar Protocolo Oficial', 'fr': 'Copier Protocole Officiel', 'zh': '复制正式试验报告', 'ja': '成績書をコピー (共有)', 'ru': 'Копировать официальный отчет'},
    };
    return d[k]?[_lang.name] ?? d[k]?['en'] ?? d[k]?['tr'] ?? k;
  }

  void _saveCurrentSatRecord() {
    final v = _verdict;
    final maxRes = max(p.resR, max(p.resS, p.resT));
    final deltaSyncMs = [(p.timeR - p.timeS).abs(), (p.timeS - p.timeT).abs(), (p.timeR - p.timeT).abs()].reduce(max);

    final newRec = TestRecord(
      timestamp: "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
      substation: p.name,
      breaker: _activeBreaker.name,
      maxRes: maxRes,
      syncDelta: deltaSyncMs,
      passed: v.satDuctor && v.satSync,
    );

    setState(() {
      p.testHistory.insert(0, newRec);
    });
    _showSnack("✓ Test Record Saved & Historical Trend Updated!");
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF00E676), content: Text(msg)));
  }

  // ============================================================================
  // NİHAİ MÜHENDİSLİK KARARI DETAY PENCERESİ (VERDICT MODAL)
  // ============================================================================
  void _showVerdictDetailsModal() {
    final v = _verdict;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111622),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(v.isReadyForCommissioning ? Icons.check_circle : Icons.cancel, color: v.isReadyForCommissioning ? const Color(0xFF00E676) : const Color(0xFFFF3D00)),
                const SizedBox(width: 8),
                const Text("POWERFIELD ENGINEERING VERDICT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFFFB300))),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 16),
            _buildVerdictRow("1. Short-Circuit Breaking (Ik'' ≤ Icu):", "${_ikMaxKa.toStringAsFixed(2)} kA ≤ ${_activeBreaker.ratedBreakingIcuKa} kA", v.shortCircuitIcu),
            _buildVerdictRow("2. Peak Making Current (Ip ≤ Ip_breaker):", "${_ipPeakKa.toStringAsFixed(1)} kA ≤ ${_activeBreaker.peakMakingIpKa} kA", v.shortCircuitIp),
            _buildVerdictRow("3. Protection Selectivity (Δt ≥ 300ms):", "Margin: ${_calcSelectivityMarginMs().toStringAsFixed(0)} ms", v.selectivityMargin),
            _buildVerdictRow("4. Cable Thermal Withstand (Smin):", "Required: ${(_cableEval['sMin'] as double).toStringAsFixed(1)} mm²", v.cableThermal),
            _buildVerdictRow("5. Cable Continuous Ampacity (Iz):", "Load: ${p.loadCurrentA.toInt()} A ≤ ${(_cableEval['deratedIz'] as double).toStringAsFixed(0)} A", v.cableAmpacity),
            _buildVerdictRow("6. Cable Voltage Drop (ΔU% ≤ 3%):", "%${(_cableEval['dropPercent'] as double).toStringAsFixed(2)}", v.cableVoltageDrop),
            _buildVerdictRow("7. SAT Contact Resistance (Ductor):", "Max: ${max(p.resR, max(p.resS, p.resT)).toStringAsFixed(1)} µΩ", v.satDuctor),
            _buildVerdictRow("8. SAT Pole Synchronism (Δt ≤ 3ms):", "Discrepancy: ${[(p.timeR - p.timeS).abs(), (p.timeS - p.timeT).abs(), (p.timeR - p.timeT).abs()].reduce(max).toStringAsFixed(1)} ms", v.satSync),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: v.isReadyForCommissioning ? const Color(0xFF00C853) : const Color(0xFFD50000), borderRadius: BorderRadius.circular(6)),
              child: Center(
                child: Text(
                  v.isReadyForCommissioning ? "STATUS: READY FOR ENERGIZATION" : "STATUS: NOT READY FOR COMMISSIONING",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  double _calcSelectivityMarginMs() {
    final tUp = ElectricalEngine.calcTripTime(faultA: _ikMaxKa * 1000.0, iPickupA: _upPrimaryPickupA, tmsVal: p.upTms, curve: p.upCurve, standard: p.protectionStandard);
    final tDown = ElectricalEngine.calcTripTime(faultA: _ikMaxKa * 1000.0, iPickupA: _downPrimaryPickupA, tmsVal: p.downTms, curve: p.downCurve, standard: p.protectionStandard);
    return (tUp.isFinite && tDown.isFinite) ? ((tUp - tDown) * 1000.0) : 0.0;
  }

  Widget _buildVerdictRow(String title, String val, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.white70)),
          Text("$val ${ok ? '✓ PASS' : '✗ FAIL'}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ok ? Colors.greenAccent : Colors.redAccent)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111622),
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFFFFB300), size: 22),
            const SizedBox(width: 8),
            Text('POWERFIELD PRO v6.3', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: _activeSwitchgear.brandColor)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF30363D)), borderRadius: BorderRadius.circular(6)),
            child: DropdownButton<AppLanguage>(
              value: _lang,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF111622),
              items: const [
                DropdownMenuItem(value: AppLanguage.tr, child: Text('TR 🇹🇷', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.en, child: Text('EN 🇬🇧', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.de, child: Text('DE 🇩🇪', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.es, child: Text('ES 🇪🇸', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.fr, child: Text('FR 🇫🇷', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.zh, child: Text('ZH 🇨🇳', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.ja, child: Text('JA 🇯🇵', style: TextStyle(fontSize: 10))),
                DropdownMenuItem(value: AppLanguage.ru, child: Text('RU 🇷🇺', style: TextStyle(fontSize: 10))),
              ],
              onChanged: (l) => setState(() => _lang = l!),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          _buildDomainLauncher(),
          _buildCommissioningVerdictBadge(),
          Expanded(child: _buildCurrentTab()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111622),
        indicatorColor: _activeSwitchgear.brandColor.withValues(alpha: 0.25),
        selectedIndex: _activeTab,
        onDestinationSelected: (i) => setState(() => _activeTab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_customize), label: t('tab_cockpit')),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: t('tab_relay')),
          NavigationDestination(icon: const Icon(Icons.fact_check_outlined), label: t('tab_sat')),
          NavigationDestination(icon: const Icon(Icons.cable), label: t('tab_cable')),
          NavigationDestination(icon: const Icon(Icons.schema), label: t('tab_sld')),
        ],
      ),
    );
  }

  Widget _buildCommissioningVerdictBadge() {
    final v = _verdict;
    return InkWell(
      onTap: _showVerdictDetailsModal,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        color: v.isReadyForCommissioning ? const Color(0xFF00C853) : const Color(0xFFD50000),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(v.isReadyForCommissioning ? Icons.check_circle : Icons.cancel, size: 13, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  v.isReadyForCommissioning ? t('verdict_ready') : t('verdict_not_ready'),
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.4),
                ),
              ],
            ),
            const Text("Tap for Details ℹ", style: TextStyle(fontSize: 8.5, color: Colors.white70, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainLauncher() {
    return Container(
      color: const Color(0xFF090D14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _buildDomainTab(t('dom_gen'), PowerDomain.generation),
          const SizedBox(width: 4),
          _buildDomainTab(t('dom_trans'), PowerDomain.transmission),
          const SizedBox(width: 4),
          _buildDomainTab(t('dom_dist'), PowerDomain.distribution),
        ],
      ),
    );
  }

  Widget _buildDomainTab(String label, PowerDomain domain) {
    final isSel = p.domain == domain;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            p.domain = domain;
            if (domain == PowerDomain.generation) p.archetype = SubArchetype.solarGES;
            else if (domain == PowerDomain.transmission) { p.archetype = SubArchetype.hvSubstation154; p.voltageKv = 154.0; p.trafoMva = 50.0; }
            else { p.archetype = SubArchetype.heavyIndustry; p.voltageKv = 34.5; p.trafoMva = 2.5; }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFFFFB300) : const Color(0xFF111622),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSel ? const Color(0xFFFFB300) : const Color(0xFF30363D)),
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSel ? Colors.black : Colors.white70)),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_activeTab) {
      case 0: return _buildCockpitTab();
      case 1: return _buildRelayAndTccTab();
      case 2: return _buildBreakerDiagnosticsTab();
      case 3: return _buildCablePowerQualityTab();
      case 4: return _buildSwitchgearSldTab();
      default: return const SizedBox();
    }
  }

  // ============================================================================
  // SEKME 0: KOKPİT (HASSAS SAYISAL GİRİŞ VE ICW/IP DETAYLI)
  // ============================================================================
  Widget _buildCockpitTab() {
    final v = _verdict;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHudCard(
          "IEC 60909 SHORT-CIRCUIT",
          "Ik''max: ${_ikMaxKa.toStringAsFixed(2)} kA",
          "Ik''min: ${_ikMinKa.toStringAsFixed(2)} kA | Ip(Peak): ${_ipPeakKa.toStringAsFixed(1)} kA | Icu Sınırı: ${_activeBreaker.ratedBreakingIcuKa} kA",
          accentColor: (v.shortCircuitIcu && v.shortCircuitIp) ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "EKİPMAN VE HÜCRE YAPILANDIRMASI (PROJE BAZLI)",
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                value: p.switchgearIndex.clamp(0, kSwitchgears.length - 1),
                isExpanded: true,
                dropdownColor: const Color(0xFF111622),
                decoration: _inputDeco(),
                items: List.generate(kSwitchgears.length, (i) => DropdownMenuItem(value: i, child: Text(kSwitchgears[i].name, style: const TextStyle(fontSize: 11)))),
                onChanged: (val) => setState(() => p.switchgearIndex = val!),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: p.breakerIndex.clamp(0, kBreakers.length - 1),
                isExpanded: true,
                dropdownColor: const Color(0xFF111622),
                decoration: _inputDeco(),
                items: List.generate(kBreakers.length, (i) => DropdownMenuItem(value: i, child: Text("${kBreakers[i].name} (Icu=${kBreakers[i].ratedBreakingIcuKa}kA, Ip=${kBreakers[i].peakMakingIpKa}kA)", style: const TextStyle(fontSize: 10)))),
                onChanged: (val) => setState(() => p.breakerIndex = val!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildEditableNumericSlider(t('lbl_sys_voltage'), p.voltageKv, 0.4, 380.0, (val) => setState(() => p.voltageKv = val)),
        _buildEditableNumericSlider(t('lbl_trafo_power'), p.trafoMva, 0.1, 250.0, (val) => setState(() => p.trafoMva = val)),
        _buildEditableNumericSlider(t('lbl_uk_percent'), p.ukPercent, 3.0, 18.0, (val) => setState(() => p.ukPercent = val)),
        _buildEditableNumericSlider(t('lbl_grid_ssc'), p.gridSscMva, 200, 5000, (val) => setState(() => p.gridSscMva = val)),
      ],
    );
  }

  // ============================================================================
  // SEKME 1: RÖLE KOORDİNASYONU & GERÇEK 50/51 TCC ÇİZİMİ
  // ============================================================================
  Widget _buildRelayAndTccTab() {
    final faultA = _ikMaxKa * 1000.0;
    final tUp = ElectricalEngine.calcTripTime(faultA: faultA, iPickupA: _upPrimaryPickupA, tmsVal: p.upTms, curve: p.upCurve, standard: p.protectionStandard);
    final tDown = ElectricalEngine.calcTripTime(faultA: faultA, iPickupA: _downPrimaryPickupA, tmsVal: p.downTms, curve: p.downCurve, standard: p.protectionStandard);
    final deltaT = (tUp.isFinite && tDown.isFinite) ? (tUp - tDown) : 0.0;
    final isSelective = deltaT >= 0.30;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHudCard(
          "COORDINATION MARGIN (Δt)",
          "${(deltaT * 1000).toStringAsFixed(0)} ms",
          isSelective ? "SELECTIVE (Δt ≥ 300ms)" : "COORDINATION MISMATCH (Δt < 300ms)!",
          accentColor: isSelective ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "ANSI 51 (IDMT) & CT SETTINGS",
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildEditableNumericSlider("CT Pri (A)", p.ctPri, 50, 2000, (v) => setState(() => p.ctPri = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildEditableNumericSlider("CT Sec (A)", p.ctSec, 1, 5, (v) => setState(() => p.ctSec = v))),
                ],
              ),
              _buildEditableNumericSlider("Upstream 51 Sec (A)", p.upSettingSecA, 1.0, 15.0, (v) => setState(() => p.upSettingSecA = v)),
              _buildEditableNumericSlider("Upstream TMS", p.upTms, 0.05, 1.2, (v) => setState(() => p.upTms = v)),
              _buildEditableNumericSlider("Downstream 51 Sec (A)", p.downSettingSecA, 0.5, 10.0, (v) => setState(() => p.downSettingSecA = v)),
              _buildEditableNumericSlider("Downstream TMS", p.downTms, 0.05, 1.0, (v) => setState(() => p.downTms = v)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "ANSI 50 (INSTANTANEOUS PICKUP)",
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Downstream 50 Instantaneous Active:", style: TextStyle(fontSize: 10.5)),
                  Switch(value: p.down50Enabled, activeColor: const Color(0xFFFFB300), onChanged: (v) => setState(() => p.down50Enabled = v)),
                ],
              ),
              if (p.down50Enabled)
                _buildEditableNumericSlider("Downstream 50 Pickup (A)", p.down50PickupA, 500, 10000, (v) => setState(() => p.down50PickupA = v)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "LOG-LOG TCC PLOT (50 & 51 INTEGRATED)",
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
            child: CustomPaint(
              painter: LogLogTccPainter(
                upIs: _upPrimaryPickupA,
                upTms: p.upTms,
                upCurve: p.upCurve,
                downIs: _downPrimaryPickupA,
                downTms: p.downTms,
                downCurve: p.downCurve,
                standard: p.protectionStandard,
                faultA: faultA,
                down50Enabled: p.down50Enabled,
                down50PickupA: p.down50PickupA,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // SEKME 2: KESİCİ SAT VE TEST GEÇMİŞİ
  // ============================================================================
  Widget _buildBreakerDiagnosticsTab() {
    final v = _verdict;
    final maxRes = max(p.resR, max(p.resS, p.resT));
    final deltaSyncMs = [(p.timeR - p.timeS).abs(), (p.timeS - p.timeT).abs(), (p.timeR - p.timeT).abs()].reduce(max);

    double? trendDriftPercent;
    if (p.testHistory.isNotEmpty) {
      final prevMax = p.testHistory.first.maxRes;
      if (prevMax > 0) {
        trendDriftPercent = ((maxRes - prevMax) / prevMax) * 100.0;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHudCard(
          "SAT KONTROL: ${_activeBreaker.name}",
          (v.satDuctor && v.satSync) ? "PASS / TESTTEN GEÇTİ" : "FAIL / ŞARTNAME DIŞI",
          "Limit: ≤ ${_activeBreaker.defaultLimitMicroOhm.toInt()} µΩ | Ölçülen: ${maxRes.toStringAsFixed(1)} µΩ | Δt: ${deltaSyncMs.toStringAsFixed(1)}ms",
          accentColor: (v.satDuctor && v.satSync) ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        if (trendDriftPercent != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF161C28), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF30363D))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("📈 Kontak Direnç Aşınma Trendi:", style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                Text(
                  "%${trendDriftPercent.abs().toStringAsFixed(1)} ${trendDriftPercent >= 0 ? 'Artış ⚠' : 'İyileşme ✓'}",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: trendDriftPercent > 10 ? Colors.orangeAccent : Colors.greenAccent),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 40)),
          icon: const Icon(Icons.save, size: 16),
          label: Text(t('save_record'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          onPressed: _saveCurrentSatRecord,
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "Kontak Direnci ve Zamanlama (Hassas Giriş)",
          child: Column(
            children: [
              _buildEditableNumericSlider("R Kutbu (µΩ)", p.resR, 10, 100, (v) => setState(() => p.resR = v)),
              _buildEditableNumericSlider("S Kutbu (µΩ)", p.resS, 10, 100, (v) => setState(() => p.resS = v)),
              _buildEditableNumericSlider("T Kutbu (µΩ)", p.resT, 10, 100, (v) => setState(() => p.resT = v)),
              _buildEditableNumericSlider("tR (ms)", p.timeR, 20, 90, (v) => setState(() => p.timeR = v)),
              _buildEditableNumericSlider("tS (ms)", p.timeS, 20, 90, (v) => setState(() => p.timeS = v)),
              _buildEditableNumericSlider("tT (ms)", p.timeT, 20, 90, (v) => setState(() => p.timeT = v)),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // SEKME 3: KABLO DÖRT KRİTERLİ DEĞERLENDİRME MATRİSİ
  // ============================================================================
  Widget _buildCablePowerQualityTab() {
    final v = _verdict;
    final eval = _cableEval;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHudCard(
          "KABLO MÜHENDİSLİK KARARI",
          "${p.cableSectionMm2.toInt()} mm² ${p.isCopper ? 'Cu' : 'Al'}",
          (v.cableThermal && v.cableAmpacity && v.cableVoltageDrop) ? "TÜM KRİTERLER SAĞLANDI (UYGUN)" : "ŞARTNAME DIŞI (YETERSİZ KESİT)",
          accentColor: (v.cableThermal && v.cableAmpacity && v.cableVoltageDrop) ? const Color(0xFF00E676) : const Color(0xFFFF3D00),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          title: "ÇOK KRİTERLİ TEKNİK KONTROL",
          child: Column(
            children: [
              _buildEvalRow("1. Termik Dayanım (Smin):", "${(eval['sMin'] as double).toStringAsFixed(1)} mm²", v.cableThermal),
              _buildEvalRow("2. Sürekli Akım Kapasitesi (Iz):", "${(eval['deratedIz'] as double).toStringAsFixed(0)} A (Yük: ${p.loadCurrentA.toInt()} A)", v.cableAmpacity),
              _buildEvalRow("3. Gerilim Düşümü (ΔU%):", "%${(eval['dropPercent'] as double).toStringAsFixed(2)} (Sınır: ≤%3.0)", v.cableVoltageDrop),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildEditableNumericSlider("Kablo Kesiti (mm²)", p.cableSectionMm2, 35, 300, (v) => setState(() => p.cableSectionMm2 = v)),
        _buildEditableNumericSlider("Hat Uzunluğu (m)", p.cableLengthM, 10, 2000, (v) => setState(() => p.cableLengthM = v)),
        _buildEditableNumericSlider("Yük Akımı (A)", p.loadCurrentA, 10, 800, (v) => setState(() => p.loadCurrentA = v)),
      ],
    );
  }

  Widget _buildEvalRow(String title, String val, bool isOk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 10.5, color: Colors.white70))),
          Text("$val ${isOk ? '✓ PASS' : '✗ FAIL'}", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isOk ? Colors.greenAccent : Colors.redAccent)),
        ],
      ),
    );
  }

  // ============================================================================
  // SEKME 4: DİNAMİK SLD ŞEMASI
  // ============================================================================
  Widget _buildSwitchgearSldTab() {
    final canvasWidth = max(MediaQuery.of(context).size.width * 1.6, p.cells.length * 125.0 + 100.0);
    const canvasHeight = 330.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF111622),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("BAY LINEUP: ${_activeSwitchgear.name}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _activeSwitchgear.brandColor)),
              Text("${p.voltageKv} kV | Ik'': ${_ikMaxKa.toStringAsFixed(1)} kA", style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF070A0E), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF30363D))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
                    painter: DynamicSwitchgearPainter(cells: p.cells, voltageKv: p.voltageKv, ikKa: _ikMaxKa, switchgear: _activeSwitchgear, breaker: _activeBreaker),
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
            itemCount: p.cells.length,
            itemBuilder: (ctx, i) {
              final c = p.cells[i];
              return Card(
                color: const Color(0xFF111622),
                margin: const EdgeInsets.only(bottom: 4),
                shape: RoundedRectangleBorder(side: BorderSide(color: _activeSwitchgear.brandColor.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(6)),
                child: ListTile(
                  dense: true,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  subtitle: Text("${c.currentVendor} | ${c.currentBreaker} | CT: ${c.ctRatio}", style: const TextStyle(fontSize: 9, color: Colors.grey)),
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

  // ============================================================================
  // HASSAS MÜHENDİSLİK SAYISAL GİRİŞ + SLIDER WIDGETI (UX ÇÖZÜMÜ)
  // ============================================================================
  Widget _buildEditableNumericSlider(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
              InkWell(
                onTap: () {
                  final tc = TextEditingController(text: val.toStringAsFixed(1));
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF111622),
                      title: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      content: TextField(
                        controller: tc,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        autofocus: true,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
                          onPressed: () {
                            final parsed = double.tryParse(tc.text.replaceAll(',', '.'));
                            if (parsed != null) {
                              onChanged(parsed.clamp(min, max));
                            }
                            Navigator.pop(ctx);
                          },
                          child: const Text("Uygula"),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF161C28), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFFB300))),
                  child: Text("[ ${val.toStringAsFixed(1)} ]", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300), fontSize: 11)),
                ),
              ),
            ],
          ),
          Slider(value: val.clamp(min, max), min: min, max: max, activeColor: const Color(0xFFFFB300), inactiveColor: const Color(0xFF30363D), onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildHudCard(String title, String value, String sub, {Color accentColor = const Color(0xFFFFB300)}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(10), border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: accentColor)),
          const SizedBox(height: 2),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF111622), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363D))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70)), const SizedBox(height: 6), child]),
    );
  }

  InputDecoration _inputDeco() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: const Color(0xFF070A0E),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFFFB300))),
    );
  }
}

// ============================================================================
// 6. TCC ÇİZİCİSİ (IDMT VE GERÇEK 50 INSTANTANEOUS ÇİZGİSİ ENTEGRE)
// ============================================================================
class LogLogTccPainter extends CustomPainter {
  final double upIs;
  final double upTms;
  final TripCurve upCurve;
  final double downIs;
  final double downTms;
  final TripCurve downCurve;
  final ProtectionStandard standard;
  final double faultA;
  final bool down50Enabled;
  final double down50PickupA;

  LogLogTccPainter({
    required this.upIs,
    required this.upTms,
    required this.upCurve,
    required this.downIs,
    required this.downTms,
    required this.downCurve,
    required this.standard,
    required this.faultA,
    required this.down50Enabled,
    required this.down50PickupA,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gridPaint = Paint()..color = const Color(0xFF21262D)..strokeWidth = 1.0;
    final axisPaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 1.5;

    double logX(double a) => (log(max(a, 10.0)) / ln10 - 1.0) / 3.0 * (w - 40) + 30;
    double logY(double t) => h - 20 - ((log(max(t, 0.01)) / ln10 + 2.0) / 4.0 * (h - 30));

    for (int p = 1; p <= 4; p++) {
      final x = logX(pow(10, p).toDouble());
      canvas.drawLine(Offset(x, 10), Offset(x, h - 20), gridPaint);
    }
    for (int p = -2; p <= 2; p++) {
      final y = logY(pow(10, p).toDouble());
      canvas.drawLine(Offset(30, y), Offset(w - 10, y), gridPaint);
    }

    canvas.drawLine(Offset(30, 10), Offset(30, h - 20), axisPaint);
    canvas.drawLine(Offset(30, h - 20), Offset(w - 10, h - 20), axisPaint);

    // Upstream 51 (Kırmızı)
    final upPaint = Paint()..color = const Color(0xFFFF3D00)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final upPath = Path();
    bool upStarted = false;
    for (double i = upIs * 1.05; i <= 10000; i += (i < 1000 ? 50 : 250)) {
      final t = ElectricalEngine.calcTripTime(faultA: i, iPickupA: upIs, tmsVal: upTms, curve: upCurve, standard: standard);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!upStarted) { upPath.moveTo(pt.dx, pt.dy); upStarted = true; } else { upPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(upPath, upPaint);

    // Downstream 51 (Yeşil) + 50 Kesme Çizgisi
    final downPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final downPath = Path();
    bool downStarted = false;
    final max51Current = down50Enabled ? min(down50PickupA, 10000.0) : 10000.0;

    for (double i = downIs * 1.05; i <= max51Current; i += (i < 1000 ? 30 : 200)) {
      final t = ElectricalEngine.calcTripTime(faultA: i, iPickupA: downIs, tmsVal: downTms, curve: downCurve, standard: standard);
      if (t.isFinite && t <= 100 && t >= 0.01) {
        final pt = Offset(logX(i), logY(t));
        if (!downStarted) { downPath.moveTo(pt.dx, pt.dy); downStarted = true; } else { downPath.lineTo(pt.dx, pt.dy); }
      }
    }
    canvas.drawPath(downPath, downPaint);

    // Gerçek ANSI 50 Çizgisi (Dikey Kesme ve 50ms Definitive Bandı)
    if (down50Enabled && down50PickupA <= 10000) {
      final instPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.8..style = PaintingStyle.stroke;
      final instX = logX(down50PickupA);
      final tCut = ElectricalEngine.calcTripTime(faultA: down50PickupA, iPickupA: downIs, tmsVal: downTms, curve: downCurve, standard: standard);
      final instYCut = logY(tCut.isFinite ? tCut : 1.0);
      final instYFloor = logY(0.05); // 50 ms kesin açma süresi

      canvas.drawLine(Offset(instX, instYCut), Offset(instX, instYFloor), instPaint);
      canvas.drawLine(Offset(instX, instYFloor), Offset(logX(10000), instYFloor), instPaint);
    }

    if (faultA >= 10 && faultA <= 10000) {
      final xFault = logX(faultA);
      final faultPaint = Paint()..color = Colors.white..strokeWidth = 1.2;
      canvas.drawLine(Offset(xFault, 15), Offset(xFault, h - 20), faultPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ============================================================================
// 7. DİNAMİK SLD ÇİZİCİSİ
// ============================================================================
class DynamicSwitchgearPainter extends CustomPainter {
  final List<SwitchgearCell> cells;
  final double voltageKv;
  final double ikKa;
  final SwitchgearModel switchgear;
  final BreakerModel breaker;

  DynamicSwitchgearPainter({required this.cells, required this.voltageKv, required this.ikKa, required this.switchgear, required this.breaker});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final busY = h * 0.42;
    const bayWidth = 125.0;

    final busPaint = Paint()..color = switchgear.brandColor..strokeWidth = 4.0;
    final linePaint = Paint()..color = const Color(0xFF8B949E)..strokeWidth = 1.8..style = PaintingStyle.stroke;

    final totalBusWidth = max(size.width, (cells.length + 1) * bayWidth);
    canvas.drawLine(Offset(25, busY), Offset(totalBusWidth - 25, busY), busPaint);

    for (int i = 0; i < cells.length; i++) {
      final x = 65.0 + (i * bayWidth);
      final cell = cells[i];

      final borderPaint = Paint()..color = switchgear.brandColor.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1.0;
      canvas.drawRect(Rect.fromLTWH(x - (bayWidth / 2) + 6, 28, bayWidth - 12, h - 40), borderPaint);

      _drawText(canvas, cell.name, Offset(x - 48, 34), Colors.white, 9, bold: true);
      _drawText(canvas, "[${switchgear.vendor} - ${breaker.name}]", Offset(x - 52, 46), switchgear.brandColor, 7.5);

      if (cell.type == CellType.incomer) {
        canvas.drawLine(Offset(x, 60), Offset(x, busY - 16), linePaint);
        _drawBreaker(canvas, Offset(x, busY - 24), cell.cbClosed);
        canvas.drawLine(Offset(x, busY - 16), Offset(x, busY), linePaint);
      } else if (cell.type == CellType.coupler) {
        _drawBreaker(canvas, Offset(x, busY), cell.cbClosed);
      } else {
        canvas.drawLine(Offset(x, busY), Offset(x, busY + 22), linePaint);
        _drawBreaker(canvas, Offset(x, busY + 30), cell.cbClosed);
        canvas.drawLine(Offset(x, busY + 38), Offset(x, h * 0.82), linePaint);
        canvas.drawCircle(Offset(x, busY + 52), 4.0, linePaint);
        canvas.drawCircle(Offset(x, busY + 60), 4.0, linePaint);
        _drawText(canvas, cell.ctRatio, Offset(x + 8, busY + 50), Colors.grey, 7.5);
      }
    }
  }

  void _drawBreaker(Canvas canvas, Offset center, bool isClosed) {
    final rect = Rect.fromCenter(center: center, width: 15, height: 15);
    final fill = Paint()..color = isClosed ? const Color(0xFFFF3D00) : const Color(0xFF00E676);
    final stroke = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
    if (!isClosed) {
      canvas.drawLine(Offset(center.dx - 4, center.dy - 4), Offset(center.dx + 4, center.dy + 4), stroke);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
