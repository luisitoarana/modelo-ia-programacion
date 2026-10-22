import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers.dart';
import '../../services/dialogos_nativos.dart';
import 'admin_exports.dart';
import '../estudio_docente.dart';

/// Bandeja docente: los textos se revisan por su contenido, nunca por longitud.
class AdministracionSection extends StatefulWidget {
  const AdministracionSection({super.key});

  @override
  State<AdministracionSection> createState() => _AdministracionSectionState();
}

class _AdministracionSectionState extends State<AdministracionSection> {
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _intentos = [];
  bool _cargando = true;
  String? _error;
  String _estudianteId = '';
  String _fase = '';
  bool _exportando = false;
  bool _hayMasIntentos = false;
  bool _cargandoMas = false;
  int _offsetSiguiente = 0;

  Future<void> _cargarMas() async {
    if (_cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      final pagina = await context.read<AuthProvider>().api.intentosDocente(
        offset: _offsetSiguiente,
      );
      if (!mounted) return;
      setState(() {
        final existentes = _intentos.map((i) => i['id']).toSet();
        _intentos.addAll(pagina.where((i) => !existentes.contains(i['id'])));
        _offsetSiguiente += pagina.length;
        _hayMasIntentos = pagina.length == 1000;
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = 'No se pudo cargar más evidencia: $e');
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  List<Map<String, dynamic>> get _intentosFiltrados => _intentos
      .where(
        (i) =>
            (_estudianteId.isEmpty ||
                i['usuario_id'].toString() == _estudianteId) &&
            (_fase.isEmpty || i['fase'] == _fase),
      )
      .toList();

  Future<void> _exportar(String formato) async {
    final intentos = _intentosFiltrados;
    if (_exportando || intentos.isEmpty) return;
    setState(() => _exportando = true);
    try {
      final carpeta = await DialogosNativos.seleccionarCarpeta(
        titulo: 'Elegir carpeta para exportar respuestas',
      );
      if (carpeta == null) return;
      final nombre =
          'intentos_docentes_${DateTime.now().microsecondsSinceEpoch}.$formato';
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre');
      await archivo.writeAsString(
        formato == 'csv'
            ? exportarIntentosCsv(intentos)
            : exportarIntentosJson(intentos),
        flush: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${intentos.length} respuestas exportadas: ${archivo.path}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final datos = await Future.wait<dynamic>([
        api.resumenAdmin(),
        api.usuariosAdmin(),
        api.intentosDocente(),
      ]);
      if (!mounted) return;
      setState(() {
        _resumen = datos[0] as Map<String, dynamic>;
        _usuarios = (datos[1] as List).cast<Map<String, dynamic>>();
        _intentos = (datos[2] as List).cast<Map<String, dynamic>>();
        _offsetSiguiente = _intentos.length;
        _hayMasIntentos = _intentos.length == 1000;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _cargando = false;
        });
      }
    }
  }

  Future<void> _asignar(Map<String, dynamic> usuario) async {
    String condicion = usuario['condicion']?.toString() ?? 'con_acompanamiento';
    String fase = usuario['fase']?.toString() ?? 'intervencion';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: Text('Asignar estudio a ${usuario['nombre']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: condicion,
                decoration: const InputDecoration(labelText: 'Condición'),
                items: const [
                  DropdownMenuItem(
                    value: 'con_acompanamiento',
                    child: Text('Con andamiaje'),
                  ),
                  DropdownMenuItem(
                    value: 'sin_acompanamiento',
                    child: Text('Generación directa'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) actualizar(() => condicion = v);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: fase,
                decoration: const InputDecoration(labelText: 'Fase'),
                items: const [
                  DropdownMenuItem(
                    value: 'pre',
                    child: Text('Pre-test: sin ayuda'),
                  ),
                  DropdownMenuItem(
                    value: 'intervencion',
                    child: Text('Intervención'),
                  ),
                  DropdownMenuItem(
                    value: 'post',
                    child: Text('Post-test: sin ayuda'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) actualizar(() => fase = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogo, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogo, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      await context.read<AuthProvider>().api.asignarEstudio(
        usuario['id'].toString(),
        condicion,
        fase,
      );
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo asignar: $e');
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> usuario) async {
    try {
      await context.read<AuthProvider>().api.cambiarEstadoEstudiante(
        usuario['id'].toString(),
        usuario['activo'] != true,
      );
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cambiar la cuenta: $e');
    }
  }

  Future<void> _cambiarClave() async {
    var actual = '';
    var nueva = '';
    var confirmacion = '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Cambiar mi contraseña'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                ),
                onChanged: (v) => actual = v,
              ),
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña (mínimo 10 caracteres)',
                ),
                onChanged: (v) => nueva = v,
              ),
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                ),
                onChanged: (v) => confirmacion = v,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    if (nueva.length < 10 || nueva != confirmacion) {
      setState(
        () => _error =
            'La nueva contraseña debe tener al menos 10 caracteres y coincidir con la confirmación.',
      );
      return;
    }
    try {
      await context.read<AuthProvider>().api.cambiarClave(actual, nueva);
      if (mounted) {
        setState(() => _error = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo cambiar la contraseña: $e');
      }
    }
  }

  Future<void> _revisar(Map<String, dynamic> intento) async {
    final anterior = intento['revision_docente'] as Map?;
    int comprension = (anterior?['comprension'] as int?) ?? 0;
    int codigo = (anterior?['codigo'] as int?) ?? 0;
    int casos = (anterior?['casos_limite'] as int?) ?? 0;
    final observaciones = TextEditingController(
      text: anterior?['observaciones']?.toString() ?? '',
    );
    final rutaDialogo = DialogRoute<bool>(
      context: context,
      builder: (dialogo) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Revisión docente (0–10)'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evalúa la idea expresada y el código, no la cantidad de palabras.',
                  ),
                  ExpansionTile(
                    title: const Text(
                      'Ver pregunta y respuesta del estudiante',
                    ),
                    children: [
                      SelectableText(
                        '${preguntaDelIntento(intento)}\n\n'
                        'Respuesta inicial:\n${intento['prediccion']}\n\n'
                        'Explicación propia:\n${intento['explicacion_propia']}\n\n'
                        'Código inicial:\n${intento['codigo_inicial']}\n\n'
                        'Código final:\n${intento['codigo_final']}',
                      ),
                    ],
                  ),
                  _puntaje(
                    'Comprensión conceptual (0–4)',
                    comprension,
                    4,
                    (v) => actualizar(() => comprension = v),
                  ),
                  _puntaje(
                    'Código y lógica (0–4)',
                    codigo,
                    4,
                    (v) => actualizar(() => codigo = v),
                  ),
                  _puntaje(
                    'Casos límite (0–2)',
                    casos,
                    2,
                    (v) => actualizar(() => casos = v),
                  ),
                  Text('Total: ${comprension + codigo + casos}/10'),
                  TextField(
                    controller: observaciones,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones para el estudiante',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogo, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogo, true),
              child: const Text('Guardar revisión'),
            ),
          ],
        ),
      ),
    );
    final confirmar = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(rutaDialogo);
    await rutaDialogo.completed;
    final texto = observaciones.text;
    observaciones.dispose();
    if (confirmar != true || !mounted) return;
    try {
      await context.read<AuthProvider>().api.revisarIntento(
        intento['id'].toString(),
        comprension: comprension,
        codigo: codigo,
        casosLimite: casos,
        observaciones: texto,
      );
      await _cargar();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar la revisión: $e');
      }
    }
  }

