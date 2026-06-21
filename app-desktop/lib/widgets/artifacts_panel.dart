import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../services/fs_local.dart';
import '../theme.dart';

/// Un "artifact" es un bloque de código (o texto) extraído de una respuesta
/// del asistente. Inspirado en los Artifacts de Claude.ai.
class Artifact {
  final String id;
  final String titulo;
  final String lenguaje; // python, dart, js, …
  final String contenido;
  final DateTime creadoEn;

  Artifact({
    required this.id,
    required this.titulo,
    required this.lenguaje,
    required this.contenido,
    required this.creadoEn,
  });

  String get extension {
    return switch (lenguaje.toLowerCase()) {
      'python' || 'py' => 'py',
      'dart' => 'dart',
      'javascript' || 'js' => 'js',
      'typescript' || 'ts' => 'ts',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'bash' || 'sh' || 'shell' => 'sh',
      'html' => 'html',
      'css' => 'css',
      'sql' => 'sql',
      _ => 'txt',
    };
  }

  String get etiquetaLenguaje {
    final l = lenguaje.toLowerCase();
    return switch (l) {
      '' => 'texto',
      'py' => 'python',
      _ => l,
    };
  }
}

/// Estado del panel de artifacts.
class ArtifactsProvider extends ChangeNotifier {
  final List<Artifact> _artifacts = [];
  int _seleccionado = -1;
  bool _abierto = false;

  List<Artifact> get artifacts => List.unmodifiable(_artifacts);
  int get seleccionado => _seleccionado;
  bool get abierto => _abierto;
  Artifact? get actual =>
      _seleccionado >= 0 && _seleccionado < _artifacts.length
          ? _artifacts[_seleccionado]
          : null;

  static final RegExp _regexCodigo =
      RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);

  /// Extrae todos los bloques de código de un texto markdown.
  /// Devuelve los artifacts creados (puede estar vacío).
  List<Artifact> extraerDesde(String contenido,
      {String tituloBase = 'Artifact'}) {
    final nuevos = <Artifact>[];
    final ahora = DateTime.now();
    var i = 0;
    for (final m in _regexCodigo.allMatches(contenido)) {
      i++;
      final lang = (m.group(1) ?? '').trim();
      final code = (m.group(2) ?? '').trim();
      if (code.isEmpty) continue;
      nuevos.add(Artifact(
        id: '${ahora.microsecondsSinceEpoch}-$i',
        titulo:
            i == 1 ? tituloBase : '$tituloBase ${i.toString().padLeft(2, '0')}',
        lenguaje: lang.isEmpty ? 'python' : lang,
        contenido: code,
        creadoEn: ahora,
      ));
    }
    return nuevos;
  }

  /// Cuenta cuántos bloques de código hay en un texto.
  int contarBloques(String contenido) =>
      _regexCodigo.allMatches(contenido).length;

  /// Abre el panel con un artifact recién creado a partir del primer bloque.
  void abrirDesdeMensaje(String contenido, {String tituloBase = 'Código'}) {
    final extraidos = extraerDesde(contenido, tituloBase: tituloBase);
    if (extraidos.isEmpty) return;
    for (final a in extraidos) {
      _artifacts.add(a);
    }
    _seleccionado = _artifacts.length - extraidos.length;
    _abierto = true;
    notifyListeners();
  }

  void seleccionar(int idx) {
    if (idx < 0 || idx >= _artifacts.length) return;
    _seleccionado = idx;
    _abierto = true;
    notifyListeners();
  }

  void cerrar() {
    _abierto = false;
    notifyListeners();
  }

  void eliminar(int idx) {
    if (idx < 0 || idx >= _artifacts.length) return;
    _artifacts.removeAt(idx);
    if (_artifacts.isEmpty) {
      _seleccionado = -1;
      _abierto = false;
    } else {
      _seleccionado = _seleccionado.clamp(0, _artifacts.length - 1);
    }
    notifyListeners();
  }

  void limpiar() {
    _artifacts.clear();
    _seleccionado = -1;
    _abierto = false;
    notifyListeners();
  }
}

// ─────────────────────────── Widget del panel ───────────────────────────

