/// Garde la règle d’affichage existante, indépendamment de Supabase et de Flutter.
String? profileFirstName(Map<String, dynamic>? metadata, String? email) {
  final source =
      [metadata?['first_name'], metadata?['name'], metadata?['full_name']]
          .whereType<String>()
          .firstWhere((name) => name.trim().isNotEmpty, orElse: () => '')
          .trim();
  final raw = source.isNotEmpty
      ? source.split(RegExp(r'\s+')).first
      : (email ?? '').split('@').first.split(RegExp(r'[._+\-\d]')).first;
  return raw.isEmpty
      ? null
      : '${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
}
