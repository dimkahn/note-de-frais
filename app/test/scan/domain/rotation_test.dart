import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';

void main() {
  test('pivoter ajoute un quart de tour horaire, et revient au départ après quatre', () {
    var r = Rotation.none;

    r = r.next();
    expect(r, Rotation.clockwise90);
    r = r.next().next().next();

    expect(r, Rotation.none);
  });

  test('se lit et s\'écrit en degrés horaires', () {
    expect(Rotation.fromDegrees(270), Rotation.clockwise270);
    expect(Rotation.clockwise180.degrees, 180);
  });

  test('une valeur absente ou inconnue ne pivote pas', () {
    expect(Rotation.fromDegrees(null), Rotation.none);
    expect(Rotation.fromDegrees(45), Rotation.none);
  });
}
