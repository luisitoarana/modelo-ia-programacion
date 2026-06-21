import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../services/i18n.dart';
import '../services/tts_service.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/onboarding.dart';

/// Settings rehecho estilo Claude:
///   - Sidebar izquierda con secciones agrupadas
///   - Área de contenido a la derecha
///   - X arriba a la derecha para cerrar
///   - Búsqueda integrada
enum _SeccionId {
  cuenta, apariencia, idioma, capacidades, voz,
  privacidad, notificaciones, atajos, exportar, ayuda,
  avanzado
}

class _Seccion {
  final _SeccionId id;
  final String label;
  final IconData icono;
  final String grupo;
  const _Seccion({
    required this.id,
    required this.label,
    required this.icono,
    required this.grupo,
  });
}

/// Abre la configuración como un MODAL centrado con bordes redondeados,
/// sombra elevada y backdrop con blur — igual al estilo de la web.
///
/// El usuario lo cierra con el botón X (esquina superior derecha) o con Esc.
Future<void> showSettings(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) => const SettingsScreen(),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SeccionId _activa = _SeccionId.cuenta;
  String _busqueda = '';
  Map<String, dynamic>? _estadoModelo;

  static const List<_Seccion> _todas = [
    _Seccion(id: _SeccionId.cuenta, label: 'Cuenta', icono: Icons.person_outline, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.apariencia, label: 'Apariencia', icono: Icons.palette_outlined, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.idioma, label: 'Idioma', icono: Icons.translate, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.capacidades, label: 'Capacidades', icono: Icons.auto_awesome, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.voz, label: 'Voz', icono: Icons.mic_none, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.privacidad, label: 'Privacidad', icono: Icons.lock_outline, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.notificaciones, label: 'Notificaciones', icono: Icons.notifications_outlined, grupo: 'Configuración'),
    _Seccion(id: _SeccionId.atajos, label: 'Atajos de teclado', icono: Icons.keyboard_outlined, grupo: 'Aplicación'),
    _Seccion(id: _SeccionId.exportar, label: 'Exportar', icono: Icons.download_outlined, grupo: 'Aplicación'),
    _Seccion(id: _SeccionId.ayuda, label: 'Ayuda', icono: Icons.help_outline, grupo: 'Aplicación'),
    _Seccion(id: _SeccionId.avanzado, label: 'Avanzado', icono: Icons.settings_ethernet, grupo: 'Avanzado'),
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final api = context.read<AuthProvider>().api;
      final e = await api.estadoModelo();
      if (mounted) setState(() => _estadoModelo = e);
    } catch (_) {}
  }

  List<_Seccion> get _filtradas {
    if (_busqueda.trim().isEmpty) return _todas;
    final q = _busqueda.toLowerCase();
    return _todas.where((s) => s.label.toLowerCase().contains(q)).toList();
  }

  Map<String, List<_Seccion>> get _porGrupo {
    final result = <String, List<_Seccion>>{};
    for (final s in _filtradas) {
      result.putIfAbsent(s.grupo, () => []).add(s);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    // Tamaño del cuadro: 88-94% de la pantalla con máximos sensatos
    // (idéntico a la versión web: 88vh × 1200px max).
    final w = (size.width * 0.94).clamp(720.0, 1200.0);
    final h = (size.height * 0.88).clamp(560.0, 760.0);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.borderSoft),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 50,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    _sidebar(p),
                    Container(width: 1, color: p.borderSoft),
                    Expanded(child: _contenido(p)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────── Sidebar ──────────────────────

  Widget _sidebar(AppPalette p) {
    return Container(
      width: 240,
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
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
                  Icon(Icons.search, size: 14, color: p.subtle),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _busqueda = v),
                      style: TextStyle(fontSize: 13, color: p.text),
                      decoration: InputDecoration(
                        hintText: 'Buscar',
                        hintStyle: TextStyle(fontSize: 13, color: p.subtle),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: _porGrupo.entries.expand((entry) {
                return [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: p.subtle,
                      ),
                    ),
                  ),
                  ...entry.value.map((s) => _navItem(p, s)),
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(AppPalette p, _Seccion s) {
    final activa = _activa == s.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: InkWell(
        onTap: () => setState(() => _activa = s.id),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: activa ? p.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(s.icono, size: 15,
                  color: activa ? p.primary : p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: activa ? p.text : p.muted,
                    fontWeight: activa ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────── Contenido ──────────────────────

  Widget _contenido(AppPalette p) {
    return Stack(
      children: [
        // Botón X arriba a la derecha
        Positioned(
          top: 14,
          right: 14,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: p.muted),
            tooltip: 'Cerrar',
          ),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _seccionContent(p),
            ),
          ),
        ),
      ],
    );
  }

  Widget _seccionContent(AppPalette p) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final theme = context.watch<ThemeProvider>();
    switch (_activa) {
      case _SeccionId.cuenta:
        return _CuentaSection(key: const ValueKey('cuenta'), usuario: auth.usuario);
      case _SeccionId.apariencia:
        return _AparienciaSection(key: const ValueKey('apariencia'), theme: theme);
      case _SeccionId.idioma:
        return _IdiomaSection(key: const ValueKey('idioma'), settings: settings);
      case _SeccionId.capacidades:
        return _CapacidadesSection(key: const ValueKey('capacidades'), settings: settings);
      case _SeccionId.voz:
        return const _VozSection(key: ValueKey('voz'));
      case _SeccionId.privacidad:
        return const _PrivacidadSection(key: ValueKey('priv'));
      case _SeccionId.notificaciones:
        return const _NotificacionesSection(key: ValueKey('notif'));
      case _SeccionId.atajos:
        return const _AtajosSection(key: ValueKey('atajos'));
      case _SeccionId.exportar:
        return _ExportarSection(key: const ValueKey('exp'));
      case _SeccionId.ayuda:
        return _AyudaSection(key: const ValueKey('ayuda'), usuario: auth.usuario);
      case _SeccionId.avanzado:
        return _AvanzadoSection(key: const ValueKey('av'), settings: settings, estadoModelo: _estadoModelo);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
//                         WIDGETS COMUNES
// ═════════════════════════════════════════════════════════════════════════

class _Titulo extends StatelessWidget {
  final String titulo;
  final String? descripcion;
  const _Titulo({required this.titulo, this.descripcion});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: p.text,
                  fontSize: 24,
                ),
          ),
          if (descripcion != null) ...[
            const SizedBox(height: 4),
            Text(
              descripcion!,
              style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubTitulo extends StatelessWidget {
  final String titulo;
  const _SubTitulo({required this.titulo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final String? descripcion;
  final Widget control;
  const _Fila({required this.label, this.descripcion, required this.control});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.borderSoft)),
        ),
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: p.text,
                          fontWeight: FontWeight.w500)),
                  if (descripcion != null) ...[
                    const SizedBox(height: 3),
                    Text(descripcion!,
                        style: TextStyle(
                            fontSize: 12,
                            color: p.muted,
                            height: 1.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            control,
          ],
        ),
      ),
    );
  }
}

