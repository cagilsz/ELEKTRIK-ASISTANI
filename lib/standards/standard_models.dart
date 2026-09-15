enum StandardFamily {
  iec,
  ieeeAnsi,
  gost,
  china,
  japan,
  germany,
  france,
  spain,
  turkey,
  custom,
}

enum AnalysisDomain {
  shortCircuit,
  protection,
  cable,
  loadFlow,
  switchgear,
  transformer,
  arcFlash,
  equipment,
  installation,
}

enum EngineeringStatus {
  pass,
  warning,
  fail,
  notVerified,
}

class StandardReference {
  final String code;
  final String edition;
  final StandardFamily family;
  final AnalysisDomain domain;
  final String title;
  final String? source;
  final DateTime? effectiveDate;

  const StandardReference({
    required this.code,
    required this.edition,
    required this.family,
    required this.domain,
    required this.title,
    this.source,
    this.effectiveDate,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'edition': edition,
        'family': family.name,
        'domain': domain.name,
        'title': title,
        'source': source,
        'effectiveDate': effectiveDate?.toIso8601String(),
      };

  factory StandardReference.fromJson(Map<String, dynamic> json) {
    return StandardReference(
      code: json['code'] as String? ?? '',
      edition: json['edition'] as String? ?? '',
      family: StandardFamily.values.firstWhere(
        (e) => e.name == json['family'],
        orElse: () => StandardFamily.custom,
      ),
      domain: AnalysisDomain.values.firstWhere(
        (e) => e.name == json['domain'],
        orElse: () => AnalysisDomain.equipment,
      ),
      title: json['title'] as String? ?? '',
      source: json['source'] as String?,
      effectiveDate: json['effectiveDate'] == null
          ? null
          : DateTime.tryParse(json['effectiveDate']),
    );
  }
}

class StandardProfile {
  final String id;
  final String name;
  final String countryCode;
  final String description;
  final List<StandardReference> standards;

  const StandardProfile({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.description,
    required this.standards,
  });

  StandardReference? forDomain(AnalysisDomain domain) {
    for (final standard in standards) {
      if (standard.domain == domain) {
        return standard;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'countryCode': countryCode,
        'description': description,
        'standards': standards.map((e) => e.toJson()).toList(),
      };

  factory StandardProfile.fromJson(Map<String, dynamic> json) {
    return StandardProfile(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? 'Custom',
      countryCode: json['countryCode'] as String? ?? '',
      description: json['description'] as String? ?? '',
      standards: (json['standards'] as List<dynamic>? ?? [])
          .map((e) => StandardReference.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

class StandardResult<T> {
  final EngineeringStatus status;
  final T? value;
  final StandardReference? standard;
  final List<String> assumptions;
  final List<String> warnings;
  final String explanation;

  const StandardResult({
    required this.status,
    this.value,
    this.standard,
    this.assumptions = const [],
    this.warnings = const [],
    this.explanation = '',
  });

  bool get isVerified => status != EngineeringStatus.notVerified;
  bool get isPass => status == EngineeringStatus.pass;
}
