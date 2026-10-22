import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../services/dialogos_nativos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../providers.dart';
import '../services/curriculum_catalog.dart';
import '../theme.dart';
import 'code/code_badges.dart';
import 'code/code_empty_state.dart';
import 'code/code_helpers.dart';
import 'code/code_models.dart';
import 'code/divisores.dart';
import 'code/diff_modal.dart';
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

enum ModoPanelDerecho { ia, archivos }

class CodeView extends StatefulWidget {
  const CodeView({super.key});

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final List<TabArchivo> _tabs = [];
  int _activa = -1;

  // Panel inferior (Output / Terminal / Problemas)
  PanelInferior _panelActivo = PanelInferior.output;
  ResultadoEjecucion? _output;
  bool _ejecutando = false;
  final List<String> _terminalLog = [];   // historial libre
  final List<String> _problemas = [];      // futuro: linting
  bool _panelInferiorMaximizado = false;
  double _altoPanelInferiorPrevio = 220;

  // Cajón derecho unificado (Asistente IA + Archivos del Proyecto)
  ModoPanelDerecho _modoPanelDerecho = ModoPanelDerecho.ia;

  // Carpeta abierta como "proyecto" (tipo Open Folder de VS Code).
  String? _carpetaRaiz;
  NodoCarpeta? _arbol;
  bool _cargandoArbol = false;

  // GlobalKey para acceder al State de la TerminalView embebida (para
  // sincronizar su CWD con el archivo activo y ejecutar comandos interactivos).
  final GlobalKey<TerminalViewState> _terminalKey = GlobalKey();
  TabArchivo? _archivoEnTerminal;

  // Panel IA Lateral estilo Cursor / Antigravity / GLM (Split View)
  bool _panelIaLateral = true;
  double _anchoPanelIa = 370;
  static const double _minAnchoPanelIa = 270;
  static const double _maxAnchoPanelIa = 620;
  final TextEditingController _iaCtrl = TextEditingController();
  final ScrollController _iaScrollCtrl = ScrollController();
  final FocusNode _iaFocusNode = FocusNode();
  bool _iaCargando = false;
  final List<MensajeEditorIa> _iaHistorial = [];
  String? _iaConversacionId;
  bool _iaCambioPendiente = false;