class _SwitchAnimado extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchAnimado({required this.value, required this.onChanged});

  @override
  State<_SwitchAnimado> createState() => _SwitchAnimadoState();
}

class _SwitchAnimadoState extends State<_SwitchAnimado> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final activo = widget.value;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => widget.onChanged(!activo),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 28,
          width: 48,
          decoration: BoxDecoration(
            color: activo ? p.primary : p.surface3,
            borderRadius: BorderRadius.circular(999),
            boxShadow: activo
                ? [
                    BoxShadow(
                      color: p.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: activo ? 23 : 3,
                top: 3,
                child: AnimatedScale(
                  scale: _pressed ? 0.85 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: Container(
                    height: 22,
                    width: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
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
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//                         SECCIONES
// ═════════════════════════════════════════════════════════════════════════

class _CuentaSection extends StatelessWidget {
  final Usuario? usuario;
  const _CuentaSection({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final inicial = usuario?.nombre.isNotEmpty == true
        ? usuario!.nombre[0].toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Cuenta',
          descripcion: 'Información de tu sesión activa.',
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.borderSoft)),
          ),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: p.subtleShadow,
                ),
                child: Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(usuario?.nombre ?? '—',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    Text(usuario?.email ?? '—',
                        style: TextStyle(fontSize: 13, color: p.muted)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: p.borderSoft),
                      ),
                      child: Text(
                        _rolLabel(usuario?.rol),
                        style: TextStyle(
                          fontSize: 11,
                          color: p.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (usuario?.institucion?.isNotEmpty == true)
          _Fila(
            label: 'Institución',
            control: Text(usuario!.institucion!,
                style: TextStyle(fontSize: 14, color: p.text)),
          ),
        const _SubTitulo(titulo: 'Sesión'),
        _Fila(
          label: 'Estado de la sesión',
          descripcion: 'Estás autenticado con un JWT válido.',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 6, width: 6,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text('Activa',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final confirmado = await mostrarConfirmacion(
              context,
              titulo: '¿Cerrar sesión?',
              descripcion:
                  'Vas a salir de tu cuenta. Tendrás que volver a iniciar sesión la próxima vez.',
              textoConfirmar: 'Cerrar sesión',
              tono: ConfirmTono.warning,
              icono: ConfirmIcono.logout,
            );
            if (!confirmado) return;
            if (context.mounted) {
              context.read<ChatProvider>().limpiar();
              context.read<AuthProvider>().logout();
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.logout, size: 15),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  String _rolLabel(String? r) => switch (r) {
        'administrador' => 'Administrador',
        'investigador' => 'Investigador',
        'estudiante' => 'Estudiante',
        null => '—',
        _ => r,
      };
}

// ────────────────────── APARIENCIA ──────────────────────

class _AparienciaSection extends StatelessWidget {
  final ThemeProvider theme;
  const _AparienciaSection({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Apariencia',
          descripcion: 'Personaliza cómo se ve el sistema.',
        ),
        const _SubTitulo(titulo: 'Tema'),
        _Fila(
          label: 'Modo de color',
          descripcion: 'Claro y Oscuro son fijos. Auto sigue el sistema operativo.',
          control: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 14),
                  label: Text('Claro')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 14),
                  label: Text('Oscuro')),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.computer_outlined, size: 14),
                  label: Text('Auto')),
            ],
            selected: {theme.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => theme.setMode(s.first),
          ),
        ),
        const _SubTitulo(titulo: 'Paleta de colores'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Cada paleta cambia toda la app. Se aplica a los modos claro y oscuro.',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.2,
          children: Paletas.todas.values.map((pal) {
            final activa = theme.paletaId == pal.id;
            return _PaletaCard(paleta: pal, activa: activa, onTap: () => theme.setPaleta(pal.id));
          }).toList(),
        ),
      ],
    );
  }
}

