import 'dart:math' as math;

// ============================================================
// POWERFIELD PRO - ELECTRICAL ENGINE
// ============================================================
//
// Amaç:
// - Elektrik şebekesi topolojisini Network Graph olarak modellemek
// - Kısa devre hesabı için Thevenin empedansı oluşturmak
// - Kablo kesiti / akım taşıma / gerilim düşümü hesaplamak
// - Basit yük akışı analizi yapmak
// - Kesici uygunluğunu kontrol etmek
// - Basit koruma açma süresi hesabı yapmak
//
// NOT:
// Bu motor profesyonel saha mühendisliği için başlangıç altyapısıdır.
// IEC/EN standardının tüm detaylarını ve üretici verilerini kapsamaz.
// Sonuçlar "tasarım doğrulaması / sertifikasyon" yerine geçmez.
// ============================================================


// ============================================================
// ENUMS
// ============================================================

enum ProtectionStandard {
  iec60255,
  ieee,
}

enum TripCurve {
  standardInverse,
  veryInverse,
  extremelyInverse,
  definiteTime,
}

enum CableInstallationMethod {
  methodA,
  methodB,
  methodCOnWall,
  methodD,
  methodE,
  methodF,
  freeAir,
}

enum ComplianceStatus {
  pass,
  fail,
  warning,
  notVerified,
}


// ============================================================
// IMPEDANCE
// ============================================================

class Impedance {
  final double r;
  final double x;

  const Impedance({
    required this.r,
    required this.x,
  });

  static const zero = Impedance(
    r: 0.0,
    x: 0.0,
  );

  double get magnitude {
    return math.sqrt((r * r) + (x * x));
  }

  double get angleRad {
    return math.atan2(x, r);
  }

  double get angleDeg {
    return angleRad * 180.0 / math.pi;
  }

  double get z => magnitude;

  Impedance operator +(Impedance other) {
    return Impedance(
      r: r + other.r,
      x: x + other.x,
    );
  }

  Impedance operator -(Impedance other) {
    return Impedance(
      r: r - other.r,
      x: x - other.x,
    );
  }

  /// Parallel impedance:
  ///
  /// Zparallel = (Z1 * Z2) / (Z1 + Z2)
  ///
  /// Complex arithmetic is performed explicitly.
  Impedance parallel(Impedance other) {
    final denominatorR = r + other.r;
    final denominatorX = x + other.x;

    final denominatorMagnitudeSquared =
        (denominatorR * denominatorR) +
        (denominatorX * denominatorX);

    if (denominatorMagnitudeSquared <= 0.0) {
      return zero;
    }

    final numeratorR =
        (r * other.r) - (x * other.x);

    final numeratorX =
        (r * other.x) + (x * other.r);

    final resultR =
        ((numeratorR * denominatorR) +
                (numeratorX * denominatorX)) /
            denominatorMagnitudeSquared;

    final resultX =
        ((numeratorX * denominatorR) -
                (numeratorR * denominatorX)) /
            denominatorMagnitudeSquared;

    return Impedance(
      r: resultR,
      x: resultX,
    );
  }

  Impedance scaled(double factor) {
    return Impedance(
      r: r * factor,
      x: x * factor,
    );
  }

  @override
  String toString() {
    return 'R=${r.toStringAsFixed(6)} Ω, '
        'X=${x.toStringAsFixed(6)} Ω, '
        '|Z|=${magnitude.toStringAsFixed(6)} Ω';
  }
}


// ============================================================
// NETWORK TYPES
// ============================================================

enum NetworkNodeType {
  grid,
  transformer,
  bus,
  cable,
  load,
  generator,
  inverter,
  generic,
}

enum NetworkBranchType {
  gridSource,
  transformer,
  cable,
  busCoupler,
  generator,
  load,
  generic,
}


// ============================================================
// NETWORK NODE
// ============================================================

class NetworkNode {
  final String id;
  final String name;
  final NetworkNodeType type;
  final double voltageKv;

  NetworkNode({
    required this.id,
    required this.name,
    required this.type,
    required this.voltageKv,
  });

  @override
  String toString() {
    return '$id ($name, ${type.name}, ${voltageKv} kV)';
  }
}


// ============================================================
// NETWORK BRANCH
// ============================================================

class NetworkBranch {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final NetworkBranchType type;
  final Impedance impedance;

  final bool normallyClosed;

  NetworkBranch({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.impedance,
    this.normallyClosed = true,
  });

  @override
  String toString() {
    return '$id: $fromNodeId -> $toNodeId, '
        '${type.name}, $impedance';
  }
}


// ============================================================
// NETWORK PATH
// ============================================================

