import 'package:flutter/material.dart';

import '../../theme.dart';

/// Encabezado grande de la pantalla RAG — icono terracota + título serif +
/// descripción larga con la promesa "sin alucinaciones".
class RagHero extends StatelessWidget {
  const RagHero({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.menu_book_rounded, size: 24, color: p.primary),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Base de conocimiento',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Los documentos que subas aquí son los que el asistente puede '
                'citar literalmente. Sin alucinaciones — si la respuesta no está '
                'en tus fuentes, te lo dirá.',
                style: TextStyle(
                  fontSize: 14,
                  color: p.muted,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
