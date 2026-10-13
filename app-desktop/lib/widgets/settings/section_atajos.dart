import 'package:flutter/material.dart';

import '../../theme.dart';
import 'settings_common.dart';

class AtajosSection extends StatelessWidget {
  const AtajosSection({super.key});

  static const _atajos = [
    ('Ctrl + N', 'Nuevo chat'),
    ('Ctrl + ,', 'Abrir configuración'),
    ('Ctrl + /', 'Mostrar atajos'),
    ('Ctrl + B', 'Colapsar/expandir sidebar'),
    ('Ctrl + Enter', 'Enviar mensaje'),
    ('Ctrl + Shift + L', 'Alternar tema claro/oscuro'),
    ('Shift + Enter', 'Nueva línea en composer'),
    ('Esc', 'Cerrar modal / volver'),
    ('↑', 'Mensaje anterior (composer vacío)'),
    ('↓', 'Mensaje siguiente (composer vacío)'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Atajos de teclado',
          descripcion:
              'Acelera tu navegación. En macOS usa ⌘ en lugar de Ctrl.',
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.borderSoft),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _atajos.length; i++) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_atajos[i].$2,
                            style: TextStyle(fontSize: 13, color: p.text)),
                      ),
                      _KbdTeclas(combo: _atajos[i].$1),
                    ],
                  ),
                ),
                if (i != _atajos.length - 1)
                  Divider(height: 1, color: p.borderSoft),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _KbdTeclas extends StatelessWidget {
  final String combo;
  const _KbdTeclas({required this.combo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final teclas = combo.split(' + ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < teclas.length; i++) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.borderSoft),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                teclas[i],
                style: TextStyle(
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
          ),
          if (i < teclas.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('+',
                  style: TextStyle(fontSize: 11, color: p.subtle)),
            ),
        ],
      ],
    );
  }
}
