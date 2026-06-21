import { useState, useEffect } from 'react';
import { Sparkles, Volume2, Square } from 'lucide-react';
import ChatLayout from '@/layouts/ChatLayout';
import VistaDividida from '@/components/VistaDividida';
import { Card } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import Button from '@/components/ui/Button';
import Textarea from '@/components/ui/Textarea';
import Select from '@/components/ui/Select';
import { ConsultaLeer, generarExplicacion } from '@/services/ai';
import { formatSeconds } from '@/lib/format';
import { mensajeError } from '@/lib/errors';

/** Aplana la respuesta estructurada de /explicar para que pueda leerse. */
function planoParaTts(r: any): string {
  if (!r) return '';
  const partes: string[] = [];
  if (r.titulo) partes.push(r.titulo);
  if (r.que_hace) partes.push('Qué hace. ' + r.que_hace);
  if (r.por_que) partes.push('Por qué. ' + r.por_que);
  if (r.explicacion) partes.push(r.explicacion);
  if (r.codigo) partes.push('Bloque de código incluido.');
  if (r.ejemplos && Array.isArray(r.ejemplos)) {
    partes.push('Ejemplos. ' + r.ejemplos.map((e: any) => e.descripcion ?? e).join('. '));
  }
  if (r.ejercicios && Array.isArray(r.ejercicios)) {
    partes.push('Ejercicios. ' + r.ejercicios.map((e: any) => e.enunciado ?? e).join('. '));
  }
  return partes
    .join('. ')
    .replace(/[*_`#>]+/g, '')
    .replace(/\s+/g, ' ')
    .slice(0, 1200);
}

export default function ExplicarPage() {
  const [prompt, setPrompt] = useState('');
  const [nivel, setNivel] = useState<'basico' | 'intermedio' | 'avanzado'>('basico');
  // Web SIEMPRE usa el modelo propio. No hay switcher de proveedor.
  // (La elección Gemini/DeepSeek vive solo en la app desktop como fallback.)
  const proveedor = 'propio';
  const [cargando, setCargando] = useState(false);
  const [resp, setResp] = useState<ConsultaLeer | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [leyendo, setLeyendo] = useState(false);

  // Detener TTS al desmontar
  useEffect(() => {
    return () => {
      if (typeof window !== 'undefined' && window.speechSynthesis) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  function alternarLectura() {
    if (typeof window === 'undefined' || !window.speechSynthesis) return;
    if (leyendo) {
      window.speechSynthesis.cancel();
      setLeyendo(false);
      return;
    }
    const texto = planoParaTts(resp?.respuesta);
    if (!texto) return;
    const u = new SpeechSynthesisUtterance(texto);
    const voiceName = window.localStorage.getItem('explicador.tts_voice') ?? '';
    const rate = parseFloat(window.localStorage.getItem('explicador.tts_rate') ?? '1.0');
    u.rate = rate;
    if (voiceName) {
      const v = window.speechSynthesis.getVoices().find((vc) => vc.name === voiceName);
      if (v) u.voice = v;
    }
    u.onend = () => setLeyendo(false);
    u.onerror = () => setLeyendo(false);
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(u);
    setLeyendo(true);
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    if (!prompt.trim()) return;
    setCargando(true);
    setError(null);
    try {
      const r = await generarExplicacion({ prompt, nivel_solicitado: nivel, proveedor });
      setResp(r);
    } catch (err: any) {
      setError(mensajeError(err, 'No se pudo generar la explicación'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <ChatLayout>
      <div className="h-full overflow-y-auto">
        <div className="mx-auto max-w-4xl px-6 py-6">
      <div className="mb-4">
        <h1 className="font-serif text-3xl text-text">Explicar y generar código</h1>
        <p className="text-sm text-muted mt-1">
          Respuesta estructurada: primero busca en la base de conocimiento; si no hay,
          usa una API para generar y aprende del resultado.
        </p>
      </div>

      <Card className="mb-5 p-5">
        <form onSubmit={enviar} className="space-y-3">
          <Textarea
            rows={3}
            placeholder='Ej: "Genera una función que calcule el promedio de notas y explícala"'
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
          />
          <div className="grid gap-3 sm:grid-cols-2">
            <Select
              value={nivel}
              onChange={(e) => setNivel(e.target.value as any)}
              options={[
                { value: 'basico', label: 'Nivel: básico' },
                { value: 'intermedio', label: 'Nivel: intermedio' },
                { value: 'avanzado', label: 'Nivel: avanzado' }
              ]}
            />
            <Button type="submit" loading={cargando}>
              {!cargando && <Sparkles size={16} />} Generar
            </Button>
          </div>
          {error && <p className="text-sm text-danger">{error}</p>}
        </form>
      </Card>

      {resp && (
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <Badge tone={resp.origen_respuesta === 'base_conocimiento' ? 'success' : 'primary'}>
            origen: {resp.origen_respuesta === 'base_conocimiento' ? 'conocimiento propio' : 'API'}
          </Badge>
          <Badge tone="neutral">tokens {resp.tokens_totales}</Badge>
          <Badge tone="neutral">{formatSeconds(resp.latencia_segundos)}</Badge>
          {resp.puntaje_calidad > 0 && (
            <Badge tone="accent">calidad {resp.puntaje_calidad}/12</Badge>
          )}
          {resp.intentos_reparacion_json > 0 && (
            <Badge tone="warning">reparaciones JSON {resp.intentos_reparacion_json}</Badge>
          )}
          <div className="ml-auto">
            <button
              onClick={alternarLectura}
              className={
                'inline-flex items-center gap-1.5 rounded-lg border border-border-soft px-3 py-1 text-xs transition-colors ' +
                (leyendo
                  ? 'bg-primary-soft text-primary'
                  : 'bg-surface text-muted hover:bg-surface-2 hover:text-text')
              }
              title={leyendo ? 'Detener lectura' : 'Leer la explicación en voz alta'}
            >
              {leyendo ? <Square size={11} /> : <Volume2 size={12} />}
              {leyendo ? 'Detener' : 'Leer en voz alta'}
            </button>
          </div>
        </div>
      )}

      <VistaDividida respuesta={resp?.respuesta || null} />
        </div>
      </div>
    </ChatLayout>
  );
}
