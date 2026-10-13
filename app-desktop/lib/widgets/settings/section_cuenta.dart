import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../confirm_dialog.dart';
import 'settings_common.dart';

class CuentaSection extends StatelessWidget {
  final Usuario? usuario;
  const CuentaSection({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final inicial = usuario?.nombre.isNotEmpty == true
        ? usuario!.nombre[0].toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Cuenta',
          descripcion: 'Información de tu sesión activa.',
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.borderSoft)),
          ),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: p.subtleShadow,
                ),
                child: Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(usuario?.nombre ?? '—',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    Text(usuario?.email ?? '—',
                        style: TextStyle(fontSize: 13, color: p.muted)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: p.borderSoft),
                      ),
                      child: Text(
                        _rolLabel(usuario?.rol),
                        style: TextStyle(
                          fontSize: 11,
                          color: p.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (usuario?.institucion?.isNotEmpty == true)
          SettingsFila(
            label: 'Institución',
            control: Text(usuario!.institucion!,
                style: TextStyle(fontSize: 14, color: p.text)),
          ),
        const SettingsSubtitulo(titulo: 'Sesión'),
        SettingsFila(
          label: 'Estado de la sesión',
          descripcion: 'Estás autenticado con un JWT válido.',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 6, width: 6,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text('Activa',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final confirmado = await mostrarConfirmacion(
              context,
              titulo: '¿Cerrar sesión?',
              descripcion:
                  'Vas a salir de tu cuenta. Tendrás que volver a iniciar sesión la próxima vez.',
              textoConfirmar: 'Cerrar sesión',
              tono: ConfirmTono.warning,
              icono: ConfirmIcono.logout,
            );
            if (!confirmado) return;
            if (context.mounted) {
              context.read<ChatProvider>().limpiar();
              context.read<AuthProvider>().logout();
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.logout, size: 15),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  String _rolLabel(String? r) => switch (r) {
        'administrador' => 'Administrador',
        'investigador' => 'Investigador',
        'estudiante' => 'Estudiante',
        null => '—',
        _ => r,
      };
}
