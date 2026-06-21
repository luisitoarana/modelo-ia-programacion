import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../providers.dart';
import '../services/tts_service.dart';
import '../theme.dart';

/// Vista de explicación de código — layout estilo IDE:
///   ┌──────────────────────────────────────────────────────────┐
///   │ Header: "Explicar código"  · selector nivel · acciones   │
///   ├───────────── tabs de archivos abiertos ──────────────────┤
///   │ [editor de código]              │ [explicación markdown] │
///   └──────────────────────────────────────────────────────────┘
class ExplicarView extends StatefulWidget {
  const ExplicarView({super.key});

  @override
  State<ExplicarView> createState() => _ExplicarViewState();
}

class _ExplicarViewState extends State<ExplicarView> {
  final _codigoCtrl = TextEditingController();
  String _explicacion = '';
  bool _cargando = false;
  bool _leyendo = false;
  String _nivel = 'basico';
  String _profundidad = 'completa'; // rapida | completa | maestra
  String? _nombreArchivo;
  final List<MapEntry<String, String>> _archivos = []; // nombre -> contenido

  @override
  void dispose() {
    _codigoCtrl.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  Future<void> _alternarLectura() async {
    if (_leyendo) {
      await TtsService.instance.stop();
      if (mounted) setState(() => _leyendo = false);
      return;
    }
    final settings = context.read<SettingsProvider>();
    if (mounted) setState(() => _leyendo = true);
    await TtsService.instance.speak(
      _explicacion,
      velocidad: settings.ttsVelocidad,
      voz: settings.ttsVoz,
      idioma: settings.idioma.startsWith('es') ? 'es-ES' : 'en-US',
    );
    // No tenemos callback de fin del speak — el usuario detiene manualmente.
  }

  Future<void> _abrirArchivos() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );
      if (res == null || res.files.isEmpty) return;
      final nuevos = <MapEntry<String, String>>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        nuevos.add(MapEntry(f.name, utf8.decode(bytes, allowMalformed: true)));
      }
      if (nuevos.isEmpty) return;
      setState(() {
        _archivos
          ..clear()
          ..addAll(nuevos);
        _cargarArchivo(nuevos.first);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    }
  }

  void _cargarArchivo(MapEntry<String, String> a) {
    setState(() {
      _codigoCtrl.text = a.value;
      _nombreArchivo = a.key;
    });
  }

  void _cerrarArchivo(String nombre) {
    setState(() {
      _archivos.removeWhere((e) => e.key == nombre);
      if (_nombreArchivo == nombre) {
        if (_archivos.isNotEmpty) {
          _cargarArchivo(_archivos.first);
        } else {
          _nombreArchivo = null;
          _codigoCtrl.clear();
        }
      }
    });
  }

  String _construirPrompt(String codigo) {
    final etiquetaArchivo =
        _nombreArchivo != null ? ' (archivo: $_nombreArchivo)' : '';

    final secciones = switch (_profundidad) {
      'rapida' => '''
1. ## Qué hace (2-3 oraciones)
2. ## Conceptos clave (lista con definiciones cortas)
3. ## Ejecuta esto si quieres ver — pequeño ejemplo de uso
''',
      'maestra' => '''
1. ## Qué hace (visión general en lenguaje claro)
2. ## Por qué se hizo así (motivación de cada decisión técnica)
3. ## Estructura general (cómo se organiza el código y por qué)
4. ## Frameworks y librerías usadas (cada una, qué resuelve y por qué se eligió)
5. ## Cómo se conectan los archivos / módulos (si aplica)
6. ## Línea por línea de las partes no triviales (con comentarios pedagógicos)
7. ## Conceptos clave usados (con definición + ejemplo mínimo)
8. ## Decisiones de arquitectura y trade-offs (por qué esto y no otra cosa)
9. ## Alternativas (al menos una forma distinta de resolver lo mismo)
10. ## Errores comunes y cómo evitarlos
11. ## Para profundizar — 2 ejercicios o preguntas abiertas que reten al estudiante
''',
      _ => '''
1. ## Qué hace (resumen claro)
2. ## Por qué se hizo así (las decisiones importantes)
3. ## Línea por línea (las partes relevantes, no triviales)
4. ## Conceptos clave usados (con definición breve)
5. ## Alternativas y trade-offs (al menos una)
6. ## Para profundizar (1-2 preguntas o mini-ejercicios)
''',
    };

    return '''Eres mi profesor de programación. Explícame el siguiente código$etiquetaArchivo para un estudiante de nivel $_nivel.

Usa esta estructura exacta (en orden, con encabezados markdown ##):

$secciones

Reglas:
- Sé concreto. Cita literalmente partes del código que estás explicando, entre backticks.
- No inventes funciones que no existen en el código.
- Si hay algo que no se entiende del código por falta de contexto, dilo explícitamente.
- Adapta el vocabulario al nivel $_nivel.

CÓDIGO A EXPLICAR:
```
$codigo
```''';
  }

  Future<void> _explicar() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) return;
    setState(() {
      _cargando = true;
      _explicacion = '';
    });
    final chat = context.read<ChatProvider>();
    final settings = context.read<SettingsProvider>();

    // Si el nombre de archivo viene con ruta (p. ej. "src/utils.py"),
    // agrupamos el chat por la carpeta padre — así múltiples archivos
    // de la misma carpeta se acumulan en un solo chat.
    // Snippets pegados sin ruta van todos al chat "📝 Código pegado".
    String contexto;
    if (_nombreArchivo == null) {
      contexto = '📝 Código pegado';
    } else {
      final partes = _nombreArchivo!.split(RegExp(r'[/\\]'));
      if (partes.length >= 2) {
        contexto = '📁 ${partes[partes.length - 2]}';
      } else {
        // Archivo suelto sin carpeta — usamos su nombre.
        contexto = '📄 ${partes.last}';
      }
    }

    try {
      if (chat.conversaciones.isEmpty) {
        await chat.cargarConversaciones();
      }
      await chat.enviarParaContexto(
        _construirPrompt(codigo),
        contexto: contexto,
        idioma: settings.idioma,
        buscarWeb: settings.buscarWeb,
      );
      final ultima = chat.mensajes.reversed
          .firstWhere((m) => !m.esUsuario, orElse: () => chat.mensajes.last);
      setState(() => _explicacion = ultima.contenido);
    } on ApiException catch (e) {
      setState(() => _explicacion =
          '### Error\n\n${e.mensaje}\n\n${e.detalle ?? ""}');
    } catch (e) {
      setState(() => _explicacion = '### Error inesperado\n\n$e');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      color: p.bg,
      child: Column(
        children: [
          _header(p),
          if (_archivos.isNotEmpty) _tabsArchivos(p),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _panel(
                      p,
                      titulo: _nombreArchivo != null
                          ? _nombreArchivo!
                          : 'Pega tu código',
                      icono: Icons.code,
                      child: TextField(
                        controller: _codigoCtrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          fontFamily: AppFonts.monoFallback.first,
                          fontFamilyFallback: AppFonts.monoFallback,
                          fontSize: 12.5,
                          height: 1.6,
                          color: p.text,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Pega aquí tu código Python…',
                          hintStyle: TextStyle(
                            color: p.subtle,
                            fontFamily: AppFonts.monoFallback.first,
                            fontFamilyFallback: AppFonts.monoFallback,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _panel(
                      p,
                      titulo: 'Explicación',
                      icono: Icons.auto_awesome,
                      accion: _explicacion.isEmpty
                          ? null
                          : Tooltip(
                              message: _leyendo
                                  ? 'Detener lectura'
                                  : 'Leer en voz alta',
                              child: InkWell(
                                onTap: _alternarLectura,
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _leyendo
                                            ? Icons.stop
                                            : Icons.volume_up,
                                        size: 13,
                                        color: _leyendo
                                            ? p.primary
                                            : p.muted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _leyendo ? 'Detener' : 'Leer',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: _leyendo
                                              ? p.primary
                                              : p.muted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      child: _explicacion.isEmpty
                          ? _EstadoVacioExplicacion(cargando: _cargando)
                          : TweenAnimationBuilder<double>(
                              key: ValueKey(_explicacion),
                              duration: const Duration(milliseconds: 320),
                              tween: Tween(begin: 0.0, end: 1.0),
                              curve: Curves.easeOut,
                              builder: (_, t, child) => Opacity(
                                opacity: t,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - t) * 8),
                                  child: child,
                                ),
                              ),
                              child: SingleChildScrollView(
                                child: MarkdownBody(
                                  data: _explicacion,
                                  selectable: true,
                                  styleSheet: _markdownStyle(context, p),
                                ),
                              ),
                            ),
                    ),
                  ),
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
          Icon(Icons.code, size: 18, color: p.primary),
          const SizedBox(width: 10),
          Text(
            'Explicar código',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(width: 16),
          _selectorNivel(p),
          const SizedBox(width: 8),
          _selectorProfundidad(p),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _abrirArchivos,
            icon: const Icon(Icons.folder_open, size: 15),
            label: const Text('Abrir archivos'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _cargando ? null : _explicar,
            icon: _cargando
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome, size: 15),
            label: const Text('Explicar'),
          ),
        ],
      ),
    );
  }

  Widget _tabsArchivos(AppPalette p) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: _archivos.length,
        itemBuilder: (context, i) {
          final a = _archivos[i];
          final activo = a.key == _nombreArchivo;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            decoration: BoxDecoration(
              color: activo ? p.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: activo ? p.border : Colors.transparent,
              ),
            ),
            child: InkWell(
              onTap: () => _cargarArchivo(a),
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 12, color: activo ? p.primary : p.subtle),
                    const SizedBox(width: 6),
                    Text(
                      a.key,
                      style: TextStyle(
                          fontSize: 12,
                          color: activo ? p.text : p.muted,
                          fontWeight:
                              activo ? FontWeight.w500 : FontWeight.w400),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _cerrarArchivo(a.key),
                      child: Icon(Icons.close, size: 12, color: p.subtle),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectorNivel(AppPalette p) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.borderSoft),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _nivel,
          dropdownColor: p.surface,
          style: TextStyle(color: p.text, fontSize: 12.5),
          icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
          items: const [
            DropdownMenuItem(value: 'basico', child: Text('Básico')),
            DropdownMenuItem(value: 'intermedio', child: Text('Intermedio')),
            DropdownMenuItem(value: 'avanzado', child: Text('Avanzado')),
          ],
          onChanged: (v) => setState(() => _nivel = v ?? 'basico'),
        ),
      ),
    );
  }

  Widget _selectorProfundidad(AppPalette p) {
    return Tooltip(
      message: 'Cuánta profundidad pedimos a la explicación.',
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.borderSoft),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _profundidad,
            dropdownColor: p.surface,
            style: TextStyle(color: p.text, fontSize: 12.5),
            icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
            items: const [
              DropdownMenuItem(
                  value: 'rapida',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt, size: 13),
                    SizedBox(width: 6),
                    Text('Rápida'),
                  ])),
              DropdownMenuItem(
                  value: 'completa',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.menu_book, size: 13),
                    SizedBox(width: 6),
                    Text('Completa'),
                  ])),
              DropdownMenuItem(
                  value: 'maestra',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.school, size: 13),
                    SizedBox(width: 6),
                    Text('Maestra'),
                  ])),
            ],
            onChanged: (v) => setState(() => _profundidad = v ?? 'completa'),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    AppPalette p, {
    required String titulo,
    required IconData icono,
    required Widget child,
    Widget? accion,
  }) {
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
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(icono, size: 14, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: p.text,
                    ),
                  ),
                ),
                if (accion != null) accion,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context, AppPalette p) {
    final base = Theme.of(context).textTheme;
    return MarkdownStyleSheet(
      p: base.bodyMedium?.copyWith(color: p.text, height: 1.6),
      strong: TextStyle(color: p.text, fontWeight: FontWeight.w600),
      code: TextStyle(
        backgroundColor: p.surface2,
        fontFamily: AppFonts.monoFallback.first,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: 13,
        color: p.text,
      ),
      codeblockDecoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      codeblockPadding: const EdgeInsets.all(14),
    );
  }
}

