import 'package:flutter/material.dart';

import '../../providers.dart';
import '../../theme.dart';
import 'settings_common.dart';

class AparienciaSection extends StatelessWidget {
  final ThemeProvider theme;
  const AparienciaSection({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Apariencia',
          descripcion: 'Personaliza cómo se ve el sistema.',
        ),
        const SettingsSubtitulo(titulo: 'Tema'),
        SettingsFila(
          label: 'Modo de color',
          descripcion:
              'Claro y Oscuro son fijos. Auto sigue el sistema operativo.',
          control: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 14),
                  label: Text('Claro')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 14),
                  label: Text('Oscuro')),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.computer_outlined, size: 14),
                  label: Text('Auto')),
            ],
            selected: {theme.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => theme.setMode(s.first),
          ),
        ),
        const SettingsSubtitulo(titulo: 'Paleta de colores'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Cada paleta cambia toda la app. Se aplica a los modos claro y oscuro.',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.2,
          children: Paletas.todas.values.map((pal) {
            final activa = theme.paletaId == pal.id;
            return _PaletaCard(
              paleta: pal,
              activa: activa,
              onTap: () => theme.setPaleta(pal.id),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PaletaCard extends StatefulWidget {
  final PaletaInfo paleta;
  final bool activa;
  final VoidCallback onTap;
  const _PaletaCard({
    required this.paleta,
    required this.activa,
    required this.onTap,
  });

  @override
  State<_PaletaCard> createState() => _PaletaCardState();
}

class _PaletaCardState extends State<_PaletaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.activa
                ? p.primary.withValues(alpha: 0.08)
                : (_hover ? p.surface2 : p.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.activa ? p.primary : p.borderSoft,
              width: widget.activa ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                height: 36,
                child: Stack(
                  children: [
                    for (var i = 0; i < widget.paleta.swatches.length; i++)
                      Positioned(
                        left: (i * 18).toDouble(),
                        top: 4,
                        child: Container(
                          height: 28,
                          width: 28,
                          decoration: BoxDecoration(
                            color: widget.paleta.swatches[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: p.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.paleta.nombre,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: p.text,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(widget.paleta.descripcion,
                        style: TextStyle(
                            fontSize: 11.5, color: p.subtle, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (widget.activa) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle, size: 16, color: p.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
