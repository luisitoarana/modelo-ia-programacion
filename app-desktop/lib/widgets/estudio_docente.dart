import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers.dart';
import '../services/dialogos_nativos.dart';
import 'evaluacion_estudio.dart';

Future<void> abrirEstudioDocente(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const Dialog(
    child: SizedBox(width: 1080, height: 760, child: EstudioDocente()),
  ),
);

class TareasIntervencion extends StatefulWidget {
  const TareasIntervencion({super.key});
  @override
  State<TareasIntervencion> createState() => _TareasIntervencionState();
}

class _TareasIntervencionState extends State<TareasIntervencion> {
  Future<void> _ver() async {
    try {
      final datos = await context.read<AuthProvider>().api.estudioActual();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tareas comunes de intervención'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ambos grupos trabajan estas tareas con el mismo motor. En generación directa se entrega código; con andamiaje puedes pedir explicaciones y razonar sobre los cambios.',
                  ),
                  for (final t in datos['tareas'] as List? ?? [])
                    ListTile(
                      title: Text('Módulo ${t['modulo']}'),
                      subtitle: SelectableText(t['consigna'] as String),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Volver al trabajo'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListTile(
      dense: true,
      title: const Text('Intervención · tareas comunes de los tres módulos'),
      trailing: OutlinedButton(
        onPressed: _ver,
        child: const Text('Ver tareas'),
      ),
    ),
  );
}

class EstudioDocente extends StatefulWidget {
  const EstudioDocente({super.key});
  @override
  State<EstudioDocente> createState() => _EstudioDocenteState();
}

