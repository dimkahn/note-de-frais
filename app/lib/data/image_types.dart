import 'package:path/path.dart' as p;

/// Type MIME d'une image enregistrée sur l'appareil, d'après son extension.
String contentTypeOfPath(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      _ => 'image/jpeg',
    };

/// Extension de fichier d'une image reçue du serveur, d'après son type MIME.
String extensionOfContentType(String contentType) =>
    switch (contentType.split(';').first.trim()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      _ => 'jpg',
    };
