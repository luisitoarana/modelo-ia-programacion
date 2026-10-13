import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme.dart';
import 'settings_common.dart';

class ExportarSection extends StatefulWidget {
  const ExportarSection({super.key});

  @override
  State<ExportarSection> createState() => _ExportarSectionState();
}

class _ExportarSectionState extends State<ExportarSection> {
  List<ConversacionResumen> _conversaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final api = context.read<AuthProvider>().api;
      final list = await api.listarConversaciones();
      if (mounted) {
        setState(() {
          _conversaciones = list;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _toMarkdown(String titulo, List<Mensaje> mensajes) {
    final buf = StringBuffer();
    buf.writeln('# $titulo');
    buf.writeln();
    buf.writeln('_Exportado el ${DateTime.now()}_');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    for (final m in mensajes) {
      if (m.id == 'tmp' || m.id == 'err') continue;
      final rol = m.esUsuario ? 'Tú' : 'Asistente';
      buf.writeln('### $rol');
      buf.writeln();
      buf.writeln(m.contenido);
      buf.writeln();
    }
    return buf.toString();
  }

  Future<void> _exportar(ConversacionResumen c) async {
    final api = context.read<AuthProvider>().api;
    try {
      final mensajes = await api.obtenerMensajes(c.id);
      final md = _toMarkdown(c.titulo, mensajes);
      var nombre = c.titulo
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (nombre.length > 60) nombre = nombre.substring(0, 60);
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar conversación',
        fileName: '${nombre.isEmpty ? "chat" : nombre}.md',
        bytes: Uint8List.fromList(md.codeUnits),
      );
      if (ruta != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Guardado en $ruta')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Exportar',
          descripcion:
              'Descarga tus conversaciones como Markdown para guardar o citar en tu tesis.',
        ),
        const SettingsSubtitulo(titulo: 'Conversaciones disponibles'),
        if (_cargando)
          const Center(child: CircularProgressIndicator())
        else if (_conversaciones.isEmpty)
          Text('Aún no tienes conversaciones para exportar.',
              style: TextStyle(color: p.muted, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.borderSoft),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _conversaciones.take(20).length; i++) ...[
                  ListTile(
                    title: Text(
                      _conversaciones[i].titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.text),
                    ),
                    trailing: OutlinedButton.icon(
                      onPressed: () => _exportar(_conversaciones[i]),
                      icon: const Icon(Icons.download, size: 13),
                      label: const Text('.md'),
                    ),
                  ),
                  if (i != _conversaciones.take(20).length - 1)
                    Divider(height: 1, color: p.borderSoft),
                ],
                if (_conversaciones.length > 20)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '… y ${_conversaciones.length - 20} más.',
                      style: TextStyle(fontSize: 11, color: p.subtle),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
