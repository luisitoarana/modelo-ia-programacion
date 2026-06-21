import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../providers.dart';
import '../theme.dart';
import 'syntax_highlighter.dart';
import 'terminal_view.dart';

/// Vista "Code" v2 — Editor estilo VS Code / Cursor con:
///
///   ┌────────┬───────────────────────────────────────────┬──────────┐
///   │ Files  │ tabs.py•  utils.js   ✕  [+] [📂]          │ 💬 IA    │
///   │ pane   ├───────────────────────────────────────────┤  pane    │
///   │        │ 1 ┃ def foo():                            │ (opc)    │
///   │ • main │ 2 ┃     pass    (highlight INLINE)        │          │
///   │ • lib  │ 3 ┃                                        │          │
///   │        ├───────────────────────────────────────────┤          │
///   │        │ [▶ EJECUTAR · PYTHON]  ✨ Mejorar  💾    │          │
///   │        ├───────────────────────────────────────────┤          │
///   │        │ Output | Terminal | Problemas             │          │
///   │        │ (panel inferior con tabs)                 │          │
///   └────────┴───────────────────────────────────────────┴──────────┘
///
/// Mejoras vs v1:
///   - **CodeController**: el syntax highlight se aplica INLINE en el
///     TextField (vía buildTextSpan), sin capas duplicadas que causen
///     texto rayado.
///   - **Sidebar de archivos** colapsable.
///   - **Multi-lenguaje** para ejecutar (Python / JavaScript / Bash).
///   - **Panel IA lateral** (opcional, colapsable).
///   - **Tabs en output**: Output / Terminal / Problemas.
///   - **Botón Ejecutar grande** y siempre visible.
///   - **Detección automática de lenguaje** por extensión.

class CodeView extends StatefulWidget {
  const CodeView({super.key});

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final List<_TabArchivo> _tabs = [];
  int _activa = -1;

  // Panel inferior (Output / Terminal / Problemas)
  _PanelInferior _panelActivo = _PanelInferior.output;
  _ResultadoEjecucion? _output;
  bool _ejecutando = false;
  final List<String> _terminalLog = [];   // historial libre
  final List<String> _problemas = [];      // futuro: linting

  // Sidebar de archivos (colapsable) — ahora a la DERECHA.
  bool _sidebarArchivos = true;

  // Carpeta abierta como "proyecto" (tipo Open Folder de VS Code).
  String? _carpetaRaiz;
  _NodoCarpeta? _arbol;
  bool _cargandoArbol = false;

  // GlobalKey para acceder al State de la TerminalView embebida (para
  // sincronizar su CWD con el archivo activo).
  final GlobalKey<State<TerminalView>> _terminalKey = GlobalKey();

  // Panel IA ahora vive como tab del panel inferior (junto a
  // Output/Terminal/Problemas) — más cerca del editor.
  final TextEditingController _iaCtrl = TextEditingController();
  bool _iaCargando = false;
  String? _iaUltimaRespuesta;

  // ── Tamaños dinámicos de los paneles (redimensionables) ─────────────
  /// Ancho del panel EXPLORADOR (sidebar derecho).
  double _anchoExplorador = 260;
  /// Alto del panel inferior (output/terminal/problemas/IA).
  double _altoPanelInferior = 240;
  static const double _minAnchoExplorador = 180;
  static const double _maxAnchoExplorador = 500;
  static const double _minAltoPanelInferior = 80;
  static const double _maxAltoPanelInferior = 600;

  @override
  void initState() {
    super.initState();
    // Sin tabs por defecto — el usuario decide qué archivo abrir.
    // Mostramos un empty state profesional cuando no hay nada abierto.
    _activa = -1;
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    _iaCtrl.dispose();
    super.dispose();
  }

  _TabArchivo? get _tabActiva =>
      (_activa >= 0 && _activa < _tabs.length) ? _tabs[_activa] : null;

  /// CWD que la terminal embebida debe usar: el directorio del archivo
  /// activo (si tiene ruta) o la carpeta raíz abierta. Permite que al
  /// escribir `python archivo.py` el archivo esté en la PWD.
  String? get _cwdParaTerminal {
    final t = _tabActiva;
    if (t != null && t.ruta != null) {
      final sep = Platform.pathSeparator;
      final idx = t.ruta!.lastIndexOf(sep);
      if (idx > 0) return t.ruta!.substring(0, idx);
    }
    return _carpetaRaiz;
  }

  // ────────────────────── Acciones ──────────────────────

