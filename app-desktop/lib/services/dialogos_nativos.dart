import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Servicio de diálogos nativos seguro para evitar el crash fatal de Windows 11
/// (0xc0000005 en comdlg32.dll) cuando se invoca FilePicker en el hilo principal de Flutter.
class DialogosNativos {
  /// Selecciona una carpeta del sistema de archivos de forma 100% aislada.
  static Future<String?> seleccionarCarpeta({String? titulo}) async {
    if (Platform.isWindows) {
      try {
        final script = '''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
\$dlg.Description = '${titulo ?? "Seleccionar carpeta"}'
\$dlg.ShowNewFolderButton = \$true
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::WriteLine(\$dlg.SelectedPath)
}
''';
        final res = await Process.run(
          'powershell',
          ['-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
          stdoutEncoding: utf8,
        );
        final salida = res.stdout.toString().trim();
        if (salida.isNotEmpty && Directory(salida).existsSync()) {
          return salida;
        }
        return null;
      } catch (_) {
        // Fallback defensivo a FilePicker
      }
    }

    try {
      return await FilePicker.platform.getDirectoryPath(dialogTitle: titulo);
    } catch (_) {
      return null;
    }
  }

  /// Selecciona uno o varios archivos del sistema de archivos de forma aislada.
  static Future<List<String>> seleccionarArchivos({
    String? titulo,
    bool permitirMultiples = true,
  }) async {
    if (Platform.isWindows) {
      try {
        final multi = permitirMultiples ? '\$true' : '\$false';
        final script = '''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.OpenFileDialog
\$dlg.Title = '${titulo ?? "Abrir archivo"}'
\$dlg.Multiselect = $multi
\$dlg.Filter = "Todos los archivos (*.*)|*.*|Archivos de Código (*.py;*.js;*.html;*.css;*.json;*.md;*.txt)|*.py;*.js;*.html;*.css;*.json;*.md;*.txt"
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::WriteLine(\$dlg.FileNames -join '|')
}
''';
        final res = await Process.run(
          'powershell',
          ['-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
          stdoutEncoding: utf8,
        );
        final salida = res.stdout.toString().trim();
        if (salida.isNotEmpty) {
          final rutas = salida
              .split('|')
              .map((r) => r.trim())
              .where((r) => r.isNotEmpty && File(r).existsSync())
              .toList();
          if (rutas.isNotEmpty) return rutas;
        }
        return [];
      } catch (_) {
        // Fallback defensivo
      }
    }

    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: titulo,
        allowMultiple: permitirMultiples,
      );
      if (res != null && res.paths.isNotEmpty) {
        return res.paths.whereType<String>().toList();
      }
    } catch (_) {}
    return [];
  }

  /// Diálogo para guardar archivo con nombre sugerido.
  static Future<String?> guardarArchivo({
    String? titulo,
    String? nombreSugerido,
    String? extensionDefecto = 'py',
  }) async {
    if (Platform.isWindows) {
      try {
        final nombre = nombreSugerido ?? 'archivo.py';
        final script = '''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.SaveFileDialog
\$dlg.Title = '${titulo ?? "Guardar archivo"}'
\$dlg.FileName = '$nombre'
\$dlg.Filter = "Archivos Python (*.py)|*.py|Todos los archivos (*.*)|*.*"
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::WriteLine(\$dlg.FileName)
}
''';
        final res = await Process.run(
          'powershell',
          ['-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
          stdoutEncoding: utf8,
        );
        final salida = res.stdout.toString().trim();
        if (salida.isNotEmpty) {
          return salida;
        }
        return null;
      } catch (_) {
        // Fallback defensivo
      }
    }

    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: titulo,
        fileName: nombreSugerido,
      );
    } catch (_) {
      return null;
    }
  }
}