/// Estado vacío del panel de Explicación — pulse animation cuando carga,
/// estado inactivo bonito cuando no hay nada todavía.
class _EstadoVacioExplicacion extends StatefulWidget {
  final bool cargando;
  const _EstadoVacioExplicacion({required this.cargando});

  @override
  State<_EstadoVacioExplicacion> createState() => _EstadoVacioExplicacionState();
}

class _EstadoVacioExplicacionState extends State<_EstadoVacioExplicacion>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.cargando) ...[
            // Halo pulsante mientras carga.
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.primary.withValues(alpha: 0.06 + 0.10 * _ctrl.value),
                ),
                child: Center(
                  child: Container(
                    height: 28 + 4 * _ctrl.value,
                    width: 28 + 4 * _ctrl.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.primary.withValues(alpha: 0.20 + 0.20 * _ctrl.value),
                    ),
                    child: Icon(Icons.auto_awesome,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Generando explicación…',
              style: TextStyle(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'El profesor está pensando paso a paso',
              style: TextStyle(color: p.subtle, fontSize: 11.5),
            ),
          ] else ...[
            Icon(Icons.auto_awesome_outlined, size: 36, color: p.subtle),
            const SizedBox(height: 8),
            Text(
              'La explicación aparecerá aquí',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Text(
              'Pega código y dale "Explicar"',
              style: TextStyle(color: p.subtle, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}
