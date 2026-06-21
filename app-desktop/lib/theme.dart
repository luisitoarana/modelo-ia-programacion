import 'package:flutter/material.dart';

/// Paleta cálida inspirada en las apps de Anthropic (Claude.ai + Claude Code).
///
/// Decisiones de diseño:
///  - Fondos cálidos (off-white / dark warm) en vez de azulados fríos.
///  - Acento terracota (#D97757) como en Claude.
///  - Tipografía serif ("Georgia") para titulares, sans-serif del sistema
///    para UI y monospace para código.
///  - Bordes muy sutiles y radios suaves (12–16 px).
class AppColors {
  // ---- Oscuro (cálido) ----
  static const darkBg = Color(0xFF262624);       // fondo principal
  static const darkSurface = Color(0xFF30302E);  // tarjetas, sidebar
  static const darkSurface2 = Color(0xFF3A3A37); // hover / activo
  static const darkSurface3 = Color(0xFF45453F); // input, code bg
  static const darkBorder = Color(0xFF3D3D3A);
  static const darkBorderSoft = Color(0xFF333330);
  static const darkText = Color(0xFFF5F4ED);
  static const darkMuted = Color(0xFFB8B5A8);
  static const darkSubtle = Color(0xFF8A8779);

  // ---- Claro (off-white estilo papel) ----
  static const lightBg = Color(0xFFFAF9F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF0EFE7);
  static const lightSurface3 = Color(0xFFE8E6DA);
  static const lightBorder = Color(0xFFE5E2D6);
  static const lightBorderSoft = Color(0xFFEDEBE0);
  static const lightText = Color(0xFF1F1E1B);
  static const lightMuted = Color(0xFF6B6A5E);
  static const lightSubtle = Color(0xFF8E8C7E);

  // ---- Acentos ----
  static const primary = Color(0xFFD97757);        // terracota Anthropic
  static const primaryHover = Color(0xFFC96644);
  static const primarySoft = Color(0xFFE9A287);
  static const accent = Color(0xFFB85C3E);         // terracota oscuro
  static const success = Color(0xFF6B8E5A);
  static const danger = Color(0xFFC15F4D);
  static const warning = Color(0xFFCE9A4F);
  static const info = Color(0xFF6B8AAE);
}

/// Tokens de animación — curvas y duraciones consistentes en toda la app.
///
/// Mantiene la "voz" del producto: animaciones rápidas, suaves, nunca
/// llamativas. Estilo Anthropic: la UI no llama la atención sobre sí misma,
/// se siente fluida sin ser dramática.
class AppMotion {
  /// Curva por defecto: ease-out suave (lo que usan Linear, Vercel, Anthropic).
  static const Curve standard = Cubic(0.16, 1, 0.3, 1);

  /// Curva para entradas que aparecen (modales, popovers).
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);

  /// Duración corta: tooltips, hovers (110ms).
  static const Duration fast = Duration(milliseconds: 110);

  /// Duración media: dropdowns, paneles (220ms).
  static const Duration medium = Duration(milliseconds: 220);

  /// Duración larga: transiciones entre vistas (320ms).
  static const Duration slow = Duration(milliseconds: 320);
}

/// Sistema de espaciado de 4px — usar siempre múltiplos de 4.
/// Evita el "espaciado a ojo" que hace la UI inconsistente.
class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
}

