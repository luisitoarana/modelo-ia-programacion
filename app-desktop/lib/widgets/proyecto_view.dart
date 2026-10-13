import '../services/dialogos_nativos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../services/fs_local.dart';
import '../theme.dart';
import 'code/divisores.dart';

class _Item {
  final String nombre;
  final String ruta;
  final bool esCarpeta;
  _Item(this.nombre, this.ruta, this.esCarpeta);
}

/// Explorador de archivos de TU PC (no del proyecto del servidor).
///
/// Layout tipo IDE:
///   ┌─────────────────────────────────────────────────────────┐
///   │ Header: Explorador · [Abrir carpeta de mi PC]           │
///   ├─────────────────────────────────────────────────────────┤
///   │ Breadcrumb: C:\Users\tanyi\proyecto                     │
///   ├──────────── arbol ────────────┬─── visor del archivo ───┤
///   │ folder/                       │ file.py · [Ver] [Editar]│
///   │ ├── file1.py                  │ ┌─ syntax highlighting ─┐
///   │ └── file2.dart                │ │ def hola(): …         │
///   │ …                             │ └────────────────────── │
///   └─────────────────────────────────────────────────────────┘
class ProyectoView extends StatefulWidget {
  const ProyectoView({super.key});

  @override
  State<ProyectoView> createState() => _ProyectoViewState();
}

class _ProyectoViewState extends State<ProyectoView> {
  String? _raiz;
  String _ruta = '';
  List<_Item> _items = [];
  bool _cargando = false;

  String? _archivoNombre;
  String _archivoLenguaje = '';
  String _archivoContenido = '';

  bool _modoEditar = false;
  bool _explicando = false;
  String? _explicacion;
  final TextEditingController _editCtrl = TextEditingController();
  bool _guardando = false;

  double _anchoExplorador = 280.0;
  double _altoExplicacion = 250.0;

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  String _padre(String ruta) {
    final partes = ruta.split(RegExp(r'[/\\]'))
      ..removeWhere((s) => s.isEmpty);
    if (partes.isEmpty) return '';
    partes.removeLast();
    return (ruta.startsWith('/') ? '/' : '') + partes.join('/');
  }

