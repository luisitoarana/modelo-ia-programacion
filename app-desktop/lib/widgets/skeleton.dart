import 'package:flutter/material.dart';

import '../theme.dart';

/// Skeleton loaders elegantes con efecto shimmer.
///
/// Estilo Linear / Vercel: gradiente diagonal que se mueve suavemente
/// de izquierda a derecha. Mucho más profesional que un simple
/// `CircularProgressIndicator` y mejor UX porque insinúa la forma
/// del contenido que va a aparecer.
///
/// Uso típico:
///   if (cargando) const Skeleton.text(lines: 3)
///   else Text(...)
class Skeleton extends StatefulWidget {
  /// Ancho del bloque. `null` = ocupa todo el espacio disponible.
  final double? width;

  /// Alto del bloque.
  final double height;

  /// Radio del borde. Por defecto 6 (estilo bloque de texto).
  final double radius;

  /// Modo: `text`, `card`, `circle`, `block`.
  final _SkeletonShape _shape;

  /// Número de líneas si es modo `text`. Cada línea tiene ancho variable.
  final int lines;

  /// Skeleton de texto: una o más líneas con anchos variados.
  const Skeleton.text({
    super.key,
    this.lines = 1,
    this.width,
    this.height = 12,
  })  : radius = 4,
        _shape = _SkeletonShape.text;

  /// Skeleton circular para avatares.
  const Skeleton.circle({super.key, double size = 32})
      : width = size,
        height = size,
        radius = 999,
        lines = 1,
        _shape = _SkeletonShape.circle;

  /// Skeleton de card (rectángulo con radio mayor).
  const Skeleton.card({
    super.key,
    this.width,
    this.height = 120,
    this.radius = 12,
  })  : lines = 1,
        _shape = _SkeletonShape.card;

  /// Skeleton genérico de bloque (sin forma específica).
  const Skeleton.block({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  })  : lines = 1,
        _shape = _SkeletonShape.block;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

enum _SkeletonShape { text, circle, card, block }

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget._shape == _SkeletonShape.text && widget.lines > 1) {
      // Skeleton multi-línea: la última línea es más corta (estilo párrafo).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(widget.lines, (i) {
          final esUltima = i == widget.lines - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: esUltima ? 0 : 8),
            child: SizedBox(
              width: esUltima
                  ? (widget.width ?? double.infinity) * 0.65
                  : widget.width,
              child: _shimmerBlock(),
            ),
          );
        }),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _shimmerBlock(),
    );
  }

  Widget _shimmerBlock() {
    final p = AppPalette.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                // Gradiente diagonal que se desplaza con `_ctrl`.
                final t = _ctrl.value;
                return LinearGradient(
                  begin: Alignment(-1.0 + 3.0 * t - 1.5, -1.0),
                  end: Alignment(-1.0 + 3.0 * t + 0.5, 1.0),
                  colors: [
                    Colors.transparent,
                    p.surface3.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                  stops: const [0.35, 0.5, 0.65],
                ).createShader(rect);
              },
              child: Container(color: p.surface2),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton de un mensaje completo del chat (avatar + 3 líneas).
class SkeletonChatMessage extends StatelessWidget {
  final bool esUsuario;
  const SkeletonChatMessage({super.key, this.esUsuario = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton.circle(size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton.text(lines: 3, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton de un item de la lista de conversaciones de la sidebar.
class SkeletonConversacion extends StatelessWidget {
  const SkeletonConversacion({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Skeleton.text(height: 11, width: 200),
    );
  }
}
