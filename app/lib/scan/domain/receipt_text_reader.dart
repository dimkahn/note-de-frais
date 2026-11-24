/// Frontière vers la reconnaissance de texte (OCR) de l'appareil.
abstract interface class ReceiptTextReader {
  /// Texte lu sur l'image, lignes séparées par `\n` ; `null` si rien n'a pu être lu.
  Future<String?> read(String imagePath);
}