class _PaletaCard extends StatefulWidget {
  final PaletaInfo paleta;
  final bool activa;
  final VoidCallback onTap;
  const _PaletaCard({required this.paleta, required this.activa, required this.onTap});

  @override
  State<_PaletaCard> createState() => _PaletaCardState();
}

class _PaletaCardState extends State<_PaletaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.activa
                ? p.primary.withValues(alpha: 0.08)
                : (_hover ? p.surface2 : p.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.activa ? p.primary : p.borderSoft,
              width: widget.activa ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Swatches
              SizedBox(
                width: 60,
                height: 36,
                child: Stack(
                  children: [
                    for (var i = 0; i < widget.paleta.swatches.length; i++)
                      Positioned(
                        left: (i * 18).toDouble(),
                        top: 4,
                        child: Container(
                          height: 28,
                          width: 28,
                          decoration: BoxDecoration(
                            color: widget.paleta.swatches[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: p.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.paleta.nombre,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: p.text,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(widget.paleta.descripcion,
                        style: TextStyle(
                            fontSize: 11.5, color: p.subtle, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (widget.activa) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle, size: 16, color: p.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────── IDIOMA ──────────────────────

class _IdiomaSection extends StatelessWidget {
  final SettingsProvider settings;
  const _IdiomaSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Idioma',
          descripcion:
              'El idioma en que el asistente responde y los locales del dictado por voz.',
        ),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Esta opción cambia el idioma de las RESPUESTAS del asistente, no el idioma de la interfaz. La UI sigue en español por ahora.',
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        _Fila(
          label: 'Idioma del asistente',
          descripcion:
              'El chat responderá siempre en este idioma, sin importar en cuál preguntes.',
          control: SizedBox(
            width: 220,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderSoft),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.idioma,
                  dropdownColor: p.surface,
                  style: TextStyle(color: p.text, fontSize: 13),
                  isExpanded: true,
                  icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                  items: Idiomas.opciones.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) settings.setIdioma(v);
                  },
                ),
              ),
            ),
          ),
        ),
        _Fila(
          label: 'Idioma de la interfaz',
          descripcion:
              'Cambia labels, botones y menús del sistema. Cobertura parcial — el resto sigue en español.',
          control: SizedBox(
            width: 220,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderSoft),
              ),
              child: ValueListenableBuilder<UiLang>(
                valueListenable: I18n.instance.idioma,
                builder: (_, lang, __) => DropdownButtonHideUnderline(
                  child: DropdownButton<UiLang>(
                    value: lang,
                    dropdownColor: p.surface,
                    isExpanded: true,
                    style: TextStyle(color: p.text, fontSize: 13),
                    icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                    items: const [
                      DropdownMenuItem(value: UiLang.es, child: Text('Español')),
                      DropdownMenuItem(value: UiLang.en, child: Text('English')),
                    ],
                    onChanged: (v) {
                      if (v != null) I18n.instance.setIdioma(v);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────── CAPACIDADES ──────────────────────

class _CapacidadesSection extends StatelessWidget {
  final SettingsProvider settings;
  const _CapacidadesSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Capacidades del asistente',
          descripcion: 'Activa funciones avanzadas para enriquecer las respuestas.',
        ),
        _Fila(
          label: 'Búsqueda en internet',
          descripcion:
              'El asistente puede consultar la web cuando la pregunta lo amerite. Las fuentes se citan en la respuesta.',
          control: _SwitchAnimado(
            value: settings.buscarWeb,
            onChanged: settings.setBuscarWeb,
          ),
        ),
      ],
    );
  }
}

// ────────────────────── VOZ ──────────────────────

class _VozSection extends StatefulWidget {
  const _VozSection({super.key});

  @override
  State<_VozSection> createState() => _VozSectionState();
}

class _VozSectionState extends State<_VozSection> {
  List<Map<String, String>> _voces = [];

  @override
  void initState() {
    super.initState();
    _cargarVoces();
  }

  Future<void> _cargarVoces() async {
    final voces = await TtsService.instance.voicesDisponibles();
    if (mounted) setState(() => _voces = voces);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final settings = context.watch<SettingsProvider>();
    // Filtramos voces al idioma del asistente para una lista más relevante.
    final idiomaTts = settings.idioma.startsWith('es')
        ? 'es'
        : settings.idioma.substring(0, 2);
    final vocesFiltradas = _voces.where((v) => v['locale']!.startsWith(idiomaTts)).toList();
    final vocesParaMostrar = vocesFiltradas.isNotEmpty ? vocesFiltradas : _voces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Voz',
          descripcion: 'Dictado por voz y lectura de respuestas.',
        ),
        const _SubTitulo(titulo: 'Dictado por voz (entrada)'),
        _Fila(
          label: 'Estado',
          descripcion:
              'El botón del micrófono en el composer ya está funcional. Usa el idioma del asistente.',
          control: const _BadgeEstado(label: 'Disponible', color: AppColors.success),
        ),
        const _SubTitulo(titulo: 'Síntesis de voz (salida)'),
        _Fila(
          label: 'Leer respuestas en voz alta',
          descripcion:
              'Cuando el asistente responde, también lo lee con la voz seleccionada.',
          control: _SwitchAnimado(
            value: settings.ttsHabilitado,
            onChanged: settings.setTts,
          ),
        ),
        _Fila(
          label: 'Voz',
          descripcion: '${vocesParaMostrar.length} voces disponibles en tu sistema para el idioma actual.',
          control: SizedBox(
            width: 220,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.borderSoft),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: settings.ttsVoz,
                  dropdownColor: p.surface,
                  isExpanded: true,
                  style: TextStyle(color: p.text, fontSize: 13),
                  icon: Icon(Icons.unfold_more, size: 14, color: p.subtle),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Predeterminada del sistema',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                    ...vocesParaMostrar.map((v) => DropdownMenuItem<String?>(
                          value: v['name'],
                          child: Text(
                            '${v['name']} (${v['locale']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: settings.setTtsVoz,
                ),
              ),
            ),
          ),
        ),
        _Fila(
          label: 'Velocidad de lectura',
          descripcion:
              '${(settings.ttsVelocidad * 2).toStringAsFixed(1)}× — más bajo = más lento.',
          control: SizedBox(
            width: 220,
            child: Slider(
              value: settings.ttsVelocidad,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              activeColor: p.primary,
              onChanged: settings.setTtsVelocidad,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            TtsService.instance.speak(
              'Hola, soy tu asistente. Esta es una prueba de voz.',
              velocidad: settings.ttsVelocidad,
              voz: settings.ttsVoz,
              idioma: settings.idioma.startsWith('es') ? 'es-ES' : 'en-US',
            );
          },
          icon: const Icon(Icons.volume_up, size: 15),
          label: const Text('Probar voz'),
        ),
      ],
    );
  }
}

