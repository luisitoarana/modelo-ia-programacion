import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers.dart';

/// Consignas comunes: el grupo directo no recibe pistas ni soluciones locales.
Future<Map<String, dynamic>?> elegirTareaEstudio(
  BuildContext context, {
  required bool generar,
}) async {
  try {
    final datos = await context.read<AuthProvider>().api.tareasEstudio();
    if (!context.mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          generar
              ? 'Práctica · generación de código'
              : 'Práctica · andamiaje explicativo',
        ),
        content: SizedBox(
          width: 720,
          height: 500,
          child: ListView(
            children: [
              const Text(
                'Estas tareas practican las competencias de los tres módulos con otros datos. No son una evaluación ni se califican automáticamente.',
              ),
              for (final tarea in datos['tareas'] as List? ?? [])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Módulo ${tarea['modulo']} · ${tarea['competencia']}',
                        ),
                        SelectableText(tarea['consigna'] as String),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.copy),
                              label: const Text('Copiar consigna'),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: tarea['solicitud'] as String,
                                  ),
                                );
                                if (ctx.mounted)
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Consigna copiada'),
                                    ),
                                  );
                              },
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(
                                ctx,
                                Map<String, dynamic>.from(tarea),
                              ),
                              child: Text(
                                generar
                                    ? 'Generar código'
                                    : 'Trabajar esta tarea',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar las tareas: $e')),
      );
    return null;
  }
}
