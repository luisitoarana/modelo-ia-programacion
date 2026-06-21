import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Panel con efecto cristal esmerilado (frosted glass).
///
/// Estilo macOS / iOS / Vision Pro — superficie semi-transparente con
/// blur del contenido detrás, borde 1px iluminado por dentro y sombra
/// sutil pegada. Útil para:
///  - Overlays sobre código (artifacts, popovers de info).
///  - Headers que flotan sobre contenido scrolleable.
///  - Tarjetas de "summary" sobre fondos coloridos (dashboards de
///    investigador con gráficas de fondo).
///
/// Importante: `BackdropFilter.blur` requiere que detrás haya contenido
/// pintado. Si va directamente sobre `Scaffold.body` blanco, el efecto
/// no se nota. Combinar con `AmbientBackground` para que el blur tenga
/// algo que difuminar.
class GlassPanel extends StatelessWidget {
  /// Contenido del panel.
  final Widget child;

  /// Padding interior.
  final EdgeInsetsGeometry padding;

  /// Radio del borde.
  final double radius;

  /// Intensidad del blur. 0 = sin blur, 30+ = vidrio opaco.
  final double blur;

  /// Opacidad del color de superficie (sobrepuesto al blur).
  final double opacity;

  /// Si es `true`, añade un borde iluminado 1px estilo glass.
  final bool border;

  /// Nivel de elevación (sombra). Por defecto nivel 2.
  final int elevation;

  /// Ancho fijo opcional.
  final double? width;

  /// Alto fijo opcional.
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.lg,
    this.blur = 24,
    this.opacity = 0.65,
    this.border = true,
    this.elevation = 2,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = isDark
        ? p.surface.withValues(alpha: opacity * 0.75)
        : p.surface.withValues(alpha: opacity);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: p.elevation(elevation),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: BorderRadius.circular(radius),
              border: border
                  ? Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.40),
                      width: 1,
                    )
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
