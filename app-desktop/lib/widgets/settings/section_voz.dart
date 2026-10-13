import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers.dart';
import '../../services/tts_service.dart';
import '../../theme.dart';
import 'settings_common.dart';

class VozSection extends StatefulWidget {
  const VozSection({super.key});

  @override
  State<VozSection> createState() => _VozSectionState();
}

class _VozSectionState extends State<VozSection> {
  List<Map<String, String>> _voces = [];

  @override
  void initState() {
    super.initState();
    _cargarVoces();
  }

  Future<void> _cargarVoces() async {
    final voces = await TtsService.instance.voicesDisponibles();
    if (mounted) setState(() => _voces = voces);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final settings = context.watch<SettingsProvider>();
    final idiomaTts = settings.idioma.startsWith('es')
        ? 'es'
        : settings.idioma.substring(0, 2);
    final vocesFiltradas =
        _voces.where((v) => v['locale']!.startsWith(idiomaTts)).toList();
    final vocesParaMostrar =
        vocesFiltradas.isNotEmpty ? vocesFiltradas : _voces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Voz',
          descripcion: 'Dictado por voz y lectura de respuestas.',
        ),
        const SettingsSubtitulo(titulo: 'Dictado por voz (entrada)'),
        const SettingsFila(
          label: 'Estado',
          descripcion:
              'El botón del micrófono en el composer ya está funcional. Usa el idioma del asistente.',
          control: SettingsBadgeEstado(
              label: 'Disponible', color: AppColors.success),
        ),
        const SettingsSubtitulo(titulo: 'Síntesis de voz (salida)'),
        SettingsFila(
          label: 'Leer respuestas en voz alta',
          descripcion:
              'Cuando el asistente responde, también lo lee con la voz seleccionada.',
          control: SettingsSwitch(
            value: settings.ttsHabilitado,
            onChanged: settings.setTts,
          ),
        ),
        SettingsFila(
          label: 'Voz',
          descripcion:
              '${vocesParaMostrar.length} voces disponibles en tu sistema para el idioma actual.',
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
                child: DropdownButton<String?>(
                  value: settings.ttsVoz,
                  dropdownColor: p.surface,
                  isExpanded: true,
                  style: TextStyle(color: p.text, fontSize: 13),
                  icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Predeterminada del sistema',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                    ...vocesParaMostrar.map((v) => DropdownMenuItem<String?>(
                          value: v['name'],
                          child: Text(
                            '${v['name']} (${v['locale']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: settings.setTtsVoz,
                ),
              ),
            ),
          ),
        ),
        SettingsFila(
          label: 'Velocidad de lectura',
          descripcion:
              '${(settings.ttsVelocidad * 2).toStringAsFixed(1)}× — más bajo = más lento.',
          control: SizedBox(
            width: 220,
            child: Slider(
              value: settings.ttsVelocidad,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              activeColor: p.primary,
              onChanged: settings.setTtsVelocidad,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            TtsService.instance.speak(
              'Hola, soy tu asistente. Esta es una prueba de voz.',
              velocidad: settings.ttsVelocidad,
              voz: settings.ttsVoz,
              idioma: settings.idioma.startsWith('es') ? 'es-ES' : 'en-US',
            );
          },
          icon: const Icon(Icons.volume_up, size: 15),
          label: const Text('Probar voz'),
        ),
      ],
    );
  }
}
