import 'dart:convert';

import '../../services/curriculum_catalog.dart';

/// Los registros anteriores a la captura de la pregunta conservan el código,
/// pero su enunciado solo puede consultarse en la versión actual del catálogo.
String preguntaDelIntento(Map<String, dynamic> intento) {
  final registrada = intento['pregunta']?.toString().trim() ?? '';
  if (registrada.isNotEmpty) return registrada;
  final id = switch (intento['leccion_id']) {
    'm1_l4_indentacion_reglas' => 'm1_l4_indentacion',
    'm2_l3_listas_colecciones' => 'm2_l3_listas_indexacion',
    final otro => otro,
  };
  for (final leccion in CurriculumCatalog.lecciones) {
    if (leccion.id == id) {
      return leccion.preguntaAutoevaluacion;
    }
  }
  return '¿Qué hará este código y qué salida o resultado esperas?';
}

String origenPregunta(Map<String, dynamic> intento) =>
    (intento['pregunta']?.toString().trim().isNotEmpty ?? false)
    ? 'registrada_con_el_intento'
    : 'catalogo_actual_no_registrada';

Map<String, dynamic> _evidencia(Map<String, dynamic> intento) {
  final revision = intento['revision_docente'] as Map?;
  return {
    'intento_id': intento['id'],
    'usuario_id': intento['usuario_id'],
    'estudiante': intento['usuario_nombre'],
    'email': intento['usuario_email'],
    'fecha': intento['fecha_creacion'],
    'leccion_id': intento['leccion_id'],
    'fase': intento['fase'],
    'modo': intento['modo'],
    'pregunta': preguntaDelIntento(intento),
    'origen_pregunta': origenPregunta(intento),
    'codigo_inicial': intento['codigo_inicial'],
    'respuesta_inicial': intento['prediccion'],
    'explicacion_propia': intento['explicacion_propia'],
    'codigo_final': intento['codigo_final'],
    'pistas_usadas': intento['pistas_usadas'],
    'duracion_segundos': intento['duracion_segundos'],
    'estado_revision': revision == null ? 'pendiente' : 'revisado_por_docente',
    'comprension': revision?['comprension'],
    'codigo': revision?['codigo'],
    'casos_limite': revision?['casos_limite'],
    'puntaje': revision?['puntaje'],
    'observaciones': revision?['observaciones'],
    'docente_id': revision?['docente_id'],
    'fecha_revision': revision?['fecha_actualizacion'],
  };
}

String exportarIntentosJson(List<Map<String, dynamic>> intentos) =>
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'cantidad': intentos.length,
      'intentos': intentos.map(_evidencia).toList(),
    });

String exportarIntentosCsv(List<Map<String, dynamic>> intentos) {
  if (intentos.isEmpty) return '';
  final registros = intentos.map(_evidencia).toList();
  String celda(Object? valor) {
    var texto = valor?.toString() ?? '';
    // Un texto escrito por un estudiante debe abrirse como texto en Excel.
    // JSON conserva el contenido exacto cuando se necesita procesarlo.
    if (RegExp(r'^\s*[=+@-]').hasMatch(texto)) texto = "'$texto";
    return '"${texto.replaceAll('"', '""')}"';
  }

  return '\uFEFF${[registros.first.keys.map(celda).join(','), ...registros.map((fila) => fila.values.map(celda).join(','))].join('\r\n')}\r\n';
}
