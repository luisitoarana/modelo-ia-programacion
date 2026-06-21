import { useEffect, useState } from 'react';
import { BookOpen } from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import { api } from '@/services/api';

interface Tema {
  slug: string;
  titulo: string;
  categoria: string;
}

export default function ConocimientoPage() {
  const [categorias, setCategorias] = useState<string[]>([]);
  const [catActiva, setCatActiva] = useState<string | null>(null);
  const [temas, setTemas] = useState<Tema[]>([]);
  const [contenido, setContenido] = useState('');
  const [temaActivo, setTemaActivo] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ categorias: string[] }>('/knowledge/categorias').then((r) => {
      setCategorias(r.data.categorias);
      if (r.data.categorias[0]) setCatActiva(r.data.categorias[0]);
    });
  }, []);

  useEffect(() => {
    if (!catActiva) return;
    api
      .get<{ temas: Tema[] }>(`/knowledge/categoria/${catActiva}`)
      .then((r) => setTemas(r.data.temas))
      .catch(() => setTemas([]));
    setContenido('');
    setTemaActivo(null);
  }, [catActiva]);

  function abrir(t: Tema) {
    setTemaActivo(t.slug);
    api.get<{ contenido: string }>(`/knowledge/tema/${t.categoria}/${t.slug}`).then((r) =>
      setContenido(r.data.contenido)
    );
  }

  return (
    <AppLayout>
      <div className="mb-4">
        <h1 className="text-2xl font-bold">Base de conocimiento</h1>
        <p className="text-sm text-muted">Conceptos curados de Python, OOP y algoritmos.</p>
      </div>

      <div className="grid gap-4 lg:grid-cols-[200px_240px_1fr]">
        <Card className="p-3">
          <div className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-wide text-muted">
            Categorías
          </div>
          {categorias.map((c) => (
            <button
              key={c}
              onClick={() => setCatActiva(c)}
              className={`w-full rounded-lg px-3 py-2 text-left text-sm capitalize ${
                c === catActiva ? 'bg-primary-soft text-primary' : 'text-muted hover:bg-surface-2'
              }`}
            >
              {c.replace(/_/g, ' ')}
            </button>
          ))}
        </Card>

        <Card className="p-3">
          <div className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-wide text-muted">
            Temas
          </div>
          {temas.map((t) => (
            <button
              key={t.slug}
              onClick={() => abrir(t)}
              className={`w-full rounded-lg px-3 py-2 text-left text-sm ${
                t.slug === temaActivo ? 'bg-surface-2 font-medium' : 'text-muted hover:bg-surface-2'
              }`}
            >
              {t.titulo}
            </button>
          ))}
          {temas.length === 0 && <p className="px-2 text-sm text-muted">Sin temas.</p>}
        </Card>

        <Card className="min-h-[360px] p-5">
          {contenido ? (
            <pre className="whitespace-pre-wrap border-0 bg-transparent p-0 font-sans text-sm leading-relaxed">
              {contenido}
            </pre>
          ) : (
            <div className="flex h-full flex-col items-center justify-center text-muted">
              <BookOpen size={28} className="mb-2 opacity-50" />
              <p className="text-sm">Selecciona un tema para verlo.</p>
            </div>
          )}
        </Card>
      </div>
    </AppLayout>
  );
}
