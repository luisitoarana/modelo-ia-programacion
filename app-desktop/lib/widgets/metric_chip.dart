import 'package:flutter/material.dart';

import '../theme.dart';

/// Tipo de tendencia para acompañar la métrica.
enum MetricTrend { up, down, neutral }

/// Chip de métrica para dashboards estilo Linear / Vercel Analytics.
///
/// Estructura:
///   - label corto arriba (ej: "Loss val").
///   - número grande tipográficamente protagonista.
///   - chip de variación opcional (ej: "+12.4%") con color semántico
///     según tendencia (verde sube, rojo baja, gris neutro).
///   - icono opcional en la esquina superior.
///
/// Útil para:
///   - Panel de investigador con métricas del entrenamiento.
///   - Estadísticas del dataset (válidos, descartados, código compila).
///   - Métricas de calidad de los reward models.
class MetricChip extends StatefulWidget {
  /// Texto pequeño descriptivo arriba.
  final String label;

  /// Valor protagonista (string para permitir formatos como "3.4M", "98.2 %").
  final String valor;

  /// Cambio numérico para mostrar variación. Ej: "+12.4%", "-3", "stable".
  final String? variacion;

  /// Tipo de tendencia (define el color del chip de variación).
  final MetricTrend tendencia;

  /// Icono opcional para identificar la categoría.
  final IconData? icono;

  /// Acción opcional al tocar el chip.
  final VoidCallback? onTap;

  const MetricChip({
    super.key,
    required this.label,
    required this.valor,
    this.variacion,
    this.tendencia = MetricTrend.neutral,
    this.icono,
    this.onTap,
  });

  @override
  State<MetricChip> createState() => _MetricChipState();
}

class _MetricChipState extends State<MetricChip> {
  bool _hover = false;

  Color _colorTendencia(AppPalette p) {
    switch (widget.tendencia) {
      case MetricTrend.up:
        return p.success;
      case MetricTrend.down:
        return p.danger;
      case MetricTrend.neutral:
        return p.muted;
    }
  }

  IconData _iconoTendencia() {
    switch (widget.tendencia) {
      case MetricTrend.up:
        return Icons.trending_up;
      case MetricTrend.down:
        return Icons.trending_down;
      case MetricTrend.neutral:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final colorTend = _colorTendencia(p);

    final content = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: _hover ? p.primary.withValues(alpha: 0.35) : p.borderSoft,
          width: 1,
        ),
        boxShadow: _hover ? p.elevation(2) : p.elevation(1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.icono != null) ...[
                Icon(widget.icono, size: 14, color: p.subtle),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: p.muted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.valor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: p.text,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          if (widget.variacion != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorTend.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconoTendencia(), size: 11, color: colorTend),
                  const SizedBox(width: 3),
                  Text(
                    widget.variacion!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorTend,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.onTap == null) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}
