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

/// Compte connecté, tel que décrit par le serveur.
final class Account {
  const Account({required this.email, required this.plan});

  factory Account.fromJson(Map<String, Object?> json) => Account(
    email: json['email']! as String,
    plan: Plan.fromCode(json['plan'] as String?),
  );

  final String email;
  final Plan plan;

  Map<String, Object?> toJson() => {'email': email, 'plan': plan.code};

  @override
  bool operator ==(Object other) =>
      other is Account && other.email == email && other.plan == plan;

  @override
  int get hashCode => Object.hash(email, plan);
}

/// Session ouverte sur le serveur : le jeton est un secret, à garder dans le stockage sécurisé.
final class Session {
  const Session({required this.token, required this.account});

  final String token;
  final Account account;

  Session copyWith({Account? account}) =>
      Session(token: token, account: account ?? this.account);
}
