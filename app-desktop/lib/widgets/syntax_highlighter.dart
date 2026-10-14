import 'package:flutter/material.dart';

import '../theme.dart';

/// Pequeño resaltador de sintaxis para los lenguajes más usados en clase.
///
/// No es un parser completo — es un tokenizador por reglas regex (estilo
/// Pygments simplificado) que cubre los casos comunes con buen aspecto:
/// keywords, strings, comentarios, números, decoradores, definiciones de
/// función/clase. Suficiente para que un archivo Python "se vea como
/// Python", un Dart "como Dart", etc.
///
/// Si el lenguaje no se reconoce, devuelve un único span en color base.
class SyntaxHighlighter {
  /// Devuelve los spans coloreados para [code] en el [lenguaje] dado.
  static List<TextSpan> highlight(
    String code,
    String lenguaje,
    AppPalette p,
  ) {
    final l = lenguaje.toLowerCase().trim();
    final reglas = _reglasPara(l);
    if (reglas.isEmpty) {
      return [TextSpan(text: code, style: _baseStyle(p))];
    }
    return _tokenizar(code, reglas, p);
  }

  /// Idiomas que el resaltador entiende. Cualquier otro va en plano.
  static const Set<String> lenguajesSoportados = {
    'py', 'python',
    'dart',
    'js', 'javascript', 'ts', 'typescript', 'jsx', 'tsx',
    'json',
    'yaml', 'yml',
    'html', 'xml',
    'css', 'scss',
    'sql',
    'sh', 'bash', 'shell', 'zsh', 'ps1', 'powershell',
    'c', 'cpp', 'c++', 'java', 'go', 'rust', 'rs', 'kt', 'kotlin',
    'md', 'markdown',
  };
}

// ────────────────────────── Paleta de tokens ──────────────────────────

TextStyle _baseStyle(AppPalette p) => TextStyle(color: p.codeText);

class _Colores {
  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color builtin;
  final Color def;
  final Color decorator;
  final Color punctuation;
  final Color base;
  const _Colores({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.builtin,
    required this.def,
    required this.decorator,
    required this.punctuation,
    required this.base,
  });
}

_Colores _coloresPara(AppPalette p) {
  final esOscuro = p.codeBg.computeLuminance() < 0.5;
  if (!esOscuro) {
    return _Colores(
      keyword: p.primary,
      string: const Color(0xFF15803D),
      comment: p.subtle,
      number: const Color(0xFF0284C7),
      builtin: const Color(0xFF7C3AED),
      def: const Color(0xFF6D28D9),
      decorator: const Color(0xFFC2410C),
      punctuation: p.codeText.withValues(alpha: 0.85),
      base: p.codeText,
    );
  }
  return _Colores(
    keyword: p.primary,
    string: const Color(0xFF98C379),
    comment: p.subtle,
    number: const Color(0xFF7DAEF0),
    builtin: const Color(0xFFE5C07B),
    def: const Color(0xFFE5C07B),
    decorator: const Color(0xFFE89E5C),
    punctuation: p.codeText.withValues(alpha: 0.7),
    base: p.codeText,
  );
}

// ────────────────────────── Reglas por lenguaje ──────────────────────────

class _Regla {
  final RegExp re;
  final Color Function(_Colores) color;
  const _Regla(this.re, this.color);
}

List<_Regla> _reglasPara(String l) {
  if (l == 'py' || l == 'python') return _python;
  if (l == 'dart') return _dart;
  if (l == 'js' ||
      l == 'javascript' ||
      l == 'ts' ||
      l == 'typescript' ||
      l == 'jsx' ||
      l == 'tsx') return _js;
  if (l == 'json') return _json;
  if (l == 'yaml' || l == 'yml') return _yaml;
  if (l == 'html' || l == 'xml') return _html;
  if (l == 'css' || l == 'scss') return _css;
  if (l == 'sql') return _sql;
  if (l == 'sh' ||
      l == 'bash' ||
      l == 'shell' ||
      l == 'zsh' ||
      l == 'ps1' ||
      l == 'powershell') return _bash;
  if (l == 'c' ||
      l == 'cpp' ||
      l == 'c++' ||
      l == 'java' ||
      l == 'go' ||
      l == 'rust' ||
      l == 'rs' ||
      l == 'kt' ||
      l == 'kotlin') return _cFamily;
  if (l == 'md' || l == 'markdown') return _markdown;
  return const [];
}

