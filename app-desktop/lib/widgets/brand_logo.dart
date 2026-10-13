import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Logotipo moderno y geométrico para la plataforma.
///
/// Simboliza la intersección entre:
///  - **Tecnología e Inteligencia Artificial**: Nodos y polígonos angulares limpios.
///  - **Smart Trading**: Vector ascendente y prisma de rendimiento cuántico.
///  - **Desarrollo de Videojuegos**: Escudo facetado de baja poligonización (low-poly / crest).
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final Color? color;
  final Gradient? gradient;

  const BrandLogo({
    super.key,
    this.size = 24.0,
    this.showGlow = false,
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final gradienteEfectivo = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color ?? p.primary,
            color != null ? color!.withValues(alpha: 0.85) : p.primaryHover,
            const Color(0xFF38BDF8), // Acento cian tecnológico
          ],
        );

    Widget logoWidget = CustomPaint(
      size: Size(size, size),
      painter: _BrandLogoPainter(
        gradient: gradienteEfectivo,
        colorFijo: color,
      ),
    );

    if (showGlow) {
      return Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: (color ?? p.primary).withValues(alpha: 0.35),
              blurRadius: size * 0.6,
              spreadRadius: size * 0.1,
            ),
          ],
        ),
        child: logoWidget,
      );
    }

    return logoWidget;
  }
}

class _BrandLogoPainter extends CustomPainter {
  final Gradient gradient;
  final Color? colorFijo;

  _BrandLogoPainter({required this.gradient, this.colorFijo});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // 1. Fondo: Emblema contenedor rounded squircle de alta precisión
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.28));
    final bgPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, bgPaint);

    // Borde sutil de brillo superior
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.04)
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, borderPaint);

    // 2. Glifo de Código y Red Neuronal: < / >
    final strokeWidth = math.max(1.5, w * 0.085);
    final codePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Bracket Izquierdo <
    final pathLeft = Path()
      ..moveTo(w * 0.38, h * 0.32)
      ..lineTo(w * 0.23, h * 0.50)
      ..lineTo(w * 0.38, h * 0.68);
    canvas.drawPath(pathLeft, codePaint);

    // Bracket Derecho >
    final pathRight = Path()
      ..moveTo(w * 0.62, h * 0.32)
      ..lineTo(w * 0.77, h * 0.50)
      ..lineTo(w * 0.62, h * 0.68);
    canvas.drawPath(pathRight, codePaint);

    // Barra / Slash central estilizada
    final slashPaint = Paint()
      ..color = const Color(0xFF38BDF8) // Azul cian tecnológico
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final pathSlash = Path()
      ..moveTo(w * 0.56, h * 0.28)
      ..lineTo(w * 0.44, h * 0.72);
    canvas.drawPath(pathSlash, slashPaint);

    // Nodo central neuronal (chispa de inteligencia)
    final nodePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(w * 0.50, h * 0.50), math.max(1.2, w * 0.08), nodePaint);
  }

  @override
  bool shouldRepaint(covariant _BrandLogoPainter oldDelegate) {
    return oldDelegate.colorFijo != colorFijo;
  }
}
