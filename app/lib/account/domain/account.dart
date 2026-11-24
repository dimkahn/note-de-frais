/// Offre d'un compte (alignée sur l'énumération `Plan` du serveur).
enum Plan {
  free('FREE', 'Gratuit'),
  premium('PREMIUM', 'Premium');

  const Plan(this.code, this.label);

  final String code;
  final String label;

  static Plan fromCode(String? code) =>
      values.firstWhere((p) => p.code == code, orElse: () => free);
}

/// Place utilisée en ligne par un compte, rapportée à l'espace de son offre.
final class StorageUsage {
  const StorageUsage({required this.usedBytes, required this.quotaBytes});

  final int usedBytes;
  final int quotaBytes;

  /// Part utilisée, entre 0 et 1.
  double get fraction =>
      quotaBytes <= 0 ? 1 : (usedBytes / quotaBytes).clamp(0, 1).toDouble();

  /// Au-delà de 90 % : à signaler.
  bool get nearlyFull => fraction > 0.9;

  @override
  bool operator ==(Object other) =>
      other is StorageUsage &&
      other.usedBytes == usedBytes &&
      other.quotaBytes == quotaBytes;

  @override
  int get hashCode => Object.hash(usedBytes, quotaBytes);
}

/// Compte connecté, tel que décrit par le serveur. L'usage n'est connu qu'après lecture de
/// `GET /api/account` (absent des réponses d'inscription et de connexion).
final class Account {
  const Account({
    required this.email,
    required this.plan,
    this.usage,
    this._aiAnalysis,
  });

  factory Account.fromJson(Map<String, Object?> json) {
    final used = json['usedBytes'] as int?;
    final quota = json['quotaBytes'] as int?;
    return Account(
      email: json['email']! as String,
      plan: Plan.fromCode(json['plan'] as String?),
      usage: used == null || quota == null
          ? null
          : StorageUsage(usedBytes: used, quotaBytes: quota),
      aiAnalysis: json['aiAnalysis'] as bool?,
    );
  }

  final String email;
  final Plan plan;
  final StorageUsage? usage;
  final bool? _aiAnalysis;

  /// Analyse des justificatifs par l'IA du serveur incluse dans l'offre ; tant que le serveur
  /// ne l'a pas précisé, déduite de l'offre (Premium seulement).
  bool get aiAnalysis => _aiAnalysis ?? plan == Plan.premium;

  Map<String, Object?> toJson() => {
    'email': email,
    'plan': plan.code,
    if (usage != null) 'usedBytes': usage!.usedBytes,
    if (usage != null) 'quotaBytes': usage!.quotaBytes,
    if (_aiAnalysis != null) 'aiAnalysis': _aiAnalysis,
  };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.email == email &&
      other.plan == plan &&
      other.usage == usage &&
      other.aiAnalysis == aiAnalysis;

  @override
  int get hashCode => Object.hash(email, plan, usage, aiAnalysis);
}

/// Session ouverte sur le serveur : le jeton est un secret, à garder dans le stockage sécurisé.
final class Session {
  const Session({required this.token, required this.account});

  final String token;
  final Account account;

  Session copyWith({Account? account}) =>
      Session(token: token, account: account ?? this.account);
}
