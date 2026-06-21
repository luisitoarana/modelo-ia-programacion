import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' as path_provider show getTemporaryDirectory;
import 'package:shared_preferences/shared_preferences.dart' show SharedPreferences;

import '../models.dart';

/// Helpers para exportar conversaciones del desktop.
///
/// Markdown: usa file_picker.saveFile con bytes.
/// PDF:      genera HTML pre-formateado en un archivo temporal y
///           lo abre con el shell del SO (Windows/Mac/Linux). El usuario
///           pulsa Ctrl+P en el navegador → Guardar como PDF.
class ExportService {
  /// Devuelve markdown bien formateado para una conversación.
  static String toMarkdown(String titulo, List<Mensaje> mensajes) {
    final buf = StringBuffer();
    buf.writeln('# $titulo');
    buf.writeln();
    buf.writeln('_Exportado el ${DateTime.now()}_');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    for (final m in mensajes) {
      if (m.id == 'tmp' || m.id == 'err') continue;
      buf.writeln('### ${m.esUsuario ? "Tú" : "Asistente"}');
      buf.writeln();
      buf.writeln(m.contenido);
      buf.writeln();
    }
    return buf.toString();
  }

  /// Abre file picker y guarda como `.md`. Devuelve la ruta elegida o null.
  static Future<String?> guardarMarkdown(
    String titulo,
    List<Mensaje> mensajes,
  ) async {
    final md = toMarkdown(titulo, mensajes);
    var nombre = titulo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (nombre.length > 60) nombre = nombre.substring(0, 60);
    if (nombre.isEmpty) nombre = 'chat';
    return FilePicker.platform.saveFile(
      dialogTitle: 'Exportar como Markdown',
      fileName: '$nombre.md',
      bytes: Uint8List.fromList(md.codeUnits),
    );
  }