class NetworkPath {
  final List<String> nodeIds;
  final List<String> branchIds;
  final Impedance impedance;

  NetworkPath({
    required this.nodeIds,
    required this.branchIds,
    required this.impedance,
  });

  @override
  String toString() {
    return 'Path(${nodeIds.join(' -> ')}) '
        'Z=$impedance';
  }
}


// ============================================================
// NETWORK GRAPH
// ============================================================

class NetworkGraph {
  final Map<String, NetworkNode> nodes = {};
  final Map<String, NetworkBranch> branches = {};

  void addNode(NetworkNode node) {
    if (nodes.containsKey(node.id)) {
      throw ArgumentError(
        'Network node already exists: ${node.id}',
      );
    }

    nodes[node.id] = node;
  }

  void addBranch(NetworkBranch branch) {
    if (!nodes.containsKey(branch.fromNodeId)) {
      throw ArgumentError(
        'From node does not exist: ${branch.fromNodeId}',
      );
    }

    if (!nodes.containsKey(branch.toNodeId)) {
      throw ArgumentError(
        'To node does not exist: ${branch.toNodeId}',
      );
    }

    if (branches.containsKey(branch.id)) {
      throw ArgumentError(
        'Network branch already exists: ${branch.id}',
      );
    }

    branches[branch.id] = branch;
  }

  NetworkNode? getNode(String id) {
    return nodes[id];
  }

  NetworkBranch? getBranch(String id) {
    return branches[id];
  }

  List<NetworkBranch> connectedBranches(
    String nodeId,
  ) {
    return branches.values.where((branch) {
      return branch.normallyClosed &&
          (branch.fromNodeId == nodeId ||
              branch.toNodeId == nodeId);
    }).toList();
  }

  String oppositeNode(
    NetworkBranch branch,
    String nodeId,
  ) {
    if (branch.fromNodeId == nodeId) {
      return branch.toNodeId;
    }

    if (branch.toNodeId == nodeId) {
      return branch.fromNodeId;
    }

    throw ArgumentError(
      'Node $nodeId is not part of branch ${branch.id}',
    );
  }

  List<NetworkPath> findPathsToSources(
    String targetNodeId,
  ) {
    if (!nodes.containsKey(targetNodeId)) {
      return [];
    }

    final sourceNodes = nodes.values
        .where((node) => node.type == NetworkNodeType.grid)
        .toList();

    final results = <NetworkPath>[];

    for (final source in sourceNodes) {
      final visitedNodes = <String>{};
      final visitedBranches = <String>{};

      _dfsPaths(
        currentNodeId: targetNodeId,
        sourceNodeId: source.id,
        visitedNodes: visitedNodes,
        visitedBranches: visitedBranches,
        nodePath: [targetNodeId],
        branchPath: [],
        impedance: Impedance.zero,
        results: results,
      );
    }

    return results;
  }

  void _dfsPaths({
    required String currentNodeId,
    required String sourceNodeId,
    required Set<String> visitedNodes,
    required Set<String> visitedBranches,
    required List<String> nodePath,
    required List<String> branchPath,
    required Impedance impedance,
    required List<NetworkPath> results,
  }) {
    if (currentNodeId == sourceNodeId) {
      results.add(
        NetworkPath(
          nodeIds: List<String>.from(nodePath),
          branchIds: List<String>.from(branchPath),
          impedance: impedance,
        ),
      );

      return;
    }

    visitedNodes.add(currentNodeId);

    for (final branch in connectedBranches(currentNodeId)) {
      if (visitedBranches.contains(branch.id)) {
        continue;
      }

      final nextNode = oppositeNode(
        branch,
        currentNodeId,
      );

      if (visitedNodes.contains(nextNode)) {
        continue;
      }

      visitedBranches.add(branch.id);
      nodePath.add(nextNode);
      branchPath.add(branch.id);

      _dfsPaths(
        currentNodeId: nextNode,
        sourceNodeId: sourceNodeId,
        visitedNodes: visitedNodes,
        visitedBranches: visitedBranches,
        nodePath: nodePath,
        branchPath: branchPath,
        impedance: impedance + branch.impedance,
        results: results,
      );

      branchPath.removeLast();
      nodePath.removeLast();
      visitedBranches.remove(branch.id);
    }

    visitedNodes.remove(currentNodeId);
  }

  Impedance calculateTheveninImpedance(
    String targetNodeId,
  ) {
    final paths = findPathsToSources(targetNodeId);

    if (paths.isEmpty) {
      return Impedance.zero;
    }

    Impedance? result;

    for (final path in paths) {
      if (path.impedance.magnitude <= 0.0) {
        continue;
      }

      if (result == null) {
        result = path.impedance;
      } else {
        result = result.parallel(path.impedance);
      }
    }

    return result ?? Impedance.zero;
  }

