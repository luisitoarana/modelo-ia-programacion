import { useEffect, useRef, useState } from 'react';
import {
  Upload, Trash2, FileText, Search, Database, Sparkles, Loader2,
  CheckCircle2, AlertCircle, FileCode, FileJson, BookOpen,
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import {
  obtenerEstadoRag, listarDocumentosRag, subirArchivoRag, subirTextoRag,
  eliminarDocumentoRag, buscarRag,
  EstadoRag, DocumentoRag, ChunkRag,
} from '@/services/rag';
import { mensajeError } from '@/lib/errors';
import { cn } from '@/lib/cn';

/**
 * Panel RAG — gestiona el índice vectorial del usuario.
 *
 * Sube documentos arrastrándolos o seleccionándolos. El chat los citará
 * automáticamente cuando preguntes algo relacionado, en lugar de inventar.
 */

export default function RagPage() {
  const [estado, setEstado] = useState<EstadoRag | null>(null);
  const [documentos, setDocumentos] = useState<DocumentoRag[]>([]);
  const [cargando, setCargando] = useState(true);
  const [subiendo, setSubiendo] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const inputArchivoRef = useRef<HTMLInputElement>(null);

  // Modal subir texto manual
  const [modalTexto, setModalTexto] = useState(false);
  const [tituloTexto, setTituloTexto] = useState('');
  const [contenidoTexto, setContenidoTexto] = useState('');

  // Búsqueda de prueba
  const [consulta, setConsulta] = useState('');
  const [resultados, setResultados] = useState<ChunkRag[]>([]);
  const [buscando, setBuscando] = useState(false);

  async function recargar() {
    try {
      const [e, d] = await Promise.all([
        obtenerEstadoRag(),
        listarDocumentosRag(),
      ]);
      setEstado(e);
      setDocumentos(d);
    } catch (e) {
      setError(mensajeError(e));
    } finally {
      setCargando(false);
    }
  }

  useEffect(() => {
    recargar();
  }, []);

  // ─────────────── Subida ───────────────

  async function subirArchivos(archivos: FileList | File[]) {
    setSubiendo(true);
    setError(null);
    try {
      for (const archivo of Array.from(archivos)) {
        await subirArchivoRag(archivo);
      }
      await recargar();
    } catch (e) {
      setError(mensajeError(e));
    } finally {
      setSubiendo(false);
    }
  }

  function manejarDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragOver(false);
    if (e.dataTransfer.files.length === 0) return;
    subirArchivos(e.dataTransfer.files);
  }

  async function subirTexto() {
    if (!tituloTexto.trim() || !contenidoTexto.trim()) return;
    setSubiendo(true);
    setError(null);
    try {
      await subirTextoRag({
        titulo: tituloTexto.trim(),
        texto: contenidoTexto.trim(),
        fuente: 'pegado',
      });
      setTituloTexto('');
      setContenidoTexto('');
      setModalTexto(false);
      await recargar();
    } catch (e) {
      setError(mensajeError(e));
    } finally {
      setSubiendo(false);
    }
  }

  async function eliminar(doc: DocumentoRag) {
    if (!confirm(`Eliminar "${doc.titulo}"? El chat ya no lo citará.`)) return;
    try {
      await eliminarDocumentoRag(doc.id);
      await recargar();
    } catch (e) {
      setError(mensajeError(e));
    }
  }

  async function probarBusqueda(e: React.FormEvent) {
    e.preventDefault();
    if (!consulta.trim()) return;
    setBuscando(true);
    try {
      const r = await buscarRag(consulta.trim(), 5);
      setResultados(r);
    } catch (e) {
      setError(mensajeError(e));
    } finally {
      setBuscando(false);
    }
  }

  // ─────────────── Render ───────────────

  return (
    <AppLayout>
      <div className="mx-auto max-w-5xl py-8 px-6">
        {/* Header */}
        <div className="mb-6 flex items-start gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/15 text-primary">
            <Database size={22} />
          </div>
          <div className="min-w-0 flex-1">
            <h1 className="font-serif text-2xl text-text">Base de conocimiento (RAG)</h1>
            <p className="mt-1 text-sm text-muted">
              Sube documentos, código o notas. El chat los citará en lugar de inventar
              cuando preguntes algo relacionado.
            </p>
          </div>
        </div>

        {/* Estado */}
        <EstadoBanner estado={estado} cargando={cargando} />

        {error && (
          <div className="mb-4 flex items-start gap-2 rounded-lg border border-danger/40 bg-danger/5 p-3 text-sm text-danger">
            <AlertCircle size={16} className="mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Zona drag-drop */}
        <Card className="mb-6">
          <div
            onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
            onDragLeave={() => setDragOver(false)}
            onDrop={manejarDrop}
            onClick={() => inputArchivoRef.current?.click()}
            className={cn(
              'flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-10 transition-colors',
              dragOver
                ? 'border-primary bg-primary/5'
                : 'border-border-soft hover:border-primary/50 hover:bg-surface-2/50',
            )}
          >
            <input
              ref={inputArchivoRef}
              type="file"
              multiple
              accept=".txt,.md,.py,.json,.yml,.yaml,.rst,.js,.ts,.tsx,.html,.css"
              onChange={(e) => e.target.files && subirArchivos(e.target.files)}
              className="hidden"
            />
            {subiendo ? (
              <Loader2 size={32} className="animate-spin text-primary" />
            ) : (
              <Upload size={32} className="text-muted" />
            )}
            <p className="mt-3 font-medium text-text">
              {subiendo
                ? 'Indexando...'
                : 'Arrastra documentos aquí o haz click'}
            </p>
            <p className="mt-1 text-xs text-muted">
              .txt, .md, .py, .json, .yml... (máx 5 MB cada uno)
            </p>
          </div>
          <div className="mt-3 flex justify-end">
            <button
              onClick={() => setModalTexto(true)}
              className="text-xs text-primary hover:underline"
            >
              o pega texto manualmente →
            </button>
          </div>
        </Card>

        {/* Búsqueda de prueba */}
        <Card className="mb-6">
          <h2 className="mb-2 flex items-center gap-2 font-serif text-lg text-text">
            <Search size={16} /> Probar búsqueda
          </h2>
          <p className="mb-3 text-xs text-muted">
            Escribe una consulta para ver qué chunks devolvería el RAG al chat.
            Sirve para depurar antes de hacer preguntas reales.
          </p>
          <form onSubmit={probarBusqueda} className="flex gap-2">
            <input
              type="text"
              value={consulta}
              onChange={(e) => setConsulta(e.target.value)}
              placeholder="¿Cómo se entrena el modelo?"
              className="flex-1 rounded-lg border border-border-soft bg-surface px-3 py-2 text-sm focus:border-primary focus:outline-none"
            />
            <button
              type="submit"
              disabled={!consulta.trim() || buscando}
              className="flex items-center gap-1 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary-hover disabled:opacity-50"
            >
              {buscando ? <Loader2 size={14} className="animate-spin" /> : <Search size={14} />}
              Buscar
            </button>
          </form>
          {resultados.length > 0 && (
            <div className="mt-4 flex flex-col gap-2">
              {resultados.map((r) => (
                <div key={r.chunk_id} className="rounded-lg border border-border-soft bg-surface-2/40 p-3">
                  <div className="mb-1 flex items-center justify-between gap-2">
                    <span className="truncate text-xs font-medium text-text">{r.doc_titulo}</span>
                    <span className="shrink-0 rounded-full bg-success/15 px-2 py-0.5 text-[10px] font-semibold text-success">
                      {(r.score * 100).toFixed(0)}%
                    </span>
                  </div>
                  <p className="text-xs leading-relaxed text-muted line-clamp-3">{r.texto}</p>
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* Lista de documentos */}
        <Card>
          <h2 className="mb-3 flex items-center gap-2 font-serif text-lg text-text">
            <FileText size={16} /> Documentos indexados
            <span className="rounded-full bg-surface-2 px-2 py-0.5 text-xs font-medium text-muted">
              {documentos.length}
            </span>
          </h2>
          {documentos.length === 0 ? (
            <div className="rounded-lg bg-surface-2/40 p-8 text-center text-sm text-muted">
              No hay documentos indexados todavía. Sube algunos arriba.
            </div>
          ) : (
            <div className="flex flex-col divide-y divide-border-soft">
              {documentos.map((d) => (
                <DocumentoItem key={d.id} doc={d} onEliminar={() => eliminar(d)} />
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Modal pegar texto */}
      {modalTexto && (
        <ModalPegarTexto
          titulo={tituloTexto}
          contenido={contenidoTexto}
          subiendo={subiendo}
          onTitulo={setTituloTexto}
          onContenido={setContenidoTexto}
          onSubir={subirTexto}
          onCancelar={() => setModalTexto(false)}
        />
      )}
    </AppLayout>
  );
}

// ─────────────── Subcomponentes ───────────────

function EstadoBanner({ estado, cargando }: { estado: EstadoRag | null; cargando: boolean }) {
  if (cargando) {
    return (
      <div className="mb-4 flex items-center gap-2 rounded-lg border border-border-soft bg-surface-2/40 p-3 text-sm text-muted">
        <Loader2 size={14} className="animate-spin" />
        Verificando estado del índice...
      </div>
    );
  }
  if (!estado || !estado.disponible) {
    return (
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm">
        <AlertCircle size={16} className="mt-0.5 shrink-0 text-warning" />
        <div>
          <p className="font-medium text-warning">Sistema RAG no disponible</p>
          <p className="text-xs text-muted">{estado?.motivo ?? 'Reinicia el backend para activarlo.'}</p>
        </div>
      </div>
    );
  }
  return (
    <div className="mb-4 grid gap-3 sm:grid-cols-3">
      <MiniMetrica icon={<FileText size={14} />} valor={estado.n_documentos} label="documentos" />
      <MiniMetrica icon={<Sparkles size={14} />} valor={estado.n_chunks} label="chunks indexados" />
      <MiniMetrica
        icon={<BookOpen size={14} />}
        valor={estado.backend === 'sentence-transformers' ? 'SBERT' : estado.backend}
        label={`embeddings (${estado.dim}d)`}
        textual
      />
    </div>
  );
}

function MiniMetrica({
  icon, valor, label, textual,
}: { icon: React.ReactNode; valor: number | string; label: string; textual?: boolean }) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-border-soft bg-surface p-3">
      <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/15 text-primary">
        {icon}
      </div>
      <div className="min-w-0">
        <p className="font-serif text-lg leading-tight text-text">
          {textual ? valor : Number(valor).toLocaleString()}
        </p>
        <p className="text-[11px] text-muted">{label}</p>
      </div>
    </div>
  );
}

function DocumentoItem({ doc, onEliminar }: { doc: DocumentoRag; onEliminar: () => void }) {
  const icon = (() => {
    if (doc.titulo.endsWith('.json') || doc.titulo.endsWith('.yml')) return <FileJson size={14} />;
    if (doc.titulo.endsWith('.py') || doc.titulo.endsWith('.ts') || doc.titulo.endsWith('.js'))
      return <FileCode size={14} />;
    return <FileText size={14} />;
  })();
  return (
    <div className="flex items-center gap-3 py-2.5">
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-surface-2 text-muted">
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-text">{doc.titulo}</p>
        <p className="truncate text-[11px] text-subtle">
          {doc.n_chunks} chunks · {doc.fuente}
          {doc.fecha ? ` · ${new Date(doc.fecha).toLocaleDateString()}` : ''}
        </p>
      </div>
      <button
        onClick={onEliminar}
        className="rounded-md p-2 text-muted hover:bg-danger/10 hover:text-danger"
        title="Eliminar"
      >
        <Trash2 size={14} />
      </button>
    </div>
  );
}

function ModalPegarTexto({
  titulo, contenido, subiendo, onTitulo, onContenido, onSubir, onCancelar,
}: {
  titulo: string; contenido: string; subiendo: boolean;
  onTitulo: (v: string) => void; onContenido: (v: string) => void;
  onSubir: () => void; onCancelar: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-2xl rounded-2xl bg-surface p-6 shadow-elevated">
        <h3 className="mb-4 font-serif text-xl text-text">Pegar texto manualmente</h3>
        <div className="flex flex-col gap-3">
          <input
            type="text"
            value={titulo}
            onChange={(e) => onTitulo(e.target.value)}
            placeholder="Título del documento"
            className="rounded-lg border border-border-soft bg-surface-2 px-3 py-2 text-sm focus:border-primary focus:outline-none"
          />
          <textarea
            value={contenido}
            onChange={(e) => onContenido(e.target.value)}
            placeholder="Pega aquí el contenido..."
            rows={10}
            className="rounded-lg border border-border-soft bg-surface-2 px-3 py-2 text-sm focus:border-primary focus:outline-none"
          />
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button
            onClick={onCancelar}
            className="rounded-lg border border-border-soft bg-surface px-4 py-2 text-sm hover:bg-surface-2"
          >
            Cancelar
          </button>
          <button
            onClick={onSubir}
            disabled={!titulo.trim() || !contenido.trim() || subiendo}
            className="flex items-center gap-1.5 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary-hover disabled:opacity-50"
          >
            {subiendo ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
            Indexar
          </button>
        </div>
      </div>
    </div>
  );
}
