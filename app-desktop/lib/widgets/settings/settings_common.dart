import 'package:flutter/material.dart';

import '../../theme.dart';

/// Título grande de una sección de settings (24 pt).
class SettingsTitulo extends StatelessWidget {
  final String titulo;
  final String? descripcion;
  const SettingsTitulo({super.key, required this.titulo, this.descripcion});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: p.text,
                  fontSize: 24,
                ),
          ),
          if (descripcion != null) ...[
            const SizedBox(height: 4),
            Text(
              descripcion!,
              style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Subtítulo interno de una sección (15 pt, semibold).
class SettingsSubtitulo extends StatelessWidget {
  final String titulo;
  const SettingsSubtitulo({super.key, required this.titulo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
      ),
    );
  }
}

/// Fila estándar de ajuste: label + descripción + control a la derecha.
class SettingsFila extends StatelessWidget {
  final String label;
  final String? descripcion;
  final Widget control;
  const SettingsFila({
    super.key,
    required this.label,
    this.descripcion,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.borderSoft)),
        ),
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: p.text,
                          fontWeight: FontWeight.w500)),
                  if (descripcion != null) ...[
                    const SizedBox(height: 3),
                    Text(descripcion!,
                        style: TextStyle(
                            fontSize: 12, color: p.muted, height: 1.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            control,
          ],
        ),
      ),
    );
  }
}

/// Switch animado con feedback táctil (press = shrink) usado en toda la UI
/// de settings.
class SettingsSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final activo = widget.value;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => widget.onChanged(!activo),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 28,
          width: 48,
          decoration: BoxDecoration(
            color: activo ? p.primary : p.surface3,
            borderRadius: BorderRadius.circular(999),
            boxShadow: activo
                ? [
                    BoxShadow(
                      color: p.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: activo ? 23 : 3,
                top: 3,
                child: AnimatedScale(
                  scale: _pressed ? 0.85 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: Container(
                    height: 22,
                    width: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 3,
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
    );
  }
}

/// Píldora coloreada indicando un estado ("Activo", "Privadas", …).
class SettingsBadgeEstado extends StatelessWidget {
  final String label;
  final Color color;
  const SettingsBadgeEstado({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