  bool hasPathToSource(
    String targetNodeId,
  ) {
    return findPathsToSources(targetNodeId).isNotEmpty;
  }

  List<String> validate() {
    final errors = <String>[];

    for (final branch in branches.values) {
      if (!nodes.containsKey(branch.fromNodeId)) {
        errors.add(
          'Branch ${branch.id}: '
          'missing from node ${branch.fromNodeId}',
        );
      }

      if (!nodes.containsKey(branch.toNodeId)) {
        errors.add(
          'Branch ${branch.id}: '
          'missing to node ${branch.toNodeId}',
        );
      }

      if (branch.impedance.r < 0.0 ||
          branch.impedance.x < 0.0) {
        errors.add(
          'Branch ${branch.id}: negative impedance value',
        );
      }
    }

    final gridCount = nodes.values
        .where(
          (node) => node.type == NetworkNodeType.grid,
        )
        .length;

    if (gridCount == 0) {
      errors.add('No grid source exists in network.');
    }

    return errors;
  }
}


// ============================================================
// NETWORK BUILDER
// ============================================================

class NetworkBuilder {
  final NetworkGraph graph = NetworkGraph();

  NetworkGraph build() {
    return graph;
  }

  void addGrid({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.grid,
        voltageKv: voltageKv,
      ),
    );
  }

  void addTransformer({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.transformer,
        voltageKv: voltageKv,
      ),
    );
  }

  void addBus({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.bus,
        voltageKv: voltageKv,
      ),
    );
  }

  void addCableNode({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.cable,
        voltageKv: voltageKv,
      ),
    );
  }

  void addLoad({
    required String id,
    required String name,
    required double voltageKv,
  }) {
    graph.addNode(
      NetworkNode(
        id: id,
        name: name,
        type: NetworkNodeType.load,
        voltageKv: voltageKv,
      ),
    );
  }

  void addBranch({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    required NetworkBranchType type,
    required Impedance impedance,
    bool normallyClosed = true,
  }) {
    graph.addBranch(
      NetworkBranch(
        id: id,
        fromNodeId: fromNodeId,
        toNodeId: toNodeId,
        type: type,
        impedance: impedance,
        normallyClosed: normallyClosed,
      ),
    );
  }
}


// ============================================================
// IMPEDANCE FACTORY
// ============================================================

class ImpedanceFactory {
  static Impedance grid({
    required double voltageKv,
    required double shortCircuitMva,
  }) {
    if (voltageKv <= 0.0 ||
        shortCircuitMva <= 0.0) {
      return Impedance.zero;
    }

    final z = (voltageKv * voltageKv) /
        shortCircuitMva;

    return Impedance(
      r: z * 0.1,
      x: z * 0.9,
    );
  }

  static Impedance transformer({
    required double ratedMva,
    required double ukPercent,
    required double voltageKv,
    double rxRatio = 0.1,
  }) {
    if (ratedMva <= 0.0 ||
        ukPercent <= 0.0 ||
        voltageKv <= 0.0) {
      return Impedance.zero;
    }

    final zBase =
        (voltageKv * voltageKv) / ratedMva;

    final z = zBase * (ukPercent / 100.0);

    final r = z * rxRatio;
    final x = math.sqrt(
      math.max(
        0.0,
        (z * z) - (r * r),
      ),
    );

    return Impedance(
      r: r,
      x: x,
    );
  }

  static Impedance cable({
    required double lengthKm,
    required double resistanceOhmPerKm,
    required double reactanceOhmPerKm,
  }) {
    if (lengthKm < 0.0) {
      return Impedance.zero;
    }

    return Impedance(
      r: lengthKm * resistanceOhmPerKm,
      x: lengthKm * reactanceOhmPerKm,
    );
  }
}


// ============================================================
// SHORT CIRCUIT
// ============================================================

class ShortCircuitResult {
  final double voltageKv;
  final double faultCurrentKa;
  final double faultCurrentA;
  final Impedance theveninImpedance;
  final bool valid;
  final String message;

  const ShortCircuitResult({
    required this.voltageKv,
    required this.faultCurrentKa,
    required this.faultCurrentA,
    required this.theveninImpedance,
    required this.valid,
    required this.message,
  });
}

