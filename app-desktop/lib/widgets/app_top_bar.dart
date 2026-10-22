import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers.dart';
import '../screens/home_screen.dart';
import '../theme.dart';
import 'brand_logo.dart';
import 'estudio_docente.dart';

/// Barra superior de navegación y controles del sistema.
///
/// Integra:
///  - Breadcrumb de navegación con la sección activa.
///  - Omnibar central con acceso directo a la Paleta de Comandos (Ctrl+K).
///  - Indicador del Modelo IA activo con badge de rendimiento.
///  - Botones de acción rápida: Alternar tema, Atajos y Configuración.
///  - Avatar de usuario con rol y nombre.
class AppTopBar extends StatelessWidget {
  final VistaPrincipal vista;
  final VoidCallback onAbrirPalette;
  final VoidCallback onAbrirAtajos;
  final VoidCallback onAbrirSettings;
  final VoidCallback onToggleSidebar;
  final bool sidebarColapsado;

  const AppTopBar({
    super.key,
    required this.vista,
    required this.onAbrirPalette,
    required this.onAbrirAtajos,
    required this.onAbrirSettings,
    required this.onToggleSidebar,
    required this.sidebarColapsado,
  });

  String _nombreVista(VistaPrincipal v) {
    switch (v) {
      case VistaPrincipal.chat:
        return 'Chat Asistente';
      case VistaPrincipal.explicar:
        return 'Explicador de Código';
      case VistaPrincipal.code:
        return 'Editor de Código';
      case VistaPrincipal.proyecto:
        return 'Explorador de Archivos';
      case VistaPrincipal.terminal:
        return 'Terminal Interactiva';
    }
  }

  IconData _iconoVista(VistaPrincipal v) {
    switch (v) {
      case VistaPrincipal.chat:
        return Icons.chat_bubble_outline_rounded;
      case VistaPrincipal.explicar:
        return Icons.auto_awesome_rounded;
      case VistaPrincipal.code:
        return Icons.code_rounded;
      case VistaPrincipal.proyecto:
        return Icons.folder_open_rounded;
      case VistaPrincipal.terminal:
        return Icons.terminal_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    const String modeloLabel = 'Asistente Python IA';
    final Color modeloColor = p.primary;

    final String modoEstudioLabel = settings.esBloqueadoPostTest
        ? (settings.faseEstudio == 'pre' ? 'Pretest (sin IA)' : 'Postest (sin IA)')
        : (settings.esSinAcompanamiento ? 'Solo Código' : 'Acompañamiento');
    final Color modoEstudioColor = settings.esBloqueadoPostTest
        ? AppColors.danger
        : (settings.esSinAcompanamiento ? p.subtle : p.primary);
    final IconData modoEstudioIcono = settings.esBloqueadoPostTest
        ? Icons.lock_clock_rounded
        : (settings.esSinAcompanamiento ? Icons.code_rounded : Icons.school_rounded);

    final String moduloLabel = settings.esModuloPrincipiante
        ? 'Módulo 1: Fundamentos'
        : (settings.esModuloIntermedio ? 'Módulo 2: Control y Estructuras' : 'Módulo 3: Algoritmos y POO');
    final Color moduloColor = settings.esModuloPrincipiante
        ? Colors.blue
        : (settings.esModuloIntermedio ? Colors.amber.shade700 : Colors.purple);
    final IconData moduloIcono = settings.esModuloPrincipiante
        ? Icons.menu_book_rounded
        : (settings.esModuloIntermedio ? Icons.alt_route_rounded : Icons.psychology_rounded);

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mostrarBuscador = constraints.maxWidth >= 1450;
          final mostrarDetalles = constraints.maxWidth >= 1100;
          return Row(
        children: [
          // ── 1. Izquierda: Logo y Título interactivo (Toggle sidebar Ctrl+B) ──
          Tooltip(
            message: sidebarColapsado
                ? 'Expandir barra lateral (Ctrl+B)'
                : 'Colapsar barra lateral (Ctrl+B)',
            child: InkWell(
              onTap: onToggleSidebar,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: p.primaryGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const BrandLogo(
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Explicador IA',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),

          // Breadcrumb
          if (mostrarDetalles) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '›',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: p.subtle,
              ),
            ),
          ),
          Icon(_iconoVista(vista), size: 14, color: p.primary),
          const SizedBox(width: 5),
          Text(
            _nombreVista(vista),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: p.muted,
            ),
          ),
          ],

          const Spacer(),

          // ── 2. Centro: Omnibar / Command Center ──
          if (mostrarBuscador) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minWidth: 260),
            child: _OmnibarLauncher(onTap: onAbrirPalette),
          ),

