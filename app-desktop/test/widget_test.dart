// Smoke test básico de la app de escritorio.
import 'package:flutter_test/flutter_test.dart';

import 'package:app_desktop/models.dart';

void main() {
  test('Mensaje.fromJson parsea correctamente', () {
    final m = Mensaje.fromJson({
      'id': '1',
      'rol': 'asistente',
      'contenido': 'Hola',
      'latencia_segundos': 1.5,
    });
    expect(m.rol, 'asistente');
    expect(m.contenido, 'Hola');
    expect(m.esUsuario, false);
  });

  test('Usuario.esAdmin', () {
    final u = Usuario.fromJson({
      'id': 'x',
      'nombre': 'Admin',
      'email': 'a@b.com',
      'rol': 'administrador',
    });
    expect(u.esAdmin, true);
  });
}
