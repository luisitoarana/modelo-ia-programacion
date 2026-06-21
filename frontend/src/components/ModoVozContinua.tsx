import { useEffect, useRef, useState } from 'react';
import { Mic, Square, Volume2 } from 'lucide-react';
import { cn } from '@/lib/cn';

// Web Speech API types — no están en lib.dom estándar, los declaramos.
type SpeechRecognition = any;
interface SpeechRecognitionEvent {
  resultIndex: number;
  results: {
    length: number;
    [i: number]: { 0: { transcript: string } };
  };
}

/**
 * Modo Voz Continua — conversación bidireccional por voz tipo ChatGPT Voice.
 *
 * Loop completo:
 *   1. STT escucha al usuario (con detección de fin por pausa de silencio).
 *   2. Cuando termina, llama a `onEnviarMensaje(textoTranscrito)`.
 *   3. El padre devuelve la respuesta del asistente vía prop `ultimaRespuesta`.
 *   4. TTS lee la respuesta en voz alta.
 *   5. Cuando termina el TTS, vuelve a escuchar automáticamente (paso 1).
 *
 * Estados visibles para el usuario:
 *   - "🎤 Te escucho..."         (escuchando)
 *   - "💭 Pensando..."           (enviando al backend)
 *   - "🔊 Respondiendo..."        (TTS hablando)
 *
 * El usuario puede pausar/reanudar con un toggle. Cuando pausa, el loop se
 * detiene en cualquier estado y vuelve solo al pulsar de nuevo.
 *
 * Limitaciones:
 *   - Requiere navegador con Web Speech API (Chrome, Edge — no Firefox).
 *   - Necesita permiso de micrófono.
 *   - VAD (Voice Activity Detection) básico por timeout de silencio.
 */

type Estado = 'esperando' | 'escuchando' | 'pensando' | 'hablando';

interface Props {
  locale: string;
  /** Callback cuando el usuario termina de hablar y queremos enviar al chat. */
  onEnviarMensaje: (texto: string) => Promise<void>;
  /** Última respuesta del asistente — el componente la leerá cuando cambie. */
  ultimaRespuesta?: string | null;
  /** Cierra el modo voz */
  onCerrar: () => void;
}

