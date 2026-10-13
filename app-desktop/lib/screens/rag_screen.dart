import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/rag/rag_banner_error.dart';
import '../widgets/rag/rag_dialogos.dart';
import '../widgets/rag/rag_drop_zone.dart';
import '../widgets/rag/rag_hero.dart';
import '../widgets/rag/rag_metricas.dart';
import '../widgets/rag/rag_tabla_documentos.dart';

/// Pantalla "Base de conocimiento" (RAG) — orquesta:
///   - Hero (título + descripción)
///   - Métricas del índice (documentos, chunks, backend)
///   - Banner de error (opcional)
///   - Drop zone (subir archivos o pegar texto)
///   - Tabla de documentos indexados con filtro y hover para eliminar
///
/// Cada bloque vive en `lib/widgets/rag/`. Esta pantalla solo se encarga de
/// mantener el estado y llamar a la API.
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
    setState(() {
      _cargando = true;
      _error = null;
    });
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
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _cargando = false;
        });
      }
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
    );
    if (res == null || res.files.isEmpty) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      for (final f in res.files) {
        final bytes = f.bytes ??
            (f.path != null ? await File(f.path!).readAsBytes() : null);
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
    final res = await mostrarDialogoPegarTexto(context);
    if (res == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      await _api.subirTextoRag(
        titulo: res.titulo,
        texto: res.contenido,
        fuente: 'pegado',
      );
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _eliminar(DocumentoRag d) async {
    final ok = await confirmarEliminarDocumento(context, d);
    if (!ok) return;
    try {
      await _api.eliminarDocumentoRag(d.id);
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _archivosSoltados(List<String> paths) async {
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      for (final f in paths) {
        final bytes = await File(f).readAsBytes();
        if (bytes.length > 5_000_000) continue;
        final nombre = f.split(Platform.pathSeparator).last;
        await _api.subirArchivoRag(nombreArchivo: nombre, bytes: bytes);
      }
      await _recargar();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
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
                AppSpacing.x6,
                AppSpacing.x8,
                AppSpacing.x6,
                AppSpacing.x10,
              ),
              children: [
                const RagHero(),
                const SizedBox(height: AppSpacing.x6),
                RagMetricas(
                  estado: _estado,
                  cargando: _cargando,
                  onRecargar: _recargar,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  RagBannerError(
                    mensaje: _error!,
                    onCerrar: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: AppSpacing.x6),
                RagDropZone(
                  subiendo: _subiendo,
                  onPickFiles: _seleccionarYSubir,
                  onPasteText: _pegarTexto,
                  onFilesDropped: _archivosSoltados,
                ),
                const SizedBox(height: AppSpacing.x6),
                RagTablaDocumentos(
                  todos: _documentos,
                  filtrados: _documentosFiltrados,
                  cargando: _cargando,
                  filtro: _filtro,
                  filtroCtrl: _filtroCtrl,
                  onEliminar: _eliminar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
