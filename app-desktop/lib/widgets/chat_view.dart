import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../screens/settings_screen.dart';
import '../services/export_service.dart';
import '../services/tts_service.dart';
import '../theme.dart';
import 'artifacts_panel.dart';
import 'fuentes_mensaje.dart';
import 'mic_button.dart';
import 'modo_voz_continua.dart';
import 'skeleton.dart';
import 'selector_proveedor.dart';

/// Un archivo adjunto al composer.
///
/// Puede ser:
///  - **texto**: archivo de código/markdown leído como string (se inyecta
///    en el cuerpo del mensaje al backend).
///  - **imagen**: bytes binarios que se envían como multipart al endpoint
///    `/mensajes-multimodal` (procesados por el procesador de visión del backend).
class _Adjunto {
  final String nombre;
  final String contenido;     // texto del archivo; '' si es imagen
  final int tamano;
  final bool esImagen;
  final Uint8List? bytes;     // solo imágenes
  final String? mimeType;     // ej: 'image/png'
  const _Adjunto(this.nombre, this.contenido, this.tamano)
      : esImagen = false, bytes = null, mimeType = null;
  const _Adjunto.imagen({
    required this.nombre,
    required Uint8List this.bytes,
    required this.tamano,
    required String this.mimeType,
  })  : esImagen = true,
        contenido = '';
}

const int _kMaxBytesAdjunto = 200 * 1024;          // 200 KB texto
const int _kMaxBytesImagen = 5 * 1024 * 1024;       // 5 MB imagen
const int _kMaxAdjuntos = 6;
const int _kMaxImagenes = 3;                         // límite backend

const _kMimesImagen = {
  'image/png', 'image/jpeg', 'image/jpg', 'image/webp',
};

String? _detectarMimeImagen(String nombreArchivo) {
  final ext = nombreArchivo.toLowerCase().split('.').last;
  switch (ext) {
    case 'png': return 'image/png';
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'webp': return 'image/webp';
  }
  return null;
}