class ShortCircuitEngine {
  static ShortCircuitResult calcFaultAtNode({
    required NetworkGraph graph,
    required String nodeId,
    double voltageFactor = 1.0,
  }) {
    final node = graph.getNode(nodeId);

    if (node == null) {
      return ShortCircuitResult(
        voltageKv: 0.0,
        faultCurrentKa: 0.0,
        faultCurrentA: 0.0,
        theveninImpedance: Impedance.zero,
        valid: false,
        message: 'Node not found: $nodeId',
      );
    }

    final zth =
        graph.calculateTheveninImpedance(nodeId);

    if (zth.magnitude <= 0.0) {
      return ShortCircuitResult(
        voltageKv: node.voltageKv,
        faultCurrentKa: 0.0,
        faultCurrentA: 0.0,
        theveninImpedance: zth,
        valid: false,
        message:
            'No valid Thevenin impedance found.',
      );
    }

    final voltageV =
        node.voltageKv * 1000.0;

    final currentA =
        (voltageFactor * voltageV) /
            (math.sqrt(3.0) * zth.magnitude);

    return ShortCircuitResult(
      voltageKv: node.voltageKv,
      faultCurrentKa: currentA / 1000.0,
      faultCurrentA: currentA,
      theveninImpedance: zth,
      valid: true,
      message: 'Short-circuit calculation completed.',
    );
  }

  static double threePhaseFaultCurrentKa({
    required double voltageKv,
    required Impedance impedance,
    double voltageFactor = 1.0,
  }) {
    if (voltageKv <= 0.0 ||
        impedance.magnitude <= 0.0) {
      return 0.0;
    }

    final currentA =
        (voltageFactor * voltageKv * 1000.0) /
            (math.sqrt(3.0) * impedance.magnitude);

    return currentA / 1000.0;
  }
}


// ============================================================
// CABLE DATA
// ============================================================

class CableSizeResult {
  final double selectedSectionMm2;
  final double designCurrentA;
  final double ampacityA;
  final double voltageDropV;
  final double voltageDropPercent;
  final ComplianceStatus status;
  final String message;

  const CableSizeResult({
    required this.selectedSectionMm2,
    required this.designCurrentA,
    required this.ampacityA,
    required this.voltageDropV,
    required this.voltageDropPercent,
    required this.status,
    required this.message,
  });
}


// ============================================================
// CABLE ENGINE
// ============================================================

class CableEngine {
  // Partial engineering reference tables.
  //
  // These are not a substitute for the exact cable manufacturer
  // table / installation condition / ambient correction factors.

  static final Map<double, double> iecAmpacityTablesCu = {
    1.5: 14.0,
    2.5: 20.0,
    4.0: 26.0,
    6.0: 34.0,
    10.0: 46.0,
    16.0: 61.0,
    25.0: 80.0,
    35.0: 99.0,
    50.0: 119.0,
    70.0: 151.0,
    95.0: 182.0,
    120.0: 210.0,
    150.0: 240.0,
    185.0: 273.0,
    240.0: 321.0,
    300.0: 367.0,
    400.0: 438.0,
    500.0: 502.0,
    630.0: 578.0,
  };

  static final Map<double, double> iecAmpacityTablesAl = {
    1.5: 11.0,
    2.5: 16.0,
    4.0: 21.0,
    6.0: 27.0,
    10.0: 37.0,
    16.0: 49.0,
    25.0: 64.0,
    35.0: 78.0,
    50.0: 94.0,
    70.0: 119.0,
    95.0: 145.0,
    120.0: 167.0,
    150.0: 191.0,
    185.0: 217.0,
    240.0: 255.0,
    300.0: 291.0,
    400.0: 347.0,
    500.0: 398.0,
    630.0: 459.0,
  };

  static double? ampacity({
    required double sectionMm2,
    required bool aluminium,
    required CableInstallationMethod method,
  }) {
    final table = aluminium
        ? iecAmpacityTablesAl
        : iecAmpacityTablesCu;

    // We deliberately do not silently map an unknown
    // installation method to free-air.
    switch (method) {
      case CableInstallationMethod.methodA:
      case CableInstallationMethod.methodB:
      case CableInstallationMethod.methodCOnWall:
      case CableInstallationMethod.methodD:
      case CableInstallationMethod.methodE:
      case CableInstallationMethod.methodF:
        return table[sectionMm2];

      case CableInstallationMethod.freeAir:
        return table[sectionMm2];
    }
  }

  static double selectSection({
    required double designCurrentA,
    required bool aluminium,
    required CableInstallationMethod method,
  }) {
    final table = aluminium
        ? iecAmpacityTablesAl
        : iecAmpacityTablesCu;

    for (final entry in table.entries) {
      if (entry.value >= designCurrentA) {
        return entry.key;
      }
    }

    return 0.0;
  }

