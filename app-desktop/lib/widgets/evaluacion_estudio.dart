import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers.dart';

/// Instrumento sin IA: el código se escribe aquí y se entrega al docente.
class EvaluacionEstudio extends StatefulWidget {
  const EvaluacionEstudio({super.key});
  @override
  State<EvaluacionEstudio> createState() => _EvaluacionEstudioState();
}

class _EvaluacionEstudioState extends State<EvaluacionEstudio> {
  Map<String, dynamic>? _estado, _entrega;
  final _codigo = <String, TextEditingController>{};
  final _texto = <String, TextEditingController>{};
  String? _error;
  bool _ocupado = false, _cambio = false;
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    _cargar();
    _autosave = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_cambio && !_ocupado && _entrega?['estado'] == 'borrador') _guardar();
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final c in [..._codigo.values, ..._texto.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _adoptar(Map<String, dynamic>? entrega) {
    _entrega = entrega;
    if (entrega == null) return;
    final respuestas = entrega['respuestas'] as Map? ?? {};
    for (final p in entrega['preguntas'] as List) {
      final id = p['id'] as String;
      final r = respuestas[id] as Map? ?? {};
      _codigo.putIfAbsent(
        id,
        () => TextEditingController(text: r['codigo']?.toString() ?? ''),
      );
      _texto.putIfAbsent(
        id,
        () => TextEditingController(text: r['explicacion']?.toString() ?? ''),
      );
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final estado = await context.read<AuthProvider>().api.estudioActual();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _adoptar((estado['entrega'] as Map?)?.cast<String, dynamic>());
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _iniciar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final e = await context.read<AuthProvider>().api.iniciarEvaluacion();
      if (mounted) setState(() => _adoptar(e));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _guardar({bool finalizar = false}) async {
    if (_ocupado || _entrega == null) return;
    if (finalizar) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Entregar evaluación'),
          content: const Text(
            'Se enviarán también las respuestas incompletas o vacías. No tienes que acertar ni escribir una respuesta larga. Después de entregar no podrás cambiarla. ¿Confirmas el envío?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir trabajando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entregar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted || _ocupado) return;
    }
    final respuestas = <String, dynamic>{
      for (final id in _codigo.keys)
        id: {
          'codigo': _codigo[id]!.text,
          'explicacion': _texto[id]!.text,
          'sin_responder':
              _codigo[id]!.text.trim().isEmpty &&
              _texto[id]!.text.trim().isEmpty,
        },
    };
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final e = await context.read<AuthProvider>().api.guardarEvaluacion(
        _entrega!['id'] as String,
        respuestas,
        _entrega!['revision'] as int,
        finalizar: finalizar,
      );
      if (!mounted) return;
      setState(() {
        _entrega = e;
        _cambio = false;
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              'No se confirmó el guardado. Conserva esta pantalla y reintenta: $e',
        );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fase =
        _estado?['fase'] ?? context.watch<SettingsProvider>().faseEstudio;
    final cerrado = _estado?['abierto'] != true;
    final enviado = _entrega?['estado'] == 'enviado';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          fase == 'pre'
              ? 'Pretest · Explicador de código'
              : 'Postest · Editor de código',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Evaluación individual para ambos grupos. Escribe tu código y explica con tus palabras. No se utiliza IA, pistas, soluciones ni ejecución de código. Una respuesta corta puede ser correcta; si no sabes, puedes dejarla sin responder.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (_ocupado) const LinearProgressIndicator(),
        if (_entrega == null) ...[
          const SizedBox(height: 20),
          Text(
            _estado?['abierto'] == true
                ? 'El docente ha abierto la evaluación.'
                : 'Evaluación cerrada. Espera la indicación del docente y pulsa Actualizar.',
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _ocupado ? null : _cargar,
                child: const Text('Actualizar'),
              ),
              FilledButton(
                onPressed: _ocupado || _estado?['abierto'] != true
                    ? null
                    : _iniciar,
                child: const Text('Iniciar evaluación'),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _ocupado ? null : _cargar,
            child: const Text('Actualizar estado'),
          ),
          Text('Inicio: ${_entrega!['iniciada_en']} · ${_entrega!['version']}'),
          if (enviado)
            Text(
              'Entrega recibida por el servidor: ${_entrega!['enviada_en']}. Pendiente de revisión docente.',
            ),
          for (final p in _entrega!['preguntas'] as List)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Módulo ${p['modulo']} · ${p['competencia']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(p['consigna'] as String),
                    const SizedBox(height: 12),
                    TextField(
                      key: ValueKey('evaluacion-codigo-${p['id']}'),
                      controller: _codigo[p['id']],
                      readOnly: enviado || cerrado || _ocupado,
                      minLines: 4,
                      maxLines: 14,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontFamily: 'monospace'),
                      onChanged: (_) => setState(() => _cambio = true),
                      decoration: const InputDecoration(
                        labelText: 'Tu código Python',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: ValueKey('evaluacion-texto-${p['id']}'),
                      controller: _texto[p['id']],
                      readOnly: enviado || cerrado || _ocupado,
                      minLines: 2,
                      maxLines: 8,
                      onChanged: (_) => setState(() => _cambio = true),
                      decoration: const InputDecoration(
                        labelText: 'Tu explicación / respuesta',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!enviado) ...[
            Text(
              _cambio
                  ? 'Hay cambios pendientes de guardar.'
                  : 'Borrador guardado en el servidor.',
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _ocupado || cerrado ? null : () => _guardar(),
                  child: const Text('Guardar borrador'),
                ),
                FilledButton(
                  onPressed: _ocupado || cerrado
                      ? null
                      : () => _guardar(finalizar: true),
                  child: const Text('Entregar evaluación'),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
