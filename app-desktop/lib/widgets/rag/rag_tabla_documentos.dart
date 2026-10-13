import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import 'rag_row_documento.dart';

/// Tarjeta principal con la lista de documentos indexados:
///   - Header con título "Documentos", contador y campo de filtro.
///   - Estados: cargando, vacío total, filtro vacío, o lista normal.
class RagTablaDocumentos extends StatelessWidget {
  final List<DocumentoRag> todos;
  final List<DocumentoRag> filtrados;
  final bool cargando;
  final String filtro;
  final TextEditingController filtroCtrl;
  final void Function(DocumentoRag) onEliminar;

  const RagTablaDocumentos({
    super.key,
    required this.todos,
    required this.filtrados,
    required this.cargando,
    required this.filtro,
    required this.filtroCtrl,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerTabla(p),
          Container(height: 1, color: p.borderSoft),
          if (cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else if (todos.isEmpty)
            _RagEmptyState()
          else if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.x10),
              child: Center(
                child: Text(
                  'Ningún documento coincide con "$filtro".',
                  style: TextStyle(fontSize: 13, color: p.muted),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < filtrados.length; i++)
                  RagRowDocumento(
                    doc: filtrados[i],
                    esUltimo: i == filtrados.length - 1,
                    onEliminar: () => onEliminar(filtrados[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _headerTabla(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x5,
        AppSpacing.x4,
        AppSpacing.x5,
        AppSpacing.x3,
      ),
      child: Row(
        children: [
          Text(
            'Documentos',
            style: TextStyle(
              fontFamily: AppFonts.serifFallback.first,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: p.text,
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
              '${todos.length}',
              style: TextStyle(
                fontSize: 11,
                color: p.muted,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          if (todos.isNotEmpty)
            SizedBox(
              width: 200,
              child: TextField(
                controller: filtroCtrl,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Filtrar…',
                  hintStyle:
                      TextStyle(fontSize: 12.5, color: p.subtle),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: p.muted,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: p.surface2.withValues(alpha: 0.5),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}

/// Empty state ilustrado cuando aún no hay documentos indexados.
class _RagEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.text,
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