/// Sistema de elevación de 5 niveles inspirado en Material 3 + Anthropic.
///
/// Cada nivel se usa para una intención de diseño distinta:
///  - level0: superficie plana, sin sombra (fondo de la app).
///  - level1: chips, hover de botones outline.
///  - level2: cards y botones primarios en reposo.
///  - level3: dropdowns, popovers, tooltips.
///  - level4: modales, bottom sheets, command palette.
///  - level5: drag preview (efecto "flotando").
///
/// Usar los métodos de [AppPalette] (`p.elevation(N)`) en lugar de
/// definir BoxShadow ad-hoc en cada widget para mantener consistencia.
class AppElevation {
  /// Sombra base, "humo" muy difuso a la sombra del objeto.
  static List<BoxShadow> _layered(Color shadow, double a, double b) {
    return <BoxShadow>[
      BoxShadow(
        color: shadow.withValues(alpha: a),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: b),
        blurRadius: 28,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> level0() => const <BoxShadow>[];
  static List<BoxShadow> level1(Color shadow) =>
      _layered(shadow, 0.05, 0.04);
  static List<BoxShadow> level2(Color shadow) =>
      _layered(shadow, 0.10, 0.08);
  static List<BoxShadow> level3(Color shadow) =>
      _layered(shadow, 0.15, 0.14);
  static List<BoxShadow> level4(Color shadow) =>
      _layered(shadow, 0.22, 0.18);
  static List<BoxShadow> level5(Color shadow) =>
      _layered(shadow, 0.32, 0.24);
}

/// Sistema de radios para mantener bordes consistentes.
class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;
}

/// Familias tipográficas con fallbacks multiplataforma.
class AppFonts {
  /// Sans serif para UI general. Usa la fuente del SO si no hay Inter.
  static const List<String> sansFallback = <String>[
    'Inter',
    'Segoe UI',
    'SF Pro Display',
    'Helvetica Neue',
    'Roboto',
    'Arial',
  ];

  /// Serif para titulares (estilo papel / Claude).
  static const List<String> serifFallback = <String>[
    'Tiempos Text',
    'Source Serif Pro',
    'Georgia',
    'Cambria',
    'Times New Roman',
  ];

  /// Monospace para código.
  static const List<String> monoFallback = <String>[
    'JetBrains Mono',
    'Fira Code',
    'Consolas',
    'Menlo',
    'Monaco',
    'Courier New',
  ];
}

/// Set de colores para una paleta en un modo (claro u oscuro).
class _PalCol {
  final Color bg, surface, surface2, surface3, border, borderSoft;
  final Color text, muted, subtle, primary, primaryHover;
  final Color accent, codeBg, codeText;
  const _PalCol({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.primary,
    required this.primaryHover,
    required this.accent,
    required this.codeBg,
    required this.codeText,
  });
}

/// Información de una paleta de colores disponibles para que el usuario
/// elija desde la pantalla de Configuración.
class PaletaInfo {
  final String id;
  final String nombre;
  final String descripcion;
  final List<Color> swatches; // 3 colores representativos
  final _PalCol light;
  final _PalCol dark;
  const PaletaInfo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.swatches,
    required this.light,
    required this.dark,
  });
}

