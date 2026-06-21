import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers.dart';
import '../services/tts_service.dart';
import '../theme.dart';

/// Modo Voz Continua para desktop — equivalente Flutter del componente web.
///
/// Loop bidireccional:
///   1. STT escucha (con detección de silencio).
///   2. Al detectar fin de frase → manda al backend vía ChatProvider.enviar().
///   3. Cuando llega la respuesta del asistente → TTS la lee en voz alta.
///   4. Cuando termina el TTS → vuelve a escuchar.
///
/// El usuario puede pausar/reanudar y salir en cualquier momento.
class ModoVozContinua extends StatefulWidget {
  /// Locale STT, ej 'es-ES'. Si null, usa el idioma de Settings.
  final String? locale;
  final VoidCallback onCerrar;
  const ModoVozContinua({
    super.key,
    this.locale,
    required this.onCerrar,
  });

  @override
  State<ModoVozContinua> createState() => _ModoVozContinuaState();
}

enum _EstadoVoz { esperando, escuchando, pensando, hablando }

class _ModoVozContinuaState extends State<ModoVozContinua> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  Timer? _silencioTimer;
  bool _pausado = false;
  bool _sttInicializado = false;
  String _transcript = '';
  _EstadoVoz _estado = _EstadoVoz.esperando;

  // Para detectar respuesta nueva del asistente
  int _ultimoConteoMensajes = 0;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _detenerTodo();
    super.dispose();
  }

  Future<void> _inicializar() async {
    _ultimoConteoMensajes = context.read<ChatProvider>().mensajes.length;
    final ok = await _speech.initialize(
      onError: (e) => debugPrint('[voz] error stt: $e'),
      onStatus: (s) => debugPrint('[voz] stt status: $s'),
    );
    _sttInicializado = ok;
    if (!ok) {
      _mostrarSnack('No se pudo iniciar el micrófono.');
      return;
    }
    _iniciarEscucha();
  }

  void _iniciarEscucha() {
    if (!_sttInicializado || _pausado) return;
    setState(() {
      _estado = _EstadoVoz.escuchando;
      _transcript = '';
    });
    final locale = widget.locale ??
        _idiomaALocale(context.read<SettingsProvider>().idioma);
    _speech.listen(
      onResult: (res) {
        setState(() => _transcript = res.recognizedWords);
        _resetSilencioTimer();
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: locale,
      listenMode: stt.ListenMode.dictation,
    );
    _resetSilencioTimer();
  }

  /// Si pasa 1.5s sin nuevos resultados, asumimos fin de frase.
  void _resetSilencioTimer() {
    _silencioTimer?.cancel();
    _silencioTimer = Timer(const Duration(milliseconds: 1500), () {
      final texto = _transcript.trim();
      if (texto.length > 2) {
        _finalizarTurno(texto);
      }
    });
  }

  Future<void> _finalizarTurno(String texto) async {
    _silencioTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (!mounted) return;
    setState(() => _estado = _EstadoVoz.pensando);
    final chat = context.read<ChatProvider>();
    try {
      // Si no hay conversación activa, ChatProvider.enviar() la crea internamente.
      await chat.enviar(texto);
      // Esperamos a que llegue el nuevo mensaje del asistente.
      await _esperarRespuestaYHablar(chat);
    } catch (e) {
      debugPrint('[voz] error enviar: $e');
      if (!mounted) return;
      setState(() => _estado = _EstadoVoz.esperando);
      if (!_pausado) _iniciarEscucha();
    }
  }

  Future<void> _esperarRespuestaYHablar(ChatProvider chat) async {
    // Polling muy simple: revisamos si ya creció `mensajes` con un mensaje
    // del asistente. Timeout 30s.
    final t0 = DateTime.now();
    while (DateTime.now().difference(t0).inSeconds < 30) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      if (chat.mensajes.length > _ultimoConteoMensajes) {
        final ultimo = chat.mensajes.last;
        if (!ultimo.esUsuario &&
            ultimo.id != 'tmp' &&
            ultimo.id != 'err') {
          _ultimoConteoMensajes = chat.mensajes.length;
          await _hablarRespuesta(ultimo.contenido);
          return;
        }
      }
    }
    // Timeout
    if (!mounted) return;
    setState(() => _estado = _EstadoVoz.esperando);
    if (!_pausado) _iniciarEscucha();
  }

  Future<void> _hablarRespuesta(String texto) async {
    if (!mounted) return;
    setState(() => _estado = _EstadoVoz.hablando);
    final settings = context.read<SettingsProvider>();
    try {
      await TtsService.instance.speak(
        texto,
        velocidad: settings.ttsVelocidad,
        voz: settings.ttsVoz,
        idioma: settings.idioma.startsWith('es') ? 'es-ES' : 'en-US',
      );
      // El TTS de flutter_tts no nos avisa cuando termina si
      // awaitSpeakCompletion=false. Estimamos por longitud.
      final ms = (texto.length * 60).clamp(2000, 25000);
      await Future<void>.delayed(Duration(milliseconds: ms));
    } catch (e) {
      debugPrint('[voz] error tts: $e');
    }
    if (!mounted) return;
    setState(() => _estado = _EstadoVoz.esperando);
    if (!_pausado) _iniciarEscucha();
  }

  void _detenerTodo() {
    _silencioTimer?.cancel();
    if (_speech.isListening) {
      _speech.stop();
    }
    TtsService.instance.stop();
  }

  void _alternarPausa() {
    if (_pausado) {
      setState(() => _pausado = false);
      _iniciarEscucha();
    } else {
      setState(() => _pausado = true);
      _detenerTodo();
      setState(() => _estado = _EstadoVoz.esperando);
    }
  }

  void _salir() {
    _detenerTodo();
    widget.onCerrar();
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _idiomaALocale(String codigo) {
    if (codigo.startsWith('es')) return 'es_ES';
    if (codigo.startsWith('en')) return 'en_US';
    return 'es_ES';
  }

  // ─── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (color, icono, texto) = switch (_estado) {
      _EstadoVoz.esperando => (
          _pausado ? p.muted : p.text.withValues(alpha: 0.7),
          Icons.mic_none,
          _pausado ? '⏸  Pausado' : 'Listo',
        ),
      _EstadoVoz.escuchando => (p.primary, Icons.mic, '🎤  Te escucho...'),
      _EstadoVoz.pensando => (AppColors.warning, Icons.psychology, '💭  Pensando...'),
      _EstadoVoz.hablando => (AppColors.success, Icons.volume_up, '🔊  Respondiendo...'),
    };

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Card(
        color: p.surface,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bolita pulsante
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icono, size: 56, color: color),
              ),
              const SizedBox(height: 22),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 18, color: p.text, fontWeight: FontWeight.w600,
                ),
              ),
              if (_transcript.isNotEmpty &&
                  _estado == _EstadoVoz.escuchando) ...[
                const SizedBox(height: 10),
                Text(
                  '"$_transcript"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13, color: p.muted, fontStyle: FontStyle.italic,
                  ),
                ),
              ] else if (_estado == _EstadoVoz.esperando && !_pausado) ...[
                const SizedBox(height: 10),
                Text(
                  'Habla con normalidad.\nDetecto cuándo terminas y te respondo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _alternarPausa,
                      icon: Icon(
                        _pausado ? Icons.play_arrow : Icons.pause,
                        size: 16,
                      ),
                      label: Text(_pausado ? 'Reanudar' : 'Pausar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salir,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('Terminar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Requiere micrófono · STT del sistema',
                style: TextStyle(fontSize: 10.5, color: p.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
