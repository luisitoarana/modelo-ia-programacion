import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../theme.dart';
import 'pulse_dot.dart';

/// Barra de estado inferior estilo IDE moderno (VS Code / Cursor / PyCharm).
///
/// Muestra métricas vivas y telemetría de desarrollo:
///  - Conexión al backend en puerto :8765 con pulso verde activo.
///  - Versión del runtime de Python y estado del Sandbox.
///  - Nombre del modelo LLM activo y checkpoint.
///  - Base de conocimiento RAG.
///  - Atajos esenciales visibles para el estudiante.
class AppStatusBar extends StatelessWidget {
  final VistaPrincipal vista;
  final VoidCallback onAbrirPalette;
  final VoidCallback onAbrirSettings;

  const AppStatusBar({
    super.key,
    required this.vista,
    required this.onAbrirPalette,
    required this.onAbrirSettings,
  });

  String _nombreVista(VistaPrincipal v) {
    switch (v) {
      case VistaPrincipal.chat:
        return 'Chat Asistente';
      case VistaPrincipal.explicar:
        return 'Explicador';
      case VistaPrincipal.code:
        return 'Editor de Código';
      case VistaPrincipal.proyecto:
        return 'Explorador';
      case VistaPrincipal.terminal:
        return 'Terminal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const String modeloBadge = 'LLM: Asistente Python IA';
    final Color modeloColor = p.primary;

    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          // ── 1. Izquierda: Backend Online + Python Runtime ──
          Tooltip(
            message: 'Servidor FastAPI activo en http://127.0.0.1:8765',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseDot(color: p.success, size: 6.5, activo: true),
                const SizedBox(width: 6),
                Text(
                  'Backend :8765',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: p.muted,
                  ),
                ),
              ],
            ),
          ),
          _separador(p),

          // Python Runtime + Sandbox
          Tooltip(
            message: 'Entorno Python local con validador de seguridad AST',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, size: 12, color: p.primary),
                const SizedBox(width: 5),
                Text(
                  'Python 3.14 · Sandbox Seguro',
                  style: TextStyle(fontSize: 11, color: p.muted),
                ),
              ],
            ),
          ),
          _separador(p),

          // Sección activa
          Text(
            _nombreVista(vista),
            style: TextStyle(fontSize: 11, color: p.subtle),
          ),

          const Spacer(),

          // ── 2. Derecha: Modelo LLM + RAG + Atajos ──
          // Modelo LLM
          InkWell(
            onTap: onAbrirSettings,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_alt_rounded,
                      size: 13, color: modeloColor),
                  const SizedBox(width: 4),
                  Text(
                    modeloBadge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: modeloColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _separador(p),



          // Codificación
          Text(
            'UTF-8',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: p.subtle,
            ),
          ),
          _separador(p),

          // Atajos rápidos
          InkWell(
            onTap: onAbrirPalette,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                'Ctrl+K Paleta  •  Ctrl+B Barra  •  Ctrl+/ Atajos',
                style: TextStyle(
                  fontSize: 10.5,
                  color: p.subtle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _separador(AppPalette p) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: p.borderSoft,
    );
  }
}