/// Catálogo de paletas. Cada paleta cambia toda la app.
class Paletas {
  static const Map<String, PaletaInfo> todas = {
    'terracota': PaletaInfo(
      id: 'terracota',
      nombre: 'Terracota (Anthropic)',
      descripcion: 'La paleta original. Cálida, cercana, tipo papel.',
      swatches: [Color(0xFFD97757), Color(0xFFFAF9F5), Color(0xFF1F1E1B)],
      light: _PalCol(
        bg: Color(0xFFFAF9F5), surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFF0EFE7), surface3: Color(0xFFE8E6DA),
        border: Color(0xFFE5E2D6), borderSoft: Color(0xFFEDEBE0),
        text: Color(0xFF1F1E1B), muted: Color(0xFF6B6A5E), subtle: Color(0xFF8E8C7E),
        primary: Color(0xFFD97757), primaryHover: Color(0xFFC96644),
        accent: Color(0xFFB85C3E),
        codeBg: Color(0xFF1F1E1B), codeText: Color(0xFFF5F4ED),
      ),
      dark: _PalCol(
        bg: Color(0xFF262624), surface: Color(0xFF30302E),
        surface2: Color(0xFF3A3A37), surface3: Color(0xFF45453F),
        border: Color(0xFF3D3D3A), borderSoft: Color(0xFF333330),
        text: Color(0xFFF5F4ED), muted: Color(0xFFB8B5A8), subtle: Color(0xFF8A8779),
        primary: Color(0xFFD97757), primaryHover: Color(0xFFE58A6A),
        accent: Color(0xFFC97052),
        codeBg: Color(0xFF1B1A18), codeText: Color(0xFFEDEAD9),
      ),
    ),
    'academico': PaletaInfo(
      id: 'academico',
      nombre: 'Académico Azul',
      descripcion: 'Sobrio y profesional. Para defensa de tesis universitaria.',
      swatches: [Color(0xFF2563EB), Color(0xFFF8FAFC), Color(0xFF0F172A)],
      light: _PalCol(
        bg: Color(0xFFF8FAFC), surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFF1F5F9), surface3: Color(0xFFE2E8F0),
        border: Color(0xFFE2E8F0), borderSoft: Color(0xFFEEF2F8),
        text: Color(0xFF0F172A), muted: Color(0xFF475569), subtle: Color(0xFF94A3B8),
        primary: Color(0xFF2563EB), primaryHover: Color(0xFF1D4ED8),
        accent: Color(0xFF7C3AED),
        codeBg: Color(0xFF0F172A), codeText: Color(0xFFE6EDF6),
      ),
      dark: _PalCol(
        bg: Color(0xFF0A0F1D), surface: Color(0xFF0F172A),
        surface2: Color(0xFF18233A), surface3: Color(0xFF24324A),
        border: Color(0xFF24324A), borderSoft: Color(0xFF1E293B),
        text: Color(0xFFE6EDF6), muted: Color(0xFF94A3B8), subtle: Color(0xFF64748B),
        primary: Color(0xFF3B82F6), primaryHover: Color(0xFF60A5FA),
        accent: Color(0xFF8B5CF6),
        codeBg: Color(0xFF020617), codeText: Color(0xFFE2E8F0),
      ),
    ),
    'bosque': PaletaInfo(
      id: 'bosque',
      nombre: 'Verde Bosque',
      descripcion: 'Tranquilo y natural. Tonos crema y verde profundo.',
      swatches: [Color(0xFF16A34A), Color(0xFFF7F5EF), Color(0xFF1C2316)],
      light: _PalCol(
        bg: Color(0xFFF7F5EF), surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFECEBE2), surface3: Color(0xFFDDE0D3),
        border: Color(0xFFDDE0D3), borderSoft: Color(0xFFE8E6DB),
        text: Color(0xFF1C2316), muted: Color(0xFF5C6B54), subtle: Color(0xFF8A9684),
        primary: Color(0xFF16A34A), primaryHover: Color(0xFF15803D),
        accent: Color(0xFFD97706),
        codeBg: Color(0xFF1C2316), codeText: Color(0xFFEEF0EA),
      ),
      dark: _PalCol(
        bg: Color(0xFF1A201A), surface: Color(0xFF262D24),
        surface2: Color(0xFF2F3A2D), surface3: Color(0xFF3A4737),
        border: Color(0xFF3A4737), borderSoft: Color(0xFF2F3A2D),
        text: Color(0xFFEEF0EA), muted: Color(0xFFB8BCAF), subtle: Color(0xFF7E8479),
        primary: Color(0xFF22C55E), primaryHover: Color(0xFF4ADE80),
        accent: Color(0xFFF59E0B),
        codeBg: Color(0xFF111811), codeText: Color(0xFFEEF0EA),
      ),
    ),
    'purpura': PaletaInfo(
      id: 'purpura',
      nombre: 'Púrpura Real',
      descripcion: 'Elegante y creativo. Violetas y lavandas suaves.',
      swatches: [Color(0xFF8B5CF6), Color(0xFFFAF8FF), Color(0xFF1C1530)],
      light: _PalCol(
        bg: Color(0xFFFAF8FF), surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFF1EDFA), surface3: Color(0xFFE6DDF5),
        border: Color(0xFFE6DDF5), borderSoft: Color(0xFFF1EDFA),
        text: Color(0xFF1C1530), muted: Color(0xFF5C5072), subtle: Color(0xFF9690A8),
        primary: Color(0xFF8B5CF6), primaryHover: Color(0xFF7C3AED),
        accent: Color(0xFFEC4899),
        codeBg: Color(0xFF1C1530), codeText: Color(0xFFEEE9F7),
      ),
      dark: _PalCol(
        bg: Color(0xFF1A142A), surface: Color(0xFF251D3A),
        surface2: Color(0xFF322752), surface3: Color(0xFF3F3266),
        border: Color(0xFF3F3266), borderSoft: Color(0xFF322752),
        text: Color(0xFFEEE9F7), muted: Color(0xFFB5ACC9), subtle: Color(0xFF7D75A0),
        primary: Color(0xFFA78BFA), primaryHover: Color(0xFFC4B5FD),
        accent: Color(0xFFF472B6),
        codeBg: Color(0xFF130E1F), codeText: Color(0xFFEEE9F7),
      ),
    ),
    'mono': PaletaInfo(
      id: 'mono',
      nombre: 'Minimalista',
      descripcion: 'Solo grises. Foco máximo en el contenido.',
      swatches: [Color(0xFF404040), Color(0xFFFAFAFA), Color(0xFF171717)],
      light: _PalCol(
        bg: Color(0xFFFAFAFA), surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFF4F4F5), surface3: Color(0xFFE4E4E7),
        border: Color(0xFFE4E4E7), borderSoft: Color(0xFFF4F4F5),
        text: Color(0xFF171717), muted: Color(0xFF525252), subtle: Color(0xFFA3A3A3),
        primary: Color(0xFF404040), primaryHover: Color(0xFF262626),
        accent: Color(0xFF737373),
        codeBg: Color(0xFF171717), codeText: Color(0xFFFAFAFA),
      ),
      dark: _PalCol(
        bg: Color(0xFF0A0A0A), surface: Color(0xFF171717),
        surface2: Color(0xFF262626), surface3: Color(0xFF404040),
        border: Color(0xFF404040), borderSoft: Color(0xFF262626),
        text: Color(0xFFFAFAFA), muted: Color(0xFFA3A3A3), subtle: Color(0xFF737373),
        primary: Color(0xFFE5E5E5), primaryHover: Color(0xFFFAFAFA),
        accent: Color(0xFFA3A3A3),
        codeBg: Color(0xFF000000), codeText: Color(0xFFFAFAFA),
      ),
    ),
  };

  static PaletaInfo get(String id) => todas[id] ?? todas['terracota']!;
}