  static CableSizeResult sizeCable({
    required double designCurrentA,
    required double lengthM,
    required double voltageV,
    required double powerFactor,
    required bool aluminium,
    required CableInstallationMethod method,
    double resistanceOhmPerKm = 0.0,
    double reactanceOhmPerKm = 0.08,
    double maxVoltageDropPercent = 3.0,
  }) {
    if (designCurrentA <= 0.0) {
      return const CableSizeResult(
        selectedSectionMm2: 0.0,
        designCurrentA: 0.0,
        ampacityA: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Design current must be greater than zero.',
      );
    }

    if (lengthM < 0.0 ||
        voltageV <= 0.0 ||
        powerFactor <= 0.0 ||
        powerFactor > 1.0) {
      return const CableSizeResult(
        selectedSectionMm2: 0.0,
        designCurrentA: 0.0,
        ampacityA: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Invalid cable input parameters.',
      );
    }

    final selectedSection = selectSection(
      designCurrentA: designCurrentA,
      aluminium: aluminium,
      method: method,
    );

    if (selectedSection <= 0.0) {
      return CableSizeResult(
        selectedSectionMm2: 0.0,
        designCurrentA: designCurrentA,
        ampacityA: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        status: ComplianceStatus.fail,
        message:
            'No available cable section satisfies design current.',
      );
    }

    final ampacityValue = ampacity(
      sectionMm2: selectedSection,
      aluminium: aluminium,
      method: method,
    );

    if (ampacityValue == null) {
      return CableSizeResult(
        selectedSectionMm2: selectedSection,
        designCurrentA: designCurrentA,
        ampacityA: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        status: ComplianceStatus.notVerified,
        message:
            'Ampacity table does not contain this installation case.',
      );
    }

    final calculatedResistance =
        resistanceOhmPerKm > 0.0
            ? resistanceOhmPerKm
            : _defaultResistance(
                sectionMm2: selectedSection,
                aluminium: aluminium,
              );

    final lengthKm = lengthM / 1000.0;

    final resistance =
        calculatedResistance * lengthKm;

    final reactance =
        reactanceOhmPerKm * lengthKm;

    final sinPhi =
        math.sqrt(
          math.max(
            0.0,
            1.0 -
                (powerFactor * powerFactor),
          ),
        );

    final voltageDrop =
        math.sqrt(3.0) *
            designCurrentA *
            ((resistance * powerFactor) +
                (reactance * sinPhi));

    final voltageDropPercent =
        voltageDrop / voltageV * 100.0;

    final status =
        voltageDropPercent <= maxVoltageDropPercent
            ? ComplianceStatus.pass
            : ComplianceStatus.warning;

    return CableSizeResult(
      selectedSectionMm2: selectedSection,
      designCurrentA: designCurrentA,
      ampacityA: ampacityValue,
      voltageDropV: voltageDrop,
      voltageDropPercent: voltageDropPercent,
      status: status,
      message:
          status == ComplianceStatus.pass
              ? 'Cable sizing passed the basic checks.'
              : 'Cable ampacity passed, but voltage drop exceeds the configured limit.',
    );
  }

  static double _defaultResistance({
    required double sectionMm2,
    required bool aluminium,
  }) {
    if (sectionMm2 <= 0.0) {
      return 0.0;
    }

    final resistivity =
        aluminium ? 0.0282 : 0.0175;

    return resistivity / sectionMm2;
  }

  static double adiabaticMinimumSection({
    required double faultCurrentA,
    required double clearingTimeS,
    required double k,
  }) {
    if (faultCurrentA <= 0.0 ||
        clearingTimeS <= 0.0 ||
        k <= 0.0) {
      return 0.0;
    }

    return faultCurrentA *
        math.sqrt(clearingTimeS) /
        k;
  }
}


// ============================================================
// LOAD FLOW
// ============================================================

class LoadFlowResult {
  final double sendingVoltageV;
  final double receivingVoltageV;
  final double voltageDropV;
  final double voltageDropPercent;
  final double currentA;
  final ComplianceStatus status;
  final String message;

  const LoadFlowResult({
    required this.sendingVoltageV,
    required this.receivingVoltageV,
    required this.voltageDropV,
    required this.voltageDropPercent,
    required this.currentA,
    required this.status,
    required this.message,
  });
}

