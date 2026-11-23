import 'package:note_de_frais/data/google_auth.dart';

/// Double du compte Google de l'appareil : rend un jeton d'identité, ou `null` (annulation).
final class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.token = 'jeton-google'});

  String? token;
  var prompts = 0;

  @override
  Future<String?> idToken() async {
    prompts++;
    return token;
  }
}
