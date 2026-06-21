import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fs_local.dart';
import '../theme.dart';

/// Una línea del historial de la terminal.
class _Linea {
  final String texto;
  final String? prompt; // cwd al momento del comando, si es comando
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

/// Información del shell real que usa el backend.
class _ShellInfo {
  final String nombre; // "cmd", "sh", "no disponible"
  final String etiquetaCompleta; // "CMD (Windows)" etc.
  final String simbolo; // "$" o ">"
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
      etiquetaCompleta: 'Terminal no disponible en web',
      simbolo: '\$',
      color: AppColors.warning,
    );
  }
  // ejecutarComandoLocal usa cmd /c en Windows y /bin/sh -c en el resto.
  try {
    if (Platform.isWindows) {
      return const _ShellInfo(
        nombre: 'cmd',
        etiquetaCompleta: 'CMD · Windows',
        simbolo: '>',
        color: AppColors.info,
      );
    }
    if (Platform.isMacOS) {
      return const _ShellInfo(
        nombre: 'sh',
        etiquetaCompleta: 'sh · macOS',
        simbolo: '\$',
        color: AppColors.info,
      );
    }
    if (Platform.isLinux) {
      return const _ShellInfo(
        nombre: 'sh',
        etiquetaCompleta: 'sh · Linux',
        simbolo: '\$',
        color: AppColors.info,
      );
    }
  } catch (_) {}
  return const _ShellInfo(
    nombre: 'sh',
    etiquetaCompleta: 'sh',
    simbolo: '\$',
    color: AppColors.info,
  );
}

/// Terminal interactiva con shell real del SO.
///
/// [cwdInicial] permite arrancar la terminal directamente en un
/// directorio concreto — útil cuando se embebe en la vista Code para
/// que el `cd` ya esté en la carpeta del archivo abierto.
///
/// [compacta] reduce paddings y oculta el header descriptivo — pensado
/// para cuando se mete como panel inferior de otra vista (vista Code).
class TerminalView extends StatefulWidget {
  final String? cwdInicial;
  final bool compacta;
  const TerminalView({super.key, this.cwdInicial, this.compacta = false});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
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
    // Sin mensaje inicial — el caret en `_emptyConsola` ya indica que está lista.
  }

  void _intentarCwdInicial() {
    // Si el caller (vista Code) nos pasó un cwd explícito, lo usamos.
    if (widget.cwdInicial != null && widget.cwdInicial!.isNotEmpty) {
      _cwd = widget.cwdInicial;
      return;
    }
    // En desktop intentamos arrancar en el directorio del usuario para
    // que se vea siempre dónde estás (no esperar al "Cambiar carpeta").
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

  /// Permite a un widget padre (la vista Code) cambiar el cwd de la
  /// terminal cuando el usuario abre un archivo distinto.
  void cambiarCwd(String nuevoCwd) {
    if (_cwd == nuevoCwd) return;
    setState(() {
      _cwd = nuevoCwd;
      _historial.add(_Linea('cd "$nuevoCwd"  (automático)', esInfo: true));
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _elegirCarpeta() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      setState(() {
        _cwd = dir;
        _historial.add(_Linea('cambiado a: $dir', esInfo: true));
      });
      _scrollAlFinal();
    }
  }

  void _irAHome() {
    try {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        setState(() {
          _cwd = home;
          _historial.add(_Linea('cambiado a: $home', esInfo: true));
        });
        _scrollAlFinal();
      }
    } catch (_) {}
  }

  void _subirNivel() {
    if (_cwd == null) return;
    final padre = _padre(_cwd!);
    setState(() {
      _cwd = padre;
      _historial.add(_Linea('cambiado a: $padre', esInfo: true));
    });
    _scrollAlFinal();
  }

  void _limpiar() {
    setState(() => _historial.clear());
  }

  /// Resuelve `cd <ruta>` localmente — el cwd se mantiene en estado Dart.
  bool _manejarComandoLocal(String cmd) {
    final partes = cmd.trim().split(RegExp(r'\s+'));
    final base = partes.first.toLowerCase();

    if (base == 'clear' || base == 'cls') {
      _limpiar();
      return true;
    }

    if (base == 'pwd') {
      setState(() => _historial
          .add(_Linea(_cwd ?? '(sin carpeta de trabajo)')));
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
            'cd: necesitas una carpeta base. Usa el botón "Carpeta" o '
            'pasa una ruta absoluta (p. ej. C:\\Users).',
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
      _historial.add(_Linea(
        r.salida.isEmpty ? '(sin salida)' : r.salida,
        esError: r.codigo != 0,
      ));
      _ejecutando = false;
    });
    _scrollAlFinal();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
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

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      color: p.bg,
      child: Column(
        children: [
          _header(p),
          _cwdBanner(p),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Expanded(child: _consola(p)),
                  const SizedBox(height: 10),
                  _promptInput(p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header con título + shell badge + botón limpiar ───
  Widget _header(AppPalette p) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 18, color: p.primary),
          const SizedBox(width: 10),
          Text(
            'Terminal',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(width: 10),
          // Badge con el shell real
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _shell.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _shell.color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 11, color: _shell.color),
                const SizedBox(width: 5),
                Text(
                  _shell.etiquetaCompleta,
                  style: TextStyle(
                    color: _shell.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.monoFallback.first,
                    fontFamilyFallback: AppFonts.monoFallback,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Limpiar (Ctrl+L)',
            child: IconButton(
              onPressed: _historial.isEmpty ? null : _limpiar,
              icon: Icon(Icons.cleaning_services_outlined,
                  size: 16, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Banner con el CWD prominente + botones de navegación ───
  Widget _cwdBanner(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: p.primary),
          const SizedBox(width: 8),
          Text(
            'Estás en:',
            style: TextStyle(
              fontSize: 12,
              color: p.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.borderSoft),
              ),
              child: SelectableText(
                _cwd ?? '(ninguna carpeta seleccionada · usa "Cambiar")',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  color: _cwd == null ? p.subtle : p.text,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _BotonChip(
            icon: Icons.arrow_upward,
            tooltip: 'Subir un nivel (cd ..)',
            onTap: _cwd == null ? null : _subirNivel,
          ),
          const SizedBox(width: 4),
          _BotonChip(
            icon: Icons.home_outlined,
            tooltip: 'Ir a Inicio (carpeta personal)',
            onTap: _irAHome,
          ),
          const SizedBox(width: 4),
          _BotonChip(
            icon: Icons.folder_open,
            tooltip: 'Cambiar carpeta…',
            onTap: _elegirCarpeta,
            destacado: true,
          ),
        ],
      ),
    );
  }

  Widget _consola(AppPalette p) {
    if (_historial.isEmpty && !_ejecutando) {
      return _emptyConsola(p);
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scroll,
          itemCount: _historial.length + (_ejecutando ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == _historial.length && _ejecutando) {
              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      height: 11,
                      width: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: p.codeText.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ejecutando…',
                      style: TextStyle(
                        fontFamily: AppFonts.monoFallback.first,
                        fontFamilyFallback: AppFonts.monoFallback,
                        fontSize: 12.5,
                        color: p.codeText.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              );
            }
            return _LineaTerminal(linea: _historial[i], shell: _shell);
          },
        ),
      ),
    );
  }

  /// Consola vacía — sólo el caret parpadeante, sin texto tutorial.
  Widget _emptyConsola(AppPalette p) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.all(14),
      alignment: Alignment.topLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _shell.simbolo,
            style: TextStyle(
              color: p.codeText.withValues(alpha: 0.35),
              fontSize: 13,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
          const SizedBox(width: 8),
          _CursorParpadeante(color: p.codeText.withValues(alpha: 0.4)),
        ],
      ),
    );
  }

  Widget _promptInput(AppPalette p) {
    final mostrarPrompt = _cwd ?? '~';
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              mostrarPrompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.muted,
                fontFamily: AppFonts.monoFallback.first,
                fontFamilyFallback: AppFonts.monoFallback,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _shell.simbolo,
            style: TextStyle(
              color: p.primary,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Shortcuts(
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
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onSubmitted: (_) => _ejecutar(),
                  style: TextStyle(
                    fontFamily: AppFonts.monoFallback.first,
                    fontFamilyFallback: AppFonts.monoFallback,
                    fontSize: 13,
                    color: p.text,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        Platform.isWindows ? 'dir · python --version · …'
                                            : 'ls · python --version · …',
                    hintStyle: TextStyle(
                      color: p.subtle,
                      fontFamily: AppFonts.monoFallback.first,
                      fontFamilyFallback: AppFonts.monoFallback,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _BotonEjecutar(
            ejecutando: _ejecutando,
            onTap: _ejecutar,
          ),
        ],
      ),
    );
  }
}

