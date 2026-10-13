import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../providers.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../services/i18n.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'empty_state.dart';
import 'pulse_dot.dart';
import 'skeleton.dart';
import 'brand_logo.dart';

/// Panel lateral de navegación (Sidebar):
///  - Colapsable (mini-rail de 64px o panel completo de 280px).
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final colapsado = widget.colapsado;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: colapsado ? 64 : 280,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(colapsado: colapsado, onToggle: widget.onToggleColapsado),
          const SizedBox(height: 4),

          // Botón principal "Nuevo chat" (terracota).
          Padding(
            padding: EdgeInsets.symmetric(horizontal: colapsado ? 8 : 12),
            child: _NuevoChatButton(
              colapsado: colapsado,
              onTap: () {
                chat.nueva();
                widget.onCambiarVista(VistaPrincipal.chat);
              },
            ),
          ),

          const SizedBox(height: 8),

          // Navegación principal.
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            colapsado: colapsado,
            activo: widget.vista == VistaPrincipal.chat,
            onTap: () => widget.onCambiarVista(VistaPrincipal.chat),
          ),
          _NavItem(
            icon: Icons.code,
            label: 'Explicar código',
            colapsado: colapsado,
            activo: widget.vista == VistaPrincipal.explicar,
            onTap: () => widget.onCambiarVista(VistaPrincipal.explicar),
          ),
          _NavItem(
            icon: Icons.edit_note,
            label: 'Editor de Código',
            colapsado: colapsado,
            activo: widget.vista == VistaPrincipal.code,
            onTap: () => widget.onCambiarVista(VistaPrincipal.code),
          ),
          _NavItem(
            icon: Icons.folder_copy_outlined,
            label: 'Explorador',
            colapsado: colapsado,
            activo: widget.vista == VistaPrincipal.proyecto,
            onTap: () => widget.onCambiarVista(VistaPrincipal.proyecto),
          ),
          _NavItem(
            icon: Icons.terminal,
            label: 'Terminal',
            colapsado: colapsado,
            activo: widget.vista == VistaPrincipal.terminal,
            onTap: () => widget.onCambiarVista(VistaPrincipal.terminal),
          ),
          if (auth.usuario?.esAdmin == true)
            _NavItem(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Administración',
              colapsado: colapsado,
              activo: false,
              onTap: () => showSettings(context, abrirAdministracion: true),
            ),

          if (!colapsado) ...[
            const SizedBox(height: 14),
            _SearchField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 12),

          // Recientes con agrupación por fecha.
          Expanded(
            child: _Recientes(
              conversaciones: chat.conversacionesOrdenadas,
              activaId: chat.activaId,
              colapsado: colapsado,
              query: _query,
              // Si NO se cargó nunca y está cargando: skeletons.
              // Si ya se cargó y no hay conversaciones: empty state.
              cargando:
                  chat.cargandoConversaciones &&
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

          Divider(height: 1, color: p.borderSoft),
          _UsuarioFooter(
            nombre: auth.usuario?.nombre ?? '',
            rol: auth.usuario?.rol ?? '',
            colapsado: colapsado,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

class _Header extends StatelessWidget {
  final bool colapsado;
  final VoidCallback onToggle;
  const _Header({required this.colapsado, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (colapsado) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Center(
          child: Tooltip(
            message: 'Expandir',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const BrandLogo(size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
      child: Row(
        children: [
          Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              color: p.primary,
              borderRadius: BorderRadius.circular(9),
              boxShadow: p.subtleShadow,
            ),
            alignment: Alignment.center,
            child: const BrandLogo(size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Explicador IA',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                color: p.text,
                letterSpacing: -0.1,
              ),
            ),
          ),
          Tooltip(
            message: 'Colapsar sidebar',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.menu_open, size: 18, color: p.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Botón nuevo chat ───────────────────────────

class _NuevoChatButton extends StatefulWidget {
  final bool colapsado;
  final VoidCallback onTap;
  const _NuevoChatButton({required this.colapsado, required this.onTap});

  @override
  State<_NuevoChatButton> createState() => _NuevoChatButtonState();
}

class _NuevoChatButtonState extends State<_NuevoChatButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final bg = _hover ? p.primaryHover : p.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.colapsado ? I18n.t('sidebar.nuevo_chat') : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 38,
            padding: EdgeInsets.symmetric(
              horizontal: widget.colapsado ? 0 : 12,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              boxShadow: p.subtleShadow,
            ),
            child: Row(
              mainAxisAlignment: widget.colapsado
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 17),
                if (!widget.colapsado) ...[
                  const SizedBox(width: 8),
                  Text(
                    I18n.t('sidebar.nuevo_chat'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
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

// ─────────────────────────── Search ───────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.borderSoft),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 15, color: p.subtle),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(fontSize: 13, color: p.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar chats…',
                  hintStyle: TextStyle(color: p.subtle, fontSize: 13),
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
                child: Icon(Icons.close, size: 14, color: p.subtle),
              ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: EmptyState(
          icono: Icons.forum_outlined,
          titulo: 'Tu primer chat',
          mensaje: 'Empieza preguntando lo que quieras a tu asistente.',
          accion: EmptyStateAction(
            label: 'Crear chat',
            icono: Icons.add,
            onTap: onNuevoChat,
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
    final p = AppPalette.of(context);
    final bg = widget.activa
        ? p.surface2
        : (_dragOver
              ? p.primary.withValues(alpha: 0.08)
              : (_hover
                    ? p.surface2.withValues(alpha: 0.55)
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
                    color: widget.activa ? p.text : p.muted,
                    fontWeight: widget.activa
                        ? FontWeight.w500
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

// ─────────────────────────── Nav item ───────────────────────────

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool activo;
  final bool colapsado;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.activo = false,
    this.colapsado = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = widget.activo ? p.text : p.muted;
    final bg = widget.activo
        ? p.surface2
        : (_hover ? p.surface2.withValues(alpha: 0.55) : Colors.transparent);

    // Indicador lateral terracota — solo si activo y no colapsado.
    final indicador = AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      width: widget.activo && !widget.colapsado ? 3 : 0,
      height: widget.activo ? 16 : 0,
      margin: EdgeInsets.only(
        right: widget.activo && !widget.colapsado ? 8 : 0,
      ),
      decoration: BoxDecoration(
        color: p.primary,
        borderRadius: BorderRadius.circular(99),
      ),
    );

    final contenido = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      padding: EdgeInsets.symmetric(
        horizontal: widget.colapsado ? 0 : 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: widget.colapsado
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          AnimatedSlide(
            duration: AppMotion.fast,
            offset: _hover && !widget.activo
                ? const Offset(0.02, 0)
                : Offset.zero,
            child: Icon(
              widget.icon,
              size: 17,
              color: widget.activo ? p.primary : color,
            ),
          ),
          if (!widget.colapsado) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.activo ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.colapsado ? 8 : 4,
        vertical: 1,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Tooltip(
          message: widget.colapsado ? widget.label : '',
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: widget.colapsado
                ? contenido
                : Row(
                    children: [
                      indicador,
                      Expanded(child: contenido),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Footer de usuario ───────────────────────────

class _UsuarioFooter extends StatelessWidget {
  final String nombre;
  final String rol;
  final bool colapsado;
  const _UsuarioFooter({
    required this.nombre,
    required this.rol,
    required this.colapsado,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    if (colapsado) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: p.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      inicial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: PulseDot(size: 6, tooltip: 'Conectado'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'Tema',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                themeProvider.mode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                size: 18,
                color: p.muted,
              ),
              onPressed: () => themeProvider.setMode(
                themeProvider.mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              ),
            ),
            IconButton(
              tooltip: 'Configuración',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.settings_outlined, size: 18, color: p.muted),
              onPressed: () => showSettings(context),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Row(
        children: [
          // Avatar con micro-indicador de conexión (pulse verde
          // pegado abajo-derecha). Aporta sensación de "vivo".
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: p.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: p.elevation(1),
                ),
                child: Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: p.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const PulseDot(
                    size: 7,
                    tooltip: 'Conectado al backend',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
                Text(
                  _rolLabel(rol),
                  style: TextStyle(fontSize: 11, color: p.subtle),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cambiar tema',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              themeProvider.mode == ThemeMode.dark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              size: 17,
              color: p.muted,
            ),
            onPressed: () => themeProvider.setMode(
              themeProvider.mode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            ),
          ),
          IconButton(
            tooltip: 'Configuración',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(Icons.settings_outlined, size: 17, color: p.muted),
            onPressed: () => showSettings(context),
          ),
        ],
      ),
    );
  }

  String _rolLabel(String rol) => switch (rol) {
    'administrador' => 'Administrador',
    'investigador' => 'Investigador',
    'estudiante' => 'Estudiante',
    _ => rol,
  };
}
