import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/sidebar.dart';
import '../widgets/chat_view.dart';
import '../widgets/code_view.dart';
import '../widgets/evaluacion_estudio.dart';
import '../widgets/estudio_docente.dart';
import '../widgets/explicar_view.dart';
import '../widgets/proyecto_view.dart';
import '../widgets/terminal_view.dart';
import '../widgets/command_palette.dart';
import '../widgets/atajos_overlay.dart';
import '../widgets/onboarding.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_status_bar.dart';
import 'settings_screen.dart';

/// Pestañas principales de la app.
/// El orden importa: se usa como índice del IndexedStack.
enum VistaPrincipal { chat, explicar, code, proyecto, terminal }

// ──────────────────────── Intents para atajos ────────────────────────

class _NuevoChatIntent extends Intent { const _NuevoChatIntent(); }
class _AbrirSettingsIntent extends Intent { const _AbrirSettingsIntent(); }
class _ToggleTemaIntent extends Intent { const _ToggleTemaIntent(); }
class _ToggleSidebarIntent extends Intent { const _ToggleSidebarIntent(); }
class _VistaChatIntent extends Intent { const _VistaChatIntent(); }
class _VistaExplicarIntent extends Intent { const _VistaExplicarIntent(); }
class _VistaCodeIntent extends Intent { const _VistaCodeIntent(); }
class _VistaProyectoIntent extends Intent { const _VistaProyectoIntent(); }
class _VistaTerminalIntent extends Intent { const _VistaTerminalIntent(); }
class _CommandPaletteIntent extends Intent { const _CommandPaletteIntent(); }
class _AtajosOverlayIntent extends Intent { const _AtajosOverlayIntent(); }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VistaPrincipal _vista = VistaPrincipal.chat;
  bool _sidebarColapsado = false;
  Timer? _actualizarEstudio;
  bool _asignacionConsultada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final usuarioId = context.read<AuthProvider>().usuario?.id;
      if (usuarioId != null) context.read<SettingsProvider>().activarPerfil(usuarioId);
      context.read<SettingsProvider>().setAsignacionEstudio(const {'asignado': false});
      if (context.read<AuthProvider>().usuario?.esInvestigador == true &&
          context.read<SettingsProvider>().esBloqueadoPostTest) {
        context.read<SettingsProvider>().setModoAcompanamiento('con_acompanamiento');
      }
      _cargarAsignacionEstudio();
      // Onboarding la primera vez.
      mostrarOnboardingSiPrimeraVez(context);
    });
    // Escucha cambios de vista solicitados desde el command palette.
    eventoCambioVista.addListener(_onCambioVistaDesdePalette);
    _actualizarEstudio = Timer.periodic(const Duration(seconds: 10), (_) => _cargarAsignacionEstudio());
  }

  Future<void> _cargarAsignacionEstudio() async {
    try {
      final datos = await context.read<AuthProvider>().api.obtenerAsignacionEstudio();
      if (mounted) {
        final anterior = context.read<SettingsProvider>().faseEstudio;
        if ((!_asignacionConsultada || anterior != datos['fase']) &&
            datos['fase'] != 'pre' && datos['fase'] != 'post' && datos['pendiente_asignacion'] != true) {
          context.read<ChatProvider>().cargarConversaciones();
        }
        context.read<SettingsProvider>().setAsignacionEstudio(datos);
        setState(() {
          _asignacionConsultada = true;
          if (anterior != datos['fase']) {
            if (datos['fase'] == 'pre') _vista = VistaPrincipal.explicar;
            if (datos['fase'] == 'post') _vista = VistaPrincipal.code;
            if (datos['fase'] == 'intervencion') {
              _vista = datos['modo_efectivo'] == 'sin_acompanamiento'
                  ? VistaPrincipal.code : VistaPrincipal.explicar;
            }
          }
        });
      }
    } catch (_) {
      // Los ajustes locales siguen disponibles si el servidor no responde.
    }
  }

  @override
  void dispose() {
    _actualizarEstudio?.cancel();
    eventoCambioVista.removeListener(_onCambioVistaDesdePalette);
    super.dispose();
  }

  void _onCambioVistaDesdePalette() {
    final idx = eventoCambioVista.value;
    if (idx == null) return;
    if (!mounted) return;
    setState(() => _vista = VistaPrincipal.values[idx]);
    eventoCambioVista.value = null;
  }

  void _toggleSidebar() {
    setState(() => _sidebarColapsado = !_sidebarColapsado);
  }

  void _nuevoChat() {
    context.read<ChatProvider>().nueva();
    setState(() => _vista = VistaPrincipal.chat);
  }

  void _abrirSettings() {
    showSettings(context);
  }

  void _toggleTema() {
    final tema = context.read<ThemeProvider>();
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    tema.setMode(esOscuro ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Cmd/Ctrl + K — command palette
        SingleActivator(LogicalKeyboardKey.keyK, control: true): const _CommandPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): const _CommandPaletteIntent(),
        // Cmd/Ctrl + / — atajos overlay
        SingleActivator(LogicalKeyboardKey.slash, control: true): const _AtajosOverlayIntent(),
        SingleActivator(LogicalKeyboardKey.slash, meta: true): const _AtajosOverlayIntent(),
        // Cmd/Ctrl + N — nuevo chat
        SingleActivator(LogicalKeyboardKey.keyN, control: true): const _NuevoChatIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): const _NuevoChatIntent(),
        // Cmd/Ctrl + , — abrir settings
        SingleActivator(LogicalKeyboardKey.comma, control: true): const _AbrirSettingsIntent(),
        SingleActivator(LogicalKeyboardKey.comma, meta: true): const _AbrirSettingsIntent(),
        // Cmd/Ctrl + Shift + L — alternar tema
        SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true): const _ToggleTemaIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, meta: true, shift: true): const _ToggleTemaIntent(),
        // Cmd/Ctrl + B — toggle sidebar
        SingleActivator(LogicalKeyboardKey.keyB, control: true): const _ToggleSidebarIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true): const _ToggleSidebarIntent(),
        // Cmd/Ctrl + 1..4 — cambiar de pestaña
        SingleActivator(LogicalKeyboardKey.digit1, control: true): const _VistaChatIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, meta: true): const _VistaChatIntent(),
        SingleActivator(LogicalKeyboardKey.digit2, control: true): const _VistaExplicarIntent(),
        SingleActivator(LogicalKeyboardKey.digit2, meta: true): const _VistaExplicarIntent(),
        SingleActivator(LogicalKeyboardKey.digit3, control: true): const _VistaCodeIntent(),
        SingleActivator(LogicalKeyboardKey.digit3, meta: true): const _VistaCodeIntent(),
        SingleActivator(LogicalKeyboardKey.digit4, control: true): const _VistaProyectoIntent(),
        SingleActivator(LogicalKeyboardKey.digit4, meta: true): const _VistaProyectoIntent(),
        SingleActivator(LogicalKeyboardKey.digit5, control: true): const _VistaTerminalIntent(),
        SingleActivator(LogicalKeyboardKey.digit5, meta: true): const _VistaTerminalIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
            onInvoke: (_) { showCommandPalette(context); return null; },
          ),
          _AtajosOverlayIntent: CallbackAction<_AtajosOverlayIntent>(
            onInvoke: (_) { showAtajosOverlay(context); return null; },
          ),
          _NuevoChatIntent: CallbackAction<_NuevoChatIntent>(
            onInvoke: (_) { _nuevoChat(); return null; },
          ),
          _AbrirSettingsIntent: CallbackAction<_AbrirSettingsIntent>(
            onInvoke: (_) { _abrirSettings(); return null; },
          ),
          _ToggleTemaIntent: CallbackAction<_ToggleTemaIntent>(
            onInvoke: (_) { _toggleTema(); return null; },
          ),
          _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
            onInvoke: (_) { _toggleSidebar(); return null; },
          ),
          _VistaChatIntent: CallbackAction<_VistaChatIntent>(
            onInvoke: (_) { setState(() => _vista = VistaPrincipal.chat); return null; },
          ),
          _VistaExplicarIntent: CallbackAction<_VistaExplicarIntent>(
            onInvoke: (_) { setState(() => _vista = VistaPrincipal.explicar); return null; },
          ),
          _VistaCodeIntent: CallbackAction<_VistaCodeIntent>(
            onInvoke: (_) { setState(() => _vista = VistaPrincipal.code); return null; },
          ),
          _VistaProyectoIntent: CallbackAction<_VistaProyectoIntent>(
            onInvoke: (_) { setState(() => _vista = VistaPrincipal.proyecto); return null; },
          ),
          _VistaTerminalIntent: CallbackAction<_VistaTerminalIntent>(
            onInvoke: (_) { setState(() => _vista = VistaPrincipal.terminal); return null; },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: p.bg,
            body: Column(
              children: [
                AppTopBar(
                  vista: _vista,
                  onAbrirPalette: () => showCommandPalette(context),
                  onAbrirAtajos: () => showAtajosOverlay(context),
                  onAbrirSettings: _abrirSettings,
                  onToggleSidebar: _toggleSidebar,
                  sidebarColapsado: _sidebarColapsado,
                ),
                Expanded(
                  child: Row(
                    children: [
                      Sidebar(
                        vista: _vista,
                        colapsado: _sidebarColapsado,
                        onToggleColapsado: _toggleSidebar,
                        onCambiarVista: (v) => setState(() => _vista = v),
                      ),
                      Expanded(
                        child: !_asignacionConsultada
                          ? Center(child: TextButton(onPressed: _cargarAsignacionEstudio, child: const Text('Comprobar fase de estudio')))
                          : context.watch<AuthProvider>().usuario?.esInvestigador != true && context.watch<SettingsProvider>().pendienteAsignacion
                          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('El estudio está activo. Espera a que el docente asigne tu grupo y pretest; todavía no puedes utilizar la IA.')))
                          : context.watch<AuthProvider>().usuario?.esInvestigador != true && context.watch<SettingsProvider>().esBloqueadoPostTest
                          ? EvaluacionEstudio(key: ValueKey(context.watch<SettingsProvider>().faseEstudio))
                          : Column(children: [
                            if (context.watch<AuthProvider>().usuario?.esInvestigador == true)
                              TextButton.icon(onPressed: () => abrirEstudioDocente(context), icon: const Icon(Icons.science_outlined), label: const Text('Pretest, postest y revisión docente')),
                            Expanded(child: IndexedStack(
                          index: _vista.index,
                          children: const [
                            ChatView(),
                            ExplicarView(),
                            CodeView(),
                            ProyectoView(),
                            TerminalView(),
                          ],
                        )),
                          ]),
                      ),
                    ],
                  ),
                ),
                AppStatusBar(
                  vista: _vista,
                  onAbrirPalette: () => showCommandPalette(context),
                  onAbrirSettings: _abrirSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
