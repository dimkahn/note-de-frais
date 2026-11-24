import 'money.dart';
import '../../scan/domain/quad.dart';
import '../../scan/domain/receipt_parser.dart';
import '../../scan/domain/rotation.dart';

/// Type de dépense (aligné sur l'énumération `Category` du serveur).
enum ExpenseCategory {
  restaurant('RESTAURANT', 'Restaurant'),
  hotel('HOTEL', 'Hôtel'),
  transport('TRANSPORT', 'Transport'),
  train('TRAIN', 'Train'),
  avion('AVION', 'Avion'),
  taxi('TAXI', 'Taxi / VTC'),
  carburant('CARBURANT', 'Carburant'),
  peage('PEAGE', 'Péage'),
  parking('PARKING', 'Parking'),
  fournitures('FOURNITURES', 'Fournitures'),
  telecom('TELECOM', 'Télécom'),
  autre('AUTRE', 'Autre');

  const ExpenseCategory(this.code, this.label);

  final String code;
  final String label;

  static ExpenseCategory? fromCode(String? code) {
    if (code == null) return null;
    return values.firstWhere((c) => c.code == code, orElse: () => autre);
  }
}

/// Filtre de netteté appliqué par le serveur après recadrage.
enum ImageFilter {
  none('NONE', 'Aucun'),
  enhance('ENHANCE', 'Amélioré'),
  sharpen('SHARPEN', 'Netteté forte'),
  scanBw('SCAN_BW', 'Scan N&B');

  const ImageFilter(this.code, this.label);

  final String code;
  final String label;

  static ImageFilter fromCode(String? code) =>
      values.firstWhere((f) => f.code == code, orElse: () => enhance);
}

enum ProcessingStatus {
  pending('PENDING', 'Traitement en cours'),
  done('DONE', 'Traité'),
  extractionFailed('EXTRACTION_FAILED', 'À compléter'),

  /// Image traitée par le serveur, sans analyse IA (offre Gratuite) : les valeurs lues sur
  /// l'appareil ou saisies à la main font foi.
  notIncluded('NOT_INCLUDED', 'Analyse IA non incluse'),
  failed('FAILED', 'Échec du traitement');

  const ProcessingStatus(this.code, this.label);

  final String code;
  final String label;

  static ProcessingStatus fromCode(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => pending);
}

/// État de synchronisation local → serveur.
enum SyncState {
  synced,
  pendingUpload,
  pendingUpdate,
  pendingReprocess,
  pendingDelete,
}

/// Dépense, immuable. Les montants sont des textes décimaux exacts ("42.50").
final class Expense {
  const Expense({
    required this.id,
    this.merchant,
    this.category,
    this.expenseDate,
    this.amountTotal,
    this.amountVat,
    this.currency,
    this.city,
    this.country,
    this.address,
    this.paymentMethod,
    this.description,
    this.userEdited = false,
    this.prefilled = false,
    this.filter = ImageFilter.enhance,
    this.cropped = false,
    this.corners,
    this.rotation = Rotation.none,
    this.hasProcessedImage = false,
    this.status = ProcessingStatus.pending,
    this.processingError,
    this.deleted = false,
    this.createdAt,
    this.serverUpdatedAt,
    this.syncState = SyncState.synced,
    this.originalPath,
    this.processedPath,
  });

  /// Nouvelle dépense capturée sur l'appareil, pas encore envoyée.
  factory Expense.draft({
    required String id,
    required String originalPath,
    required ImageFilter filter,
  }) => Expense(
    id: id,
    filter: filter,
    originalPath: originalPath,
    createdAt: DateTime.now().toUtc(),
    syncState: SyncState.pendingUpload,
  );

  factory Expense.fromServerJson(Map<String, Object?> json) => Expense(
    id: json['id']! as String,
    merchant: json['merchant'] as String?,
    category: ExpenseCategory.fromCode(json['category'] as String?),
    expenseDate: _date(json['expenseDate']),
    amountTotal: normalizeAmount(json['amountTotal']),
    amountVat: normalizeAmount(json['amountVat']),
    currency: json['currency'] as String?,
    city: json['city'] as String?,
    country: json['country'] as String?,
    address: json['address'] as String?,
    paymentMethod: json['paymentMethod'] as String?,
    description: json['description'] as String?,
    userEdited: json['userEdited'] as bool? ?? false,
    filter: ImageFilter.fromCode(json['filter'] as String?),
    cropped: json['cropped'] as bool? ?? false,
    corners: _quad(json['corners']),
    rotation: Rotation.fromDegrees(json['rotation']),
    hasProcessedImage: json['hasProcessedImage'] as bool? ?? false,
    status: ProcessingStatus.fromCode(json['status'] as String?),
    processingError: json['processingError'] as String?,
    deleted: json['deleted'] as bool? ?? false,
    createdAt: _instant(json['createdAt']),
    serverUpdatedAt: _instant(json['updatedAt']),
  );