// ────────────────────── PRIVACIDAD ──────────────────────

class _PrivacidadSection extends StatelessWidget {
  const _PrivacidadSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _Titulo(
          titulo: 'Privacidad y seguridad',
          descripcion: 'Control de tus datos y sesión.',
        ),
        _Fila(
          label: 'Conversaciones',
          descripcion:
              'Tus conversaciones están guardadas en la base de datos y solo tú las ves.',
          control: _BadgeEstado(label: 'Privadas', color: AppColors.success),
        ),
        _Fila(
          label: 'Cifrado de API keys',
          descripcion:
              'Las claves de Gemini/DeepSeek están cifradas en la BD con AES-256.',
          control: _BadgeEstado(label: 'Activo', color: AppColors.success),
        ),
        _Fila(
          label: 'Filtro de contenido',
          descripcion:
              'Bloquea consultas con intención claramente maliciosa (malware, robo de credenciales).',
          control: _BadgeEstado(label: 'Activado', color: AppColors.success),
        ),
      ],
    );
  }
}

class _BadgeEstado extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgeEstado({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ────────────────────── NOTIFICACIONES ──────────────────────

class _NotificacionesSection extends StatelessWidget {
  const _NotificacionesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Notificaciones',
          descripcion: 'Cuándo y cómo te avisamos.',
        ),
        _Fila(
          label: 'Notificaciones del sistema',
          descripcion:
              'Aviso cuando termine un entrenamiento largo (próximamente).',
          control: Text('Próximamente',
              style: TextStyle(
                  fontSize: 12, color: p.subtle, fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }
}

// ────────────────────── ATAJOS ──────────────────────

class _AtajosSection extends StatelessWidget {
  const _AtajosSection({super.key});

  static const _atajos = [
    ('Ctrl + N', 'Nuevo chat'),
    ('Ctrl + ,', 'Abrir configuración'),
    ('Ctrl + /', 'Mostrar atajos'),
    ('Ctrl + B', 'Colapsar/expandir sidebar'),
    ('Ctrl + Enter', 'Enviar mensaje'),
    ('Ctrl + Shift + L', 'Alternar tema claro/oscuro'),
    ('Shift + Enter', 'Nueva línea en composer'),
    ('Esc', 'Cerrar modal / volver'),
    ('↑', 'Mensaje anterior (composer vacío)'),
    ('↓', 'Mensaje siguiente (composer vacío)'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Atajos de teclado',
          descripcion: 'Acelera tu navegación. En macOS usa ⌘ en lugar de Ctrl.',
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.borderSoft),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _atajos.length; i++) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_atajos[i].$2,
                            style: TextStyle(fontSize: 13, color: p.text)),
                      ),
                      _KbdTeclas(combo: _atajos[i].$1),
                    ],
                  ),
                ),
                if (i != _atajos.length - 1)
                  Divider(height: 1, color: p.borderSoft),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _KbdTeclas extends StatelessWidget {
  final String combo;
  const _KbdTeclas({required this.combo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final teclas = combo.split(' + ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < teclas.length; i++) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.borderSoft),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                teclas[i],
                style: TextStyle(
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
          ),
          if (i < teclas.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('+',
                  style: TextStyle(fontSize: 11, color: p.subtle)),
            ),
        ],
      ],
    );
  }
}

