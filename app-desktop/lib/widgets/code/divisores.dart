import 'package:flutter/material.dart';

import '../../theme.dart';

/// Divisor horizontal arrastrable (cambia el alto del panel inferior).
///
/// `delta` positivo en el callback = el usuario arrastró hacia abajo.
/// El padre decide cómo interpretar el signo (típicamente:
/// `alto -= delta` para que arrastrar abajo achique el panel inferior).
class DivisorHorizontal extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const DivisorHorizontal({super.key, required this.onDrag});

  @override
  State<DivisorHorizontal> createState() => _DivisorHorizontalState();
}

class _DivisorHorizontalState extends State<DivisorHorizontal> {
  bool _hover = false;
  bool _arrastrando = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _arrastrando = true),
        onVerticalDragEnd: (_) => setState(() => _arrastrando = false),
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 4,
          color: (_hover || _arrastrando)
              ? p.primary.withValues(alpha: 0.5)
              : p.borderSoft,
        ),
      ),
    );
  }
}

/// Divisor vertical arrastrable (cambia el ancho del explorador).
///
/// `delta` positivo = arrastró hacia la derecha.
class DivisorVertical extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const DivisorVertical({super.key, required this.onDrag});

  @override
  State<DivisorVertical> createState() => _DivisorVerticalState();
}

class _DivisorVerticalState extends State<DivisorVertical> {
  bool _hover = false;
  bool _arrastrando = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _arrastrando = true),
        onHorizontalDragEnd: (_) => setState(() => _arrastrando = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 4,
          color: (_hover || _arrastrando)
              ? p.primary.withValues(alpha: 0.5)
              : p.borderSoft,
        ),
      ),
    );
  }
}
