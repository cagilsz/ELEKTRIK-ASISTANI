import 'standard_models.dart';
import 'standard_registry.dart';

class StandardEngine {
  final StandardProfile profile;

  const StandardEngine({
    required this.profile,
  });

  factory StandardEngine.fromProfileId(String id) {
    return StandardEngine(
      profile: StandardRegistry.byId(id),
    );
  }

  StandardReference? standardFor(AnalysisDomain domain) {
    return profile.forDomain(domain);
  }

  StandardResult<T> verify<T>({
    required AnalysisDomain domain,
    required T value,
    List<String> assumptions = const [],
    List<String> warnings = const [],
    EngineeringStatus status = EngineeringStatus.pass,
    String? explanation,
  }) {
    final standard = standardFor(domain);

    if (standard == null) {
      return StandardResult<T>(
        status: EngineeringStatus.notVerified,
        value: value,
        assumptions: assumptions,
        warnings: [
          ...warnings,
          'Bu analiz için seçili profilde tanımlı bir standart bulunamadı.',
        ],
        explanation:
            'Sonuç hesaplandı ancak seçili standart profili altında doğrulanmış değil.',
      );
    }

    return StandardResult<T>(
      status: status,
      value: value,
      standard: standard,
      assumptions: assumptions,
      warnings: warnings,
      explanation: explanation ??
          '${standard.code} (${standard.edition}) kapsamında değerlendirildi.',
    );
  }
}