// Estilo común: orden importa — comentarios y strings ANTES de keywords
// (porque "def" dentro de un comentario o string no debe colorearse).
final List<_Regla> _python = [
  // comentarios
  _Regla(RegExp(r'#[^\n]*'), (c) => c.comment),
  // triple-string """ … """ y ''' … '''
  _Regla(RegExp(r'"""[\s\S]*?"""'), (c) => c.string),
  _Regla(RegExp(r"'''[\s\S]*?'''"), (c) => c.string),
  // strings simples y dobles
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  // números (enteros, decimales, hex)
  _Regla(RegExp(r'\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*(?:e[+-]?\d+)?)\b'),
      (c) => c.number),
  // decoradores
  _Regla(RegExp(r'@\w+(?:\.\w+)*'), (c) => c.decorator),
  // definición tras def/class
  _Regla(RegExp(r'(?<=\bdef\s)\w+'), (c) => c.def),
  _Regla(RegExp(r'(?<=\bclass\s)\w+'), (c) => c.def),
  // keywords
  _Regla(
    RegExp(r'\b(def|class|if|elif|else|for|while|in|not|and|or|is|None|True|False|return|yield|import|from|as|pass|break|continue|with|try|except|finally|raise|lambda|global|nonlocal|async|await|del|assert|match|case)\b'),
    (c) => c.keyword,
  ),
  // built-ins comunes
  _Regla(
    RegExp(r'\b(print|len|range|str|int|float|bool|list|dict|tuple|set|map|filter|zip|enumerate|sorted|reversed|sum|min|max|abs|round|open|input|type|isinstance|hasattr|getattr|setattr|super|self|cls|__init__|__name__|__main__)\b'),
    (c) => c.builtin,
  ),
];

final List<_Regla> _dart = [
  _Regla(RegExp(r'//[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'/\*[\s\S]*?\*/'), (c) => c.comment),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*(?:e[+-]?\d+)?)\b'),
      (c) => c.number),
  _Regla(RegExp(r'@\w+'), (c) => c.decorator),
  _Regla(
    RegExp(r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|Function|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|part|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield)\b'),
    (c) => c.keyword,
  ),
  _Regla(
    RegExp(r'\b(int|double|num|String|bool|List|Map|Set|Future|Stream|Iterable|Object|Widget|BuildContext|StatelessWidget|StatefulWidget|State|override|print)\b'),
    (c) => c.builtin,
  ),
];

final List<_Regla> _js = [
  _Regla(RegExp(r'//[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'/\*[\s\S]*?\*/'), (c) => c.comment),
  _Regla(RegExp(r'`(?:\\.|[^`\\])*`'), (c) => c.string),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*(?:e[+-]?\d+)?)\b'),
      (c) => c.number),
  _Regla(RegExp(r'@\w+'), (c) => c.decorator),
  _Regla(
    RegExp(r'\b(const|let|var|function|return|if|else|for|while|do|break|continue|switch|case|default|new|class|extends|super|this|import|export|from|as|default|async|await|try|catch|finally|throw|typeof|instanceof|in|of|delete|void|null|undefined|true|false|enum|interface|type|namespace|public|private|protected|readonly|static|abstract|implements)\b'),
    (c) => c.keyword,
  ),
  _Regla(
    RegExp(r'\b(console|window|document|Math|JSON|Promise|Array|Object|String|Number|Boolean|Symbol|Map|Set|RegExp|Date|Error|React|useState|useEffect|useMemo|useCallback)\b'),
    (c) => c.builtin,
  ),
];

final List<_Regla> _json = [
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"\s*(?=:)'),
      (c) => c.keyword), // claves
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r'\b(?:true|false|null)\b'), (c) => c.keyword),
  _Regla(RegExp(r'-?\d+\.?\d*(?:e[+-]?\d+)?'), (c) => c.number),
];

final List<_Regla> _yaml = [
  _Regla(RegExp(r'#[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'^[ \t]*[\w.\-]+(?=:)', multiLine: true),
      (c) => c.keyword), // claves
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'\b(?:true|false|null|yes|no|on|off)\b'),
      (c) => c.builtin),
  _Regla(RegExp(r'\b-?\d+\.?\d*\b'), (c) => c.number),
];

final List<_Regla> _html = [
  _Regla(RegExp(r'<!--[\s\S]*?-->'), (c) => c.comment),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'</?\w[\w-]*'), (c) => c.keyword), // <tag y </tag
  _Regla(RegExp(r'\b\w[\w-]*(?=\=)'), (c) => c.decorator), // atributos
];

final List<_Regla> _css = [
  _Regla(RegExp(r'/\*[\s\S]*?\*/'), (c) => c.comment),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'#[0-9A-Fa-f]{3,8}\b'), (c) => c.number), // colores hex
  _Regla(RegExp(r'\b\d+\.?\d*(?:px|em|rem|%|vh|vw|s|ms|deg)?\b'),
      (c) => c.number),
  _Regla(RegExp(r'@[\w-]+'), (c) => c.decorator),
  _Regla(RegExp(r'\.[\w-]+'), (c) => c.builtin), // .clases
  _Regla(RegExp(r'[\w-]+(?=\s*:)'), (c) => c.keyword), // propiedades
];

