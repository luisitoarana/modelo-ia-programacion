import 'package:flutter/material.dart';

import '../theme.dart';

enum ConfirmTono { danger, warning, neutral }
enum ConfirmIcono { eliminar, logout, warning }

/// Muestra un diálogo de confirmación elegante con backdrop blur y
/// animación de entrada (scale + fade).
///
/// Devuelve `true` si el usuario confirma, `false` si cancela.
///
/// Atajos:
///   - Enter → confirma
///   - Esc   → cancela
Future<bool> mostrarConfirmacion(
  BuildContext context, {
  required String titulo,
  required String descripcion,
  String textoConfirmar = 'Confirmar',
  String textoCancelar = 'Cancelar',
  ConfirmTono tono = ConfirmTono.danger,
  ConfirmIcono icono = ConfirmIcono.warning,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) {
      return _ConfirmDialogContent(
        titulo: titulo,
        descripcion: descripcion,
        textoConfirmar: textoConfirmar,
        textoCancelar: textoCancelar,
        tono: tono,
        icono: icono,
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _ConfirmDialogContent extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final String textoConfirmar;
  final String textoCancelar;
  final ConfirmTono tono;
  final ConfirmIcono icono;

  const _ConfirmDialogContent({
    required this.titulo,
    required this.descripcion,
    required this.textoConfirmar,
    required this.textoCancelar,
    required this.tono,
    required this.icono,
  });

  Color _tonoColor(AppPalette p) => switch (tono) {
        ConfirmTono.danger => AppColors.danger,
        ConfirmTono.warning => AppColors.warning,
        ConfirmTono.neutral => p.primary,
      };

  IconData _iconoData() => switch (icono) {
        ConfirmIcono.eliminar => Icons.delete_outline,
        ConfirmIcono.logout => Icons.logout,
        ConfirmIcono.warning => Icons.warning_amber,
      };

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final colorTono = _tonoColor(p);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: colorTono.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_iconoData(), size: 22, color: colorTono),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: p.text,
                              fontSize: 19,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        descripcion,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: p.muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.4),
                    border: Border(top: BorderSide(color: p.borderSoft)),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(color: p.borderSoft),
                            foregroundColor: p.text,
                          ),
                          child: Text(textoCancelar),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorTono,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: Text(textoConfirmar),
                        ),
                      ),
                    ],
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
