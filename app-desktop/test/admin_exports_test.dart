import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_desktop/widgets/settings/admin_exports.dart';

void main() {
  final intento = <String, dynamic>{
    'id': 'intento-1',
    'usuario_id': 'estudiante-1',
    'usuario_nombre': 'Ana',
    'usuario_email': 'ana@example.test',
    'leccion_id': 'm1_l1_variables',
    'pregunta': '¿Qué guarda edad?',
    'fase': 'pre',
    'modo': 'bloqueado_post_test',
    'codigo_inicial': 'edad = 20\nprint(edad)',
    'codigo_final': 'print(20)',
    'prediccion': '20, porque guarda un número.\nUna segunda línea.',
    'explicacion_propia': 'Dice "20".',
    'revision_docente': {
      'comprension': 4,
      'codigo': 4,
      'casos_limite': 2,
      'puntaje': 10,
      'observaciones': 'Idea correcta.',
    },
  };

  test(
    'JSON conserva pregunta, identidad, código y rúbrica sin alterar respuestas',
    () {
      final datos = jsonDecode(exportarIntentosJson([intento])) as Map;
      final fila = (datos['intentos'] as List).single as Map;
      expect(fila['pregunta'], '¿Qué guarda edad?');
      expect(fila['origen_pregunta'], 'registrada_con_el_intento');
      expect(fila['email'], 'ana@example.test');
      expect(fila['codigo_inicial'], intento['codigo_inicial']);
      expect(fila['respuesta_inicial'], intento['prediccion']);
      expect(fila['puntaje'], 10);
    },
  );

  test('CSV preserva saltos, comas y comillas; evita ejecutar fórmulas', () {
    final csv = exportarIntentosCsv([
      {...intento, 'prediccion': '=1+1'},
    ]);
    expect(csv, startsWith('\uFEFF'));
    expect(csv, contains('"\'=1+1"'));
    expect(csv, contains('"Dice ""20""."'));
    expect(csv, contains('"edad = 20\nprint(edad)"'));
  });

  test(
    'los intentos antiguos identifican el enunciado derivado del catálogo',
    () {
      final antiguo = {...intento}..remove('pregunta');
      expect(origenPregunta(antiguo), 'catalogo_actual_no_registrada');
      expect(preguntaDelIntento(antiguo), contains('estudiante y edad'));
    },
  );
}
