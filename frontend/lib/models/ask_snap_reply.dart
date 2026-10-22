/// Dépense citée par le backend, ouvrable grâce à son identifiant réel.
class AskSnapReference {
  const AskSnapReference({
    required this.id,
    required this.merchant,
    required this.date,
    required this.cents,
    required this.currency,
    required this.category,
  });
  factory AskSnapReference.fromJson(Map<String, dynamic> json) =>
      AskSnapReference(
        id: json['id'] as String,
        merchant: json['merchant'] as String,
        date: DateTime.parse(json['transaction_date'] as String),
        cents: json['amount_in_cents'] as int,
        currency: json['currency'] as String,
        category: json['category'] as String,
      );
  final String id, merchant, currency, category;
  final DateTime date;
  final int cents;
  String get amount =>
      '$currency ${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Réponse calculée côté serveur. `scope` expose la période et les filtres
/// appliqués ; les références permettent de vérifier les dépenses concernées.
class AskSnapReply {
  const AskSnapReply({
    required this.answer,
    required this.scope,
    required this.references,
    required this.matchedCount,
    required this.suggestions,
  });
  factory AskSnapReply.fromJson(Map<String, dynamic> json) => AskSnapReply(
    answer: json['answer'] as String,
    scope: json['scope'] as String,
    references: [
      for (final r in json['references'] as List)
        AskSnapReference.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
    matchedCount: json['matched_count'] as int,
    suggestions: (json['suggestions'] as List).cast<String>(),
  );
  final String answer, scope;
  final List<AskSnapReference> references;
  final int matchedCount;
  final List<String> suggestions;
}
