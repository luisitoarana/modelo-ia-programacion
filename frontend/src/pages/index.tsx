import { FormEvent, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/router';
import ReactMarkdown from 'react-markdown';
import {
  ArrowUp, Copy, Sparkles, Loader2, RefreshCw, ThumbsUp, ThumbsDown,
  Paperclip, Mic, MicOff, X, FunctionSquare, Calculator, GitBranch, Repeat,
  FileText, FileJson, FileCode, Globe, AlertTriangle, Brain, KeyRound,
  Settings, ArrowRight, Download, Volume2, BookOpen
} from 'lucide-react';
import Link from 'next/link';
import ChatSidebar from '@/components/chat/ChatSidebar';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import ModoVozContinua from '@/components/ModoVozContinua';
import FuentesMensaje from '@/components/FuentesMensaje';
// SelectorProveedor SE OMITE INTENCIONALMENTE en la web.
// Decisión arquitectónica: la web SOLO usa el modelo propio. La elección
// multi-IA (Gemini/DeepSeek como fallback de créditos) vive únicamente
// en la app de escritorio.
import { getToken } from '@/services/api';
import { enviarFeedback, Voto } from '@/services/feedback';
import { useT } from '@/lib/i18n';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import {
  ConversacionResumen, Mensaje,
  listarConversaciones, obtenerConversacion, enviarMensaje,
  enviarMensajeConImagenes,
  mensajeRapido, eliminarConversacion
} from '@/services/chat';
import { mensajeError } from '@/lib/errors';
import { cn } from '@/lib/cn';

import { descargarMarkdown, descargarPDF } from '@/lib/exportar';
import { FileDown } from 'lucide-react';

// Tamaño máximo por adjunto y total de adjuntos.
const MAX_BYTES_ADJUNTO = 200 * 1024;
const MAX_ADJUNTOS = 6;

// ─────────────────────────── Menú Exportar ───────────────────────────

function ExportarMenu({ titulo, mensajes }: { titulo: string; mensajes: Mensaje[] }) {
  const [abierto, setAbierto] = useState(false);

  // Cierra el menú al click fuera.
  useEffect(() => {
    if (!abierto) return;
    function onClick() { setAbierto(false); }
    window.addEventListener('click', onClick);
    return () => window.removeEventListener('click', onClick);
  }, [abierto]);

  // Listener para Ctrl+K → "Exportar conversación actual" del palette
  useEffect(() => {
    function handler() {
      descargarMarkdown(titulo, mensajes);
    }
    window.addEventListener('explicador:exportar', handler);
    return () => window.removeEventListener('explicador:exportar', handler);
  }, [titulo, mensajes]);

  return (
    <div className="relative" onClick={(e) => e.stopPropagation()}>
      <button
        onClick={() => setAbierto(!abierto)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-border-soft bg-surface px-3 py-1 text-xs text-muted hover:bg-surface-2 hover:text-text transition-colors"
        title="Exportar este chat"
      >
        <Download size={12} />
        Exportar
      </button>
      {abierto && (
        <div className="absolute right-0 top-full mt-1 z-30 w-48 rounded-lg border border-border-soft bg-bg shadow-elevated overflow-hidden animate-fade-in">
          <button
            onClick={() => {
              descargarMarkdown(titulo, mensajes);
              setAbierto(false);
            }}
            className="flex w-full items-center gap-2 px-3 py-2 text-xs text-text hover:bg-surface-2 transition-colors"
          >
            <FileText size={13} className="text-muted" />
            <span className="flex-1 text-left">Markdown (.md)</span>
          </button>
          <button
            onClick={() => {
              descargarPDF(titulo, mensajes);
              setAbierto(false);
            }}
            className="flex w-full items-center gap-2 px-3 py-2 text-xs text-text hover:bg-surface-2 transition-colors border-t border-border-soft"
          >
            <FileDown size={13} className="text-muted" />
            <span className="flex-1 text-left">PDF (vía impresión)</span>
          </button>
        </div>
      )}
    </div>
  );
}

interface Adjunto {
  nombre: string;
  contenido: string;       // texto del archivo (vacío si tipo=imagen)
  tamano: number;
  tipo?: 'texto' | 'imagen';
  blob?: File;             // solo cuando tipo=imagen — el File original
  preview?: string;        // dataURL para mostrar miniatura (solo imagen)
}

export default function AsistentePage() {
  const router = useRouter();
  const { t } = useT();
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const [conversaciones, setConversaciones] = useState<ConversacionResumen[]>([]);
  const [activaId, setActivaId] = useState<string | null>(null);
  const [mensajes, setMensajes] = useState<Mensaje[]>([]);
  const [input, setInput] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [adjuntos, setAdjuntos] = useState<Adjunto[]>([]);
  // Toggle puntual de "buscar en web" — empieza tomando el valor de
  // configuracion (localStorage) y se puede cambiar por mensaje.
  const [buscarWeb, setBuscarWeb] = useState(false);
  // Proveedor de IA elegido por el usuario para este chat — persiste en LS.
  // En la web SIEMPRE se usa el modelo propio — no hay switcher.
  const proveedor = 'propio';
  // Modo Voz Continua: conversación bidireccional sin tocar el teclado.
  const [modoVoz, setModoVoz] = useState(false);
  // Diálogo de confirmación para eliminar conversación.
  const [confirmEliminar, setConfirmEliminar] = useState<{ id: string; titulo: string } | null>(null);
  const finRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!getToken()) {
      router.replace('/login');
      return;
    }
    obtenerPerfil().then(setUsuario).catch(() => router.replace('/login'));
    cargarConversaciones();
    // Lee el toggle global de Settings al cargar.
    if (typeof window !== 'undefined') {
      setBuscarWeb(window.localStorage.getItem('explicador.buscar_web') === 'true');
    }
    // Escucha atajo global Ctrl+N (lanzado por _app.tsx).
    function onNuevoChat() { nueva(); }
    window.addEventListener('explicador:nuevo-chat', onNuevoChat as any);
    return () => window.removeEventListener('explicador:nuevo-chat', onNuevoChat as any);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Si llegamos con ?conv=ID (desde otra página por el sidebar) o ?c=ID
  // (persistencia automática), abrir esa conversación.
  useEffect(() => {
    const id = router.query.conv ?? router.query.c;
    if (typeof id === 'string' && id.length > 0 && id !== activaId) {
      seleccionar(id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router.query.conv, router.query.c]);

  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [mensajes, enviando]);

  // Si TTS está activado, leer la última respuesta del asistente cuando llega.
  useEffect(() => {
    if (typeof window === 'undefined' || !('speechSynthesis' in window)) return;
    if (window.localStorage.getItem('explicador.tts') !== 'true') return;
    if (enviando) return;
    const last = mensajes[mensajes.length - 1];
    if (!last || last.rol !== 'asistente' || last.id === 'err') return;
    // Quitar marcadores markdown para que la voz no lea "asterisco asterisco"
    const limpio = last.contenido
      .replace(/```[\s\S]*?```/g, '. Bloque de código. ')
      .replace(/[*_`#>]/g, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .slice(0, 1000); // tope para no leer respuestas gigantes
    try {
      window.speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(limpio);
      const voiceName = window.localStorage.getItem('explicador.tts_voice') ?? '';
      const rate = parseFloat(window.localStorage.getItem('explicador.tts_rate') ?? '1.0');
      u.rate = rate;
      if (voiceName) {
        const v = window.speechSynthesis.getVoices().find((vc) => vc.name === voiceName);
        if (v) u.voice = v;
      }
      window.speechSynthesis.speak(u);
    } catch { /* noop */ }
  }, [mensajes, enviando]);

  useEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 220)}px`;
  }, [input]);

  async function cargarConversaciones() {
    try {
      setConversaciones(await listarConversaciones());
    } catch {
      /* noop */
    }
  }

  function nueva() {
    setActivaId(null);
    setMensajes([]);
    setInput('');
    // Limpia ?c=ID de la URL para arrancar fresco.
    if (typeof window !== 'undefined') {
      const nueva = new URL(window.location.href);
      nueva.searchParams.delete('c');
      nueva.searchParams.delete('conv');
      window.history.replaceState({}, '', nueva.toString());
    }
    inputRef.current?.focus();
  }

  async function seleccionar(id: string) {
    setActivaId(id);
    // Refleja la conversación activa en la URL para que sobreviva a
    // refrescos del navegador y a navegación entre pestañas.
    if (typeof window !== 'undefined') {
      const nueva = new URL(window.location.href);
      nueva.searchParams.set('c', id);
      window.history.replaceState({}, '', nueva.toString());
    }
    try {
      const d = await obtenerConversacion(id);
      setMensajes(d.mensajes);
    } catch {
      setMensajes([]);
    }
  }

  function pedirEliminar(id: string) {
    const conv = conversaciones.find((c) => c.id === id);
    setConfirmEliminar({ id, titulo: conv?.titulo ?? 'Conversación' });
  }

  async function eliminar(id: string) {
    await eliminarConversacion(id);
    if (id === activaId) nueva();
    cargarConversaciones();
  }

  async function regenerar() {
    // Toma el último mensaje del usuario y lo reenvía.
    const ultimoUsuario = [...mensajes].reverse().find((m) => m.rol === 'usuario');
    if (!ultimoUsuario || enviando) return;
    await enviarTexto(ultimoUsuario.contenido);
  }

  async function enviar(e: FormEvent) {
    e.preventDefault();
    const texto = input.trim();
    if ((!texto && adjuntos.length === 0) || enviando) return;
    // Separamos adjuntos de tipo imagen vs texto: las imágenes van como
    // multipart, los archivos de texto se inyectan en el cuerpo del mensaje.
    const imagenes = adjuntos.filter((a) => a.tipo === 'imagen' && a.blob);
    const adjuntosTexto = adjuntos.filter((a) => a.tipo !== 'imagen');
    const mensajeFinal = construirMensajeConAdjuntos(texto, adjuntosTexto);
    setInput('');
    setAdjuntos([]);
    await enviarTexto(mensajeFinal, imagenes.map((a) => a.blob!));
  }

  async function enviarTexto(texto: string, imagenes: File[] = []) {
    setEnviando(true);
    const optimista: Mensaje = {
      id: 'tmp-user', rol: 'usuario',
      contenido: texto + (imagenes.length
        ? `\n\n📷 ${imagenes.length} imagen(es) adjunta(s)` : ''),
      tokens_totales: 0, latencia_segundos: 0, fecha_creacion: new Date().toISOString()
    };
    setMensajes((m) => [...m, optimista]);

    const idioma =
      typeof window !== 'undefined' ? window.localStorage.getItem('explicador.idioma') ?? 'es' : 'es';
    try {
      // Si hay imágenes adjuntas, forzamos endpoint multimodal.
      // Requiere conversación existente — si no hay, creamos una con
      // mensajeRapido (sin imágenes, solo el texto inicial).
      let convoIdParaImagenes = activaId;
      if (imagenes.length && !convoIdParaImagenes) {
        const inicial = await mensajeRapido(
          'Inicio de conversación con imágenes.',
          { idioma, buscarWeb: false },
        );
        convoIdParaImagenes = inicial.conversacion_id;
        setActivaId(convoIdParaImagenes);
        if (typeof window !== 'undefined') {
          const nueva = new URL(window.location.href);
          nueva.searchParams.set('c', convoIdParaImagenes);
          window.history.replaceState({}, '', nueva.toString());
        }
      }
      const resp = imagenes.length
        ? await enviarMensajeConImagenes(convoIdParaImagenes!, texto, imagenes, { idioma, buscarWeb })
        : activaId
        ? await enviarMensaje(activaId, texto, { idioma, buscarWeb, proveedor })
        : await mensajeRapido(texto, { idioma, buscarWeb, proveedor });
      // Garantizamos que la URL refleje la conversación activa, así si
      // refrescas o cambias de pestaña tu chat sigue ahí.
      if (!activaId) {
        setActivaId(resp.conversacion_id);
        if (typeof window !== 'undefined') {
          const nueva = new URL(window.location.href);
          nueva.searchParams.set('c', resp.conversacion_id);
          window.history.replaceState({}, '', nueva.toString());
        }
      }
      setMensajes((m) => [
        ...m.filter((x) => x.id !== 'tmp-user'),
        resp.mensaje_usuario,
        resp.mensaje_asistente
      ]);
      cargarConversaciones();
    } catch (err) {
      setMensajes((m) => [
        ...m,
        {
          id: 'err', rol: 'asistente', contenido: mensajeError(err, 'No se pudo responder.'),
          tokens_totales: 0, latencia_segundos: 0, fecha_creacion: new Date().toISOString()
        }
      ]);
    } finally {
      setEnviando(false);
      inputRef.current?.focus();
    }
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      enviar(e as unknown as FormEvent);
    }
  }

  const vacio = mensajes.length === 0 && !activaId;
  const ultimoEsAsistente =
    mensajes.length > 0 && mensajes[mensajes.length - 1].rol === 'asistente' && !enviando;

  return (
    <div className="flex h-screen overflow-hidden bg-bg text-text">
      <ChatSidebar
        conversaciones={conversaciones}
        activaId={activaId}
        usuario={usuario}
        onNueva={nueva}
        onSeleccionar={seleccionar}
        onEliminar={pedirEliminar}
      />

      <ConfirmDialog
        abierto={confirmEliminar !== null}
        titulo="¿Eliminar esta conversación?"
        descripcion={`"${confirmEliminar?.titulo ?? ''}" se borrará permanentemente. Esta acción no se puede deshacer.`}
        textoConfirmar="Eliminar"
        textoCancelar="Cancelar"
        tono="danger"
        icono="eliminar"
        onConfirmar={async () => {
          if (confirmEliminar) {
            await eliminar(confirmEliminar.id);
            setConfirmEliminar(null);
          }
        }}
        onCancelar={() => setConfirmEliminar(null)}
      />

      {/* Modo Voz Continua — overlay full-screen */}
      {modoVoz && (
        <ModoVozContinua
          locale={idiomaALocale(
            typeof window !== 'undefined'
              ? window.localStorage.getItem('explicador.idioma') ?? 'es'
              : 'es'
          )}
          onEnviarMensaje={async (texto) => {
            // Reusamos el mismo flujo de envío, sin imágenes.
            await enviarTexto(texto, []);
          }}
          ultimaRespuesta={
            mensajes.length > 0 && mensajes[mensajes.length - 1].rol === 'asistente'
              ? mensajes[mensajes.length - 1].contenido
              : null
          }
          onCerrar={() => setModoVoz(false)}
        />
      )}

      <main className="flex min-w-0 flex-1 flex-col">
        {/* Header sutil del chat */}
        <header className="flex h-12 items-center justify-between border-b border-border-soft bg-bg px-6">
          <p className="truncate text-sm font-medium text-muted">
            {activaId
              ? conversaciones.find((c) => c.id === activaId)?.titulo ?? 'Conversación'
              : t('chat.nueva')}
          </p>
          {activaId && mensajes.length > 0 && (
            <ExportarMenu
              titulo={conversaciones.find((c) => c.id === activaId)?.titulo ?? 'Conversación'}
              mensajes={mensajes}
            />
          )}
        </header>

        {vacio ? (
          <Bienvenida
            usuario={usuario}
            onSugerencia={(s) => {
              setInput(s);
              inputRef.current?.focus();
            }}
            composer={
              <Composer
                input={input}
                setInput={setInput}
                enviar={enviar}
                enviando={enviando}
                inputRef={inputRef}
                onKeyDown={onKeyDown}
                adjuntos={adjuntos}
                setAdjuntos={setAdjuntos}
                buscarWeb={buscarWeb}
                setBuscarWeb={setBuscarWeb}
                onModoVoz={() => setModoVoz(true)}
              />
            }
          />
        ) : (
          <>
            <div className="flex-1 overflow-y-auto">
              <div className="mx-auto max-w-3xl px-6 py-8">
                {mensajes.map((m, i) => (
                  <MensajeItem
                    key={m.id ?? i}
                    mensaje={m}
                    esUltimoAsistente={
                      ultimoEsAsistente && i === mensajes.length - 1
                    }
                    onRegenerar={regenerar}
                  />
                ))}
                {enviando && <EscribiendoIndicador />}
                <div ref={finRef} />
              </div>
            </div>
            <div className="bg-bg">
              <div className="mx-auto max-w-3xl px-6 pb-3 pt-2">
                <Composer
                  input={input}
                  setInput={setInput}
                  enviar={enviar}
                  enviando={enviando}
                  inputRef={inputRef}
                  onKeyDown={onKeyDown}
                  adjuntos={adjuntos}
                  setAdjuntos={setAdjuntos}
                  buscarWeb={buscarWeb}
                  setBuscarWeb={setBuscarWeb}
                  onModoVoz={() => setModoVoz(true)}
                />
                <p className="mt-2 text-center text-[11px] text-subtle">
                  Las respuestas pueden contener errores. Verifica el código antes de ejecutarlo.
                </p>
              </div>
            </div>
          </>
        )}
      </main>
    </div>
  );
}

// ─────────────────────────── Bienvenida ───────────────────────────

interface SugProps {
  usuario: UsuarioPerfil | null;
  onSugerencia: (s: string) => void;
  composer: React.ReactNode;
}

function Bienvenida({ usuario, onSugerencia, composer }: SugProps) {
  const saludo = usuario ? `Hola, ${usuario.nombre.split(' ')[0]}` : 'Hola';
  const esAdmin = usuario?.rol === 'administrador';

  // Verifica si admin tiene API o modelo configurado (best-effort, sin bloquear).
  const [sinCerebro, setSinCerebro] = useState(false);
  useEffect(() => {
    if (!esAdmin) return;
    Promise.all([
      fetch('/api/v1/admin/config/api-keys', {
        headers: { Authorization: `Bearer ${getToken()}` }
      }).then((r) => r.ok ? r.json() : { keys: [] }).catch(() => ({ keys: [] })),
      fetch('/api/v1/ai/modelo-estado', {
        headers: { Authorization: `Bearer ${getToken()}` }
      }).then((r) => r.ok ? r.json() : { disponible: false }).catch(() => ({ disponible: false }))
    ]).then(([apiData, modelo]) => {
      const keysActivas = (apiData.keys || []).some((k: any) => k.activa || k.configurada);
      setSinCerebro(!keysActivas && !modelo.disponible);
    });
  }, [esAdmin]);

  return (
    <div className="flex flex-1 items-center justify-center px-6">
      <div className="w-full max-w-2xl animate-fade-in">
        {sinCerebro && (
          <div className="mb-6 rounded-2xl border border-warning/40 bg-warning/5 p-4">
            <div className="flex items-start gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-warning/15 text-warning">
                <AlertTriangle size={16} />
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-semibold text-text text-sm mb-0.5">
                  Tu sistema aún no tiene cerebro
                </h3>
                <p className="text-xs text-muted leading-relaxed mb-3">
                  No tienes API configurada ni modelo entrenado. El chat funcionará pero responderá con un aviso. Configura una API o entrena el modelo para que responda de verdad.
                </p>
                <div className="flex flex-wrap gap-2">
                  <Link
                    href="/admin"
                    className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary-hover transition-colors"
                  >
                    <KeyRound size={12} /> Configurar API <ArrowRight size={10} />
                  </Link>
                  <Link
                    href="/panel"
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-soft bg-surface px-3 py-1.5 text-xs font-medium hover:bg-surface-2 transition-colors"
                  >
                    <Brain size={12} /> Ver entrenamiento
                  </Link>
                </div>
              </div>
            </div>
          </div>
        )}
        <div className="mb-3 flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-soft">
            <Sparkles size={20} />
          </div>
          <h1 className="font-serif text-4xl text-text">{saludo}</h1>
        </div>
        <p className="mb-7 pl-[52px] text-base text-muted">
          ¿En qué te ayudo hoy con Python?
        </p>
        {composer}
        <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
          {SUGERENCIAS.map((s, i) => (
            <button
              key={s.titulo}
              onClick={() => onSugerencia(`${s.titulo} ${s.detalle}`)}
              className="group flex items-center gap-3 rounded-xl border border-border-soft bg-surface px-4 py-3 text-left transition-all hover:border-primary/40 hover:bg-surface-2 hover:shadow-soft animate-fade-in"
              style={{ animationDelay: `${i * 80}ms` }}
            >
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary-soft text-primary transition-transform group-hover:scale-110">
                <s.icon size={15} />
              </div>
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-text">{s.titulo}</p>
                <p className="truncate text-xs text-subtle">{s.detalle}</p>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

const SUGERENCIAS = [
  { titulo: 'Explícame qué es una función', detalle: 'con un ejemplo paso a paso', icon: FunctionSquare },
  { titulo: 'Programa que calcule el promedio', detalle: 'de una lista de notas', icon: Calculator },
  { titulo: 'Clase padre e hija', detalle: 'con herencia y polimorfismo', icon: GitBranch },
  { titulo: '¿Cómo funciona un bucle for?', detalle: 'iterando sobre listas y diccionarios', icon: Repeat }
];

// ─────────────────────────── Mensaje ───────────────────────────

function MensajeItem({
  mensaje,
  esUltimoAsistente,
  onRegenerar
}: {
  mensaje: Mensaje;
  esUltimoAsistente: boolean;
  onRegenerar: () => void;
}) {
  const [feedback, setFeedback] = useState<0 | 1 | -1>(0);
  const [hover, setHover] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const esUsuario = mensaje.rol === 'usuario';

  /** Persiste el voto en el backend para alimentar el RLHF.
   *  Si el usuario hace click en el mismo voto, lo "toggle" a 0
   *  (deshacer no persiste — pero el voto previo queda en la BD).
   *  Optimistic UI: actualiza el estado visual antes de la respuesta.
   */
  async function votar(voto: 1 | -1) {
    const nuevo = (feedback === voto ? 0 : voto) as 0 | 1 | -1;
    setFeedback(nuevo);
    // Solo persistimos votos efectivos (+1 / -1), no el toggle-off.
    if (nuevo === 0) return;
    // No persistir mensajes temporales o de error.
    if (mensaje.id === 'tmp' || mensaje.id === 'err' || !mensaje.id) return;
    setGuardando(true);
    try {
      await enviarFeedback({
        mensaje_id: mensaje.id,
        voto: nuevo as Voto,
      });
    } catch (_) {
      // Si falla, revertir visualmente para no engañar al usuario.
      setFeedback(0);
    } finally {
      setGuardando(false);
    }
  }

  if (esUsuario) {
    return (
      <div className="mb-6 flex justify-end">
        <div className="max-w-[80%] whitespace-pre-wrap rounded-2xl rounded-br-md border border-border-soft bg-surface-2 px-4 py-2.5 text-[15px] leading-relaxed text-text">
          {mensaje.contenido}
        </div>
      </div>
    );
  }

  // Detectar mensajes de "sistema" — el backend devolvió un texto pero
  // realmente es un estado especial que merece presentación visual.
  const esEstadoSistema =
    mensaje.origen_respuesta === 'sin_configurar' ||
    mensaje.origen_respuesta === 'api_error' ||
    mensaje.origen_respuesta === 'filtro_contenido' ||
    mensaje.origen_respuesta === 'vision_en_entrenamiento';

  if (esEstadoSistema) {
    return (
      <div className="mb-8 flex gap-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-warning/15 text-warning">
          <AlertTriangle size={16} />
        </div>
        <div className="min-w-0 flex-1">
          <EstadoSistemaCard origen={mensaje.origen_respuesta!} mensaje={mensaje.contenido} />
        </div>
      </div>
    );
  }

  return (
    <div
      className="group mb-8 flex gap-4"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-soft">
        <Sparkles size={16} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="prose-chat">
          <ReactMarkdown>{mensaje.contenido}</ReactMarkdown>
        </div>
        <div
          className={cn(
            'mt-2 flex items-center gap-1 transition-opacity',
            hover || feedback !== 0 ? 'opacity-100' : 'opacity-0'
          )}
        >
          <BtnAccion
            onClick={() => navigator.clipboard?.writeText(mensaje.contenido)}
            title="Copiar"
          >
            <Copy size={13} />
          </BtnAccion>
          {esUltimoAsistente && (
            <BtnAccion onClick={onRegenerar} title="Regenerar respuesta">
              <RefreshCw size={13} />
            </BtnAccion>
          )}
          <BtnAccion
            onClick={() => votar(1)}
            title="Buena respuesta — ayuda a entrenar el modelo"
            activo={feedback === 1}
            activoColor="text-success"
          >
            <ThumbsUp size={13} />
          </BtnAccion>
          <BtnAccion
            onClick={() => votar(-1)}
            title="Mejorable — ayuda a entrenar el modelo"
            activo={feedback === -1}
            activoColor="text-danger"
          >
            <ThumbsDown size={13} />
          </BtnAccion>
        </div>
        <FuentesMensaje
          rag={mensaje.metadata_json?.fuentes_rag}
          web={mensaje.metadata_json?.fuentes_web}
        />
        {mensaje.origen_respuesta && (
          <p className="mt-1 text-[11px] text-subtle">
            {mensaje.origen_respuesta === 'modelo_propio'
              ? 'modelo propio'
              : mensaje.origen_respuesta === 'modelo_propio_multimodal'
              ? 'modelo propio multimodal'
              : mensaje.origen_respuesta === 'api'
              ? 'vía API (andamio)'
              : mensaje.origen_respuesta}
            {mensaje.latencia_segundos ? ` · ${mensaje.latencia_segundos}s` : ''}
          </p>
        )}
      </div>
    </div>
  );
}

function BtnAccion({
  children, onClick, title, activo = false, activoColor = 'text-primary'
}: {
  children: React.ReactNode;
  onClick: () => void;
  title: string;
  activo?: boolean;
  activoColor?: string;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      className={cn(
        'rounded-md p-1.5 transition-colors',
        activo ? activoColor : 'text-subtle hover:bg-surface-2 hover:text-text'
      )}
    >
      {children}
    </button>
  );
}

function EscribiendoIndicador() {
  return (
    <div className="mb-8 flex gap-4">
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground">
        <Sparkles size={16} />
      </div>
      <div className="flex items-center gap-1.5 pt-2">
        <span className="typing-dot" />
        <span className="typing-dot" />
        <span className="typing-dot" />
      </div>
    </div>
  );
}

// ─────────────────────────── Helpers de adjuntos ───────────────────────────

function construirMensajeConAdjuntos(texto: string, adjuntos: Adjunto[]): string {
  if (adjuntos.length === 0) return texto;
  const partes: string[] = [`Adjunto ${adjuntos.length} archivo(s) como contexto:`, ''];
  for (const a of adjuntos) {
    const ext = a.nombre.split('.').pop()?.toLowerCase() ?? '';
    const kb = a.tamano < 1024 ? `${a.tamano}B` : `${(a.tamano / 1024).toFixed(1)}KB`;
    partes.push(`### 📎 \`${a.nombre}\` (${kb})`);
    partes.push('');
    partes.push('```' + ext);
    partes.push(a.contenido);
    partes.push('```');
    partes.push('');
  }
  if (texto.length > 0) {
    partes.push('---', '', texto);
  } else {
    partes.push('Explícame estos archivos: qué hacen, cómo se conectan y por qué se diseñaron así.');
  }
  return partes.join('\n');
}

function iconoArchivo(nombre: string) {
  const ext = nombre.toLowerCase().split('.').pop() ?? '';
  if (['json', 'yml', 'yaml'].includes(ext)) return FileJson;
  if (['py', 'pyw', 'dart', 'js', 'ts', 'jsx', 'tsx', 'java', 'go', 'rs', 'c', 'cpp', 'sh'].includes(ext)) return FileCode;
  return FileText;
}

// ─────────────────────────── Hook de speech recognition ───────────────────────

/** Hook que envuelve la Web Speech API. Devuelve estado + funciones. */
function useSpeechRecognition(idioma = 'es-ES', onResult?: (texto: string) => void) {
  const [escuchando, setEscuchando] = useState(false);
  const [soportado, setSoportado] = useState(true);
  const recRef = useRef<any>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) {
      setSoportado(false);
      return;
    }
    const r = new SR();
    r.lang = idioma;
    r.continuous = false;
    r.interimResults = true;
    r.onresult = (e: any) => {
      let texto = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        texto += e.results[i][0].transcript;
      }
      onResult?.(texto);
    };
    r.onend = () => setEscuchando(false);
    r.onerror = () => setEscuchando(false);
    recRef.current = r;
    return () => {
      try { r.stop(); } catch { /* noop */ }
    };
  }, [idioma, onResult]);

  function iniciar() {
    if (!recRef.current || escuchando) return;
    try { recRef.current.start(); setEscuchando(true); } catch { /* ya iniciado */ }
  }
  function detener() {
    if (!recRef.current || !escuchando) return;
    try { recRef.current.stop(); } catch { /* noop */ }
    setEscuchando(false);
  }
  function toggle() { escuchando ? detener() : iniciar(); }

  return { escuchando, soportado, iniciar, detener, toggle };
}

// ─────────────────────────── Composer ───────────────────────────

function Composer({
  input, setInput, enviar, enviando, inputRef, onKeyDown,
  adjuntos, setAdjuntos, buscarWeb, setBuscarWeb,
  onModoVoz,
}: {
  input: string;
  setInput: (v: string) => void;
  enviar: (e: FormEvent) => void;
  enviando: boolean;
  inputRef: React.RefObject<HTMLTextAreaElement | null>;
  onKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  adjuntos: Adjunto[];
  setAdjuntos: (a: Adjunto[]) => void;
  buscarWeb: boolean;
  setBuscarWeb: (v: boolean) => void;
  onModoVoz?: () => void;
}) {
  const tieneTexto = input.trim().length > 0;
  const fileInputRef = useRef<HTMLInputElement>(null);
  const baseInput = useRef('');

  // Idioma leído de localStorage (lo guarda /configuracion).
  const idioma =
    typeof window !== 'undefined' ? window.localStorage.getItem('explicador.idioma') ?? 'es' : 'es';
  const localeVoz = idiomaALocale(idioma);

  const onResultadoVoz = (texto: string) => {
    const sep = baseInput.current.length > 0 ? ' ' : '';
    setInput(baseInput.current + sep + texto);
  };
  const { escuchando, soportado, toggle } = useSpeechRecognition(localeVoz, onResultadoVoz);

  function iniciarDictado() {
    if (escuchando) {
      toggle();
      return;
    }
    baseInput.current = input.trim();
    toggle();
  }

  const MIME_IMAGEN = new Set(['image/png', 'image/jpeg', 'image/jpg', 'image/webp']);
  const MAX_BYTES_IMAGEN = 5 * 1024 * 1024;     // 5 MB (límite backend)
  const MAX_IMAGENES = 3;                         // 3 imágenes (límite backend)

  async function manejarArchivos(files: FileList | null) {
    if (!files) return;
    const nuevos: Adjunto[] = [...adjuntos];
    let omitidos = 0;
    for (const f of Array.from(files)) {
      if (nuevos.length >= MAX_ADJUNTOS) { omitidos++; continue; }

      // ¿Es imagen? Si sí, otro límite y otro flujo (no leemos como texto).
      if (MIME_IMAGEN.has(f.type)) {
        const yaImagenes = nuevos.filter((a) => a.tipo === 'imagen').length;
        if (yaImagenes >= MAX_IMAGENES) { omitidos++; continue; }
        if (f.size > MAX_BYTES_IMAGEN) { omitidos++; continue; }
        const preview = await new Promise<string>((resolve, reject) => {
          const r = new FileReader();
          r.onload = () => resolve(r.result as string);
          r.onerror = () => reject(r.error);
          r.readAsDataURL(f);
        }).catch(() => '');
        nuevos.push({
          nombre: f.name, contenido: '', tamano: f.size,
          tipo: 'imagen', blob: f, preview,
        });
        continue;
      }

      // Archivo de texto: flujo original.
      if (f.size > MAX_BYTES_ADJUNTO) { omitidos++; continue; }
      try {
        const texto = await f.text();
        if (texto.includes('\x00')) { omitidos++; continue; }
        nuevos.push({
          nombre: f.name, contenido: texto, tamano: f.size,
          tipo: 'texto',
        });
      } catch {
        omitidos++;
      }
    }
    setAdjuntos(nuevos);
    if (omitidos > 0) {
      console.warn(`${omitidos} archivo(s) omitido(s) (límites: 200KB texto, 5MB imagen, max ${MAX_IMAGENES} imgs).`);
    }
    if (fileInputRef.current) fileInputRef.current.value = '';
  }

  return (
    <form
      onSubmit={enviar}
      className="relative rounded-2xl border border-border bg-surface shadow-soft transition-all focus-within:border-primary/50"
    >
      {/* Chips de adjuntos */}
      {adjuntos.length > 0 && (
        <div className="flex flex-wrap gap-1.5 border-b border-border-soft px-3 py-2">
          {adjuntos.map((a, i) => {
            const kb = a.tamano < 1024 ? `${a.tamano}B` : `${(a.tamano / 1024).toFixed(1)}KB`;
            // Imagen: chip con miniatura + tamaño + botón quitar.
            if (a.tipo === 'imagen' && a.preview) {
              return (
                <div
                  key={`${a.nombre}-${i}`}
                  className="group relative flex items-center gap-1.5 rounded-md border border-border-soft bg-surface-2 p-1"
                  title={`${a.nombre} · ${kb}`}
                >
                  <img
                    src={a.preview}
                    alt={a.nombre}
                    className="h-14 w-14 rounded object-cover"
                  />
                  <div className="flex flex-col pr-1">
                    <span className="max-w-[140px] truncate text-[11.5px] font-medium text-text">{a.nombre}</span>
                    <span className="text-[10.5px] text-subtle">📷 imagen · {kb}</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => setAdjuntos(adjuntos.filter((_, j) => j !== i))}
                    className="absolute -right-1 -top-1 rounded-full bg-bg p-0.5 text-subtle opacity-0 transition-opacity group-hover:opacity-100 hover:text-danger"
                    aria-label="Quitar imagen"
                  >
                    <X size={11} />
                  </button>
                </div>
              );
            }
            // Texto: chip clásico.
            const Icono = iconoArchivo(a.nombre);
            return (
              <div
                key={`${a.nombre}-${i}`}
                className="flex items-center gap-1.5 rounded-md border border-border-soft bg-surface-2 px-2 py-1"
              >
                <Icono size={12} className="text-primary" />
                <span className="max-w-[160px] truncate text-[12px] font-medium text-text">{a.nombre}</span>
                <span className="text-[10.5px] text-subtle">{kb}</span>
                <button
                  type="button"
                  onClick={() => setAdjuntos(adjuntos.filter((_, j) => j !== i))}
                  className="ml-0.5 rounded text-subtle hover:text-text"
                  aria-label="Quitar adjunto"
                >
                  <X size={11} />
                </button>
              </div>
            );
          })}
        </div>
      )}

      <textarea
        ref={inputRef}
        value={input}
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={onKeyDown}
        rows={1}
        placeholder={
          escuchando
            ? 'Escuchando… habla ahora'
            : 'Pregúntame sobre Python… (Enter para enviar · Shift+Enter para nueva línea)'
        }
        className="w-full resize-none rounded-2xl bg-transparent px-4 pt-3.5 pb-1 text-[15px] leading-relaxed text-text placeholder:text-subtle focus:outline-none"
        style={{ minHeight: 52, maxHeight: 220 }}
      />

      <input
        ref={fileInputRef}
        type="file"
        multiple
        hidden
        accept=".py,.pyw,.dart,.js,.mjs,.ts,.jsx,.tsx,.json,.yml,.yaml,.html,.htm,.xml,.css,.scss,.sql,.sh,.ps1,.md,.markdown,.txt,.log,.csv,.tsv,.c,.cpp,.h,.hpp,.java,.go,.rs,.kt,.ini,.toml,.env,image/png,image/jpeg,image/webp"
        onChange={(e) => manejarArchivos(e.target.files)}
      />

      <div className="flex items-center gap-1 px-2 pb-2">
        <button
          type="button"
          title={
            adjuntos.length >= MAX_ADJUNTOS
              ? `Máximo ${MAX_ADJUNTOS} archivos`
              : 'Adjuntar código (.py, .json, .md…) o imágenes (.png, .jpg) — la IA las analizará'
          }
          disabled={adjuntos.length >= MAX_ADJUNTOS}
          onClick={() => fileInputRef.current?.click()}
          className={cn(
            'rounded-md p-1.5 transition-colors',
            adjuntos.length > 0
              ? 'text-primary hover:bg-surface-2'
              : 'text-muted hover:bg-surface-2 hover:text-text',
            adjuntos.length >= MAX_ADJUNTOS && 'opacity-50 cursor-not-allowed'
          )}
        >
          <Paperclip size={16} />
        </button>
        <button
          type="button"
          title={
            !soportado
              ? 'Tu navegador no soporta dictado por voz (usa Chrome o Edge)'
              : escuchando
              ? 'Detener dictado'
              : 'Dictar por voz'
          }
          disabled={!soportado}
          onClick={iniciarDictado}
          className={cn(
            'rounded-md p-1.5 transition-colors',
            !soportado && 'opacity-40 cursor-not-allowed',
            escuchando
              ? 'text-danger animate-pulse'
              : 'text-muted hover:bg-surface-2 hover:text-text'
          )}
        >
          {escuchando ? <MicOff size={16} /> : <Mic size={16} />}
        </button>
        {/* Modo Voz Continua — diálogo bidireccional como ChatGPT Voice */}
        {onModoVoz && (
          <button
            type="button"
            title="Modo conversación por voz (la IA te responde hablando)"
            disabled={!soportado}
            onClick={onModoVoz}
            className={cn(
              'rounded-md p-1.5 transition-colors',
              !soportado && 'opacity-40 cursor-not-allowed',
              'text-muted hover:bg-surface-2 hover:text-text',
            )}
          >
            <Volume2 size={16} />
          </button>
        )}
        <button
          type="button"
          title={
            buscarWeb
              ? 'Búsqueda web activada · click para desactivar'
              : 'Activar búsqueda en internet para esta consulta'
          }
          onClick={() => setBuscarWeb(!buscarWeb)}
          className={cn(
            'flex items-center gap-1.5 rounded-md px-2 py-1.5 text-[12px] font-medium transition-colors',
            buscarWeb
              ? 'bg-primary/15 text-primary border border-primary/40'
              : 'text-muted hover:bg-surface-2 hover:text-text border border-transparent'
          )}
        >
          <Globe size={14} />
          <span>Web</span>
        </button>
        <div className="ml-auto flex items-center gap-2">
          {(tieneTexto || adjuntos.length > 0) && (
            <span className="text-[11px] text-subtle">
              {input.length} car. · {adjuntos.length} adj.
            </span>
          )}
          <button
            type="submit"
            disabled={enviando || (!tieneTexto && adjuntos.length === 0)}
            className={cn(
              'flex h-8 w-8 items-center justify-center rounded-lg transition-all',
              (tieneTexto || adjuntos.length > 0) && !enviando
                ? 'bg-primary text-primary-foreground hover:bg-primary-hover'
                : 'bg-surface-3 text-subtle'
            )}
            aria-label="Enviar"
          >
            {enviando ? (
              <Loader2 size={15} className="animate-spin" />
            ) : (
              <ArrowUp size={15} />
            )}
          </button>
        </div>
      </div>
    </form>
  );
}

// ─────────────────────────── Estado del sistema (sin cerebro) ───────────────────────────

/** Tarjeta visual para respuestas de "sistema" (sin API ni modelo, error, filtro). */
function EstadoSistemaCard({ origen, mensaje }: { origen: string; mensaje: string }) {
  const cfg = (() => {
    switch (origen) {
      case 'sin_configurar':
        return {
          titulo: 'El asistente aún no tiene cerebro',
          descripcion:
            'No hay un modelo propio entrenado ni una API externa configurada. Para que el chat responda necesitas una de las dos.',
          tone: 'warning' as const,
          icon: <Brain size={16} />,
          acciones: [
            {
              label: 'Configurar API',
              href: '/admin',
              icon: <KeyRound size={13} />,
              primaria: true,
            },
            {
              label: 'Ajustes',
              href: '/configuracion',
              icon: <Settings size={13} />,
              primaria: false,
            },
          ],
        };
      case 'api_error':
        return {
          titulo: 'No pude generar la respuesta',
          descripcion:
            'La API externa devolvió un error. Puede ser cuota agotada, clave inválida o el proveedor caído.',
          tone: 'danger' as const,
          icon: <AlertTriangle size={16} />,
          acciones: [
            {
              label: 'Revisar API',
              href: '/admin',
              icon: <KeyRound size={13} />,
              primaria: true,
            },
          ],
        };
      case 'filtro_contenido':
        return {
          titulo: 'Esa pregunta no la puedo asistir',
          descripcion:
            'El sistema bloqueó el contenido por su política de uso. Si era una pregunta educativa, reformulala (ver sugerencias abajo).',
          tone: 'warning' as const,
          icon: <AlertTriangle size={16} />,
          acciones: [],
        };
      case 'vision_en_entrenamiento':
        return {
          titulo: 'El modelo de visión propio está en entrenamiento',
          descripcion:
            'Por decisión arquitectónica este sistema NO usa APIs externas para analizar imágenes (sería contradictorio con la tesis). El modelo ViT propio se entrena en local. Mientras tanto, puedes pegar el código como texto y te lo explico igual.',
          tone: 'neutral' as const,
          icon: <Brain size={16} />,
          acciones: [
            {
              label: 'Ver documentación',
              href: '/rag',
              icon: <BookOpen size={13} />,
              primaria: false,
            },
          ],
        };
      default:
        return {
          titulo: 'Estado del sistema',
          descripcion: mensaje,
          tone: 'neutral' as const,
          icon: <AlertTriangle size={16} />,
          acciones: [],
        };
    }
  })();

  const toneClasses: Record<string, string> = {
    warning: 'border-warning/40 bg-warning/5',
    danger: 'border-danger/40 bg-danger/5',
    neutral: 'border-border-soft bg-surface-2/50',
  };
  const titleToneClasses: Record<string, string> = {
    warning: 'text-warning',
    danger: 'text-danger',
    neutral: 'text-text',
  };

  return (
    <div
      className={cn(
        'rounded-2xl border p-5 animate-fade-in',
        toneClasses[cfg.tone]
      )}
    >
      <h3 className={cn('font-serif text-lg mb-1', titleToneClasses[cfg.tone])}>
        {cfg.titulo}
      </h3>
      <p className="text-sm text-muted leading-relaxed mb-4">
        {cfg.descripcion}
      </p>
      {origen === 'sin_configurar' && (
        <div className="mb-4 grid gap-2 sm:grid-cols-2">
          <OpcionMini
            icon={<KeyRound size={13} className="text-primary" />}
            titulo="Opción 1 — API rápida"
            descripcion="Configurar Gemini o DeepSeek. Funciona en segundos."
          />
          <OpcionMini
            icon={<Brain size={13} className="text-accent" />}
            titulo="Opción 2 — Modelo propio"
            descripcion="Entrenar tu LLM con ml.train. Toma horas pero es 100% tuyo."
          />
        </div>
      )}
      {origen === 'filtro_contenido' && (
        // Mostramos el mensaje original que ya trae sugerencias.
        <div className="prose-chat text-sm mt-3">
          <ReactMarkdown>{mensaje}</ReactMarkdown>
        </div>
      )}
      {cfg.acciones.length > 0 && (
        <div className="flex flex-wrap gap-2 mt-2">
          {cfg.acciones.map((a) => (
            <Link
              key={a.href}
              href={a.href}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-lg px-3.5 py-2 text-sm font-medium transition-colors',
                a.primaria
                  ? 'bg-primary text-primary-foreground hover:bg-primary-hover'
                  : 'border border-border-soft bg-surface hover:bg-surface-2'
              )}
            >
              {a.icon}
              {a.label}
              <ArrowRight size={12} />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

function OpcionMini({
  icon, titulo, descripcion
}: {
  icon: React.ReactNode;
  titulo: string;
  descripcion: string;
}) {
  return (
    <div className="rounded-lg border border-border-soft bg-surface px-3 py-2.5">
      <div className="flex items-center gap-2 mb-0.5">
        {icon}
        <span className="text-[12.5px] font-semibold text-text">{titulo}</span>
      </div>
      <p className="text-[11.5px] text-subtle leading-snug">{descripcion}</p>
    </div>
  );
}

/** Mapea el código de idioma del settings al locale del speech recognition. */
function idiomaALocale(codigo: string): string {
  if (codigo.startsWith('es')) return codigo.includes('-') ? codigo : 'es-ES';
  if (codigo.startsWith('en')) return codigo.includes('-') ? codigo : 'en-US';
  if (codigo.startsWith('pt')) return codigo === 'pt-BR' ? 'pt-BR' : 'pt-PT';
  if (codigo.startsWith('zh')) return codigo === 'zh-TW' ? 'zh-TW' : 'zh-CN';
  const map: Record<string, string> = {
    fr: 'fr-FR', it: 'it-IT', de: 'de-DE', ru: 'ru-RU',
    ja: 'ja-JP', ko: 'ko-KR', ar: 'ar-SA', hi: 'hi-IN',
    tr: 'tr-TR', nl: 'nl-NL', pl: 'pl-PL', id: 'id-ID',
    th: 'th-TH', vi: 'vi-VN'
  };
  return map[codigo] ?? 'es-ES';
}
