import '../standards/standard_models.dart';

class EngineeringExplanation {
  final String title;
  final String input;
  final String rule;
  final String calculation;
  final String result;
  final List<String> warnings;

  const EngineeringExplanation({
    required this.title,
    required this.input,
    required this.rule,
    required this.calculation,
    required this.result,
    this.warnings = const [],
  });

  factory EngineeringExplanation.fromResult({
    required String title,
    required StandardResult resultData,
    required String input,
    required String calculation,
  }) {
    final standard = resultData.standard;

    return EngineeringExplanation(
      title: title,
      input: input,
      rule: standard == null
          ? 'Doğrulanmış standart referansı bulunamadı.'
          : '${standard.code} — ${standard.edition}',
      calculation: calculation,
      result: resultData.value?.toString() ?? 'N/A',
      warnings: resultData.warnings,
    );
  }
}
