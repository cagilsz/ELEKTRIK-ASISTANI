class FieldContext {
  final String? countryCode;
  final double? altitudeM;
  final double? temperatureC;
  final double? humidityPercent;

  const FieldContext({
    this.countryCode,
    this.altitudeM,
    this.temperatureC,
    this.humidityPercent,
  });

  FieldContext copyWith({
    String? countryCode,
    double? altitudeM,
    double? temperatureC,
    double? humidityPercent,
  }) {
    return FieldContext(
      countryCode: countryCode ?? this.countryCode,
      altitudeM: altitudeM ?? this.altitudeM,
      temperatureC: temperatureC ?? this.temperatureC,
      humidityPercent: humidityPercent ?? this.humidityPercent,
    );
  }

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'altitudeM': altitudeM,
        'temperatureC': temperatureC,
        'humidityPercent': humidityPercent,
      };

  factory FieldContext.fromJson(Map<String, dynamic> json) {
    return FieldContext(
      countryCode: json['countryCode'] as String?,
      altitudeM: (json['altitudeM'] as num?)?.toDouble(),
      temperatureC: (json['temperatureC'] as num?)?.toDouble(),
      humidityPercent: (json['humidityPercent'] as num?)?.toDouble(),
    );
  }
}