class AppTheme {
  /// Tema claro con paleta personalizable.
  static ThemeData light({String paletaId = 'terracota'}) {
    final c = Paletas.get(paletaId).light;
    return _build(
      brightness: Brightness.light,
      bg: c.bg, surface: c.surface, surface2: c.surface2, surface3: c.surface3,
      border: c.border, borderSoft: c.borderSoft,
      text: c.text, muted: c.muted, subtle: c.subtle,
      primary: c.primary, primaryHover: c.primaryHover, accent: c.accent,
      codeBg: c.codeBg, codeText: c.codeText,
      shadow: Colors.black.withValues(alpha: 0.06),
    );
  }

  /// Tema oscuro con paleta personalizable.
  static ThemeData dark({String paletaId = 'terracota'}) {
    final c = Paletas.get(paletaId).dark;
    return _build(
      brightness: Brightness.dark,
      bg: c.bg, surface: c.surface, surface2: c.surface2, surface3: c.surface3,
      border: c.border, borderSoft: c.borderSoft,
      text: c.text, muted: c.muted, subtle: c.subtle,
      primary: c.primary, primaryHover: c.primaryHover, accent: c.accent,
      codeBg: c.codeBg, codeText: c.codeText,
      shadow: Colors.black.withValues(alpha: 0.35),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color surface3,
    required Color border,
    required Color borderSoft,
    required Color text,
    required Color muted,
    required Color subtle,
    required Color primary,
    Color? primaryHover,
    Color? accent,
    required Color codeBg,
    required Color codeText,
    required Color shadow,
  }) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final isDark = brightness == Brightness.dark;
    final accentColor = accent ?? AppColors.accent;
    final hoverColor = primaryHover ?? AppColors.primaryHover;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      surface: surface,
      onSurface: text,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accentColor,
      onSecondary: Colors.white,
      error: AppColors.danger,
      outline: border,
      outlineVariant: borderSoft,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: colorScheme,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      cardColor: surface,

