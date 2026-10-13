import 'package:flutter/material.dart';

import '../../theme.dart';
import 'settings_common.dart';

class NotificacionesSection extends StatelessWidget {
  const NotificacionesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Notificaciones',
          descripcion: 'Cuándo y cómo te avisamos.',
        ),
        SettingsFila(
          label: 'Notificaciones del sistema',
          descripcion:
              'Aviso cuando termine un entrenamiento largo (próximamente).',
          control: Text('Próximamente',
              style: TextStyle(
                  fontSize: 12,
                  color: p.subtle,
                  fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }
}