  Future<void> _abrirArchivos() async {
    final p = AppPalette.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'py', 'dart', 'js', 'ts', 'tsx', 'jsx', 'json', 'md', 'txt',
        'java', 'kt', 'rs', 'go', 'c', 'cpp', 'h', 'hpp', 'cs',
        'rb', 'php', 'sh', 'yaml', 'yml', 'toml', 'html', 'css',
      ],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      final i = _tabs.indexWhere((t) => t.ruta == f.path);
      if (i >= 0) {
        setState(() => _activa = i);
        continue;
      }
      String contenido = '';
      try {
        contenido = await File(f.path!).readAsString();
      } catch (_) {
        continue;
      }
      final lenguaje = _lenguajeDeExtension(f.extension ?? '');
      setState(() {
        _tabs.add(_TabArchivo(
          nombre: f.name,
          ruta: f.path,
          contenido: contenido,
          original: contenido,
          lenguaje: lenguaje,
          palette: p,
        ));
        _activa = _tabs.length - 1;
      });
    }
  }

  /// Pide nombre con extensión y crea archivo en memoria (o en la carpeta
  /// raíz si hay una abierta). El usuario tiene control total del nombre.
  Future<void> _nuevoArchivo({String? carpetaDestino}) async {
    final nombre = await _dialogoTexto(
      titulo: 'Nuevo archivo',
      etiqueta: 'Nombre del archivo',
      hint: 'ej: utils.py · main.js · script.sh',
      valorInicial: 'sin_titulo.py',
      botonOk: 'Crear',
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    final nombreLimpio = nombre.trim();
    final ext = nombreLimpio.contains('.') ? nombreLimpio.split('.').last : '';
    final lenguaje = _lenguajeDeExtension(ext);
    final p = AppPalette.of(context);

    // Si hay carpeta destino → crear archivo físico en disco.
    String? rutaFinal;
    if (carpetaDestino != null) {
      rutaFinal = '$carpetaDestino${Platform.pathSeparator}$nombreLimpio';
      try {
        final f = File(rutaFinal);
        if (await f.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ya existe: $rutaFinal')),
            );
          }
          return;
        }
        await f.create(recursive: true);
        await f.writeAsString('');
        await _refrescarArbol();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo crear: $e')),
          );
        }
        return;
      }
    }

    setState(() {
      _tabs.add(_TabArchivo(
        nombre: nombreLimpio,
        ruta: rutaFinal,
        contenido: '',
        original: '',
        lenguaje: lenguaje,
        palette: p,
      ));
      _activa = _tabs.length - 1;
    });
  }

  /// Abre una carpeta como "proyecto" — el sidebar muestra su árbol.
  Future<void> _abrirCarpeta() async {
    final ruta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Abrir carpeta como proyecto',
    );
    if (ruta == null) return;
    setState(() {
      _carpetaRaiz = ruta;
      _cargandoArbol = true;
    });
    await _refrescarArbol();
  }

  Future<void> _refrescarArbol() async {
    if (_carpetaRaiz == null) return;
    setState(() => _cargandoArbol = true);
    try {
      final raiz = await _construirArbol(_carpetaRaiz!, profundidad: 1);
      setState(() {
        _arbol = raiz;
        _cargandoArbol = false;
      });
    } catch (e) {
      setState(() => _cargandoArbol = false);
    }
  }

  /// Construye el árbol recursivo (lazy: primer nivel + sub al expandir).
  Future<_NodoCarpeta> _construirArbol(String ruta, {int profundidad = 1}) async {
    final dir = Directory(ruta);
    final hijos = <_NodoArchivo>[];
    try {
      await for (final entidad in dir.list(followLinks: false)) {
        final nombre = entidad.path.split(Platform.pathSeparator).last;
        // Skip carpetas ocultas / node_modules / __pycache__ etc.
        if (_ignorar(nombre)) continue;
        if (entidad is Directory) {
          hijos.add(_NodoArchivo.carpeta(
            nombre: nombre,
            ruta: entidad.path,
          ));
        } else if (entidad is File) {
          hijos.add(_NodoArchivo.archivo(
            nombre: nombre,
            ruta: entidad.path,
            lenguaje: _lenguajeDeExtension(
              nombre.contains('.') ? nombre.split('.').last : '',
            ),
          ));
        }
      }
    } catch (_) {/* dir no accesible */}
    // Ordenar: carpetas primero, después archivos, ambos alfabéticos.
    hijos.sort((a, b) {
      if (a.esCarpeta != b.esCarpeta) return a.esCarpeta ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return _NodoCarpeta(
      nombre: ruta.split(Platform.pathSeparator).last,
      ruta: ruta,
      hijos: hijos,
    );
  }

  bool _ignorar(String nombre) {
    if (nombre.startsWith('.')) return true;
    return const {
      'node_modules', '__pycache__', 'venv', '.venv', 'env',
      'build', 'dist', '.dart_tool', '.idea', '.vscode',
      'target', 'bin', 'obj', '.next',
    }.contains(nombre);
  }

  /// Abre un archivo del árbol como tab.
  Future<void> _abrirDesdeArbol(_NodoArchivo nodo) async {
    if (nodo.esCarpeta) return;
    // Si ya está abierto, solo activar.
    final i = _tabs.indexWhere((t) => t.ruta == nodo.ruta);
    if (i >= 0) {
      setState(() => _activa = i);
      return;
    }
    String contenido = '';
    try {
      contenido = await File(nodo.ruta).readAsString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer: $e')),
        );
      }
      return;
    }
    final p = AppPalette.of(context);
    setState(() {
      _tabs.add(_TabArchivo(
        nombre: nodo.nombre,
        ruta: nodo.ruta,
        contenido: contenido,
        original: contenido,
        lenguaje: nodo.lenguaje ?? 'texto',
        palette: p,
      ));
      _activa = _tabs.length - 1;
    });
  }

  /// Renombra un archivo o carpeta en disco.
  Future<void> _renombrar(_NodoArchivo nodo) async {
    final nuevoNombre = await _dialogoTexto(
      titulo: 'Renombrar',
      etiqueta: 'Nuevo nombre',
      valorInicial: nodo.nombre,
      botonOk: 'Renombrar',
    );
    if (nuevoNombre == null || nuevoNombre.trim().isEmpty) return;
    if (nuevoNombre.trim() == nodo.nombre) return;
    final padre = nodo.ruta.substring(
      0, nodo.ruta.length - nodo.nombre.length,
    );
    final nuevaRuta = '$padre${nuevoNombre.trim()}';
    try {
      if (nodo.esCarpeta) {
        await Directory(nodo.ruta).rename(nuevaRuta);
      } else {
        await File(nodo.ruta).rename(nuevaRuta);
      }
      // Actualizar tabs abiertas que apunten al archivo.
      for (final t in _tabs) {
        if (t.ruta == nodo.ruta) {
          t.ruta = nuevaRuta;
          t.nombre = nuevoNombre.trim();
        }
      }
      await _refrescarArbol();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo renombrar: $e')),
        );
      }
    }
  }

  /// Elimina (mueve a papelera) un archivo o carpeta.
  Future<void> _eliminarNodo(_NodoArchivo nodo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar "${nodo.nombre}"?\n\n'
            'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      if (nodo.esCarpeta) {
        await Directory(nodo.ruta).delete(recursive: true);
      } else {
        await File(nodo.ruta).delete();
      }
      // Cerrar tabs abiertas del archivo eliminado.
      _tabs.removeWhere((t) => t.ruta == nodo.ruta);
      if (_activa >= _tabs.length) _activa = _tabs.length - 1;
      await _refrescarArbol();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  /// Diálogo simple con un TextField. Devuelve el texto introducido o null.
  Future<String?> _dialogoTexto({
    required String titulo,
    required String etiqueta,
    String? hint,
    String valorInicial = '',
    String botonOk = 'Aceptar',
  }) async {
    final ctrl = TextEditingController(text: valorInicial);
    // Seleccionar nombre (sin extensión) para edición rápida.
    final puntoIdx = valorInicial.lastIndexOf('.');
    if (puntoIdx > 0) {
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: puntoIdx);
    } else {
      ctrl.selection = TextSelection(
          baseOffset: 0, extentOffset: valorInicial.length);
    }
    final p = AppPalette.of(context);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo,
            style: TextStyle(fontSize: 16, color: p.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: etiqueta,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(botonOk),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  void _cerrarTab(int i) {
    setState(() {
      final t = _tabs.removeAt(i);
      t.dispose();
      if (_tabs.isEmpty) {
        _activa = -1;
      } else {
        _activa = _activa.clamp(0, _tabs.length - 1);
      }
    });
  }

  Future<void> _guardar() async {
    final t = _tabActiva;
    if (t == null) return;
    if (t.ruta == null) {
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar archivo',
        fileName: t.nombre,
      );
      if (ruta == null) return;
      t.ruta = ruta;
      t.nombre = ruta.split(Platform.pathSeparator).last;
      // Re-detectar lenguaje según la nueva extensión.
      final ext = t.nombre.contains('.') ? t.nombre.split('.').last : '';
      final nuevoLenguaje = _lenguajeDeExtension(ext);
      if (nuevoLenguaje != t.lenguaje) {
        t.lenguaje = nuevoLenguaje;
        t.controller().lenguaje = nuevoLenguaje;
      }
    }
    try {
      await File(t.ruta!).writeAsString(t.contenido, flush: true);
      setState(() => t.original = t.contenido);
      _terminalLog.add('💾 Guardado: ${t.ruta}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardado en ${t.ruta}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Future<void> _ejecutar() async {
    final t = _tabActiva;
    if (t == null || _ejecutando) return;
    final ejecutable = _lenguajeEjecutable(t.lenguaje);
    if (ejecutable == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No puedo ejecutar "${t.lenguaje}". Soportados: python, javascript, bash.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    setState(() {
      _ejecutando = true;
      _output = null;
      _panelActivo = _PanelInferior.output;
    });
    final inicio = DateTime.now();
    try {
      final ApiClient api = context.read<AuthProvider>().api;
      final r = await api.ejecutarPython(
        t.contenido,
        timeout: 10,
        lenguaje: ejecutable,
      );
      setState(() {
        _output = _ResultadoEjecucion(
          stdout: (r['stdout'] ?? '').toString(),
          stderr: (r['stderr'] ?? '').toString(),
          exitCode: (r['exit_code'] as num?)?.toInt() ?? -1,
          duracion: (r['duracion_segundos'] as num?)?.toDouble() ?? 0.0,
          timeout: r['timeout'] == true,
          lenguaje: ejecutable,
        );
      });
      _terminalLog.add(
        '${inicio.toString().substring(11, 19)} · ${ejecutable.toUpperCase()} '
        '· exit ${_output!.exitCode} · ${_output!.duracion.toStringAsFixed(2)}s',
      );
    } catch (e) {
      setState(() {
        _output = _ResultadoEjecucion(
          stdout: '',
          stderr: 'Error invocando al backend: $e',
          exitCode: -1,
          duracion: 0,
          timeout: false,
          lenguaje: ejecutable,
        );
      });
    } finally {
      if (mounted) setState(() => _ejecutando = false);
    }
  }

  Future<void> _consultarIa(String pregunta) async {
    final t = _tabActiva;
    if (t == null || pregunta.trim().isEmpty || _iaCargando) return;
    final settings = context.read<SettingsProvider>();
    final api = context.read<AuthProvider>().api;
    setState(() {
      _iaCargando = true;
      _iaUltimaRespuesta = null;
    });
    final prompt =
        '${pregunta.trim()}\n\nContexto: este es el archivo "${t.nombre}" '
        '(lenguaje: ${t.lenguaje}):\n\n```${t.lenguaje}\n${t.contenido}\n```';

    try {
      // Necesitamos una conversación. Si no hay una activa, creamos una rápida.
      final chat = context.read<ChatProvider>();
      if (chat.activaId == null) {
        chat.nueva();
        // Pequeño wait para que el state se propague antes de leerlo.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // Si seguimos sin id (provider crea conv solo al enviar primer
      // mensaje), enviamos vía el provider que lo gestiona internamente.
      if (chat.activaId == null) {
        await chat.enviar(prompt, idioma: settings.idioma);
        final msgs = chat.mensajes;
        final ultima = msgs.isNotEmpty ? msgs.last : null;
        setState(() {
          _iaUltimaRespuesta = (ultima != null && !ultima.esUsuario)
              ? ultima.contenido
              : '(sin respuesta del asistente)';
        });
      } else {
        final resp = await api.enviarMensaje(
          chat.activaId!,
          prompt,
          idioma: settings.idioma,
          buscarWeb: false,
        );
        setState(() {
          _iaUltimaRespuesta = resp.mensajeAsistente.contenido;
        });
      }
    } catch (e) {
      setState(() {
        _iaUltimaRespuesta = 'Error al consultar IA: $e';
      });
    } finally {
      if (mounted) setState(() => _iaCargando = false);
    }
  }

  // ────────────────────── Build ──────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true): const _GuardarIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): const _GuardarIntent(),
        SingleActivator(LogicalKeyboardKey.f5): const _EjecutarIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, control: true): const _EjecutarIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true): const _EjecutarIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GuardarIntent: CallbackAction<_GuardarIntent>(
              onInvoke: (_) { _guardar(); return null; }),
          _EjecutarIntent: CallbackAction<_EjecutarIntent>(
              onInvoke: (_) { _ejecutar(); return null; }),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: p.bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Lado IZQUIERDO: editor + panel inferior ───────────
                Expanded(
                  child: Column(
                    children: [
                      _tabBar(p),
                      Container(height: 1, color: p.borderSoft),
                      Expanded(child: _editor(p)),
                      _toolbar(p),
                      // Divisor horizontal arrastrable: cambia el alto
                      // del panel inferior (output / terminal / problemas / IA).
                      _DivisorHorizontal(
                        onDrag: (delta) {
                          setState(() {
                            _altoPanelInferior = (_altoPanelInferior - delta)
                                .clamp(_minAltoPanelInferior,
                                    _maxAltoPanelInferior);
                          });
                        },
                      ),
                      SizedBox(
                        height: _altoPanelInferior,
                        child: _panelInferior(p),
                      ),
                    ],
                  ),
                ),
                // ── Divisor vertical arrastrable (editor ↔ explorador) ─
                if (_sidebarArchivos)
                  _DivisorVertical(
                    onDrag: (delta) {
                      setState(() {
                        _anchoExplorador = (_anchoExplorador - delta)
                            .clamp(_minAnchoExplorador, _maxAnchoExplorador);
                      });
                    },
                  ),
                // ── Lado DERECHO: EXPLORADOR ──────────────────────────
                if (_sidebarArchivos)
                  SizedBox(
                    width: _anchoExplorador,
                    child: _sidebar(p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────── Sidebar de archivos ────────────

  Widget _sidebar(AppPalette p) {
    return Container(
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Solo EXPLORADOR — la lista de archivos abiertos se ve
          // arriba como tabs, no se duplica aquí.
          Expanded(child: _seccionExplorador(p)),
        ],
      ),
    );
  }

  Widget _seccionExplorador(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EXPLORADOR',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                        color: p.subtle),
                  ),
                ),
                _miniIcon(p, Icons.create_new_folder_outlined,
                    'Abrir carpeta', _abrirCarpeta),
                if (_carpetaRaiz != null) ...[
                  const SizedBox(width: 2),
                  _miniIcon(p, Icons.note_add_outlined,
                      'Nuevo archivo en la carpeta raíz',
                      () => _nuevoArchivo(carpetaDestino: _carpetaRaiz)),
                  const SizedBox(width: 2),
                  _miniIcon(p, Icons.refresh, 'Refrescar', _refrescarArbol),
                ],
                const SizedBox(width: 2),
                _miniIcon(p, Icons.menu_open, 'Ocultar sidebar',
                    () => setState(() => _sidebarArchivos = false)),
                const SizedBox(width: 4),
              ],
            ),
          ),
          if (_carpetaRaiz != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
              child: Tooltip(
                message: _carpetaRaiz!,
                child: Text(
                  _carpetaRaiz!.split(Platform.pathSeparator).last,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.text),
                ),
              ),
            ),
          ],
          Expanded(child: _arbolContent(p)),
        ],
    );
  }

  Widget _arbolContent(AppPalette p) {
    if (_carpetaRaiz == null) {
      // Empty state ilustrado del explorador.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.folder_open_rounded,
                      size: 18, color: p.primary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Sin carpeta abierta',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.serifFallback.first,
                fontSize: 14, fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige una carpeta para empezar a editar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: p.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _abrirCarpeta,
              style: FilledButton.styleFrom(
                backgroundColor: p.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9,
                ),
                minimumSize: Size.zero,
                textStyle: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.create_new_folder_outlined, size: 13),
              label: const Text('Abrir carpeta'),
            ),
          ],
        ),
      );
    }
    if (_cargandoArbol) {
      return Center(
        child: SizedBox(
          height: 16, width: 16,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: p.primary),
        ),
      );
    }
    if (_arbol == null || _arbol!.hijos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('(carpeta vacía)',
            style: TextStyle(fontSize: 11.5, color: p.subtle)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in _arbol!.hijos) _nodoTile(p, h, profundidad: 0),
        ],
      ),
    );
  }

  /// Renderiza un nodo del árbol (archivo o carpeta). Recursivo.
  Widget _nodoTile(AppPalette p, _NodoArchivo n, {required int profundidad}) {
    final indent = 8.0 + profundidad * 12.0;
    if (n.esCarpeta) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filaNodo(
            p,
            indent: indent,
            icono: n.expandido ? Icons.expand_more : Icons.chevron_right,
            iconoArchivo: Icons.folder,
            nombre: n.nombre,
            esCarpeta: true,
            onTap: () async {
              if (!n.expandido && n.hijos == null) {
                // Lazy load
                final sub = await _construirArbol(n.ruta);
                n.hijos = sub.hijos;
              }
              setState(() => n.expandido = !n.expandido);
            },
            onContext: () => _menuContextual(n),
          ),
          if (n.expandido && n.hijos != null)
            for (final h in n.hijos!) _nodoTile(p, h, profundidad: profundidad + 1),
        ],
      );
    }
    return _filaNodo(
      p,
      indent: indent + 16, // alineado con texto de carpeta
      icono: null,
      iconoArchivo: _iconoLenguaje(n.lenguaje ?? 'texto'),
      nombre: n.nombre,
      esCarpeta: false,
      onTap: () => _abrirDesdeArbol(n),
      onContext: () => _menuContextual(n),
    );
  }

  Widget _filaNodo(
    AppPalette p, {
    required double indent,
    required IconData? icono,
    required IconData iconoArchivo,
    required String nombre,
    required bool esCarpeta,
    required VoidCallback onTap,
    required VoidCallback onContext,
  }) {
    return InkWell(
      onTap: onTap,
      onSecondaryTap: onContext,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 3, 8, 3),
        child: Row(
          children: [
            if (icono != null)
              Icon(icono, size: 14, color: p.muted)
            else
              const SizedBox(width: 14),
            const SizedBox(width: 2),
            Icon(iconoArchivo, size: 12,
                color: esCarpeta ? p.primary.withValues(alpha: 0.85) : p.muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(nombre,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: p.text,
                      fontWeight: esCarpeta ? FontWeight.w500 : FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menuContextual(_NodoArchivo n) async {
    final p = AppPalette.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = overlay.localToGlobal(Offset.zero);
    final accion = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx + 240, pos.dy + 100, 0, 0),
      color: p.surface,
      items: [
        if (!n.esCarpeta)
          PopupMenuItem<String>(
            value: 'abrir',
            child: Row(children: [
              Icon(Icons.open_in_new, size: 13, color: p.muted),
              const SizedBox(width: 8),
              const Text('Abrir', style: TextStyle(fontSize: 12.5)),
            ]),
          ),
        if (n.esCarpeta)
          PopupMenuItem<String>(
            value: 'nuevo_aqui',
            child: Row(children: [
              Icon(Icons.note_add_outlined, size: 13, color: p.muted),
              const SizedBox(width: 8),
              const Text('Nuevo archivo aquí',
                  style: TextStyle(fontSize: 12.5)),
            ]),
          ),
        PopupMenuItem<String>(
          value: 'renombrar',
          child: Row(children: [
            Icon(Icons.drive_file_rename_outline, size: 13, color: p.muted),
            const SizedBox(width: 8),
            const Text('Renombrar', style: TextStyle(fontSize: 12.5)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'eliminar',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 13, color: AppColors.danger),
            const SizedBox(width: 8),
            const Text('Eliminar',
                style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
          ]),
        ),
      ],
    );
    switch (accion) {
      case 'abrir':
        await _abrirDesdeArbol(n);
        break;
      case 'nuevo_aqui':
        await _nuevoArchivo(carpetaDestino: n.ruta);
        break;
      case 'renombrar':
        await _renombrar(n);
        break;
      case 'eliminar':
        await _eliminarNodo(n);
        break;
    }
  }

  // Sección "ABIERTOS" eliminada — los archivos abiertos ya se muestran
  // como tabs arriba del editor. Tener dos lugares era redundante.

  Widget _miniIcon(AppPalette p, IconData ico, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(ico, size: 13, color: p.muted),
        ),
      ),
    );
  }


  // ──────────── Tabs superiores de archivos ────────────

  Widget _tabBar(AppPalette p) {
    return Container(
      height: 36,
      color: p.surface,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (_, i) => _tabItem(p, i),
            ),
          ),
          _miniIcon(p, Icons.add, 'Nuevo', () => _nuevoArchivo()),
          _miniIcon(p, Icons.folder_open, 'Abrir', _abrirArchivos),
          const SizedBox(width: 4),
          // Toggle del sidebar EXPLORADOR (ahora a la derecha).
          _miniIcon(
            p,
            _sidebarArchivos ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            _sidebarArchivos ? 'Ocultar explorador' : 'Mostrar explorador',
            () => setState(() => _sidebarArchivos = !_sidebarArchivos),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _tabItem(AppPalette p, int i) {
    final t = _tabs[i];
    final activa = i == _activa;
    final sucio = t.contenido != t.original;
    return InkWell(
      onTap: () => setState(() => _activa = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: activa ? p.bg : Colors.transparent,
          border: activa
              ? Border(
                  top: BorderSide(color: p.primary, width: 2),
                  right: BorderSide(color: p.borderSoft),
                  left: BorderSide(color: p.borderSoft),
                )
              : Border(right: BorderSide(color: p.borderSoft)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconoLenguaje(t.lenguaje), size: 12, color: p.muted),
            const SizedBox(width: 6),
            Text(t.nombre,
                style: TextStyle(
                    fontSize: 12.5,
                    color: activa ? p.text : p.muted,
                    fontWeight: activa ? FontWeight.w500 : FontWeight.w400)),
            if (sucio)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  height: 6, width: 6,
                  decoration: BoxDecoration(color: p.muted, shape: BoxShape.circle),
                ),
              ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _cerrarTab(i),
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Icon(Icons.close, size: 13, color: p.subtle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────── Editor ────────────

  Widget _editor(AppPalette p) {
    final t = _tabActiva;
    if (t == null) return _vacio(p);
    // Asegurar controller y propagar paleta actual.
    final controller = t.controller(p);
    controller.palette = p;
    controller.lenguaje = t.lenguaje;

    final lineas = (t.contenido.isEmpty
        ? 1
        : '\n'.allMatches(t.contenido).length + 1);

    return Container(
      color: p.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gutter de números de línea
          Container(
            width: 44,
            color: p.surface,
            padding: const EdgeInsets.only(top: 10, right: 8),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 1; i <= lineas; i++)
                    Text('$i',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: p.subtle,
                          fontFamily: AppFonts.monoFallback.first,
                          fontFamilyFallback: AppFonts.monoFallback,
                        )),
                ],
              ),
            ),
          ),
          // Editor — el CodeController hace el highlight INLINE,
          // sin overlays. Esto elimina el problema de "texto rayado".
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: p.primary,
              onChanged: (v) => setState(() => t.contenido = v),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.fromLTRB(10, 10, 10, 10),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: p.text,
                fontFamily: AppFonts.monoFallback.first,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── Toolbar central ────────────

  Widget _toolbar(AppPalette p) {
    final t = _tabActiva;
    final ejecutable = t != null ? _lenguajeEjecutable(t.lenguaje) : null;
    final puedeEjecutar = ejecutable != null && !_ejecutando;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          // BOTÓN EJECUTAR — terracota con sombra tintada en primary
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: puedeEjecutar
                  ? [
                      BoxShadow(
                        color: p.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: puedeEjecutar ? p.primary : p.surface3,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: puedeEjecutar ? _ejecutar : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    children: [
                      if (_ejecutando)
                        SizedBox(
                          height: 14, width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                puedeEjecutar ? Colors.white : p.subtle),
                          ),
                        )
                      else
                        Icon(Icons.play_arrow_rounded,
                            size: 16,
                            color: puedeEjecutar ? Colors.white : p.subtle),
                      const SizedBox(width: 6),
                      Text(
                        _ejecutando ? 'Ejecutando…' : 'Ejecutar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: puedeEjecutar ? Colors.white : p.subtle,
                        ),
                      ),
                      if (ejecutable != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ejecutable.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: puedeEjecutar ? Colors.white : p.subtle,
                            fontFamily: AppFonts.monoFallback.first,
                            fontFamilyFallback: AppFonts.monoFallback,
                          ),
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mejorar con IA → abre la pestaña IA del panel inferior y
          // dispara una consulta automática.
          _btnSec(p, Icons.auto_awesome_rounded, 'Mejorar con IA',
              AppColors.accent,
              t != null && t.contenido.trim().isNotEmpty,
              'Pregunta a la IA sobre este código (panel inferior)',
              () {
                setState(() => _panelActivo = _PanelInferior.ia);
                _consultarIa('Revisa este código y sugiere mejoras concretas. '
                    'Indica qué está bien, qué se puede mejorar y por qué.');
              }),
          const Spacer(),
          // Info derecha — agrupada con un separador vertical sutil.
          if (t != null) ...[
            Text(
              '${t.contenido.split("\n").length} líneas',
              style: TextStyle(
                fontSize: 11,
                color: p.subtle,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            _badgeLenguaje(p, t.lenguaje),
            const SizedBox(width: 10),
            Container(width: 1, height: 16, color: p.borderSoft),
            const SizedBox(width: 4),
          ],
          // Guardar
          _btnSec(p, Icons.save_outlined, 'Guardar', p.text,
              t != null, 'Guardar archivo (Ctrl+S)', _guardar),
        ],
      ),
    );
  }

  Widget _btnSec(AppPalette p, IconData icono, String label, Color color,
      bool habilitado, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: habilitado ? onTap : null,
          borderRadius: BorderRadius.circular(7),
          hoverColor: p.surface2.withValues(alpha: 0.6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 14, color: habilitado ? color : p.subtle),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: habilitado ? color : p.subtle,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badgeLenguaje(AppPalette p, String lang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.borderSoft),
      ),
      child: Text(lang.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
              color: p.muted,
              fontWeight: FontWeight.w600)),
    );
  }

  // ──────────── Panel inferior con tabs ────────────

  Widget _panelInferior(AppPalette p) {
    // El alto lo gobierna el caller (SizedBox de altura `_altoPanelInferior`).
    // No usamos `maxHeight` aquí para no chocar con el sizing del padre.
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tabs
          Container(
            height: 32,
            color: p.surface,
            child: Row(
              children: [
                _tabPanel(p, _PanelInferior.output, 'Output', Icons.output),
                _tabPanel(p, _PanelInferior.terminal, 'Terminal', Icons.terminal),
                _tabPanel(p, _PanelInferior.problemas, 'Problemas',
                    Icons.warning_amber_outlined,
                    contador: _problemas.length),
                _tabPanel(p, _PanelInferior.ia, 'Asistente IA',
                    Icons.smart_toy_outlined),
                const Spacer(),
                if (_output != null && _panelActivo == _PanelInferior.output)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _badgeResultado(p, _output!),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: p.borderSoft),
          Expanded(child: _contenidoPanelInferior(p)),
        ],
      ),
    );
  }

  Widget _tabPanel(AppPalette p, _PanelInferior tab, String label, IconData icono,
      {int contador = 0}) {
    final activa = _panelActivo == tab;
    return InkWell(
      onTap: () => setState(() => _panelActivo = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          border: activa
              ? Border(bottom: BorderSide(color: p.primary, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 12, color: activa ? p.text : p.subtle),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: activa ? p.text : p.muted,
                    fontWeight: activa ? FontWeight.w600 : FontWeight.w400)),
            if (contador > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$contador',
                    style: const TextStyle(
                        fontSize: 9.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contenidoPanelInferior(AppPalette p) {
    switch (_panelActivo) {
      case _PanelInferior.output:
        if (_output == null && !_ejecutando) {
          // Empty state limpio, sin emoji ASCII ni paréntesis tutoriales.
          return Container(
            color: p.codeBg,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 14, color: p.subtle),
                const SizedBox(width: 8),
                Text(
                  'La salida del programa aparecerá aquí',
                  style: TextStyle(
                    fontSize: 12, color: p.subtle,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          color: p.codeBg,
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: SelectableText(
              _output == null
                  ? 'Ejecutando código en sandbox…'
                  : _construirOutput(_output!),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                fontFamily: AppFonts.monoFallback.first,
                fontFamilyFallback: AppFonts.monoFallback,
                color: p.codeText,
              ),
            ),
          ),
        );
      case _PanelInferior.terminal:
        // Terminal interactiva real: el usuario puede ejecutar pip install,
        // python archivo.py, ls, cd, etc. Arranca en la carpeta del archivo
        // activo (o en la carpeta raíz del proyecto si hay una abierta).
        return TerminalView(
          key: _terminalKey,
          cwdInicial: _cwdParaTerminal,
          compacta: true,
        );
      case _PanelInferior.problemas:
        return Center(
          child: Text(
            _problemas.isEmpty
                ? 'Sin problemas detectados.\n(Linting en tiempo real — próximamente)'
                : _problemas.join('\n'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
        );
      case _PanelInferior.ia:
        return _contenidoPanelIa(p);
    }
  }

  /// Panel del Asistente IA — ahora vive abajo, no en un sidebar lateral.
  Widget _contenidoPanelIa(AppPalette p) {
    final t = _tabActiva;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cuerpo (sugerencias + respuesta)
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t == null
                      ? 'Abre un archivo para que el asistente lo vea como contexto.'
                      : 'Asistente con contexto: ${t.nombre} · ${t.lenguaje}',
                  style: TextStyle(
                      fontSize: 11.5, color: p.muted, height: 1.5),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _chipIa(p, '¿Qué hace este código?', _consultarIa),
                    _chipIa(p, 'Encuentra bugs', _consultarIa),
                    _chipIa(p, 'Refactoriza esto', _consultarIa),
                    _chipIa(p, 'Añade docstrings', _consultarIa),
                    _chipIa(p, 'Optimiza el rendimiento', _consultarIa),
                  ],
                ),
                const SizedBox(height: 12),
                if (_iaCargando)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.primary),
                      ),
                    ),
                  )
                else if (_iaUltimaRespuesta != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _iaUltimaRespuesta!,
                      style: TextStyle(
                          fontSize: 12, color: p.text, height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: p.borderSoft),
        // Input para preguntar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _iaCtrl,
                  style: TextStyle(fontSize: 12.5, color: p.text),
                  decoration: InputDecoration(
                    hintText: 'Pregunta al asistente sobre el código...',
                    hintStyle:
                        TextStyle(fontSize: 12.5, color: p.subtle),
                    filled: true,
                    fillColor: p.surface2,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: p.borderSoft),
                    ),
                  ),
                  onSubmitted: (v) {
                    _consultarIa(v);
                    _iaCtrl.clear();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _iaCargando
                    ? null
                    : () {
                        _consultarIa(_iaCtrl.text);
                        _iaCtrl.clear();
                      },
                icon: Icon(Icons.send, size: 16, color: p.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _construirOutput(_ResultadoEjecucion o) {
    final partes = <String>[];
    if (o.stdout.isNotEmpty) partes.add(o.stdout);
    if (o.stderr.isNotEmpty) {
      partes.add(o.stdout.isNotEmpty
          ? '\n--- stderr ---\n' + o.stderr
          : o.stderr);
    }
    if (partes.isEmpty) partes.add('(sin salida)');
    return partes.join('');
  }

  Widget _badgeResultado(AppPalette p, _ResultadoEjecucion o) {
    final ok = o.exitCode == 0 && !o.timeout;
    final color = o.timeout
        ? AppColors.warning
        : (ok ? AppColors.success : AppColors.danger);
    final icono = o.timeout
        ? Icons.timer_outlined
        : (ok ? Icons.check_circle_outline : Icons.error_outline);
    final texto = o.timeout
        ? 'timeout · ${o.duracion.toStringAsFixed(2)}s'
        : 'exit ${o.exitCode} · ${o.duracion.toStringAsFixed(2)}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: color),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  fontSize: 10.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback)),
        ],
      ),
    );
  }

  // El panel IA antiguamente lateral ahora vive como tab del panel
  // inferior. Ver _contenidoPanelIa().

  Widget _chipIa(AppPalette p, String label, void Function(String) onTap) {
    return InkWell(
      onTap: () => onTap(label),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: p.borderSoft),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10.5, color: p.muted)),
      ),
    );
  }

  // ──────────── Estado vacío ────────────

  Widget _vacio(AppPalette p) {
    return Container(
      color: p.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 92, height: 92,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 62, height: 62,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(Icons.code_rounded,
                        size: 26, color: p.primary),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Sin archivos abiertos',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 22, fontWeight: FontWeight.w600,
                  color: p.text, letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abre un archivo desde el explorador o crea uno nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5, color: p.muted, height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _abrirArchivos,
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: const Text('Abrir archivo'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _nuevoArchivo,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.borderSoft),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('Nuevo archivo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────── Helpers ────────────

  IconData _iconoLenguaje(String l) => switch (l) {
        'python' => Icons.terminal,
        'dart' => Icons.flutter_dash,
        'javascript' || 'typescript' => Icons.javascript,
        'json' || 'yaml' => Icons.data_object,
        'markdown' => Icons.article_outlined,
        'html' || 'css' => Icons.web,
        _ => Icons.description_outlined,
      };

  String _lenguajeDeExtension(String ext) => switch (ext.toLowerCase()) {
        'py' => 'python',
        'dart' => 'dart',
        'js' || 'mjs' || 'cjs' => 'javascript',
        'jsx' => 'javascript',
        'ts' || 'tsx' => 'typescript',
        'json' => 'json',
        'md' => 'markdown',
        'yaml' || 'yml' => 'yaml',
        'java' => 'java',
        'kt' => 'kotlin',
        'rs' => 'rust',
        'go' => 'go',
        'c' || 'h' => 'c',
        'cpp' || 'hpp' || 'cc' => 'cpp',
        'cs' => 'csharp',
        'rb' => 'ruby',
        'php' => 'php',
        'sh' => 'bash',
        'html' => 'html',
        'css' => 'css',
        _ => 'texto',
      };

  /// Devuelve el nombre del runtime para sandbox o null si no es ejecutable.
  String? _lenguajeEjecutable(String l) => switch (l) {
        'python' => 'python',
        'javascript' => 'javascript',
        'typescript' => 'javascript', // Node los acepta si están transpilados
        'bash' || 'shell' => 'bash',
        _ => null,
      };
}

// ════════════════════════════════════════════════════════════════════
// CodeController — TextEditingController que aplica syntax highlight
// INLINE vía buildTextSpan. Esto elimina el bug de overlays
// desalineados que causaba el efecto "texto rayado".
// ════════════════════════════════════════════════════════════════════

class _CodeController extends TextEditingController {
  String lenguaje;
  AppPalette palette;

  _CodeController({
    required String text,
    required this.lenguaje,
    required this.palette,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }
    final spans = SyntaxHighlighter.highlight(text, lenguaje, palette);
    return TextSpan(style: style, children: spans);
  }
}

// ════════════════════════════════════════════════════════════════════
// Modelos internos
// ════════════════════════════════════════════════════════════════════

class _TabArchivo {
  String nombre;
  String? ruta;
  String contenido;
  String original;
  String lenguaje;
  _CodeController? _controller;

  _TabArchivo({
    required this.nombre,
    required this.ruta,
    required this.contenido,
    required this.original,
    required this.lenguaje,
    AppPalette? palette,
  }) {
    if (palette != null) {
      _controller = _CodeController(
        text: contenido, lenguaje: lenguaje, palette: palette,
      );
    }
  }

  /// El controller se inicializa lazy al primer build con la paleta real.
  _CodeController controller([AppPalette? p]) {
    if (_controller == null) {
      assert(p != null,
          'Se requiere paleta al primer acceso al controller');
      _controller = _CodeController(
        text: contenido, lenguaje: lenguaje, palette: p!,
      );
    }
    return _controller!;
  }

  void dispose() => _controller?.dispose();
}

class _ResultadoEjecucion {
  final String stdout;
  final String stderr;
  final int exitCode;
  final double duracion;
  final bool timeout;
  final String lenguaje;
  _ResultadoEjecucion({
    required this.stdout, required this.stderr,
    required this.exitCode, required this.duracion,
    required this.timeout, required this.lenguaje,
  });
}

enum _PanelInferior { output, terminal, problemas, ia }

class _GuardarIntent extends Intent { const _GuardarIntent(); }
class _EjecutarIntent extends Intent { const _EjecutarIntent(); }

// ════════════════════════════════════════════════════════════════════
// Divisores arrastrables (resize bars)
//
// Estos dos widgets son los gripper que el usuario arrastra para
// cambiar el tamaño de los paneles. Disparan un callback `onDrag`
// con el delta en píxeles cada vez que el cursor se mueve. El widget
// padre se encarga de actualizar el state con clamp a min/max.
// ════════════════════════════════════════════════════════════════════

class _DivisorHorizontal extends StatefulWidget {
  /// `delta` positivo = arrastró hacia abajo (panel inferior se hace más chico).
  final ValueChanged<double> onDrag;
  const _DivisorHorizontal({required this.onDrag});

  @override
  State<_DivisorHorizontal> createState() => _DivisorHorizontalState();
}

class _DivisorHorizontalState extends State<_DivisorHorizontal> {
  bool _hover = false;
  bool _arrastrando = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _arrastrando = true),
        onVerticalDragEnd: (_) => setState(() => _arrastrando = false),
        // delta.dy positivo = movió hacia abajo → panel inferior achica
        // (porque su alto = altoTotal - posiciónDivisor). Invertimos signo
        // para que el caller reciba "cuánto crece el panel inferior".
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 4,
          color: (_hover || _arrastrando)
              ? p.primary.withValues(alpha: 0.5)
              : p.borderSoft,
        ),
      ),
    );
  }
}

