import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/server_config.dart';

void main() {
  test('un build debug ou profile vise le serveur local', () {
    expect(buildServerUrl(release: false), 'http://localhost:8080');
  });

  test('un build release vise le serveur de production en https', () {
    expect(buildServerUrl(release: true), 'https://api.notedefrais.fr');
  });
}
