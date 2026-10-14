import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../providers.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../services/dialogos_nativos.dart';
import '../services/i18n.dart';
import '../theme.dart';
import 'brand_logo.dart';
import 'code/divisores.dart';
import 'confirm_dialog.dart';
import 'pulse_dot.dart';
import 'skeleton.dart';

/// Panel lateral de navegación (Sidebar):
///  - Colapsable (mini-rail de 48px o panel completo redimensionable).
///  - Botón "Nuevo chat" prominente.
///  - Búsqueda integrada para filtrar conversaciones.
///  - Agrupación automática de conversaciones por fecha
///    (Hoy / Ayer / Últimos 7 días / Anteriores).
///  - Footer compacto con menú de usuario.
class Sidebar extends StatefulWidget {
  final VistaPrincipal vista;
  final ValueChanged<VistaPrincipal> onCambiarVista;
  final bool colapsado;
  final VoidCallback onToggleColapsado;

  const Sidebar({
    super.key,
    required this.vista,
    required this.onCambiarVista,
    this.colapsado = false,
    required this.onToggleColapsado,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  double _anchoProyectos = 240.0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final colapsado = widget.colapsado;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Activity Rail Izquierdo (48px fijo) ──
        _ActivityRail(
          vista: widget.vista,
          onCambiarVista: widget.onCambiarVista,
          colapsado: colapsado,
          onToggleColapsado: widget.onToggleColapsado,
        ),

        // ── 2. Panel de Proyectos y Chats (redimensionable con DivisorVertical) ──
        _ProyectosPanel(
          ancho: _anchoProyectos,
          colapsado: colapsado,
          onToggleColapsado: widget.onToggleColapsado,
          onNuevoChat: () {
            chat.nueva();
            widget.onCambiarVista(VistaPrincipal.chat);
          },
          searchCtrl: _searchCtrl,
          query: _query,
          onQueryChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          onAbrirProyecto: () => widget.onCambiarVista(VistaPrincipal.code),
          recientesWidget: _Recientes(
            conversaciones: chat.conversacionesOrdenadas,
            activaId: chat.activaId,
            colapsado: false,
            query: _query,
            cargando: chat.cargandoConversaciones &&
                !chat.conversacionesCargadasAlgunaVez,
            onNuevoChat: () {
              chat.nueva();
              widget.onCambiarVista(VistaPrincipal.chat);
            },
            onSeleccionar: (id) {
              chat.seleccionar(id);
              widget.onCambiarVista(VistaPrincipal.chat);
            },
            onEliminar: (id) async {
              final conv = chat.conversaciones.firstWhere(
                (c) => c.id == id,
                orElse: () => ConversacionResumen(
                  id: id,
                  titulo: 'Conversación',
                  fechaActualizacion: '',
                ),
              );
              final confirmado = await mostrarConfirmacion(
                context,
                titulo: '¿Eliminar esta conversación?',
                descripcion:
                    '"${conv.titulo}" se borrará permanentemente. Esta acción no se puede deshacer.',
                textoConfirmar: 'Eliminar',
                textoCancelar: 'Cancelar',
                tono: ConfirmTono.danger,
                icono: ConfirmIcono.eliminar,
              );
              if (confirmado) chat.eliminar(id);
            },
          ),
        ),

        // ── Divisor arrastrable (aparece solo si el panel está desplegado) ──
        if (!colapsado)
          DivisorVertical(
            onDrag: (dx) {
              setState(() {
                _anchoProyectos = (_anchoProyectos + dx).clamp(180.0, 450.0);
              });
            },
          ),
      ],
    );
  }
}

// ─────────────────────────── Activity Rail (48px) ───────────────────────────

class _ActivityRail extends StatelessWidget {
  final VistaPrincipal vista;
  final ValueChanged<VistaPrincipal> onCambiarVista;
  final bool colapsado;
  final VoidCallback onToggleColapsado;

