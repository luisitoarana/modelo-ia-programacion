import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../screens/settings_screen.dart';
import '../services/i18n.dart';
import '../theme.dart';

/// Command Palette estilo VS Code / Spotlight para la app desktop.
///
/// Se abre con showCommandPalette(context). Devuelve cuando el usuario
/// selecciona un comando o cierra el diálogo.
///
/// Atajos del palette:
///   - ↑↓     navegar resultados
///   - Enter  ejecutar el seleccionado
///   - Esc    cerrar
Future<void> showCommandPalette(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) => const _CommandPaletteContent(),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

class _Comando {
  final String id;
  final String titulo;
  final String? subtitulo;
  final String seccion;
  final IconData icono;
  final VoidCallback onEjecutar;
  const _Comando({
    required this.id,
    required this.titulo,
    this.subtitulo,
    required this.seccion,
    required this.icono,
    required this.onEjecutar,
  });
}

class _CommandPaletteContent extends StatefulWidget {
  const _CommandPaletteContent();

  @override
  State<_CommandPaletteContent> createState() => _CommandPaletteContentState();
}

class _CommandPaletteContentState extends State<_CommandPaletteContent> {
  final _queryCtrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  int _seleccionado = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Comando> _construirComandos() {
    final chat = context.read<ChatProvider>();
    final theme = context.read<ThemeProvider>();
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    void cerrarYHacer(VoidCallback fn) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    }

    final acciones = <_Comando>[
      _Comando(
        id: 'nuevo',
        titulo: I18n.t('cmd.nuevo_chat'),
        seccion: I18n.t('palette.s_acciones'),
        icono: Icons.add,
        onEjecutar: () => cerrarYHacer(() => chat.nueva()),
      ),
      _Comando(
        id: 'tema',
        titulo: esOscuro ? I18n.t('cmd.tema_claro') : I18n.t('cmd.tema_oscuro'),
        seccion: I18n.t('palette.s_acciones'),
        icono: esOscuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        onEjecutar: () => cerrarYHacer(
            () => theme.setMode(esOscuro ? ThemeMode.light : ThemeMode.dark)),
      ),
    ];

    final navegacion = <_Comando>[
      _Comando(
        id: 'chat',
        titulo: I18n.t('cmd.ir_chat'),
        seccion: I18n.t('palette.s_navegacion'),
        icono: Icons.chat_bubble_outline,
        onEjecutar: () => cerrarYHacer(() {
          // Disparamos un evento custom que home_screen captura.
          _eventoCambioVista.value = 0;
        }),
      ),
      _Comando(
        id: 'explicar',
        titulo: I18n.t('cmd.ir_explicar'),
        seccion: I18n.t('palette.s_navegacion'),
        icono: Icons.code,
        onEjecutar: () => cerrarYHacer(() => _eventoCambioVista.value = 1),
      ),
      _Comando(
        id: 'explorador',
        titulo: I18n.t('cmd.ir_explorador'),
        seccion: I18n.t('palette.s_navegacion'),
        icono: Icons.folder_open,
        onEjecutar: () => cerrarYHacer(() => _eventoCambioVista.value = 2),
      ),
      _Comando(
        id: 'terminal',
        titulo: I18n.t('cmd.ir_terminal'),
        seccion: I18n.t('palette.s_navegacion'),
        icono: Icons.terminal,
        onEjecutar: () => cerrarYHacer(() => _eventoCambioVista.value = 3),
      ),
    ];

    final config = <_Comando>[
      _Comando(
        id: 'settings',
        titulo: I18n.t('cmd.configuracion'),
        seccion: I18n.t('palette.s_configuracion'),
        icono: Icons.settings_outlined,
        onEjecutar: () => cerrarYHacer(() => showSettings(context)),
      ),
      _Comando(
        id: 'paleta',
        titulo: I18n.t('cmd.apariencia'),
        seccion: I18n.t('palette.s_configuracion'),
        icono: Icons.palette_outlined,
        onEjecutar: () => cerrarYHacer(() => showSettings(context)),
      ),
    ];

    final convs = chat.conversaciones.take(10).map((c) => _Comando(
          id: 'conv-${c.id}',
          titulo: c.titulo.isEmpty ? 'Conversación' : c.titulo,
          subtitulo: I18n.t('cmd.abrir_conv'),
          seccion: I18n.t('palette.s_conversaciones'),
          icono: Icons.chat_outlined,
          onEjecutar: () => cerrarYHacer(() => chat.seleccionar(c.id)),
        ));

