/// Montants manipulés en texte décimal à 2 chiffres ("42.50") et additionnés en centimes
/// entiers : jamais d'arithmétique en `double`.
library;

/// Normalise une valeur JSON (nombre ou texte, virgule ou point) en "123.45", ou `null`.
String? normalizeAmount(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toStringAsFixed(2);
  final text = value.toString().trim().replaceAll(RegExp(r'[\s €$£]'), '');
  if (text.isEmpty) return null;
  final cents = parseCents(text.replaceAll(',', '.'));
  return cents == null ? null : formatCents(cents);
}

/// "35.5" → 3550 ; `null` si illisible.
int? parseCents(String amount) {
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(amount);
  if (match == null) return null;
  final sign = match.group(1) == '-' ? -1 : 1;
  final units = int.parse(match.group(2)!);
  final decimals = (match.group(3) ?? '').padRight(2, '0');
  return sign * (units * 100 + int.parse(decimals));
}

/// 3550 → "35.50".
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
