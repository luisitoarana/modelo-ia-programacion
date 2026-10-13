import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';

/// Bloque de fuentes citadas por una respuesta del asistente.
///
/// Componente de visualización de fuentes y métricas del sistema:
///   - Por defecto compactado, sin invadir visualmente la respuesta.
///   - Expandible con animación fluida.
///   - Chips densos pero respiran (12px de padding interno).
///   - Score con punto de color en vez de píldora porcentual ruidosa.
///   - Hover sutil que sube la card 1px y oscurece el borde.
class FuentesMensaje extends StatefulWidget {
  final List<FuenteRag> rag;
  final List<FuenteWeb> web;

  const FuentesMensaje({super.key, this.rag = const [], this.web = const []});

  @override
  State<FuentesMensaje> createState() => _FuentesMensajeState();
}

class _FuentesMensajeState extends State<FuentesMensaje>
    with SingleTickerProviderStateMixin {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.rag.length + widget.web.length;
    if (total == 0) return const SizedBox.shrink();

    final p = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x3),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: _expandido
              ? p.surface2.withValues(alpha: 0.45)
              : p.surface2.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _expandido ? p.border : p.borderSoft,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header clickeable
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _expandido = !_expandido),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x2 + 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 13,
                        color: p.muted,
                      ),
                      const SizedBox(width: AppSpacing.x2),
                      Text(
                        total == 1
                            ? 'Fuente consultada'
                            : '$total fuentes consultadas',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x2),
                      if (widget.rag.isNotEmpty)
                        _CountBadge(
                          count: widget.rag.length,
                          label: widget.rag.length == 1 ? 'doc' : 'docs',
                          color: p.primary,
                        ),
                      if (widget.web.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.x1),
                        _CountBadge(
                          count: widget.web.length,
                          label: 'web',
                          color: AppColors.accent,
                        ),
                      ],
                      const Spacer(),
                      AnimatedRotation(
                        duration: AppMotion.medium,
                        curve: AppMotion.standard,
                        turns: _expandido ? 0.5 : 0,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Lista expandible animada
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: _expandido
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x3,
                        0,
                        AppSpacing.x3,
                        AppSpacing.x3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.rag.isNotEmpty || widget.web.isNotEmpty)
                            Container(
                              height: 1,
                              margin: const EdgeInsets.only(bottom: AppSpacing.x2),
                              color: p.borderSoft,
                            ),
                          ...widget.rag.map((f) => _ChipRag(fuente: f)),
                          if (widget.rag.isNotEmpty && widget.web.isNotEmpty)
                            const SizedBox(height: AppSpacing.x1),
                          ...widget.web.map((f) => _ChipWeb(fuente: f)),
                        ],
                      ),
                    )
                  : const SizedBox(height: 0, width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _CountBadge({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ChipRag extends StatefulWidget {
  final FuenteRag fuente;
  const _ChipRag({required this.fuente});

  @override
  State<_ChipRag> createState() => _ChipRagState();
}

class _ChipRagState extends State<_ChipRag> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final score = widget.fuente.score;
    final dotColor = score >= 0.5
        ? AppColors.success
        : score >= 0.3
            ? AppColors.warning
            : p.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: _hover ? p.border : p.borderSoft),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Score dot (más sutil que la píldora)
            Tooltip(
              message: 'Similitud: ${(score * 100).toStringAsFixed(1)}%',
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Icon(Icons.description_outlined, size: 13, color: p.primary),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                widget.fuente.titulo,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: p.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${(score * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: p.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipWeb extends StatefulWidget {
  final FuenteWeb fuente;
  const _ChipWeb({required this.fuente});

  @override
  State<_ChipWeb> createState() => _ChipWebState();
}

class _ChipWebState extends State<_ChipWeb> {
  bool _hover = false;

  String? get _dominio {
    if (widget.fuente.url == null) return null;
    try {
      return Uri.parse(widget.fuente.url!).host.replaceFirst('www.', '');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final etiqueta = widget.fuente.titulo ?? _dominio ?? 'Resultado web';
    final clickeable = widget.fuente.url != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: clickeable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        margin: const EdgeInsets.only(bottom: 4),
        transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(
            color: _hover ? AppColors.accent.withValues(alpha: 0.4) : p.borderSoft,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: clickeable
                ? () async {
                    final uri = Uri.tryParse(widget.fuente.url!);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical: AppSpacing.x2,
              ),
              child: Row(
                children: [
                  Icon(Icons.language_rounded, size: 13, color: AppColors.accent),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      etiqueta,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_dominio != null) ...[
                    const SizedBox(width: AppSpacing.x2),
                    Text(
                      _dominio!,
                      style: TextStyle(
                        fontSize: 11,
                        color: p.subtle,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  if (clickeable) ...[
                    const SizedBox(width: AppSpacing.x2),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 12,
                      color: _hover ? AppColors.accent : p.subtle,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
