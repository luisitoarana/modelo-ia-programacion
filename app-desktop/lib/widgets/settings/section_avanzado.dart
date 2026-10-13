import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme.dart';
import 'settings_common.dart';

/// Sección "Avanzado" del settings:
///   - Selector de proveedor de IA (auto / modelo propio / APIs externas).
///   - URL efectiva del backend.
///   - Estado del modelo propio (disponible o motivo).
class AvanzadoSection extends StatefulWidget {
  final SettingsProvider settings;
  final Map<String, dynamic>? estadoModelo;
  const AvanzadoSection({
    super.key,
    required this.settings,
    this.estadoModelo,
  });

  @override
  State<AvanzadoSection> createState() => _AvanzadoSectionState();
}

class _AvanzadoSectionState extends State<AvanzadoSection> {
  List<ProveedorIA>? _proveedores;
  String? _errorProveedores;

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
  }

  Future<void> _cargarProveedores() async {
    try {
      final api = context.read<AuthProvider>().api;
      final lista = await api.listarProveedores();
      if (mounted) setState(() => _proveedores = lista);
    } catch (e) {
      if (mounted) setState(() => _errorProveedores = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsTitulo(
          titulo: 'Avanzado',
          descripcion:
              'Opciones que rara vez necesitan cambiar. Solo modifica si sabes lo que haces.',
        ),
        const SettingsSubtitulo(titulo: 'Motor de respuesta'),
        _selectorProveedor(p),
        const SizedBox(height: 14),
        const SettingsSubtitulo(titulo: 'Conexión al backend'),
        _cardBackend(p),
        const SizedBox(height: 14),
        const SettingsSubtitulo(titulo: 'Estado del modelo propio'),
        _cardEstadoModelo(p),
      ],
    );
  }

  Widget _selectorProveedor(AppPalette p) {
    if (_errorProveedores != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No se pudieron cargar los proveedores: $_errorProveedores',
                style: TextStyle(fontSize: 12, color: p.text, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    if (_proveedores == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: p.primary),
            ),
            const SizedBox(width: 10),
            Text('Cargando proveedores…',
                style: TextStyle(fontSize: 12, color: p.subtle)),
          ],
        ),
      );
    }

    final activo = widget.settings.proveedor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Elige qué motor responde tus mensajes. "Automático" usa tu modelo propio cuando está entrenado y cae a una API externa si no.',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
          ),
        ),
        for (final prov in _proveedores!)
          _ProveedorTile(
            proveedor: prov,
            seleccionado: prov.id == activo,
            onTap: prov.disponible
                ? () => widget.settings.setProveedor(prov.id)
                : null,
          ),
      ],
    );
  }

  Widget _cardBackend(AppPalette p) {
    return Container(
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
            widget.settings.apiUrlEfectiva,
            style: TextStyle(
              fontSize: 12.5,
              color: p.text,
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardEstadoModelo(AppPalette p) {
    final estado = widget.estadoModelo;
    if (estado == null) {
      return Text('Verificando…',
          style: TextStyle(fontSize: 12.5, color: p.subtle));
    }
    final disponible = estado['disponible'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderSoft),
      ),
      child: Row(
        children: [
          Icon(
            disponible ? Icons.check_circle : Icons.hourglass_empty,
            size: 18,
            color: disponible ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              disponible
                  ? 'Modelo activo'
                  : (estado['motivo']?.toString() ?? 'Modelo no entrenado'),
              style: TextStyle(fontSize: 13, color: p.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta clickable con un proveedor. Muestra icono según tipo,
/// nombre + descripción, badge de estado y check si es el activo.
class _ProveedorTile extends StatefulWidget {
  final ProveedorIA proveedor;
  final bool seleccionado;
  final VoidCallback? onTap;
  const _ProveedorTile({
    required this.proveedor,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  State<_ProveedorTile> createState() => _ProveedorTileState();
}

class _ProveedorTileState extends State<_ProveedorTile> {
  bool _hover = false;

  IconData _iconoTipo() {
    switch (widget.proveedor.tipo) {
      case 'propio':
        return Icons.psychology_outlined;
      case 'auto':
        return Icons.auto_awesome;
      case 'api':
      default:
        return Icons.cloud_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final habilitado = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = habilitado),
      onExit: (_) => setState(() => _hover = false),
      cursor: habilitado
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.seleccionado
                  ? p.primary.withValues(alpha: 0.08)
                  : (_hover ? p.surface2 : p.surface),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.seleccionado
                    ? p.primary
                    : p.borderSoft,
                width: widget.seleccionado ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.seleccionado
                        ? p.primary.withValues(alpha: 0.15)
                        : p.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconoTipo(),
                    size: 16,
                    color: widget.seleccionado ? p.primary : p.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.proveedor.nombre,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: habilitado ? p.text : p.subtle,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!widget.proveedor.disponible)
                            const SettingsBadgeEstado(
                              label: 'no disponible',
                              color: AppColors.warning,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.proveedor.descripcion,
                        style: TextStyle(
                          fontSize: 12,
                          color: p.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.seleccionado) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: p.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