  factory Expense.fromDb(Map<String, Object?> row) => Expense(
    id: row['id']! as String,
    merchant: row['merchant'] as String?,
    category: ExpenseCategory.fromCode(row['category'] as String?),
    expenseDate: _date(row['expense_date']),
    amountTotal: row['amount_total'] as String?,
    amountVat: row['amount_vat'] as String?,
    currency: row['currency'] as String?,
    city: row['city'] as String?,
    country: row['country'] as String?,
    address: row['address'] as String?,
    paymentMethod: row['payment_method'] as String?,
    description: row['description'] as String?,
    userEdited: row['user_edited'] == 1,
    prefilled: row['prefilled'] == 1,
    filter: ImageFilter.fromCode(row['filter'] as String?),
    cropped: row['cropped'] == 1,
    corners: _quad(row['corners']),
    rotation: Rotation.fromDegrees(row['rotation']),
    hasProcessedImage: row['has_processed_image'] == 1,
    status: ProcessingStatus.fromCode(row['status'] as String?),
    processingError: row['processing_error'] as String?,
    deleted: row['deleted'] == 1,
    createdAt: _instant(row['created_at']),
    serverUpdatedAt: _instant(row['server_updated_at']),
    syncState: SyncState.values.byName(row['sync_state']! as String),
    originalPath: row['original_path'] as String?,
    processedPath: row['processed_path'] as String?,
  );

  final String id;
  final String? merchant;
  final ExpenseCategory? category;
  final DateTime? expenseDate;
  final String? amountTotal;
  final String? amountVat;
  final String? currency;
  final String? city;
  final String? country;
  final String? address;
  final String? paymentMethod;
  final String? description;
  final bool userEdited;

  /// Champs devinés par la lecture sur l'appareil, pas encore confirmés (ni par l'utilisateur,
  /// ni par l'analyse du serveur). Propre à l'appareil : jamais envoyé au serveur.
  final bool prefilled;
  final ImageFilter filter;
  final bool cropped;

  /// Contour choisi sur l'appareil ; `null` = détection automatique par le serveur.
  final Quad? corners;

  /// Quart de tour horaire du rendu, choisi sur l'appareil.
  final Rotation rotation;
  final bool hasProcessedImage;
  final ProcessingStatus status;
  final String? processingError;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? serverUpdatedAt;
  final SyncState syncState;

  /// Copie locale de la photo d'origine (jamais modifiée).
  final String? originalPath;

  /// Copie locale de l'image recadrée/améliorée par le serveur.
  final String? processedPath;

  /// Date utilisée pour trier/regrouper : date du justificatif, sinon date de capture.
  DateTime? get effectiveDate => expenseDate ?? createdAt?.toLocal();

  Map<String, Object?> toDb() => {
    'id': id,
    'merchant': merchant,
    'category': category?.code,
    'expense_date': _formatDate(expenseDate),
    'amount_total': amountTotal,
    'amount_vat': amountVat,
    'currency': currency,
    'city': city,
    'country': country,
    'address': address,
    'payment_method': paymentMethod,
    'description': description,
    'user_edited': userEdited ? 1 : 0,
    'prefilled': prefilled ? 1 : 0,
    'filter': filter.code,
    'cropped': cropped ? 1 : 0,
    'corners': corners?.format(),
    'rotation': rotation.degrees,
    'has_processed_image': hasProcessedImage ? 1 : 0,
    'status': status.code,
    'processing_error': processingError,
    'deleted': deleted ? 1 : 0,
    'created_at': createdAt?.toIso8601String(),
    'server_updated_at': serverUpdatedAt?.toIso8601String(),
    'sync_state': syncState.name,
    'original_path': originalPath,
    'processed_path': processedPath,
  };

  /// Corps de `PUT /api/expenses/{id}` (montants envoyés en texte : précision exacte).
  Map<String, Object?> toUpdateJson() => {
    'merchant': merchant,
    'category': category?.code,
    'expenseDate': _formatDate(expenseDate),
    'amountTotal': amountTotal,
    'amountVat': amountVat,
    'currency': currency,
    'city': city,
    'country': country,
    'address': address,
    'paymentMethod': paymentMethod,
    'description': description,
  };

