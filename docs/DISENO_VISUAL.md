# Diseño Visual del Sistema

> Especificación del sistema de diseño del producto: tokens visuales,
> componentes reutilizables, principios de interacción y mejoras
> aplicadas en la sesión de junio 2026.
>
> Este documento sirve como referencia para el capítulo de Interfaz de
> Usuario del documentación y como guía técnica para mantener consistencia
> visual al añadir nuevas pantallas.

---

## 1. Filosofía de diseño

El producto adopta la filosofía visual de Anthropic Claude, Linear y
Stripe:

- **Calidez sobre tecnicidad**: paletas off-white y terracota en lugar
 de azules fríos.
- **Tipografía como protagonista**: serif para titulares, sans para UI,
 monospace para código.
- **Microinteracciones invisibles**: animaciones rápidas (110–320 ms)
 con curvas suaves que el usuario siente pero no nota.
- **Espacio generoso**: espaciado a múltiplos de 4 px, márgenes
 ampliados para reducir carga cognitiva.
- **Profundidad sin ruido**: sombras en capas (humo difuso + sombra
 pegada) en lugar de sombras planas duras.

---

## 2. Tokens de diseño

### 2.1 Sistema de espaciado (4 px)

```
x1 = 4 px x6 = 24 px
x2 = 8 px x8 = 32 px
x3 = 12 px x10 = 40 px
x4 = 16 px x12 = 48 px
x5 = 20 px
```

Implementado en `AppSpacing` (`app-desktop/lib/theme.dart`).

### 2.2 Sistema de radios

```
sm = 6 px (chips pequeños, inputs)
md = 10 px (botones, cards)
lg = 14 px (modales, popovers)
xl = 20 px (login card, cards destacadas)
pill = 999 px (chips redondeados, avatares)
```

Implementado en `AppRadius` (nuevo).

### 2.3 Sistema de elevación de 5 niveles

Cada nivel representa una intención semántica. Implementado en
`AppElevation` y accesible como `palette.elevation(N)`.

| Nivel | Uso |
|---|---|
| 0 | Superficie plana, sin sombra. Fondo de la app. |
| 1 | Chips, hover de botones outline. |
| 2 | Cards y botones primarios en reposo. |
| 3 | Dropdowns, popovers, tooltips. |
| 4 | Modales, bottom sheets, command palette. |
| 5 | Drag preview (efecto "flotando"). |

Cada nivel combina dos sombras: una capa "humo difuso" (blur grande,
spread negativo) más una capa "pegada" (blur corto) para definir el
contorno superior. Estilo Anthropic / Linear.

### 2.4 Curvas de animación

Implementado en `AppMotion`:

```
standard = Cubic(0.16, 1, 0.3, 1) // ease-out suave
emphasized = Cubic(0.2, 0, 0, 1) // entradas de modales

fast = 110 ms // hovers, tooltips
medium = 220 ms // dropdowns, paneles
slow = 320 ms // transiciones entre vistas
```

### 2.5 Paleta de colores

Cinco paletas seleccionables por el usuario desde Configuración:

- **terracota** (default — inspirada en Anthropic).
- **academico** (azul profesional).
- **bosque** (verde natural).
- **purpura** (creativo elegante).
- **mono** (minimalista solo grises).

Cada paleta define 15+ colores semánticos accesibles desde `AppPalette`.
Implementado en `Paletas` (`app-desktop/lib/theme.dart`).

### 2.6 Tipografía

| Fuente | Uso |
|---|---|
| Inter / Segoe UI / SF Pro Display | UI general (sans serif) |
| Tiempos Text / Source Serif Pro / Georgia | Titulares (serif) |
| JetBrains Mono / Fira Code / Consolas | Código (monospace) |

Implementado en `AppFonts`.

### 2.7 Gradientes semánticos

| Gradiente | Uso |
|---|---|
| `palette.surfaceGradient` | Cards destacadas (sutil — del surface al primary al 2.5 %). |
| `palette.primaryGradient` | Botones protagonistas, logo (primary → primaryHover). |

Inspirado en Stripe y Linear.

---

## 3. Componentes reutilizables (V2)

### 3.1 Skeleton loaders (`widgets/skeleton.dart`)