final List<_Regla> _sql = [
  _Regla(RegExp(r'--[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'/\*[\s\S]*?\*/'), (c) => c.comment),
  _Regla(RegExp(r"'(?:''|[^'])*'"), (c) => c.string),
  _Regla(RegExp(r'\b\d+\.?\d*\b'), (c) => c.number),
  _Regla(
    RegExp(
        r'\b(SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|TABLE|DROP|ALTER|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AS|AND|OR|NOT|NULL|IS|IN|LIKE|BETWEEN|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|VALUES|SET|INTO|PRIMARY|KEY|FOREIGN|REFERENCES|INDEX|UNIQUE|DEFAULT|CASCADE|RETURNING|WITH|CASE|WHEN|THEN|ELSE|END|DISTINCT|EXISTS|COUNT|SUM|AVG|MIN|MAX)\b',
        caseSensitive: false),
    (c) => c.keyword,
  ),
];

final List<_Regla> _bash = [
  _Regla(RegExp(r'#[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'[^']*'"), (c) => c.string),
  _Regla(RegExp(r'\$\{?\w+\}?'), (c) => c.builtin), // variables
  _Regla(RegExp(r'\b\d+\b'), (c) => c.number),
  _Regla(
    RegExp(r'\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|export|local|echo|cd|ls|grep|sed|awk|cat|sudo|apt|pip|npm|git|docker|python)\b'),
    (c) => c.keyword,
  ),
];

final List<_Regla> _cFamily = [
  _Regla(RegExp(r'//[^\n]*'), (c) => c.comment),
  _Regla(RegExp(r'/\*[\s\S]*?\*/'), (c) => c.comment),
  _Regla(RegExp(r'"(?:\\.|[^"\\])*"'), (c) => c.string),
  _Regla(RegExp(r"'(?:\\.|[^'\\])*'"), (c) => c.string),
  _Regla(RegExp(r'#\w+'), (c) => c.decorator),
  _Regla(RegExp(r'\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*[fL]?)\b'), (c) => c.number),
  _Regla(
    RegExp(r'\b(if|else|for|while|do|switch|case|break|continue|return|class|struct|enum|union|public|private|protected|static|const|void|int|long|short|char|float|double|bool|true|false|null|nullptr|new|delete|this|throw|try|catch|template|typename|namespace|using|virtual|override|final|auto|var|fn|let|mut|pub|impl|trait|use|mod|crate|where|move|ref|fun|val|object|companion|when|is)\b'),
    (c) => c.keyword,
  ),
];

final List<_Regla> _markdown = [
  _Regla(RegExp(r'```[\s\S]*?```'), (c) => c.string), // bloques de código
  _Regla(RegExp(r'`[^`]+`'), (c) => c.string), // código inline
  _Regla(RegExp(r'^#{1,6}\s[^\n]+', multiLine: true),
      (c) => c.keyword), // encabezados
  _Regla(RegExp(r'\*\*[^*]+\*\*'), (c) => c.def), // negrita
  _Regla(RegExp(r'\*[^*]+\*'), (c) => c.builtin), // cursiva
  _Regla(RegExp(r'\[[^\]]+\]\([^)]+\)'),
      (c) => c.decorator), // enlaces [texto](url)
  _Regla(RegExp(r'^\s*[-*+]\s', multiLine: true),
      (c) => c.punctuation), // bullets
];

// ────────────────────────── Tokenizador ──────────────────────────

List<TextSpan> _tokenizar(
  String code,
  List<_Regla> reglas,
  AppPalette p,
) {
  final colores = _coloresPara(p);
  final spans = <TextSpan>[];
  final buffer = StringBuffer();

  void volcarBuffer() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: _baseStyle(p)));
    buffer.clear();
  }

  int pos = 0;
  while (pos < code.length) {
    Match? mejor;
    Color? mejorColor;
    int mejorLen = 0;
    for (final regla in reglas) {
      final m = regla.re.matchAsPrefix(code, pos);
      if (m != null && m.end > m.start) {
        final len = m.end - m.start;
        if (len > mejorLen) {
          mejor = m;
          mejorColor = regla.color(colores);
          mejorLen = len;
        }
      }
    }
    if (mejor != null && mejorColor != null) {
      volcarBuffer();
      spans.add(TextSpan(
        text: code.substring(mejor.start, mejor.end),
        style: TextStyle(color: mejorColor),
      ));
      pos = mejor.end;
    } else {
      buffer.write(code[pos]);
      pos++;
    }
  }
  volcarBuffer();
  return spans;
}

// ────────────────────────── Widget envoltura ──────────────────────────

/// Texto seleccionable con sintaxis coloreada. Pensado para mostrar
/// el contenido completo de un archivo en el explorador.
class HighlightedCode extends StatelessWidget {
  final String code;
  final String lenguaje;
  final double fontSize;
  final TextStyle? baseStyle;

  const HighlightedCode({
    super.key,
    required this.code,
    required this.lenguaje,
    this.fontSize = 12.5,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final spans = SyntaxHighlighter.highlight(code, lenguaje, p);
    final base = (baseStyle ??
            TextStyle(
              fontFamily: AppFonts.monoFallback.first,
              fontFamilyFallback: AppFonts.monoFallback,
              fontSize: fontSize,
              height: 1.55,
              color: p.codeText,
            ));
    return SelectableText.rich(
      TextSpan(style: base, children: spans),
    );
  }
}
