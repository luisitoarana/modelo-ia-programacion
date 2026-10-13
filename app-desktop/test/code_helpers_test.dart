import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/code/code_helpers.dart';

void main() {
  test('extrae varios archivos de una propuesta y conserva su contenido', () {
    final archivos = extraerArchivosPropuestos(
      'ARCHIVO: backend/main.py\n\n```python\nprint("hola")\n```\n'
      'ARCHIVO: backend/requirements.txt\n```text\nfastapi\n```',
    );
    expect(archivos.length, 2);
    expect(archivos.first.rutaRelativa, 'backend/main.py');
    expect(archivos.first.contenido, 'print("hola")');
  });

  test('rechaza rutas que escapan del proyecto', () {
    expect(rutaPropuestaSegura('backend/main.py'), isTrue);
    expect(rutaPropuestaSegura('../fuera.py'), isFalse);
    expect(rutaPropuestaSegura('C:/fuera.py'), isFalse);
    expect(rutaPropuestaSegura('/fuera.py'), isFalse);
  });

  test('selección sin foco -1 no arroja RangeError', () {
    final controller = TextEditingController(text: 'print(1)');
    expect(controller.selection.start, -1);
    expect(textoSeleccionadoSeguro(controller), '');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    expect(textoSeleccionadoSeguro(controller), 'print');
    controller.dispose();
  });

  test('reconoce solicitud de corrección y confirmación breve', () {
    expect(esPeticionDeCambio('Corrige este error'), isTrue);
    expect(esPeticionDeCambio('Cómo corregirlo'), isTrue);
    expect(esPeticionDeCambio('Corrígelo'), isTrue);
    expect(esPeticionDeCambio('¿Qué es una variable?'), isFalse);
    expect(esConfirmacionDeCambio('Sí, corrígelo.'), isTrue);
    expect(esConfirmacionDeCambio('de acuerdo'), isTrue);
  });
}