  Future<void> _cargar(String ruta) async {
    setState(() {
      _cargando = true;
      _archivoNombre = null;
      _explicacion = null;
      _modoEditar = false;
    });
    try {
      final entradas = await listarLocal(ruta);
      _items = entradas
          .map((e) => _Item(e.nombre, e.ruta, e.esCarpeta))
          .toList();
      _ruta = ruta;
    } catch (_) {
      _items = [];
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static const Set<String> _extensionesBinarias = {
    'exe', 'dll', 'so', 'dylib', 'bin', 'gguf', 'iso', 'img',
    'zip', 'tar', 'gz', 'bz2', '7z', 'rar',
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'bmp',
    'mp4', 'mkv', 'avi', 'mov', 'mp3', 'wav', 'flac',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'db', 'sqlite', 'sqlite3', 'pyc', 'class', 'o', 'obj',
  };

  Future<void> _abrirArchivo(_Item it) async {
    if (it.esCarpeta) return;

    final ext = it.nombre.contains('.') ? it.nombre.split('.').last.toLowerCase() : '';
    if (_extensionesBinarias.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${it.nombre}" es un archivo binario y no se puede abrir como texto.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _archivoNombre = null;
      _explicacion = null;
      _modoEditar = false;
    });
    try {
      final contenido = await leerLocal(it.ruta);
      if (!mounted) return;
      _editCtrl.text = contenido;
      setState(() {
        _archivoNombre = it.ruta;
        _archivoLenguaje = _detectarLenguaje(it.nombre);
        _archivoContenido = contenido;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    }
  }

  Future<void> _abrirCarpeta() async {
    final dir = await DialogosNativos.seleccionarCarpeta(titulo: 'Seleccionar carpeta de tu PC');
    if (dir == null) return;
    setState(() => _raiz = dir);
    await _cargar(dir);
  }

  Future<void> _guardar() async {
    if (_archivoNombre == null) return;
    setState(() => _guardando = true);
    final ok = await escribirLocal(_archivoNombre!, _editCtrl.text);
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) {
        _archivoContenido = _editCtrl.text;
        _modoEditar = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Guardado.' : 'No se pudo guardar.')),
    );
  }

  Future<void> _explicar() async {
    if (_archivoNombre == null || _explicando) return;
    final archivoConsultado = _archivoNombre!;
    setState(() {
      _explicando = true;
      _explicacion = null;
    });
    final settings = context.read<SettingsProvider>();
    final chat = context.read<ChatProvider>();

    // Contexto = carpeta padre (no archivo individual) — así múltiples
    // archivos de la misma carpeta se acumulan en UN solo chat en vez
    // de generar uno por archivo.
    final partes = _archivoNombre!.split(RegExp(r'[/\\]'));
    final nombreCorto = partes.last;
    final carpetaPadre = partes.length >= 2 ? partes[partes.length - 2] : 'raíz';
    final contexto = '📁 $carpetaPadre';

    final contenidoSeguro = _modoEditar ? _editCtrl.text : _archivoContenido;

    final extension = nombreCorto.contains('.')
        ? nombreCorto.split('.').last.toLowerCase()
        : '';
    final esMarkdown = extension == 'md' ||
        extension == 'txt' ||
        extension == 'rst' ||
        extension == 'log';
    final esDatos = extension == 'json' ||
        extension == 'yaml' ||
        extension == 'yml' ||
        extension == 'toml' ||
        extension == 'env' ||
        extension == 'xml';
    final esWeb = extension == 'html' ||
        extension == 'htm' ||
        extension == 'css' ||
        extension == 'svg';

    final String prompt;
    if (esMarkdown) {
      prompt = '''📄 **Documento Técnico:** $nombreCorto (`$_archivoNombre`)

Analiza y resume pedagógicamente este documento en español:
1. 🎯 **Propósito y Tema Central**: Explica en 2 o 3 oraciones claras de qué trata este documento, qué sistema documenta y cuál es su objetivo.
2. 📑 **Contenido y Secciones Clave**: Resume brevemente los conceptos, especificaciones o puntos principales explicados en el texto.
3. 💡 **Puntos de Interés**: Aspectos clave para quien consulte esta documentación.

REGLAS ABSOLUTAS:
- Responde 100% en español.
- Esto es un documento de texto/Markdown, NO es código ejecutable. NO inventes funciones, clases ni código Python que no existen.
- Sé conciso, directo y pedagógico.

CONTENIDO REAL:
```markdown
$contenidoSeguro
```''';
    } else if (esDatos) {
      prompt = '''📊 **Estructura de Datos / Configuración:** $nombreCorto (`$_archivoNombre`)

Analiza este archivo estructurado ($extension.toUpperCase()) en español:
1. 🎯 **Propósito**: Para qué sirve este archivo y qué configuración o entidad modela en el sistema.
2. 🔑 **Campos y Claves Principales**: Qué datos, propiedades o listas almacena y qué representan.
3. ⚙️ **Uso Práctico**: Cómo influyen estos valores en la aplicación.

REGLAS ABSOLUTAS:
- Responde 100% en español.
- Es un archivo de configuración/datos ($extension), NO un script con funciones. Describe el modelo de datos real.

CONTENIDO:
```$extension
$contenidoSeguro
```''';
    } else if (esWeb) {
      prompt = '''🌐 **Vista Web / Estilo:** $nombreCorto (`$_archivoNombre`)

Analiza este archivo de interfaz web en español:
1. 🎯 **Propósito**: Qué vista o diseño visual define en la aplicación.
2. 🧩 **Estructura**: Elementos, contenedores o estilos principales.
3. 🎨 **Buenas Prácticas**: Semántica y organización.

REGLAS:
- Responde 100% en español, conciso y directo.

CONTENIDO:
```$extension
$contenidoSeguro
```''';
    } else {
      prompt = '''💻 **Código Fuente:** $nombreCorto (`$_archivoNombre`)

Explica de forma directa, didáctica y clara este archivo de programación ($extension):
1. 🎯 **Propósito General**: Qué problema resuelve este código y cuál es su objetivo principal (en 2 o 3 oraciones claras).
2. 🧩 **Lógica y Componentes Clave**: Funciones o clases principales y cómo se procesan los datos.
3. 🛡️ **Puntos Críticos**: Manejo de excepciones, casos límite o sugerencias de buenas prácticas.

REGLAS:
- Responde 100% en español pedagógico, conciso y al grano.
- Explica únicamente lo que este código hace realmente.

CÓDIGO:
```$_archivoLenguaje
$contenidoSeguro
```''';
    }

    try {
      // Si ya hay conversaciones cargadas, busca una para este archivo.
      // Si no, cárgalas primero.
      if (chat.conversaciones.isEmpty) {
        await chat.cargarConversaciones();
      }
      await chat.enviarParaContexto(
        prompt,
        contexto: contexto,
        idioma: settings.idioma,
        buscarWeb: settings.buscarWeb,
        proveedor: settings.proveedor,
        modoAcompanamiento: settings.modoAcompanamiento,
        nivelModulo: settings.nivelModulo,
      );
      // Tomamos la última respuesta del asistente para mostrar en panel.
      final ultima = chat.mensajes.reversed
          .firstWhere((m) => !m.esUsuario, orElse: () => chat.mensajes.last);
      if (mounted && _archivoNombre == archivoConsultado) {
        setState(() => _explicacion = ultima.contenido);
      }
    } catch (e) {
      if (mounted && _archivoNombre == archivoConsultado) {
        setState(() => _explicacion = '### Error\n\n$e');
      }
    } finally {
      if (mounted) setState(() => _explicando = false);
    }
  }

  String _detectarLenguaje(String nombre) {
    final ext = nombre.toLowerCase().split('.').last;
    return switch (ext) {
      'py' || 'pyw' => 'python',
      'dart' => 'dart',
      'js' || 'mjs' || 'cjs' => 'javascript',
      'ts' => 'typescript',
      'jsx' => 'jsx',
      'tsx' => 'tsx',
      'json' => 'json',
      'yml' || 'yaml' => 'yaml',
      'html' || 'htm' => 'html',
      'xml' => 'xml',
      'css' || 'scss' => 'css',
      'sql' => 'sql',
      'sh' => 'bash',
      'ps1' => 'powershell',
      'md' || 'markdown' => 'markdown',
      'c' => 'c',
      'cpp' || 'cc' || 'cxx' || 'h' || 'hpp' => 'cpp',
      'java' => 'java',
      'go' => 'go',
      'rs' => 'rust',
      'kt' || 'kts' => 'kotlin',
      _ => 'text',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (!soportaDiscoLocal) {
      return Container(color: p.bg, child: _avisoWeb(p));
    }
    return Container(
      color: p.bg,
      child: Column(
        children: [
          _header(p),
          if (_raiz != null) _breadcrumb(p),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _raiz == null
                  ? _necesitaCarpeta(p)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: _anchoExplorador, child: _panelLista(p)),
                        DivisorVertical(
                          onDrag: (delta) {
                            setState(() {
                              _anchoExplorador =
                                  (_anchoExplorador + delta).clamp(180.0, 520.0);
                            });
                          },
                        ),
                        Expanded(child: _panelVisor(p)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppPalette p) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_copy_outlined, size: 18, color: p.primary),
          const SizedBox(width: 10),
          Text(
            'Explorador de mi computadora',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _abrirCarpeta,
            icon: const Icon(Icons.folder_open, size: 14),
            label: Text(_raiz == null ? 'Abrir carpeta' : 'Cambiar carpeta'),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb(AppPalette p) {
    final etiqueta = _ruta.isEmpty ? '(raíz)' : _ruta;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          if (_ruta.isNotEmpty)
            Tooltip(
              message: 'Subir un nivel',
              child: InkWell(
                onTap: () => _cargar(_padre(_ruta)),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.arrow_upward, size: 14, color: p.muted),
                ),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.muted,
                fontSize: 12,
                fontFamily: AppFonts.monoFallback.first,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoWeb(AppPalette p) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 40, color: p.subtle),
            const SizedBox(height: 10),
            Text(
              'Disco local no disponible',
              style: TextStyle(
                color: p.muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'El acceso a las carpetas de tu PC solo está disponible en la '
              'app de escritorio nativa (Windows/Linux/macOS), no en navegador.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.subtle, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _necesitaCarpeta(AppPalette p) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.folder_open, size: 28, color: p.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'Elige una carpeta de tu PC',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: p.text,
                    fontSize: 17,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Selecciona cualquier carpeta de tu computadora para empezar '
              'a navegarla, abrir archivos y pedirle al asistente que te '
              'los explique.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: p.subtle, height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _abrirCarpeta,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Elegir carpeta'),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ejemplos útiles:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p.muted,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  _ejemplo(p, '• Tu carpeta de proyectos Python'),
                  _ejemplo(p, '• Un repositorio que quieras entender'),
                  _ejemplo(p, '• Una carpeta con scripts sueltos'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ejemplo(AppPalette p, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(texto,
            style: TextStyle(fontSize: 12, color: p.subtle, height: 1.5)),
      );

  Widget _panelLista(AppPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 13, color: p.muted),
                const SizedBox(width: 6),
                Text(
                  'Archivos',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const Spacer(),
                if (_items.isNotEmpty)
                  Text(
                    '${_items.length}',
                    style: TextStyle(fontSize: 11, color: p.subtle),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: p.primary),
                    ),
                  )
                : (_items.isEmpty
                    ? Center(
                        child: Text(
                          'Carpeta vacía.',
                          style: TextStyle(color: p.subtle, fontSize: 12.5),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(6),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          final activo = it.ruta == _archivoNombre;
                          return _NodoTile(
                            item: it,
                            activo: activo,
                            onTap: () => it.esCarpeta
                                ? _cargar(it.ruta)
                                : _abrirArchivo(it),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  Widget _panelVisor(AppPalette p) {
    if (_archivoNombre == null) {
      return Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.borderSoft),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 36, color: p.subtle),
              const SizedBox(height: 8),
              Text(
                'Selecciona un archivo para ver su código.',
                style: TextStyle(color: p.subtle, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbarArchivo(p),
                Expanded(child: _vistaCodigo(p)),
              ],
            ),
          ),
        ),
        if (_explicacion != null) ...[
          const SizedBox(height: 4),
          DivisorHorizontal(
            onDrag: (delta) {
              setState(() {
                _altoExplicacion =
                    (_altoExplicacion - delta).clamp(120.0, 550.0);
              });
            },
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: _altoExplicacion,
            child: _panelExplicacion(p),
          ),
        ],
      ],
    );
  }

  Widget _toolbarArchivo(AppPalette p) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 14, color: p.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _archivoNombre!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.text,
                fontFamily: AppFonts.monoFallback.first,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
          ),
          // Badge de lenguaje
          if (_archivoLenguaje.isNotEmpty && _archivoLenguaje != 'text') ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _archivoLenguaje,
                style: TextStyle(
                  fontSize: 10.5,
                  color: p.primary,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Toggle Ver / Editar
          _ToggleVerEditar(
            modoEditar: _modoEditar,
            onChange: (v) {
              setState(() {
                _modoEditar = v;
                if (v) _editCtrl.text = _archivoContenido;
              });
            },
          ),
          const SizedBox(width: 8),
          if (_modoEditar) ...[
            OutlinedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 13),
              label: const Text('Guardar'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: _explicando ? null : _explicar,
            icon: _explicando
                ? const SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome, size: 13),
            label: const Text('Explicar'),
          ),
        ],
      ),
    );
  }

  Widget _vistaCodigo(AppPalette p) {
    final lineas = _archivoContenido.split('\n');
    return Container(
      color: p.codeBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Números de línea
          Container(
            width: 48,
            padding: const EdgeInsets.only(top: 14, right: 10),
            decoration: BoxDecoration(
              color: p.codeBg,
              border: Border(right: BorderSide(color: p.codeText.withValues(alpha: 0.1))),
            ),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < lineas.length; i++)
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: AppFonts.monoFallback.first,
                        fontFamilyFallback: AppFonts.monoFallback,
                        fontSize: 12.5,
                        height: 1.55,
                        color: p.codeText.withValues(alpha: 0.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Visor y editor nativo (totalmente a prueba de cuelgues al seleccionar texto)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: TextField(
                controller: _editCtrl,
                readOnly: !_modoEditar,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                  fontSize: 12.5,
                  height: 1.55,
                  color: p.codeText,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelExplicacion(AppPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 13, color: p.primary),
                const SizedBox(width: 8),
                Text(
                  'Explicación',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Cerrar explicación',
                  child: InkWell(
                    onTap: () => setState(() => _explicacion = null),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 15, color: p.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: MarkdownBody(
                data: _explicacion!,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: p.text, fontSize: 13, height: 1.55),
                  code: TextStyle(
                    backgroundColor: p.surface2,
                    fontFamily: AppFonts.monoFallback.first,
                    fontFamilyFallback: AppFonts.monoFallback,
                    fontSize: 12.5,
                    color: p.text,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: p.codeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodoTile extends StatefulWidget {
  final _Item item;
  final bool activo;
  final VoidCallback onTap;
  const _NodoTile({
    required this.item,
    required this.activo,
    required this.onTap,
  });

  @override
  State<_NodoTile> createState() => _NodoTileState();
}

class _NodoTileState extends State<_NodoTile> {
  bool _hover = false;

  IconData _iconoArchivo(String nombre) {
    final ext = nombre.toLowerCase().split('.').last;
    return switch (ext) {
      'py' || 'pyw' => Icons.bolt,
      'dart' => Icons.flutter_dash,
      'js' || 'mjs' || 'ts' || 'jsx' || 'tsx' => Icons.javascript,
      'html' => Icons.html,
      'css' => Icons.css,
      'json' || 'yml' || 'yaml' => Icons.data_object,
      'md' => Icons.article_outlined,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => Icons.image_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      _ => Icons.description_outlined,
    };
  }

  Color _colorArchivo(String nombre, AppPalette p) {
    final ext = nombre.toLowerCase().split('.').last;
    return switch (ext) {
      'py' || 'pyw' => const Color(0xFF7DAEF0),
      'dart' => const Color(0xFF55C7F2),
      'js' || 'mjs' => const Color(0xFFE8C87C),
      'ts' || 'tsx' || 'jsx' => const Color(0xFF7DAEF0),
      'html' => const Color(0xFFE07B5C),
      'css' => const Color(0xFF7DAEF0),
      'json' || 'yml' || 'yaml' => const Color(0xFFC8B47D),
      'md' => p.muted,
      _ => p.muted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final it = widget.item;
    final bg = widget.activo
        ? p.surface2
        : (_hover ? p.surface2.withValues(alpha: 0.55) : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                it.esCarpeta ? Icons.folder_rounded : _iconoArchivo(it.nombre),
                size: 14,
                color: it.esCarpeta ? p.primary : _colorArchivo(it.nombre, p),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  it.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.activo ? p.text : p.muted,
                    fontWeight:
                        widget.activo ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleVerEditar extends StatelessWidget {
  final bool modoEditar;
  final ValueChanged<bool> onChange;
  const _ToggleVerEditar({required this.modoEditar, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget btn(bool valor, IconData icono, String label, String tooltip) {
      final activo = modoEditar == valor;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => onChange(valor),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: activo ? p.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(icono,
                    size: 12, color: activo ? p.primary : p.subtle),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: activo ? p.text : p.subtle,
                    fontWeight:
                        activo ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.borderSoft),
      ),
      child: Row(children: [
        btn(false, Icons.visibility_outlined, 'Ver',
            'Vista con resaltado de sintaxis (solo lectura)'),
        btn(true, Icons.edit_outlined, 'Editar',
            'Modo edición (texto plano, permite guardar)'),
      ]),
    );
  }
}
