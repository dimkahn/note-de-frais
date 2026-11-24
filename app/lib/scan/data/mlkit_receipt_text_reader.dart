import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/receipt_text_reader.dart';
import 'text_rows.dart';

/// OCR Google ML Kit sur l'appareil (Android / iOS), modèle latin embarqué : aucun réseau.
final class MlKitReceiptTextReader implements ReceiptTextReader {
  const MlKitReceiptTextReader();

  @override
  Future<String?> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final text = assembleRows([
        for (final block in recognized.blocks)
          for (final line in block.lines)
            TextFragment(
              line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              bottom: line.boundingBox.bottom,
            ),
      ]);
      return text.isEmpty ? null : text;
    } finally {
      await recognizer.close();
    }
  }
}
