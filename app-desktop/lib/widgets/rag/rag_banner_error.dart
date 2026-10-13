import 'package:flutter/material.dart';

import '../../theme.dart';

/// Banner rojo con el mensaje de error y un botón X para cerrarlo.
class RagBannerError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onCerrar;
  const RagBannerError({
    super.key,
    required this.mensaje,
    required this.onCerrar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ),
          IconButton(
            onPressed: onCerrar,
            icon: const Icon(Icons.close, size: 14),
            color: AppColors.danger,
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}
