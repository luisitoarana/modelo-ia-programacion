import { ReactNode, useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import ChatSidebar from '@/components/chat/ChatSidebar';
import { getToken } from '@/services/api';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import {
  ConversacionResumen,
  listarConversaciones,
  eliminarConversacion,
} from '@/services/chat';

/**
 * Layout para páginas "tipo asistente" — usa el mismo sidebar de chat
 * (con conversaciones recientes) que la página principal. Pensado para
 * envolver páginas que el estudiante usa en el flujo de aprendizaje
 * (p. ej. /explicar). Así no salta a un layout admin que confunde.
 *
 * Comportamiento de navegación desde el sidebar:
 *  - "Nuevo chat" → navega a `/`
 *  - Click en conversación → navega a `/?conv=<id>` (la página `/` la
 *    carga automáticamente al detectar el query param)
 *  - "Eliminar" → llama la API y refresca la lista localmente
 */
export default function ChatLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const [conversaciones, setConversaciones] = useState<ConversacionResumen[]>([]);

  useEffect(() => {
    if (!getToken()) {
      router.replace('/login');
      return;
    }
    obtenerPerfil()
      .then(setUsuario)
      .catch(() => router.replace('/login'));
    cargar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function cargar() {
    try {
      setConversaciones(await listarConversaciones());
    } catch {
      /* noop */
    }
  }

  return (
    <div className="flex h-screen overflow-hidden bg-bg text-text">
      <ChatSidebar
        conversaciones={conversaciones}
        activaId={null}
        usuario={usuario}
        onNueva={() => router.push('/')}
        onSeleccionar={(id) => router.push(`/?conv=${id}`)}
        onEliminar={async (id) => {
          await eliminarConversacion(id);
          cargar();
        }}
      />
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        {children}
      </main>
    </div>
  );
}
