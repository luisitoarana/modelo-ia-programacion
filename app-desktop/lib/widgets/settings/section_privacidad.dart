import 'package:flutter/material.dart';

import '../../theme.dart';
import 'settings_common.dart';

class PrivacidadSection extends StatelessWidget {
  const PrivacidadSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SettingsTitulo(
          titulo: 'Privacidad y seguridad',
          descripcion: 'Control de tus datos y sesión.',
        ),
        SettingsFila(
          label: 'Conversaciones',
          descripcion:
              'Tus conversaciones están guardadas en la base de datos y solo tú las ves.',
          control:
              SettingsBadgeEstado(label: 'Privadas', color: AppColors.success),
        ),
        SettingsFila(
          label: 'Cifrado de credenciales',
          descripcion:
              'Las credenciales del sistema están cifradas en la BD con AES-256.',
          control:
              SettingsBadgeEstado(label: 'Activo', color: AppColors.success),
        ),
        SettingsFila(
          label: 'Filtro de contenido',
          descripcion:
              'Bloquea consultas con intención claramente maliciosa (malware, robo de credenciales).',
          control:
              SettingsBadgeEstado(label: 'Activado', color: AppColors.success),
        ),
      ],
    );
  }
}
