import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';

/// Fila de un documento indexado: icono coloreado por extensión, título,
/// contador de chunks + fuente, fecha corta y botón X que aparece en hover.
class RagRowDocumento extends StatefulWidget {
  final DocumentoRag doc;
  final bool esUltimo;
  final VoidCallback onEliminar;

  const RagRowDocumento({
    super.key,
    required this.doc,
    required this.esUltimo,
    required this.onEliminar,
  });

  @override
  State<RagRowDocumento> createState() => _RagRowDocumentoState();
}

class _RagRowDocumentoState extends State<RagRowDocumento> {
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
          color:
              _hover ? p.surface2.withValues(alpha: 0.5) : Colors.transparent,
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
              width: 30,
              height: 30,
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
                      Text(' · ',
                          style: TextStyle(fontSize: 11, color: p.subtle)),
                      Flexible(
                        child: Text(
                          widget.doc.fuente,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: p.subtle),
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