class _DivisorVertical extends StatefulWidget {
  /// `delta` positivo = arrastró hacia la derecha (panel derecho se hace más chico).
  final ValueChanged<double> onDrag;
  const _DivisorVertical({required this.onDrag});

  @override
  State<_DivisorVertical> createState() => _DivisorVerticalState();
}

class _DivisorVerticalState extends State<_DivisorVertical> {
  bool _hover = false;
  bool _arrastrando = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _arrastrando = true),
        onHorizontalDragEnd: (_) => setState(() => _arrastrando = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 4,
          color: (_hover || _arrastrando)
              ? p.primary.withValues(alpha: 0.5)
              : p.borderSoft,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Árbol de archivos del proyecto (tipo "Open Folder" de VS Code).
// `_NodoArchivo` representa cada entrada (archivo o carpeta).
// `_NodoCarpeta` es la raíz de un árbol.
// ════════════════════════════════════════════════════════════════════

class _NodoArchivo {
  final String nombre;
  final String ruta;
  final bool esCarpeta;
  final String? lenguaje;   // solo archivos
  bool expandido;            // solo carpetas
  List<_NodoArchivo>? hijos; // null = aún no se cargaron (lazy)

  _NodoArchivo._({
    required this.nombre,
    required this.ruta,
    required this.esCarpeta,
    this.lenguaje,
    this.expandido = false,
    this.hijos,
  });

  factory _NodoArchivo.archivo({
    required String nombre,
    required String ruta,
    required String lenguaje,
  }) =>
      _NodoArchivo._(
        nombre: nombre, ruta: ruta, esCarpeta: false, lenguaje: lenguaje,
      );

  factory _NodoArchivo.carpeta({
    required String nombre,
    required String ruta,
  }) =>
      _NodoArchivo._(
        nombre: nombre, ruta: ruta, esCarpeta: true,
      );
}

class _NodoCarpeta {
  final String nombre;
  final String ruta;
  final List<_NodoArchivo> hijos;
  _NodoCarpeta({
    required this.nombre,
    required this.ruta,
    required this.hijos,
  });
}
