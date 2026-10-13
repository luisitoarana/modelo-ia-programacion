import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';

/// Banda superior con status del índice, contadores de documentos/chunks y
/// backend de embeddings. Muestra un botón de recarga cuando no está cargando.
class RagMetricas extends StatelessWidget {
  final EstadoRag? estado;
  final bool cargando;
  final VoidCallback onRecargar;
  const RagMetricas({
    super.key,
    required this.estado,
    required this.cargando,
    required this.onRecargar,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final e = estado;
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
            cargando
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
            _statTexto(
              p,
              e.backend == 'sentence-transformers' ? 'SBERT' : e.backend,
              '${e.dim}d embeddings',
            ),
          ],
          const Spacer(),
          if (!cargando)
            IconButton(
              tooltip: 'Recargar',
              icon: Icon(Icons.refresh_rounded, size: 16, color: p.muted),
              onPressed: onRecargar,
              splashRadius: 18,
            ),
        ],
      ),
    );
  }

  Widget _statusDot(bool ok) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _miniSep(AppPalette p) =>
      Container(width: 1, height: 18, color: p.borderSoft);

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
}
