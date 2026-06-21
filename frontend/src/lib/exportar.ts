/**
 * Helpers para exportar conversaciones.
 *
 * Markdown: descarga directa de un .md generado en memoria.
 * PDF:      usa la API nativa window.print() con un documento HTML
 *           pre-formateado en una ventana nueva. El usuario elige
 *           "Guardar como PDF" en el diálogo de impresión. Sin deps.
 */

export interface MensajeExport {
  rol: 'usuario' | 'asistente';
  contenido: string;
  id?: string;
}

/** Sanitiza un título para usarlo como nombre de archivo. */
function nombreArchivo(titulo: string, ext: string): string {
  let n = titulo
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (n.length > 60) n = n.substring(0, 60);
  if (!n) n = 'chat';
  return `${n}.${ext}`;
}

/** Convierte mensajes a markdown estructurado. */
export function aMarkdown(titulo: string, mensajes: MensajeExport[]): string {
  const lineas: string[] = [
    `# ${titulo}`,
    '',
    `_Exportado el ${new Date().toLocaleString()}_`,
    '',
    '---',
    ''
  ];
  for (const m of mensajes) {
    if (m.id === 'tmp-user' || m.id === 'err') continue;
    lineas.push(`### ${m.rol === 'usuario' ? 'Tú' : 'Asistente'}`);
    lineas.push('');
    lineas.push(m.contenido);
    lineas.push('');
  }
  return lineas.join('\n');
}

/** Descarga la conversación como archivo .md */
export function descargarMarkdown(titulo: string, mensajes: MensajeExport[]) {
  const md = aMarkdown(titulo, mensajes);
  const blob = new Blob([md], { type: 'text/markdown;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nombreArchivo(titulo, 'md');
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/** Escapa HTML para evitar XSS en el documento de impresión. */
function escHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Conversor mínimo markdown→HTML (suficiente para el chat). */
function md2html(md: string): string {
  let h = escHtml(md);
  // Bloques de código primero (no escapar de nuevo).
  h = h.replace(/```([a-z]*)\n([\s\S]*?)```/gi,
    (_, _lang, code) => `<pre><code>${code}</code></pre>`);
  // Inline code
  h = h.replace(/`([^`\n]+)`/g, '<code>$1</code>');
  // Headers
  h = h.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  h = h.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  h = h.replace(/^# (.+)$/gm, '<h1>$1</h1>');
  // Bold / italic
  h = h.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  h = h.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>');
  // Links
  h = h.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  // Listas (muy básico)
  h = h.replace(/^\s*[-*] (.+)$/gm, '<li>$1</li>');
  h = h.replace(/(<li>.*<\/li>\n?)+/g, (m) => `<ul>${m}</ul>`);
  // Párrafos: doble salto = nuevo párrafo
  h = h.split(/\n\n+/).map((p) => {
    const t = p.trim();
    if (!t) return '';
    // Si ya empieza con un tag de bloque, no envolver en <p>.
    if (/^<(h\d|pre|ul|ol|li|blockquote)/i.test(t)) return t;
    return `<p>${t.replace(/\n/g, '<br>')}</p>`;
  }).join('\n');
  return h;
}

/** Abre una ventana de impresión con la conversación lista para guardar como PDF. */
export function descargarPDF(titulo: string, mensajes: MensajeExport[]) {
  const w = window.open('', '_blank', 'width=820,height=900');
  if (!w) {
    alert('Tu navegador bloqueó la ventana de impresión. Permite popups y reintenta.');
    return;
  }

  // Construir HTML con estilos para impresión.
  const mensajesHtml = mensajes
    .filter((m) => m.id !== 'tmp-user' && m.id !== 'err')
    .map((m) => {
      const rol = m.rol === 'usuario' ? 'Tú' : 'Asistente';
      const clase = m.rol === 'usuario' ? 'user' : 'assistant';
      return `<section class="msg ${clase}">
        <div class="rol">${rol}</div>
        <div class="contenido">${md2html(m.contenido)}</div>
      </section>`;
    })
    .join('\n');

  const html = `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>${escHtml(titulo)}</title>
  <style>
    @page { size: A4; margin: 18mm 16mm; }
    @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
    body {
      font-family: -apple-system, Segoe UI, Inter, system-ui, sans-serif;
      color: #1a1a1a; line-height: 1.55; font-size: 11.5pt; margin: 0;
    }
    .header { border-bottom: 1px solid #ddd; padding-bottom: 12pt; margin-bottom: 18pt; }
    .header h1 {
      font-family: Georgia, "Times New Roman", serif;
      font-weight: 500; font-size: 22pt; margin: 0 0 4pt 0; color: #1a1a1a;
    }
    .header .meta { font-size: 10pt; color: #777; }
    .msg { margin-bottom: 16pt; page-break-inside: avoid; }
    .msg .rol {
      font-weight: 600; font-size: 9.5pt; color: #777;
      text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4pt;
    }
    .msg.user .rol { color: #d97757; }
    .msg.assistant .rol { color: #555; }
    .msg .contenido { color: #2a2a2a; }
    .msg p { margin: 0 0 8pt 0; }
    .msg h1, .msg h2, .msg h3 {
      font-family: Georgia, serif; font-weight: 500;
      margin: 12pt 0 6pt 0;
    }
    .msg h1 { font-size: 16pt; }
    .msg h2 { font-size: 14pt; }
    .msg h3 { font-size: 12pt; }
    .msg pre {
      background: #f4f4f0; padding: 10pt; border-radius: 5pt;
      overflow-x: auto; font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 10pt; line-height: 1.5;
      page-break-inside: avoid;
      border: 1px solid #e0e0db;
    }
    .msg code {
      background: #f4f4f0; padding: 1pt 4pt; border-radius: 3pt;
      font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 10.5pt;
    }
    .msg pre code { background: transparent; padding: 0; }
    .msg ul { padding-left: 18pt; margin: 4pt 0 8pt 0; }
    .msg li { margin: 2pt 0; }
    .msg a { color: #d97757; text-decoration: underline; }
    .footer { font-size: 9pt; color: #999; text-align: center; margin-top: 24pt; border-top: 1px solid #eee; padding-top: 10pt; }
  </style>
</head>
<body>
  <div class="header">
    <h1>${escHtml(titulo)}</h1>
    <div class="meta">Exportado el ${escHtml(new Date().toLocaleString())} · Explicador IA</div>
  </div>
  ${mensajesHtml}
  <div class="footer">Generado por Explicador IA · Plataforma educativa de Python</div>
  <script>
    // Espera a que cargue todo y dispara la impresión.
    window.addEventListener('load', () => {
      setTimeout(() => { window.print(); }, 200);
    });
  </script>
</body>
</html>`;

  w.document.open();
  w.document.write(html);
  w.document.close();
}
