import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// Selector multi-IA estilo Anthropic / Linear.
///
/// Diseño:
///   - Pill horizontal compacto en el composer.
///   - Al abrirse, popover anclado con sombra de dos capas + escala-fade.
///   - Items con icono coloreado por tipo, descripción de una línea.
///   - Item activo con halo terracota y check mark.
///   - Items deshabilitados visibles pero atenuados, con la razón.
///
/// La elección se persiste en `SettingsProvider.proveedor`.
class SelectorProveedor extends StatefulWidget {
  final ApiClient api;
  const SelectorProveedor({super.key, required this.api});

  @override
  State<SelectorProveedor> createState() => _SelectorProveedorState();
}

class _SelectorProveedorState extends State<SelectorProveedor> {
  List<ProveedorIA> _proveedores = const [];
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.api.listarProveedores();
      if (mounted) setState(() => _proveedores = lista);
    } catch (_) {
      if (mounted) {
        setState(() {
          _proveedores = const [
            ProveedorIA(
              id: 'auto', nombre: 'Asistente Python IA',
              descripcion: 'Selección automática según los motores configurados',
              tipo: 'auto', disponible: true,
            ),
          ];
        });
      }
    }
  }

  // ─── Visual helpers ────────────────────────────────────────────

  IconData _iconoTipo(String tipo) {
    if (tipo == 'auto') return Icons.bolt_rounded;
    if (tipo == 'propio' || tipo == 'local') return Icons.auto_awesome_rounded;
    return Icons.cloud_outlined;
  }

  Color _colorTipo(String tipo, AppPalette p) {
    if (tipo == 'auto') return AppColors.accent;
    if (tipo == 'propio' || tipo == 'local') return p.primary;
    return AppColors.info;
  }

  // ─── Popover ───────────────────────────────────────────────────

  Future<void> _abrirMenu(BuildContext ctxAnchor, String actualId) async {
    final overlay = Overlay.of(ctxAnchor).context.findRenderObject() as RenderBox?;
    final box = ctxAnchor.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;

    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
    final anchorTop = pos.dy;
    final menuHeight = (_proveedores.length * 64 + 28).clamp(80, 360).toDouble();
    final left = pos.dx;
    final top = anchorTop - menuHeight - 10;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (popCtx) => _PopoverProveedores(
        provs: _proveedores,
        actualId: actualId,
        leftPx: left,
        topPx: top.clamp(8.0, double.infinity),
        anchorWidth: box.size.width,
        iconoTipo: _iconoTipo,
        colorTipo: _colorTipo,
        onPick: (id) {
          context.read<SettingsProvider>().setProveedor(id);
          entry?.remove();
        },
        onDismiss: () => entry?.remove(),
      ),
    );
    Overlay.of(ctxAnchor).insert(entry);
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final actualId = context.watch<SettingsProvider>().proveedor;
    final actual = _proveedores.firstWhere(
      (e) => e.id == actualId,
      orElse: () => _proveedores.isNotEmpty
          ? _proveedores.first
          : const ProveedorIA(
              id: 'auto', nombre: 'Asistente Python IA',
              descripcion: '', tipo: 'propio', disponible: true,
            ),
    );

    final hayVarios = _proveedores.length > 1;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: hayVarios ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Tooltip(
        message: actual.descripcion.isNotEmpty
            ? actual.descripcion
            : 'Motor neural de la tesis (100% offline · GPU CUDA + Andamiaje)',
        child: Builder(
          builder: (innerCtx) => GestureDetector(
            onTap: hayVarios ? () => _abrirMenu(innerCtx, actualId) : null,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: _hover && hayVarios ? p.surface2 : p.surface,
                border: Border.all(
                  color: _hover && hayVarios ? p.border : p.borderSoft,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconoTipo(actual.tipo),
                    size: 13,
                    color: _colorTipo(actual.tipo, p),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    actual.nombre,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (hayVarios) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _hover ? -0.5 : 0,
                      duration: AppMotion.medium,
                      curve: AppMotion.standard,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: p.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Popover separado para evitar reconstruir el menú en cada hover
// ════════════════════════════════════════════════════════════════════

class _PopoverProveedores extends StatefulWidget {
  final List<ProveedorIA> provs;
  final String actualId;
  final double leftPx;
  final double topPx;
  final double anchorWidth;
  final IconData Function(String) iconoTipo;
  final Color Function(String, AppPalette) colorTipo;
  final void Function(String) onPick;
  final VoidCallback onDismiss;

  const _PopoverProveedores({
    required this.provs,
    required this.actualId,
    required this.leftPx,
    required this.topPx,
    required this.anchorWidth,
    required this.iconoTipo,
    required this.colorTipo,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  State<_PopoverProveedores> createState() => _PopoverProveedoresState();
}

class _PopoverProveedoresState extends State<_PopoverProveedores>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.medium)
      ..forward();
    _scale = Tween(begin: 0.96, end: 1.0)
        .chain(CurveTween(curve: AppMotion.emphasized))
        .animate(_ctrl);
    _opacity = Tween(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: AppMotion.standard))
        .animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const width = 304.0;

    return Stack(
      children: [
        // Capa de cierre por tap fuera
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned(
          left: widget.leftPx,
          top: widget.topPx,
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.bottomLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.border),
                    boxShadow: p.elevatedShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Encabezado discreto
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.x4, AppSpacing.x3, AppSpacing.x4, AppSpacing.x2,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Elegir IA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: p.muted,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'por turno',
                              style: TextStyle(fontSize: 10, color: p.subtle),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      ...widget.provs.map((prov) => _ItemProv(
                            prov: prov,
                            esActual: prov.id == widget.actualId,
                            iconoTipo: widget.iconoTipo,
                            colorTipo: widget.colorTipo,
                            onTap: prov.disponible
                                ? () => widget.onPick(prov.id)
                                : null,
                          )),
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x3,
                          vertical: AppSpacing.x2,
                        ),
                        color: p.borderSoft,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.x4, 0, AppSpacing.x4, AppSpacing.x3,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 11, color: p.subtle),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Modelo propio = tu IA. APIs = andamio temporal.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: p.subtle,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _ItemProv extends StatefulWidget {
  final ProveedorIA prov;
  final bool esActual;
  final IconData Function(String) iconoTipo;
  final Color Function(String, AppPalette) colorTipo;
  final VoidCallback? onTap;

  const _ItemProv({
    required this.prov,
    required this.esActual,
    required this.iconoTipo,
    required this.colorTipo,
    required this.onTap,
  });

  @override
  State<_ItemProv> createState() => _ItemProvState();
}

class _ItemProvState extends State<_ItemProv> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final colorAccento = widget.colorTipo(widget.prov.tipo, p);
    final disabled = widget.onTap == null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: widget.esActual
                ? p.primary.withValues(alpha: 0.08)
                : _hover && !disabled
                    ? p.surface2.withValues(alpha: 0.55)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Opacity(
            opacity: disabled ? 0.45 : 1.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: widget.esActual
                        ? colorAccento.withValues(alpha: 0.2)
                        : colorAccento.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    widget.iconoTipo(widget.prov.tipo),
                    size: 15,
                    color: colorAccento,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.prov.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                            ),
                          ),
                          if (widget.esActual) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_rounded, size: 13, color: p.primary),
                          ],
                          if (disabled && !widget.esActual) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'sin entrenar',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (widget.prov.descripcion.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.prov.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: p.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
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
}