class ArtifactsPanel extends StatelessWidget {
  final ArtifactsProvider provider;
  const ArtifactsPanel({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final actual = provider.actual;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(left: BorderSide(color: p.borderSoft)),
      ),
      child: Column(
        children: [
          _Cabecera(provider: provider, actual: actual),
          if (provider.artifacts.length > 1)
            _BarraTabs(provider: provider),
          Expanded(
            child: actual == null
                ? _VacioPanel()
                : _CodigoVisor(artifact: actual),
          ),
          if (actual != null) _BarraAcciones(artifact: actual),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final ArtifactsProvider provider;
  final Artifact? actual;
  const _Cabecera({required this.provider, required this.actual});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize_outlined, size: 16, color: p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              actual?.titulo ?? 'Artifacts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ),
          if (actual != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.borderSoft),
              ),
              child: Text(
                actual!.etiquetaLenguaje,
                style: TextStyle(
                  fontSize: 11,
                  color: p.muted,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Cerrar panel',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: provider.cerrar,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close, size: 16, color: p.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraTabs extends StatelessWidget {
  final ArtifactsProvider provider;
  const _BarraTabs({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: provider.artifacts.length,
        itemBuilder: (context, i) {
          final a = provider.artifacts[i];
          final activa = i == provider.seleccionado;
          return InkWell(
            onTap: () => provider.seleccionar(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                color: activa ? p.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.code, size: 12, color: activa ? p.primary : p.subtle),
                  const SizedBox(width: 6),
                  Text(
                    a.titulo,
                    style: TextStyle(
                      fontSize: 12,
                      color: activa ? p.text : p.muted,
                      fontWeight: activa ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => provider.eliminar(i),
                    child: Icon(Icons.close, size: 12, color: p.subtle),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VacioPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code_off, size: 40, color: p.subtle),
            const SizedBox(height: 10),
            Text(
              'Sin artifacts aún',
              style: TextStyle(
                color: p.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cuando el asistente genere código, podrás abrirlo aquí para verlo cómodamente, copiarlo o guardarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.subtle, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodigoVisor extends StatelessWidget {
  final Artifact artifact;
  const _CodigoVisor({required this.artifact});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final lineas = artifact.contenido.split('\n');
    return Container(
      color: p.codeBg,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Números de línea.
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 6, top: 2),
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
              Container(
                width: 1,
                margin: const EdgeInsets.only(top: 2),
                color: p.codeText.withValues(alpha: 0.1),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: SelectableText(
                      artifact.contenido,
                      style: TextStyle(
                        fontFamily: AppFonts.monoFallback.first,
                        fontFamilyFallback: AppFonts.monoFallback,
                        fontSize: 13,
                        height: 1.55,
                        color: p.codeText,
                      ),
                    ),
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

class _BarraAcciones extends StatelessWidget {
  final Artifact artifact;
  const _BarraAcciones({required this.artifact});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          _BotonAccion(
            icon: Icons.content_copy,
            label: 'Copiar',
            onTap: () async {
              await Clipboard.setData(
                  ClipboardData(text: artifact.contenido));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Código copiado'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          _BotonAccion(
            icon: Icons.save_alt,
            label: 'Guardar como…',
            onTap: () => _guardar(context),
          ),
          const Spacer(),
          Text(
            '${artifact.contenido.split('\n').length} líneas',
            style: TextStyle(fontSize: 11, color: p.subtle),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar(BuildContext context) async {
    final nombreSugerido = _nombreArchivo(artifact);
    try {
      if (kIsWeb || !soportaDiscoLocal) {
        // En web, ofrecemos un picker que descargue los bytes.
        await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar artifact',
          fileName: nombreSugerido,
          bytes: Uint8List.fromList(utf8.encode(artifact.contenido)),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Descargando $nombreSugerido…')),
        );
        return;
      }
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar artifact',
        fileName: nombreSugerido,
      );
      if (ruta == null) return;
      final ok = await escribirLocal(ruta, artifact.contenido);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Guardado en $ruta' : 'No se pudo guardar.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  String _nombreArchivo(Artifact a) {
    final base = a.titulo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final nombre = base.isEmpty ? 'artifact' : base;
    return '$nombre.${a.extension}';
  }
}

class _BotonAccion extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BotonAccion({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_BotonAccion> createState() => _BotonAccionState();
}

class _BotonAccionState extends State<_BotonAccion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? p.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: p.muted),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: p.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
