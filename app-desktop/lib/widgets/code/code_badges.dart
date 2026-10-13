import 'package:flutter/material.dart';

import '../../theme.dart';
import 'code_models.dart';

/// Píldora que resume el resultado de una ejecución: color verde/rojo/naranja
/// según exit code y timeout, con icono + "exit N · Ts".
class BadgeResultado extends StatelessWidget {
  final ResultadoEjecucion resultado;
  const BadgeResultado({super.key, required this.resultado});

  @override
  Widget build(BuildContext context) {
    final o = resultado;
    final ok = o.exitCode == 0 && !o.timeout;
    final color = o.timeout
        ? AppColors.warning
        : (ok ? AppColors.success : AppColors.danger);
    final icono = o.timeout
        ? Icons.timer_outlined
        : (ok ? Icons.check_circle_outline : Icons.error_outline);
    final texto = o.timeout
        ? 'timeout · ${o.duracion.toStringAsFixed(2)}s'
        : 'exit ${o.exitCode} · ${o.duracion.toStringAsFixed(2)}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w600,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta mono con el nombre del lenguaje en mayúsculas (ej. `PYTHON`).
class BadgeLenguaje extends StatelessWidget {
  final String lenguaje;
  const BadgeLenguaje({super.key, required this.lenguaje});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.borderSoft),
      ),
      child: Text(
        lenguaje.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontFamily: AppFonts.monoFallback.first,
          fontFamilyFallback: AppFonts.monoFallback,
          color: p.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Chip de sugerencia clickeable ("Refactoriza esto", "Encuentra bugs", …)
/// usado en el panel IA para lanzar consultas rápidas al asistente.
class ChipIa extends StatelessWidget {
  final String label;
  final void Function(String label) onTap;
  const ChipIa({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return InkWell(
      onTap: () => onTap(label),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: p.borderSoft),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10.5, color: p.muted),
        ),
      ),
    );
  }
}