class _EstudioDocenteState extends State<EstudioDocente> {
  Map<String, dynamic>? _config, _datos;
  bool _ocupado = false, _ciega = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final valores = await Future.wait([
        api.configuracionEstudio(),
        api.resumenEstudio(),
      ]);
      if (mounted)
        setState(() {
          _config = valores[0];
          _datos = valores[1];
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _configurar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().api.configurarEstudio({
        for (final k in [
          'estudio_activo',
          'pre_abierto',
          'post_abierto',
          'practica_guiada',
          'preguntas_activas',
        ])
          k: _config![k],
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración aplicada en el servidor.'),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _fase(Map u) async {
    var fase = u['fase']?.toString() ?? 'pre';
    var condicion = u['condicion']?.toString() ?? 'con_acompanamiento';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, cambiar) => AlertDialog(
          title: Text('Asignar a ${u['nombre']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: condicion,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: const [
                  DropdownMenuItem(
                    value: 'con_acompanamiento',
                    child: Text('Con andamiaje explicativo'),
                  ),
                  DropdownMenuItem(
                    value: 'sin_acompanamiento',
                    child: Text('Generación directa'),
                  ),
                ],
                onChanged: (v) => cambiar(() => condicion = v!),
              ),
              DropdownButtonFormField<String>(
                initialValue: fase,
                decoration: const InputDecoration(labelText: 'Fase'),
                items: const [
                  DropdownMenuItem(
                    value: 'pre',
                    child: Text('Pretest sin ayuda'),
                  ),
                  DropdownMenuItem(
                    value: 'intervencion',
                    child: Text('Intervención'),
                  ),
                  DropdownMenuItem(
                    value: 'post',
                    child: Text('Postest sin ayuda'),
                  ),
                ],
                onChanged: (v) => cambiar(() => fase = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthProvider>().api.asignarEstudio(
        u['usuario_id'],
        condicion,
        fase,
      );
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _autorizar(Map u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorizar una cuenta docente'),
        content: Text(
          '${u['nombre']} podrá revisar entregas y gestionar fases. Debe ser una cuenta nueva de la persona que evaluará, no un participante ni la cuenta pública.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Autorizar docente'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthProvider>().api.autorizarDocente(u['usuario_id']);
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _revisar(Map e, Map p) async {
    final previa = (e['revisiones'] as Map? ?? {})[p['id']] as Map? ?? {};
    int comprension = previa['comprension'] as int? ?? 0;
    int codigo = previa['codigo'] as int? ?? 0;
    int casos = previa['casos_limite'] as int? ?? 0;
    var observaciones = previa['observaciones']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, cambiar) => AlertDialog(
          title: Text('Rúbrica · ${p['competencia']}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Valora el contenido, no la extensión. Código equivalente es válido. Una respuesta incorrecta o incompleta también es evidencia; no se elimina.',
                  ),
                  _puntuar(
                    'Comprensión y explicación',
                    comprension,
                    4,
                    (v) => cambiar(() => comprension = v),
                  ),
                  _puntuar(
                    'Código y resultado',
                    codigo,
                    4,
                    (v) => cambiar(() => codigo = v),
                  ),
                  _puntuar(
                    'Caso límite / dato alternativo',
                    casos,
                    2,
                    (v) => cambiar(() => casos = v),
                  ),
                  TextFormField(
                    initialValue: observaciones,
                    onChanged: (v) => observaciones = v,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Justificación docente',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar calificación humana'),
            ),
          ],
        ),
      ),
    );
    final texto = observaciones;
    if (ok != true || !mounted) return;
    try {
      await context
          .read<AuthProvider>()
          .api
          .revisarEvaluacion(e['id'], p['id'], {
            'comprension': comprension,
            'codigo': codigo,
            'casos_limite': casos,
            'observaciones': texto,
          });
      await _cargar();
    } catch (ex) {
      if (mounted) setState(() => _error = '$ex');
    }
  }

  Widget _puntuar(
    String nombre,
    int valor,
    int maximo,
    ValueChanged<int> cambiar,
  ) => Row(
    children: [
      Expanded(child: Text(nombre)),
      DropdownButton<int>(
        value: valor,
        items: [
          for (var n = 0; n <= maximo; n++)
            DropdownMenuItem(value: n, child: Text('$n')),
        ],
        onChanged: (v) {
          if (v != null) cambiar(v);
        },
      ),
    ],
  );
  Future<void> _exportar(String formato) async {
    try {
      final carpeta = await DialogosNativos.seleccionarCarpeta(
        titulo: 'Guardar evidencias pre/post',
      );
      if (carpeta == null || !mounted) return;
      final filas = <Map<String, dynamic>>[];
      for (final e in _datos!['entregas'] as List) {
        for (final p in e['preguntas'] as List) {
          final r = (e['respuestas'] as Map)[p['id']] as Map? ?? {};
          final nota = (e['revisiones'] as Map)[p['id']] as Map? ?? {};
          filas.add({
            'entrega_id': e['id'],
            'participante': e['seudonimo'],
            if (!_ciega) ...{
              'usuario_id': e['usuario_id'],
              'fase': e['fase'],
              'grupo': e['condicion'],
            },
            'version': e['version'],
            'pregunta_id': p['id'],
            'modulo': p['modulo'],
            'consigna': p['consigna'],
            'codigo': r['codigo'],
            'explicacion': r['explicacion'],
            'sin_responder': r['sin_responder'],
            'estado': e['estado'],
            'inicio': e['iniciada_en'],
            'entrega': e['enviada_en'],
            'comprension': nota['comprension'],
            'codigo_nota': nota['codigo'],
            'casos_limite': nota['casos_limite'],
            'observaciones': nota['observaciones'],
            'docente_id': nota['docente_id'],
            'fecha_revision': nota['revisada_en'],
          });
        }
      }
      String contenido;
      if (formato == 'json') {
        contenido = const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'revision_ciega': _ciega,
          'respuestas': filas,
          if (!_ciega) 'participantes': _datos!['participantes'],
        });
      } else {
        String celda(dynamic v) {
          var s = v?.toString() ?? '';
          if (RegExp(r'^\s*[=+@\-]').hasMatch(s)) s = "'$s";
          return '"${s.replaceAll('"', '""')}"';
        }

        contenido = filas.isEmpty
            ? ''
            : '\uFEFF${filas.first.keys.map(celda).join(',')}\r\n${filas.map((r) => r.values.map(celda).join(',')).join('\r\n')}';
      }
      final archivo = File(
        '$carpeta${Platform.pathSeparator}pre_post_${DateTime.now().millisecondsSinceEpoch}.$formato',
      );
      await archivo.writeAsString(contenido, flush: true);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Evidencias guardadas: ${archivo.path}')),
        );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: const Text('Pretest, postest y revisión docente'),
        trailing: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      if (_ocupado) const LinearProgressIndicator(),
      Wrap(
        spacing: 12,
        children: [
          for (final fase in ['pre', 'post'])
            OutlinedButton.icon(
              onPressed: () => abrirVistaPreviaEvaluacion(context, fase),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(
                fase == 'pre' ? 'Vista previa pretest' : 'Vista previa postest',
              ),
            ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      Expanded(
        child: _config == null || _datos == null
            ? Center(
                child: TextButton(
                  onPressed: _cargar,
                  child: const Text('Cargar estudio'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Instrumento piloto para revisión del profesor. Seis tareas: dos por módulo. Las preguntas abiertas son equivalentes en competencia, todavía no validadas en dificultad.',
                  ),
                  for (final entrada in {
                    'estudio_activo':
                        'Activar estudio: exigir asignación y pretest antes de usar IA',
                    'pre_abierto': 'Abrir pretest',
                    'post_abierto': 'Abrir postest',
                    'practica_guiada':
                        'Pedir predicción y respuesta antes de explicar durante la intervención',
                  }.entries)
                    SwitchListTile(
                      title: Text(entrada.value),
                      value: _config![entrada.key] == true,
                      onChanged: _ocupado
                          ? null
                          : (v) => setState(() => _config![entrada.key] = v),
                    ),
                  const Text(
                    'Selecciona las preguntas para los nuevos pretests. Cada postest conserva las competencias de su pretest. Los instrumentos iniciados no cambian.',
                  ),
                  for (final p in _config!['banco'] as List)
                    CheckboxListTile(
                      title: Text(
                        'Módulo ${p['modulo']} · ${p['competencia']}',
                      ),
                      subtitle: Text('Pre: ${p['pre']}\nPost: ${p['post']}'),
                      value: (_config!['preguntas_activas'] as List).contains(
                        p['id'],
                      ),
                      onChanged: _ocupado
                          ? null
                          : (v) => setState(() {
                              final ids = List<String>.from(
                                _config!['preguntas_activas'],
                              );
                              if (v == true) {
                                ids.add(p['id']);
                              } else {
                                ids.remove(p['id']);
                              }
                              _config!['preguntas_activas'] = ids;
                            }),
                    ),
                  FilledButton(
                    onPressed: _ocupado ? null : _configurar,
                    child: const Text('Aplicar activación y preguntas'),
                  ),
                  const Divider(),
                  const Text(
                    'Participantes y avance · solo notas humanas, no inferencias de la IA',
                  ),
                  for (final u in _datos!['participantes'] as List)
                    ListTile(
                      title: Text(
                        '${u['nombre']} · ${u['seudonimo']}${u['demostracion'] == true ? ' · DEMOSTRACIÓN' : ''}',
                      ),
                      subtitle: Text(
                        '${u['condicion'] ?? 'sin grupo'} · ${u['fase'] ?? 'sin fase'}\n${_avance(u['comparacion'] as Map)}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _fase(u as Map),
                            child: const Text('Asignar grupo/fase'),
                          ),
                          if (context.read<AuthProvider>().usuario?.esAdmin ==
                                  true &&
                              u['demostracion'] != true)
                            TextButton(
                              onPressed: () => _autorizar(u as Map),
                              child: const Text('Autorizar docente'),
                            ),
                        ],
                      ),
                    ),
                  const Text(
                    'Una diferencia post − pre es descriptiva; no demuestra por sí sola un efecto causal. La cuenta de demostración se identifica para excluirla del análisis real.',
                  ),
                  const Divider(),
                  CheckboxListTile(
                    value: _ciega,
                    onChanged: (v) => setState(() => _ciega = v == true),
                    title: const Text(
                      'Revisión ciega: ocultar identidad, grupo y fase en las entregas y exportaciones',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _exportar('csv'),
                        child: const Text('Exportar pre/post CSV'),
                      ),
                      OutlinedButton(
                        onPressed: () => _exportar('json'),
                        child: const Text('Exportar pre/post JSON'),
                      ),
                      TextButton(
                        onPressed: _cargar,
                        child: const Text('Actualizar entregas'),
                      ),
                    ],
                  ),
                  for (final e in _datos!['entregas'] as List)
                    Card(
                      child: ExpansionTile(
                        key: PageStorageKey('entrega-${e['id']}'),
                        title: Text(
                          _ciega
                              ? 'Entrega ${e['id']}'
                              : '${e['seudonimo']} · ${e['fase']} · ${e['condicion']}',
                        ),
                        subtitle: Text(
                          '${e['estado']} · ${e['puntaje'] == null ? 'Pendiente de revisión completa' : '${e['puntaje']}/${e['maximo']}'}',
                        ),
                        children: [
                          for (final p in e['preguntas'] as List)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    'Módulo ${p['modulo']} · ${p['consigna']}',
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    'Código:\n${(e['respuestas'] as Map)[p['id']]?['codigo'] ?? ''}\n\nExplicación:\n${(e['respuestas'] as Map)[p['id']]?['explicacion'] ?? ''}',
                                  ),
                                  if ((e['respuestas']
                                          as Map)[p['id']]?['sin_responder'] ==
                                      true)
                                    const Text('Entregada sin responder'),
                                  if ((e['revisiones'] as Map)[p['id']] != null)
                                    Text(
                                      'Revisión: ${(e['revisiones'] as Map)[p['id']]}',
                                    ),
                                  if (e['estado'] == 'enviado')
                                    TextButton(
                                      onPressed: () =>
                                          _revisar(e as Map, p as Map),
                                      child: const Text(
                                        'Calificar con rúbrica 0–10',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
  String _avance(Map c) => c['estado'] == 'revisado'
      ? 'Pre: ${c['pre_porcentaje']}% · Post: ${c['post_porcentaje']}% · Cambio: ${c['cambio_puntos_porcentuales']} puntos porcentuales'
      : c['estado'] == 'no_comparable'
      ? 'Instrumentos no comparables; revisar configuración.'
      : 'Pendiente: se necesitan ambas entregas y todas las notas.';
}