    return [...acciones, ...navegacion, ...config, ...convs];
  }

  List<_Comando> _filtrar(List<_Comando> todos) {
    if (_query.trim().isEmpty) return todos;
    final q = _query.toLowerCase();
    return todos
        .where((c) =>
            c.titulo.toLowerCase().contains(q) ||
            c.seccion.toLowerCase().contains(q))
        .toList();
  }

  Map<String, List<_Comando>> _agruparPorSeccion(List<_Comando> cs) {
    final m = <String, List<_Comando>>{};
    for (final c in cs) {
      m.putIfAbsent(c.seccion, () => []).add(c);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final todos = _construirComandos();
    final filtrados = _filtrar(todos);
    final grupos = _agruparPorSeccion(filtrados);

    return Align(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.borderSoft),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Input
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.borderSoft)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 16, color: p.subtle),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardListener(
                          focusNode: FocusNode(skipTraversal: true),
                          onKeyEvent: (evt) {
                            if (evt is! KeyDownEvent) return;
                            if (evt.logicalKey == LogicalKeyboardKey.arrowDown) {
                              setState(() => _seleccionado =
                                  (_seleccionado + 1).clamp(0, filtrados.length - 1));
                            } else if (evt.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() => _seleccionado =
                                  (_seleccionado - 1).clamp(0, filtrados.length - 1));
                            } else if (evt.logicalKey == LogicalKeyboardKey.enter) {
                              if (_seleccionado < filtrados.length) {
                                filtrados[_seleccionado].onEjecutar();
                              }
                            } else if (evt.logicalKey == LogicalKeyboardKey.escape) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: TextField(
                            controller: _queryCtrl,
                            focusNode: _focus,
                            onChanged: (v) => setState(() {
                              _query = v;
                              _seleccionado = 0;
                            }),
                            style: TextStyle(color: p.text, fontSize: 14.5),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: I18n.t('palette.placeholder'),
                              hintStyle:
                                  TextStyle(color: p.subtle, fontSize: 14.5),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.surface2,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: p.borderSoft),
                        ),
                        child: Text(
                          'esc',
                          style: TextStyle(
                              fontSize: 10,
                              color: p.subtle,
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (filtrados.isEmpty)
                          _SinResultados(query: _query)
                        else
                          ..._construirLista(grupos, filtrados, p),
                      ],
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.borderSoft)),
                    color: p.surface.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      _KbdMini(text: '↑↓'),
                      const SizedBox(width: 4),
                      Text(I18n.t('palette.navegar'),
                          style: TextStyle(fontSize: 10.5, color: p.subtle)),
                      const SizedBox(width: 14),
                      _KbdMini(text: '↵'),
                      const SizedBox(width: 4),
                      Text(I18n.t('palette.seleccionar'),
                          style: TextStyle(fontSize: 10.5, color: p.subtle)),
                      const Spacer(),
                      Text('${filtrados.length} ${I18n.t('palette.resultados')}',
                          style: TextStyle(fontSize: 10.5, color: p.subtle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _construirLista(
      Map<String, List<_Comando>> grupos, List<_Comando> planos, AppPalette p) {
    final items = <Widget>[];
    grupos.forEach((seccion, comandos) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            seccion.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: p.subtle,
            ),
          ),
        ),
      );
      for (final c in comandos) {
        final idx = planos.indexOf(c);
        items.add(
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _seleccionado = idx),
            child: InkWell(
              onTap: c.onEjecutar,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                color: _seleccionado == idx
                    ? p.surface2
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(c.icono,
                        size: 14,
                        color: _seleccionado == idx ? p.primary : p.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: p.text)),
                          if (c.subtitulo != null)
                            Text(c.subtitulo!,
                                style: TextStyle(
                                    fontSize: 11, color: p.subtle)),
                        ],
                      ),
                    ),
                    if (_seleccionado == idx)
                      Icon(Icons.arrow_forward,
                          size: 11, color: p.subtle),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    });
    return items;
  }
}

class _SinResultados extends StatelessWidget {
  final String query;
  const _SinResultados({required this.query});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 28, color: p.subtle),
          const SizedBox(height: 8),
          Text(
            '${I18n.t('palette.sin_resultados')} «$query»',
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _KbdMini extends StatelessWidget {
  final String text;
  const _KbdMini({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: p.borderSoft),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: p.muted,
          fontFamily: AppFonts.monoFallback.first,
          fontFamilyFallback: AppFonts.monoFallback,
        ),
      ),
    );
  }
}

/// Notifier compartido para comunicar al HomeScreen un cambio de vista
/// solicitado desde el palette (Chat=0, Explicar=1, Explorador=2, Terminal=3).
final ValueNotifier<int?> _eventoCambioVista = ValueNotifier<int?>(null);
ValueNotifier<int?> get eventoCambioVista => _eventoCambioVista;
