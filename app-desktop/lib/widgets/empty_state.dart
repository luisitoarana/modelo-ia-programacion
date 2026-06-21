import 'package:flutter/material.dart';

import '../theme.dart';

/// Estado vacío elegante con ilustración ambiental y acción opcional.
///
/// Estilo Anthropic / Linear: ilustración minimalista (círculos
/// concéntricos + icono central), tipografía generosa y un botón
/// primario para invitar a la acción siguiente.
///
/// Uso:
///   EmptyState(
///     icono: Icons.chat_bubble_outline,
///     titulo: 'Aún no hay conversaciones',
///     mensaje: 'Empieza preguntando lo que quieras a tu asistente.',
///     accion: EmptyStateAction(
///       label: 'Nueva conversación',
///       onTap: _crearNueva,
///     ),
///   )
class EmptyState extends StatefulWidget {
  /// Icono central de la ilustración.
  final IconData icono;

  /// Titular grande (serif).
  final String titulo;

  /// Mensaje secundario (sans).
  final String mensaje;

  /// Acción primaria opcional.
  final EmptyStateAction? accion;

  /// Acción secundaria opcional (text button).
  final EmptyStateAction? accionSecundaria;

  /// Si es `true`, anima el halo central (sutil pulse).
  final bool animado;

  const EmptyState({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
    this.accionSecundaria,
    this.animado = true,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _entrada;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.animado) _pulse.repeat();

    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final txt = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: AnimatedBuilder(
            animation: _entrada,
            builder: (_, child) {
              return Opacity(
                opacity: _entrada.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - _entrada.value) * 12),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ilustración: 3 anillos concéntricos + icono central.
                _Ilustracion(
                  icono: widget.icono,
                  pulse: _pulse,
                  color: p.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.titulo,
                  textAlign: TextAlign.center,
                  style: txt.headlineLarge?.copyWith(
                    fontSize: 20,
                    color: p.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.mensaje,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: p.muted,
                    height: 1.5,
                  ),
                ),
                if (widget.accion != null) ...[
                  const SizedBox(height: 22),
                  _PrimaryAction(
                    accion: widget.accion!,
                  ),
                ],
                if (widget.accionSecundaria != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.accionSecundaria!.onTap,
                    child: Text(widget.accionSecundaria!.label),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Acción asociada a un `EmptyState`.
class EmptyStateAction {
  final String label;
  final IconData? icono;
  final VoidCallback onTap;
  const EmptyStateAction({
    required this.label,
    required this.onTap,
    this.icono,
  });
}

class _Ilustracion extends StatelessWidget {
  final IconData icono;
  final AnimationController pulse;
  final Color color;
  const _Ilustracion({
    required this.icono,
    required this.pulse,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final t = pulse.value;
          // 3 anillos con desfase de 1/3 de la animación.
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(t, p, 0.0),
              _ring(t, p, 0.33),
              _ring(t, p, 0.66),
              // Disco central con icono.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 24,
                      spreadRadius: -2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icono, color: Colors.white, size: 26),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Devuelve un anillo expandiéndose y desvaneciéndose.
  Widget _ring(double t, AppPalette p, double desfase) {
    var fase = (t + desfase) % 1.0;
    // El anillo crece desde 56px hasta 132px y se desvanece.
    final tamano = 56 + (132 - 56) * fase;
    final opacity = (1.0 - fase) * 0.35;
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.2,
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatefulWidget {
  final EmptyStateAction accion;
  const _PrimaryAction({required this.accion});

  @override
  State<_PrimaryAction> createState() => _PrimaryActionState();
}

class _PrimaryActionState extends State<_PrimaryAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.accion.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: _hover ? p.primaryHover : p.primary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: p.primary.withValues(alpha: _hover ? 0.34 : 0.22),
                blurRadius: _hover ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.accion.icono != null) ...[
                Icon(widget.accion.icono, color: Colors.white, size: 16),
                const SizedBox(width: 8),
              ],
              Text(
                widget.accion.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