  const _ActivityRail({
    required this.vista,
    required this.onCambiarVista,
    required this.colapsado,
    required this.onToggleColapsado,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);
    final auth = context.watch<AuthProvider>();
    final nombre = auth.usuario?.nombre ?? '';
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'LU';

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: esOscuro ? const Color(0xFF07080C) : const Color(0xFFEDF2F7),
        border: Border(right: BorderSide(color: esOscuro ? const Color(0xFF1C202C) : p.borderSoft)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailIcon(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Chat Asistente (Ctrl+1)',
            activo: vista == VistaPrincipal.chat,
            onTap: () => onCambiarVista(VistaPrincipal.chat),
          ),
          _RailIcon(
            icon: Icons.code_rounded,
            tooltip: 'Explicar Código (Ctrl+2)',
            activo: vista == VistaPrincipal.explicar,
            onTap: () => onCambiarVista(VistaPrincipal.explicar),
          ),
          _RailIcon(
            icon: Icons.edit_note_rounded,
            tooltip: 'Editor de Código (Ctrl+3)',
            activo: vista == VistaPrincipal.code,
            onTap: () => onCambiarVista(VistaPrincipal.code),
          ),
          _RailIcon(
            icon: Icons.folder_open_rounded,
            tooltip: 'Explorador (Ctrl+4)',
            activo: vista == VistaPrincipal.proyecto,
            onTap: () => onCambiarVista(VistaPrincipal.proyecto),
          ),
          _RailIcon(
            icon: Icons.terminal_rounded,
            tooltip: 'Terminal Interactiva (Ctrl+5)',
            activo: vista == VistaPrincipal.terminal,
            onTap: () => onCambiarVista(VistaPrincipal.terminal),
          ),
          if (auth.usuario?.esAdmin == true)
            _RailIcon(
              icon: Icons.admin_panel_settings_outlined,
              tooltip: 'Administración',
              activo: false,
              onTap: () => showSettings(context, abrirAdministracion: true),
            ),
          const Spacer(),
          _RailIcon(
            icon: colapsado ? Icons.view_sidebar_outlined : Icons.menu_open_rounded,
            tooltip: colapsado ? 'Abrir barra lateral (Ctrl+B)' : 'Ocultar barra lateral (Ctrl+B)',
            activo: !colapsado,
            onTap: onToggleColapsado,
          ),
          _RailIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Configuración (Ctrl+,)',
            activo: false,
            onTap: () => showSettings(context),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: nombre.isNotEmpty ? '$nombre (Estudiante)' : 'Usuario (LU)',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: p.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      inicial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: PulseDot(size: 6.5, tooltip: 'Conectado'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _RailIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool activo;
  final VoidCallback onTap;
  const _RailIcon({
    required this.icon,
    required this.tooltip,
    this.activo = false,
    required this.onTap,
  });

  @override
  State<_RailIcon> createState() => _RailIconState();
}

class _RailIconState extends State<_RailIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);
    final activo = widget.activo;
    final color = activo
        ? p.primary
        : (_hover ? p.text : (esOscuro ? const Color(0xFF94A3B8) : p.muted));
    final bg = activo
        ? p.primary.withValues(alpha: 0.16)
        : (_hover ? (esOscuro ? const Color(0xFF161922) : p.surface3) : Colors.transparent);

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: activo ? Border.all(color: p.primary.withValues(alpha: 0.4)) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(widget.icon, size: 19, color: color),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.0,
                    child: Center(
                      child: Text(
                        widget.tooltip,
                        style: const TextStyle(fontSize: 1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Panel Proyectos / Recientes Codex (240px) ───────────────────────────

class _ProyectosPanel extends StatelessWidget {
  final double ancho;
  final bool colapsado;
  final VoidCallback onToggleColapsado;
  final VoidCallback onNuevoChat;
  final TextEditingController searchCtrl;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAbrirProyecto;
  final Widget recientesWidget;

  const _ProyectosPanel({
    this.ancho = 240,
    required this.colapsado,
    required this.onToggleColapsado,
    required this.onNuevoChat,
    required this.searchCtrl,
    required this.query,
    required this.onQueryChanged,
    required this.onAbrirProyecto,
    required this.recientesWidget,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);
    final settings = context.watch<SettingsProvider>();
    final carpetaActiva = settings.carpetaProyecto;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: colapsado ? 0 : ancho,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: ancho,
          maxWidth: ancho,
          child: Container(
            width: ancho,
            decoration: BoxDecoration(
              color: esOscuro ? const Color(0xFF0A0C10) : p.surface,
              border: Border(right: BorderSide(color: esOscuro ? const Color(0xFF1C202C) : p.borderSoft)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header estilo Codex (hacer clic en Explicador IA colapsa/expande el panel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Ocultar panel (Ctrl+B)',
                          child: InkWell(
                            onTap: onToggleColapsado,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Explicador IA',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: p.text,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Botón minimalista Nuevo Chat
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: _BotonNuevoChatCodex(onTap: onNuevoChat),
                ),
                const SizedBox(height: 10),
                // Sección PROYECTOS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Text(
                    'PROYECTOS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: p.subtle,
                    ),
                  ),
                ),
                // Tarjeta de proyecto real o botón para abrir proyecto
                if (carpetaActiva != null && carpetaActiva.isNotEmpty)
                  _ProyectoItemCodex(
                    carpeta: carpetaActiva,
                    onTap: onAbrirProyecto,
                    onCerrar: () => settings.setCarpetaProyecto(null),
                    onCambiar: () async {
                      final nueva = await DialogosNativos.seleccionarCarpeta(
                        titulo: 'Seleccionar carpeta de proyecto',
                      );
                      if (nueva != null) {
                        settings.setCarpetaProyecto(nueva);
                        onAbrirProyecto();
                      }
                    },
                  )
                else
                  _BotonAbrirProyectoCodex(
                    onTap: () async {
                      final ruta = await DialogosNativos.seleccionarCarpeta(
                        titulo: 'Abrir carpeta como proyecto',
                      );
                      if (ruta != null) {
                        settings.setCarpetaProyecto(ruta);
                        onAbrirProyecto();
                      }
                    },
                  ),
                const SizedBox(height: 10),
                // Sección RECIENTES
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Text(
                    'RECIENTES',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: p.subtle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: _SearchFieldCodex(
                    controller: searchCtrl,
                    onChanged: onQueryChanged,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(child: recientesWidget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonAbrirProyectoCodex extends StatefulWidget {
  final VoidCallback onTap;
  const _BotonAbrirProyectoCodex({required this.onTap});

  @override
  State<_BotonAbrirProyectoCodex> createState() => _BotonAbrirProyectoCodexState();
}

class _BotonAbrirProyectoCodexState extends State<_BotonAbrirProyectoCodex> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? (esOscuro ? const Color(0xFF1E2230) : p.surface2)
                : (esOscuro ? const Color(0xFF161922) : p.surface2.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover ? p.primary : (esOscuro ? const Color(0xFF282E40) : p.border),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 16, color: p.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Abrir carpeta...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Ningún proyecto abierto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProyectoItemCodex extends StatefulWidget {
  final String carpeta;
  final VoidCallback onTap;
  final VoidCallback onCambiar;
  final VoidCallback onCerrar;

  const _ProyectoItemCodex({
    required this.carpeta,
    required this.onTap,
    required this.onCambiar,
    required this.onCerrar,
  });

  @override
  State<_ProyectoItemCodex> createState() => _ProyectoItemCodexState();
}

class _ProyectoItemCodexState extends State<_ProyectoItemCodex> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);
    final nombreCarpeta = widget.carpeta.split(RegExp(r'[/\\]')).last;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: _hover
              ? (esOscuro ? const Color(0xFF1E2230) : p.surface2)
              : (esOscuro ? const Color(0xFF161922) : p.surface2.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hover ? p.primary.withValues(alpha: 0.6) : (esOscuro ? const Color(0xFF282E40) : p.border),
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.folder_rounded, size: 16, color: p.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombreCarpeta.isEmpty ? widget.carpeta : nombreCarpeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.carpeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hover) ...[
                  Tooltip(
                    message: 'Cambiar carpeta',
                    child: InkWell(
                      onTap: widget.onCambiar,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.drive_file_move_outlined, size: 14, color: p.subtle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Cerrar proyecto',
                    child: InkWell(
                      onTap: widget.onCerrar,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.close_rounded, size: 14, color: p.subtle),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonNuevoChatCodex extends StatefulWidget {
  final VoidCallback onTap;
  const _BotonNuevoChatCodex({required this.onTap});

  @override
  State<_BotonNuevoChatCodex> createState() => _BotonNuevoChatCodexState();
}

class _BotonNuevoChatCodexState extends State<_BotonNuevoChatCodex> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover
                ? (esOscuro ? const Color(0xFF1E2230) : p.surface2)
                : (esOscuro ? const Color(0xFF161922) : p.surface3.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover ? p.primary : (esOscuro ? const Color(0xFF282E40) : p.border),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 16, color: p.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nuevo chat',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Ctrl+N',
                style: TextStyle(fontSize: 10.5, color: p.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchFieldCodex extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchFieldCodex({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: esOscuro ? const Color(0xFF161922) : p.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: esOscuro ? const Color(0xFF282E40) : p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 14, color: p.subtle),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 12, color: p.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar chats…',
                hintStyle: TextStyle(color: p.subtle, fontSize: 12),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            InkWell(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(Icons.close, size: 13, color: p.subtle),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Recientes ───────────────────────────

class _Recientes extends StatelessWidget {
  final List<ConversacionResumen> conversaciones;
  final String? activaId;
  final bool colapsado;
  final String query;
  final bool cargando;
  final VoidCallback onNuevoChat;
  final ValueChanged<String> onSeleccionar;
  final ValueChanged<String> onEliminar;

  const _Recientes({
    required this.conversaciones,
    required this.activaId,
    required this.colapsado,
    required this.query,
    required this.cargando,
    required this.onNuevoChat,
    required this.onSeleccionar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    if (colapsado) {
      // En modo colapsado mostramos solo un placeholder discreto.
      return const SizedBox.shrink();
    }

    // Mientras carga por primera vez: skeletons con shimmer (mejor UX
    // que un spinner porque insinúa la forma del contenido).
    if (cargando) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Skeleton.text(height: 9, width: 50),
            ),
            for (int i = 0; i < 4; i++) const SkeletonConversacion(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Skeleton.text(height: 9, width: 70),
            ),
            for (int i = 0; i < 2; i++) const SkeletonConversacion(),
          ],
        ),
      );
    }

    final filtradas = query.isEmpty
        ? conversaciones
        : conversaciones
              .where((c) => c.titulo.toLowerCase().contains(query))
              .toList();

    if (filtradas.isEmpty) {
      // Empty state diferenciado: si buscaba algo concreto, mostramos
      // el mensaje de "sin resultados"; si no había nada en general,
      // mostramos EmptyState con acción para crear el primero.
      if (query.isNotEmpty) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 26, color: p.subtle),
                const SizedBox(height: 8),
                Text(
                  'Sin resultados para «$query».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 24, color: p.subtle),
              const SizedBox(height: 10),
              Text(
                'Sin chats recientes',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Inicia una conversación con el botón superior.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: p.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final ayer = hoy.subtract(const Duration(days: 1));
    final hace7 = hoy.subtract(const Duration(days: 7));

    final kHoy = I18n.t('sidebar.hoy');
    final kAyer = I18n.t('sidebar.ayer');
    final kSemana = I18n.t('sidebar.ultima_semana');
    final kAntes = I18n.t('sidebar.mas_antiguas');
    final grupos = <String, List<ConversacionResumen>>{
      kHoy: [],
      kAyer: [],
      kSemana: [],
      kAntes: [],
    };

    for (final c in filtradas) {
      final fecha = DateTime.tryParse(c.fechaActualizacion);
      if (fecha == null) {
        grupos[kAntes]!.add(c);
        continue;
      }
      final dia = DateTime(fecha.year, fecha.month, fecha.day);
      if (!dia.isBefore(hoy)) {
        grupos[kHoy]!.add(c);
      } else if (!dia.isBefore(ayer)) {
        grupos[kAyer]!.add(c);
      } else if (!dia.isBefore(hace7)) {
        grupos[kSemana]!.add(c);
      } else {
        grupos[kAntes]!.add(c);
      }
    }

    final children = <Widget>[];
    grupos.forEach((etiqueta, lista) {
      if (lista.isEmpty) return;
      children.add(_GrupoHeader(etiqueta: etiqueta));
      for (final c in lista) {
        children.add(
          _ConversacionTile(
            id: c.id,
            titulo: c.titulo,
            activa: c.id == activaId,
            onTap: () => onSeleccionar(c.id),
            onEliminar: () => onEliminar(c.id),
          ),
        );
      }
      children.add(const SizedBox(height: 6));
    });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      children: children,
    );
  }
}

class _GrupoHeader extends StatelessWidget {
  final String etiqueta;
  const _GrupoHeader({required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(
        etiqueta.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: p.subtle,
        ),
      ),
    );
  }
}

// ─────────────────────────── Tile de conversación ───────────────────────────

class _ConversacionTile extends StatefulWidget {
  final String id;
  final String titulo;
  final bool activa;
  final VoidCallback onTap;
  final VoidCallback onEliminar;

  const _ConversacionTile({
    required this.id,
    required this.titulo,
    required this.activa,
    required this.onTap,
    required this.onEliminar,
  });

  @override
  State<_ConversacionTile> createState() => _ConversacionTileState();
}

class _ConversacionTileState extends State<_ConversacionTile> {
  bool _hover = false;
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette.of(context);
    final bg = widget.activa
        ? (esOscuro ? const Color(0xFF1E2230) : p.surface2)
        : (_dragOver
              ? p.primary.withValues(alpha: 0.12)
              : (_hover
                    ? (esOscuro ? const Color(0xFF161922) : p.surface3.withValues(alpha: 0.6))
                    : Colors.transparent));

    final contenido = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: _dragOver
                ? Border.all(color: p.primary.withValues(alpha: 0.45), width: 1)
                : null,
          ),
          child: Row(
            children: [
              if (_hover || _dragOver)
                Icon(Icons.drag_indicator, size: 11, color: p.subtle),
              if (_hover || _dragOver) const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.titulo.isEmpty ? 'Conversación' : widget.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.activa ? p.text : (esOscuro ? const Color(0xFFCBD5E1) : p.text.withValues(alpha: 0.85)),
                    fontWeight: widget.activa
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (_hover || widget.activa)
                Tooltip(
                  message: 'Eliminar',
                  child: InkWell(
                    onTap: widget.onEliminar,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: p.subtle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (d.data != widget.id) {
          setState(() => _dragOver = true);
          return true;
        }
        return false;
      },
      onLeave: (_) => setState(() => _dragOver = false),
      onAcceptWithDetails: (d) {
        setState(() => _dragOver = false);
        context.read<ChatProvider>().reordenar(d.data, widget.id);
      },
      builder: (_, _, _) => LongPressDraggable<String>(
        data: widget.id,
        delay: const Duration(milliseconds: 200),
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: p.surface,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator, size: 13, color: p.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.titulo.isEmpty ? 'Conversación' : widget.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: p.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: contenido),
        child: contenido,
      ),
    );
  }
}

