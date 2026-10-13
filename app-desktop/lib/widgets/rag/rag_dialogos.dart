import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';

/// Resultado del diálogo "Pegar texto": título + contenido.
class PegarTextoResult {
  final String titulo;
  final String contenido;
  const PegarTextoResult(this.titulo, this.contenido);
}

/// Diálogo para pegar texto plano y darle un título. Devuelve `null` si
/// el usuario cancela o si alguno de los dos campos está vacío.
Future<PegarTextoResult?> mostrarDialogoPegarTexto(BuildContext context) async {
  final tituloCtrl = TextEditingController();
  final contenidoCtrl = TextEditingController();
  final p = AppPalette.of(context);

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) => Dialog(
      backgroundColor: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Añadir documento',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pega cualquier texto plano. Se troceará automáticamente y quedará indexado para que el chat lo cite.',
                style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.x5),
              _LabeledField(
                label: 'Título',
                child: TextField(
                  controller: tituloCtrl,
                  autofocus: true,
                  decoration:
                      _inputDecoration(p, 'Ej: notas-clase-arboles.md'),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              _LabeledField(
                label: 'Contenido',
                child: TextField(
                  controller: contenidoCtrl,
                  minLines: 7,
                  maxLines: 12,
                  decoration:
                      _inputDecoration(p, 'Pega aquí el contenido...'),
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child:
                        Text('Cancelar', style: TextStyle(color: p.muted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.bolt_rounded, size: 15),
                    label: const Text('Indexar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4,
                        vertical: AppSpacing.x3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final titulo = tituloCtrl.text.trim();
  final contenido = contenidoCtrl.text.trim();
  tituloCtrl.dispose();
  contenidoCtrl.dispose();

  if (ok != true || titulo.isEmpty || contenido.isEmpty) return null;
  return PegarTextoResult(titulo, contenido);
}

/// Confirmación destructiva para eliminar un documento indexado.
Future<bool> confirmarEliminarDocumento(
  BuildContext context,
  DocumentoRag d,
) async {
  final p = AppPalette.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.border),
      ),
      title: Text(
        'Eliminar documento',
        style: TextStyle(fontFamily: AppFonts.serifFallback.first),
      ),
      content: Text(
        'Vas a eliminar "${d.titulo}". El chat dejará de citarlo. '
        'Esta acción no se puede deshacer.',
        style: TextStyle(color: p.muted, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline, size: 14),
          label: const Text('Eliminar'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
        ),
      ],
    ),
  );
  return ok == true;
}

InputDecoration _inputDecoration(AppPalette p, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.subtle, fontSize: 13),
    filled: true,
    fillColor: p.surface2.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.x3,
      vertical: AppSpacing.x3,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: p.borderSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: p.borderSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: p.primary, width: 1.5),
    ),
  );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: p.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
