import 'package:flutter/foundation.dart';

// Adresse du serveur par type de build. Pour la changer :
// - modifier ces constantes (le serveur de production, une fois déployé) ;
// - ou, au lancement, `--dart-define=API_URL=https://…` (prioritaire sur les deux) ;
// - ou, sur l'appareil, Compte › Avancé › Adresse du serveur (surcharge enregistrée).

/// Builds debug et profile : le serveur du PC, joint par le câble USB
/// (`adb reverse tcp:8080 tcp:8080`).
const devServerUrl = 'http://localhost:8080';

/// Build release. Provisoire : à remplacer quand le serveur sera déployé.
const prodServerUrl = 'https://api.notedefrais.fr';

/// Adresse du serveur selon le type de build.
String buildServerUrl({required bool release}) =>
    release ? prodServerUrl : devServerUrl;

/// Adresse imposée au build par `--dart-define=API_URL=...` (vide sinon).
const _apiUrl = String.fromEnvironment('API_URL');

/// Adresse utilisée quand aucune n'est saisie dans l'app : `API_URL` si fournie au build,
/// sinon celle du type de build.
String get defaultServerUrl =>
    _apiUrl.isNotEmpty ? _apiUrl : buildServerUrl(release: kReleaseMode);
