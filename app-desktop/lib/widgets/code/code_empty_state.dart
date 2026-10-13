import 'package:flutter/material.dart';

import '../../theme.dart';

/// Estado vacío del editor cuando no hay ningún archivo abierto: icono
/// terracota rodeado por dos halos, título serif "Sin archivos abiertos" y
/// dos botones — "Abrir archivo" y "Nuevo archivo".
class CodeEmptyState extends StatelessWidget {
  final VoidCallback onAbrir;
  final VoidCallback onNuevo;
  final VoidCallback? onAbrirCarpeta;
  const CodeEmptyState({
    super.key,
    required this.onAbrir,
    required this.onNuevo,
    this.onAbrirCarpeta,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      color: p.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(Icons.code_rounded,
                        size: 26, color: p.primary),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Editor de Código Python',
                style: TextStyle(
                  fontFamily: AppFonts.serifFallback.first,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abre un archivo, carga una carpeta de proyecto o crea un nuevo script.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: p.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (onAbrirCarpeta != null)
                    FilledButton.icon(
                      onPressed: onAbrirCarpeta,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.create_new_folder_outlined, size: 15),
                      label: const Text('Abrir carpeta'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onAbrir,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.borderSoft),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Abrir archivo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onNuevo,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.borderSoft),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Nuevo archivo'),
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
