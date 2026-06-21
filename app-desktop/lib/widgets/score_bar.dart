import 'package:flutter/material.dart';

import '../theme.dart';

/// Barra horizontal 0-10 para visualizar uno de los 6 scores del
/// sistema multi-criterio (SEG/LEG/ESC/ARQ/REN/MAN).
///
/// Diseño compacto y semántico:
///  - Pista vacía con color suave.
///  - Fill animado proporcional al score.
///  - Color del fill cambia según el score (rojo < 4, amarillo 4-7,
///    verde > 7) para que el usuario perciba salud de un vistazo.
///  - Label izquierda (sigla 3 caracteres) + valor derecha.
///  - Animación de entrada: el fill se rellena en 600ms con cosine ease.
class ScoreBar extends StatelessWidget {
  /// Etiqueta de 3 letras (SEG, LEG, ESC, ARQ, REN, MAN).
  final String label;

  /// Score 0.0–10.0. Si supera 10, se trunca.
  final double score;

  /// Nombre largo opcional para tooltip al pasar el mouse.
  final String? nombreCompleto;

  /// Si es `true`, anima la barra al aparecer.
  final bool animado;

  const ScoreBar({
    super.key,
    required this.label,
    required this.score,
    this.nombreCompleto,
    this.animado = true,
  });

  Color _colorPorScore(AppPalette p) {
    if (score < 4.0) return p.danger;
    if (score < 7.0) return p.warning;
    return p.success;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = _colorPorScore(p);
    final pct = (score.clamp(0.0, 10.0)) / 10.0;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Sigla — fuente monoespaciada para que las 6 barras se alineen.
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: p.muted,
              letterSpacing: 0.4,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Barra.
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: 8,
              color: p.surface2,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: animado
                        ? const Duration(milliseconds: 600)
                        : Duration.zero,
                    curve: AppMotion.standard,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: pct,
                      heightFactor: 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.85),
                              color,
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Valor a la derecha (con un dígito decimal).
        SizedBox(
          width: 32,
          child: Text(
            score.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: p.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    if (nombreCompleto == null) return row;
    return Tooltip(message: nombreCompleto!, child: row);
  }
}

/// Conjunto de las 6 barras del sistema multi-criterio.
///
/// Uso:
///   ScoreBarSet(
///     scores: {'SEG': 8.2, 'LEG': 7.0, 'ESC': 6.5,
///              'ARQ': 7.8, 'REN': 5.4, 'MAN': 8.0},
///   )
class ScoreBarSet extends StatelessWidget {
  final Map<String, double> scores;
  final bool animado;
  final double spacing;

  const ScoreBarSet({
    super.key,
    required this.scores,
    this.animado = true,
    this.spacing = 6,
  });

  static const Map<String, String> _nombresCompletos = {
    'SEG': 'Seguridad',
    'LEG': 'Legibilidad',
    'ESC': 'Escalabilidad',
    'ARQ': 'Arquitectura',
    'REN': 'Rendimiento',
    'MAN': 'Mantenibilidad',
  };

  static const List<String> _orden = ['SEG', 'LEG', 'ESC', 'ARQ', 'REN', 'MAN'];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final sigla in _orden) {
      final score = scores[sigla];
      if (score == null) continue;
      children.add(ScoreBar(
        label: sigla,
        score: score,
        nombreCompleto: _nombresCompletos[sigla],
        animado: animado,
      ));
      children.add(SizedBox(height: spacing));
    }
    if (children.isNotEmpty) children.removeLast();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