class LoadFlowEngine {
  static LoadFlowResult calculate({
    required double voltageV,
    required double powerW,
    required double powerFactor,
    required Impedance pathImpedance,
  }) {
    if (voltageV <= 0.0 ||
        powerW < 0.0 ||
        powerFactor <= 0.0 ||
        powerFactor > 1.0) {
      return const LoadFlowResult(
        sendingVoltageV: 0.0,
        receivingVoltageV: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        currentA: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Invalid load-flow parameters.',
      );
    }

    final currentA =
        powerW /
            (math.sqrt(3.0) *
                voltageV *
                powerFactor);

    final sinPhi =
        math.sqrt(
          math.max(
            0.0,
            1.0 -
                (powerFactor * powerFactor),
          ),
        );

    final voltageDrop =
        math.sqrt(3.0) *
            currentA *
            ((pathImpedance.r * powerFactor) +
                (pathImpedance.x * sinPhi));

    final receivingVoltage =
        math.max(
          0.0,
          voltageV - voltageDrop,
        );

    final voltageDropPercent =
        voltageDrop / voltageV * 100.0;

    return LoadFlowResult(
      sendingVoltageV: voltageV,
      receivingVoltageV: receivingVoltage,
      voltageDropV: voltageDrop,
      voltageDropPercent: voltageDropPercent,
      currentA: currentA,
      status:
          voltageDropPercent <= 5.0
              ? ComplianceStatus.pass
              : ComplianceStatus.warning,
      message: 'Load-flow calculation completed.',
    );
  }

  static LoadFlowResult calculateForGraph({
    required NetworkGraph graph,
    required String targetNodeId,
    required double powerW,
    required double powerFactor,
  }) {
    final node = graph.getNode(targetNodeId);

    if (node == null) {
      return const LoadFlowResult(
        sendingVoltageV: 0.0,
        receivingVoltageV: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        currentA: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Target node not found.',
      );
    }

    final paths =
        graph.findPathsToSources(targetNodeId);

    if (paths.isEmpty) {
      return const LoadFlowResult(
        sendingVoltageV: 0.0,
        receivingVoltageV: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        currentA: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'No source path found.',
      );
    }

    // For the current engine we use the equivalent
    // Thevenin path impedance.
    final equivalent =
        graph.calculateTheveninImpedance(
      targetNodeId,
    );

    final sourceNode =
        graph.getNode(paths.first.nodeIds.last);

    if (sourceNode == null) {
      return const LoadFlowResult(
        sendingVoltageV: 0.0,
        receivingVoltageV: 0.0,
        voltageDropV: 0.0,
        voltageDropPercent: 0.0,
        currentA: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Source node not found.',
      );
    }

    return calculate(
      voltageV: sourceNode.voltageKv * 1000.0,
      powerW: powerW,
      powerFactor: powerFactor,
      pathImpedance: equivalent,
    );
  }
}


// ============================================================
// BREAKER / EQUIPMENT
// ============================================================

class EquipmentValidationResult {
  final ComplianceStatus status;
  final String message;
  final double faultCurrentKa;
  final double breakingCapacityKa;

  const EquipmentValidationResult({
    required this.status,
    required this.message,
    required this.faultCurrentKa,
    required this.breakingCapacityKa,
  });
}

class EquipmentEngine {
  static EquipmentValidationResult validateBreaker({
    required double faultCurrentKa,
    required double breakingCapacityKa,
  }) {
    if (faultCurrentKa < 0.0 ||
        breakingCapacityKa <= 0.0) {
      return const EquipmentValidationResult(
        status: ComplianceStatus.notVerified,
        message: 'Invalid breaker input values.',
        faultCurrentKa: 0.0,
        breakingCapacityKa: 0.0,
      );
    }

    if (faultCurrentKa <= breakingCapacityKa) {
      return EquipmentValidationResult(
        status: ComplianceStatus.pass,
        message:
            'Breaker breaking capacity is greater than or equal to calculated fault current.',
        faultCurrentKa: faultCurrentKa,
        breakingCapacityKa: breakingCapacityKa,
      );
    }

    return EquipmentValidationResult(
      status: ComplianceStatus.fail,
      message:
          'Calculated fault current exceeds breaker breaking capacity.',
      faultCurrentKa: faultCurrentKa,
      breakingCapacityKa: breakingCapacityKa,
    );
  }
}


// ============================================================
// PROTECTION
// ============================================================

class ProtectionResult {
  final double tripTimeS;
  final ComplianceStatus status;
  final String message;

  const ProtectionResult({
    required this.tripTimeS,
    required this.status,
    required this.message,
  });
}