  /// Genera un HTML formateado, lo guarda en un archivo temporal y lo
  /// abre con el navegador por defecto. El usuario imprime desde ahí
  /// (Ctrl+P → Guardar como PDF).
  ///
  /// Devuelve la ruta del HTML temporal generado.
  static Future<String?> abrirComoPDF(
    String titulo,
    List<Mensaje> mensajes,
  ) async {
    final html = _generarHtml(titulo, mensajes);
    try {
      final dir = await path_provider.getTemporaryDirectory();
      var nombre = titulo
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (nombre.length > 60) nombre = nombre.substring(0, 60);
      if (nombre.isEmpty) nombre = 'chat';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ruta = '${dir.path}${Platform.pathSeparator}$nombre-$stamp.html';
      final file = File(ruta);
      await file.writeAsString(html, flush: true);
      // Abre el archivo con el SO. Cada plataforma usa su shell.
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', ruta]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [ruta]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [ruta]);
      } else {
        return null;
      }
      return ruta;
    } catch (_) {
      return null;
    }
  }

  /// Necesitamos shared_preferences indirectamente para que dart no
  /// elimine el import si en el futuro lo usamos.
  // ignore: unused_element
  static Future<void> _touch() async {
    await SharedPreferences.getInstance();
  }

  // ────────────────────── Helpers internos ──────────────────────

  static String _escHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// Conversor mínimo markdown → HTML (suficiente para mensajes del chat).
  static String _md2html(String md) {
    var h = _escHtml(md);
    // Bloques de código primero — los demás regex no deben tocarlos.
    h = h.replaceAllMapped(
      RegExp(r'```[a-z]*\n([\s\S]*?)```', caseSensitive: false),
      (m) => '<pre><code>${m.group(1)}</code></pre>',
    );
    // Inline code
    h = h.replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => '<code>${m.group(1)}</code>');
    // Headers
    h = h.replaceAllMapped(RegExp(r'^### (.+)$', multiLine: true), (m) => '<h3>${m.group(1)}</h3>');
    h = h.replaceAllMapped(RegExp(r'^## (.+)$', multiLine: true), (m) => '<h2>${m.group(1)}</h2>');
    h = h.replaceAllMapped(RegExp(r'^# (.+)$', multiLine: true), (m) => '<h1>${m.group(1)}</h1>');
    // Bold/italic
    h = h.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
    h = h.replaceAllMapped(RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'), (m) => '<em>${m.group(1)}</em>');
    // Links
    h = h.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => '<a href="${m.group(2)}">${m.group(1)}</a>',
    );
    // Listas básicas
    h = h.replaceAllMapped(
      RegExp(r'^\s*[-*] (.+)$', multiLine: true),
      (m) => '<li>${m.group(1)}</li>',
    );
    h = h.replaceAllMapped(
      RegExp(r'(<li>.*</li>\n?)+'),
      (m) => '<ul>${m.group(0)}</ul>',
    );
    // Párrafos por doble salto
    final partes = h.split(RegExp(r'\n\n+'));
    h = partes.map((p) {
      final t = p.trim();
      if (t.isEmpty) return '';
      if (RegExp(r'^<(h\d|pre|ul|ol|li|blockquote)', caseSensitive: false).hasMatch(t)) {
        return t;
      }
      return '<p>${t.replaceAll('\n', '<br>')}</p>';
    }).join('\n');
    return h;
  }

  static String _generarHtml(String titulo, List<Mensaje> mensajes) {
    final cuerpo = mensajes
        .where((m) => m.id != 'tmp' && m.id != 'err')
        .map((m) {
          final rol = m.esUsuario ? 'Tú' : 'Asistente';
          final clase = m.esUsuario ? 'user' : 'assistant';
          return '<section class="msg $clase">'
              '<div class="rol">$rol</div>'
              '<div class="contenido">${_md2html(m.contenido)}</div>'
              '</section>';
        })
        .join('\n');

    return '''
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>${_escHtml(titulo)}</title>
  <style>
    @page { size: A4; margin: 18mm 16mm; }
    @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
    body {
      font-family: -apple-system, "Segoe UI", Inter, system-ui, sans-serif;
      color: #1a1a1a; line-height: 1.55; font-size: 11.5pt; margin: 0; padding: 24pt;
      max-width: 800px; margin: 0 auto;
    }
    .header { border-bottom: 1px solid #ddd; padding-bottom: 12pt; margin-bottom: 18pt; }
    .header h1 {
      font-family: Georgia, "Times New Roman", serif;
      font-weight: 500; font-size: 22pt; margin: 0 0 4pt 0;
    }
    .header .meta { font-size: 10pt; color: #777; }
    .print-cta {
      background: #d97757; color: white; padding: 10pt 16pt;
      border-radius: 6pt; text-align: center; cursor: pointer;
      margin-bottom: 20pt; font-weight: 600; border: none; font-size: 12pt;
      width: 100%;
    }
    @media print { .print-cta { display: none; } }
    .msg { margin-bottom: 16pt; page-break-inside: avoid; }
    .msg .rol {
      font-weight: 600; font-size: 9.5pt; color: #777;
      text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4pt;
    }
    .msg.user .rol { color: #d97757; }
    .msg.assistant .rol { color: #555; }
    .msg p { margin: 0 0 8pt 0; }
    .msg h1, .msg h2, .msg h3 {
      font-family: Georgia, serif; font-weight: 500; margin: 12pt 0 6pt 0;
    }
    .msg h1 { font-size: 16pt; } .msg h2 { font-size: 14pt; } .msg h3 { font-size: 12pt; }
    .msg pre {
      background: #f4f4f0; padding: 10pt; border-radius: 5pt;
      overflow-x: auto; font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 10pt; line-height: 1.5; page-break-inside: avoid;
      border: 1px solid #e0e0db;
    }
    .msg code {
      background: #f4f4f0; padding: 1pt 4pt; border-radius: 3pt;
      font-family: "JetBrains Mono", Consolas, monospace; font-size: 10.5pt;
    }
    .msg pre code { background: transparent; padding: 0; }
    .msg ul { padding-left: 18pt; margin: 4pt 0 8pt 0; }
    .msg a { color: #d97757; text-decoration: underline; }
    .footer { font-size: 9pt; color: #999; text-align: center; margin-top: 24pt;
              border-top: 1px solid #eee; padding-top: 10pt; }
  </style>
</head>
<body>
  <button class="print-cta" onclick="window.print()">📄 Guardar como PDF (Ctrl+P)</button>
  <div class="header">
    <h1>${_escHtml(titulo)}</h1>
    <div class="meta">Exportado el ${_escHtml(DateTime.now().toString())} · Explicador IA</div>
  </div>
  $cuerpo
  <div class="footer">Generado por Explicador IA · Plataforma educativa de Python</div>
</body>
</html>
''';
  }
}