  // ── Tamaños dinámicos de los paneles (redimensionables) ─────────────
  /// Alto del panel inferior (output/terminal/problemas).
  double _altoPanelInferior = 220;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<SettingsProvider>(context);
    if (settings.carpetaProyecto != _carpetaRaiz) {
      _carpetaRaiz = settings.carpetaProyecto;
      if (_carpetaRaiz != null) {
        _refrescarArbolYAutoAbrir();
      } else {
        setState(() {
          _arbol = null;
        });
      }
    }
  }

  Future<void> _abrirRutaDirecta(String ruta) async {
    final nombre = ruta.split(Platform.pathSeparator).last;
    final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
    await _abrirDesdeArbol(NodoArchivo.archivo(
      nombre: nombre,
      ruta: ruta,
      lenguaje: lenguajeDeExtension(ext),
    ));
  }

  Future<void> _refrescarArbolYAutoAbrir() async {
    if (_carpetaRaiz == null) return;
    await _refrescarArbol();
    if (_tabs.isEmpty && mounted) {
      final sep = Platform.pathSeparator;
      final mainPy = File('$_carpetaRaiz${sep}main.py');
      final appPy = File('$_carpetaRaiz${sep}app.py');
      if (await mainPy.exists()) {
        await _abrirRutaDirecta(mainPy.path);
      } else if (await appPy.exists()) {
        await _abrirRutaDirecta(appPy.path);
      } else {
        try {
          final dir = Directory(_carpetaRaiz!);
          await for (final entidad in dir.list(followLinks: false)) {
            if (entidad is File && entidad.path.endsWith('.py')) {
              await _abrirRutaDirecta(entidad.path);
              break;
            }
          }
        } catch (_) {}
      }
    }
  }

  void _ejecutarEnTerminalInteractiva([String? comandoPersonalizado]) {
    final t = _tabActiva;
    _archivoEnTerminal = t;
    if (context.read<SettingsProvider>().esBloqueadoPostTest) return;
    setState(() {
      _panelActivo = PanelInferior.terminal;
      _output = null;
      _problemas.clear();
    });
    final nombreArchivo = t?.nombre ?? 'main.py';
    final cmd = comandoPersonalizado ?? 'python "$nombreArchivo"';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (comandoPersonalizado == null && t?.lenguaje == 'python') {
        _terminalKey.currentState?.ejecutarCodigoPython(t!.contenido);
      } else {
        _terminalKey.currentState?.ejecutarComando(cmd);
      }
    });
  }

  Future<void> _alHacerClicEjecutar() async {
    if (_ejecutando) return;
    if (_tabActiva == null) {
      if (_carpetaRaiz != null) {
        final sep = Platform.pathSeparator;
        final mainPy = File('$_carpetaRaiz${sep}main.py');
        final appPy = File('$_carpetaRaiz${sep}app.py');
        if (await mainPy.exists()) {
          await _abrirRutaDirecta(mainPy.path);
          await _ejecutar();
          return;
        } else if (await appPy.exists()) {
          await _abrirRutaDirecta(appPy.path);
          await _ejecutar();
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abre o selecciona un archivo de código Python (.py) para ejecutar.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    await _ejecutar();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    _iaCtrl.dispose();
    _iaScrollCtrl.dispose();
    _iaFocusNode.dispose();
    super.dispose();
  }

  TabArchivo? get _tabActiva =>
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

  static const Set<String> _extensionesBinarias = {
    'exe', 'dll', 'so', 'dylib', 'bin', 'gguf', 'iso', 'img',
    'zip', 'tar', 'gz', 'bz2', '7z', 'rar',
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'bmp',
    'mp4', 'mkv', 'avi', 'mov', 'mp3', 'wav', 'flac',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'db', 'sqlite', 'sqlite3', 'pyc', 'class', 'o', 'obj',
  };
  static const int _maxTamanoArchivoBytes = 3 * 1024 * 1024; // 3 MB límite seguro

  // ────────────────────── Acciones ──────────────────────

  Future<void> _abrirArchivos() async {
    final p = AppPalette.of(context);
    final rutas = await DialogosNativos.seleccionarArchivos(
      titulo: 'Abrir archivos en el editor',
      permitirMultiples: true,
    );
    if (rutas.isEmpty || !mounted) return;
    for (final ruta in rutas) {
      final i = _tabs.indexWhere((t) => t.ruta == ruta);
      if (i >= 0) {
        setState(() => _activa = i);
        continue;
      }
      final nombre = ruta.split(Platform.pathSeparator).last;
      final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
      if (_extensionesBinarias.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$nombre" es un archivo binario y no se puede abrir como texto.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        continue;
      }

      final file = File(ruta);
      if (!await file.exists()) continue;

      try {
        final tam = await file.length();
        if (tam > _maxTamanoArchivoBytes) {
          if (mounted) {
            final tamMb = (tam / (1024 * 1024)).toStringAsFixed(1);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"$nombre" ($tamMb MB) excede el límite de 3 MB para el editor.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          continue;
        }
      } catch (_) {}

      String contenido = '';
      try {
        final bytes = await file.readAsBytes();
        contenido = utf8.decode(bytes, allowMalformed: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo leer $nombre: $e')),
          );
        }
        continue;
      }
      if (!mounted) return;
      final lenguaje = lenguajeDeExtension(ext);
      setState(() {
        _tabs.add(TabArchivo(
          nombre: nombre,
          ruta: ruta,
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
    if (!mounted) return;
    final nombreLimpio = nombre.trim();
    final ext = nombreLimpio.contains('.') ? nombreLimpio.split('.').last : '';
    final lenguaje = lenguajeDeExtension(ext);
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
      _tabs.add(TabArchivo(
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
    try {
      final ruta = await DialogosNativos.seleccionarCarpeta(
        titulo: 'Abrir carpeta como proyecto',
      );
      if (ruta == null) return;
      if (!mounted) return;
      context.read<SettingsProvider>().setCarpetaProyecto(ruta);
      setState(() {
        _carpetaRaiz = ruta;
        _cargandoArbol = true;
        _iaHistorial.clear();
        _iaConversacionId = null;
        _iaCambioPendiente = false;
      });
      await _refrescarArbolYAutoAbrir();
    } catch (_) {}
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
  Future<NodoCarpeta> _construirArbol(String ruta, {int profundidad = 1}) async {
    final dir = Directory(ruta);
    final hijos = <NodoArchivo>[];
    try {
      await for (final entidad in dir.list(followLinks: false)) {
        final nombre = entidad.path.split(Platform.pathSeparator).last;
        // Skip carpetas ocultas / node_modules / __pycache__ etc.
        if (_ignorar(nombre)) continue;
        if (entidad is Directory) {
          hijos.add(NodoArchivo.carpeta(
            nombre: nombre,
            ruta: entidad.path,
          ));
        } else if (entidad is File) {
          hijos.add(NodoArchivo.archivo(
            nombre: nombre,
            ruta: entidad.path,
            lenguaje: lenguajeDeExtension(
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
    return NodoCarpeta(
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
      'target', 'bin', 'obj', '.next', 'models',
    }.contains(nombre);
  }

  /// Abre un archivo del árbol como tab.
  Future<void> _abrirDesdeArbol(NodoArchivo nodo) async {
    if (nodo.esCarpeta) return;
    // Si ya está abierto, solo activar.
    final i = _tabs.indexWhere((t) => t.ruta == nodo.ruta);
    if (i >= 0) {
      setState(() => _activa = i);
      return;
    }

    final ext = nodo.nombre.contains('.') ? nodo.nombre.split('.').last.toLowerCase() : '';
    if (_extensionesBinarias.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${nodo.nombre}" es un archivo binario y no se puede abrir como texto en el editor.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final file = File(nodo.ruta);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El archivo "${nodo.nombre}" no existe en disco.')),
        );
      }
      return;
    }

    try {
      final tamano = await file.length();
      if (tamano > _maxTamanoArchivoBytes) {
        if (mounted) {
          final tamMb = (tamano / (1024 * 1024)).toStringAsFixed(1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('El archivo "${nodo.nombre}" ($tamMb MB) excede el límite de 3 MB para el editor.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    String contenido = '';
    try {
      final bytes = await file.readAsBytes();
      contenido = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    final p = AppPalette.of(context);
    setState(() {
      _tabs.add(TabArchivo(
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
  Future<void> _renombrar(NodoArchivo nodo) async {
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
  Future<void> _eliminarNodo(NodoArchivo nodo) async {
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
    final rutaDialogo = DialogRoute<String>(
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
    final res = await Navigator.of(context, rootNavigator: true).push(rutaDialogo);
    await rutaDialogo.completed;
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
      final ruta = await DialogosNativos.guardarArchivo(
        titulo: 'Guardar archivo',
        nombreSugerido: t.nombre,
      );
      if (ruta == null) return;
      t.ruta = ruta;
      t.nombre = ruta.split(Platform.pathSeparator).last;
      // Re-detectar lenguaje según la nueva extensión.
      final ext = t.nombre.contains('.') ? t.nombre.split('.').last : '';
      final nuevoLenguaje = lenguajeDeExtension(ext);
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

  void _cargarRetoCurricular(LeccionCurricular leccion, AppPalette p) {
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].leccionCurricular?.id == leccion.id) {
        setState(() {
          _activa = i;
          _panelIaLateral = true;
        });
        return;
      }
    }

    final nombreArchivo = 'reto_${leccion.id.replaceAll('.', '_')}.py';
    final nuevaTab = TabArchivo(
      nombre: nombreArchivo,
      ruta: null,
      contenido: leccion.codigoInicial,
      original: leccion.codigoInicial,
      lenguaje: 'python',
      leccionCurricular: leccion,
      palette: p,
    );

    setState(() {
      _tabs.add(nuevaTab);
      _activa = _tabs.length - 1;
      _panelIaLateral = true;
      _iaHistorial.add(MensajeEditorIa(
        esUsuario: false,
        texto: '🎓 **Reto Curricular Activo: ${leccion.titulo}**\n\n'
            '📌 **Objetivo Pedagógico:**\n${leccion.descripcionPedagogica}\n\n'
            '👨‍🏫 **Guía Didáctica:**\n${leccion.guiaDocente}\n\n'
            '❓ **Pregunta de Autoevaluación:**\n*${leccion.preguntaAutoevaluacion}*\n\n'
            '---\n'
            '✍️ Desarrolla tu solución en el editor y presiona **▶ EJECUTAR** (F5) para probarla.\n'
            '💡 Si necesitas ayuda o pistas progresivas, haz clic en **"Pedir Pista Pedagógica"**.',
      ));
    });
    _autoScrollIa();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reto cargado en editor: ${leccion.titulo}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _mostrarPistasCurriculares(LeccionCurricular leccion) {
    if (!context.read<SettingsProvider>().esConAcompanamiento) return;
    final p = AppPalette.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Row(
          children: [
            const Icon(Icons.lightbulb_rounded, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pistas Pedagógicas: ${leccion.titulo}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.text),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Andamiaje Progresivo (El Libro de Python):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.subtle),
              ),
              const SizedBox(height: 10),
              ...leccion.pistasAndamiaje.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${entry.key + 1}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: TextStyle(fontSize: 12, color: p.text, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Divider(color: p.borderSoft),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.help_outline_rounded, size: 16, color: p.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Autoevaluación: ${leccion.preguntaAutoevaluacion}',
                      style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: p.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoRetosCurriculares(BuildContext context, AppPalette p, SettingsProvider settings) {
    if (settings.esBloqueadoPostTest) return;
    String nivelSeleccionado = settings.nivelModulo;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final lecciones = CurriculumCatalog.leccionesPorModulo(nivelSeleccionado);
          return AlertDialog(
            backgroundColor: p.surface,
            title: Row(
              children: [
                Icon(Icons.school_rounded, color: p.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.esSinAcompanamiento ? 'Preguntas de los módulos' : 'Retos Curriculares — El Libro de Python',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.text),
                      ),
                      Text(
                        settings.esSinAcompanamiento ? 'Las mismas consignas de los módulos: genera y corrige código sin pistas.' : 'Retos de los módulos con acompañamiento explicativo',
                        style: TextStyle(fontSize: 11.5, color: p.subtle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              height: 480,
              child: Column(
                children: [
                  Row(
                    children: [
                      _tabModuloDialog('principiante', 'Módulo 1: Principiante', nivelSeleccionado, p, () {
                        setDialogState(() => nivelSeleccionado = 'principiante');
                      }),
                      const SizedBox(width: 6),
                      _tabModuloDialog('intermedio', 'Módulo 2: Intermedio', nivelSeleccionado, p, () {
                        setDialogState(() => nivelSeleccionado = 'intermedio');
                      }),
                      const SizedBox(width: 6),
                      _tabModuloDialog('avanzado', 'Módulo 3: Avanzado', nivelSeleccionado, p, () {
                        setDialogState(() => nivelSeleccionado = 'avanzado');
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: p.borderSoft, height: 1),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: lecciones.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final lec = lecciones[i];
                        final estaAbierto = _tabs.any((t) => t.leccionCurricular?.id == lec.id);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: estaAbierto ? p.primary.withValues(alpha: 0.5) : p.borderSoft,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: p.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      settings.esSinAcompanamiento ? lec.numero : lec.id,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: p.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      lec.titulo,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: p.text,
                                      ),
                                    ),
                                  ),
                                  if (estaAbierto)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Abierto',
                                        style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  if (settings.esSinAcompanamiento)
                                    TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: lec.preguntaCodigo)), child: const Text('Copiar pregunta')),
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      if (settings.nivelModulo != nivelSeleccionado) {
                                        settings.setNivelModulo(nivelSeleccionado);
                                      }
                                      if (settings.esSinAcompanamiento) {
                                        _consultarIa(lec.preguntaCodigo);
                                      } else {
                                        _cargarRetoCurricular(lec, p);
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                    icon: Icon(estaAbierto ? Icons.open_in_new_rounded : Icons.code_rounded, size: 14),
                                    label: Text(settings.esSinAcompanamiento ? 'Generar código' : estaAbierto ? 'Ver en Editor' : 'Cargar Reto', style: const TextStyle(fontSize: 11.5)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                settings.esSinAcompanamiento ? lec.preguntaCodigo : lec.descripcionPedagogica,
                                style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.3),
                              ),
                              const SizedBox(height: 6),
                              if (settings.esConAcompanamiento) Row(
                                children: [
                                  Icon(Icons.school_outlined, size: 12, color: p.subtle),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      lec.guiaDocente,
                                      style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: p.subtle),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _mostrarPistasCurriculares(lec),
                                    child: Text(
                                      'Ver Pistas (${lec.pistasAndamiaje.length})',
                                      style: TextStyle(fontSize: 11, color: p.primary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabModuloDialog(String id, String titulo, String seleccionado, AppPalette p, VoidCallback onTap) {
    final activo = id == seleccionado;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? p.primary.withValues(alpha: 0.15) : p.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: activo ? p.primary : p.borderSoft),
          ),
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: activo ? FontWeight.bold : FontWeight.normal,
              color: activo ? p.primary : p.muted,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _ejecutar() async {
    final t = _tabActiva;
    if (t == null || _ejecutando) return;
    if (t.lenguaje == 'python' && RegExp(r'\binput\s*\(').hasMatch(t.contenido)) {
      _ejecutarEnTerminalInteractiva();
      return;
    }
    final ejecutable = lenguajeEjecutable(t.lenguaje);
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
      _panelActivo = PanelInferior.output;
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
        _output = ResultadoEjecucion(
          stdout: (r['stdout'] ?? '').toString(),
          stderr: (r['stderr'] ?? '').toString(),
          exitCode: (r['exit_code'] as num?)?.toInt() ?? -1,
          duracion: (r['duracion_segundos'] as num?)?.toDouble() ?? 0.0,
          timeout: r['timeout'] == true,
          lenguaje: ejecutable,
        );
        _extraerProblemasDeOutput(_output!, t.nombre);
      });
      _terminalLog.add(
        '${inicio.toString().substring(11, 19)} · ${ejecutable.toUpperCase()} '
        '· exit ${_output!.exitCode} · ${_output!.duracion.toStringAsFixed(2)}s',
      );
    } catch (e) {
      setState(() {
        _output = ResultadoEjecucion(
          stdout: '',
          stderr: 'Error invocando al backend: $e',
          exitCode: -1,
          duracion: 0,
          timeout: false,
          lenguaje: ejecutable,
        );
        _problemas.clear();
        _problemas.add('Error de conexión o ejecución: $e');
      });
    } finally {
      if (mounted) setState(() => _ejecutando = false);
    }
  }

  void _extraerProblemasDeOutput(ResultadoEjecucion out, String nombreArchivo) {
    _problemas.clear();
    final err = out.stderr.trim();
    if (err.isEmpty) return;

    final lineas = err.split('\n');
    for (final l in lineas) {
      final s = l.trim();
      if (s.isEmpty) continue;
      if (s.endsWith('Error') ||
          s.contains('Error:') ||
          s.contains('Exception:')) {
        if (!_problemas.contains(s)) {
          _problemas.add(s);
        }
      }
    }
    if (_problemas.isEmpty && out.exitCode != 0) {
      _problemas.add('Proceso finalizado con código de error ${out.exitCode}');
    }
  }

  Future<void> _consultarIa(String pregunta, {String? instruccionPrevia}) async {
    final textoLimpio = pregunta.trim();
    if (textoLimpio.isEmpty || _iaCargando) return;
    if (instruccionPrevia == null) {
      if (await _crearCarpetaPorInstruccion(textoLimpio)) return;
      if (!mounted) return;
    }
    final t = _tabActiva;
    final settings = context.read<SettingsProvider>();
    final api = context.read<AuthProvider>().api;

    setState(() {
      _iaCargando = true;
      _panelIaLateral = true; // Abre automáticamente el panel lateral de IA
      _iaHistorial.add(MensajeEditorIa(
        esUsuario: true,
        texto: textoLimpio,
      ));
    });

    _autoScrollIa();

    try {
    final contenidoAlEnviar = t?.contenido;
    final pideCambio = esPeticionDeCambio(textoLimpio) ||
        (_iaCambioPendiente && esConfirmacionDeCambio(textoLimpio));
    final buffer = StringBuffer();
    if (instruccionPrevia != null && instruccionPrevia.isNotEmpty) {
      buffer.writeln(instruccionPrevia);
      buffer.writeln();
    }

    buffer.writeln('[PETICION_USUARIO]');
    buffer.writeln(textoLimpio);
    final nombreUsuario = context.read<AuthProvider>().usuario?.nombre;
    if (nombreUsuario != null && RegExp(r'\bmi nombre\b', caseSensitive: false).hasMatch(textoLimpio)) {
      buffer.writeln('Nombre del solicitante para esta petición: ${jsonEncode(nombreUsuario)}. Si se pide input, conserva la entrada por teclado.');
    }
    buffer.writeln('[/PETICION_USUARIO]');
    if (_iaCambioPendiente && esConfirmacionDeCambio(textoLimpio)) {
      buffer.writeln('Aplica la corrección que propusiste en el turno anterior al archivo actual. Devuelve el archivo completo.');
    }
    final esNuevaCreacion = !pideCambio && esSolicitudNueva(textoLimpio);
    buffer.writeln('[EDITOR_OPERACION:${esNuevaCreacion ? 'crear' : pideCambio ? 'corregir' : 'consulta'}]');

    if (t != null && !esNuevaCreacion) {
      buffer.writeln(
        'Contexto: Estás colaborando en el archivo "${t.nombre}". '
        'Comprende con tu capacidad de inteligencia artificial la intención del estudiante: '
        'si pide programar, cambiar, quitar, adaptar o probar cualquier lógica en este archivo '
        '(por ejemplo: valores fijos, sin input, fórmulas, funciones o scripts directos), '
        'devuelve el código completo y funcional en un bloque ```${t.lenguaje} listo para ejecutarse.',
      );
      buffer.writeln();

      final p = AppPalette.of(context);
      final ctrl = t.controller(p);
      final seleccion = textoSeleccionadoSeguro(ctrl);
      final esDoc = t.lenguaje == 'markdown' ||
          t.nombre.toLowerCase().endsWith('.md') ||
          t.nombre.toLowerCase().endsWith('.txt');
      final etiqueta = esDoc ? 'Documento Markdown/Texto' : 'Código';
      if (seleccion.trim().isNotEmpty && !pideCambio) {
        buffer.writeln('Fragmento de $etiqueta seleccionado en el editor ("${t.nombre}"):');
        final seleccionSegura = seleccion.length > 3500
            ? seleccion.substring(0, 3500)
            : seleccion;
        buffer.writeln('```${t.lenguaje}\n$seleccionSegura\n```\n');
      } else {
        final contenidoSeguro = t.contenido.length > 180000
            ? '${t.contenido.substring(0, 90000)}\n# ... [contenido intermedio omitido] ...\n${t.contenido.substring(t.contenido.length - 90000)}'
            : t.contenido;
        buffer.writeln('$etiqueta actual en el editor ("${t.nombre}"):');
        buffer.writeln('```${t.lenguaje}');
        buffer.writeln(contenidoSeguro);
        buffer.writeln('```');
      }
    } else if (esNuevaCreacion) {
      buffer.writeln('Instrucción: El usuario solicita crear una solución o código nuevo. Genera el código completo, limpio y listo para ejecutarse.');
    } else if (_carpetaRaiz != null) {
      final hijosNombres = _arbol?.hijos.map((h) => (h.esCarpeta ? '📁 ' : '📄 ') + h.nombre).take(20).join(', ') ?? '';
      buffer.writeln('Contexto del proyecto: Carpeta "${_carpetaRaiz!.split(Platform.pathSeparator).last}".');
      if (hijosNombres.isNotEmpty) {
        buffer.writeln('Estructura de archivos: $hijosNombres.');
      }
    }

    if (t == null && !esNuevaCreacion) {
      for (final mensaje in _iaHistorial.reversed) {
        if (mensaje.esUsuario || mensaje.codigoExtraido == null) continue;
        final codigoPrevio = mensaje.codigoExtraido!.trim();
        if (codigoPrevio.isNotEmpty) {
          buffer.writeln('Último código generado para continuar:');
          buffer.writeln('```python');
          buffer.writeln(codigoPrevio.length > 3000
              ? codigoPrevio.substring(0, 3000)
              : codigoPrevio);
          buffer.writeln('```');
          break;
        }
      }
    }

    // Incluir contexto pedagógico si hay un reto curricular activo y es relevante para el archivo actual
    if (t?.leccionCurricular != null && settings.esConAcompanamiento && !esNuevaCreacion) {
      final lec = t!.leccionCurricular!;
      buffer.writeln('\n[RETO CURRICULAR ACTIVO]');
      buffer.writeln('Título del Reto: ${lec.titulo}');
      buffer.writeln('Objetivo Pedagógico: ${lec.descripcionPedagogica}');
      buffer.writeln('Guía Didáctica: ${lec.guiaDocente}');
      buffer.writeln('Pregunta de Autoevaluación Sugerida: ${lec.preguntaAutoevaluacion}');
    }

    // Incluir error reciente de terminal solo si el usuario pide corregir o no es nueva creación
    if (_output != null && _output!.stderr.trim().isNotEmpty && !esNuevaCreacion) {
      buffer.writeln('\nSalida de error reciente de la última ejecución (stderr):');
      final error = _output!.stderr.trim();
      buffer.writeln('```\n${error.length > 1000 ? error.substring(0, 1000) : error}\n```');
    }

    final prompt = buffer.toString();

      _iaConversacionId ??= await api.crearConversacion(
        'Editor: ${t?.nombre ?? _carpetaRaiz?.split(Platform.pathSeparator).last ?? 'sin archivo'}',
      );
      final resp = await api.enviarMensaje(
        _iaConversacionId!,
        prompt,
        idioma: settings.idioma,
        buscarWeb: false,
        proveedor: settings.proveedor,
        modoAcompanamiento: settings.modoAcompanamiento,
        nivelModulo: settings.nivelModulo,
      ).timeout(const Duration(seconds: 90));
      if (mounted) {
        final respuestaTexto = resp.mensajeAsistente.contenido;
        final archivosPropuestos = extraerArchivosPropuestos(respuestaTexto);
        final archivoActualPropuesto = t != null && archivosPropuestos.length == 1 &&
            archivosPropuestos.single.rutaRelativa.replaceAll('\\', '/').split('/').last == t.nombre;
        final codigoExtraido = archivoActualPropuesto
            ? archivosPropuestos.single.contenido
            : _extraerCodigoDeMarkdown(respuestaTexto);
        Map<String, dynamic>? validacionPropuesta;
        if (codigoExtraido != null && (archivosPropuestos.isEmpty || archivoActualPropuesto) &&
            (t == null || esNuevaCreacion || t.lenguaje == 'python')) {
          validacionPropuesta = await api.validarSintaxisPython(codigoExtraido);
          if (!mounted) return;
          if ((validacionPropuesta['valido_para_aplicar'] ?? validacionPropuesta['valido']) != true) {
            _iaCambioPendiente = false;
            throw ApiException('La propuesta no se aplicó: ${validacionPropuesta['mensaje'] ?? validacionPropuesta['errores'] ?? 'verificación Python fallida'}');
          }
        }
        setState(() {
          _iaCambioPendiente = codigoExtraido != null || RegExp(
            r'(?:¿|\?).*(?:corr[íi][jg]|correg|arregl|modific|aplic|actualiz)|(?:quieres|deseas|puedo).*(?:corr[íi][jg]|correg|arregl|modific|aplic|actualiz)',
            caseSensitive: false,
          ).hasMatch(respuestaTexto);
          _iaHistorial.add(MensajeEditorIa(
            esUsuario: false,
            texto: respuestaTexto,
            codigoExtraido: codigoExtraido,
          ));
        });
        _autoScrollIa();

        // 🚀 APLICACIÓN INTELIGENTE EN TIEMPO REAL:
        // Si hay un archivo abierto y la IA generó una versión de código que difiere de la actual:
        if (codigoExtraido != null && codigoExtraido.trim().isNotEmpty && t != null && !esNuevaCreacion && pideCambio &&
            (archivosPropuestos.isEmpty || archivoActualPropuesto)) {
          final contextoCompleto = !resp.mensajeAsistente.contextoRecortado &&
              !resp.mensajeAsistente.respuestaIncompleta;
          final esDiferente = codigoExtraido.trim() != t.contenido.trim();
          if (esDiferente && contenidoAlEnviar!.length <= 180000 && contextoCompleto &&
              _tabs.contains(t) && t.contenido == contenidoAlEnviar) {
            final sintaxis = t.lenguaje == 'python'
                ? validacionPropuesta!
                : <String, dynamic>{'valido': true};
            if (!mounted) return;
            if ((sintaxis['valido_para_aplicar'] ?? sintaxis['valido']) == true) {
              if (_tabs.contains(t) && t.contenido == contenidoAlEnviar) {
                _reemplazarTodoElArchivo(codigoExtraido, archivo: t);
                _iaCambioPendiente = false;
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('La propuesta no pasó la validación de Python y no se aplicó. Revisa los errores del chat.'),
                duration: Duration(seconds: 3),
              ));
            }
          }
        } else if (codigoExtraido != null && codigoExtraido.trim().isNotEmpty && (t == null || esNuevaCreacion)) {
          // Si no hay archivo abierto y la IA generó código, crear y abrir pestaña automáticamente
          String nombreSugerido = 'programa.py';
          final cLow = codigoExtraido.toLowerCase();
          if (cLow.contains('calculadora')) {
            nombreSugerido = 'calculadora.py';
          } else if (cLow.contains('tabla') || cLow.contains('multiplic')) {
            nombreSugerido = 'tablas_multiplicar.py';
          } else if (cLow.contains('promedio')) {
            nombreSugerido = 'calcula_promedio.py';
          } else if (cLow.contains('fibonacci')) {
            nombreSugerido = 'fibonacci.py';
          }
          final p = AppPalette.of(context);
          setState(() {
            _tabs.add(TabArchivo(
              nombre: nombreSugerido,
              ruta: null,
              contenido: codigoExtraido,
              original: codigoExtraido,
              lenguaje: 'python',
              palette: p,
            ));
            _activa = _tabs.length - 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Se abrió una nueva pestaña con "$nombreSugerido" lista para ejecutar.'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (codigoExtraido != null && codigoExtraido.trim().isNotEmpty && t != null && t.contenido.trim().isEmpty) {
          await _aplicarPropuestaIa(codigoExtraido, archivo: t);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _iaHistorial.add(MensajeEditorIa(
            esUsuario: false,
            texto: e is TimeoutException
                ? 'La consulta superó el tiempo de espera y se detuvo. Puedes volver a intentarlo con una petición más concreta.'
                : 'No se pudo completar la consulta: $e',
          ));
        });
        _autoScrollIa();
      }
    } finally {
      if (mounted) setState(() => _iaCargando = false);
    }
  }

  Future<bool> _crearCarpetaPorInstruccion(String texto) async {
    final coincidencia = RegExp(
      r'^(?:crea|crear|haz|agrega|añade)\s+(?:(?:una?|otra)\s+)?carpeta\s+(?:llamada\s+)?["`]?([\w-]+)["`]?\s*[.!]?$',
      caseSensitive: false,
    ).firstMatch(texto);
    if (coincidencia == null) return false;
    final nombre = coincidencia.group(1)!;
    final raiz = _carpetaRaiz ?? await DialogosNativos.seleccionarCarpeta(
      titulo: 'Selecciona el proyecto donde crear $nombre',
    );
    if (raiz == null || !mounted) return true;
    final destino = Directory('$raiz${Platform.pathSeparator}$nombre');
    try {
      final existia = await destino.exists();
      if (!existia) await destino.create();
      setState(() {
        _carpetaRaiz = raiz;
        _iaHistorial.add(MensajeEditorIa(esUsuario: true, texto: texto));
        _iaHistorial.add(MensajeEditorIa(
          esUsuario: false,
          texto: existia ? 'La carpeta `$nombre` ya existe en el proyecto.'
              : 'Creé la carpeta `$nombre` dentro del proyecto abierto.',
        ));
      });
      await _refrescarArbol();
    } catch (e) {
      setState(() => _iaHistorial.add(MensajeEditorIa(
        esUsuario: false, texto: 'No se pudo crear la carpeta: $e',
      )));
    }
    _autoScrollIa();
    return true;
  }

  Future<void> _crearEstructuraDesdeIa(String respuesta) async {
    final archivos = extraerArchivosPropuestos(respuesta).take(30).toList();
    if (archivos.isEmpty) return;
    final raiz = _carpetaRaiz ?? await DialogosNativos.seleccionarCarpeta(
      titulo: 'Selecciona la carpeta raíz del proyecto',
    );
    if (raiz == null || !mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Crear estructura propuesta'),
        content: SizedBox(
          width: 480,
          height: 240,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Revisa las rutas. Los archivos existentes se conservarán.'),
            const SizedBox(height: 10),
            Expanded(child: ListView(children: [
              for (final archivo in archivos) Text('• ${archivo.rutaRelativa}'),
            ])),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Crear archivos')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    var creados = 0;
    var omitidos = 0;
    for (final archivo in archivos) {
      final partes = archivo.rutaRelativa.replaceAll('\\', '/').split('/');
      if (!rutaPropuestaSegura(archivo.rutaRelativa)) {
        omitidos++;
        continue;
      }
      var actual = raiz;
      var enlace = false;
      for (final parte in partes.take(partes.length - 1)) {
        actual = '$actual${Platform.pathSeparator}$parte';
        if (await FileSystemEntity.type(actual, followLinks: false) == FileSystemEntityType.link) {
          enlace = true;
          break;
        }
      }
      if (enlace) { omitidos++; continue; }
      final ruta = '$raiz${Platform.pathSeparator}${partes.join(Platform.pathSeparator)}';
      final archivoDisco = File(ruta);
      if (await archivoDisco.exists()) { omitidos++; continue; }
      try {
        await archivoDisco.parent.create(recursive: true);
        await archivoDisco.writeAsString(archivo.contenido, flush: true);
        creados++;
      } catch (_) { omitidos++; }
    }
    if (!mounted) return;
    setState(() => _carpetaRaiz = raiz);
    await _refrescarArbol();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Estructura aplicada: $creados archivo(s) creados, $omitidos omitidos.'),
    ));
  }

  Future<void> _ejecutarAuditoriaAst() async {
    setState(() {
      _iaCargando = true;
      _panelIaLateral = true;
      _iaHistorial.add(MensajeEditorIa(
        esUsuario: true,
        texto: 'Auditoría arquitectónica completa del proyecto mediante AST (Map-Reduce).',
      ));
    });
    _autoScrollIa();

    try {
      final api = context.read<AuthProvider>().api;
      final res = await api.auditarProyectoAST(conAuditoriaIa: true, proveedor: 'auto');
      if (mounted) {
        final informe = res['informe_ia']?.toString() ?? 'Auditoría completada.';
        setState(() {
          _iaHistorial.add(MensajeEditorIa(
            esUsuario: false,
            texto: informe,
          ));
        });
        _autoScrollIa();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _iaHistorial.add(MensajeEditorIa(
            esUsuario: false,
            texto: 'Error al realizar la auditoría AST: $e',
          ));
        });
        _autoScrollIa();
      }
    } finally {
      if (mounted) setState(() => _iaCargando = false);
    }
  }

  void _autoScrollIa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_iaScrollCtrl.hasClients) {
        _iaScrollCtrl.animateTo(
          _iaScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertarCodigoEnCursor(String codigo) {
    final t = _tabActiva;
    if (t == null) return;
    final p = AppPalette.of(context);
    final ctrl = t.controller(p);
    final text = ctrl.text;
    final sel = ctrl.selection;

    int start = sel.start;
    int end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final nuevoTexto = text.replaceRange(start, end, codigo);
    setState(() {
      t.contenido = nuevoTexto;
      ctrl.text = nuevoTexto;
      ctrl.selection = TextSelection.collapsed(offset: start + codigo.length);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código insertado en la posición del cursor'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _aplicarPropuestaIa(String codigo, {TabArchivo? archivo}) async {
    final destino = archivo ?? _tabActiva;
    if (destino == null) return;
    final anterior = destino.contenido;
    try {
      if (destino.lenguaje == 'python') {
        final verificacion = await context.read<AuthProvider>().api.validarSintaxisPython(codigo);
        if (!mounted) return;
        if ((verificacion['valido_para_aplicar'] ?? verificacion['valido']) != true) {
          throw ApiException(verificacion['mensaje']?.toString() ?? 'La propuesta no pasó la verificación Python.');
        }
      }
      if (!mounted || !_tabs.contains(destino) || destino.contenido != anterior) return;
      _reemplazarTodoElArchivo(codigo, archivo: destino);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Archivo conservado: $e')));
    }
  }

  void _reemplazarTodoElArchivo(String nuevoCodigo, {TabArchivo? archivo}) {
    final t = archivo ?? _tabActiva;
    if (t == null) return;
    final p = AppPalette.of(context);
    final anterior = t.contenido;
    setState(() {
      t.contenido = nuevoCodigo;
      t.controller(p).text = nuevoCodigo;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 360,
        backgroundColor: p.surface2,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: p.borderSoft),
        ),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF4ADE80)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${t.nombre} actualizado (Ctrl+S)',
                style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: p.primary,
          onPressed: () {
            if (!mounted || !_tabs.contains(t) || t.contenido != nuevoCodigo) return;
            setState(() {
              t.contenido = anterior;
              t.controller(p).text = anterior;
            });
          },
        ),
      ),
    );
  }

  Future<void> _crearArchivoDesdeIa(String codigo) async {
    final p = AppPalette.of(context);
    String nombreSugerido = 'programa.py';
    final cLow = codigo.toLowerCase();
    if (cLow.contains('tabla') || cLow.contains('multiplic')) {
      nombreSugerido = 'tablas_multiplicar.py';
    } else if (cLow.contains('promedio')) {
      nombreSugerido = 'calcula_promedio.py';
    } else if (cLow.contains('primo')) {
      nombreSugerido = 'numeros_primos.py';
    } else if (cLow.contains('par') && cLow.contains('impar')) {
      nombreSugerido = 'par_o_impar.py';
    } else if (cLow.contains('calculadora')) {
      nombreSugerido = 'calculadora.py';
    } else if (cLow.contains('fibonacci')) {
      nombreSugerido = 'fibonacci.py';
    } else if (cLow.contains('factorial')) {
      nombreSugerido = 'factorial.py';
    } else if (cLow.contains('orden') || cLow.contains('burbuja')) {
      nombreSugerido = 'ordenamiento.py';
    }

    final nombreElegido = await _dialogoTexto(
      titulo: 'Crear nuevo archivo con este código',
      etiqueta: 'Nombre del archivo',
      valorInicial: nombreSugerido,
      botonOk: 'Crear y Abrir',
    );
    if (nombreElegido == null || nombreElegido.trim().isEmpty) return;
    final nombreFinal = nombreElegido.trim();
    final ext = nombreFinal.contains('.') ? nombreFinal.split('.').last : 'py';
    final lenguaje = lenguajeDeExtension(ext);

    if (lenguaje == 'python') {
      try {
        final verificacion = await context.read<AuthProvider>().api.validarSintaxisPython(codigo);
        if (!mounted) return;
        if ((verificacion['valido_para_aplicar'] ?? verificacion['valido']) != true) {
          throw ApiException(verificacion['mensaje']?.toString() ?? 'La propuesta no pasó la verificación Python.');
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se creó el archivo: $e')));
        return;
      }
    }

    String? rutaFinal;
    if (_carpetaRaiz != null) {
      rutaFinal = '$_carpetaRaiz${Platform.pathSeparator}$nombreFinal';
      try {
        await File(rutaFinal).writeAsString(codigo, flush: true);
        await _refrescarArbol();
      } catch (_) {}
    }

    setState(() {
      _tabs.add(TabArchivo(
        nombre: nombreFinal,
        ruta: rutaFinal,
        contenido: codigo,
        original: codigo,
        lenguaje: lenguaje,
        palette: p,
      ));
      _activa = _tabs.length - 1;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archivo "$nombreFinal" creado y abierto en el editor.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _copiarCodigo(String codigo) {
    Clipboard.setData(ClipboardData(text: codigo));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ────────────────────── Build ──────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true): const GuardarIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): const GuardarIntent(),
        SingleActivator(LogicalKeyboardKey.f5): const EjecutarIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, control: true): const EjecutarIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true): const EjecutarIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          GuardarIntent: CallbackAction<GuardarIntent>(
              onInvoke: (_) { _guardar(); return null; }),
          EjecutarIntent: CallbackAction<EjecutarIntent>(
              onInvoke: (_) { _ejecutar(); return null; }),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final disponible = constraints.maxWidth;
              final maxIa = (disponible * 0.45).clamp(240.0, _maxAnchoPanelIa);
              final anchoIa = _anchoPanelIa.clamp(240.0, maxIa);

              return Container(
                color: p.bg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Centro: EDITOR + PANEL INFERIOR (Ocupa todo el ancho central) ──
                    Expanded(
                      child: Column(
                        children: [
                          _tabBar(p),
                          _breadcrumbBar(p),
                          Container(height: 1, color: p.borderSoft),
                          Expanded(child: _editor(p)),
                          _toolbar(p),
                          // Divisor horizontal arrastrable: cambia el alto
                          // del panel inferior (output / terminal / problemas).
                          DivisorHorizontal(
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
                    // ── Lado DERECHO: CAJÓN UNIFICADO (Asistente IA + Archivos del Proyecto) ──
                    if (_panelIaLateral)
                      DivisorVertical(
                        onDrag: (delta) {
                          setState(() {
                            _anchoPanelIa = (_anchoPanelIa - delta)
                                .clamp(_minAnchoPanelIa, _maxAnchoPanelIa);
                          });
                        },
                      ),
                    if (_panelIaLateral)
                      SizedBox(
                        width: anchoIa,
                        child: _cajonDerechoUnificado(p),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ──────────── Breadcrumb Bar (Estilo VS Code / Cursor) ────────────

  Widget _breadcrumbBar(AppPalette p) {
    final t = _tabActiva;
    final nombre = t?.nombre ?? 'Sin archivo seleccionado';
    final lines = t != null ? (t.contenido.split('\n').length) : 0;
    final lenguaje = t?.lenguaje.toUpperCase() ?? 'TEXT';
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surface2.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_outlined, size: 13, color: p.subtle),
          const SizedBox(width: 5),
          Text(
            _carpetaRaiz != null
                ? _carpetaRaiz!.split(Platform.pathSeparator).last
                : 'Proyecto',
            style: TextStyle(fontSize: 11, color: p.subtle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('›', style: TextStyle(fontSize: 12, color: p.subtle)),
          ),
          if (t != null) ...[
            Icon(iconoLenguaje(t.lenguaje), size: 12, color: p.primary),
            const SizedBox(width: 5),
            Text(
              nombre,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: p.text,
              ),
            ),
            const Spacer(),
            Text(
              '$lines líneas  •  $lenguaje  •  UTF-8',
              style: TextStyle(
                fontSize: 10.5,
                color: p.subtle,
              ),
            ),
          ] else ...[
            Text('Ningún archivo abierto',
                style: TextStyle(fontSize: 11, color: p.subtle)),
          ],
        ],
      ),
    );
  }

  // ──────────── Sidebar de archivos ────────────

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
                _miniIcon(p, Icons.close, 'Cerrar panel',
                    () => setState(() => _panelIaLateral = false)),
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
  Widget _nodoTile(AppPalette p, NodoArchivo n, {required int profundidad}) {
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
                try {
                  final sub = await _construirArbol(n.ruta);
                  if (!mounted) return;
                  n.hijos = sub.hijos;
                } catch (_) {
                  n.hijos = [];
                }
              }
              if (mounted) {
                setState(() => n.expandido = !n.expandido);
              }
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
      iconoArchivo: iconoLenguaje(n.lenguaje ?? 'texto'),
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

  Future<void> _menuContextual(NodoArchivo n) async {
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
          // Toggle del panel de archivos (en el cajón derecho unificado).
          _miniIcon(
            p,
            (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.archivos)
                ? Icons.folder
                : Icons.folder_outlined,
            (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.archivos)
                ? 'Ocultar archivos'
                : 'Mostrar archivos',
            () {
              setState(() {
                if (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.archivos) {
                  _panelIaLateral = false;
                } else {
                  _panelIaLateral = true;
                  _modoPanelDerecho = ModoPanelDerecho.archivos;
                }
              });
            },
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
            Icon(iconoLenguaje(t.lenguaje), size: 12, color: p.muted),
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
    if (t == null) {
      return CodeEmptyState(
        onAbrir: _abrirArchivos,
        onNuevo: _nuevoArchivo,
      );
    }
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
              key: const ValueKey('editor-codigo'),
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: p.primary,
              onChanged: (v) => setState(() => t.contenido = v),
              contextMenuBuilder: (context, editableTextState) {
                final List<ContextMenuButtonItem> buttonItems =
                    List.from(editableTextState.contextMenuButtonItems);
                final seleccion = textoSeleccionadoSeguro(controller);
                if (seleccion.trim().isNotEmpty) {
                  buttonItems.insert(
                    0,
                    ContextMenuButtonItem(
                      label: '⚡ Explicar selección',
                      onPressed: () {
                        ContextMenuController.removeAny();
                        setState(() => _panelActivo = PanelInferior.ia);
                        final esDoc = t.lenguaje == 'markdown' ||
                            t.nombre.toLowerCase().endsWith('.md') ||
                            t.nombre.toLowerCase().endsWith('.txt');
                        if (esDoc) {
                          _consultarIa(
                            'Explica y contextualiza este fragmento del documento ("${t.nombre}"):\n\n$seleccion',
                          );
                        } else {
                          _consultarIa(
                            'Explícame paso a paso este fragmento de código:\n```${t.lenguaje}\n$seleccion\n```',
                          );
                        }
                      },
                    ),
                  );
                  buttonItems.insert(
                    1,
                    ContextMenuButtonItem(
                      label: '🐛 Detectar bugs',
                      onPressed: () {
                        ContextMenuController.removeAny();
                        setState(() => _panelActivo = PanelInferior.ia);
                        _consultarIa(
                          'Revisa si hay bugs o fallas en este código y cómo solucionarlos:\n```${t.lenguaje}\n$seleccion\n```',
                        );
                      },
                    ),
                  );
                  buttonItems.insert(
                    2,
                    ContextMenuButtonItem(
                      label: '✨ Optimizar',
                      onPressed: () {
                        ContextMenuController.removeAny();
                        setState(() => _panelActivo = PanelInferior.ia);
                        _consultarIa(
                          'Propón una versión más limpia y eficiente de este fragmento:\n```${t.lenguaje}\n$seleccion\n```',
                        );
                      },
                    ),
                  );
                }
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: buttonItems,
                );
              },
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
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();
    final ejecutable = t != null ? lenguajeEjecutable(t.lenguaje) : null;
    final puedeEjecutar = !_ejecutando && (t != null || _carpetaRaiz != null);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: esOscuro ? const Color(0xFF11131A) : p.surface,
        border: Border(top: BorderSide(color: esOscuro ? const Color(0xFF1C202C) : p.borderSoft)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // BOTÓN EJECUTAR — Estilo VS Code en tono Esmeralda brillante
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: puedeEjecutar ? const Color(0x2610B981) : (esOscuro ? const Color(0xFF181B24) : p.surface2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: puedeEjecutar ? const Color(0x7310B981) : (esOscuro ? const Color(0xFF282E40) : p.border),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: puedeEjecutar ? _alHacerClicEjecutar : null,
                  borderRadius: BorderRadius.circular(6),
                  hoverColor: const Color(0x4010B981),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_ejecutando)
                          const SizedBox(
                            height: 12,
                            width: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                            ),
                          )
                        else
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 15,
                            color: puedeEjecutar ? const Color(0xFF34D399) : p.subtle,
                          ),
                        const SizedBox(width: 5),
                        Text(
                          _ejecutando ? 'Ejecutando…' : '▶ Ejecutar (F5)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: puedeEjecutar ? const Color(0xFF34D399) : p.subtle,
                          ),
                        ),
                        if (ejecutable != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              ejecutable.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: puedeEjecutar ? const Color(0xFF34D399) : p.subtle,
                                fontFamily: AppFonts.monoFallback.first,
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
            const SizedBox(width: 6),
            // BOTÓN EJECUTAR EN TERMINAL INTERACTIVA
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: esOscuro ? const Color(0xFF181B24) : p.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: esOscuro ? const Color(0xFF282E40) : p.border,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: Tooltip(
                  message: 'Ejecutar script en Terminal interactiva (ideal para input())',
                  child: InkWell(
                    onTap: (t != null || _carpetaRaiz != null) ? () => _ejecutarEnTerminalInteractiva() : null,
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: p.primary.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.terminal_rounded,
                            size: 14,
                            color: (t != null || _carpetaRaiz != null) ? p.primary : p.subtle,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Terminal',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              color: (t != null || _carpetaRaiz != null) ? p.text : p.subtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Guardar — compacto 28px
            _btnSec(
              p,
              Icons.save_outlined,
              'Guardar',
              const Color(0xFFF8FAFC),
              t != null,
              'Guardar archivo (Ctrl+S)',
              _guardar,
            ),
            const SizedBox(width: 6),
            // Explicar a fondo con IA
            _btnSec(
              p,
              Icons.psychology_outlined,
              'Explicar',
              const Color(0xFF6366F1),
              settings.esConAcompanamiento && ((t != null && t.contenido.trim().isNotEmpty) || _carpetaRaiz != null),
              (t != null && (t.lenguaje == 'markdown' || t.nombre.toLowerCase().endsWith('.md') || t.nombre.toLowerCase().endsWith('.txt')))
                  ? 'Analizar y resumir este documento o especificación técnica'
                  : 'Explicar el código o sistema paso a paso con andamiaje pedagógico',
              () {
                final esDoc = t != null && (t.lenguaje == 'markdown' ||
                    t.nombre.toLowerCase().endsWith('.md') ||
                    t.nombre.toLowerCase().endsWith('.txt'));
                if (esDoc) {
                  _consultarIa(
                    'Analiza en detalle este documento ("${t.nombre}"): resume su propósito, sus secciones o requerimientos principales y explica claramente su contenido pedagógico o técnico.',
                  );
                } else {
                  _consultarIa(
                    'Explica en detalle qué hace este código o sistema: propósito general, arquitectura lógica paso a paso y variables clave.',
                  );
                }
              },
            ),
            const SizedBox(width: 6),
            // Detectar errores / bugs
            _btnSec(
              p,
              Icons.bug_report_outlined,
              'Detectar Errores',
              const Color(0xFFEF4444),
              settings.esConAcompanamiento && ((t != null && t.contenido.trim().isNotEmpty) || _carpetaRaiz != null),
              'Auditar posibles errores, excepciones y casos límite',
              () {
                _consultarIa(
                  'Audita a fondo este código buscando errores sintácticos, bugs lógicos, excepciones posibles (ZeroDivisionError, IndexError, etc.) y casos límite.',
                );
              },
            ),
            const SizedBox(width: 6),
            // Retos y Módulos Curriculares
            _btnSec(
              p,
              Icons.school_outlined,
              settings.esSinAcompanamiento ? 'Preguntas de los módulos' : 'Retos Curriculares',
              const Color(0xFF38BDF8),
              !settings.esBloqueadoPostTest,
              settings.esSinAcompanamiento ? 'Preguntas de las lecciones del módulo; también puedes escribir tu propia petición en el chat' : 'Explorar retos prácticos del currículo (${CurriculumCatalog.nombreNivel(settings.nivelModulo)})',
              () => _mostrarDialogoRetosCurriculares(context, p, settings),
            ),
            if (t != null && t.contenido != t.original) ...[
              const SizedBox(width: 6),
              _btnSec(
                p,
                Icons.difference_outlined,
                'Ver Diff',
                const Color(0xFF38BDF8),
                true,
                'Comparar cambios sin guardar respecto al original',
                () {
                  DiffModal.mostrar(
                    context,
                    codigoOriginal: t.original,
                    codigoNuevo: t.contenido,
                    nombreArchivo: t.nombre,
                    onAplicar: (nuevo) {
                      setState(() {
                        t.contenido = nuevo;
                        t.controller(p).text = nuevo;
                      });
                    },
                  );
                },
              ),
            ],
            const SizedBox(width: 12),
            if (t != null) ...[
              Text(
                '${t.contenido.split("\n").length} líneas',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              BadgeLenguaje(lenguaje: t.lenguaje),
              const SizedBox(width: 8),
              Container(width: 1, height: 16, color: const Color(0xFF282E40)),
              const SizedBox(width: 8),
            ],
            // Controles rápidos del Cajón Derecho Unificado
            _btnSec(
              p,
              (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.ia)
                  ? Icons.auto_awesome_rounded
                  : Icons.auto_awesome_outlined,
              'Asistente IA',
              const Color(0xFF6366F1),
              true,
              'Abrir o alternar Asistente IA',
              () {
                setState(() {
                  if (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.ia) {
                    _panelIaLateral = false;
                  } else {
                    _panelIaLateral = true;
                    _modoPanelDerecho = ModoPanelDerecho.ia;
                  }
                });
              },
            ),
            const SizedBox(width: 6),
            _btnSec(
              p,
              (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.archivos)
                  ? Icons.folder_open_rounded
                  : Icons.folder_outlined,
              'Archivos',
              const Color(0xFF38BDF8),
              true,
              'Ver archivos del proyecto en el panel derecho',
              () {
                setState(() {
                  if (_panelIaLateral && _modoPanelDerecho == ModoPanelDerecho.archivos) {
                    _panelIaLateral = false;
                  } else {
                    _panelIaLateral = true;
                    _modoPanelDerecho = ModoPanelDerecho.archivos;
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _btnSec(AppPalette p, IconData icono, String label, Color color,
      bool habilitado, String tip, VoidCallback onTap) {
    final esOscuro = p.codeBg.computeLuminance() < 0.5;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: esOscuro ? const Color(0xFF181B24) : p.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: esOscuro ? const Color(0xFF282E40) : p.borderSoft),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: habilitado ? onTap : null,
            borderRadius: BorderRadius.circular(6),
            hoverColor: p.primary.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icono,
                    size: 13,
                    color: habilitado
                        ? (esOscuro ? color : (color == const Color(0xFFF8FAFC) ? p.text : color))
                        : p.subtle,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: habilitado
                          ? (esOscuro
                              ? (color == p.text ? const Color(0xFFF8FAFC) : color)
                              : (color == const Color(0xFFF8FAFC) ? p.text : color))
                          : p.subtle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────── Panel inferior con tabs (Estilo VS Code) ────────────

  Widget _panelInferior(AppPalette p) {
    final esOscuro = p.codeBg.computeLuminance() < 0.5;
    return Container(
      decoration: BoxDecoration(
        color: esOscuro ? const Color(0xFF0F1117) : p.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera compacta 32px
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: esOscuro ? const Color(0xFF0B0D13) : p.surface2,
              border: Border(bottom: BorderSide(color: esOscuro ? const Color(0xFF1C202C) : p.borderSoft)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tabPanel(p, PanelInferior.terminal, 'TERMINAL', Icons.terminal_rounded),
                  _tabPanel(p, PanelInferior.output, 'SALIDA', Icons.output_rounded),
                  _tabPanel(p, PanelInferior.problemas, 'PROBLEMAS', Icons.warning_amber_rounded, contador: _problemas.length),
                  _tabPanel(p, PanelInferior.ia, 'Asistente IA', Icons.auto_awesome_rounded),
                  const SizedBox(width: 16),
                // Indicador de Sandbox
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: esOscuro ? const Color(0xFF161922) : p.surface3,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: esOscuro ? const Color(0xFF282E40) : p.borderSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🐍', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 4),
                      Text(
                        'Python 3.14 - Sandbox',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: esOscuro ? const Color(0xFF94A3B8) : p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Botón limpiar
                Tooltip(
                  message: 'Limpiar salida',
                  child: InkWell(
                    onTap: () => setState(() => _output = null),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.delete_outline_rounded, size: 14, color: esOscuro ? const Color(0xFF94A3B8) : p.muted),
                    ),
                  ),
                ),
                // Maximizar / Restaurar
                Tooltip(
                  message: _panelInferiorMaximizado ? 'Restaurar panel' : 'Maximizar panel',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (_panelInferiorMaximizado) {
                          _altoPanelInferior = _altoPanelInferiorPrevio;
                          _panelInferiorMaximizado = false;
                        } else {
                          _altoPanelInferiorPrevio = _altoPanelInferior;
                          _altoPanelInferior = 460;
                          _panelInferiorMaximizado = true;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        _panelInferiorMaximizado ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                        size: 13,
                        color: esOscuro ? const Color(0xFF94A3B8) : p.muted,
                      ),
                    ),
                  ),
                ),
                // Ocultar / Minimizar
                Tooltip(
                  message: 'Cerrar panel inferior',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _altoPanelInferior = _minAltoPanelInferior;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: esOscuro ? const Color(0xFF94A3B8) : p.muted),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
          Expanded(child: _contenidoPanelInferior(p)),
        ],
      ),
    );
  }

  Widget _tabPanel(AppPalette p, PanelInferior tab, String label, IconData icono,
      {int contador = 0}) {
    final activa = _panelActivo == tab;
    final esOscuro = p.codeBg.computeLuminance() < 0.5;
    return InkWell(
      onTap: () => setState(() => _panelActivo = tab),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activa
              ? (esOscuro ? const Color(0x1F6366F1) : p.primary.withValues(alpha: 0.12))
              : Colors.transparent,
          border: activa
              ? Border(bottom: BorderSide(color: p.primary, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 12, color: activa ? p.primary : (esOscuro ? const Color(0xFF64748B) : p.subtle)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                color: activa ? (esOscuro ? const Color(0xFFF8FAFC) : p.text) : (esOscuro ? const Color(0xFF94A3B8) : p.muted),
                fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (contador > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$contador',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contenidoPanelInferior(AppPalette p) {
    switch (_panelActivo) {
      case PanelInferior.output:
        if (_output == null && !_ejecutando) {
          return Container(
            color: p.codeBg,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 16, color: p.subtle),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Presiona "Ejecutar" (o F5) para correr el código y ver la salida aquí',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12, color: p.subtle,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          color: p.codeBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: p.surface2.withValues(alpha: 0.3),
                  border: Border(bottom: BorderSide(color: p.borderSoft.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    Text(
                      'Registro de Ejecución',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Limpiar salida',
                      child: InkWell(
                        onTap: () => setState(() => _output = null),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline_rounded, size: 14, color: p.muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_output != null && _output!.stderr.contains('EOFError'))
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.keyboard_outlined, size: 16, color: AppColors.info),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tu programa necesita datos escritos por ti. Abre la terminal, escribe cada respuesta y pulsa Enter.',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.info,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.terminal_rounded, size: 14),
                        label: const Text('Ejecutar en TERMINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _ejecutarEnTerminalInteractiva(),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _output == null
                        ? 'Ejecutando código...'
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
              ),
            ],
          ),
        );
      case PanelInferior.terminal:
        return TerminalView(
          key: _terminalKey,
          cwdInicial: _cwdParaTerminal,
          compacta: true,
          onIrASalida: () => setState(() => _panelActivo = PanelInferior.output),
          onIrAProblemas: () => setState(() => _panelActivo = PanelInferior.problemas),
          contadorProblemas: _problemas.length,
          onCorregirError: (error) {
            final indice = _archivoEnTerminal == null ? -1 : _tabs.indexOf(_archivoEnTerminal!);
            if (indice < 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abre de nuevo el archivo que produjo este error.')));
              return;
            }
            setState(() => _activa = indice);
            _consultarIa('Corrige el error del archivo actual conservando la entrada por teclado cuando exista.\nError de la terminal:\n$error');
          },
        );
      case PanelInferior.problemas:
        if (_problemas.isEmpty) {
          return Container(
            color: p.codeBg,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 30, color: Color(0xFF4ADE80)),
                const SizedBox(height: 8),
                Text(
                  'No se han detectado problemas en el archivo',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'Los errores sintácticos o excepciones de ejecución se mostrarán aquí.',
                  style: TextStyle(fontSize: 11.5, color: p.subtle),
                ),
              ],
            ),
          );
        }
        return Container(
          color: p.codeBg,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _problemas.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: p.borderSoft),
            itemBuilder: (context, idx) {
              final prob = _problemas[idx];
              final esEof = prob.contains('EOFError') || prob.contains('input');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        prob,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppFonts.monoFallback.first,
                          fontFamilyFallback: AppFonts.monoFallback,
                          color: p.codeText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (esEof) ...[
                      InkWell(
                        onTap: () => _ejecutarEnTerminalInteractiva(),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.terminal_rounded, size: 11, color: AppColors.info),
                              SizedBox(width: 4),
                              Text(
                                'Terminal interactiva',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.info,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    InkWell(
                      onTap: () {
                        final instruccion = esEof
                            ? 'Revisa el código actual conservando las llamadas input(). La entrada se recibe en la terminal; no la sustituyas por números inventados. Corrige únicamente los errores reales y devuelve el archivo completo.'
                            : context.read<SettingsProvider>().esSinAcompanamiento
                              ? 'Corrige este error en el archivo actual. Devuelve únicamente el archivo Python completo corregido:\n`$prob`'
                              : 'Corrige este error en el archivo actual y explica brevemente el cambio. Devuelve el código completo funcional:\n`$prob`';
                        _consultarIa(instruccion);
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 11, color: AppColors.danger),
                            SizedBox(width: 4),
                            Text(
                              'Corregir con IA',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      case PanelInferior.ia:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 22, color: p.primary),
              const SizedBox(height: 8),
              Text(
                'El Asistente IA está activo en el panel lateral derecho',
                style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Interactúa, genera y modifica código con andamiaje o directo desde allí.',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
              const SizedBox(height: 10),
              if (!_panelIaLateral)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.primary),
                  icon: const Icon(Icons.open_in_new_rounded, size: 13),
                  label: const Text('Abrir Panel Lateral de IA', style: TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => _panelIaLateral = true),
                ),
            ],
          ),
        );
    }
  }

  Widget _cajonDerechoUnificado(AppPalette p) {
    final t = _tabActiva;
    final settings = context.watch<SettingsProvider>();
    final esOscuro = p.codeBg.computeLuminance() < 0.5;
    return Container(
      color: esOscuro ? const Color(0xFF0F1117) : p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header del Cajón Unificado con pestañas [✨ Asistente IA | 📁 Archivos]
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: esOscuro ? const Color(0xFF0B0D13) : p.surface2,
              border: Border(bottom: BorderSide(color: esOscuro ? const Color(0xFF1C202C) : p.borderSoft)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tabItemCajon(p, ModoPanelDerecho.ia, '✨ Asistente IA'),
                  const SizedBox(width: 4),
                  _tabItemCajon(p, ModoPanelDerecho.archivos, '📁 Archivos'),
                  const SizedBox(width: 8),
                  if (_modoPanelDerecho == ModoPanelDerecho.ia && _iaHistorial.isNotEmpty)
                    _miniIcon(p, Icons.delete_sweep_outlined, 'Limpiar historial de chat', () {
                      setState(() {
                        _iaHistorial.clear();
                        _iaConversacionId = null;
                        _iaCambioPendiente = false;
                      });
                    }),
                  _miniIcon(p, Icons.close_rounded, 'Ocultar panel derecho', () {
                    setState(() => _panelIaLateral = false);
                  }),
                ],
              ),
            ),
          ),
          Expanded(
            child: _modoPanelDerecho == ModoPanelDerecho.ia
                ? _cuerpoAsistenteIa(p, t, settings)
                : _seccionExplorador(p),
          ),
        ],
      ),
    );
  }

  Widget _tabItemCajon(AppPalette p, ModoPanelDerecho modo, String label) {
    final activo = _modoPanelDerecho == modo;
    final esOscuro = p.codeBg.computeLuminance() < 0.5;
    return InkWell(
      onTap: () => setState(() => _modoPanelDerecho = modo),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: activo
              ? (esOscuro ? const Color(0x1F6366F1) : p.primary.withValues(alpha: 0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: activo
              ? Border.all(color: esOscuro ? const Color(0x556366F1) : p.primary.withValues(alpha: 0.35))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: activo ? FontWeight.w600 : FontWeight.w400,
            color: activo
                ? (esOscuro ? const Color(0xFFF8FAFC) : p.primary)
                : (esOscuro ? const Color(0xFF94A3B8) : p.muted),
          ),
        ),
      ),
    );
  }

  Widget _cuerpoAsistenteIa(AppPalette p, TabArchivo? t, SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // Sub-header de contexto de archivo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.surface2.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 12, color: p.subtle),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    t != null
                        ? '${t.nombre} (${t.lenguaje})'
                        : (_carpetaRaiz != null
                            ? 'Proyecto: ${_carpetaRaiz!.split(Platform.pathSeparator).last}'
                            : 'Sin archivo activo'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: p.muted,
                      fontFamily: AppFonts.monoFallback.first,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.borderSoft),
          // Banner de Reto Curricular si la pestaña activa tiene una lección
          if (t?.leccionCurricular != null && settings.esConAcompanamiento) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: p.primary.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, size: 14, color: p.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reto ${t!.leccionCurricular!.id}: ${t.leccionCurricular!.titulo}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: p.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          t.leccionCurricular!.descripcionPedagogica,
                          style: TextStyle(fontSize: 10, color: p.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _mostrarPistasCurriculares(t.leccionCurricular!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: p.borderSoft),
                      ),
                      child: Text(
                        '💡 Pistas',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.borderSoft),
          ],
          if (settings.esBloqueadoPostTest)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_clock_rounded, size: 36, color: AppColors.danger),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Modo Evaluación Post-Test',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: p.text),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'El asistente de inteligencia artificial está temporalmente deshabilitado en esta fase evaluativa.\n\nPor favor, resuelve tus algoritmos y ejercicios de programación directamente en el editor. El motor de ejecución (F5 / ▶) y la terminal interactiva continúan funcionando.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            // Lista de Mensajes / Estado inicial
            Expanded(
              child: _iaHistorial.isEmpty
                  ? _emptyStateIaLateral(p, t)
                  : ListView.builder(
                      controller: _iaScrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _iaHistorial.length + (_iaCargando ? 1 : 0),
                      itemBuilder: (context, idx) {
                        if (idx == _iaHistorial.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  height: 14,
                                  width: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: p.primary),
                                ),
                                const SizedBox(width: 8),
                                Text('Generando respuesta...',
                                    style: TextStyle(fontSize: 11.5, color: p.muted)),
                              ],
                            ),
                          );
                        }
                        final msg = _iaHistorial[idx];
                        return _itemMensajeIaLateral(p, msg, t);
                      },
                    ),
            ),
            Divider(height: 1, color: p.borderSoft),
            // Input inferior de instrucciones
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _iaCtrl,
                      key: const ValueKey('editor-pregunta'),
                      focusNode: _iaFocusNode,
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(fontSize: 12, color: p.text),
                      decoration: InputDecoration(
                        hintText: t != null
                            ? 'Instruye a la IA sobre "${t.nombre}"...'
                            : 'Instruye a la IA sobre tu código...',
                        hintStyle: TextStyle(fontSize: 11.5, color: p.subtle),
                        filled: true,
                        fillColor: p.surface2,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: p.borderSoft),
                        ),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          _consultarIa(v);
                          _iaCtrl.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _iaCargando
                        ? null
                        : () {
                            if (_iaCtrl.text.trim().isNotEmpty) {
                              _consultarIa(_iaCtrl.text);
                              _iaCtrl.clear();
                            }
                          },
                    icon: Icon(Icons.send_rounded, size: 16, color: p.primary),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
  }

  Widget _emptyStateIaLateral(AppPalette p, TabArchivo? t) {
    if (context.watch<SettingsProvider>().esSinAcompanamiento) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(
        'Generación directa de código. Describe el programa que necesitas; recibirás código Python. Puedes ejecutarlo en el editor. Las pistas, explicaciones y preguntas guiadas están desactivadas para esta condición.',
        style: TextStyle(color: p.text, height: 1.5),
      ));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.terminal_rounded, size: 28, color: p.primary),
          const SizedBox(height: 10),
          Text(
            'Asistente de Código y Algoritmos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Capacitado para generar código, analizar arquitectura, explicar paso a paso y detectar errores.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (t?.leccionCurricular != null) ...[
            () {
              final lec = t!.leccionCurricular!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ANDAMIAJE PEDAGÓGICO DEL RETO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: p.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _chipAccionLateral(
                    p,
                    Icons.lightbulb_outline_rounded,
                    'Pedir pista pedagógica sin la respuesta directa',
                    () => _consultarIa(
                      'Estoy resolviendo el reto curricular "${lec.titulo}". '
                      'Analiza mi código actual y proporciona una pista didáctica basada en andamiaje '
                      'para guiar mi razonamiento lógico, sin revelarme el código completo final.',
                    ),
                    colorAcento: AppColors.accent,
                  ),
                  const SizedBox(height: 6),
                  _chipAccionLateral(
                    p,
                    Icons.quiz_outlined,
                    'Pregunta de autoevaluación conceptual',
                    () => _consultarIa(
                      'Formula una pregunta socrática o de autoevaluación pedagógica basada en: '
                      '"${lec.preguntaAutoevaluacion}", ayudándome a razonar sobre mi código actual.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _chipAccionLateral(
                    p,
                    Icons.task_alt_rounded,
                    'Evaluar cumplimiento de objetivos del reto',
                    () => _consultarIa(
                      'Audita mi código frente a los objetivos pedagógicos del reto "${lec.titulo}". '
                      'Indica si he cumplido los requisitos esperados y sugiere mejoras de estilo pythónico.',
                    ),
                    colorAcento: AppColors.success,
                  ),
                  const SizedBox(height: 14),
                ],
              );
            }(),
          ],
          Text(
            'ACCIONES RÁPIDAS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: p.subtle,
            ),
          ),
          const SizedBox(height: 8),
          _chipAccionLateral(
            p,
            Icons.flash_on_rounded,
            'Generar nueva función o clase',
            () {
              _iaCtrl.text = 'Genera una función o clase para: ';
              _iaCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _iaCtrl.text.length));
              _iaFocusNode.requestFocus();
            },
          ),
          const SizedBox(height: 6),
          _chipAccionLateral(
            p,
            Icons.psychology_outlined,
            'Explicar este archivo a fondo',
            () {
              final tCur = _tabActiva;
              final esDoc = tCur != null && (tCur.lenguaje == 'markdown' ||
                  tCur.nombre.toLowerCase().endsWith('.md') ||
                  tCur.nombre.toLowerCase().endsWith('.txt'));
              if (esDoc) {
                _consultarIa(
                  'Analiza en detalle este documento ("${tCur.nombre}"): resume su propósito, sus secciones o requerimientos principales y explica claramente su contenido pedagógico o técnico.',
                );
              } else {
                _consultarIa(
                  'Explica en detalle qué hace este código o sistema: propósito general, arquitectura lógica paso a paso y variables clave.',
                );
              }
            },
          ),
          const SizedBox(height: 6),
          _chipAccionLateral(
            p,
            Icons.bug_report_outlined,
            'Buscar bugs y casos límite',
            () => _consultarIa('Audita a fondo este código buscando errores sintácticos, bugs lógicos, excepciones posibles y casos límite.'),
          ),
          const SizedBox(height: 6),
          _chipAccionLateral(
            p,
            Icons.account_tree_outlined,
            'Auditar arquitectura de proyecto (AST)',
            () => _ejecutarAuditoriaAst(),
          ),
          const SizedBox(height: 6),
          _chipAccionLateral(
            p,
            Icons.auto_awesome_rounded,
            'Optimizar y limpiar código',
            () => _consultarIa('Propón una versión más limpia, eficiente y pythónica de este código.'),
          ),
          if (_output != null && _output!.stderr.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _chipAccionLateral(
              p,
              Icons.warning_amber_rounded,
              'Analizar error de ejecución reciente',
              () => _consultarIa('Analiza el error que arrojó la última ejecución y propón la corrección exacta.'),
              colorAcento: AppColors.danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipAccionLateral(AppPalette p, IconData icono, String texto, VoidCallback onTap, {Color? colorAcento}) {
    final color = colorAcento ?? p.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.borderSoft),
        ),
        child: Row(
          children: [
            Icon(icono, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(fontSize: 11.5, color: p.text, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemMensajeIaLateral(AppPalette p, MensajeEditorIa msg, TabArchivo? t) {
    if (msg.esUsuario) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              msg.texto,
              style: TextStyle(fontSize: 12, color: p.text, height: 1.4),
            ),
          ),
        ),
      );
    }

    // Mensaje de la IA
    final codigo = msg.codigoExtraido;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 12, color: p.primary),
              const SizedBox(width: 5),
              Text(
                'Asistente',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.primary),
              ),
              const Spacer(),
              Tooltip(
                message: 'Copiar respuesta completa',
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.texto));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Respuesta copiada al portapapeles')),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy_rounded, size: 13, color: p.subtle),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.borderSoft),
            ),
            child: MarkdownBody(
              data: msg.texto,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 12, color: p.text, height: 1.45),
                h1: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: p.text),
                h2: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.text),
                h3: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.primary),
                code: TextStyle(
                  fontFamily: AppFonts.monoFallback.first,
                  fontSize: 11,
                  backgroundColor: p.surface3,
                  color: p.primary,
                ),
                codeblockDecoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.borderSoft),
                ),
              ),
            ),
          ),
          if (extraerArchivosPropuestos(msg.texto).isNotEmpty) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _crearEstructuraDesdeIa(msg.texto),
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: Text('Crear estructura (${extraerArchivosPropuestos(msg.texto).length} archivos)'),
            ),
          ],
          if (codigo != null && codigo.trim().isNotEmpty &&
              extraerArchivosPropuestos(msg.texto).isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: p.surface2.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.borderSoft),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.note_add_outlined, size: 13),
                    label: const Text('Crear como archivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    onPressed: () => _crearArchivoDesdeIa(codigo),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 13),
                    label: const Text('Reemplazar archivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    onPressed: () => _aplicarPropuestaIa(codigo),
                  ),
                  Tooltip(
                    message: 'Inserta este fragmento exactamente donde esté parpadeando el cursor en el editor',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        side: BorderSide(color: p.borderSoft),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.input_rounded, size: 13),
                      label: const Text('Pegar en posición del cursor', style: TextStyle(fontSize: 11)),
                      onPressed: () => _insertarCodigoEnCursor(codigo),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: BorderSide(color: AppColors.info.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.difference_rounded, size: 13),
                    label: const Text('Ver Diff', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      DiffModal.mostrar(
                        context,
                        codigoOriginal: t?.contenido ?? '',
                        codigoNuevo: codigo,
                        nombreArchivo: t?.nombre ?? 'codigo.py',
                        onAplicar: (nuevo) {
                          if (t != null) {
                            setState(() {
                              t.contenido = nuevo;
                              t.controller(p).text = nuevo;
                            });
                          }
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    tooltip: 'Copiar código',
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: () => _copiarCodigo(codigo),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _construirOutput(ResultadoEjecucion o) {
    final partes = <String>[];
    final ahora = DateTime.now();
    final hora = ahora.hour.toString().padLeft(2, '0');
    final min = ahora.minute.toString().padLeft(2, '0');
    final seg = ahora.second.toString().padLeft(2, '0');
    final ts = '[$hora:$min:$seg]';

    if (o.stdout.isNotEmpty) {
      final lineas = o.stdout.split('\n');
      for (final l in lineas) {
        if (l.isNotEmpty) {
          partes.add('$ts INFO: $l\n');
        }
      }
    }
    if (o.ok && o.stderr.isEmpty) {
      partes.add('$ts SUCCESS: Ejecución completada exitosamente (código 0)\n');
    }
    if (o.stderr.isNotEmpty) {
      final lineasErr = o.stderr.split('\n');
      for (final l in lineasErr) {
        if (l.isNotEmpty) {
          partes.add('$ts ERROR: $l\n');
        }
      }
    }
    if (partes.isEmpty) partes.add('$ts INFO: (sin salida)\n');
    return partes.join('');
  }

  String? _extraerCodigoDeMarkdown(String texto) {
    final matches = RegExp(r'```(?:\w+)?\r?\n([\s\S]*?)```').allMatches(texto);
    if (matches.isEmpty) return null;
    String? mejorBloque;
    for (final m in matches) {
      final codigo = m.group(1)?.trim();
      if (codigo == null || codigo.isEmpty) continue;
      if (mejorBloque == null || codigo.length > mejorBloque.length) {
        mejorBloque = codigo;
      }
    }
    return mejorBloque;
  }
}
