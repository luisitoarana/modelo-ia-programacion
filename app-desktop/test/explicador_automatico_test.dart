import 'package:flutter_test/flutter_test.dart';
import 'package:app_desktop/services/explicador_automatico.dart';

void main() {
  test('comentario después de un literal no inventa comilla faltante', () {
    final resultado = ExplicadorAutomatico.analizar(
      "producto = 'Cuaderno' # texto de ejemplo",
    );
    expect(resultado.erroresSintacticos, isEmpty);
    expect(resultado.variables.single.valorLiteral, "'Cuaderno'");
  });

  test('comentario después de dos puntos no inventa error en for', () {
    final resultado = ExplicadorAutomatico.analizar(
      'for numero in range(1, 6): # recorrer cinco números\n'
      '    print(numero)',
    );
    expect(resultado.erroresSintacticos, isEmpty);
    expect(resultado.estructuras.first.tieneDosPuntos, isTrue);
  });

  test('almohadilla dentro de una cadena sigue siendo parte del texto', () {
    final resultado = ExplicadorAutomatico.analizar("etiqueta = '#Python'");
    expect(resultado.erroresSintacticos, isEmpty);
    expect(resultado.variables.single.valorLiteral, "'#Python'");
  });
}