// ────────────────────── EXPORTAR ──────────────────────

class _ExportarSection extends StatefulWidget {
  const _ExportarSection({super.key});

  @override
  State<_ExportarSection> createState() => _ExportarSectionState();
}

class _ExportarSectionState extends State<_ExportarSection> {
  List<ConversacionResumen> _conversaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final api = context.read<AuthProvider>().api;
      final list = await api.listarConversaciones();
      if (mounted) setState(() {
        _conversaciones = list;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _toMarkdown(String titulo, List<Mensaje> mensajes) {
    final buf = StringBuffer();
    buf.writeln('# $titulo');
    buf.writeln();
    buf.writeln('_Exportado el ${DateTime.now()}_');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    for (final m in mensajes) {
      if (m.id == 'tmp' || m.id == 'err') continue;
      final rol = m.esUsuario ? 'Tú' : 'Asistente';
      buf.writeln('### $rol');
      buf.writeln();
      buf.writeln(m.contenido);
      buf.writeln();
    }
    return buf.toString();
  }

  Future<void> _exportar(ConversacionResumen c) async {
    final api = context.read<AuthProvider>().api;
    try {
      final mensajes = await api.obtenerMensajes(c.id);
      final md = _toMarkdown(c.titulo, mensajes);
      var nombre = c.titulo
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
              .replaceAll(RegExp(r'^_+|_+$'), '');
      if (nombre.length > 60) nombre = nombre.substring(0, 60);
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar conversación',
        fileName: '${nombre.isEmpty ? "chat" : nombre}.md',
        bytes: Uint8List.fromList(md.codeUnits),
      );
      if (ruta != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Guardado en $ruta')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Exportar',
          descripcion:
              'Descarga tus conversaciones como Markdown para guardar o citar en tu tesis.',
        ),
        const _SubTitulo(titulo: 'Conversaciones disponibles'),
        if (_cargando)
          const Center(child: CircularProgressIndicator())
        else if (_conversaciones.isEmpty)
          Text('Aún no tienes conversaciones para exportar.',
              style: TextStyle(color: p.muted, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.borderSoft),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _conversaciones.take(20).length; i++) ...[
                  ListTile(
                    title: Text(
                      _conversaciones[i].titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.text),
                    ),
                    trailing: OutlinedButton.icon(
                      onPressed: () => _exportar(_conversaciones[i]),
                      icon: const Icon(Icons.download, size: 13),
                      label: const Text('.md'),
                    ),
                  ),
                  if (i != _conversaciones.take(20).length - 1)
                    Divider(height: 1, color: p.borderSoft),
                ],
                if (_conversaciones.length > 20)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '… y ${_conversaciones.length - 20} más.',
                      style: TextStyle(fontSize: 11, color: p.subtle),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ────────────────────── AYUDA ──────────────────────

class _AyudaSection extends StatelessWidget {
  final Usuario? usuario;
  const _AyudaSection({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Ayuda',
          descripcion: 'Recursos para aprovechar al máximo el sistema.',
        ),
        // Botón destacado para volver a ver el tour de bienvenida
        _BotonVerTour(),
        const SizedBox(height: 8),
        _TarjetaAyuda(
          icono: Icons.menu_book,
          titulo: 'Guía del asistente',
          descripcion: 'Cómo hacer mejores preguntas, modo profesor, adjuntos.',
        ),
        const SizedBox(height: 8),
        _TarjetaAyuda(
          icono: Icons.email_outlined,
          titulo: 'Reportar un problema',
          descripcion: 'Envía un correo describiendo qué pasó.',
        ),
        const SizedBox(height: 8),
        _TarjetaAyuda(
          icono: Icons.info_outline,
          titulo: 'Sobre Explicador IA',
          descripcion:
              'LLM educativo entrenado desde cero para enseñanza de Python.',
        ),
      ],
    );
  }
}

class _TarjetaAyuda extends StatefulWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  const _TarjetaAyuda({
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  @override
  State<_TarjetaAyuda> createState() => _TarjetaAyudaState();
}

class _TarjetaAyudaState extends State<_TarjetaAyuda> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hover ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hover ? p.border : p.borderSoft),
        ),
        child: Row(
          children: [
            Icon(widget.icono, size: 16, color: p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.titulo,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: p.text,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(widget.descripcion,
                      style: TextStyle(
                          fontSize: 12, color: p.muted, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: p.subtle),
          ],
        ),
      ),
    );
  }
}