class ProtectionEngine {
  static ProtectionResult calcTripTime({
    required double faultCurrentA,
    required double pickupCurrentA,
    required double timeMultiplier,
    TripCurve curve = TripCurve.standardInverse,
  }) {
    if (faultCurrentA <= 0.0 ||
        pickupCurrentA <= 0.0 ||
        timeMultiplier <= 0.0) {
      return const ProtectionResult(
        tripTimeS: 0.0,
        status: ComplianceStatus.notVerified,
        message: 'Invalid protection parameters.',
      );
    }

    final multiple =
        faultCurrentA / pickupCurrentA;

    if (multiple <= 1.0) {
      return const ProtectionResult(
        tripTimeS: double.infinity,
        status: ComplianceStatus.warning,
        message:
            'Fault current does not exceed pickup current.',
      );
    }

    double tripTime;

    switch (curve) {
      case TripCurve.standardInverse:
        tripTime =
            timeMultiplier *
                (0.14 /
                    (math.pow(
                          multiple,
                          0.02,
                        ) -
                        1.0));

      case TripCurve.veryInverse:
        tripTime =
            timeMultiplier *
                (13.5 /
                    (multiple - 1.0));

      case TripCurve.extremelyInverse:
        tripTime =
            timeMultiplier *
                (80.0 /
                    ((multiple * multiple) -
                        1.0));

      case TripCurve.definiteTime:
        tripTime = timeMultiplier;
    }

    if (!tripTime.isFinite ||
        tripTime <= 0.0) {
      return const ProtectionResult(
        tripTimeS: 0.0,
        status: ComplianceStatus.notVerified,
        message:
            'Protection curve calculation returned an invalid value.',
      );
    }

    return ProtectionResult(
      tripTimeS: tripTime,
      status: ComplianceStatus.pass,
      message: 'Protection trip time calculated.',
    );
  }
}


// ============================================================
// NETWORK ANALYSIS
// ============================================================

class FaultAnalysisResult {
  final String nodeId;
  final String nodeName;
  final double faultCurrentKa;
  final double faultCurrentA;
  final Impedance theveninImpedance;
  final ComplianceStatus status;
  final String message;

  const FaultAnalysisResult({
    required this.nodeId,
    required this.nodeName,
    required this.faultCurrentKa,
    required this.faultCurrentA,
    required this.theveninImpedance,
    required this.status,
    required this.message,
  });
}

class NetworkAnalysisEngine {
  static FaultAnalysisResult analyzeFault({
    required NetworkGraph graph,
    required String nodeId,
    double voltageFactor = 1.0,
  }) {
    final node = graph.getNode(nodeId);

    if (node == null) {
      return FaultAnalysisResult(
        nodeId: nodeId,
        nodeName: '',
        faultCurrentKa: 0.0,
        faultCurrentA: 0.0,
        theveninImpedance: Impedance.zero,
        status: ComplianceStatus.notVerified,
        message: 'Node not found.',
      );
    }

    final result =
        ShortCircuitEngine.calcFaultAtNode(
      graph: graph,
      nodeId: nodeId,
      voltageFactor: voltageFactor,
    );

    if (!result.valid) {
      return FaultAnalysisResult(
        nodeId: nodeId,
        nodeName: node.name,
        faultCurrentKa: result.faultCurrentKa,
        faultCurrentA: result.faultCurrentA,
        theveninImpedance:
            result.theveninImpedance,
        status: ComplianceStatus.notVerified,
        message: result.message,
      );
    }

    return FaultAnalysisResult(
      nodeId: nodeId,
      nodeName: node.name,
      faultCurrentKa: result.faultCurrentKa,
      faultCurrentA: result.faultCurrentA,
      theveninImpedance:
          result.theveninImpedance,
      status: ComplianceStatus.pass,
      message: result.message,
    );
  }
}


// ============================================================
// LEGACY / UI FACADE
// ============================================================
//
// Bu sınıf mevcut UI tarafının doğrudan engine sınıflarına
// bağımlılığını azaltmak için tutuluyor.
//
// Eski çağrılar mümkün olduğunca burada korunur.
// ============================================================

class ElectricalEngine {
  // ----------------------------------------------------------
  // Short Circuit
  // ----------------------------------------------------------

  static double calculateShortCircuitCurrent({
    required double voltageKv,
    required double shortCircuitMva,
  }) {
    if (voltageKv <= 0.0 ||
        shortCircuitMva <= 0.0) {
      return 0.0;
    }

    final currentKa =
        shortCircuitMva /
            (math.sqrt(3.0) *
                voltageKv);

    return currentKa;
  }

  static double calculateFaultCurrent({
    required double voltageKv,
    required double impedanceOhm,
  }) {
    if (voltageKv <= 0.0 ||
        impedanceOhm <= 0.0) {
      return 0.0;
    }

    final currentA =
        (voltageKv * 1000.0) /
            (math.sqrt(3.0) *
                impedanceOhm);

    return currentA;
  }

  // ----------------------------------------------------------
  // Transformer
  // ----------------------------------------------------------

