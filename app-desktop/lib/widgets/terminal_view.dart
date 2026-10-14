import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../services/fs_local.dart';
import '../theme.dart';

/// Una línea del historial de la terminal interactiva.
class _Linea {
  final String texto;
  final String? prompt; // Directorio de trabajo en el momento del comando
  final bool esComando;
  final bool esError;
  final bool esInfo;
  _Linea(
    this.texto, {
    this.prompt,
    this.esComando = false,
    this.esError = false,
    this.esInfo = false,
  });
}

/// Información del shell nativo del sistema (PowerShell en Windows / Bash en Unix).
class _ShellInfo {
  final String nombre; // "powershell", "bash", "zsh"
  final String etiquetaCompleta; // "powershell", "bash"
  final String simbolo; // "PS" o "$"
  final Color color;
  const _ShellInfo({
    required this.nombre,
    required this.etiquetaCompleta,
    required this.simbolo,
    required this.color,
  });
}

_ShellInfo _detectarShell() {
  if (!soportaDiscoLocal) {
    return const _ShellInfo(
      nombre: 'no disponible',
      etiquetaCompleta: 'no disponible',
      simbolo: '\$',
      color: AppColors.warning,
    );
  }
  try {
    if (Platform.isWindows) {
      return const _ShellInfo(
        nombre: 'powershell',
        etiquetaCompleta: 'powershell',
        simbolo: 'PS',
        color: Color(0xFF38BDF8),
      );
    }
    if (Platform.isMacOS) {
      return const _ShellInfo(
        nombre: 'zsh',
        etiquetaCompleta: 'zsh',
        simbolo: '\$',
        color: Color(0xFF4ADE80),
      );
    }
    if (Platform.isLinux) {
      return const _ShellInfo(
        nombre: 'bash',
        etiquetaCompleta: 'bash',
        simbolo: '\$',
        color: Color(0xFF4ADE80),
      );
    }
  } catch (_) {}
  return const _ShellInfo(
    nombre: 'bash',
    etiquetaCompleta: 'bash',
    simbolo: '\$',
    color: Color(0xFF4ADE80),
  );
}

/// Terminal interactiva estilo Visual Studio Code.
///
/// Integra ejecución nativa en PowerShell (Windows) o Bash/Zsh (Unix),
/// historial continuo de comandos, atajos de flechas arriba/abajo y diseño
/// idéntico al panel de terminal integrado de VS Code.
class TerminalView extends StatefulWidget {
  final String? cwdInicial;
  final bool compacta;
  final VoidCallback? onIrASalida;
  final VoidCallback? onIrAProblemas;
  final int contadorProblemas;
  const TerminalView({
    super.key,
    this.cwdInicial,
    this.compacta = false,
    this.onIrASalida,
    this.onIrAProblemas,
    this.contadorProblemas = 0,
  });

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final List<_Linea> _historial = [];
  final List<String> _comandosPrevios = [];
  int _indiceHistorial = -1;
  String? _cwd;
  bool _ejecutando = false;
  late final _ShellInfo _shell;

  @override
  void initState() {
    super.initState();
    _shell = _detectarShell();
    _intentarCwdInicial();

    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyL) {
          _limpiar();
          _ctrl.clear();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    // Mensaje de bienvenida oficial de PowerShell / Terminal
    if (Platform.isWindows) {
      _historial.add(_Linea(
        'Windows PowerShell\nCopyright (C) Microsoft Corporation. Todos los derechos reservados.\n\nInstala la versión más reciente de PowerShell para nuevas características: https://aka.ms/PSWindows\n',
        esInfo: true,
      ));
    } else {
      _historial.add(_Linea(
        'Terminal de sistema lista (${_shell.nombre}).\n',
        esInfo: true,
      ));
    }
  }

