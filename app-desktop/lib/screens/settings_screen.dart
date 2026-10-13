import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/settings/section_apariencia.dart';
import '../widgets/settings/section_administracion.dart';
import '../widgets/settings/section_atajos.dart';
import '../widgets/settings/section_avanzado.dart';
import '../widgets/settings/section_ayuda.dart';
import '../widgets/settings/section_capacidades.dart';
import '../widgets/settings/section_cuenta.dart';
import '../widgets/settings/section_exportar.dart';
import '../widgets/settings/section_idioma.dart';
import '../widgets/settings/section_notificaciones.dart';
import '../widgets/settings/section_privacidad.dart';
import '../widgets/settings/section_voz.dart';

/// Pantalla de configuración del sistema:
///   - Sidebar izquierda con secciones agrupadas
///   - Área de contenido a la derecha (cambia según sección activa)
///   - Búsqueda para filtrar secciones
///   - Cierre con X o Esc
///
/// El contenido de cada sección vive en `lib/widgets/settings/*.dart` — este
/// archivo solo se encarga del layout y la navegación.
enum _SeccionId {
  cuenta,
  apariencia,
  idioma,
  capacidades,
  voz,
  privacidad,
  notificaciones,
  atajos,
  exportar,
  ayuda,
  avanzado,
  administracion,
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
Future<void> showSettings(
  BuildContext context, {
  bool abrirAdministracion = false,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) =>
        SettingsScreen(abrirAdministracion: abrirAdministracion),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.96,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

class SettingsScreen extends StatefulWidget {
  final bool abrirAdministracion;
  const SettingsScreen({super.key, this.abrirAdministracion = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SeccionId _activa = _SeccionId.cuenta;
  String _busqueda = '';
  Map<String, dynamic>? _estadoModelo;

  static const List<_Seccion> _todas = [
    _Seccion(
      id: _SeccionId.cuenta,
      label: 'Cuenta',
      icono: Icons.person_outline,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.apariencia,
      label: 'Apariencia',
      icono: Icons.palette_outlined,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.idioma,
      label: 'Idioma',
      icono: Icons.translate,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.capacidades,
      label: 'Capacidades',
      icono: Icons.auto_awesome,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.administracion,
      label: 'Administración',
      icono: Icons.admin_panel_settings_outlined,
      grupo: 'Administración',
    ),
    _Seccion(
      id: _SeccionId.voz,
      label: 'Voz',
      icono: Icons.mic_none,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.privacidad,
      label: 'Privacidad',
      icono: Icons.lock_outline,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.notificaciones,
      label: 'Notificaciones',
      icono: Icons.notifications_outlined,
      grupo: 'Configuración',
    ),
    _Seccion(
      id: _SeccionId.atajos,
      label: 'Atajos de teclado',
      icono: Icons.keyboard_outlined,
      grupo: 'Aplicación',
    ),
    _Seccion(
      id: _SeccionId.exportar,
      label: 'Exportar',
      icono: Icons.download_outlined,
      grupo: 'Aplicación',
    ),
    _Seccion(
      id: _SeccionId.ayuda,
      label: 'Ayuda',
      icono: Icons.help_outline,
      grupo: 'Aplicación',
    ),
    _Seccion(
      id: _SeccionId.avanzado,
      label: 'Avanzado',
      icono: Icons.settings_ethernet,
      grupo: 'Avanzado',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.abrirAdministracion &&
        context.read<AuthProvider>().usuario?.esAdmin == true) {
      _activa = _SeccionId.administracion;
    }
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
    final esAdmin = context.read<AuthProvider>().usuario?.esAdmin == true;
    final visibles = _todas.where(
      (s) => s.id != _SeccionId.administracion || esAdmin,
    );
    if (_busqueda.trim().isEmpty) return visibles.toList();
    final q = _busqueda.toLowerCase();
    return visibles.where((s) => s.label.toLowerCase().contains(q)).toList();
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
    // Cuadro: 88-94% de la pantalla con límites sensatos (mismo que web).
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
              Icon(s.icono, size: 15, color: activa ? p.primary : p.muted),
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
              child: _seccionContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _seccionContent() {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final theme = context.watch<ThemeProvider>();
    switch (_activa) {
      case _SeccionId.cuenta:
        return CuentaSection(
          key: const ValueKey('cuenta'),
          usuario: auth.usuario,
        );
      case _SeccionId.apariencia:
        return AparienciaSection(
          key: const ValueKey('apariencia'),
          theme: theme,
        );
      case _SeccionId.idioma:
        return IdiomaSection(key: const ValueKey('idioma'), settings: settings);
      case _SeccionId.capacidades:
        return CapacidadesSection(
          key: const ValueKey('capacidades'),
          settings: settings,
        );
      case _SeccionId.voz:
        return const VozSection(key: ValueKey('voz'));
      case _SeccionId.privacidad:
        return const PrivacidadSection(key: ValueKey('priv'));
      case _SeccionId.notificaciones:
        return const NotificacionesSection(key: ValueKey('notif'));
      case _SeccionId.atajos:
        return const AtajosSection(key: ValueKey('atajos'));
      case _SeccionId.exportar:
        return const ExportarSection(key: ValueKey('exp'));
      case _SeccionId.ayuda:
        return AyudaSection(
          key: const ValueKey('ayuda'),
          usuario: auth.usuario,
        );
      case _SeccionId.avanzado:
        return AvanzadoSection(
          key: const ValueKey('av'),
          settings: settings,
          estadoModelo: _estadoModelo,
        );
      case _SeccionId.administracion:
        return const AdministracionSection(key: ValueKey('admin'));
    }
  }
}
