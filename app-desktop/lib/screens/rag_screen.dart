import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// Pantalla "Base de conocimiento" (RAG) — diseño Anthropic / Linear.
///
/// Layout:
///   - Hero header con título serif, descripción larga y métricas inline.
///   - Drop zone grande con ilustración de glifos + estado dragOver
///     que la ilumina con halo terracota.
///   - "Documentos indexados" como tabla densa con hover por fila.
///   - Empty state ilustrado, no genérico.
class RagScreen extends StatefulWidget {
  const RagScreen({super.key});

  @override
  State<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends State<RagScreen> {
  EstadoRag? _estado;
  List<DocumentoRag> _documentos = const [];
  bool _cargando = true;
  bool _subiendo = false;
  String? _error;

  // Filtrado en vivo de la lista.
  final TextEditingController _filtroCtrl = TextEditingController();
  String _filtro = '';

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _recargar();
    _filtroCtrl.addListener(() {
      setState(() => _filtro = _filtroCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  // ─── data ──────────────────────────────────────────────────────

  Future<void> _recargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final e = await _api.estadoRag();
      final d = await _api.listarDocumentosRag();
      if (!mounted) return;
      setState(() {
        _estado = e;
        _documentos = d;
        _cargando = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.mensaje; _cargando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _cargando = false; });
    }
  }

  Future<void> _seleccionarYSubir() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'txt', 'md', 'py', 'json', 'yml', 'yaml',
        'rst', 'js', 'ts', 'tsx', 'html', 'css',
      ],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    setState(() { _subiendo = true; _error = null; });
    try {
      for (final f in res.files) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;
        if (bytes.length > 5_000_000) {
          throw Exception('${f.name} supera 5 MB.');
        }
        await _api.subirArchivoRag(nombreArchivo: f.name, bytes: bytes);
      }
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _pegarTexto() async {
    final tituloCtrl = TextEditingController();
    final contenidoCtrl = TextEditingController();
    final p = AppPalette.of(context);

    final res = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Añadir documento',
                  style: TextStyle(
                    fontFamily: AppFonts.serifFallback.first,
                    fontSize: 20, fontWeight: FontWeight.w600, color: p.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pega cualquier texto plano. Se troceará automáticamente y quedará indexado para que el chat lo cite.',
                  style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.45),
                ),
                const SizedBox(height: AppSpacing.x5),
                _LabeledField(
                  label: 'Título',
                  child: TextField(
                    controller: tituloCtrl,
                    autofocus: true,
                    decoration: _inputDecoration(p, 'Ej: notas-clase-arboles.md'),
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                _LabeledField(
                  label: 'Contenido',
                  child: TextField(
                    controller: contenidoCtrl,
                    minLines: 7, maxLines: 12,
                    decoration: _inputDecoration(p, 'Pega aquí el contenido...'),
                  ),
                ),
                const SizedBox(height: AppSpacing.x5),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancelar', style: TextStyle(color: p.muted)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.bolt_rounded, size: 15),
                      label: const Text('Indexar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x4, vertical: AppSpacing.x3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (res != true) return;
    final titulo = tituloCtrl.text.trim();
    final contenido = contenidoCtrl.text.trim();
    if (titulo.isEmpty || contenido.isEmpty) return;

    setState(() { _subiendo = true; _error = null; });
    try {
      await _api.subirTextoRag(titulo: titulo, texto: contenido, fuente: 'pegado');
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _eliminar(DocumentoRag d) async {
    final p = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        title: Text('Eliminar documento',
            style: TextStyle(fontFamily: AppFonts.serifFallback.first)),
        content: Text(
          'Vas a eliminar "${d.titulo}". El chat dejará de citarlo. '
          'Esta acción no se puede deshacer.',
          style: TextStyle(color: p.muted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 14),
            label: const Text('Eliminar'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.eliminarDocumentoRag(d.id);
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  InputDecoration _inputDecoration(AppPalette p, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.subtle, fontSize: 13),
      filled: true,
      fillColor: p.surface2.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3, vertical: AppSpacing.x3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.borderSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.primary, width: 1.5),
      ),
    );
  }

  // ─── filtrado ──────────────────────────────────────────────────

  List<DocumentoRag> get _documentosFiltrados {
    if (_filtro.isEmpty) return _documentos;
    return _documentos
        .where((d) =>
            d.titulo.toLowerCase().contains(_filtro) ||
            d.fuente.toLowerCase().contains(_filtro))
        .toList();
  }

  // ─── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x6, AppSpacing.x8,
                AppSpacing.x6, AppSpacing.x10,
              ),
              children: [
                _hero(p),
                const SizedBox(height: AppSpacing.x6),
                _metricasRow(p),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  _bannerError(p),
                ],
                const SizedBox(height: AppSpacing.x6),
                _DropZone(
                  subiendo: _subiendo,
                  onPickFiles: _seleccionarYSubir,
                  onPasteText: _pegarTexto,
                  onFilesDropped: (files) async {
                    // Si en el futuro habilitamos drag-and-drop nativo,
                    // recibirá los archivos por aquí.
                    setState(() { _subiendo = true; _error = null; });
                    try {
                      for (final f in files) {
                        final bytes = await File(f).readAsBytes();
                        if (bytes.length > 5_000_000) continue;
                        final nombre = f.split(Platform.pathSeparator).last;
                        await _api.subirArchivoRag(
                          nombreArchivo: nombre, bytes: bytes,
                        );
                      }
                      await _recargar();
                    } catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    } finally {
                      if (mounted) setState(() => _subiendo = false);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.x6),
                _tablaDocumentos(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── pieces ────────────────────────────────────────────────────

  Widget _hero(AppPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.menu_book_rounded, size: 24, color: p.primary),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Base de conocimiento',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Los documentos que subas aquí son los que el asistente puede '
                'citar literalmente. Sin alucinaciones — si la respuesta no está '
                'en tus fuentes, te lo dirá.',
                style: TextStyle(
                  fontSize: 14,
                  color: p.muted,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricasRow(AppPalette p) {
    final e = _estado;
    final estaBien = e != null && e.disponible;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x5,
        vertical: AppSpacing.x4,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.borderSoft),
      ),
      child: Row(
        children: [
          _statusDot(estaBien),
          const SizedBox(width: AppSpacing.x3),
          Text(
            _cargando
                ? 'Verificando índice…'
                : estaBien
                    ? 'Índice activo'
                    : 'Índice no disponible',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          if (estaBien) ...[
            const SizedBox(width: AppSpacing.x4),
            _miniSep(p),
            const SizedBox(width: AppSpacing.x4),
            _statNumero(p, e.nDocumentos, 'documentos'),
            const SizedBox(width: AppSpacing.x5),
            _statNumero(p, e.nChunks, 'chunks'),
            const SizedBox(width: AppSpacing.x5),
            _statTexto(p,
                e.backend == 'sentence-transformers' ? 'SBERT' : e.backend,
                '${e.dim}d embeddings'),
          ],
          const Spacer(),
          if (!_cargando)
            IconButton(
              tooltip: 'Recargar',
              icon: Icon(Icons.refresh_rounded, size: 16, color: p.muted),
              onPressed: _recargar,
              splashRadius: 18,
            ),
        ],
      ),
    );
  }

  Widget _statusDot(bool ok) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6, spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _miniSep(AppPalette p) => Container(
        width: 1, height: 18, color: p.borderSoft,
      );

  Widget _statNumero(AppPalette p, int valor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          valor.toString(),
          style: TextStyle(
            fontFamily: AppFonts.serifFallback.first,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: p.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );
  }

  Widget _statTexto(AppPalette p, String valor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            valor,
            style: TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: p.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );
  }

  Widget _bannerError(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4, vertical: AppSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(_error!,
                style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
          ),
          IconButton(
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close, size: 14),
            color: AppColors.danger,
            splashRadius: 14,
          ),
        ],
      ),
    );
  }

  Widget _tablaDocumentos(AppPalette p) {
    final filtrados = _documentosFiltrados;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x5, AppSpacing.x4,
              AppSpacing.x5, AppSpacing.x3,
            ),
            child: Row(
              children: [
                Text(
                  'Documentos',
                  style: TextStyle(
                    fontFamily: AppFonts.serifFallback.first,
                    fontSize: 17, fontWeight: FontWeight.w600, color: p.text,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_documentos.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: p.muted,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                if (_documentos.isNotEmpty)
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _filtroCtrl,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: 'Filtrar…',
                        hintStyle: TextStyle(fontSize: 12.5, color: p.subtle),
                        prefixIcon: Icon(Icons.search_rounded, size: 14, color: p.muted),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: p.surface2.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: p.borderSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: p.borderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: p.primary, width: 1.2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: p.borderSoft),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else if (_documentos.isEmpty)
            _emptyState(p)
          else if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.x10),
              child: Center(
                child: Text(
                  'Ningún documento coincide con "$_filtro".',
                  style: TextStyle(fontSize: 13, color: p.muted),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < filtrados.length; i++)
                  _RowDocumento(
                    doc: filtrados[i],
                    esUltimo: i == filtrados.length - 1,
                    onEliminar: () => _eliminar(filtrados[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _emptyState(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.menu_book_rounded,
                      size: 22, color: p.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            Text(
              'Aún no hay nada indexado',
              style: TextStyle(
                fontFamily: AppFonts.serifFallback.first,
                fontSize: 16, fontWeight: FontWeight.w600, color: p.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sube tus notas, capítulos de libro o código fuente.\n'
              'Cuando preguntes algo, el chat lo citará palabra por palabra.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Sub-widgets
// ════════════════════════════════════════════════════════════════════

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: p.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DropZone extends StatefulWidget {
  final bool subiendo;
  final VoidCallback onPickFiles;
  final VoidCallback onPasteText;
  final void Function(List<String> paths)? onFilesDropped;

  const _DropZone({
    required this.subiendo,
    required this.onPickFiles,
    required this.onPasteText,
    this.onFilesDropped,
  });

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.subiendo ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.subiendo ? null : widget.onPickFiles,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 30),
          decoration: BoxDecoration(
            color: _hover
                ? p.primary.withValues(alpha: 0.04)
                : p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover ? p.primary.withValues(alpha: 0.5) : p.borderSoft,
              width: 1.5,
              style: BorderStyle.solid,
            ),
            boxShadow: _hover ? p.insetGlow : null,
          ),
          child: Column(
            children: [
              // Ilustración de glifos apilados
              SizedBox(
                width: 64, height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _GlyphPage(
                      color: p.borderSoft, dx: -10, dy: 6, rotZ: -0.08,
                    ),
                    _GlyphPage(
                      color: p.border, dx: 10, dy: 4, rotZ: 0.06,
                    ),
                    _GlyphPage(
                      color: _hover
                          ? p.primary.withValues(alpha: 0.7)
                          : p.muted,
                      dx: 0, dy: -4, rotZ: 0,
                      destacado: true,
                      icon: widget.subiendo
                          ? Icons.hourglass_top_rounded
                          : Icons.add_rounded,
                      iconColor: _hover ? p.primary : p.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(
                widget.subiendo
                    ? 'Indexando...'
                    : 'Arrastra o haz click para subir',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hasta 5 MB · .md  .txt  .py  .json  .yml  .rst  .html  .css',
                style: TextStyle(
                  fontSize: 11.5,
                  color: p.muted,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: widget.subiendo ? null : widget.onPickFiles,
                    icon: const Icon(Icons.upload_file_rounded, size: 14),
                    label: const Text('Elegir archivos'),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4, vertical: 10,
                      ),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  OutlinedButton.icon(
                    onPressed: widget.subiendo ? null : widget.onPasteText,
                    icon: const Icon(Icons.text_snippet_outlined, size: 14),
                    label: const Text('Pegar texto'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.borderSoft),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4, vertical: 10,
                      ),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphPage extends StatelessWidget {
  final Color color;
  final double dx, dy, rotZ;
  final bool destacado;
  final IconData? icon;
  final Color? iconColor;
  const _GlyphPage({
    required this.color,
    this.dx = 0, this.dy = 0, this.rotZ = 0,
    this.destacado = false,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rotZ,
        child: Container(
          width: destacado ? 36 : 32,
          height: destacado ? 44 : 38,
          decoration: BoxDecoration(
            color: destacado ? p.surface : p.surface2.withValues(alpha: 0.7),
            border: Border.all(color: color, width: destacado ? 1.6 : 1),
            borderRadius: BorderRadius.circular(5),
            boxShadow: destacado ? p.subtleShadow : null,
          ),
          child: icon != null
              ? Icon(icon, size: 14, color: iconColor ?? p.muted)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5,
                      ),
                      height: 2, width: double.infinity,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  }),
                ),
        ),
      ),
    );
  }
}

class _RowDocumento extends StatefulWidget {
  final DocumentoRag doc;
  final bool esUltimo;
  final VoidCallback onEliminar;

  const _RowDocumento({
    required this.doc,
    required this.esUltimo,
    required this.onEliminar,
  });

  @override
  State<_RowDocumento> createState() => _RowDocumentoState();
}

class _RowDocumentoState extends State<_RowDocumento> {
  bool _hover = false;

  IconData _icono() {
    final t = widget.doc.titulo.toLowerCase();
    if (t.endsWith('.json') || t.endsWith('.yml') || t.endsWith('.yaml')) {
      return Icons.data_object_rounded;
    }
    if (t.endsWith('.py')) return Icons.code_rounded;
    if (t.endsWith('.ts') || t.endsWith('.tsx') || t.endsWith('.js')) {
      return Icons.javascript_rounded;
    }
    if (t.endsWith('.md') || t.endsWith('.rst')) {
      return Icons.article_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _colorIcono(AppPalette p) {
    final t = widget.doc.titulo.toLowerCase();
    if (t.endsWith('.py')) return AppColors.info;
    if (t.endsWith('.md') || t.endsWith('.rst')) return p.primary;
    if (t.endsWith('.json') || t.endsWith('.yml')) return AppColors.warning;
    return p.muted;
  }

  String _fechaCorta() {
    try {
      final dt = DateTime.parse(widget.doc.fecha);
      final ahora = DateTime.now();
      final diff = ahora.difference(dt);
      if (diff.inMinutes < 1) return 'ahora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: _hover ? p.surface2.withValues(alpha: 0.5) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: widget.esUltimo ? Colors.transparent : p.borderSoft,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x5,
          vertical: AppSpacing.x3,
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: _colorIcono(p).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(_icono(), size: 14, color: _colorIcono(p)),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.doc.titulo,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${widget.doc.nChunks} chunks',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.subtle,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(' · ', style: TextStyle(fontSize: 11, color: p.subtle)),
                      Flexible(
                        child: Text(
                          widget.doc.fuente,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.subtle),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Text(
              _fechaCorta(),
              style: TextStyle(
                fontSize: 11,
                color: p.subtle,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            AnimatedOpacity(
              duration: AppMotion.fast,
              opacity: _hover ? 1.0 : 0.0,
              child: IconButton(
                tooltip: 'Eliminar',
                onPressed: widget.onEliminar,
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                color: AppColors.danger,
                splashRadius: 14,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