Loaders elegantes con efecto shimmer diagonal. Cuatro variantes:

- `Skeleton.text(lines: N)` — múltiples líneas con anchos variados;
 la última siempre más corta.
- `Skeleton.circle(size: N)` — avatares.
- `Skeleton.card(width, height)` — cards y bloques rectangulares con
 radio mayor.
- `Skeleton.block(width, height)` — bloques genéricos.

Más composiciones de alto nivel: `SkeletonChatMessage` (avatar + 3
líneas) y `SkeletonConversacion` (tile de la sidebar).

**Estilo**: gradiente diagonal que se desplaza con un ciclo de
1.4 segundos. Sustituye `CircularProgressIndicator` cuando se carga
contenido estructurado, mejorando la UX al insinuar la forma del
contenido por venir.

### 3.2 Empty states (`widgets/empty_state.dart`)

Estados vacíos con ilustración ambiental y acciones primarias /
secundarias. Componentes:

- `EmptyState(icono, titulo, mensaje, accion, accionSecundaria)` — el
 componente completo.
- `EmptyStateAction(label, icono?, onTap)` — modelo de acción.

**Ilustración central**: tres anillos concéntricos que se expanden y
desvanecen continuamente, con un disco coloreado en el centro y el
icono semántico. Animación con desfase de 1/3 entre anillos para crear
un efecto de "pulso" hipnotizante sin ser distractor.

**Animación de entrada**: fade + translate Y 12 px en 600 ms.

### 3.3 Pulse dot (`widgets/pulse_dot.dart`)

Indicador animado de "en vivo" para estados dinámicos. Dos
componentes:

- `PulseDot(color, size, activo, tooltip)` — punto solo.
- `PulseStatus(label, color, activo)` — punto + texto, útil para
 "Conectado", "Pensando…", "Streaming".

**Comportamiento**: el halo se expande continuamente con la fase
saliendo del punto central. Cuando `activo: false`, el punto queda
estático sin halo.

Aplicable a:
- Estado del modelo propio (cargado / no cargado / cargando).
- Streaming en curso.
- Conexión al backend.
- Indicador de batch background corriendo.

### 3.4 Ambient background (`widgets/ambient_background.dart`)

Fondo dinámico con orbs blureados que flotan muy lentamente. Estilo
Stripe / Linear / Vercel. Dos variantes:

- `AmbientBackground(orbCount, intensity)` — animado con ciclo de
 40 segundos. Configurable.
- `AmbientBackgroundStatic(intensity)` — versión sin animación para
 áreas donde el usuario lee o trabaja.

**Implementación**: `CustomPainter` con `RadialGradient` por orb +
`MaskFilter.blur(32)`. Tres tonalidades cercanas al primary para
mezcla armónica. `RepaintBoundary` para que el fondo no fuerce
repaints de la jerarquía superior.

---

## 4. Mejoras aplicadas en esta sesión

### 4.1 LoginScreen

| Antes | Después |
|---|---|
| Gradiente radial estático + glow circular | `AmbientBackground` con orbs flotantes |
| Logo: color plano + sombra simple | Logo: `primaryGradient` + sombra más sofisticada |
| Card: 2 sombras planas | Card: `elevation(4)` + halo terracota + `surfaceGradient` |
| Botón Entrar: color plano + sombra | Botón: `primaryGradient` + sombra modulada por hover + splash veil claro |
| Radios 10/18 px ad-hoc | Radios desde `AppRadius` (consistencia) |
| Curvas y duraciones inline | Curvas desde `AppMotion` (consistencia) |

### 4.2 Sistema de elevación

Antes: cada widget definía sus propias `BoxShadow` ad-hoc, generando
inconsistencias visuales. Ahora: cinco niveles semánticos accesibles
con `palette.elevation(N)`. Esto garantiza que dos popovers se vean
exactamente igual aunque vivan en pantallas distintas.

### 4.3 Gradientes semánticos

Antes: gradientes manuales inline (`LinearGradient(colors: [p.primary,...])`).
Ahora: dos getters `surfaceGradient` y `primaryGradient` en
`AppPalette` para que cualquier widget pueda aplicarlos sin reescribir
lógica.

---

## 5. Cómo usar los componentes nuevos

