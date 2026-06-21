import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import { Database, Cpu, BookOpen, Server, Layers, GraduationCap } from 'lucide-react';

const FLUJO = [
  { t: 'APIs (Gemini / DeepSeek)', d: 'Solo generan datos de entrenamiento', icon: <Server size={18} /> },
  { t: 'Dataset educativo', d: 'instruccion / entrada / salida validados', icon: <Database size={18} /> },
  { t: 'Tokenizer + Transformer propio', d: 'Entrenamiento desde cero (PyTorch)', icon: <Cpu size={18} /> },
  { t: 'Motor de inferencia', d: 'El modelo responde sin APIs', icon: <Layers size={18} /> },
  { t: 'Estudiante', d: 'Usuario → Modelo propio → Respuesta', icon: <GraduationCap size={18} /> }
];

const CARPETAS: { nombre: string; desc: string }[] = [
  { nombre: 'ml/', desc: 'LLM propio: tokenizer, modelo, training, inference' },
  { nombre: 'ml/model/transformer.py', desc: 'Transformer decoder desde cero' },
  { nombre: 'ml/tokenizer/bpe.py', desc: 'Tokenizer BPE byte-level propio' },
  { nombre: 'ml/training/trainer.py', desc: 'Pipeline de entrenamiento' },
  { nombre: 'ml/data/generator.py', desc: 'Generación de dataset con APIs' },
  { nombre: 'backend/', desc: 'FastAPI: auth, motor educativo, base de conocimiento' },
  { nombre: 'backend/app/services/model_inference_service.py', desc: 'Modelo propio en la web' },
  { nombre: 'datasets/', desc: 'Corpus crudo, procesado y validado' },
  { nombre: 'training/', desc: 'Checkpoints y experimentos' },
  { nombre: 'knowledge_base/', desc: 'Conocimiento curado de Python/OOP/algoritmos' },
  { nombre: 'frontend/', desc: 'Portal Next.js (este sitio)' },
  { nombre: 'research/', desc: 'Bitácora, metodología, validación, resultados' }
];

export default function ProyectoPage() {
  return (
    <AppLayout>
      <div className="mb-4">
        <h1 className="text-2xl font-bold">Mapa del proyecto</h1>
        <p className="text-sm text-muted">
          Arquitectura científica: las APIs solo generan datos; el modelo propio responde.
        </p>
      </div>

      <Card className="mb-6 p-6">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-muted">
          Flujo de la investigación
        </h2>
        <div className="flex flex-col gap-3 lg:flex-row lg:items-stretch">
          {FLUJO.map((f, i) => (
            <div key={i} className="flex flex-1 items-center gap-3">
              <div className="flex-1 rounded-xl border bg-surface-2/40 p-4">
                <div className="mb-2 flex h-9 w-9 items-center justify-center rounded-lg bg-primary-soft text-primary">
                  {f.icon}
                </div>
                <div className="text-sm font-semibold">{f.t}</div>
                <div className="text-xs text-muted">{f.d}</div>
              </div>
              {i < FLUJO.length - 1 && (
                <div className="hidden text-muted lg:block">→</div>
              )}
            </div>
          ))}
        </div>
      </Card>

      <Card className="p-6">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-muted">
          Estructura de carpetas
        </h2>
        <div className="grid gap-2 sm:grid-cols-2">
          {CARPETAS.map((c) => (
            <div key={c.nombre} className="flex items-start gap-3 rounded-lg border p-3">
              <BookOpen size={16} className="mt-0.5 shrink-0 text-primary" />
              <div>
                <code className="text-sm font-semibold">{c.nombre}</code>
                <p className="text-xs text-muted">{c.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </AppLayout>
  );
}
