import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme.dart';

/// Servicio de reconocimiento de voz (voz → texto) con resultados en
/// TIEMPO REAL (cada palabra reconocida se emite mientras hablas).
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  bool get escuchando => _speech.isListening;

  Future<bool> _asegurar({
    void Function(String estado)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows || Platform.isLinux) return false;
    } catch (_) {
      return false;
    }
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (e) => onError?.call(e),
        onStatus: (s) => onStatus?.call(s),
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  Future<bool> iniciar(
    void Function(String palabras, bool finalResult) onPalabras, {
    String localeId = 'es_ES',
    void Function(String estado)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    if (!await _asegurar(onStatus: onStatus, onError: onError)) return false;
    await _speech.listen(
      onResult: (r) => onPalabras(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
      pauseFor: const Duration(seconds: 5),
      listenFor: const Duration(minutes: 2),
    );
    return true;
  }

  Future<void> detener() => _speech.stop();
}

/// Botón de micrófono que dicta al [controller].
///
/// La transcripción se actualiza en VIVO mientras el usuario habla
/// (resultados parciales), igual que en la versión web. Si la API se
/// detiene sola por silencio prolongado, el icono vuelve a "mic_none"
/// para indicarlo.
class MicButton extends StatefulWidget {
  final TextEditingController controller;
  final String localeId;
  final double size;

  const MicButton({
    super.key,
    required this.controller,
    this.localeId = 'es_ES',
    this.size = 20,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  final VoiceService _voz = VoiceService();
  bool _escuchando = false;
  String _base = '';

  void _aplicarTranscripcion(String palabras, bool finalResult) {
    // La engine devuelve `recognizedWords` con TODO lo reconocido desde
    // el inicio del listen — no es incremental, es acumulativo. Por eso
    // simplemente pegamos al texto base que había antes de empezar.
    final separador = _base.isEmpty ? '' : ' ';
    final texto = '$_base$separador$palabras';
    widget.controller.text = texto;
    widget.controller.selection =
        TextSelection.collapsed(offset: texto.length);
    // Si fue resultado final y la engine se va a detener sola, congelamos
    // ese trozo en _base para que la siguiente "ronda" lo respete.
    if (finalResult) {
      _base = texto;
    }
  }

  Future<void> _toggle() async {
    if (_escuchando) {
      await _voz.detener();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    _base = widget.controller.text.trim();
    final ok = await _voz.iniciar(
      _aplicarTranscripcion,
      localeId: widget.localeId,
      onStatus: (estado) {
        // Cuando la engine termina por silencio o timeout, el estado pasa
        // a "notListening" / "done". Actualizamos el icono.
        if (!mounted) return;
        if (estado == 'notListening' || estado == 'done') {
          if (_escuchando) setState(() => _escuchando = false);
        }
      },
      onError: (e) {
        if (!mounted) return;
        if (_escuchando) setState(() => _escuchando = false);
        // Solo mostramos error visible si NO es el típico "no-match" o
        // "no-speech" (que pasan al quedarse callado un rato — ruido normal).
        final errId = e.errorMsg;
        if (errId != 'error_no_match' && errId != 'error_speech_timeout') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Micrófono: $errId'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
    if (ok) {
      if (mounted) setState(() => _escuchando = true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.mic_none_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Platform.isWindows
                      ? '🎤 Dictado por voz en Windows: Presiona la combinación de teclas "Win + H" para dictar directamente con el motor de voz de Windows.'
                      : 'Micrófono no disponible. Revisa los permisos del sistema.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Tooltip(
      message: _escuchando
          ? 'Detener dictado (escuchando…)'
          : 'Dictar por voz',
      child: IconButton(
        onPressed: _toggle,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            _escuchando ? Icons.mic : Icons.mic_none,
            key: ValueKey(_escuchando),
            size: widget.size,
            color: _escuchando ? AppColors.danger : p.muted,
          ),
        ),
      ),
    );
  }
}
