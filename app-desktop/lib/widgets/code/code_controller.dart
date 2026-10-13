import 'package:flutter/material.dart';

import '../../theme.dart';
import '../syntax_highlighter.dart';

/// `TextEditingController` que aplica syntax highlight INLINE vía
/// `buildTextSpan`. Esto evita overlays desalineados que causaban el
/// bug del "texto rayado" en la versión anterior.
class CodeController extends TextEditingController {
  String lenguaje;
  AppPalette palette;

  CodeController({
    required String text,
    required this.lenguaje,
    required this.palette,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }
    final spans = SyntaxHighlighter.highlight(text, lenguaje, palette);
    return TextSpan(style: style, children: spans);
  }
}
