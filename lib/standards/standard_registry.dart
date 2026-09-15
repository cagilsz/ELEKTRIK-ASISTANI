import 'standard_models.dart';

class StandardRegistry {
  StandardRegistry._();

  static const List<StandardProfile> profiles = [
    StandardProfile(
      id: 'turkey_teias_iec',
      name: 'Türkiye / TEİAŞ + IEC',
      countryCode: 'TR',
      description: 'Türkiye şebeke projeleri için IEC ve TEİAŞ tabanlı profil.',
      standards: [
        StandardReference(
          code: 'IEC 60909-0',
          edition: '2026',
          family: StandardFamily.iec,
          domain: AnalysisDomain.shortCircuit,
          title: 'Short-circuit currents in three-phase AC systems',
        ),
        StandardReference(
          code: 'IEC 60255',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.protection,
          title: 'Measuring relays and protection equipment',
        ),
        StandardReference(
          code: 'IEC 60364',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.cable,
          title: 'Low-voltage electrical installations',
        ),
        StandardReference(
          code: 'IEC 62271',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.switchgear,
          title: 'High-voltage switchgear and controlgear',
        ),
        StandardReference(
          code: 'IEC 60076',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.transformer,
          title: 'Power transformers',
        ),
        StandardReference(
          code: 'TEİAŞ Technical Specifications',
          edition: 'project applicable edition',
          family: StandardFamily.turkey,
          domain: AnalysisDomain.equipment,
          title: 'TEİAŞ technical requirements',
        ),
      ],
    ),

    StandardProfile(
      id: 'international_iec',
      name: 'International / IEC',
      countryCode: 'INT',
      description: 'Genel IEC tabanlı mühendislik profili.',
      standards: [
        StandardReference(
          code: 'IEC 60909-0',
          edition: '2026',
          family: StandardFamily.iec,
          domain: AnalysisDomain.shortCircuit,
          title: 'Short-circuit currents',
        ),
        StandardReference(
          code: 'IEC 60255',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.protection,
          title: 'Protection equipment',
        ),
        StandardReference(
          code: 'IEC 60364',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.cable,
          title: 'Electrical installations',
        ),
        StandardReference(
          code: 'IEC 62271',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.switchgear,
          title: 'HV switchgear',
        ),
        StandardReference(
          code: 'IEC 60076',
          edition: 'current project edition',
          family: StandardFamily.iec,
          domain: AnalysisDomain.transformer,
          title: 'Power transformers',
        ),
      ],
    ),

    StandardProfile(
      id: 'usa_ieee_ansi',
      name: 'USA / IEEE + ANSI',
      countryCode: 'US',
      description: 'IEEE/ANSI tabanlı elektrik güç sistemi analiz profili.',
      standards: [
        StandardReference(
          code: 'IEEE 1584',
          edition: '2018',
          family: StandardFamily.ieeeAnsi,
          domain: AnalysisDomain.arcFlash,
          title: 'Arc-Flash Hazard Calculations',
        ),
        StandardReference(
          code: 'IEEE 242',
          edition: '2001',
          family: StandardFamily.ieeeAnsi,
          domain: AnalysisDomain.protection,
          title: 'Protection and Coordination',
        ),
        StandardReference(
          code: 'IEEE 399',
          edition: 'project applicable edition',
          family: StandardFamily.ieeeAnsi,
          domain: AnalysisDomain.loadFlow,
          title: 'Industrial and Commercial Power Systems Analysis',
        ),
      ],
    ),

    StandardProfile(
      id: 'russia_gost',
      name: 'Russia / GOST',
      countryCode: 'RU',
      description: 'GOST/GOST R tabanlı proje profili.',
      standards: [
        StandardReference(
          code: 'GOST R',
          edition: 'project applicable edition',
          family: StandardFamily.gost,
          domain: AnalysisDomain.equipment,
          title: 'Russian national standards',
        ),
      ],
    ),

    StandardProfile(
      id: 'china_gb',
      name: 'China / GB + GB/T + DL/T',
      countryCode: 'CN',
      description: 'Çin ulusal ve enerji sektörü standartları için profil.',
      standards: [
        StandardReference(
          code: 'GB/GB-T',
          edition: 'project applicable edition',
          family: StandardFamily.china,
          domain: AnalysisDomain.installation,
          title: 'Chinese national standards',
        ),
        StandardReference(
          code: 'DL/T',
          edition: 'project applicable edition',
          family: StandardFamily.china,
          domain: AnalysisDomain.equipment,
          title: 'Chinese electric power industry standards',
        ),
      ],
    ),

    StandardProfile(
      id: 'japan_jec_jis',
      name: 'Japan / JEC + JIS',
      countryCode: 'JP',
      description: 'JEC/JIS tabanlı Japonya proje profili.',
      standards: [
        StandardReference(
          code: 'JEC',
          edition: 'project applicable edition',
          family: StandardFamily.japan,
          domain: AnalysisDomain.equipment,
          title: 'Japanese Electrotechnical Committee standards',
        ),
        StandardReference(
          code: 'JIS',
          edition: 'project applicable edition',
          family: StandardFamily.japan,
          domain: AnalysisDomain.installation,
          title: 'Japanese Industrial Standards',
        ),
      ],
    ),

    StandardProfile(
      id: 'germany_din_vde',
      name: 'Germany / DIN + VDE',
      countryCode: 'DE',
      description: 'DIN/VDE ve ilgili EN/IEC tabanlı profil.',
      standards: [
        StandardReference(
          code: 'DIN/VDE',
          edition: 'project applicable edition',
          family: StandardFamily.germany,
          domain: AnalysisDomain.installation,
          title: 'German electrical standards',
        ),
      ],
    ),

    StandardProfile(
      id: 'france_nf',
      name: 'France / NF',
      countryCode: 'FR',
      description: 'NF ve ilgili EN/IEC tabanlı profil.',
      standards: [
        StandardReference(
          code: 'NF',
          edition: 'project applicable edition',
          family: StandardFamily.france,
          domain: AnalysisDomain.installation,
          title: 'French standards',
        ),
      ],
    ),

    StandardProfile(
      id: 'spain_une',
      name: 'Spain / UNE',
      countryCode: 'ES',
      description: 'UNE ve ilgili EN/IEC tabanlı profil.',
      standards: [
        StandardReference(
          code: 'UNE',
          edition: 'project applicable edition',
          family: StandardFamily.spain,
          domain: AnalysisDomain.installation,
          title: 'Spanish standards',
        ),
      ],
    ),
  ];

  static StandardProfile get international =>
      profiles.firstWhere((p) => p.id == 'international_iec');

  static StandardProfile byId(String id) {
    return profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => international,
    );
  }

  static List<StandardProfile> forCountry(String countryCode) {
    final code = countryCode.toUpperCase();

    final matches = profiles
        .where((p) => p.countryCode.toUpperCase() == code)
        .toList();

    if (matches.isNotEmpty) {
      return matches;
    }

    return [international];
  }
}
