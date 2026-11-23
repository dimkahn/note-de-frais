/// Champs devinés à partir du texte d'un justificatif ; tous optionnels.
final class ReceiptGuess {
  const ReceiptGuess({
    this.merchant,
    this.expenseDate,
    this.amountTotal,
    this.amountVat,
    this.currency,
  });

  final String? merchant;
  final DateTime? expenseDate;

  /// Montants décimaux exacts en texte ("42.50"), comme dans `Expense`.
  final String? amountTotal;
  final String? amountVat;
  final String? currency;

  bool get isEmpty =>
      merchant == null &&
      expenseDate == null &&
      amountTotal == null &&
      amountVat == null &&
      currency == null;
}

/// Devine montant TTC, TVA, date, devise et commerçant dans le texte d'un ticket ou d'une facture
/// (lu par OCR sur l'appareil). Règles pensées pour les justificatifs français ; un champ non
/// trouvé reste `null` plutôt que d'être inventé.
final class ReceiptParser {
  const ReceiptParser();

  ReceiptGuess parse(String text) {
    final lines = [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final total = _total(lines);
    final vat = _vat(lines);
    return ReceiptGuess(
      merchant: _merchant(lines),
      expenseDate: _date(lines),
      amountTotal: _format(total),
      amountVat: _format(
        vat != null && (total == null || vat < total) ? vat : null,
      ),
      currency: _currency(text),
    );
  }

  // --- Montants (en centimes) ---

  /// Montant avec 2 décimales ; ni morceau de date (14.03.26), ni pourcentage (10,00 %).
  static final _amount = RegExp(
    r'(?<![\d.,])(\d{1,3}(?:[  .,]\d{3})+|\d+)[.,](\d{2})(?![\d%]|[.,]\d|\s%)',
  );

  /// Centimes mal reconnus par l'OCR : lettre O pour zéro, espace après la virgule (« 304. O0 »).
  /// L'espace n'est toléré qu'en fin de ligne (devise éventuelle) : « 3, 25 pièces » n'est pas un
  /// montant.
  static final _ocrCents = RegExp(
    r'(\d)([.,])(?:([0-9Oo]{2})(?![\dOo])| ([0-9Oo]{2})(?=\s*(?:€|EUR)?\s*$))',
  );

  static String _fixOcrCents(String line) => line.replaceAllMapped(
    _ocrCents,
    (m) => '${m[1]}${m[2]}${(m[3] ?? m[4])!.replaceAll(RegExp('[Oo]'), '0')}',
  );

  static List<int> _amounts(String line) => [
    for (final m in _amount.allMatches(_fixOcrCents(line)))
      int.parse(m[1]!.replaceAll(RegExp(r'\D'), '')) * 100 + int.parse(m[2]!),
  ];

  static const _totalKeys = [
    'TOTAL',
    'TTC',
    'A PAYER',
    'A REGLER',
    'MONTANT DU',
  ];
  static const _cashKeys = ['ESPECE', 'RENDU', 'MONNAIE', 'CHANGE'];

  /// Le plus grand montant des lignes « total » (TTC ≥ HT) ; à défaut, le plus grand montant
  /// hors espèces données et monnaie rendue.
  static int? _total(List<String> lines) {
    final candidates = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final f = _fold(lines[i]);
      if (!_totalKeys.any(f.contains) || f.contains('SOUS')) continue;
      var amounts = _amounts(lines[i]);
      if (amounts.isEmpty &&
          i + 1 < lines.length &&
          _isAmountOnly(lines[i + 1])) {
        amounts = _amounts(lines[i + 1]);
      }
      candidates.addAll(amounts);
    }
    if (candidates.isEmpty) {
      for (final line in lines) {
        if (!_cashKeys.any(_fold(line).contains)) {
          candidates.addAll(_amounts(line));
        }
      }
    }
    return _max(candidates);
  }

  /// Ligne réduite à un montant (et sa devise) : la valeur d'un mot-clé posé seul sur la ligne
  /// précédente (« NET A PAYER » / « 42,50 »), pas une ligne d'article sous un en-tête de colonne
  /// (« PRIX TTC »).
  static bool _isAmountOnly(String line) =>
      RegExp(r'^\s*(?:€|EUR|EUROS?)?\s*$')
          .hasMatch(_fold(_fixOcrCents(line).replaceAll(_amount, '')));