/// Vista de chat interactiva:
///  - Mensajes del asistente sin "burbuja", como prosa.
///  - Mensajes del usuario en chip discreto a la derecha.
///  - Acciones por mensaje al pasar el cursor (copiar, regenerar, feedback).
///  - Composer flotante con sombra suave y botón terracota.
///  - Bienvenida con serif y chips de sugerencia.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _composerFocus = FocusNode();
  final List<_Adjunto> _adjuntos = [];
  // Cuenta de mensajes en la última vista para detectar "respuesta recién llegada".
  int _ultimoConteoMensajes = 0;
  // Modo Voz Continua — overlay activo.
  bool _modoVozAbierto = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// Abre el file picker, lee archivos como texto y los pone en la lista
  /// de adjuntos. Saltea binarios y los que excedan el tamaño.
  Future<void> _adjuntarArchivos() async {
    if (_adjuntos.length >= _kMaxAdjuntos) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (res == null || res.files.isEmpty) return;
      int omitidos = 0;
      for (final f in res.files) {
        if (_adjuntos.length >= _kMaxAdjuntos) {
          omitidos++;
          continue;
        }
        Uint8List? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          try {
            bytes = await File(f.path!).readAsBytes();
          } catch (_) {}
        }
        if (bytes == null) {
          omitidos++;
          continue;
        }

        // ¿Es imagen? El backend la enrutará al procesador multimodal.
        final mime = _detectarMimeImagen(f.name);
        if (mime != null) {
          final yaImagenes = _adjuntos.where((a) => a.esImagen).length;
          if (yaImagenes >= _kMaxImagenes) {
            omitidos++;
            continue;
          }
          if (bytes.length > _kMaxBytesImagen) {
            omitidos++;
            continue;
          }
          _adjuntos.add(_Adjunto.imagen(
            nombre: f.name,
            bytes: bytes,
            tamano: bytes.length,
            mimeType: mime,
          ));
          continue;
        }

        // Texto: límite + decodificación UTF-8 segura.
        if (bytes.length > _kMaxBytesAdjunto) {
          omitidos++;
          continue;
        }
        try {
          final texto = utf8.decode(bytes, allowMalformed: false);
          _adjuntos.add(_Adjunto(f.name, texto, bytes.length));
        } catch (_) {
          omitidos++; // binario no-imagen
        }
      }
      if (mounted) {
        setState(() {});
        if (omitidos > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Omitidos $omitidos archivo(s): binarios o mayores a 200 KB.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    }
  }

  void _quitarAdjunto(int i) {
    setState(() => _adjuntos.removeAt(i));
  }

  /// Construye el mensaje final concatenando los adjuntos como bloques de
  /// código markdown antes del texto del usuario, así el LLM los lee como
  /// contexto.
  String _construirMensajeFinal(String texto) {
    if (_adjuntos.isEmpty) return texto;
    final buffer = StringBuffer();
    buffer.writeln(
        'Adjunto ${_adjuntos.length} archivo(s) como contexto:');
    buffer.writeln();
    for (final a in _adjuntos) {
      final ext = a.nombre.split('.').last.toLowerCase();
      buffer.writeln('### 📎 `${a.nombre}` (${_formatoTamano(a.tamano)})');
      buffer.writeln();
      buffer.writeln('```$ext');
      buffer.writeln(a.contenido);
      buffer.writeln('```');
      buffer.writeln();
    }
    if (texto.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln(texto);
    } else {
      buffer.writeln(
          'Explícame estos archivos: qué hacen, cómo se conectan y por qué se diseñaron así.');
    }
    return buffer.toString();
  }

  String _formatoTamano(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  // Override por mensaje del toggle "buscar en web". null = usa el de Settings.
  bool? _buscarWebOverride;

  void _toggleBuscarWeb() {
    final settings = context.read<SettingsProvider>();
    final actual = _buscarWebOverride ?? settings.buscarWeb;
    setState(() => _buscarWebOverride = !actual);
  }

  void _enviar() {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty && _adjuntos.isEmpty) return;
    final mensajeFinal = _construirMensajeFinal(texto);
    _ctrl.clear();
    final adjuntosPrevios = List<_Adjunto>.from(_adjuntos);
    setState(() => _adjuntos.clear());
    final settings = context.read<SettingsProvider>();
    final buscarWeb = _buscarWebOverride ?? settings.buscarWeb;
    context.read<ChatProvider>().enviar(
          mensajeFinal,
          idioma: settings.idioma,
          buscarWeb: buscarWeb,
          proveedor: settings.proveedor,
          modoAcompanamiento: settings.modoAcompanamiento,
          nivelModulo: settings.nivelModulo,
        );
    adjuntosPrevios.length;
    _scrollAlFinal();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _regenerar() {
    final chat = context.read<ChatProvider>();
    // Busca el último mensaje del usuario y lo reenvía.
    Mensaje? ultimoUsuario;
    for (final m in chat.mensajes.reversed) {
      if (m.esUsuario) {
        ultimoUsuario = m;
        break;
      }
    }
    if (ultimoUsuario == null) return;
    final settings = context.read<SettingsProvider>();
    chat.enviar(
      ultimoUsuario.contenido,
      idioma: settings.idioma,
      buscarWeb: settings.buscarWeb,
      proveedor: settings.proveedor,
      modoAcompanamiento: settings.modoAcompanamiento,
      nivelModulo: settings.nivelModulo,
    );
    _scrollAlFinal();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final artifacts = context.watch<ArtifactsProvider>();
    final settings = context.watch<SettingsProvider>();
    final vacio = chat.mensajes.isEmpty && chat.activaId == null;

    // ── TTS: leer la última respuesta del asistente si llegó una nueva ──
    if (settings.ttsHabilitado &&
        chat.mensajes.length > _ultimoConteoMensajes &&
        !chat.enviando) {
      final ultima = chat.mensajes.last;
      if (!ultima.esUsuario && ultima.id != 'err' && ultima.id != 'tmp') {
        // Detecta estados del sistema — no leer esas respuestas largas.
        final esEstadoSistema = ultima.origenRespuesta == 'sin_configurar' ||
            ultima.origenRespuesta == 'api_error';
        if (!esEstadoSistema) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            TtsService.instance.speak(
              ultima.contenido,
              velocidad: settings.ttsVelocidad,
              voz: settings.ttsVoz,
              idioma: _idiomaATtsLocale(settings.idioma),
            );
          });
        }
      }
    }
    _ultimoConteoMensajes = chat.mensajes.length;

    final chatColumn = Container(
      color: p.bg,
      child: Column(
        children: [
          // Cabecera muy sutil con el título del chat.
          _ChatHeader(activo: chat.activaId != null, conversaciones: chat.conversaciones, activaId: chat.activaId),
          Expanded(
            child: vacio
                ? _Bienvenida(
                    nombre: auth.usuario?.nombre ?? '',
                    onSugerencia: (s) {
                      _ctrl.text = s;
                      _composerFocus.requestFocus();
                    },
                  )
                : (chat.cargandoMensajes && chat.mensajes.isEmpty)
                    // Skeletons de mensajes mientras cargan los del backend.
                    // UX más rápida que un spinner.
                    ? ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 24),
                        children: const [
                          SkeletonChatMessage(esUsuario: true),
                          SkeletonChatMessage(esUsuario: false),
                          SkeletonChatMessage(esUsuario: true),
                          SkeletonChatMessage(esUsuario: false),
                        ],
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 24),
                        itemCount:
                            chat.mensajes.length + (chat.enviando ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= chat.mensajes.length) {
                            return const _Escribiendo();
                          }
                          final m = chat.mensajes[i];
                          final esUltimoAsistente = !m.esUsuario &&
                              i == chat.mensajes.length - 1 &&
                              !chat.enviando;
                          return _MensajeWidget(
                            mensaje: m,
                            permitirRegenerar: esUltimoAsistente,
                            onRegenerar: _regenerar,
                          );
                        },
                      ),
          ),
          if (settings.esBloqueadoPostTest)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_rounded, size: 20, color: AppColors.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Modo de Evaluación Post-Test Activo: El asistente conversacional se encuentra deshabilitado para evaluar las competencias independientes de los estudiantes.',
                      style: TextStyle(fontSize: 12.5, color: p.text, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _Composer(
              controller: _ctrl,
              focus: _composerFocus,
              enviando: chat.enviando,
              onEnviar: _enviar,
              adjuntos: _adjuntos,
              onAdjuntar: _adjuntarArchivos,
              onQuitarAdjunto: _quitarAdjunto,
              buscarWeb: _buscarWebOverride ??
                  context.watch<SettingsProvider>().buscarWeb,
              onToggleBuscarWeb: _toggleBuscarWeb,
              localeId: Idiomas.localeVoz(
                context.watch<SettingsProvider>().idioma,
              ),
              onAbrirModoVoz: () => setState(() => _modoVozAbierto = true),
            ),
            const SizedBox(height: 6),
            _PieAyuda(),
          ],
        ],
      ),
    );

    // Si el panel de artifacts está abierto, dividimos en dos columnas de forma responsiva.
    final base = artifacts.abierto
        ? LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = (constraints.maxWidth * 0.42).clamp(310.0, 520.0);
              return Row(
                children: [
                  Expanded(child: chatColumn),
                  SizedBox(
                    width: panelWidth,
                    child: ArtifactsPanel(provider: artifacts),
                  ),
                ],
              );
            },
          )
        : chatColumn;

    // El overlay del modo voz se monta encima de toda la vista.
    return Stack(
      children: [
        base,
        if (_modoVozAbierto)
          Positioned.fill(
            child: ModoVozContinua(
              onCerrar: () => setState(() => _modoVozAbierto = false),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

class _ChatHeader extends StatelessWidget {
  final bool activo;
  final List<ConversacionResumen> conversaciones;
  final String? activaId;
  const _ChatHeader({
    required this.activo,
    required this.conversaciones,
    required this.activaId,
  });

  String _tituloChat(BuildContext context) {
    var titulo = 'Conversación';
    if (activaId != null) {
      final match = conversaciones.where((c) => c.id == activaId);
      if (match.isNotEmpty) titulo = match.first.titulo;
    }
    return titulo;
  }

  Future<void> _exportarMd(BuildContext context) async {
    final mensajes = context.read<ChatProvider>().mensajes;
    if (mensajes.isEmpty) return;
    final titulo = _tituloChat(context);
    try {
      final ruta = await ExportService.guardarMarkdown(titulo, mensajes);
      if (ruta != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardado en $ruta'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  Future<void> _exportarPdf(BuildContext context) async {
    final mensajes = context.read<ChatProvider>().mensajes;
    if (mensajes.isEmpty) return;
    final titulo = _tituloChat(context);
    try {
      final ruta = await ExportService.abrirComoPDF(titulo, mensajes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ruta == null
                  ? 'No se pudo abrir el navegador para guardar PDF.'
                  : 'Abriendo en el navegador. Usa Ctrl+P → Guardar como PDF.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final chat = context.watch<ChatProvider>();
    String titulo = 'Nueva conversación';
    if (activo && activaId != null) {
      final match = conversaciones.where((c) => c.id == activaId);
      if (match.isNotEmpty) titulo = match.first.titulo;
    }
    final hayMensajes = chat.mensajes.isNotEmpty && activaId != null;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: p.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (hayMensajes)
            PopupMenuButton<String>(
              tooltip: 'Exportar este chat',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              color: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: p.borderSoft),
              ),
              onSelected: (v) {
                if (v == 'md') _exportarMd(context);
                if (v == 'pdf') _exportarPdf(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'md',
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description, size: 14, color: p.muted),
                      const SizedBox(width: 10),
                      Text('Markdown (.md)',
                          style: TextStyle(fontSize: 12.5, color: p.text)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 14, color: p.muted),
                      const SizedBox(width: 10),
                      Text('PDF (vía navegador)',
                          style: TextStyle(fontSize: 12.5, color: p.text)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: p.borderSoft),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download, size: 12, color: p.muted),
                    const SizedBox(width: 5),
                    Text(
                      'Exportar',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: p.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.unfold_more, size: 11, color: p.subtle),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Bienvenida ───────────────────────────

class _Bienvenida extends StatefulWidget {
  final String nombre;
  final ValueChanged<String> onSugerencia;
  const _Bienvenida({required this.nombre, required this.onSugerencia});

  @override
  State<_Bienvenida> createState() => _BienvenidaState();
}

class _BienvenidaState extends State<_Bienvenida> {
  Future<bool>? _sinCerebroFuture;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.usuario?.rol == 'administrador') {
      _sinCerebroFuture = _verificarSinCerebro();
    }
  }

  Future<bool> _verificarSinCerebro() async {
    final api = context.read<AuthProvider>().api;
    try {
      final results = await Future.wait([
        api.estadoApiKeys().catchError((_) => <Map<String, dynamic>>[]),
        api.estadoModelo().catchError((_) => <String, dynamic>{}),
      ]);
      final keys = results[0] as List;
      final modelo = results[1] as Map;
      final hayApi = keys.any((k) =>
          k is Map &&
          (k['configurada'] == true || k['activa'] == true));
      final hayModelo = modelo['disponible'] == true;
      return !hayApi && !hayModelo;
    } catch (_) {
      return false;
    }
  }

  static const _sugerencias = <_Sugerencia>[
    _Sugerencia(
      icon: Icons.functions,
      titulo: 'Explícame qué es una función',
      detalle: 'con un ejemplo paso a paso',
    ),
    _Sugerencia(
      icon: Icons.calculate_outlined,
      titulo: 'Programa que calcule el promedio',
      detalle: 'de una lista de notas',
    ),
    _Sugerencia(
      icon: Icons.account_tree_outlined,
      titulo: 'Clase padre e hija',
      detalle: 'con herencia y polimorfismo',
    ),
    _Sugerencia(
      icon: Icons.loop,
      titulo: '¿Cómo funciona un bucle for?',
      detalle: 'iterando sobre listas y diccionarios',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final saludo = widget.nombre.isEmpty
        ? 'Hola'
        : 'Hola, ${widget.nombre.split(' ').first}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner admin: si admin y no hay cerebro configurado.
              if (_sinCerebroFuture != null)
                FutureBuilder<bool>(
                  future: _sinCerebroFuture,
                  builder: (context, snap) {
                    if (snap.data != true) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _SinCerebroBanner(),
                    );
                  },
                ),
              // Animación de entrada del título + saludo.
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 400),
                tween: Tween(begin: 0.0, end: 1.0),
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 8),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar grande centrado con gradiente terracota.
                    Container(
                      height: 56, width: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [p.primary, p.primaryHover],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: p.primary.withValues(alpha: 0.35),
                            blurRadius: 24, offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: AppSpacing.x5),
                    Text(
                      saludo,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppFonts.serifFallback.first,
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      '¿En qué te ayudo hoy con Python?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x10),
              // Cards con animación escalonada de entrada.
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.x3,
                crossAxisSpacing: AppSpacing.x3,
                childAspectRatio: 2.4,
                children: [
                  for (var i = 0; i < _sugerencias.length; i++)
                    TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 350 + i * 80),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOut,
                      builder: (_, t, child) => Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 12),
                          child: child,
                        ),
                      ),
                      child: _SugerenciaCard(
                        sugerencia: _sugerencias[i],
                        onTap: () => widget.onSugerencia(
                          '${_sugerencias[i].titulo} ${_sugerencias[i].detalle}',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner para admin: aviso de que no hay cerebro (API ni modelo).
class _SinCerebroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.warning_amber,
                size: 16, color: AppColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu sistema aún no tiene cerebro',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'No tienes API configurada ni modelo entrenado. Configura una en Settings para que el chat responda.',
                  style: TextStyle(
                      fontSize: 12, color: p.muted, height: 1.45),
                ),
                const SizedBox(height: 10),
                _BotonAccionEstado(
                  icono: Icons.key,
                  label: 'Configurar API',
                  primaria: true,
                  onTap: () => showSettings(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sugerencia {
  final IconData icon;
  final String titulo;
  final String detalle;
  const _Sugerencia({
    required this.icon,
    required this.titulo,
    required this.detalle,
  });
}

class _SugerenciaCard extends StatefulWidget {
  final _Sugerencia sugerencia;
  final VoidCallback onTap;
  const _SugerenciaCard({required this.sugerencia, required this.onTap});

  @override
  State<_SugerenciaCard> createState() => _SugerenciaCardState();
}

class _SugerenciaCardState extends State<_SugerenciaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.all(AppSpacing.x4),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover ? p.primary.withValues(alpha: 0.4) : p.borderSoft,
            ),
            boxShadow: _hover ? p.subtleShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _hover
                      ? p.primary.withValues(alpha: 0.18)
                      : p.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(widget.sugerencia.icon, size: 14, color: p.primary),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                widget.sugerencia.titulo,
                style: TextStyle(
                  fontSize: 14,
                  color: p.text,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                widget.sugerencia.detalle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: p.muted,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Mensaje ───────────────────────────

class _MensajeWidget extends StatefulWidget {
  final Mensaje mensaje;
  final bool permitirRegenerar;
  final VoidCallback onRegenerar;

  const _MensajeWidget({
    required this.mensaje,
    required this.permitirRegenerar,
    required this.onRegenerar,
  });

  @override
  State<_MensajeWidget> createState() => _MensajeWidgetState();
}

class _MensajeWidgetState extends State<_MensajeWidget> {
  bool _hover = false;
  int _feedback = 0; // 0 = ninguno, 1 = like, -1 = dislike
  bool _guardandoFeedback = false;

  /// Persiste el voto en el backend para alimentar el RLHF.
  /// Optimistic UI: si falla la API, revertimos visualmente.
  /// Si el usuario hace click en el mismo voto, lo "toggle" a 0 (sin persistir).
  Future<void> _votar(int voto) async {
    final nuevo = _feedback == voto ? 0 : voto;
    setState(() => _feedback = nuevo);
    // No persistimos toggle-off ni mensajes temporales/errores.
    if (nuevo == 0) return;
    if (widget.mensaje.id == 'tmp' || widget.mensaje.id == 'err') return;
    if (widget.mensaje.id.isEmpty) return;
    setState(() => _guardandoFeedback = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.enviarFeedback(
        mensajeId: widget.mensaje.id,
        voto: nuevo,
      );
    } catch (_) {
      // Revertir si falla — no engañar al usuario.
      if (mounted) setState(() => _feedback = 0);
    } finally {
      if (mounted) setState(() => _guardandoFeedback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final artifacts = context.watch<ArtifactsProvider>();
    final m = widget.mensaje;

    if (m.esUsuario) {
      // Burbuja del usuario: redondeada uniforme,
      // padding generoso, sin "punta" hacia el avatar (diseño limpio).
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12,
                ),
                constraints: const BoxConstraints(maxWidth: 620),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.borderSoft),
                ),
                child: SelectableText(
                  m.contenido,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14.5,
                    height: 1.55,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ¿Es un estado del sistema (sin API/modelo, error, filtro)?
    final esEstadoSistema = m.origenRespuesta == 'sin_configurar' ||
        m.origenRespuesta == 'api_error' ||
        m.origenRespuesta == 'filtro_contenido' ||
        m.origenRespuesta == 'vision_en_entrenamiento' ||
        m.origenRespuesta == 'modelo_propio_no_disponible';

    // Mensaje del asistente — sin burbuja, prosa con avatar.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 30,
              width: 30,
              decoration: BoxDecoration(
                gradient: esEstadoSistema
                    ? null
                    : LinearGradient(
                        colors: [p.primary, p.primaryHover],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: esEstadoSistema
                    ? AppColors.warning.withValues(alpha: 0.15)
                    : null,
                borderRadius: BorderRadius.circular(9),
                boxShadow: esEstadoSistema
                    ? null
                    : [
                        BoxShadow(
                          color: p.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Icon(
                esEstadoSistema
                    ? Icons.warning_amber_rounded
                    : Icons.auto_awesome_rounded,
                size: 16,
                color: esEstadoSistema ? AppColors.warning : Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (esEstadoSistema)
                    _EstadoSistemaCard(
                      origen: m.origenRespuesta!,
                      mensaje: m.contenido,
                    )
                  else
                    MarkdownBody(
                      data: m.contenido,
                      selectable: true,
                      styleSheet: _markdownStyle(context, p),
                    ),
                  if (artifacts.contarBloques(m.contenido) > 0) ...[
                    const SizedBox(height: 10),
                    _ArtifactCTA(
                      cantidad: artifacts.contarBloques(m.contenido),
                      onAbrir: () => artifacts.abrirDesdeMensaje(
                        m.contenido,
                        tituloBase: _tituloDesdeMensaje(m.contenido),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _AccionesMensaje(
                    visible: _hover || _feedback != 0,
                    permitirRegenerar: widget.permitirRegenerar,
                    feedback: _feedback,
                    onCopiar: () async {
                      await Clipboard.setData(
                          ClipboardData(text: m.contenido));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mensaje copiado al portapapeles'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    onRegenerar: widget.onRegenerar,
                    onLike: () => _votar(1),
                    onDislike: () => _votar(-1),
                  ),
                  if (m.fuentesRag.isNotEmpty || m.fuentesWeb.isNotEmpty)
                    FuentesMensaje(rag: m.fuentesRag, web: m.fuentesWeb),
                  if (m.origenRespuesta != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _origenLabel(m.origenRespuesta!),
                      style: TextStyle(fontSize: 11, color: p.subtle),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context, AppPalette p) {
    final base = Theme.of(context).textTheme;
    return MarkdownStyleSheet(
      p: base.bodyMedium?.copyWith(color: p.text, height: 1.6),
      h1: base.headlineLarge?.copyWith(color: p.text),
      h2: base.titleLarge?.copyWith(color: p.text, fontSize: 17),
      h3: base.titleLarge?.copyWith(color: p.text, fontSize: 15),
      strong: TextStyle(color: p.text, fontWeight: FontWeight.w600),
      em: TextStyle(color: p.text, fontStyle: FontStyle.italic),
      a: TextStyle(color: p.primary, decoration: TextDecoration.underline),
      blockquote: TextStyle(color: p.muted, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      listBullet: TextStyle(color: p.text),
      code: TextStyle(
        backgroundColor: p.surface2,
        fontFamily: AppFonts.monoFallback.first,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: 13,
        color: p.text,
      ),
      codeblockDecoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      codeblockPadding: const EdgeInsets.all(14),
    );
  }

  String _origenLabel(String origen) {
    return switch (origen) {
      'modelo_propio' => 'Modelo propio',
      'modelo_propio_multimodal' => 'Modelo propio multimodal',
      'api' => 'Vía API (andamio temporal)',
      'sin_configurar' => 'Sin modelo/API configurados',
      'vision_en_entrenamiento' => 'Visión en entrenamiento',
      'modelo_propio_no_disponible' => 'Modelo propio no disponible',
      _ => origen,
    };
  }
}

// ─────────────────────────── Acciones por mensaje ───────────────────────────

class _AccionesMensaje extends StatelessWidget {
  final bool visible;
  final bool permitirRegenerar;
  final int feedback;
  final VoidCallback onCopiar;
  final VoidCallback onRegenerar;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  const _AccionesMensaje({
    required this.visible,
    required this.permitirRegenerar,
    required this.feedback,
    required this.onCopiar,
    required this.onRegenerar,
    required this.onLike,
    required this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: Row(
          children: [
            _AccionIcono(
              icon: Icons.content_copy_outlined,
              tooltip: 'Copiar',
              onTap: onCopiar,
            ),
            if (permitirRegenerar)
              _AccionIcono(
                icon: Icons.refresh,
                tooltip: 'Regenerar respuesta',
                onTap: onRegenerar,
              ),
            _AccionIcono(
              icon: Icons.thumb_up_outlined,
              tooltip: 'Buena respuesta',
              activo: feedback == 1,
              activoColor: p.success,
              onTap: onLike,
            ),
            _AccionIcono(
              icon: Icons.thumb_down_outlined,
              tooltip: 'Mejorable',
              activo: feedback == -1,
              activoColor: p.danger,
              onTap: onDislike,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccionIcono extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool activo;
  final Color? activoColor;

  const _AccionIcono({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.activo = false,
    this.activoColor,
  });

  @override
  State<_AccionIcono> createState() => _AccionIconoState();
}

class _AccionIconoState extends State<_AccionIcono> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = widget.activo
        ? (widget.activoColor ?? p.primary)
        : (_hover ? p.text : p.subtle);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(widget.icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Escribiendo (streaming) ───────────────────────────

class _Escribiendo extends StatefulWidget {
  const _Escribiendo();

  @override
  State<_Escribiendo> createState() => _EscribiendoState();
}

class _EscribiendoState extends State<_Escribiendo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.primary, p.primaryHover],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: p.primary.withValues(alpha: 0.3),
                  blurRadius: 10, offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 14),
          // Burbuja con tres puntos animados de escritura.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12,
            ),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.borderSoft),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_ctrl.value + i / 3) % 1.0;
                  final opacity = 0.35 + 0.65 * (1 - (t * 2 - 1).abs());
                  return Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
                    child: Container(
                      height: 7, width: 7,
                      decoration: BoxDecoration(
                        color: p.muted.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Composer ───────────────────────────

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool enviando;
  final VoidCallback onEnviar;
  final List<_Adjunto> adjuntos;
  final VoidCallback onAdjuntar;
  final ValueChanged<int> onQuitarAdjunto;
  final bool buscarWeb;
  final VoidCallback onToggleBuscarWeb;
  final String localeId;
  /// Callback para abrir el modo Voz Continua. Null = botón oculto.
  final VoidCallback? onAbrirModoVoz;

  const _Composer({
    required this.controller,
    required this.focus,
    required this.enviando,
    required this.onEnviar,
    required this.adjuntos,
    required this.onAdjuntar,
    required this.onQuitarAdjunto,
    required this.buscarWeb,
    required this.onToggleBuscarWeb,
    required this.localeId,
    this.onAbrirModoVoz,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _enfocado = false;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _enfocado = widget.focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final tieneTexto = widget.controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.standard,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _enfocado
                    ? p.primary.withValues(alpha: 0.5)
                    : p.borderSoft,
                width: _enfocado ? 1.5 : 1,
              ),
              boxShadow: _enfocado
                  ? [
                      ...p.elevatedShadow,
                      BoxShadow(
                        color: p.primary.withValues(alpha: 0.1),
                        blurRadius: 28, spreadRadius: -4,
                      ),
                    ]
                  : p.elevatedShadow,
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Chips de archivos adjuntos
                if (widget.adjuntos.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < widget.adjuntos.length; i++)
                          _ChipAdjunto(
                            adjunto: widget.adjuntos[i],
                            onQuitar: () => widget.onQuitarAdjunto(i),
                          ),
                      ],
                    ),
                  ),
                ],
                Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    const SingleActivator(LogicalKeyboardKey.enter):
                        const _SubmitIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SubmitIntent: CallbackAction<_SubmitIntent>(
                        onInvoke: (_) {
                          widget.onEnviar();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focus,
                      minLines: 1,
                      maxLines: 8,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                          color: p.text, fontSize: 14.5, height: 1.45),
                      decoration: InputDecoration(
                        hintText:
                            'Pregúntame sobre Python… (Enter para enviar · Shift+Enter para nueva línea)',
                        hintStyle: TextStyle(color: p.subtle, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Tooltip(
                      message: widget.adjuntos.length >= _kMaxAdjuntos
                          ? 'Máximo $_kMaxAdjuntos archivos'
                          : 'Adjuntar archivos (.py, .txt, .md, .json, .yaml, .csv…)',
                      child: IconButton(
                        onPressed: widget.adjuntos.length >= _kMaxAdjuntos
                            ? null
                            : widget.onAdjuntar,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        icon: Icon(Icons.attach_file,
                            size: 18,
                            color: widget.adjuntos.isNotEmpty
                                ? p.primary
                                : p.muted),
                      ),
                    ),
                    MicButton(
                      controller: widget.controller,
                      localeId: widget.localeId,
                      size: 18,
                    ),
                    // Modo Voz Continua — diálogo bidireccional por voz.
                    if (widget.onAbrirModoVoz != null)
                      Tooltip(
                        message: 'Modo conversación por voz',
                        child: IconButton(
                          onPressed: widget.onAbrirModoVoz,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.volume_up_outlined,
                              size: 18, color: p.muted),
                        ),
                      ),
                    _BotonWeb(
                      activo: widget.buscarWeb,
                      onTap: widget.onToggleBuscarWeb,
                    ),
                    const SizedBox(width: 6),
                    SelectorProveedor(
                      api: context.read<AuthProvider>().api,
                    ),
                    const SizedBox(width: 6),
                    const _BotonModoAcompanamiento(),
                    const Spacer(),
                    if (tieneTexto || widget.enviando) ...[
                      Text(
                        '${widget.controller.text.length} car.',
                        style: TextStyle(fontSize: 11, color: p.subtle),
                      ),
                      const SizedBox(width: 10),
                    ],
                    _BotonEnviar(
                      activo: tieneTexto && !widget.enviando,
                      enviando: widget.enviando,
                      onTap: widget.onEnviar,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _BotonEnviar extends StatefulWidget {
  final bool activo;
  final bool enviando;
  final VoidCallback onTap;
  const _BotonEnviar({
    required this.activo,
    required this.enviando,
    required this.onTap,
  });

  @override
  State<_BotonEnviar> createState() => _BotonEnviarState();
}

class _BotonEnviarState extends State<_BotonEnviar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final habilitado = widget.activo;
    final bg = !habilitado
        ? p.surface3
        : (_hover ? p.primaryHover : p.primary);
    final fg = !habilitado ? p.subtle : Colors.white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: habilitado ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          width: 32,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.enviando
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: fg),
                )
              : Icon(Icons.arrow_upward, size: 17, color: fg),
        ),
      ),
    );
  }
}

class _PieAyuda extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        'Las respuestas pueden contener errores. Verifica el código antes de ejecutarlo.',
        style: TextStyle(fontSize: 11, color: p.subtle),
      ),
    );
  }
}

// ─────────────────────────── CTA de artifact ───────────────────────────

class _ArtifactCTA extends StatefulWidget {
  final int cantidad;
  final VoidCallback onAbrir;
  const _ArtifactCTA({required this.cantidad, required this.onAbrir});

  @override
  State<_ArtifactCTA> createState() => _ArtifactCTAState();
}

class _ArtifactCTAState extends State<_ArtifactCTA> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final label = widget.cantidad == 1
        ? 'Abrir código en panel'
        : 'Abrir ${widget.cantidad} bloques en panel';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onAbrir,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hover ? p.surface2 : p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover ? p.primary.withValues(alpha: 0.5) : p.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 26,
                width: 26,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.dashboard_customize_outlined,
                    size: 14, color: p.primary),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                  Text(
                    'Visualizar, copiar y guardar',
                    style: TextStyle(fontSize: 11, color: p.subtle),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward, size: 14, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Botón "Web" (toggle) ───────────────────────────

/// Pill toggle interactivo: siempre con borde visible para que
/// se vea claramente que es un control activable; el color de fondo y el
/// texto cambian a terracota cuando está activo.
class _BotonWeb extends StatefulWidget {
  final bool activo;
  final VoidCallback onTap;
  const _BotonWeb({required this.activo, required this.onTap});

  @override
  State<_BotonWeb> createState() => _BotonWebState();
}

class _BotonWebState extends State<_BotonWeb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final activo = widget.activo;
    final color = activo
        ? Colors.white
        : (_hover ? p.text : p.muted);
    final bg = activo
        ? p.primary
        : (_hover ? p.surface2 : Colors.transparent);
    final borderColor = activo
        ? p.primary
        : (_hover ? p.border : p.borderSoft);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: activo
            ? 'Búsqueda web ACTIVADA · click para desactivar'
            : 'Activar búsqueda en internet — el asistente consultará la web',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 30,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 13, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'Web',
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight:
                          activo ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (activo) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.check_circle,
                        size: 11, color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector rápido en el composer para alternar entre:
/// - "con_acompanamiento" (Andamiaje pedagógico para la tesis)
/// - "sin_acompanamiento" (Solo código directo)
class _BotonModoAcompanamiento extends StatelessWidget {
  const _BotonModoAcompanamiento();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final p = AppPalette.of(context);
    final esCon = settings.esConAcompanamiento;

    final color = esCon ? p.primary : p.muted;
    final bg = esCon ? p.primary.withValues(alpha: 0.10) : p.surface2;
    final borderColor = esCon ? p.primary.withValues(alpha: 0.35) : p.borderSoft;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: esCon
            ? 'Modo: Andamiaje Pedagógico (Explicación didáctica + variables + Big-O + código)'
            : 'Modo: Sin Acompañamiento (Solo código directo sin teoría)',
        child: InkWell(
          onTap: () {
            final nuevo = esCon ? 'sin_acompanamiento' : 'con_acompanamiento';
            settings.setModoAcompanamiento(nuevo);
          },
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  esCon ? Icons.school_outlined : Icons.code,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  esCon ? 'Andamiaje' : 'Solo Código',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: esCon ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Chip de adjunto ───────────────────────────

class _ChipAdjunto extends StatelessWidget {
  final _Adjunto adjunto;
  final VoidCallback onQuitar;
  const _ChipAdjunto({required this.adjunto, required this.onQuitar});

  IconData _icono(String nombre) {
    final ext = nombre.toLowerCase().split('.').last;
    return switch (ext) {
      'py' || 'pyw' => Icons.bolt,
      'dart' => Icons.flutter_dash,
      'js' || 'ts' || 'jsx' || 'tsx' => Icons.javascript,
      'html' => Icons.html,
      'css' => Icons.css,
      'json' || 'yml' || 'yaml' => Icons.data_object,
      'md' => Icons.article_outlined,
      'csv' || 'tsv' => Icons.table_chart_outlined,
      'txt' || 'log' => Icons.description_outlined,
      _ => Icons.attach_file,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final tamano = adjunto.tamano < 1024
        ? '${adjunto.tamano}B'
        : adjunto.tamano < 1024 * 1024
            ? '${(adjunto.tamano / 1024).toStringAsFixed(1)}KB'
            : '${(adjunto.tamano / (1024 * 1024)).toStringAsFixed(1)}MB';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: p.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Miniatura si es imagen, icono de archivo si es texto.
          if (adjunto.esImagen && adjunto.bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                adjunto.bytes!,
                width: 32, height: 32, fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 6),
          ] else ...[
            Icon(_icono(adjunto.nombre), size: 12, color: p.primary),
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              adjunto.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: p.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            adjunto.esImagen ? '📷 $tamano' : tamano,
            style: TextStyle(fontSize: 10.5, color: p.subtle),
          ),
          const SizedBox(width: 5),
          InkWell(
            onTap: onQuitar,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 11, color: p.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Tarjeta de Estado del Sistema ───────────────────────────

/// Reemplaza el mensaje markdown plano "Todavía no hay un modelo..." por una
/// tarjeta visual con CTA. Detecta el `origen_respuesta` y muestra la
/// presentación adecuada para cada tipo de estado.
class _EstadoSistemaCard extends StatelessWidget {
  final String origen;
  final String mensaje;
  const _EstadoSistemaCard({required this.origen, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final cfg = _config(origen);
    final tone = _toneColor(p, cfg.tone);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cfg.titulo,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: tone,
              fontFamily: AppFonts.serifFallback.first,
              fontFamilyFallback: AppFonts.serifFallback,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cfg.descripcion,
            style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
          ),
          if (origen == 'sin_configurar') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OpcionMini(
                    icono: Icons.psychology_outlined,
                    color: p.primary,
                    titulo: 'Modelo Propio de la Tesis',
                    descripcion: 'Inferencia neuronal local 100% offline y andamiaje pedagógico.',
                  ),
                ),
              ],
            ),
          ],
          if (origen == 'filtro_contenido') ...[
            const SizedBox(height: 10),
            MarkdownBody(
              data: mensaje,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: p.text, fontSize: 13, height: 1.55),
              ),
            ),
          ],
          if (cfg.acciones.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in cfg.acciones)
                  _BotonAccionEstado(
                    icono: a.icono,
                    label: a.label,
                    primaria: a.primaria,
                    onTap: () => a.accion(context),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  _CfgEstado _config(String origen) {
    switch (origen) {
      case 'sin_configurar':
        return _CfgEstado(
          titulo: 'El asistente aún no tiene cerebro',
          descripcion:
              'No hay un modelo propio entrenado ni una API externa configurada. Para que el chat responda necesitas una de las dos.',
          tone: 'warning',
          acciones: [
            _AccionEstado(
              icono: Icons.key,
              label: 'Configurar API',
              primaria: true,
              accion: (ctx) => showSettings(ctx),
            ),
          ],
        );
      case 'api_error':
        return _CfgEstado(
          titulo: 'No pude generar la respuesta',
          descripcion:
              'La API externa devolvió un error. Puede ser cuota agotada, clave inválida o el proveedor caído.',
          tone: 'danger',
          acciones: [
            _AccionEstado(
              icono: Icons.key,
              label: 'Revisar API',
              primaria: true,
              accion: (ctx) => showSettings(ctx),
            ),
          ],
        );
      case 'filtro_contenido':
        return _CfgEstado(
          titulo: 'Esa pregunta no la puedo asistir',
          descripcion:
              'El sistema bloqueó el contenido por su política de uso. Si era una pregunta educativa, reformulala (ver sugerencias abajo).',
          tone: 'warning',
          acciones: [],
        );
      case 'vision_en_entrenamiento':
        return _CfgEstado(
          titulo: 'El modelo de visión propio está en entrenamiento',
          descripcion:
              'Por decisión arquitectónica este sistema NO usa APIs externas para analizar imágenes (sería contradictorio con la tesis). El modelo ViT propio se entrena en local. Mientras tanto, puedes pegar el código como texto y te lo explico igual.',
          tone: 'neutral',
          acciones: [],
        );
      case 'modelo_propio_no_disponible':
        return _CfgEstado(
          titulo: 'El modelo propio no está disponible',
          descripcion:
              'Elegiste "Modelo propio" pero aún no hay un checkpoint entrenado. Entrénalo (ver docs/ENTRENAR_KAGGLE.md) o cambia a otra IA en el selector del chat.',
          tone: 'warning',
          acciones: [
            _AccionEstado(
              icono: Icons.settings,
              label: 'Cambiar IA',
              primaria: true,
              accion: (ctx) => showSettings(ctx),
            ),
          ],
        );
      default:
        return _CfgEstado(
          titulo: 'Estado del sistema',
          descripcion: mensaje,
          tone: 'neutral',
          acciones: [],
        );
    }
  }

  Color _toneColor(AppPalette p, String tone) => switch (tone) {
        'warning' => AppColors.warning,
        'danger' => AppColors.danger,
        _ => p.muted,
      };
}

class _CfgEstado {
  final String titulo;
  final String descripcion;
  final String tone;
  final List<_AccionEstado> acciones;
  _CfgEstado({
    required this.titulo,
    required this.descripcion,
    required this.tone,
    required this.acciones,
  });
}

class _AccionEstado {
  final IconData icono;
  final String label;
  final bool primaria;
  final void Function(BuildContext) accion;
  _AccionEstado({
    required this.icono,
    required this.label,
    required this.primaria,
    required this.accion,
  });
}

class _OpcionMini extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  const _OpcionMini({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.descripcion,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            descripcion,
            style: TextStyle(fontSize: 11, color: p.subtle, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _BotonAccionEstado extends StatefulWidget {
  final IconData icono;
  final String label;
  final bool primaria;
  final VoidCallback onTap;
  const _BotonAccionEstado({
    required this.icono,
    required this.label,
    required this.primaria,
    required this.onTap,
  });

  @override
  State<_BotonAccionEstado> createState() => _BotonAccionEstadoState();
}

class _BotonAccionEstadoState extends State<_BotonAccionEstado> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final bgPrim = _hover ? p.primaryHover : p.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.primaria
                ? bgPrim
                : (_hover ? p.surface2 : p.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.primaria ? bgPrim : p.borderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icono,
                size: 13,
                color: widget.primaria ? Colors.white : p.text,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: widget.primaria ? Colors.white : p.text,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                size: 11,
                color: widget.primaria ? Colors.white : p.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mapea el código de idioma del settings al locale que entiende flutter_tts.
String _idiomaATtsLocale(String codigo) {
  if (codigo.startsWith('es')) return 'es-ES';
  if (codigo.startsWith('en')) return 'en-US';
  if (codigo.startsWith('pt')) return codigo.contains('BR') ? 'pt-BR' : 'pt-PT';
  if (codigo.startsWith('zh')) return codigo.contains('TW') ? 'zh-TW' : 'zh-CN';
  return switch (codigo) {
    'fr' => 'fr-FR', 'it' => 'it-IT', 'de' => 'de-DE', 'ru' => 'ru-RU',
    'ja' => 'ja-JP', 'ko' => 'ko-KR', 'ar' => 'ar-SA', 'hi' => 'hi-IN',
    'tr' => 'tr-TR', 'nl' => 'nl-NL', 'pl' => 'pl-PL', 'id' => 'id-ID',
    'th' => 'th-TH', 'vi' => 'vi-VN',
    _ => 'es-ES',
  };
}

/// Heurística simple: usa la primera línea de texto plano como título base
/// del artifact, recortada a 40 caracteres.
String _tituloDesdeMensaje(String contenido) {
  for (final raw in contenido.split('\n')) {
    final l = raw.trim();
    if (l.isEmpty || l.startsWith('```')) continue;
    final limpio = l.replaceAll(RegExp(r'[#*_`>\-]+'), '').trim();
    if (limpio.isEmpty) continue;
    return limpio.length > 40 ? '${limpio.substring(0, 40)}…' : limpio;
  }
  return 'Código';
}