          const Spacer(),
          ],

          // ── 3. Derecha: Modelo + Atajos + Tema + Usuario ──
          // Chip del Modelo Activo
          if (mostrarDetalles) Tooltip(
            message: 'Motor neuronal activo (Clic para configuración)',
            child: InkWell(
              onTap: onAbrirSettings,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: modeloColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: modeloColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: modeloColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      modeloLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: modeloColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: modeloColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Chip del Módulo Curricular (Clic para cambiar nivel de andamiaje)
          if (mostrarDetalles) Tooltip(
            message: 'Módulo Curricular de Aprendizaje (Clic para cambiar nivel)',
            child: InkWell(
              onTap: () => _mostrarDialogoModulos(context),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: moduloColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: moduloColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(moduloIcono, size: 13, color: moduloColor),
                    const SizedBox(width: 6),
                    Text(
                      moduloLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: moduloColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down_rounded, size: 14, color: moduloColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Chip de la Condición Experimental de Tesis (Clic para alternar)
          Tooltip(
            message: 'Condición Cuasiexperimental de Tesis (Clic para alternar)',
            child: InkWell(
              onTap: () => _mostrarDialogoModoEstudio(context),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: modoEstudioColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: modoEstudioColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(modoEstudioIcono, size: 13, color: modoEstudioColor),
                    const SizedBox(width: 6),
                    Text(
                      modoEstudioLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: modoEstudioColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down_rounded, size: 14, color: modoEstudioColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Botón Tema (Claro / Oscuro)
          Tooltip(
            message: esOscuro
                ? 'Cambiar a modo claro (Ctrl+Shift+L)'
                : 'Cambiar a modo oscuro (Ctrl+Shift+L)',
            child: IconButton(
              icon: Icon(
                esOscuro
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 18,
                color: p.muted,
              ),
              splashRadius: 18,
              onPressed: () {
                theme.setMode(esOscuro ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          ),

          // Botón Configuración (los atajos están accesibles dentro de Configuración o con Ctrl+/)
          Tooltip(
            message: 'Configuración (Ctrl+,)',
            child: IconButton(
              icon: Icon(Icons.tune_rounded, size: 18, color: p.muted),
              splashRadius: 18,
              onPressed: onAbrirSettings,
            ),
          ),

          const SizedBox(width: 4),

          // Avatar de usuario
          if (auth.usuario != null) ...[
            Container(
              height: 24,
              width: 1,
              color: p.borderSoft,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            Tooltip(
              message: ' ()',
              child: InkWell(
                onTap: onAbrirSettings,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: p.primary.withValues(alpha: 0.2),
                        child: Text(
                          (auth.usuario?.nombre.isNotEmpty ?? false)
                              ? auth.usuario!.nombre[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: p.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        auth.usuario?.nombre.split(' ').first ?? 'Admin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: p.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          auth.usuario?.rol.toUpperCase() ?? 'ADMIN',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: p.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
          );
        },
      ),
    );
  }
}

/// Omnibar central interactiva con hover suave y atajo Ctrl+K
class _OmnibarLauncher extends StatefulWidget {
  final VoidCallback onTap;
  const _OmnibarLauncher({required this.onTap});

  @override
  State<_OmnibarLauncher> createState() => _OmnibarLauncherState();
}

class _OmnibarLauncherState extends State<_OmnibarLauncher> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover
                ? p.surface2
                : p.surface2.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: _hover
                  ? p.primary.withValues(alpha: 0.45)
                  : p.borderSoft,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: p.primary.withValues(alpha: 0.08),
                      blurRadius: 10,
                      spreadRadius: -1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 14,
                color: _hover ? p.primary : p.subtle,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Buscar archivos, atajos o preguntar a la IA...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _hover ? p.text : p.subtle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: p.borderSoft),
                ),
                child: Text(
                  'Ctrl K',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: p.muted,
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

void _mostrarDialogoModoEstudio(BuildContext context) {
  final settings = context.read<SettingsProvider>();
  final p = AppPalette.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.science_outlined, size: 20, color: p.primary),
          const SizedBox(width: 10),
          const Text('Condición Cuasiexperimental de Tesis', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.asignacionActiva
                  ? 'Condición asignada por el docente. Fase: ${settings.faseEstudio ?? "intervencion"}.'
                  : 'Modo de exploración local (sin asignación de estudio):',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: settings.esConAcompanamiento ? p.surface2 : null,
              leading: const Icon(Icons.school_rounded, color: Colors.teal),
              title: const Text('Grupo Experimental', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Con Acompañamiento Didáctico y Andamiaje Pedagógico paso a paso', style: TextStyle(fontSize: 11)),
              trailing: settings.esConAcompanamiento ? const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 18) : null,
              onTap: settings.asignacionActiva ? null : () {
                settings.setModoAcompanamiento('con_acompanamiento');
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 6),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: settings.esSinAcompanamiento ? p.surface2 : null,
              leading: const Icon(Icons.code_rounded, color: Colors.blueGrey),
              title: const Text('Grupo Control', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Sin Acompañamiento (Generación directa de código sin explicaciones)', style: TextStyle(fontSize: 11)),
              trailing: settings.esSinAcompanamiento ? const Icon(Icons.check_circle_rounded, color: Colors.blueGrey, size: 18) : null,
              onTap: settings.asignacionActiva ? null : () {
                settings.setModoAcompanamiento('sin_acompanamiento');
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 6),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: settings.esBloqueadoPostTest ? p.surface2 : null,
              leading: const Icon(Icons.lock_clock_rounded, color: AppColors.danger),
              title: const Text('Pretest y postest', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.danger)),
              subtitle: Text(context.read<AuthProvider>().usuario?.esInvestigador == true
                  ? 'Administrar evaluaciones y abrir una vista previa docente'
                  : 'El docente asigna y abre tu evaluación; no se activa desde este selector.', style: const TextStyle(fontSize: 11)),
              trailing: settings.esBloqueadoPostTest ? const Icon(Icons.check_circle_rounded, color: AppColors.danger, size: 18) : null,
              onTap: context.read<AuthProvider>().usuario?.esInvestigador != true ? null : () {
                Navigator.pop(ctx);
                abrirEstudioDocente(context);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

void _mostrarDialogoModulos(BuildContext context) {
  final settings = context.read<SettingsProvider>();
  final p = AppPalette.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_stories_rounded, size: 20, color: p.primary),
          const SizedBox(width: 10),
          const Text('Ruta de Aprendizaje Curricular (Python)', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Currículo basado en "El Libro de Python". Selecciona el módulo para calibrar el andamiaje pedagógico de la IA:',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              const SizedBox(height: 14),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: settings.esModuloPrincipiante ? p.surface2 : null,
                leading: const Icon(Icons.menu_book_rounded, color: Colors.blue),
                title: const Text('Módulo 1: Principiante (Fundamentos y Palabras Reservadas)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  '• Variables (ej. Luis = 1) y tipos de datos primitivos (int, float, str, bool)\n'
                  '• Palabras reservadas oficiales (keyword.kwlist: def, if, for, return, True, False, None)\n'
                  '• Entrada y salida estándar print(), input() e indentación de 4 espacios\n'
                  '💡 Andamiaje: Desglose sintáctico paso a paso con analogías sencillas.',
                  style: TextStyle(fontSize: 11, height: 1.35),
                ),
                trailing: settings.esModuloPrincipiante ? const Icon(Icons.check_circle_rounded, color: Colors.blue, size: 18) : null,
                onTap: () {
                  settings.setNivelModulo('principiante');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: settings.esModuloIntermedio ? p.surface2 : null,
                leading: Icon(Icons.alt_route_rounded, color: Colors.amber.shade700),
                title: const Text('Módulo 2: Intermedio (Estructuras de Control y Colecciones)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  '• Condicionales if/elif/else y bucles for/while con range()\n'
                  '• Colecciones de datos: listas [], diccionarios {}, tuplas ()\n'
                  '• Variables de rol algorítmico: acumuladores, contadores y banderas\n'
                  '• Programación defensiva: prevención de ZeroDivisionError, listas vacías y try/except\n'
                  '💡 Andamiaje: Invariantes de bucles, casos límite y blindaje de código.',
                  style: TextStyle(fontSize: 11, height: 1.35),
                ),
                trailing: settings.esModuloIntermedio ? Icon(Icons.check_circle_rounded, color: Colors.amber.shade700, size: 18) : null,
                onTap: () {
                  settings.setNivelModulo('intermedio');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: settings.esModuloAvanzado ? p.surface2 : null,
                leading: const Icon(Icons.psychology_rounded, color: Colors.purple),
                title: const Text('Módulo 3: Avanzado (Algoritmos, Big-O y POO)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  '• Análisis asintótico formal: Notación Big-O temporal y espacial (O(1), O(log n), O(n), O(n²))\n'
                  '• Programación Orientada a Objetos: clases class, __init__, métodos, self y herencia\n'
                  '• Estándares de calidad PEP 8, tipado estático (typing) y refactorización moderna\n'
                  '💡 Andamiaje: Análisis matemático Big-O, trade-offs de arquitectura y escalabilidad.',
                  style: TextStyle(fontSize: 11, height: 1.35),
                ),
                trailing: settings.esModuloAvanzado ? const Icon(Icons.check_circle_rounded, color: Colors.purple, size: 18) : null,
                onTap: () {
                  settings.setNivelModulo('avanzado');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
