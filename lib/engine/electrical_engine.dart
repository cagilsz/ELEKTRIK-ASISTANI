// Konum: lib/engine/electrical_engine.dart

import 'dart:math';

enum ProtectionStandard { iec60255, ieeeC37112 }
enum TripCurve { standardInverse, veryInverse, extremelyInverse, longTimeInverse }

class ElectricalEngine {
  /// Simplified preliminary IEC 60909 model.
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

    final zMax = zQ + zT;
    final ikMax = (1.10 * v) / (sqrt(3) * zMax);

    final rHot = rT * 1.24;
    final zTHot = sqrt(rHot * rHot + xT * xT);
    final zMin = zQ + zTHot;
    final ikMin = v / (sqrt(3) * zMin);

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

  static double calcAltitudeDeratingFactor(double altitudeMeters) {
    if (altitudeMeters <= 1000) return 1;
    return max(.60, 1 - (altitudeMeters - 1000) * .00004);
  }
}