  Expense copyWith({
    String? merchant,
    ExpenseCategory? category,
    DateTime? expenseDate,
    String? amountTotal,
    String? amountVat,
    String? currency,
    String? city,
    String? country,
    String? address,
    String? paymentMethod,
    String? description,
    bool? userEdited,
    bool? prefilled,
    ImageFilter? filter,
    bool? cropped,
    Quad? corners,
    Rotation? rotation,
    bool? hasProcessedImage,
    ProcessingStatus? status,
    String? processingError,
    bool? deleted,
    DateTime? serverUpdatedAt,
    SyncState? syncState,
    String? originalPath,
    String? processedPath,
  }) => Expense(
    id: id,
    merchant: merchant ?? this.merchant,
    category: category ?? this.category,
    expenseDate: expenseDate ?? this.expenseDate,
    amountTotal: amountTotal ?? this.amountTotal,
    amountVat: amountVat ?? this.amountVat,
    currency: currency ?? this.currency,
    city: city ?? this.city,
    country: country ?? this.country,
    address: address ?? this.address,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    description: description ?? this.description,
    userEdited: userEdited ?? this.userEdited,
    prefilled: prefilled ?? this.prefilled,
    filter: filter ?? this.filter,
    cropped: cropped ?? this.cropped,
    corners: corners ?? this.corners,
    rotation: rotation ?? this.rotation,
    hasProcessedImage: hasProcessedImage ?? this.hasProcessedImage,
    status: status ?? this.status,
    processingError: processingError ?? this.processingError,
    deleted: deleted ?? this.deleted,
    createdAt: createdAt,
    serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
    syncState: syncState ?? this.syncState,
    originalPath: originalPath ?? this.originalPath,
    processedPath: processedPath ?? this.processedPath,
  );

  /// Champs que la lecture sur l'appareil a pu remplir.
  ReceiptGuess get guess => ReceiptGuess(
    merchant: merchant,
    expenseDate: expenseDate,
    amountTotal: amountTotal,
    amountVat: amountVat,
    currency: currency,
  );

  /// Pré-remplit les champs vides avec ce que la lecture sur l'appareil a deviné. Sans effet sur une
  /// dépense corrigée à la main ou déjà analysée par le serveur. Ne change pas l'état de synchronisation :
  /// un pré-remplissage ne doit jamais partir au serveur comme une correction manuelle.
  Expense withDeviceGuess(ReceiptGuess guess) {
    if (userEdited || status == ProcessingStatus.done || guess.isEmpty) {
      return this;
    }
    return copyWith(
      merchant: merchant ?? guess.merchant,
      expenseDate: expenseDate ?? guess.expenseDate,
      amountTotal: amountTotal ?? guess.amountTotal,
      amountVat: amountVat ?? guess.amountVat,
      currency: currency ?? guess.currency,
      prefilled: true,
    );
  }

  /// Remplace l'ensemble des champs éditables (les valeurs `null` effacent le champ).
  Expense withEditedFields(Expense edited) => Expense(
    id: id,
    merchant: edited.merchant,
    category: edited.category,
    expenseDate: edited.expenseDate,
    amountTotal: edited.amountTotal,
    amountVat: edited.amountVat,
    currency: edited.currency,
    city: edited.city,
    country: edited.country,
    address: edited.address,
    paymentMethod: edited.paymentMethod,
    description: edited.description,
    userEdited: true,
    filter: filter,
    cropped: cropped,
    corners: corners,
    rotation: rotation,
    hasProcessedImage: hasProcessedImage,
    status: status,
    processingError: processingError,
    deleted: deleted,
    createdAt: createdAt,
    serverUpdatedAt: serverUpdatedAt,
    syncState: syncState == SyncState.pendingUpload
        ? syncState
        : SyncState.pendingUpdate,
    originalPath: originalPath,
    processedPath: processedPath,
  );

  @override
  bool operator ==(Object other) =>
      other is Expense && _props.toString() == other._props.toString();

  @override
  int get hashCode => Object.hashAll(_props);

  List<Object?> get _props => toDb().values.toList();

  @override
  String toString() =>
      'Expense($id, $merchant, $amountTotal $currency, ${syncState.name})';
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final d = DateTime.tryParse(value);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime? _instant(Object? value) => value is String && value.isNotEmpty
    ? DateTime.tryParse(value)?.toUtc()
    : null;

String? _formatDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Quad? _quad(Object? value) =>
    value is String && value.isNotEmpty ? Quad.parse(value) : null;
