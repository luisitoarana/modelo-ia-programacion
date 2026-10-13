import 'package:flutter/material.dart';

import '../../config.dart';
import '../../providers.dart';
import '../../services/i18n.dart';
import '../../theme.dart';
import 'settings_common.dart';

class IdiomaSection extends StatelessWidget {
  final SettingsProvider settings;
  const IdiomaSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Idioma',
          descripcion:
              'El idioma en que el asistente responde y los locales del dictado por voz.',
        ),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Esta opción cambia el idioma de las RESPUESTAS del asistente, no el idioma de la interfaz. La UI sigue en español por ahora.',
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        SettingsFila(
          label: 'Idioma del asistente',
          descripcion:
              'El chat responderá siempre en este idioma, sin importar en cuál preguntes.',
          control: SizedBox(
            width: 220,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderSoft),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.idioma,
                  dropdownColor: p.surface,
                  style: TextStyle(color: p.text, fontSize: 13),
                  isExpanded: true,
                  icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                  items: Idiomas.opciones.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) settings.setIdioma(v);
                  },
                ),
              ),
            ),
          ),
        ),
        SettingsFila(
          label: 'Idioma de la interfaz',
          descripcion:
              'Cambia labels, botones y menús del sistema. Cobertura parcial — el resto sigue en español.',
          control: SizedBox(
            width: 220,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderSoft),
              ),
              child: ValueListenableBuilder<UiLang>(
                valueListenable: I18n.instance.idioma,
                builder: (_, lang, __) => DropdownButtonHideUnderline(
                  child: DropdownButton<UiLang>(
                    value: lang,
                    dropdownColor: p.surface,
                    isExpanded: true,
                    style: TextStyle(color: p.text, fontSize: 13),
                    icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                    items: const [
                      DropdownMenuItem(value: UiLang.es, child: Text('Español')),
                      DropdownMenuItem(value: UiLang.en, child: Text('English')),
                    ],
                    onChanged: (v) {
                      if (v != null) I18n.instance.setIdioma(v);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
