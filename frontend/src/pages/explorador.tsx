import { useEffect, useState } from 'react';
import {
  Folder, FileCode2, ChevronRight, Home, Sparkles, Loader2, FileText
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import Button from '@/components/ui/Button';
import {
  NodoArchivo, ArchivoLeido, listarArbol, leerArchivo
} from '@/services/proyecto';
import { mensajeRapido } from '@/services/chat';
import { mensajeError } from '@/lib/errors';

function segmentos(ruta: string): { nombre: string; ruta: string }[] {
  if (!ruta) return [];
  const partes = ruta.split('/');
  return partes.map((p, i) => ({ nombre: p, ruta: partes.slice(0, i + 1).join('/') }));
}

export default function ExploradorPage() {
  const [rutaActual, setRutaActual] = useState('');
  const [elementos, setElementos] = useState<NodoArchivo[]>([]);
  const [archivo, setArchivo] = useState<ArchivoLeido | null>(null);
  const [cargandoArbol, setCargandoArbol] = useState(true);
  const [explicacion, setExplicacion] = useState<string | null>(null);
  const [explicando, setExplicando] = useState(false);

  useEffect(() => {
    abrirCarpeta('');
  }, []);

  async function abrirCarpeta(ruta: string) {
    setCargandoArbol(true);
    try {
      setElementos(await listarArbol(ruta));
      setRutaActual(ruta);
    } catch {
      setElementos([]);
    } finally {
      setCargandoArbol(false);
    }
  }

  async function abrirArchivo(n: NodoArchivo) {
    setArchivo(null);
    setExplicacion(null);
    try {
      setArchivo(await leerArchivo(n.ruta));
    } catch (e) {
      setArchivo(null);
    }
  }

  async function explicar() {
    if (!archivo) return;
    setExplicando(true);
    setExplicacion(null);
    try {
      const prompt =
        `Explica este archivo del proyecto (${archivo.ruta}) paso a paso y el ` +
        `porqué de cada parte, para un estudiante:\n\n\`\`\`${archivo.lenguaje}\n` +
        `${archivo.contenido}\n\`\`\``;
      const r = await mensajeRapido(prompt);
      setExplicacion(r.mensaje_asistente.contenido);
    } catch (e) {
      setExplicacion(mensajeError(e, 'No se pudo explicar.'));
    } finally {
      setExplicando(false);
    }
  }

  return (
    <AppLayout>
      <div className="mb-4">
        <h1 className="text-2xl font-bold">Explorador del proyecto</h1>
        <p className="text-sm text-muted">
          El sistema entra a las carpetas reales y lee el código. Selecciona un
          archivo y pídele que lo explique (cuando el modelo esté entrenado).
        </p>
      </div>

      {/* Breadcrumb */}
      <div className="mb-3 flex flex-wrap items-center gap-1 text-sm">
        <button onClick={() => abrirCarpeta('')} className="flex items-center gap-1 rounded px-1.5 py-0.5 text-muted hover:bg-surface-2 hover:text-text">
          <Home size={14} /> proyecto
        </button>
        {segmentos(rutaActual).map((s) => (
          <span key={s.ruta} className="flex items-center gap-1">
            <ChevronRight size={13} className="text-muted" />
            <button onClick={() => abrirCarpeta(s.ruta)} className="rounded px-1.5 py-0.5 text-muted hover:bg-surface-2 hover:text-text">
              {s.nombre}
            </button>
          </span>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-[300px_1fr]">
        {/* Árbol */}
        <Card className="max-h-[72vh] overflow-y-auto p-2">
          {cargandoArbol ? (
            <div className="flex justify-center py-6 text-muted"><Loader2 className="animate-spin" /></div>
          ) : (
            <div className="flex flex-col gap-0.5">
              {elementos.length === 0 && (
                <p className="px-2 py-3 text-sm text-muted">Carpeta vacía.</p>
              )}
              {elementos.map((n) => (
                <button
                  key={n.ruta}
                  onClick={() => (n.tipo === 'carpeta' ? abrirCarpeta(n.ruta) : abrirArchivo(n))}
                  className="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-sm text-muted transition-colors hover:bg-surface-2 hover:text-text"
                >
                  {n.tipo === 'carpeta' ? (
                    <Folder size={15} className="shrink-0 text-primary" />
                  ) : n.es_texto ? (
                    <FileCode2 size={15} className="shrink-0 text-accent" />
                  ) : (
                    <FileText size={15} className="shrink-0 text-muted" />
                  )}
                  <span className="truncate">{n.nombre}</span>
                </button>
              ))}
            </div>
          )}
        </Card>

        {/* Visor */}
        <div className="space-y-4">
          <Card className="overflow-hidden">
            {!archivo ? (
              <div className="flex h-64 flex-col items-center justify-center text-muted">
                <FileCode2 size={26} className="mb-2 opacity-50" />
                <p className="text-sm">Selecciona un archivo para ver su código.</p>
              </div>
            ) : (
              <>
                <div className="flex items-center justify-between border-b px-4 py-2.5">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-semibold">{archivo.ruta}</div>
                    <div className="text-[11px] text-muted">
                      {archivo.lenguaje} · {archivo.tamano} bytes
                      {archivo.truncado && ' · (truncado)'}
                    </div>
                  </div>
                  <Button size="sm" onClick={explicar} loading={explicando}>
                    {!explicando && <Sparkles size={15} />} Explicar
                  </Button>
                </div>
                <pre className="max-h-[52vh] overflow-auto bg-[#020617] p-4 text-xs leading-relaxed text-slate-200">
                  {archivo.contenido}
                </pre>
              </>
            )}
          </Card>

          {explicacion && (
            <Card className="p-5">
              <h3 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <Sparkles size={15} className="text-accent" /> Explicación
              </h3>
              <p className="whitespace-pre-wrap text-sm leading-relaxed text-muted">
                {explicacion}
              </p>
            </Card>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
