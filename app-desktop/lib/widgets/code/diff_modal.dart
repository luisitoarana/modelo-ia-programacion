import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

enum TipoLineaDiff { sinCambio, agregada, eliminada }

class LineaDiff {
  final TipoLineaDiff tipo;
  final String texto;
  final int? numOriginal;
  final int? numModificado;

  LineaDiff({
    required this.tipo,
    required this.texto,
    this.numOriginal,
    this.numModificado,
  });
}

/// Modal interactivo estilo Cursor / GitHub para comparar código "Antes vs. Después".
class DiffModal extends StatelessWidget {
  final String codigoOriginal;
  final String codigoNuevo;
  final String nombreArchivo;
  final ValueChanged<String>? onAplicar;

  const DiffModal({
    super.key,
    required this.codigoOriginal,
    required this.codigoNuevo,
    this.nombreArchivo = 'código',
    this.onAplicar,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required String codigoOriginal,
    required String codigoNuevo,
    String nombreArchivo = 'código',
    ValueChanged<String>? onAplicar,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        child: DiffModal(
          codigoOriginal: codigoOriginal,
          codigoNuevo: codigoNuevo,
          nombreArchivo: nombreArchivo,
          onAplicar: onAplicar,
        ),
      ),
    );
  }

  List<LineaDiff> _calcularDiff(String orig, String nuevo) {
    final lineasOrig = orig.split('\n');
    final lineasNuevo = nuevo.split('\n');
    final diff = <LineaDiff>[];

    // Algoritmo de diff por líneas
    int i = 0;
    int j = 0;
    int numO = 1;
    int numN = 1;

    while (i < lineasOrig.length || j < lineasNuevo.length) {
      if (i < lineasOrig.length && j < lineasNuevo.length) {
        if (lineasOrig[i] == lineasNuevo[j]) {
          diff.add(LineaDiff(
            tipo: TipoLineaDiff.sinCambio,
            texto: lineasOrig[i],
            numOriginal: numO++,
            numModificado: numN++,
          ));
          i++;
          j++;
        } else {
          // Detectar cambio
          diff.add(LineaDiff(
            tipo: TipoLineaDiff.eliminada,
            texto: lineasOrig[i],
            numOriginal: numO++,
            numModificado: null,
          ));
          diff.add(LineaDiff(
            tipo: TipoLineaDiff.agregada,
            texto: lineasNuevo[j],
            numOriginal: null,
            numModificado: numN++,
          ));
          i++;
          j++;
        }
      } else if (i < lineasOrig.length) {
        diff.add(LineaDiff(
          tipo: TipoLineaDiff.eliminada,
          texto: lineasOrig[i],
          numOriginal: numO++,
          numModificado: null,
        ));
        i++;
      } else if (j < lineasNuevo.length) {
        diff.add(LineaDiff(
          tipo: TipoLineaDiff.agregada,
          texto: lineasNuevo[j],
          numOriginal: null,
          numModificado: numN++,
        ));
        j++;
      }
    }
    return diff;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final lineas = _calcularDiff(codigoOriginal, codigoNuevo);
    final agregadas = lineas.where((l) => l.tipo == TipoLineaDiff.agregada).length;
    final eliminadas = lineas.where((l) => l.tipo == TipoLineaDiff.eliminada).length;

    return Container(
      constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 750),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(Icons.difference_rounded, size: 18, color: p.primary),
                const SizedBox(width: 8),
                Text(
                  'Comparación de código · $nombreArchivo',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(width: 12),
                // Chips de resumen
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '+$agregadas',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '-$eliminadas',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                // Botón copiar
                Tooltip(
                  message: 'Copiar código nuevo',
                  child: IconButton(
                    icon: Icon(Icons.copy_rounded, size: 16, color: p.muted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: codigoNuevo));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Código nuevo copiado al portapapeles'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                // Cerrar
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: p.muted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // ── Cuerpo: Lista de líneas del diff ────────────────────
          Expanded(
            child: Container(
              color: p.codeBg,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: lineas.length,
                itemBuilder: (ctx, idx) {
                  final l = lineas[idx];
                  Color? fondo;
                  Color? borde;
                  Color colorTexto = p.codeText;
                  String prefijo = ' ';

                  if (l.tipo == TipoLineaDiff.agregada) {
                    fondo = AppColors.success.withValues(alpha: 0.14);
                    borde = AppColors.success.withValues(alpha: 0.5);
                    colorTexto = AppColors.success;
                    prefijo = '+';
                  } else if (l.tipo == TipoLineaDiff.eliminada) {
                    fondo = AppColors.danger.withValues(alpha: 0.14);
                    borde = AppColors.danger.withValues(alpha: 0.5);
                    colorTexto = AppColors.danger;
                    prefijo = '-';
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: fondo,
                      border: borde != null
                          ? Border(left: BorderSide(color: borde, width: 3))
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Números de línea
                        SizedBox(
                          width: 32,
                          child: Text(
                            l.numOriginal != null ? '${l.numOriginal}' : '',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: p.subtle.withValues(alpha: 0.6),
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 32,
                          child: Text(
                            l.numModificado != null ? '${l.numModificado}' : '',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: p.subtle.withValues(alpha: 0.6),
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Signo + / -
                        SizedBox(
                          width: 14,
                          child: Text(
                            prefijo,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorTexto,
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback,
                            ),
                          ),
                        ),
                        // Texto de código
                        Expanded(
                          child: SelectableText(
                            l.texto,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: colorTexto,
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Barra inferior de acciones ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
              border: Border(top: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Text(
                  'Rojo = código previo · Verde = propuesta de la IA',
                  style: TextStyle(fontSize: 11.5, color: p.subtle),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
                if (onAplicar != null) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Aplicar cambios al editor'),
                    onPressed: () {
                      onAplicar!(codigoNuevo);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