export default function ModoVozContinua({
  locale, onEnviarMensaje, ultimaRespuesta, onCerrar,
}: Props) {
  const [estado, setEstado] = useState<Estado>('esperando');
  const [transcript, setTranscript] = useState('');
  const [pausado, setPausado] = useState(false);

  const recognitionRef = useRef<SpeechRecognition | null>(null);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ultimaRespuestaProcesadaRef = useRef<string | null>(null);
  const transcriptRef = useRef('');

  // ─── Iniciar STT ───────────────────────────────────────────────
  function iniciarEscucha() {
    if (typeof window === 'undefined') return;
    const SR = (window as any).SpeechRecognition ||
               (window as any).webkitSpeechRecognition;
    if (!SR) {
      alert('Tu navegador no soporta reconocimiento de voz. Usa Chrome o Edge.');
      return;
    }
    const rec: SpeechRecognition = new SR();
    rec.lang = locale;
    rec.continuous = true;
    rec.interimResults = true;
    rec.maxAlternatives = 1;

    transcriptRef.current = '';
    setTranscript('');
    setEstado('escuchando');

    rec.onresult = (ev: SpeechRecognitionEvent) => {
      let acumulado = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        acumulado += ev.results[i][0].transcript;
      }
      transcriptRef.current = acumulado;
      setTranscript(acumulado);
      // Resetear timer de silencio cada vez que llega texto nuevo.
      programarFinPorSilencio();
    };

    rec.onerror = (e: any) => {
      console.error('[voz] error STT:', e);
      // Errores comunes: "no-speech" → solo reprogramamos.
      if (e.error === 'no-speech' || e.error === 'aborted') return;
      pararTodo();
    };

    rec.onend = () => {
      // Si el reconocedor terminó pero NO estamos en pausa ni pensando,
      // re-arrancamos automáticamente (Chrome lo corta a ~60s).
      if (!pausado && estado === 'escuchando') {
        try { rec.start(); } catch { /* noop */ }
      }
    };

    try {
      rec.start();
      recognitionRef.current = rec;
    } catch (e) {
      console.error('[voz] no se pudo iniciar STT:', e);
      setEstado('esperando');
    }
  }

  function pararEscucha() {
    if (recognitionRef.current) {
      try { recognitionRef.current.stop(); } catch { /* noop */ }
      recognitionRef.current = null;
    }
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }
  }

  // ─── VAD básico: si hay 1.5s de silencio, asumimos fin de frase ────
  function programarFinPorSilencio() {
    if (silenceTimerRef.current) clearTimeout(silenceTimerRef.current);
    silenceTimerRef.current = setTimeout(() => {
      const texto = transcriptRef.current.trim();
      if (texto.length > 2) {
        finalizarTurno(texto);
      }
    }, 1500);
  }

  // ─── Termina turno del usuario → llama al backend ──────────────
  async function finalizarTurno(texto: string) {
    pararEscucha();
    setEstado('pensando');
    try {
      await onEnviarMensaje(texto);
      // El padre actualizará `ultimaRespuesta` y el useEffect abajo
      // disparará el TTS.
    } catch (e) {
      console.error('[voz] error enviando:', e);
      setEstado('esperando');
      if (!pausado) iniciarEscucha();
    }
  }

  // ─── TTS: leer la respuesta del asistente ──────────────────────
  useEffect(() => {
    if (!ultimaRespuesta) return;
    if (ultimaRespuesta === ultimaRespuestaProcesadaRef.current) return;
    ultimaRespuestaProcesadaRef.current = ultimaRespuesta;
    if (estado !== 'pensando') return;     // solo si estamos esperando respuesta

    if (typeof window === 'undefined' || !window.speechSynthesis) {
      setEstado('esperando');
      if (!pausado) iniciarEscucha();
      return;
    }

    // Limpiamos markdown básico para que no se lea "asterisco asterisco".
    const limpio = ultimaRespuesta
      .replace(/```[\s\S]*?```/g, '. Bloque de código. ')
      .replace(/[*_`#>]+/g, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/\s+/g, ' ')
      .slice(0, 1500);

    const voiceName = window.localStorage.getItem('explicador.tts_voice') ?? '';
    const rate = parseFloat(window.localStorage.getItem('explicador.tts_rate') ?? '1.0');
    const u = new SpeechSynthesisUtterance(limpio);
    if (voiceName) {
      const v = window.speechSynthesis.getVoices().find((vc) => vc.name === voiceName);
      if (v) u.voice = v;
    }
    u.rate = rate;
    u.onend = () => {
      setEstado('esperando');
      if (!pausado) iniciarEscucha();
    };
    u.onerror = () => {
      setEstado('esperando');
      if (!pausado) iniciarEscucha();
    };
    window.speechSynthesis.cancel();
    setEstado('hablando');
    window.speechSynthesis.speak(u);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ultimaRespuesta]);

  // ─── Auto-start al montar ──────────────────────────────────────
  useEffect(() => {
    iniciarEscucha();
    return () => {
      pararTodo();
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function pararTodo() {
    pararEscucha();
    if (typeof window !== 'undefined' && window.speechSynthesis) {
      window.speechSynthesis.cancel();
    }
    setEstado('esperando');
  }

  function alternarPausa() {
    if (pausado) {
      setPausado(false);
      iniciarEscucha();
    } else {
      setPausado(true);
      pararTodo();
    }
  }

  function salir() {
    pararTodo();
    onCerrar();
  }

  // ─── UI ─────────────────────────────────────────────────────────
  const colorPorEstado = {
    esperando: 'border-border-soft bg-surface',
    escuchando: 'border-primary bg-primary-soft/30',
    pensando: 'border-accent bg-accent-soft/30',
    hablando: 'border-success bg-success/10',
  }[estado];

  const textoEstado = {
    esperando: pausado ? '⏸ Pausado' : 'Listo',
    escuchando: '🎤 Te escucho...',
    pensando: '💭 Pensando...',
    hablando: '🔊 Respondiendo...',
  }[estado];

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className={cn(
        'relative flex w-full max-w-md flex-col items-center rounded-3xl border-2 px-8 py-12 shadow-elevated transition-colors',
        colorPorEstado,
      )}>
        {/* Bolita pulsante */}
        <div className="relative mb-6 flex h-32 w-32 items-center justify-center">
          <div className={cn(
            'absolute inset-0 rounded-full transition-all',
            estado === 'escuchando' && 'animate-ping bg-primary/30',
            estado === 'pensando' && 'animate-pulse bg-accent/30',
            estado === 'hablando' && 'animate-pulse bg-success/30',
          )} />
          <div className={cn(
            'relative flex h-24 w-24 items-center justify-center rounded-full transition-colors',
            estado === 'escuchando' && 'bg-primary text-primary-foreground',
            estado === 'pensando' && 'bg-accent text-white',
            estado === 'hablando' && 'bg-success text-white',
            estado === 'esperando' && 'bg-surface-2 text-muted',
          )}>
            {estado === 'escuchando' && <Mic size={36} />}
            {estado === 'hablando' && <Volume2 size={36} />}
            {(estado === 'esperando' || estado === 'pensando') && <Mic size={36} />}
          </div>
        </div>

        <h2 className="mb-2 font-serif text-2xl text-text">{textoEstado}</h2>
        {transcript && estado === 'escuchando' && (
          <p className="mb-4 text-center text-sm text-muted italic">"{transcript}"</p>
        )}
        {!transcript && (
          <p className="mb-4 text-center text-sm text-muted">
            Habla con normalidad. Detecto cuándo terminas y te respondo.
          </p>
        )}

        <div className="mt-4 flex w-full gap-2">
          <button
            onClick={alternarPausa}
            className="flex-1 rounded-xl border border-border-soft bg-surface px-4 py-2.5 text-sm font-medium text-text hover:bg-surface-2"
          >
            {pausado ? '▶ Reanudar' : '⏸ Pausar'}
          </button>
          <button
            onClick={salir}
            className="flex-1 rounded-xl bg-danger px-4 py-2.5 text-sm font-medium text-white hover:opacity-90"
          >
            <Square size={14} className="mr-1 inline" />
            Terminar
          </button>
        </div>

        <p className="mt-3 text-center text-[11px] text-subtle">
          Requiere micrófono · Chrome/Edge recomendado
        </p>
      </div>
    </div>
  );
}
