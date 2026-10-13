import 'package:flutter/material.dart';

import '../../theme.dart';

/// Zona grande de arrastrar/pegar para subir documentos al índice.
/// La ilustración son tres glifos de página apilados. Cuando `subiendo` es
/// verdadero, el icono central se convierte en un reloj de arena.
class RagDropZone extends StatefulWidget {
  final bool subiendo;
  final VoidCallback onPickFiles;
  final VoidCallback onPasteText;
  final void Function(List<String> paths)? onFilesDropped;

  const RagDropZone({
    super.key,
    required this.subiendo,
    required this.onPickFiles,
    required this.onPasteText,
    this.onFilesDropped,
  });

  @override
  State<RagDropZone> createState() => _RagDropZoneState();
}

class _RagDropZoneState extends State<RagDropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.subiendo
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.subiendo ? null : widget.onPickFiles,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 30),
          decoration: BoxDecoration(
            color: _hover
                ? p.primary.withValues(alpha: 0.04)
                : p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? p.primary.withValues(alpha: 0.5)
                  : p.borderSoft,
              width: 1.5,
            ),
            boxShadow: _hover ? p.insetGlow : null,
          ),
          child: Column(
            children: [
              SizedBox(
                width: 64,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _GlyphPage(
                      color: p.borderSoft,
                      dx: -10,
                      dy: 6,
                      rotZ: -0.08,
                    ),
                    _GlyphPage(
                      color: p.border,
                      dx: 10,
                      dy: 4,
                      rotZ: 0.06,
                    ),
                    _GlyphPage(
                      color: _hover
                          ? p.primary.withValues(alpha: 0.7)
                          : p.muted,
                      dx: 0,
                      dy: -4,
                      rotZ: 0,
                      destacado: true,
                      icon: widget.subiendo
                          ? Icons.hourglass_top_rounded
                          : Icons.add_rounded,
                      iconColor: _hover ? p.primary : p.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(
                widget.subiendo
                    ? 'Indexando...'
                    : 'Arrastra o haz click para subir',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hasta 5 MB · .md  .txt  .py  .json  .yml  .rst  .html  .css',
                style: TextStyle(
                  fontSize: 11.5,
                  color: p.muted,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: widget.subiendo ? null : widget.onPickFiles,
                    icon: const Icon(Icons.upload_file_rounded, size: 14),
                    label: const Text('Elegir archivos'),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  OutlinedButton.icon(
                    onPressed: widget.subiendo ? null : widget.onPasteText,
                    icon:
                        const Icon(Icons.text_snippet_outlined, size: 14),
                    label: const Text('Pegar texto'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.borderSoft),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x4,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Página estilizada (glifo) que forma la ilustración de la drop zone.
class _GlyphPage extends StatelessWidget {
  final Color color;
  final double dx, dy, rotZ;
  final bool destacado;
  final IconData? icon;
  final Color? iconColor;
  const _GlyphPage({
    required this.color,
    this.dx = 0,
    this.dy = 0,
    this.rotZ = 0,
    this.destacado = false,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rotZ,
        child: Container(
          width: destacado ? 36 : 32,
          height: destacado ? 44 : 38,
          decoration: BoxDecoration(
            color: destacado ? p.surface : p.surface2.withValues(alpha: 0.7),
            border: Border.all(color: color, width: destacado ? 1.6 : 1),
            borderRadius: BorderRadius.circular(5),
            boxShadow: destacado ? p.subtleShadow : null,
          ),
          child: icon != null
              ? Icon(icon, size: 14, color: iconColor ?? p.muted)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      height: 2,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  }),
                ),
        ),
      ),
    );
  }
}