      // Tipografía: serif para títulos grandes, sans para el resto.
      textTheme: base.textTheme
          .apply(
            fontFamily: AppFonts.sansFallback.first,
            fontFamilyFallback: AppFonts.sansFallback,
            bodyColor: text,
            displayColor: text,
          )
          .copyWith(
            displayLarge: TextStyle(
              fontFamily: AppFonts.serifFallback.first,
              fontFamilyFallback: AppFonts.serifFallback,
              fontSize: 38,
              height: 1.15,
              fontWeight: FontWeight.w500,
              color: text,
              letterSpacing: -0.4,
            ),
            displayMedium: TextStyle(
              fontFamily: AppFonts.serifFallback.first,
              fontFamilyFallback: AppFonts.serifFallback,
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: text,
            ),
            headlineLarge: TextStyle(
              fontFamily: AppFonts.serifFallback.first,
              fontFamilyFallback: AppFonts.serifFallback,
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: text,
            ),
            titleLarge: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: text,
            ),
            bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: text),
            bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: text),
            bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
            labelLarge: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),

      iconTheme: IconThemeData(color: muted, size: 18),
      primaryIconTheme: IconThemeData(color: text),

      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        hintStyle: TextStyle(color: subtle, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface3 : AppColors.lightText,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: isDark ? AppColors.darkText : Colors.white,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          isDark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.18),
        ),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(8),
      ),

      extensions: <ThemeExtension<dynamic>>[
        AppPalette(
          bg: bg,
          surface: surface,
          surface2: surface2,
          surface3: surface3,
          border: border,
          borderSoft: borderSoft,
          text: text,
          muted: muted,
          subtle: subtle,
          primary: primary,
          primaryHover: hoverColor,
          codeBg: codeBg,
          codeText: codeText,
          shadow: shadow,
          success: AppColors.success,
          danger: AppColors.danger,
          warning: AppColors.warning,
          info: AppColors.info,
        ),
      ],
    );
  }
}

/// Extensión semántica de colores accesible desde cualquier widget.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderSoft;
  final Color text;
  final Color muted;
  final Color subtle;
  final Color primary;
  final Color primaryHover;
  final Color codeBg;
  final Color codeText;
  final Color shadow;
  final Color success;
  final Color danger;
  final Color warning;
  final Color info;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.primary,
    required this.primaryHover,
    required this.codeBg,
    required this.codeText,
    required this.shadow,
    required this.success,
    required this.danger,
    required this.warning,
    required this.info,
  });

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;

  /// Sombra suave estilo Anthropic (para composer, cards flotantes).
  List<BoxShadow> get softShadow => <BoxShadow>[
        BoxShadow(
          color: shadow,
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ];

  /// Sombra mínima para botones / chips elevados.
  List<BoxShadow> get subtleShadow => <BoxShadow>[
        BoxShadow(
          color: shadow,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Sombra elevada de dos capas (popovers, menús, modales).
  /// Estilo Anthropic: una capa muy difusa para halo + una nítida pegada
  /// para definir el borde superior.
  List<BoxShadow> get elevatedShadow => <BoxShadow>[
        BoxShadow(
          color: shadow.withValues(alpha: 0.55),
          blurRadius: 36,
          spreadRadius: -6,
          offset: const Offset(0, 18),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: 0.4),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  /// Halo sutil para inputs y áreas con foco interno.
  List<BoxShadow> get insetGlow => <BoxShadow>[
        BoxShadow(
          color: primary.withValues(alpha: 0.08),
          blurRadius: 20,
          spreadRadius: -4,
        ),
      ];

  /// Acceso al sistema de elevación de 5 niveles.
  ///
  /// Uso:
  ///   decoration: BoxDecoration(
  ///     ...,
  ///     boxShadow: p.elevation(3),  // para popovers y dropdowns.
  ///   )
  List<BoxShadow> elevation(int level) {
    switch (level) {
      case 0:
        return AppElevation.level0();
      case 1:
        return AppElevation.level1(shadow);
      case 2:
        return AppElevation.level2(shadow);
      case 3:
        return AppElevation.level3(shadow);
      case 4:
        return AppElevation.level4(shadow);
      case 5:
        return AppElevation.level5(shadow);
      default:
        return AppElevation.level2(shadow);
    }
  }

  /// Gradiente sutil para superficies destacadas (cards primarias,
  /// header del onboarding). Aporta profundidad sin saturar.
  LinearGradient get surfaceGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surface,
          Color.lerp(surface, primary, 0.025)!,
        ],
      );

  /// Gradiente intenso para botones y elementos protagonistas.
  LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary,
          primaryHover,
        ],
      );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderSoft,
    Color? text,
    Color? muted,
    Color? subtle,
    Color? primary,
    Color? primaryHover,
    Color? codeBg,
    Color? codeText,
    Color? shadow,
    Color? success,
    Color? danger,
    Color? warning,
    Color? info,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      codeBg: codeBg ?? this.codeBg,
      codeText: codeText ?? this.codeText,
      shadow: shadow ?? this.shadow,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
