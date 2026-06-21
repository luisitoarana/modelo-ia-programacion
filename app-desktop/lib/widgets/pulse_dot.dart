import 'package:flutter/material.dart';

import '../theme.dart';

/// Indicador animado de "vivo" — un punto que pulsa con un anillo de halo.
///
/// Útil para:
///  - Modelo cargando o procesando.
///  - Conexión activa al backend.
///  - Streaming en curso.
///  - Cualquier estado dinámico que el usuario debe percibir como
///    en tiempo real.
///
/// Estilo Linear/Vercel: pequeño, no llamativo, pero comunica vida.
class PulseDot extends StatefulWidget {
  /// Color del punto. Si es null, usa `palette.primary`.
  final Color? color;

  /// Tamaño del punto central (px).
  final double size;

  /// Si es `true`, el halo se expande continuamente.
  final bool activo;

  /// Tooltip opcional al pasar el mouse.
  final String? tooltip;

  const PulseDot({
    super.key,
    this.color,
    this.size = 8,
    this.activo = true,
    this.tooltip,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.activo) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activo && !oldWidget.activo) {
      _ctrl.repeat();
    } else if (!widget.activo && oldWidget.activo) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = widget.color ?? p.success;
    final w = widget.size * 2.5; // ancho total con halo.

    final dot = SizedBox(
      width: w,
      height: w,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.activo)
                // Halo que crece y se desvanece.
                Container(
                  width: widget.size + (w - widget.size) * t,
                  height: widget.size + (w - widget.size) * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: (1.0 - t) * 0.35),
                  ),
                ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: widget.activo
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (widget.tooltip == null) return dot;
    return Tooltip(message: widget.tooltip!, child: dot);
  }
}

/// Compactor: pulse + label, útil en estados como "Conectado", "Pensando…".
class PulseStatus extends StatelessWidget {
  final String label;
  final Color? color;
  final bool activo;

  const PulseStatus({
    super.key,
    required this.label,
    this.color,
    this.activo = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulseDot(color: color, activo: activo),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: p.muted),
        ),
      ],
    );
  }
}
