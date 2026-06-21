import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Fondo ambiental con orbs blureados que flotan suavemente.
///
/// Sustituye un background plano por un campo de luz dinámico,
/// elevando la sensación de calidad sin distraer del contenido.
///
/// Estilo Stripe / Linear / Vercel / Anthropic — orbs grandes con
/// blur intenso, opacidad muy baja, movimiento muy lento.
///
/// Uso (debajo del contenido):
///   Stack(
///     children: [
///       const AmbientBackground(),
///       Positioned.fill(child: tuContenido),
///     ],
///   )
class AmbientBackground extends StatefulWidget {
  /// Número de orbs. 3-5 funciona mejor.
  final int orbCount;

  /// Intensidad. 0 = invisible, 1 = saturado. Por defecto 0.45.
  final double intensity;

  const AmbientBackground({
    super.key,
    this.orbCount = 4,
    this.intensity = 0.45,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_OrbConfig> _orbs;

  @override
  void initState() {
    super.initState();
    // Ciclo muy lento — orbs casi parecen estáticos.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    final rng = math.Random(42);
    _orbs = List.generate(widget.orbCount, (i) {
      return _OrbConfig(
        // Origen aleatorio dentro de [-0.2, 1.2] para que se asomen
        // por los bordes.
        cxStart: rng.nextDouble() * 1.4 - 0.2,
        cyStart: rng.nextDouble() * 1.4 - 0.2,
        cxEnd: rng.nextDouble() * 1.4 - 0.2,
        cyEnd: rng.nextDouble() * 1.4 - 0.2,
        radius: 220 + rng.nextDouble() * 220,
        phase: rng.nextDouble(),
        colorIndex: i % 3,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Tres tonalidades cercanas al primary para que la mezcla quede armónica.
    final palette = <Color>[
      p.primary,
      p.info,
      p.primaryHover,
    ];

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return CustomPaint(
            painter: _AmbientPainter(
              orbs: _orbs,
              colors: palette,
              t: t,
              intensity: widget.intensity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _OrbConfig {
  final double cxStart;
  final double cyStart;
  final double cxEnd;
  final double cyEnd;
  final double radius;
  final double phase;
  final int colorIndex;
  _OrbConfig({
    required this.cxStart,
    required this.cyStart,
    required this.cxEnd,
    required this.cyEnd,
    required this.radius,
    required this.phase,
    required this.colorIndex,
  });
}

class _AmbientPainter extends CustomPainter {
  final List<_OrbConfig> orbs;
  final List<Color> colors;
  final double t;
  final double intensity;

  _AmbientPainter({
    required this.orbs,
    required this.colors,
    required this.t,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Ondas suaves: usar sin/cos con desfase por orb.
    for (final orb in orbs) {
      // Posición interpolada entre start y end con ondulación.
      final fase = (t + orb.phase) % 1.0;
      final swing = math.sin(fase * 2 * math.pi);
      final swing2 = math.cos(fase * 2 * math.pi);
      final cx = orb.cxStart * size.width +
          (orb.cxEnd - orb.cxStart) * size.width * (0.5 + 0.5 * swing);
      final cy = orb.cyStart * size.height +
          (orb.cyEnd - orb.cyStart) * size.height * (0.5 + 0.5 * swing2);

      // Gradiente radial para cada orb.
      final color = colors[orb.colorIndex];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.32 * intensity),
            color.withValues(alpha: 0.10 * intensity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: orb.radius),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);
      canvas.drawCircle(Offset(cx, cy), orb.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.t != t || old.intensity != intensity;
}

/// Variante estática (sin animación) — útil para áreas donde el usuario
/// está leyendo o trabajando y no queremos movimiento.
class AmbientBackgroundStatic extends StatelessWidget {
  final double intensity;
  const AmbientBackgroundStatic({super.key, this.intensity = 0.35});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.8),
            radius: 1.4,
            colors: [
              p.primary.withValues(alpha: 0.10 * intensity),
              p.primary.withValues(alpha: 0.02 * intensity),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.7),
              radius: 1.2,
              colors: [
                p.info.withValues(alpha: 0.08 * intensity),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
