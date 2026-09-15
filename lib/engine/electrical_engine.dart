```dart
// lib/engine/electrical_engine.dart

import 'dart:math';

// =============================================================================
// ENUMS
// =============================================================================

enum ProtectionStandard {
  iec60255,
  ieeeC37112,
}

enum TripCurve {
  standardInverse,
  veryInverse,
  extremelyInverse,
  longTimeInverse,
}

enum CableInstallationMethod {
  methodD_underground,
  methodE_freeAir,
  methodC_onWall,
}

enum ComplianceStatus {
  pass,
  warning,
  fail,
  notVerified,
}

enum NetworkNodeType {
  grid,
  bus,
  transformer,
  cable,
  breaker,
  generator,
  load,
  generic,
}

enum NetworkBranchType {
  gridSource,
  transformer,
  cable,
  line,
  breaker,
  busTie,
  generator,
  generic,
}

// =============================================================================
// 1. IMPEDANCE
// =============================================================================

class Impedance {
  final double r;
  final double x;

  const Impedance(this.r, this.x);

  Impedance operator +(Impedance other) {
    return Impedance(
      r + other.r,
      x + other.x,
    );
  }

  double get z => sqrt(r * r + x * x);

  double get xrRatio {
    if (r.abs() < 1e-12) {
      return double.infinity;
    }
    return x / r;
  }

  bool get isValid {
    return r.isFinite &&
        x.isFinite &&
        r >= 0 &&
        x >= 0 &&
        z.isFinite;
  }

  /// Paralel empedans:
  /// Z = Z1 * Z2 / (Z1 + Z2)
  Impedance parallel(Impedance other) {
    final denominatorR = r + other.r;
    final denominatorX = x + other.x;

    final denominator =
        denominatorR * denominatorR +
        denominatorX * denominatorX;

    if (denominator <= 1e-18 ||
        !denominator.isFinite) {
      return const Impedance(
        double.infinity,
        double.infinity,
      );
    }

    final numeratorR =
        r * other.r - x * other.x;

    final numeratorX =
        r * other.x + x * other.r;

    return Impedance(
      (numeratorR * denominatorR +
              numeratorX * denominatorX) /
          denominator,
      (numeratorX * denominatorR -
              numeratorR * denominatorX) /
          denominator,
    );
  }

  @override
  String toString() {
    return 'R=${r.toStringAsFixed(6)} Ω, '
        'X=${x.toStringAsFixed(6)} Ω, '
        'Z=${z.toStringAsFixed(6)} Ω';
  }
}

// =============================================================================
// 2. NETWORK NODE
// =============================================================================

class NetworkNode {
  final String id;
  final String name;
  final NetworkNodeType type;
  final double nominalVoltageKv;

  double activePowerMw;
  double powerFactor;

  NetworkNode({
    required this.id,
    required this.name,
    required this.type,
    required this.nominalVoltageKv,
    this.activePowerMw = 0.0,
    this.powerFactor = 1.0,
  });

  bool get isValid {
    return id.isNotEmpty &&
        name.isNotEmpty &&
        nominalVoltageKv.isFinite &&
        nominalVoltageKv > 0;
  }

  @override
  String toString() {
    return '$id ($name)';
  }
}

// =============================================================================
// 3. NETWORK BRANCH
// =============================================================================

class NetworkBranch {
  final String id;
  final String name;

  final String fromNodeId;
  final String toNodeId;

  final NetworkBranchType type;

  final Impedance impedance;

  bool inService;

  final double lengthKm;

  NetworkBranch({
    required this.id,
    required this.name,
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.impedance,
    this.inService = true,
    this.lengthKm = 0.0,
  });

  bool get isValid {
    return id.isNotEmpty &&
        fromNodeId.isNotEmpty &&
        toNodeId.isNotEmpty &&
        fromNodeId != toNodeId &&
        impedance.isValid;
  }

  String otherNode(String nodeId) {
    if (nodeId == fromNodeId) {
      return toNodeId;
    }

    if (nodeId == toNodeId) {
      return fromNodeId;
    }

    throw ArgumentError(
      'Node $nodeId bu branch üzerinde bulunmuyor.',
    );
  }
}

// =============================================================================
// 4. NETWORK GRAPH
// =============================================================================

class NetworkGraph {
  final Map<String, NetworkNode> _nodes = {};
  final Map<String, NetworkBranch> _branches = {};

  // ---------------------------------------------------------------------------
  // NODE
  // ---------------------------------------------------------------------------

  void addNode(NetworkNode node) {
    if (!node.isValid) {
      throw ArgumentError(
        'Geçersiz network node: ${node.id}',
      );
    }

    _nodes[node.id] = node;
  }

  NetworkNode? getNode(String id) {
    return _nodes[id];
  }

  bool containsNode(String id) {
    return _nodes.containsKey(id);
  }

  List<NetworkNode> get nodes {
    return List.unmodifiable(
      _nodes.values,
    );
  }

  // ---------------------------------------------------------------------------
  // BRANCH
  // ---------------------------------------------------------------------------

  void addBranch(NetworkBranch branch) {
    if (!branch.isValid) {
      throw ArgumentError(
        'Geçersiz network branch: ${branch.id}',
      );
    }

    if (!containsNode(branch.fromNodeId) ||
        !containsNode(branch.toNodeId)) {
      throw ArgumentError(
        'Branch node referansı bulunamadı: '
        '${branch.fromNodeId} -> ${branch.toNodeId}',
      );
    }

    _branches[branch.id] = branch;
  }

  NetworkBranch? getBranch(String id) {
    return _branches[id];
  }

  List<NetworkBranch> get branches {
    return List.unmodifiable(
      _branches.values,
    );
  }

  // ---------------------------------------------------------------------------
  // CONNECTED BRANCHES
  // ---------------------------------------------------------------------------

  List<NetworkBranch> connectedBranches(
    String nodeId,
  ) {
    return _branches.values
        .where(
          (branch) =>
              branch.inService &&
              (branch.fromNodeId == nodeId ||
                  branch.toNodeId == nodeId),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // SOURCE PATHS
  // ---------------------------------------------------------------------------

  List<List<NetworkBranch>> findPathsToSources(
    String targetNodeId,
  ) {
    final paths =
        <List<NetworkBranch>>[];

    if (!containsNode(targetNodeId)) {
      return paths;
    }

    void dfs(
      String currentNodeId,
      List<NetworkBranch> currentPath,
      Set<String> visitedNodes,
    ) {
      final node =
          getNode(currentNodeId);

      if (node == null) {
        return;
      }

      if (node.type ==
          NetworkNodeType.grid) {
        paths.add(
          List<NetworkBranch>.from(
            currentPath,
          ),
        );
        return;
      }

      for (final branch
          in connectedBranches(currentNodeId)) {
        final nextNode =
            branch.otherNode(
          currentNodeId,
        );

        if (visitedNodes.contains(
          nextNode,
        )) {
          continue;
        }

        final nextVisited =
            Set<String>.from(
          visitedNodes,
        );

        nextVisited.add(nextNode);

        final nextPath =
            List<NetworkBranch>.from(
          currentPath,
        );

        nextPath.add(branch);

        dfs(
          nextNode,
          nextPath,
          nextVisited,
        );
      }
    }

    dfs(
      targetNodeId,
      [],
      {targetNodeId},
    );

    return paths;
  }

  // ---------------------------------------------------------------------------
  // PATH IMPEDANCE
  // ---------------------------------------------------------------------------

  Impedance pathImpedance(
    List<NetworkBranch> path,
  ) {
    var result =
        const Impedance(0.0, 0.0);

    for (final branch in path) {
      result += branch.impedance;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // THEVENIN IMPEDANCE
  //
  // Birden fazla kaynak yolu varsa paralel eşdeğer alınır.
  // ---------------------------------------------------------------------------

  Impedance calculateTheveninImpedance(
    String targetNodeId,
  ) {
    final paths =
        findPathsToSources(
      targetNodeId,
    );

    if (paths.isEmpty) {
      return const Impedance(
        double.infinity,
        double.infinity,
      );
    }

    var equivalent =
        pathImpedance(paths.first);

    for (var i = 1;
        i < paths.length;
        i++) {
      equivalent =
          equivalent.parallel(
        pathImpedance(paths[i]),
      );
    }

    return equivalent;
  }

  // ---------------------------------------------------------------------------
  // VALIDATION
  // ---------------------------------------------------------------------------

  List<String> validate() {
    final errors = <String>[];

    for (final node in _nodes.values) {
      if (!node.isValid) {
        errors.add(
          'Geçersiz node: ${node.id}',
        );
      }
    }

    for (final branch in _branches.values) {
      if (!branch.isValid) {
        errors.add(
          'Geçersiz branch: ${branch.id}',
        );
      }

      if (!containsNode(
            branch.fromNodeId,
          ) ||
          !containsNode(
            branch.toNodeId,
          )) {
        errors.add(
          'Branch ${branch.id}: node referansı eksik.',
        );
      }
    }

    return errors;
  }
}

// =============================================================================
// 5. NETWORK BUILDER
//
// SLD / proje bilgisini NetworkGraph'a dönüştürmek için ortak giriş noktası.
// =============================================================================

class NetworkBuilder {
  final NetworkGraph graph =
      NetworkGraph();

  NetworkBuilder addGrid({
    required String id,
    required String name,
    required double voltageKv,
    required double sscMva,
    double xrRatio = 10.0,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.grid,
        nominalVoltageKv: voltageKv,
      ),
    );

    return this;
  }

  NetworkBuilder addBus({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.bus,
        nominalVoltageKv: voltageKv,
      ),
    );

    return this;
  }

  NetworkBuilder addLoad({
    required String id,
    required String name,
    required double voltageKv,
    required double activePowerMw,
    required double powerFactor,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.load,
        nominalVoltageKv: voltageKv,
        activePowerMw: activePowerMw,
        powerFactor: powerFactor,
      ),
    );

    return this;
  }

  NetworkBuilder connect({
    required String id,
    required String name,
    required String from,
    required String to,
    required NetworkBranchType type,
    required Impedance impedance,
    bool inService = true,
    double lengthKm = 0.0,
  }) {
    graph.addBranch(
      NetworkBranch(
        id: id,
        name: name,
        fromNodeId: from,
        toNodeId: to,
        type: type,
        impedance: impedance,
        inService: inService,
        lengthKm: lengthKm,
      ),
    );

    return this;
  }

  NetworkGraph build() {
    return graph;
  }
}

// =============================================================================
// 6. IMPEDANCE FACTORY
// =============================================================================

class ImpedanceFactory {
  static Impedance grid({
    required double voltageKv,
    required double sscMva,
    double xrRatio = 10.0,
  }) {
    if (voltageKv <= 0 ||
        sscMva <= 0 ||
        xrRatio <= 0) {
      return const Impedance(
        double.infinity,
        double.infinity,
      );
    }

    final z =
        voltageKv * voltageKv /
            sscMva;

    final x =
        z /
            sqrt(
              1.0 +
                  1.0 /
                      (xrRatio *
                          xrRatio),
            );

    final r =
        x / xrRatio;

    return Impedance(r, x);
  }

  static Impedance transformer({
    required double voltageKv,
    required double ratedMva,
    required double ukPercent,
    double xrRatio = 8.0,
  }) {
    if (voltageKv <= 0 ||
        ratedMva <= 0 ||
        ukPercent <= 0 ||
        xrRatio <= 0) {
      return const Impedance(
        double.infinity,
        double.infinity,
      );
    }

    final z =
        (ukPercent / 100.0) *
            (voltageKv *
                    voltageKv /
                ratedMva);

    final r =
        z /
            sqrt(
              1.0 +
                  xrRatio *
                      xrRatio,
            );

    final x =
        r * xrRatio;

    return Impedance(r, x);
  }

  static Impedance cable({
    required double lengthKm,
    required double rOhmPerKm,
    required double xOhmPerKm,
  }) {
    if (lengthKm < 0 ||
        rOhmPerKm < 0 ||
        xOhmPerKm < 0) {
      return const Impedance(
        double.infinity,
        double.infinity,
      );
    }

    return Impedance(
      lengthKm * rOhmPerKm,
      lengthKm * xOhmPerKm,
    );
  }
}

// =============================================================================
// 7. SHORT CIRCUIT
// =============================================================================

class ShortCircuitEngine {
  static Map<String, double>
      calcFaultAtNode({
    required NetworkGraph graph,
    required String faultNodeId,
  }) {
    final node =
        graph.getNode(faultNodeId);

    if (node == null ||
        !node.isValid) {
      return _zero();
    }

    final voltageKv =
        node.nominalVoltageKv;

    final zTotal =
        graph.calculateTheveninImpedance(
      faultNodeId,
    );

    if (!zTotal.isValid ||
        zTotal.z <= 0 ||
        !zTotal.z.isFinite) {
      return _zero();
    }

    final cMax =
        voltageKv > 1.0
            ? 1.10
            : 1.05;

    final ikMax =
        cMax * voltageKv /
            (sqrt(3.0) * zTotal.z);

    final xr =
        zTotal.r > 0
            ? zTotal.x / zTotal.r
            : 100.0;

    final safeXr =
        max(xr, 0.001);

    final kappa =
        1.02 +
            0.98 *
                exp(
                  -3.0 /
                      safeXr,
                );

    final ipPeak =
        sqrt(2.0) *
            kappa *
            ikMax;

    final rHot =
        zTotal.r * 1.24;

    final zHot =
        sqrt(
      rHot * rHot +
          zTotal.x *
              zTotal.x,
    );

    final ikMin =
        zHot > 0
            ? voltageKv /
                (sqrt(3.0) * zHot)
            : 0.0;

    return {
      'Ik_max': ikMax,
      'Ik_min': ikMin,
      'Ip_peak': ipPeak,
      'kappa': kappa,
      'R_total': zTotal.r,
      'X_total': zTotal.x,
      'Z_total': zTotal.z,
      'X_R_ratio': xr,
    };
  }

  static Map<String, double> _zero() {
    return {
      'Ik_max': 0.0,
      'Ik_min': 0.0,
      'Ip_peak': 0.0,
      'kappa': 1.0,
      'R_total': 0.0,
      'X_total': 0.0,
      'Z_total': 0.0,
      'X_R_ratio': 0.0,
    };
  }
}

// =============================================================================
// 8. CABLE
// =============================================================================

class CableEngine {
  static const List<double>
      standardSizes = [
    1.5,
    2.5,
    4.0,
    6.0,
    10.0,
    16.0,
    25.0,
    35.0,
    50.0,
    70.0,
    95.0,
    120.0,
    150.0,
    185.0,
    240.0,
    300.0,
    400.0,
    500.0,
    630.0,
  ];

  static const Map<
      CableInstallationMethod,
      Map<double, double>>
      iecAmpacityTablesCu = {
    CableInstallationMethod.methodE_freeAir: {
      16: 96,
      25: 130,
      35: 162,
      50: 197,
      70: 250,
      95: 308,
      120: 359,
      150: 412,
      185: 475,
      240: 559,
      300: 647,
    },

    CableInstallationMethod.methodD_underground: {
      16: 73,
      25: 95,
      35: 114,
      50: 135,
      70: 167,
      95: 199,
      120: 227,
      150: 255,
      185: 289,
      240: 333,
      300: 379,
    },
  };

  static const Map<
      CableInstallationMethod,
      Map<double, double>>
      iecAmpacityTablesAl = {
    CableInstallationMethod.methodE_freeAir: {
      16: 74,
      25: 101,
      35: 126,
      50: 153,
      70: 196,
      95: 238,
      120: 276,
      150: 319,
      185: 364,
      240: 430,
      300: 497,
    },

    CableInstallationMethod.methodD_underground: {
      16: 57,
      25: 74,
      35: 89,
      50: 105,
      70: 130,
      95: 155,
      120: 177,
      150: 199,
      185: 226,
      240: 261,
      300: 298,
    },
  };

  static Map<String, dynamic>
      evaluateSizing({
    required double inputSectionMm2,
    required double lengthM,
    required double loadCurrentA,
    required double voltageKv,
    required double ikKa,
    required double faultTimeSec,
    required bool isCopper,
    required CableInstallationMethod method,
    double ambientTempC = 30.0,
    double groupingFactor = 1.0,
    double powerFactor = 0.85,
  }) {
    if (inputSectionMm2 <= 0 ||
        lengthM < 0 ||
        loadCurrentA < 0 ||
        voltageKv <= 0 ||
        ikKa < 0 ||
        faultTimeSec <= 0 ||
        groupingFactor <= 0 ||
        groupingFactor > 1 ||
        powerFactor <= 0 ||
        powerFactor > 1) {
      return {
        'status':
            ComplianceStatus.notVerified,
        'message':
            'Geçersiz kablo hesap girdileri.',
      };
    }

    final section =
        standardSizes.firstWhere(
      (s) =>
          s >= inputSectionMm2,
      orElse: () =>
          standardSizes.last,
    );

    final k =
        isCopper
            ? 143.0
            : 94.0;

    final sMin =
        ikKa *
            1000.0 *
            sqrt(faultTimeSec) /
            k;

    final thermalOk =
        section >= sMin;

    final table = isCopper
        ? iecAmpacityTablesCu[
            method]
        : iecAmpacityTablesAl[
            method];

    if (table == null) {
      return {
        'actualSectionMm2': section,
        'sMin': sMin,
        'isThermalOk': thermalOk,
        'status':
            ComplianceStatus.notVerified,
        'message':
            'Bu montaj yöntemi için doğrulanmış tablo bulunamadı.',
      };
    }

    final baseIz =
        table[section];

    if (baseIz == null) {
      return {
        'actualSectionMm2': section,
        'sMin': sMin,
        'isThermalOk': thermalOk,
        'status':
            ComplianceStatus.notVerified,
        'message':
            'Bu kesit için doğrulanmış akım taşıma verisi bulunamadı.',
      };
    }

    final kt =
        ambientTempC <= 30.0
            ? 1.0
            : ambientTempC >= 90.0
                ? 0.0
                : sqrt(
                    (90.0 -
                            ambientTempC) /
                        60.0,
                  );

    final iz =
        baseIz *
            kt *
            groupingFactor;

    final ampacityOk =
        loadCurrentA <= iz;

    final rho =
        isCopper
            ? 0.0225
            : 0.0360;

    final r =
        rho *
            lengthM /
            section;

    final x =
        0.08 *
            lengthM /
            1000.0;

    final sinPhi =
        sqrt(
      max(
        0.0,
        1.0 -
            powerFactor *
                powerFactor,
      ),
    );

    final du =
        sqrt(3.0) *
            loadCurrentA *
            (r * powerFactor +
                x * sinPhi);

    final drop =
        du /
            (voltageKv * 1000.0) *
            100.0;

    final voltageDropOk =
        drop <= 3.0;

    final status =
        thermalOk &&
                ampacityOk &&
                voltageDropOk
            ? ComplianceStatus.pass
            : ComplianceStatus.fail;

    return {
      'actualSectionMm2': section,
      'sMin': sMin,
      'isThermalOk': thermalOk,
      'baseIz': baseIz,
      'ambientFactor': kt,
      'groupingFactor':
          groupingFactor,
      'deratedIz': iz,
      'isAmpacityOk':
          ampacityOk,
      'dropPercent': drop,
      'isVoltageDropOk':
          voltageDropOk,
      'status': status,
    };
  }
}

// =============================================================================
// 9. LOAD FLOW
// =============================================================================

class LoadFlowEngine {
  static Map<String, double>
      calcLoadFlowAtNode({
    required NetworkGraph graph,
    required String receivingNodeId,
    required double activePowerMw,
    required double powerFactor,
  }) {
    final node =
        graph.getNode(
      receivingNodeId,
    );

    if (node == null ||
        !node.isValid ||
        activePowerMw < 0 ||
        powerFactor <= 0 ||
        powerFactor > 1) {
      return {
        'currentA': 0.0,
        'qMvar': 0.0,
        'sMva': 0.0,
        'sendingKv': 0.0,
        'receivingKv': 0.0,
        'dropPercent': 0.0,
        'lossMw': 0.0,
      };
    }

    final voltageKv =
        node.nominalVoltageKv;

    final pf =
        powerFactor.clamp(
      0.2,
      1.0,
    );

    final qMvar =
        activePowerMw *
            sqrt(
              max(
                0.0,
                1.0 /
                        (pf * pf) -
                    1.0,
              ),
            );

    final sMva =
        sqrt(
      activePowerMw *
              activePowerMw +
          qMvar * qMvar,
    );

    final currentA =
        sMva *
            1000.0 /
            (sqrt(3.0) *
                voltageKv);

    final z =
        graph.calculateTheveninImpedance(
      receivingNodeId,
    );

    if (!z.isValid) {
      return {
        'currentA': currentA,
        'qMvar': qMvar,
        'sMva': sMva,
        'sendingKv': voltageKv,
        'receivingKv': voltageKv,
        'dropPercent': 0.0,
        'lossMw': 0.0,
      };
    }

    final sinPhi =
        sqrt(
      max(
        0.0,
        1.0 - pf * pf,
      ),
    );

    final duKv =
        sqrt(3.0) *
            currentA *
            (z.r * pf +
                z.x * sinPhi) /
            1000.0;

    final receivingKv =
        max(
      0.001,
      voltageKv - duKv,
    );

    final dropPercent =
        100.0 *
            duKv /
            voltageKv;

    final lossMw =
        3.0 *
            currentA *
            currentA *
            z.r /
            1e6;

    return {
      'currentA': currentA,
      'qMvar': qMvar,
      'sMva': sMva,
      'sendingKv': voltageKv,
      'receivingKv': receivingKv,
      'dropPercent': dropPercent,
      'lossMw': lossMw,
    };
  }
}

// =============================================================================
// 10. EQUIPMENT
// =============================================================================

class EquipmentEngine {
  static ComplianceStatus
      validateBreaker({
    required double calculatedIkKa,
    required double calculatedIpKa,
    required double breakerIcwKa,
    required double breakerIcuKa,
    required double breakerIpKa,
    required double altitudeM,
    double? manufacturerDeratingFactor,
    double? faultDurationSec,
  }) {
    if (![
      calculatedIkKa,
      calculatedIpKa,
      breakerIcwKa,
      breakerIcuKa,
      breakerIpKa,
      altitudeM,
    ].every(
      (v) => v.isFinite && v >= 0,
    )) {
      return ComplianceStatus.notVerified;
    }

    if (altitudeM > 1000.0 &&
        manufacturerDeratingFactor ==
            null) {
      return ComplianceStatus.notVerified;
    }

    final derating =
        manufacturerDeratingFactor ??
            1.0;

    if (derating <= 0 ||
        derating > 1 ||
        !derating.isFinite) {
      return ComplianceStatus.notVerified;
    }

    final actualIcu =
        breakerIcuKa * derating;

    final actualIcw =
        breakerIcwKa * derating;

    if (calculatedIpKa >
        breakerIpKa) {
      return ComplianceStatus.fail;
    }

    if (calculatedIkKa >
        actualIcu) {
      return ComplianceStatus.fail;
    }

    if (faultDurationSec != null) {
      if (!faultDurationSec.isFinite ||
          faultDurationSec <= 0) {
        return ComplianceStatus.notVerified;
      }

      if (calculatedIkKa >
          actualIcw) {
        return ComplianceStatus.fail;
      }
    } else if (calculatedIkKa >
        actualIcw) {
      return ComplianceStatus.warning;
    }

    return ComplianceStatus.pass;
  }
}

// =============================================================================
// 11. PROTECTION
// =============================================================================

class ProtectionEngine {
  static double calcTripTime({
    required double faultA,
    required double iPickupA,
    required double tmsVal,
    required TripCurve curve,
    ProtectionStandard standard =
        ProtectionStandard.iec60255,
  }) {
    if (!faultA.isFinite ||
        !iPickupA.isFinite ||
        !tmsVal.isFinite ||
        faultA <= iPickupA ||
        iPickupA <= 0 ||
        tmsVal <= 0) {
      return double.infinity;
    }

    final m =
        faultA / iPickupA;

    if (!m.isFinite || m <= 1.0) {
      return double.infinity;
    }

    if (standard ==
        ProtectionStandard.iec60255) {
      double k = 0.14;
      double alpha = 0.02;

      switch (curve) {
        case TripCurve.standardInverse:
          k = 0.14;
          alpha = 0.02;
          break;

        case TripCurve.veryInverse:
          k = 13.5;
          alpha = 1.0;
          break;

        case TripCurve.extremelyInverse:
          k = 80.0;
          alpha = 2.0;
          break;

        case TripCurve.longTimeInverse:
          k = 120.0;
          alpha = 1.0;
          break;
      }

      final denominator =
          pow(m, alpha) - 1.0;

      if (!denominator.isFinite ||
          denominator <= 0) {
        return double.infinity;
      }

      return tmsVal *
          k /
          denominator;
    }

    double a = 0.0515;
    double b = 0.114;
    double p = 0.02;

    switch (curve) {
      case TripCurve.standardInverse:
        a = 0.0515;
        b = 0.114;
        p = 0.02;
        break;

      case TripCurve.veryInverse:
        a = 19.61;
        b = 0.491;
        p = 2.0;
        break;

      case TripCurve.extremelyInverse:
        a = 28.2;
        b = 0.1217;
        p = 2.0;
        break;

      case TripCurve.longTimeInverse:
        a = 120.0;
        b = 0.0;
        p = 1.0;
        break;
    }

    final denominator =
        pow(m, p) - 1.0;

    if (!denominator.isFinite ||
        denominator <= 0) {
      return double.infinity;
    }

    return tmsVal *
        (a / denominator + b);
  }
}

// =============================================================================
// 12. NETWORK ANALYSIS
// =============================================================================

class NetworkAnalysisEngine {
  static Map<String, dynamic>
      analyzeFault({
    required NetworkGraph graph,
    required String faultNodeId,
  }) {
    final errors =
        graph.validate();

    if (errors.isNotEmpty) {
      return {
        'status':
            ComplianceStatus.notVerified,
        'errors': errors,
      };
    }

    final node =
        graph.getNode(
      faultNodeId,
    );

    if (node == null) {
      return {
        'status':
            ComplianceStatus.notVerified,
        'errors': [
          'Fault node bulunamadı: $faultNodeId',
        ],
      };
    }

    final paths =
        graph.findPathsToSources(
      faultNodeId,
    );

    if (paths.isEmpty) {
      return {
        'status':
            ComplianceStatus.notVerified,
        'errors': [
          'Fault noktasından grid kaynağına aktif yol bulunamadı.',
        ],
      };
    }

    final fault =
        ShortCircuitEngine
            .calcFaultAtNode(
      graph: graph,
      faultNodeId:
          faultNodeId,
    );

    return {
      'status':
          ComplianceStatus.pass,
      'faultNodeId':
          faultNodeId,
      'faultNodeName':
          node.name,
      'pathsToGrid':
          paths.length,
      'pathImpedances':
          paths
              .map(
                (p) => graph
                    .pathImpedance(p),
              )
              .toList(),
      ...fault,
    };
  }
}

// =============================================================================
// 13. LEGACY FACADE
//
// MainCockpit'in mevcut çağrılarını korur.
// =============================================================================

class ElectricalEngine {
  static Map<String, double>
      calcIec60909FaultCurrents({
    required double voltageKv,
    required double trafoMva,
    required double ukPercent,
    double gridSscMva =
        1000.0,
    double xrRatio = 8.0,
  }) {
    final graph =
        NetworkGraph();

    graph.addNode(
      NetworkNode(
        id: 'GRID',
        name: 'TEİAŞ',
        type: NetworkNodeType.grid,
        nominalVoltageKv:
            voltageKv,
      ),
    );

    graph.addNode(
      NetworkNode(
        id: 'BUS',
        name: 'Ana Bara',
        type: NetworkNodeType.bus,
        nominalVoltageKv:
            voltageKv,
      ),
    );

    // Legacy facade için kaynak + trafo empedansları seri.
    final gridZ =
        ImpedanceFactory.grid(
      voltageKv: voltageKv,
      sscMva: gridSscMva,
      xrRatio: 10.0,
    );

    final trafoZ =
        ImpedanceFactory.transformer(
      voltageKv: voltageKv,
      ratedMva: trafoMva,
      ukPercent: ukPercent,
      xrRatio: xrRatio,
    );

    graph.addBranch(
      NetworkBranch(
        id: 'SOURCE_TO_BUS',
        name: 'Şebeke + Trafo',
        fromNodeId: 'GRID',
        toNodeId: 'BUS',
        type:
            NetworkBranchType.transformer,
        impedance:
            gridZ + trafoZ,
      ),
    );

    return ShortCircuitEngine
        .calcFaultAtNode(
      graph: graph,
      faultNodeId: 'BUS',
    );
  }

  static Map<String, dynamic>
      evaluateCableSizing({
    required double sectionMm2,
    required double lengthM,
    required double loadCurrentA,
    required double voltageKv,
    required double ikKa,
    required double faultTimeSec,
    required bool isCopper,
    double ambientTempC = 30.0,
    double groupingFactor = 1.0,
    CableInstallationMethod method =
        CableInstallationMethod
            .methodE_freeAir,
    double powerFactor = 0.85,
  }) {
    return CableEngine
        .evaluateSizing(
      inputSectionMm2:
          sectionMm2,
      lengthM: lengthM,
      loadCurrentA:
          loadCurrentA,
      voltageKv: voltageKv,
      ikKa: ikKa,
      faultTimeSec:
          faultTimeSec,
      isCopper: isCopper,
      method: method,
      ambientTempC:
          ambientTempC,
      groupingFactor:
          groupingFactor,
      powerFactor:
          powerFactor,
    );
  }

  static Map<String, double>
      calcLoadFlow({
    required double voltageKv,
    required double activePowerMw,
    required double powerFactor,
    required double lineLengthKm,
    required double rOhmPerKm,
    required double xOhmPerKm,
    double sourceSscMva =
        1000.0,
  }) {
    final graph =
        NetworkGraph();

    graph.addNode(
      NetworkNode(
        id: 'GRID',
        name: 'Kaynak',
        type: NetworkNodeType.grid,
        nominalVoltageKv:
            voltageKv,
      ),
    );

    graph.addNode(
      NetworkNode(
        id: 'LOAD',
        name: 'Yük',
        type: NetworkNodeType.load,
        nominalVoltageKv:
            voltageKv,
        activePowerMw:
            activePowerMw,
        powerFactor:
            powerFactor,
      ),
    );

    final sourceZ =
        ImpedanceFactory.grid(
      voltageKv: voltageKv,
      sscMva: sourceSscMva,
      xrRatio: 10.0,
    );

    final lineZ =
        ImpedanceFactory.cable(
      lengthKm:
          lineLengthKm,
      rOhmPerKm:
          rOhmPerKm,
      xOhmPerKm:
          xOhmPerKm,
    );

    graph.addBranch(
      NetworkBranch(
        id: 'SOURCE_LINE',
        name: 'Kaynak + Hat',
        fromNodeId: 'GRID',
        toNodeId: 'LOAD',
        type:
            NetworkBranchType.line,
        impedance:
            sourceZ + lineZ,
        lengthKm:
            lineLengthKm,
      ),
    );

    return LoadFlowEngine
        .calcLoadFlowAtNode(
      graph: graph,
      receivingNodeId:
          'LOAD',
      activePowerMw:
          activePowerMw,
      powerFactor:
          powerFactor,
    );
  }

  static double calcTripTime({
    required double faultA,
    required double iPickupA,
    required double tmsVal,
    required TripCurve curve,
    ProtectionStandard standard =
        ProtectionStandard.iec60255,
  }) {
    return ProtectionEngine
        .calcTripTime(
      faultA: faultA,
      iPickupA: iPickupA,
      tmsVal: tmsVal,
      curve: curve,
      standard: standard,
    );
  }

  static double
      calcNominalCurrentA(
    double mva,
    double voltageKv,
  ) {
    if (!mva.isFinite ||
        !voltageKv.isFinite ||
        mva < 0 ||
        voltageKv <= 0) {
      return 0.0;
    }

    return (mva * 1000.0) /
        (sqrt(3.0) *
            voltageKv);
  }
}
```