### 5.1 Reemplazar un estado vacío trivial

Antes:

```dart
if (lista.isEmpty)
 Center(child: Text('No hay nada todavía'));
```

Después:

```dart
if (lista.isEmpty)
 EmptyState(
 icono: Icons.chat_bubble_outline,
 titulo: 'Aún no hay conversaciones',
 mensaje: 'Empieza preguntándole lo que quieras al asistente.',
 accion: EmptyStateAction(
 label: 'Nueva conversación',
 icono: Icons.add,
 onTap: () => context.read<ChatProvider>().nueva(),
 ),
 );
```

### 5.2 Reemplazar un CircularProgressIndicator de listado

Antes:

```dart
if (cargandoConvs)
 const Center(child: CircularProgressIndicator());
```

Después:

```dart
if (cargandoConvs)
 ListView(
 children: List.generate(6, (_) => const SkeletonConversacion()),
 );
```

### 5.3 Indicar estado en vivo

```dart
PulseStatus(
 label: cargando ? 'Pensando…' : 'Conectado',
 color: cargando ? p.warning : p.success,
 activo: true,
)
```

### 5.4 Capas de elevación correctas

```dart
// Popover (nivel 3):
Container(
 decoration: BoxDecoration(
 color: p.surface,
 borderRadius: BorderRadius.circular(AppRadius.md),
 boxShadow: p.elevation(3),
 ),
 child: contenido,
)

// Modal (nivel 4):
Container(
 decoration: BoxDecoration(
 color: p.surface,
 borderRadius: BorderRadius.circular(AppRadius.lg),
 boxShadow: p.elevation(4),
 ),
 child: contenido,
)
```

---

## 6. Criterios para nuevas pantallas

Antes de añadir una pantalla nueva al producto, validar:

1. **Tokens en lugar de literales**: usar `AppSpacing.x4` en lugar de
 `16`, `AppRadius.md` en lugar de `10`.
2. **Elevación semántica**: usar `palette.elevation(N)` en lugar de
 `BoxShadow` inline.
3. **Curvas y duraciones consistentes**: importar de `AppMotion`.
4. **Componentes reutilizables**: revisar si `Skeleton`, `EmptyState`,
 `PulseDot` cubren la necesidad antes de implementar a mano.
5. **Idioma**: español neutro. Sin jerga técnica innecesaria.
6. **Responsividad**: mínimo soportar 1280×800. Cuando se pueda,
 1024×768. Los layouts deben colapsar gradualmente.
7. **Modo claro y modo oscuro**: ambos siempre legibles. Probar con la
 paleta `mono` (grises) que es la menos perdonable.
8. **Estados de carga, vacío, error**: una pantalla profesional define
 los cuatro estados (cargando, vacío, con contenido, con error). No
 solo el camino feliz.

---

## 7. Inventario de widgets actuales del app-desktop

### Widgets originales (V1)

| Widget | Función |
|---|---|
| `Sidebar` | Navegación principal colapsable con búsqueda y grupos por fecha. |
| `ChatView` | Vista de chat con bubbles, copy, feedback. |
| `CodeView` | Editor de código con syntax highlighting. |
| `ExplicarView` | Vista de explicación de código. |
| `ProyectoView` | Explorador de archivos. |
| `TerminalView` | Terminal embebida. |
| `CommandPalette` | Cmd+K. |
| `AtajosOverlay` | Cmd+/. |
| `OnboardingDialog` | Tutorial primera vez. |
| `ConfirmDialog` | Confirmación con tono y icono. |
| `ArtifactsPanel` | Panel de artefactos. |
| `MicButton`, `ModoVozContinua` | Dictado por voz. |
| `SyntaxHighlighter` | Highlighter custom. |
| `FuentesMensaje` | Fuentes de respuesta (RAG). |
| `SelectorProveedor` | Selector Gemini / DeepSeek / modelo propio. |

### Widgets nuevos (V2, esta sesión)