  /// Une ligne « total TVA » si elle existe, sinon la somme des lignes par taux (le plus petit
  /// montant de chaque ligne : la TVA est inférieure à la base HT et au TTC).
  static int? _vat(List<String> lines) {
    final perRate = <int>[];
    final totals = <int>[];
    for (final line in lines) {
      final f = _fold(line);
      if (!f.contains('TVA') && !f.contains('T.V.A')) continue;
      final amounts = _amounts(line);
      if (amounts.isEmpty) continue;
      if (f.contains('TOTAL')) {
        totals.add(_max(amounts)!);
      } else {
        perRate.add(amounts.reduce((a, b) => a < b ? a : b));
      }
    }
    if (totals.isNotEmpty) return _max(totals);
    return perRate.isEmpty ? null : perRate.reduce((a, b) => a + b);
  }

  static int? _max(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);

  static String? _format(int? cents) => cents == null
      ? null
      : '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  // --- Date ---

  static final _isoDate = RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)');
  static final _numericDate = RegExp(
    r'(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?!\d)',
  );
  static final _textDate = RegExp(
    r'(?<!\d)(\d{1,2})(?:ER)?\s+(JANV|FEVR|MARS|AVR|MAI|JUIN|JUIL|AOUT|SEPT|OCT|NOV|DEC)[A-Z]*\.?\s+(\d{4})(?!\d)',
  );
  static const _months = {
    'JANV': 1,
    'FEVR': 2,
    'MARS': 3,
    'AVR': 4,
    'MAI': 5,
    'JUIN': 6,
    'JUIL': 7,
    'AOUT': 8,
    'SEPT': 9,
    'OCT': 10,
    'NOV': 11,
    'DEC': 12,
  };

  static DateTime? _date(List<String> lines) {
    for (final line in lines) {
      final f = _fold(line);
      for (final m in _isoDate.allMatches(f)) {
        final d = _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        if (d != null) return d;
      }
      for (final m in _numericDate.allMatches(f)) {
        final y = int.parse(m[3]!);
        final d = _valid(
          y < 100 ? 2000 + y : y,
          int.parse(m[2]!),
          int.parse(m[1]!),
        );
        if (d != null) return d;
      }
      for (final m in _textDate.allMatches(f)) {
        final d = _valid(int.parse(m[3]!), _months[m[2]]!, int.parse(m[1]!));
        if (d != null) return d;
      }
    }
    return null;
  }

  static DateTime? _valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return null;
    final date = DateTime(y, m, d);
    return date.month == m && date.day == d ? date : null;
  }

  // --- Devise et commerçant ---

  static String? _currency(String text) {
    final f = _fold(text);
    bool has(String pattern) => RegExp(pattern).hasMatch(f);
    if (has(r'€|\bEUR\b')) return 'EUR';
    if (has(r'\bCHF\b')) return 'CHF';
    if (has(r'£|\bGBP\b')) return 'GBP';
    if (has(r'\$|\bUSD\b')) return 'USD';
    return null;
  }

  static const _noise = [
    'BIENVENUE',
    'TICKET',
    'FACTURE',
    'CAISSE',
    'MERCI',
    'RECU',
    'DUPLICATA',
    'CLIENT',
  ];

  /// Première ligne significative de l'en-tête : du texte, pas un montant, une date ou une formule.
  static String? _merchant(List<String> lines) {
    for (final line in lines.take(6)) {
      final f = _fold(line);
      final letters = RegExp('[A-Z]').allMatches(f).length;
      final digits = RegExp(r'\d').allMatches(f).length;
      if (letters < 3 || digits > letters) continue;
      if (_noise.any(f.contains) || _amounts(line).isNotEmpty) continue;
      if (_date([line]) != null) continue;
      return line
          .replaceAll(RegExp(r'^[^\p{L}\d]+|[^\p{L}\d]+$', unicode: true), '')
          .replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }

  /// Majuscules sans accents, pour comparer des mots-clés lus par OCR.
  static String _fold(String s) {
    const from = 'ÀÂÄÁÉÈÊËÎÏÍÔÖÓÙÛÜÚÇ';
    const to = 'AAAAEEEEIIIOOOUUUUC';
    final upper = s.toUpperCase();
    final out = StringBuffer();
    for (final ch in upper.split('')) {
      final i = from.indexOf(ch);
      out.write(i < 0 ? ch : to[i]);
    }
    return out.toString();
  }
}
