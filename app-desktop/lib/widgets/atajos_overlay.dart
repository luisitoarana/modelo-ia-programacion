import 'package:flutter/material.dart';

import '../services/i18n.dart';
import '../theme.dart';

/// Overlay con la lista de atajos del sistema.
/// Se invoca con showAtajosOverlay(context). Esc o click fuera cierra.
Future<void> showAtajosOverlay(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) => const _AtajosContent(),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _AtajosContent extends StatelessWidget {
  const _AtajosContent();

  static const _atajos = [
    ('Ctrl + K', 'Buscar acciones y conversaciones'),
    ('Ctrl + /', 'Mostrar este overlay'),
    ('Ctrl + N', 'Nuevo chat'),
    ('Ctrl + ,', 'Abrir configuración'),
    ('Ctrl + B', 'Colapsar/expandir sidebar'),
    ('Ctrl + Shift + L', 'Alternar tema claro/oscuro'),
    ('Ctrl + 1', 'Vista Chat'),
    ('Ctrl + 2', 'Vista Explicar'),
    ('Ctrl + 3', 'Vista Explorador'),
    ('Ctrl + 4', 'Vista Terminal'),
    ('Esc', 'Cerrar modal'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.borderSoft),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                  child: Row(
                    children: [
                      Icon(Icons.keyboard, size: 16, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          I18n.t('atajos.titulo'),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.text),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 16, color: p.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: p.borderSoft),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 440),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final a in _atajos)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(a.$2,
                                      style: TextStyle(
                                          fontSize: 12.5, color: p.text)),
                                ),
                                _KbdTeclas(combo: a.$1),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.borderSoft)),
                    color: p.surface.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    I18n.t('atajos.macos_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: p.subtle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.borderSoft),
            ),
            child: Center(
              child: Text(
                teclas[i],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ),
          ),
          if (i < teclas.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('+',
                  style: TextStyle(fontSize: 10, color: p.subtle)),
            ),
        ],
      ],
    );
  }
}