| Widget | Función |
|---|---|
| `Skeleton` | Loaders con shimmer (text / circle / card / block + composiciones). |
| `EmptyState` | Estados vacíos con ilustración ambiental y acciones. |
| `PulseDot`, `PulseStatus` | Indicador animado de "en vivo". |
| `AmbientBackground`, `AmbientBackgroundStatic` | Fondo con orbs blureados flotantes. |
| `GlassPanel` | Panel con efecto cristal esmerilado (frosted glass + blur). |
| `MetricChip` | Chip de métrica para dashboards (label + valor grande + tendencia). |
| `ScoreBar`, `ScoreBarSet` | Barras 0-10 para visualizar los seis scores del sistema multi-criterio. |

### Aplicaciones concretas en pantallas existentes

| Pantalla / componente | Mejora aplicada |
|---|---|
| `LoginScreen` | `AmbientBackground` + `primaryGradient` en logo y botón + `elevation(4)` en card. |
| `Sidebar` (lista de conversaciones cargando) | `SkeletonConversacion × 5` con grupo "Hoy" + "Esta semana" simulados. |
| `Sidebar` (sin conversaciones) | `EmptyState` con icono `forum_outlined`, mensaje pedagógico y acción "Nueva conversación". |
| `Sidebar` (footer del usuario) | Avatar con `primaryGradient` + `PulseDot` micro-pegado abajo-derecha como indicador de conexión. |
| `ChatView` (cargando mensajes al cambiar de conversación) | 4 `SkeletonChatMessage` alternando esUsuario en lugar de spinner. |
| `ChatProvider` | Flags nuevos `cargandoConversaciones`, `cargandoMensajes`, `conversacionesCargadasAlgunaVez` para distinguir "cargando" de "vacío". |

---

## 8. Próximas mejoras planeadas

Para futuras sesiones de diseño:

1. **Aplicar `EmptyState` a vistas restantes**: ExplicarView,
 CodeView, RagScreen, ProyectoView (cuando estén vacías).
2. **`AmbientBackgroundStatic` en RagScreen y SettingsScreen** para
 añadir profundidad sin distraer.
3. **`MetricChip` y `ScoreBar` integrados en panel del investigador**
 cuando los reward models propios produzcan scores reales.
4. **Animación de envío de mensaje** — el bubble del usuario se
 "lanza" hacia arriba con un slide + fade.
5. **Animación de streaming** — efecto de cursor parpadeante al final
 del texto mientras llegan tokens.
6. **Tour interactivo de primera vez** — overlay con tooltips
 secuenciales que explican cada zona de la UI.
7. **Drag-and-drop visual** para reordenar tabs del editor.
8. **Modo de presentación** para presentación del proyecto (oculta sidebar y
 composer, deja solo la conversación con UI minimalista).
9. **Modo enfoque** que oscurece todo excepto el bubble que se está
 leyendo.
10. **Conversación exportable como PDF estilizado** con la marca del
 sistema (logo, paleta, tipografía serif).

### Mejoras V2 ya implementadas (junio 2026)

- ✓ `Skeleton` con shimmer (4 variantes + 2 composiciones).
- ✓ `EmptyState` con ilustración animada (3 anillos concéntricos).
- ✓ `PulseDot`, `PulseStatus` para estados en vivo.
- ✓ `AmbientBackground` con orbs flotantes (40 s cycle).
- ✓ `GlassPanel` con `BackdropFilter.blur`.
- ✓ `MetricChip` para dashboards.
- ✓ `ScoreBar`, `ScoreBarSet` para los 6 reward models.
- ✓ Sistema de elevación de 5 niveles (`palette.elevation(N)`).
- ✓ Gradientes semánticos (`surfaceGradient`, `primaryGradient`).
- ✓ Sistema de radios (`AppRadius`: sm/md/lg/xl/pill).
- ✓ Aplicación en LoginScreen, Sidebar (cargando + vacío + footer),
 ChatView (cargando mensajes), ChatProvider (flags de carga).

---

## 9. Referencias visuales

- Anthropic Claude.ai — paleta cálida, jerarquía tipográfica.
- Linear — sistema de elevación, microinteracciones.
- Stripe — gradientes ambientales, animaciones lentas de fondo.
- Vercel — empty states ilustrados, skeleton loaders.
- Notion — densidad visual equilibrada.
- Cursor — modo IDE integrado con chat lateral.

Estas referencias se incorporan en la metodología pero el producto
desarrolla su propia identidad visual basada en la paleta terracota y
el contexto pedagógico hispanohablante.