  Widget _puntaje(
    String titulo,
    int valor,
    int maximo,
    ValueChanged<int> alCambiar,
  ) {
    return Row(
      children: [
        Expanded(child: Text(titulo)),
        DropdownButton<int>(
          value: valor,
          items: [
            for (var i = 0; i <= maximo; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) {
            if (v != null) alCambiar(v);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    final intentos = _intentosFiltrados;
    final participantes = <String, String>{
      for (final u in _usuarios.where((u) => u['rol'] == 'estudiante'))
        u['id'].toString(): '${u['nombre']} · ${u['email']}',
      for (final i in _intentos)
        i['usuario_id'].toString():
            '${i['usuario_nombre']} · ${i['usuario_email']}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => abrirEstudioDocente(context),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Pretest, postest y vista previa docente'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Administración y revisión docente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              onPressed: _cambiarClave,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Cambiar mi contraseña'),
            ),
            IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        Text(
          'Base de datos: ${(_resumen?['base_datos'] as Map?)?['motor'] ?? '—'} · '
          '${(_resumen?['base_datos'] as Map?)?['host'] ?? '—'}',
        ),
        Text(
          'Usuarios: ${_resumen?['usuarios'] ?? 0} · Intentos: ${_intentos.length}',
        ),
        const SizedBox(height: 20),
        Text(
          'Estudiantes y condiciones',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final usuario in _usuarios.where((u) => u['rol'] == 'estudiante'))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${usuario['nombre']} · ${usuario['email']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Nivel: ${usuario['nivel_academico'] ?? 'no indicado'} · '
                    'Condición: ${usuario['condicion'] ?? 'sin asignar'} · '
                    'Fase: ${usuario['fase'] ?? 'práctica'}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _asignar(usuario),
                        child: const Text('Asignar condición/fase'),
                      ),
                      TextButton(
                        onPressed: () => _cambiarEstado(usuario),
                        child: Text(
                          usuario['activo'] == true
                              ? 'Desactivar cuenta'
                              : 'Activar cuenta',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Intentos para revisar',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Una respuesta breve y una extensa pueden recibir la misma nota si demuestran la misma comprensión.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: constraints.maxWidth.clamp(0, 360),
                child: DropdownButtonFormField<String>(
                  initialValue: _estudianteId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por estudiante',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos los participantes'),
                    ),
                    for (final p in participantes.entries)
                      DropdownMenuItem(
                        value: p.key,
                        child: Text(p.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _estudianteId = v ?? ''),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth.clamp(0, 240),
                child: DropdownButtonFormField<String>(
                  initialValue: _fase,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por fase',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Todas las fases')),
                    DropdownMenuItem(
                      value: 'practica',
                      child: Text('Práctica libre'),
                    ),
                    DropdownMenuItem(value: 'pre', child: Text('Pre-test')),
                    DropdownMenuItem(
                      value: 'intervencion',
                      child: Text('Intervención'),
                    ),
                    DropdownMenuItem(value: 'post', child: Text('Post-test')),
                  ],
                  onChanged: (v) => setState(() => _fase = v ?? ''),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${intentos.length} intentos del filtro · ${_intentos.length} cargados',
            ),
            OutlinedButton.icon(
              onPressed: _exportando || intentos.isEmpty
                  ? null
                  : () => _exportar('csv'),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Exportar CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _exportando || intentos.isEmpty
                  ? null
                  : () => _exportar('json'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Exportar JSON'),
            ),
          ],
        ),
        const Text(
          'La exportación incluye los intentos cargados del filtro, las respuestas, el código y la revisión docente.',
        ),
        if (_hayMasIntentos)
          TextButton(
            onPressed: _cargandoMas ? null : _cargarMas,
            child: Text(
              _cargandoMas ? 'Cargando...' : 'Cargar más intentos anteriores',
            ),
          ),
        if (intentos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No hay respuestas guardadas para este filtro.'),
          ),
        for (final intento in intentos)
          Card(
            child: ExpansionTile(
              title: Text(
                '${intento['usuario_nombre']} · ${intento['leccion_id'] ?? 'Práctica libre'}',
              ),
              subtitle: Text(
                '${intento['fase']} · ${intento['revision_docente'] == null ? 'Pendiente' : 'Revisado: ${(intento['revision_docente'] as Map)['puntaje']}/10'}',
              ),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    'Estudiante: ${intento['usuario_nombre']} · ${intento['usuario_email']}\n'
                    'Fecha: ${intento['fecha_creacion']} · Pistas: ${intento['pistas_usadas']}\n\n'
                    'Pregunta:\n${preguntaDelIntento(intento)}\n'
                    '${origenPregunta(intento) == 'catalogo_actual_no_registrada' ? '(Registro anterior: enunciado tomado del catálogo actual; no se guardó la pregunta original.)\n' : ''}\n'
                    'Código inicial:\n${intento['codigo_inicial']}\n\n'
                    'Respuesta inicial:\n${intento['prediccion']}\n\n'
                    'Explicación propia:\n${intento['explicacion_propia']}\n\n'
                    'Código final:\n${intento['codigo_final']}',
                  ),
                ),
                if (intento['revision_docente'] is Map)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      'Observaciones del docente:\n${(intento['revision_docente'] as Map)['observaciones'] ?? ''}',
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => _revisar(intento),
                    child: const Text('Revisar con rúbrica'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