  void _intentarCwdInicial() {
    if (widget.cwdInicial != null && widget.cwdInicial!.isNotEmpty) {
      _cwd = widget.cwdInicial;
      return;
    }
    try {
      if (!kIsWeb) {
        final home = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          _cwd = home;
        }
      }
    } catch (_) {}
  }

  /// Permite a un widget padre (la vista Code) cambiar el cwd de la terminal.
  void cambiarCwd(String nuevoCwd) {
    if (_cwd == nuevoCwd) return;
    setState(() {
      _cwd = nuevoCwd;
    });
  }

  /// Ejecuta un comando en la terminal interactiva (útil desde el editor de código).
  Future<void> ejecutarComando(String comando) async {
    _ctrl.text = comando;
    await _ejecutar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _limpiar() {
    setState(() => _historial.clear());
  }

  bool _manejarComandoLocal(String cmd) {
    final partes = cmd.trim().split(RegExp(r'\s+'));
    final base = partes.first.toLowerCase();

    if (base == 'clear' || base == 'cls') {
      _limpiar();
      return true;
    }

    if (base == 'pwd') {
      setState(() => _historial.add(_Linea(_cwd ?? '(sin carpeta de trabajo)')));
      return true;
    }

    if (base == 'cd') {
      if (partes.length == 1) {
        setState(() => _historial.add(_Linea(_cwd ?? '(sin carpeta)')));
        return true;
      }
      var destino = partes.skip(1).join(' ');
      if ((destino.startsWith('"') && destino.endsWith('"')) ||
          (destino.startsWith("'") && destino.endsWith("'"))) {
        destino = destino.substring(1, destino.length - 1);
      }
      _cambiarCwd(destino);
      return true;
    }

    return false;
  }

  void _cambiarCwd(String destino) {
    if (_cwd == null && !_esAbsoluta(destino)) {
      setState(() => _historial.add(_Linea(
            'cd: Ruta no válida o relativa sin base.',
            esError: true,
          )));
      return;
    }
    String nueva;
    if (destino == '..') {
      nueva = _padre(_cwd!);
    } else if (destino == '.') {
      nueva = _cwd!;
    } else if (_esAbsoluta(destino)) {
      nueva = destino;
    } else {
      final sep = _cwd!.contains('\\') ? '\\' : '/';
      final base = _cwd!.endsWith(sep)
          ? _cwd!.substring(0, _cwd!.length - 1)
          : _cwd!;
      nueva = '$base$sep$destino';
    }
    setState(() => _cwd = nueva);
  }

  bool _esAbsoluta(String ruta) {
    return ruta.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(ruta) ||
        ruta.startsWith(r'\\');
  }

  String _padre(String ruta) {
    final sep = ruta.contains('\\') ? '\\' : '/';
    final partes = ruta.split(RegExp(r'[/\\]'))
      ..removeWhere((s) => s.isEmpty);
    if (partes.length <= 1) {
      return ruta.contains(':') ? '${partes.first}$sep' : sep;
    }
    partes.removeLast();
    final prefijo = ruta.contains(':') ? '' : sep;
    return '$prefijo${partes.join(sep)}';
  }

  Future<void> _ejecutar() async {
    final cmd = _ctrl.text.trim();
    if (cmd.isEmpty || _ejecutando) return;
    _ctrl.clear();
    _comandosPrevios.add(cmd);
    _indiceHistorial = _comandosPrevios.length;

    final promptAlLanzar = _cwd ?? '~';

    final cmdLower = cmd.split(RegExp(r'\s+')).first.toLowerCase();
    if (cmdLower == 'cd' ||
        cmdLower == 'pwd' ||
        cmdLower == 'clear' ||
        cmdLower == 'cls') {
      setState(() => _historial
          .add(_Linea(cmd, prompt: promptAlLanzar, esComando: true)));
      _manejarComandoLocal(cmd);
      _scrollAlFinal();
      return;
    }

    setState(() {
      _historial.add(_Linea(cmd, prompt: promptAlLanzar, esComando: true));
      _ejecutando = true;
    });
    _scrollAlFinal();

    final r = await ejecutarComandoLocal(cmd, cwd: _cwd);
    if (!mounted) return;
    setState(() {
      if (r.salida.isNotEmpty) {
        _historial.add(_Linea(r.salida, esError: r.codigo != 0));
      }
      _ejecutando = false;
    });
    _scrollAlFinal();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _historialArriba() {
    if (_comandosPrevios.isEmpty) return;
    setState(() {
      _indiceHistorial =
          (_indiceHistorial - 1).clamp(0, _comandosPrevios.length);
      if (_indiceHistorial < _comandosPrevios.length) {
        _ctrl.text = _comandosPrevios[_indiceHistorial];
        _ctrl.selection =
            TextSelection.collapsed(offset: _ctrl.text.length);
      }
    });
  }

  void _historialAbajo() {
    if (_comandosPrevios.isEmpty) return;
    setState(() {
      _indiceHistorial =
          (_indiceHistorial + 1).clamp(0, _comandosPrevios.length);
      if (_indiceHistorial >= _comandosPrevios.length) {
        _ctrl.clear();
      } else {
        _ctrl.text = _comandosPrevios[_indiceHistorial];
        _ctrl.selection =
            TextSelection.collapsed(offset: _ctrl.text.length);
      }
    });
  }

  String _formatearPrompt(String ruta) {
    if (_shell.simbolo == 'PS') {
      return 'PS $ruta>';
    }
    return '$ruta \$';
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      color: p.codeBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de pestañas y herramientas estilo Visual Studio Code
          _barraSuperiorVsCode(p),
          // Buffer único de consola (scroll continuo + cursor activo en el flujo)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _focus.requestFocus(),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Historial previo de líneas impresas
                    for (final linea in _historial) _renderLinea(p, linea),

                    // Indicador si está ejecutando
                    if (_ejecutando)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              height: 12,
                              width: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor: AlwaysStoppedAnimation<Color>(p.primary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ejecutando...',
                              style: TextStyle(
                                fontFamily: AppFonts.monoFallback.first,
                                fontSize: 12,
                                color: p.subtle,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Línea activa del Prompt de PowerShell (exactamente igual a VS Code)
                    if (!_ejecutando)
                      Shortcuts(
                        shortcuts: <ShortcutActivator, Intent>{
                          const SingleActivator(LogicalKeyboardKey.arrowUp):
                              const _HistArribaIntent(),
                          const SingleActivator(LogicalKeyboardKey.arrowDown):
                              const _HistAbajoIntent(),
                          const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                              const _LimpiarIntent(),
                        },
                        child: Actions(
                          actions: <Type, Action<Intent>>{
                            _HistArribaIntent:
                                CallbackAction<_HistArribaIntent>(onInvoke: (_) {
                              _historialArriba();
                              return null;
                            }),
                            _HistAbajoIntent:
                                CallbackAction<_HistAbajoIntent>(onInvoke: (_) {
                              _historialAbajo();
                              return null;
                            }),
                            _LimpiarIntent:
                                CallbackAction<_LimpiarIntent>(onInvoke: (_) {
                              _limpiar();
                              return null;
                            }),
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatearPrompt(_cwd ?? '~'),
                                  style: TextStyle(
                                    fontFamily: AppFonts.monoFallback.first,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _shell.color,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _ctrl,
                                    focusNode: _focus,
                                    autofocus: true,
                                    maxLines: 1,
                                    onSubmitted: (_) => _ejecutar(),
                                    style: TextStyle(
                                      fontFamily: AppFonts.monoFallback.first,
                                      fontSize: 12.5,
                                      color: p.codeText,
                                      height: 1.45,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraSuperiorVsCode(AppPalette p) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Pestaña activa TERMINAL estilo VS Code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: p.primary, width: 2),
              ),
            ),
            child: Text(
              'TERMINAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: p.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Registro y salida de ejecución del programa',
            child: InkWell(
              onTap: widget.onIrASalida,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  'SALIDA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: widget.onIrASalida != null ? p.muted : p.subtle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Lista de errores sintácticos y excepciones detectadas',
            child: InkWell(
              onTap: widget.onIrAProblemas,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      'PROBLEMAS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: widget.onIrAProblemas != null ? p.muted : p.subtle,
                      ),
                    ),
                    if (widget.contadorProblemas > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.contadorProblemas}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // Selector de instancia activa: "1: powershell"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.borderSoft),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, size: 12, color: _shell.color),
                const SizedBox(width: 5),
                Text(
                  '1: ${_shell.etiquetaCompleta}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                    fontFamily: AppFonts.monoFallback.first,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Botón Nuevo terminal / Reiniciar (+)
          Tooltip(
            message: 'Nuevo terminal / Reiniciar',
            child: InkWell(
              onTap: () {
                _limpiar();
                _focus.requestFocus();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.add_rounded, size: 15, color: p.muted),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Botón Eliminar / Limpiar terminal (Trash)
          Tooltip(
            message: 'Limpiar terminal (Ctrl+L)',
            child: InkWell(
              onTap: _limpiar,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.delete_outline_rounded, size: 15, color: p.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderLinea(AppPalette p, _Linea linea) {
    if (linea.esInfo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText(
          linea.texto,
          style: TextStyle(
            fontFamily: AppFonts.monoFallback.first,
            fontSize: 12,
            color: p.codeText.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
      );
    }
    if (linea.esComando) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontSize: 12.5,
              height: 1.45,
            ),
            children: [
              TextSpan(
                text: _formatearPrompt(linea.prompt ?? '~'),
                style: TextStyle(
                  color: _shell.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: linea.texto,
                style: TextStyle(color: p.codeText, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final esFallo = linea.esError ||
        linea.texto.contains('Traceback') ||
        linea.texto.contains('Error:') ||
        linea.texto.contains('Exception:');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            linea.texto,
            style: TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontSize: 12.5,
              height: 1.4,
              color: linea.esError
                  ? const Color(0xFFF87171) // Rojo error suave
                  : p.codeText.withValues(alpha: 0.9),
            ),
          ),
          if (esFallo && linea.texto.trim().length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: InkWell(
                onTap: () async {
                  setState(() {
                    _historial.add(_Linea('🤖 Consultando al Asistente IA sobre este error…', esInfo: true));
                  });
                  _scrollAlFinal();
                  try {
                    final auth = context.read<AuthProvider>();
                    final settings = context.read<SettingsProvider>();
                    final prompt = 'Explica brevemente y de forma didáctica en español este error de ejecución de la terminal y cómo resolverlo:\n```\n${linea.texto}\n```';
                    final resp = await auth.api.mensajeRapido(
                      prompt,
                      idioma: settings.idioma,
                      proveedor: settings.proveedor,
                      modoAcompanamiento: settings.modoAcompanamiento,
                      nivelModulo: settings.nivelModulo,
                    );
                    if (!mounted) return;
                    setState(() {
                      _historial.add(_Linea(
                        '💡 Explicación del Asistente IA:\n${resp.mensajeAsistente.contenido.trim()}',
                        esInfo: true,
                      ));
                    });
                    _scrollAlFinal();
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _historial.add(_Linea('Error al consultar al asistente: $e', esError: true));
                    });
                    _scrollAlFinal();
                  }
                },
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: AppColors.danger),
                      const SizedBox(width: 5),
                      Text(
                        'Explicar este error con IA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistArribaIntent extends Intent {
  const _HistArribaIntent();
}

class _HistAbajoIntent extends Intent {
  const _HistAbajoIntent();
}

class _LimpiarIntent extends Intent {
  const _LimpiarIntent();
}