class _LineaTerminal extends StatelessWidget {
  final _Linea linea;
  final _ShellInfo shell;
  const _LineaTerminal({required this.linea, required this.shell});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (linea.esInfo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.codeText.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: p.codeText.withValues(alpha: 0.12)),
          ),
          child: SelectableText(
            linea.texto,
            style: TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
              fontSize: 12,
              height: 1.55,
              color: p.codeText.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    }
    if (linea.esComando) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
              fontSize: 12.5,
              height: 1.5,
            ),
            children: [
              TextSpan(
                text: linea.prompt ?? '~',
                style: TextStyle(color: p.codeText.withValues(alpha: 0.6)),
              ),
              TextSpan(
                text: ' ${shell.simbolo} ',
                style: TextStyle(
                  color: p.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: linea.texto,
                style: TextStyle(color: p.codeText),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText(
        linea.texto,
        style: TextStyle(
          fontFamily: AppFonts.monoFallback.first,
          fontFamilyFallback: AppFonts.monoFallback,
          fontSize: 12.5,
          height: 1.5,
          color: linea.esError
              ? AppColors.danger
              : p.codeText.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _BotonChip extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool destacado;
  const _BotonChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destacado = false,
  });

  @override
  State<_BotonChip> createState() => _BotonChipState();
}

class _BotonChipState extends State<_BotonChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final habilitado = widget.onTap != null;
    final color = habilitado ? (widget.destacado ? p.primary : p.muted) : p.subtle;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              color: _hover && habilitado
                  ? color.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: p.borderSoft),
            ),
            child: Icon(widget.icon, size: 14, color: color),
          ),
        ),
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

class _BotonEjecutar extends StatefulWidget {
  final bool ejecutando;
  final VoidCallback onTap;
  const _BotonEjecutar({required this.ejecutando, required this.onTap});

  @override
  State<_BotonEjecutar> createState() => _BotonEjecutarState();
}

class _BotonEjecutarState extends State<_BotonEjecutar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.ejecutando ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? p.primaryHover : p.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.ejecutando)
                const SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.play_arrow, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              const Text(
                'Ejecutar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Widgets del empty state
// ════════════════════════════════════════════════════════════════════

class _CursorParpadeante extends StatefulWidget {
  final Color color;
  const _CursorParpadeante({required this.color});

  @override
  State<_CursorParpadeante> createState() => _CursorParpadeanteState();
}

class _CursorParpadeanteState extends State<_CursorParpadeante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(width: 7, height: 14, color: widget.color),
    );
  }
}