// ────────────────────── BOTÓN TOUR ──────────────────────

class _BotonVerTour extends StatefulWidget {
  @override
  State<_BotonVerTour> createState() => _BotonVerTourState();
}

class _BotonVerTourState extends State<_BotonVerTour> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => showOnboarding(context),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hover
                ? p.primary.withValues(alpha: 0.12)
                : p.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? p.primary : p.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: p.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ver el tour de bienvenida',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: p.text,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      '5 slides con las funciones clave. 30 segundos.',
                      style: TextStyle(
                          fontSize: 12, color: p.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 14, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────── AVANZADO (URL backend, estado modelo) ──────────────────────

class _AvanzadoSection extends StatelessWidget {
  final SettingsProvider settings;
  final Map<String, dynamic>? estadoModelo;
  const _AvanzadoSection({super.key, required this.settings, this.estadoModelo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo(
          titulo: 'Avanzado',
          descripcion:
              'Opciones que rara vez necesitan cambiar. Solo modifica si sabes lo que haces.',
        ),
        const _SubTitulo(titulo: 'Conexión al backend'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, size: 13, color: p.muted),
                  const SizedBox(width: 6),
                  Text('URL efectiva',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p.muted)),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                settings.apiUrlEfectiva,
                style: TextStyle(
                  fontSize: 12.5,
                  color: p.text,
                  fontFamily: AppFonts.monoFallback.first,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SubTitulo(titulo: 'Estado del modelo propio'),
        if (estadoModelo == null)
          Text('Verificando…',
              style: TextStyle(fontSize: 12.5, color: p.subtle))
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.borderSoft),
            ),
            child: Row(
              children: [
                Icon(
                  estadoModelo!['disponible'] == true
                      ? Icons.check_circle
                      : Icons.hourglass_empty,
                  size: 18,
                  color: estadoModelo!['disponible'] == true
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    estadoModelo!['disponible'] == true
                        ? 'Modelo activo'
                        : (estadoModelo!['motivo']?.toString() ??
                            'Modelo no entrenado'),
                    style: TextStyle(fontSize: 13, color: p.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