  static Impedance calculateTransformerImpedance({
    required double ratedMva,
    required double ukPercent,
    required double voltageKv,
    double rxRatio = 0.1,
  }) {
    return ImpedanceFactory.transformer(
      ratedMva: ratedMva,
      ukPercent: ukPercent,
      voltageKv: voltageKv,
      rxRatio: rxRatio,
    );
  }

  // ----------------------------------------------------------
  // Grid
  // ----------------------------------------------------------

  static Impedance calculateGridImpedance({
    required double voltageKv,
    required double shortCircuitMva,
  }) {
    return ImpedanceFactory.grid(
      voltageKv: voltageKv,
      shortCircuitMva: shortCircuitMva,
    );
  }

  // ----------------------------------------------------------
  // Cable
  // ----------------------------------------------------------

  static double calculateCableVoltageDrop({
    required double currentA,
    required double lengthM,
    required double resistanceOhmPerKm,
    required double reactanceOhmPerKm,
    required double powerFactor,
  }) {
    if (currentA <= 0.0 ||
        lengthM < 0.0 ||
        powerFactor <= 0.0 ||
        powerFactor > 1.0) {
      return 0.0;
    }

    final lengthKm =
        lengthM / 1000.0;

    final resistance =
        resistanceOhmPerKm *
            lengthKm;

    final reactance =
        reactanceOhmPerKm *
            lengthKm;

    final sinPhi =
        math.sqrt(
          math.max(
            0.0,
            1.0 -
                (powerFactor *
                    powerFactor),
          ),
        );

    return math.sqrt(3.0) *
        currentA *
        ((resistance *
                powerFactor) +
            (reactance *
                sinPhi));
  }

  static double selectCableSection({
    required double designCurrentA,
    required bool aluminium,
    required CableInstallationMethod method,
  }) {
    return CableEngine.selectSection(
      designCurrentA: designCurrentA,
      aluminium: aluminium,
      method: method,
    );
  }

  // ----------------------------------------------------------
  // Breaker
  // ----------------------------------------------------------

  static EquipmentValidationResult validateBreaker({
    required double faultCurrentKa,
    required double breakingCapacityKa,
  }) {
    return EquipmentEngine.validateBreaker(
      faultCurrentKa: faultCurrentKa,
      breakingCapacityKa: breakingCapacityKa,
    );
  }

  // ----------------------------------------------------------
  // Protection
  // ----------------------------------------------------------

  static ProtectionResult calculateTripTime({
    required double faultCurrentA,
    required double pickupCurrentA,
    required double timeMultiplier,
    TripCurve curve =
        TripCurve.standardInverse,
  }) {
    return ProtectionEngine.calcTripTime(
      faultCurrentA: faultCurrentA,
      pickupCurrentA: pickupCurrentA,
      timeMultiplier: timeMultiplier,
      curve: curve,
    );
  }

  // ----------------------------------------------------------
  // Demo / Legacy Network
  // ----------------------------------------------------------
  //
  // Buradaki model:
  //
  // GRID --(Zgrid + Ztrafo)-- BUS
  //
  // Grid ve trafo aynı iki node arasına paralel bağlanmaz.
  // Böylece fiziksel olarak seri olan grid + trafo doğru
  // şekilde modellenir.
  // ----------------------------------------------------------

  static NetworkGraph createLegacyNetwork({
    required double voltageKv,
    required double gridShortCircuitMva,
    required double transformerRatedMva,
    required double transformerUkPercent,
  }) {
    final builder = NetworkBuilder();

    builder.addGrid(
      id: 'GRID',
      name: 'Grid',
      voltageKv: voltageKv,
    );

    builder.addBus(
      id: 'BUS',
      name: 'Main Bus',
      voltageKv: voltageKv,
    );

    final gridZ =
        ImpedanceFactory.grid(
      voltageKv: voltageKv,
      shortCircuitMva:
          gridShortCircuitMva,
    );

    final transformerZ =
        ImpedanceFactory.transformer(
      ratedMva: transformerRatedMva,
      ukPercent: transformerUkPercent,
      voltageKv: voltageKv,
    );

    builder.addBranch(
      id: 'GRID_TO_BUS',
      fromNodeId: 'GRID',
      toNodeId: 'BUS',
      type: NetworkBranchType.transformer,
      impedance:
          gridZ + transformerZ,
    );

    return builder.build();
  }

  // ----------------------------------------------------------
  // Graph fault analysis
  // ----------------------------------------------------------

  static FaultAnalysisResult analyzeGraphFault({
    required NetworkGraph graph,
    required String nodeId,
  }) {
    return NetworkAnalysisEngine.analyzeFault(
      graph: graph,
      nodeId: nodeId,
    );
  }
}
