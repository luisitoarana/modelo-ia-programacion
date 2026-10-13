import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import '../onboarding.dart';
import 'settings_common.dart';

class AyudaSection extends StatelessWidget {
  final Usuario? usuario;
  const AyudaSection({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Ayuda',
          descripcion: 'Recursos para aprovechar al máximo el sistema.',
        ),
        _BotonVerTour(),
        const SizedBox(height: 8),
        const _TarjetaAyuda(
          icono: Icons.menu_book,
          titulo: 'Guía del asistente',
          descripcion:
              'Cómo hacer mejores preguntas, modo profesor, adjuntos.',
        ),
        const SizedBox(height: 8),
        const _TarjetaAyuda(
          icono: Icons.email_outlined,
          titulo: 'Reportar un problema',
          descripcion: 'Envía un correo describiendo qué pasó.',
        ),
        const SizedBox(height: 8),
        const _TarjetaAyuda(
          icono: Icons.info_outline,
          titulo: 'Sobre Explicador IA',
          descripcion:
              'LLM educativo entrenado desde cero para enseñanza de Python.',
        ),
      ],
    );
  }
}

class _TarjetaAyuda extends StatefulWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  const _TarjetaAyuda({
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  @override
  State<_TarjetaAyuda> createState() => _TarjetaAyudaState();
}

class _TarjetaAyudaState extends State<_TarjetaAyuda> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hover ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hover ? p.border : p.borderSoft),
        ),
        child: Row(
          children: [
            Icon(widget.icono, size: 16, color: p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.titulo,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: p.text,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(widget.descripcion,
                      style: TextStyle(
                          fontSize: 12, color: p.muted, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: p.subtle),
          ],
        ),
      ),
    );
  }
}

class _BotonVerTour extends StatefulWidget {
  @override
  State<_BotonVerTour> createState() => _BotonVerTourState();
}

class _BotonVerTourState extends State<_BotonVerTour> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => showOnboarding(context),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hover
                ? p.primary.withValues(alpha: 0.12)
                : p.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? p.primary : p.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: p.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ver el tour de bienvenida',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: p.text,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      '5 slides con las funciones clave. 30 segundos.',
                      style: TextStyle(
                          fontSize: 12, color: p.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 14, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}
