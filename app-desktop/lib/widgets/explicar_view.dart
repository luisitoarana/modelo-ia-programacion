import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../providers.dart';
import '../services/curriculum_catalog.dart';
import '../services/explicador_automatico.dart';
import '../services/tts_service.dart';
import '../theme.dart';
import 'tareas_estudio.dart';

/// Enfoques pedagógicos de explicación.
enum ModoExplicacion {
  pasoAPaso(
    'didactico',
    '🎓 Didáctico (Paso a paso)',
    'Explicación clara con analogías y desglose',
  ),
  complejidad(
    'complejidad',
    '⚡ Big-O & Rendimiento',
    'Análisis de tiempo O(n), memoria y estructura',
  ),
  bugs(
    'bugs',
    '🐛 Detección de Bugs & Riesgos',
    'Casos límite, excepciones y validaciones faltantes',
  ),
  optimizacion(
    'optimizacion',
    '✨ Optimización (PEP 8)',
    'Versión más idiomática, rápida y limpia',
  );

  final String id;
  final String label;
  final String descripcion;
  const ModoExplicacion(this.id, this.label, this.descripcion);
}

/// Vista de Explicación Didáctica de Código Python.
class ExplicarView extends StatefulWidget {
  const ExplicarView({super.key});

  @override
  State<ExplicarView> createState() => _ExplicarViewState();
}

class _ExplicarViewState extends State<ExplicarView> {
  final _codigoCtrl = TextEditingController();
  final _scrollEditor = ScrollController();
  final _scrollGutter = ScrollController();
  String _explicacion = '';
  bool _cargando = false;
  bool _leyendo = false;
  String _nivel = 'principiante';
  ModoExplicacion _modo = ModoExplicacion.pasoAPaso;
  String? _nombreArchivo;
  LeccionCurricular? _leccionActiva;
  String? _tareaPractica;
  final List<MapEntry<String, String>> _archivos = [];
  final _prediccionCtrl = TextEditingController();
  final _explicacionPropiaCtrl = TextEditingController();
  DateTime _inicioIntento = DateTime.now();
  String? _codigoInicialIntento;
  String? _codigoGuardado;
  int _pistasReveladas = 0;
  bool _prediccionConfirmada = false;
  bool _guardandoIntento = false;
  bool _intentoGuardado = false;
  bool _validandoSintaxis = false;
  bool? _sintaxisValida;
  String? _codigoValidado;
  String? _mensajeSintaxis;

  // Pestaña activa en la visualización de la explicación
  int _tabResultado =
      3; // 0: IA, 1: automático, 2: métricas, 3: práctica guiada

  @override
  void initState() {
    super.initState();
    // Carga la primera lección curricular para que comience con fundamentos
    _leccionActiva = CurriculumCatalog.lecciones.first;
    _codigoCtrl.text = _leccionActiva?.codigoInicial ?? '';
    _nombreArchivo = '${_leccionActiva?.id}.py';
    _codigoCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _scrollEditor.addListener(() {
      if (_scrollGutter.hasClients && _scrollEditor.hasClients) {
        if (_scrollGutter.offset != _scrollEditor.offset) {
          _scrollGutter.jumpTo(_scrollEditor.offset);
        }
      }
    });
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _prediccionCtrl.dispose();
    _explicacionPropiaCtrl.dispose();
    _scrollEditor.dispose();
    _scrollGutter.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  void _aplicarCorreccion(int numLinea, String correccion) {
    final lineas = _codigoCtrl.text.split('\n');
    if (numLinea >= 1 && numLinea <= lineas.length) {
      lineas[numLinea - 1] = correccion;
      setState(() {
        _codigoCtrl.text = lineas.join('\n');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Corrección aplicada en línea $numLinea'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _construirTextoLecturaAutomatico(DiagnosticoAutomatico diag) {
    final sb = StringBuffer();
    if (diag.respuestaPreguntaConceptual != null) {
      sb.writeln(
        diag.respuestaPreguntaConceptual!
            .replaceAll('*', '')
            .replaceAll('#', ''),
      );
      sb.writeln('. ');
    }
    if (diag.erroresSintacticos.isNotEmpty) {
      sb.writeln('Atención: se han detectado errores sintácticos. ');
      for (final err in diag.erroresSintacticos) {
        sb.writeln('$err. ');
      }
    }
    sb.writeln('Desglose paso a paso de tu código: ');
    for (final l in diag.lineas) {
      if (l.tipo != 'espacio') {
        sb.writeln('Línea ${l.numeroLinea}: ${l.explicacionDidactica}. ');
      }
    }
    if (diag.salidaSimulada != null) {
      sb.writeln('Salida estimada en consola: ${diag.salidaSimulada}.');
    }
    return sb.toString();
  }

  Future<void> _alternarLectura() async {
    if (_leyendo) {
      await TtsService.instance.stop();
      if (mounted) setState(() => _leyendo = false);
      return;
    }
    final settings = context.read<SettingsProvider>();
    final diag = ExplicadorAutomatico.analizar(_codigoCtrl.text);
    final textoLectura = (_tabResultado == 1 || _explicacion.isEmpty)
        ? _construirTextoLecturaAutomatico(diag)
        : _explicacion;

    if (textoLectura.trim().isEmpty) return;

    if (mounted) setState(() => _leyendo = true);
    await TtsService.instance.speak(
      textoLectura,
      velocidad: settings.ttsVelocidad,
      voz: settings.ttsVoz,
      idioma: settings.idioma.startsWith('es') ? 'es-ES' : 'en-US',
    );
  }

  Future<void> _abrirArchivos() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (res == null || res.files.isEmpty) return;
      final nuevos = <MapEntry<String, String>>[];
      for (final f in res.files) {
        String contenido = '';
        if (f.bytes != null) {
          contenido = utf8.decode(f.bytes!, allowMalformed: true);
        } else if (f.path != null) {
          try {
            final bytes = await File(f.path!).readAsBytes();
            contenido = utf8.decode(bytes, allowMalformed: true);
          } catch (_) {
            continue;
          }
        }
        if (contenido.isNotEmpty) {
          nuevos.add(MapEntry(f.name, contenido));
        }
      }
      if (nuevos.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _archivos
          ..clear()
          ..addAll(nuevos);
        _cargarArchivo(nuevos.first);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    }
  }

  void _cargarArchivo(MapEntry<String, String> a) {
    setState(() {
      _codigoCtrl.text = a.value;
      _nombreArchivo = a.key;
      _leccionActiva = null;
      _tareaPractica = null;
      _reiniciarIntento();
    });
  }

  void _reiniciarIntento() {
    _prediccionCtrl.clear();
    _explicacionPropiaCtrl.clear();
    _inicioIntento = DateTime.now();
    _codigoInicialIntento = null;
    _codigoGuardado = null;
    _pistasReveladas = 0;
    _prediccionConfirmada = false;
    _intentoGuardado = false;
    _explicacion = '';
    _tabResultado = 3;
    _codigoValidado = null;
    _sintaxisValida = null;
    _mensajeSintaxis = null;
  }

  Future<void> _validarSintaxis() async {
    if (_validandoSintaxis ||
        _codigoCtrl.text.trim().isEmpty ||
        context.read<SettingsProvider>().esBloqueadoPostTest) {
      return;
    }
    final codigo = _codigoCtrl.text;
    setState(() => _validandoSintaxis = true);
    try {
      final resultado = await context
          .read<AuthProvider>()
          .api
          .validarSintaxisPython(codigo);
      if (!mounted) return;
      setState(() {
        _codigoValidado = codigo;
        _sintaxisValida = resultado['valido'] == true;
        _mensajeSintaxis = _sintaxisValida == true
            ? 'Python confirmó sintaxis válida'
            : 'Error de sintaxis en línea ${resultado['linea']}: ${resultado['mensaje']}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo comprobar la sintaxis: $e')),
      );
    } finally {
      if (mounted) setState(() => _validandoSintaxis = false);
    }
  }

  Future<void> _guardarIntento() async {
    if (_guardandoIntento ||
        _intentoGuardado ||
        !_prediccionConfirmada ||
        _explicacionPropiaCtrl.text.trim().isEmpty) {
      return;
    }
    final codigoActual = _codigoCtrl.text.trim();
    if (codigoActual.isEmpty) return;
    setState(() => _guardandoIntento = true);
    try {
      final settings = context.read<SettingsProvider>();
      final api = context.read<AuthProvider>().api;
      await api.registrarIntentoAprendizaje(
        leccionId: _leccionActiva?.id,
        pregunta:
            (_tareaPractica == null ? null : 'Tarea: $_tareaPractica\n¿Qué hará tu código y por qué?') ?? _leccionActiva?.preguntaAutoevaluacion ??
            '¿Qué hará este código y qué salida o resultado esperas?',
        modo: settings.modoAcompanamiento,
        codigoInicial: _codigoInicialIntento ?? codigoActual,
        codigoFinal: codigoActual,
        prediccion: _prediccionCtrl.text.trim(),
        explicacionPropia: _explicacionPropiaCtrl.text.trim(),
        pistasUsadas: _pistasReveladas,
        duracionSegundos: DateTime.now()
            .difference(_inicioIntento)
            .inSeconds
            .clamp(0, 86400)
            .toInt(),
      );
      if (!mounted) return;
      setState(() {
        _intentoGuardado = true;
        _codigoGuardado = codigoActual;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Intento registrado. La explicación queda pendiente de revisión docente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el intento: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardandoIntento = false);
    }
  }

  void _cerrarArchivo(String nombre) {
    setState(() {
      _archivos.removeWhere((e) => e.key == nombre);
      if (_nombreArchivo == nombre) {
        if (_archivos.isNotEmpty) {
          _cargarArchivo(_archivos.first);
        } else {
          _nombreArchivo = null;
          _codigoCtrl.clear();
        }
      }
    });
  }

  String _construirPrompt(String codigo) {
    final adaptacionNivel = switch (_nivel) {
      'principiante' =>
        '''
INSTRUCCIÓN PEDAGÓGICA PARA NIVEL: PRINCIPIANTE
- Usa explicaciones amigables, pacientes y detalladas desde cero, sin jerga técnica compleja sin explicar.
- Explica qué hace cada línea, para qué sirve cada variable y por qué se toman esas decisiones.
- Si detectas errores, señala la línea exacta y explica con palabras sencillas por qué Python se detendría ahí y cómo corregirlo paso a paso.
''',
      'intermedio' =>
        '''
INSTRUCCIÓN PEDAGÓGICA PARA NIVEL: INTERMEDIO
- Enfoque pragmático y estructurado: lógica algorítmica, manejo de excepciones con try/except, legibilidad y modularidad.
- Explica la lógica interna, las precondiciones y el flujo de control.
''',
      'avanzado' =>
        '''
INSTRUCCIÓN PEDAGÓGICA PARA NIVEL: AVANZADO
- Sin introducciones obvias ni explicaciones triviales. Rigor técnico directo al grano.
- Señala exactamente: "En la función X o línea Y le falta validar Z porque genera W".
- Analiza patrones de diseño, impacto en memoria/tiempo, idioms de Python moderno y optimización a bajo nivel.
''',
      _ => '',
    };

    final enfoque = switch (_modo) {
      ModoExplicacion.pasoAPaso =>
        '''
1. ## 🎯 Diagnóstico y Propósito General
- Identifica el tipo de código (algoritmo, script utilitario de archivos, clase/modelo, función de procesamiento).
- Explica qué tarea realiza en el sistema y cuál es su objetivo.

2. ## 📦 Bibliotecas y Módulos Importados
- Analiza CADA importación (`import ...` o `from ... import ...`).
- Explica para qué sirve cada biblioteca en Python y advierte claramente si alguna no se utiliza en el código (código muerto).

3. ## 📝 Desglose Línea por Línea
- Explica secuencialmente cada instrucción del código real: variables, operaciones de entrada/salida, llamadas y retorno.
- Si abre archivos (`open`), analiza modos `"w"`/`"r"`, codificación `encoding="utf-8"` y si los recursos se liberan adecuadamente.

4. ## ⚠️ Riesgos, Casos Límite y Buenas Prácticas
- ¿Qué condiciones o datos podrían hacer fallar este código?
- Buenas prácticas aplicables (ej. gestores de contexto `with open(...)`, manejo de rutas con `pathlib`).
- Muestra la versión refactorizada moderna recomendada.
''',
      ModoExplicacion.complejidad =>
        '''
1. ## ⏱️ Complejidad Temporal (Big-O en el mejor, peor y caso promedio)
2. ## 💾 Complejidad Espacial (uso de memoria auxiliar, descriptores y buffers)
3. ## 🔄 Análisis de Bucles, Operaciones I/O y Recursión
4. ## ⚖️ Cuellos de Botella, Eficiencia de I/O y Escalabilidad
''',
      ModoExplicacion.bugs =>
        '''
1. ## 🔍 Diagnóstico Directo de Bugs y Errores
- Señala la línea o bloque exacto donde está el problema: `--> Línea X: ...`
- Explica de forma clara y directa: "¿Por qué falla o qué le falta a esta instrucción?"

2. ## 💥 Escenario de Falla y Excepción
- Muestra con qué datos de entrada se rompe el código (ej. lista vacía `[]`, división por cero, índice fuera de rango, tipo incompatible).
- Indica qué excepción o error arroja Python (`ZeroDivisionError`, `IndexError`, `TypeError`, `KeyError`, etc.).

3. ## 🛡️ Solución Concreta y Código Corregido
- Explica qué cambio específico se debe hacer para solucionar el error.
- Entrega el código Python completamente corregido, funcional y blindado.
''',
      ModoExplicacion.optimizacion =>
        '''
1. ## 🐍 Evaluación de Estilo Pythonic (PEP 8, buenas prácticas de I/O y gestión de contexto)
2. ## ✨ Propuesta de Código Optimizado (uso de pathlib, with statements y eliminación de código muerto)
3. ## 📊 Comparación Antes vs Después (por qué la versión optimizada es más segura y mantenible)
''',
    };

    final String contextoCurricular = _leccionActiva != null
        ? '''\n[CONTEXTO PEDAGÓGICO DE LA LECCIÓN]
Módulo Curricular: ${_leccionActiva!.moduloTitulo}
Lección ${_leccionActiva!.numero}: ${_leccionActiva!.titulo}
Concepto Central a Enseñar: ${_leccionActiva!.conceptoClave}
Palabras Reservadas Clave: ${_leccionActiva!.palabrasReservadas.join(", ")}
Objetivo de Aprendizaje: ${_leccionActiva!.descripcionPedagogica}
Pregunta de Reflexión a Incluir al Final: ${_leccionActiva!.preguntaAutoevaluacion}
'''
        : '';

    return '''Petición actual del estudiante: ${_modo == ModoExplicacion.pasoAPaso || _modo == ModoExplicacion.complejidad ? 'Explica mi intento sin modificar el código.' : 'Analiza los errores o mejoras del código y propone una versión corregida.'}
Eres un profesor universitario senior de Python y experto en arquitectura de software.
Explica el siguiente código de forma rigurosa y adaptada pedagógicamente al estudiante.

$adaptacionNivel
$contextoCurricular

${_tareaPractica == null ? '' : 'Tarea de práctica activa: $_tareaPractica'}
Predicción inicial del estudiante (puede ser breve o incorrecta): ${_prediccionCtrl.text}
Razonamiento del estudiante: ${_explicacionPropiaCtrl.text}
ANDAMIAJE: parte de ese razonamiento y del código real. Identifica qué comprendió y qué necesita revisar sin calificarlo. Explica un paso concreto con un ejemplo diferente; pregunta por el efecto de cambiar un dato real del código. Ayuda a transferir la idea a la tarea, no a memorizar la respuesta. No afirmes que ha aprendido solo por contestar.

DIRECTIVAS CRÍTICAS:
- Responde OBLIGATORIAMENTE en idioma ESPAÑOL.
- ANALIZA EXCLUSIVAMENTE el código real proporcionado a continuación. NO inventes clases, funciones ni salidas hipotéticas que no figuren en el código.
- NUNCA omitas las importaciones ni los detalles técnicos; cada línea importa para el aprendizaje.
- Estructura tu respuesta con las siguientes secciones:

$enfoque

CÓDIGO A EXPLICAR:
```python
$codigo
```''';
  }

  Future<void> _explicar() async {
    final settings = context.read<SettingsProvider>();
    if (settings.esBloqueadoPostTest) return;
    if (settings.esConAcompanamiento && settings.practicaGuiada &&
        (!_intentoGuardado || _codigoGuardado != _codigoCtrl.text.trim())) {
      setState(() => _tabResultado = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registra primero tu predicción y explicación para abrir la respuesta.',
          ),
        ),
      );
      return;
    }
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty || _cargando) return;

    setState(() {
      _cargando = true;
      _explicacion = '';
    });

    final api = context.read<AuthProvider>().api;

    try {
      final prompt = _construirPrompt(codigo);
      final resp = await api.mensajeRapido(
        prompt,
        idioma: settings.idioma,
        buscarWeb: false,
        proveedor: settings.proveedor,
        modoAcompanamiento: settings.modoAcompanamiento,
        nivelModulo: settings.nivelModulo,
      );

      if (!mounted) return;

      setState(() {
        _explicacion = resp.mensajeAsistente.contenido;
        _tabResultado = 0;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _explicacion =
              '### ❌ Error del Servidor\n\n${e.mensaje}\n\n${e.detalle ?? ""}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _explicacion = '### ❌ Error al procesar la solicitud\n\n$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // Análisis estructural local en tiempo real (AST ligero)
  Map<String, dynamic> _analizarEstructura(String codigo) {
    final lineas = codigo.split('\n');
    int funciones = 0;
    int clases = 0;
    int bucles = 0;
    int imports = 0;
    final nombresFunciones = <String>[];

    for (final l in lineas) {
      final t = l.trim();
      if (t.startsWith('def ')) {
        funciones++;
        final match = RegExp(
          r'def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(',
        ).firstMatch(t);
        if (match != null) nombresFunciones.add(match.group(1)!);
      } else if (t.startsWith('class ')) {
        clases++;
      } else if (t.startsWith('for ') || t.startsWith('while ')) {
        bucles++;
      } else if (t.startsWith('import ') || t.startsWith('from ')) {
        imports++;
      }
    }

    String complejidadEst = 'O(1)';
    if (bucles >= 2) {
      complejidadEst = 'O(n²) o mayor';
    } else if (bucles == 1) {
      complejidadEst = 'O(n)';
    }

    return {
      'lineas': lineas.length,
      'funciones': funciones,
      'clases': clases,
      'bucles': bucles,
      'imports': imports,
      'nombresFunciones': nombresFunciones,
      'complejidad': complejidadEst,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final settings = context.watch<SettingsProvider>();
    if (settings.esSinAcompanamiento || settings.esBloqueadoPostTest) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              settings.esBloqueadoPostTest
                  ? 'Evaluación individual: el explicador está desactivado. Resuelve el instrumento pre/post indicado por tu docente sin ayuda.'
                  : 'Condición de generación directa: usa el editor o el chat. El explicador guiado está reservado para la otra condición del estudio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 16, height: 1.5),
            ),
          ),
        ),
      );
    }
    final stats = _analizarEstructura(_codigoCtrl.text);
    final diagnostico = ExplicadorAutomatico.analizar(_codigoCtrl.text);

    return Container(
      color: p.bg,
      child: Column(
        children: [
          _header(p),
          if (settings.esConAcompanamiento)
            TextButton.icon(icon: const Icon(Icons.assignment_outlined),
              label: const Text('Tareas de práctica con andamiaje'),
              onPressed: _cargando ? null : () async {
                final tarea = await elegirTareaEstudio(context, generar: false);
                if (tarea == null || !mounted) return;
                setState(() {
                  _reiniciarIntento();
                  _leccionActiva = null;
                  _tareaPractica = tarea['consigna'] as String;
                });
              }),
          if (_tareaPractica != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Tarea: $_tareaPractica\nEscribe o pega un intento en el editor y predice qué hará. Puedes equivocarte; después contrasta tu razonamiento con la explicación.')),
          _barraEjemplos(p),
          if (_archivos.isNotEmpty) _tabsArchivos(p),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Panel Izquierdo: Editor + Métricas Locales ──
                  Expanded(flex: 5, child: _panelEditor(p, stats, diagnostico)),
                  const SizedBox(width: 12),
                  // ── Panel Derecho: Explicación Didáctica ──
                  Expanded(
                    flex: 6,
                    child: _panelExplicacion(p, stats, diagnostico),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppPalette p) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: p.primary),
          const SizedBox(width: 10),
          Text(
            'Explicador Didáctico',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(width: 16),
          // Selector Modo de Explicación
          _selectorModo(p),
          const SizedBox(width: 8),
          // Selector Nivel del Estudiante
          _selectorNivel(p),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _abrirArchivos,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              side: BorderSide(color: p.borderSoft),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 14),
            label: const Text(
              'Abrir archivo',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed:
                _cargando ||
                    context.watch<SettingsProvider>().esBloqueadoPostTest
                ? null
                : _explicar,
            style: FilledButton.styleFrom(
              backgroundColor: p.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            icon: _cargando
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bolt_rounded, size: 15),
            label: Text(
              _cargando ? 'Generando…' : 'Explicar',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraEjemplos(AppPalette p) {
    final settings = context.watch<SettingsProvider>();
    final lecciones = CurriculumCatalog.leccionesPorModulo(
      settings.nivelModulo,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface2.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: p.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_stories_rounded, size: 14, color: p.primary),
          const SizedBox(width: 6),
          Text(
            'Retos Curriculares (${settings.nivelModulo.toUpperCase()}):',
            style: TextStyle(
              fontSize: 11,
              color: p.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final l in lecciones)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _codigoCtrl.text = l.codigoInicial;
                            _nombreArchivo = '${l.id}.py';
                            _leccionActiva = l;
                            _tareaPractica = null;
                            _reiniciarIntento();
                          });
                        },
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _leccionActiva?.id == l.id
                                ? p.primary.withValues(alpha: 0.16)
                                : p.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: _leccionActiva?.id == l.id
                                  ? p.primary
                                  : p.borderSoft,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                l.icono,
                                size: 12,
                                color: _leccionActiva?.id == l.id
                                    ? p.primary
                                    : p.muted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${l.numero} ${l.titulo}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _leccionActiva?.id == l.id
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: _leccionActiva?.id == l.id
                                      ? p.text
                                      : p.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelEditor(
    AppPalette p,
    Map<String, dynamic> stats,
    DiagnosticoAutomatico diagnostico,
  ) {
    final esPostTest = context.watch<SettingsProvider>().esBloqueadoPostTest;
    final validacionActual =
        _codigoValidado == _codigoCtrl.text && _sintaxisValida != null;
    final hayAlerta = validacionActual
        ? _sintaxisValida == false
        : diagnostico.erroresSintacticos.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header del Editor con métricas locales
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 14, color: p.primary),
                const SizedBox(width: 6),
                Text(
                  _nombreArchivo ?? 'Código Python',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${stats["lineas"]} líneas  •  ${stats["funciones"]} fn  •  ${stats["bucles"]} loops',
                  style: TextStyle(fontSize: 10.5, color: p.subtle),
                ),
              ],
            ),
          ),
          if (_leccionActiva != null && !esPostTest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: p.primary.withValues(alpha: 0.07),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, size: 14, color: p.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Objetivo: ${_leccionActiva!.descripcionPedagogica}',
                      style: TextStyle(fontSize: 11, color: p.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _tabResultado = 3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 13,
                            color: p.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Ver Pistas',
                            style: TextStyle(
                              fontSize: 11,
                              color: p.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Editor de texto con columna de números de línea sincronizada
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 44,
                  color: p.surface2.withValues(alpha: 0.35),
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: SingleChildScrollView(
                    controller: _scrollGutter,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (
                          var i = 1;
                          i <=
                              (_codigoCtrl.text.isEmpty
                                  ? 1
                                  : '\n'.allMatches(_codigoCtrl.text).length +
                                        1);
                          i++
                        )
                          Text(
                            '$i',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: p.subtle,
                              fontFamily: AppFonts.monoFallback.first,
                              fontFamilyFallback: AppFonts.monoFallback,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: p.borderSoft),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    child: TextField(
                      controller: _codigoCtrl,
                      scrollController: _scrollEditor,
                      onChanged: (_) => setState(() {}),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontFamily: AppFonts.monoFallback.first,
                        fontFamilyFallback: AppFonts.monoFallback,
                        fontSize: 12.5,
                        height: 1.5,
                        color: p.text,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Pega o escribe tu código Python aquí…',
                        hintStyle: TextStyle(color: p.subtle),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Barra de Diagnóstico y Auditoría en Vivo (tiempo real)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: !esPostTest && hayAlerta
                  ? AppColors.danger.withValues(alpha: 0.12)
                  : p.surface2.withValues(alpha: 0.45),
              border: Border(top: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(
                  !esPostTest && hayAlerta
                      ? Icons.warning_amber_rounded
                      : validacionActual && !esPostTest
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 14,
                  color: !esPostTest && hayAlerta ? AppColors.danger : p.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    esPostTest
                        ? 'Evaluación independiente: ayuda y diagnósticos ocultos'
                        : validacionActual
                        ? _mensajeSintaxis ??
                              'Resultado de Python no disponible'
                        : diagnostico.erroresSintacticos.isNotEmpty
                        ? 'Posible incidencia: ${diagnostico.erroresSintacticos.first}'
                        : 'Análisis orientativo; comprueba la sintaxis con Python',
                    style: TextStyle(
                      fontSize: 11,
                      color: !esPostTest && hayAlerta
                          ? AppColors.danger
                          : p.muted,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Comprobar sintaxis con Python',
                  onPressed: esPostTest || _validandoSintaxis
                      ? null
                      : _validarSintaxis,
                  icon: const Icon(Icons.fact_check_outlined, size: 17),
                ),
                InkWell(
                  onTap: esPostTest ? null : () => _seleccionarTab(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: p.borderSoft),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 12, color: p.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Explicador en Vivo',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: p.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelExplicacion(
    AppPalette p,
    Map<String, dynamic> stats,
    DiagnosticoAutomatico diagnostico,
  ) {
    final settings = context.watch<SettingsProvider>();
    final mostrarPractica =
        (_tabResultado == 3 && settings.practicaGuiada) ||
        settings.esBloqueadoPostTest ||
        settings.esConAcompanamiento && settings.practicaGuiada &&
            (!_intentoGuardado || _codigoGuardado != _codigoCtrl.text.trim());
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header de la Explicación con Tabs y acciones
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSoft)),
            ),
            child: Row(
              children: [
                _tabHeader(p, 3, '🎯 Practicar', Icons.school_outlined),
                const SizedBox(width: 6),
                _tabHeader(p, 0, '📖 IA', Icons.article_outlined),
                const SizedBox(width: 6),
                _tabHeader(p, 1, '⚡ Auto', Icons.bolt_rounded),
                const SizedBox(width: 6),
                _tabHeader(p, 2, '📊 Métricas', Icons.insights_rounded),
                const Spacer(),
                if (!mostrarPractica &&
                    (_tabResultado == 0 && _explicacion.isNotEmpty ||
                        _tabResultado == 1)) ...[
                  Tooltip(
                    message: 'Copiar explicación',
                    child: IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      splashRadius: 14,
                      color: p.muted,
                      onPressed: () {
                        final texto = _tabResultado == 0
                            ? _explicacion
                            : _construirTextoLecturaAutomatico(diagnostico);
                        Clipboard.setData(ClipboardData(text: texto));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Explicación copiada')),
                        );
                      },
                    ),
                  ),
                  Tooltip(
                    message: _leyendo ? 'Detener lectura' : 'Leer en voz alta',
                    child: IconButton(
                      icon: Icon(
                        _leyendo ? Icons.stop_rounded : Icons.volume_up_rounded,
                        size: 15,
                      ),
                      splashRadius: 14,
                      color: _leyendo ? p.primary : p.muted,
                      onPressed: _alternarLectura,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Contenido de la pestaña activa
          Expanded(
            child: mostrarPractica
                ? _practicaGuiada(p, settings)
                : _tabResultado == 0
                ? (_explicacion.isEmpty
                      ? _estadoVacio(p)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: MarkdownBody(
                            data: _explicacion,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: p.text,
                              ),
                              h1: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: p.text,
                              ),
                              h2: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: p.primary,
                              ),
                              h3: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                              strong: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: p.text,
                              ),
                              code: TextStyle(
                                backgroundColor: p.surface2,
                                fontFamily: AppFonts.monoFallback.first,
                                fontSize: 12,
                                color: p.primary,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: p.surface2,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: p.borderSoft),
                              ),
                            ),
                          ),
                        ))
                : (_tabResultado == 1
                      ? _explicadorAutomaticoView(p, diagnostico)
                      : _metricasView(p, stats, diagnostico)),
          ),
        ],
      ),
    );
  }

  Widget _tabHeader(AppPalette p, int index, String label, IconData icon) {
    final activo = _tabResultado == index;
    return InkWell(
      onTap: () => _seleccionarTab(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: activo ? p.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: activo ? p.borderSoft : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: activo ? p.primary : p.subtle),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: activo ? FontWeight.w600 : FontWeight.w400,
                color: activo ? p.text : p.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _seleccionarTab(int index) {
    final settings = context.read<SettingsProvider>();
    if (index != 3 &&
        (settings.esBloqueadoPostTest ||
            settings.esConAcompanamiento && settings.practicaGuiada &&
                (!_intentoGuardado ||
                    _codigoGuardado != _codigoCtrl.text.trim()))) {
      setState(() => _tabResultado = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registra tu intento antes de ver las explicaciones.'),
        ),
      );
      return;
    }
    setState(() => _tabResultado = index);
  }

  Widget _practicaGuiada(AppPalette p, SettingsProvider settings) {
    if (!settings.practicaGuiada) {
      return const Center(child: Text("La práctica guiada está desactivada por el docente. Puedes pedir directamente una explicación del código."));
    }
    final pistas =
        _leccionActiva?.pistas ??
        const <String>[
          'Identifica qué datos entran y qué resultado debería producir el código.',
          'Sigue el valor de las variables importantes línea por línea.',
          'Prueba mentalmente un caso normal y un caso límite.',
        ];
    final puedePedirPistas =
        settings.esConAcompanamiento &&
        _prediccionConfirmada &&
        !_intentoGuardado &&
        _pistasReveladas < pistas.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Práctica guiada',
          style: TextStyle(
            color: p.primary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Responde con tus palabras: puedes escribir una respuesta breve o extensa y usar ejemplos. No necesitas memorizar una definición. Tu docente revisará el contenido; la IA no asigna una nota.',
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        Text(
          _leccionActiva?.preguntaAutoevaluacion ??
              '¿Qué hará este código y qué salida o resultado esperas?',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prediccionCtrl,
          readOnly: _prediccionConfirmada,
          maxLines: 3,
          maxLength: 10000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Mi respuesta inicial',
          ),
        ),
        if (!_prediccionConfirmada)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed:
                  _prediccionCtrl.text.trim().isEmpty ||
                      _codigoCtrl.text.trim().isEmpty
                  ? null
                  : () => setState(() {
                      _prediccionConfirmada = true;
                      _codigoInicialIntento = _codigoCtrl.text.trim();
                    }),
              child: const Text('Confirmar mi respuesta'),
            ),
          ),
        if (_prediccionConfirmada) ...[
          if (settings.esConAcompanamiento) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: puedePedirPistas
                  ? () => setState(() => _pistasReveladas++)
                  : null,
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
              label: Text(
                _pistasReveladas == 0
                    ? 'Pedir primera pista'
                    : 'Pedir siguiente pista ($_pistasReveladas/${pistas.length})',
              ),
            ),
            for (var i = 0; i < _pistasReveladas; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${i + 1}. ${pistas[i]}',
                  style: TextStyle(color: p.text, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Text(
            'Ahora explica por qué esperas ese resultado. Puedes usar un ejemplo o proponer una corrección.',
            style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _explicacionPropiaCtrl,
            readOnly: _intentoGuardado,
            maxLines: 4,
            maxLength: 10000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Mi explicación y posible corrección',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    _guardandoIntento ||
                        _intentoGuardado ||
                        _explicacionPropiaCtrl.text.trim().isEmpty
                    ? null
                    : _guardarIntento,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  _intentoGuardado
                      ? 'Intento registrado'
                      : _guardandoIntento
                      ? 'Guardando…'
                      : 'Registrar intento',
                ),
              ),
              if (_intentoGuardado)
                OutlinedButton(
                  onPressed: () => setState(_reiniciarIntento),
                  child: const Text('Nuevo intento'),
                ),
              if (_intentoGuardado &&
                  settings.esConAcompanamiento &&
                  _codigoGuardado == _codigoCtrl.text.trim())
                OutlinedButton(
                  onPressed: _cargando ? null : _explicar,
                  child: const Text('Abrir explicación completa'),
                ),
            ],
          ),
          if (_intentoGuardado && _codigoGuardado != _codigoCtrl.text.trim())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'El código cambió después del registro. Inicia un intento nuevo para explicar esta versión.',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ),
        ],
      ],
    );
  }

  Widget _explicadorAutomaticoView(AppPalette p, DiagnosticoAutomatico diag) {
    if (diag.lineas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt_outlined,
              size: 40,
              color: p.subtle.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Explicador Automático en Tiempo Real',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: p.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Escribe o pega código en el editor para ver su explicación y auditoría en vivo.',
              style: TextStyle(fontSize: 11.5, color: p.subtle),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. Respuesta a Pregunta Conceptual en Comentario
        if (diag.respuestaPreguntaConceptual != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.primary.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_rounded, size: 16, color: p.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Pregunta Conceptual Detectada en el Código',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: p.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: diag.respuestaPreguntaConceptual!,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 11.5, height: 1.45, color: p.text),
                    strong: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: p.text,
                    ),
                    code: TextStyle(
                      backgroundColor: p.surface2,
                      fontFamily: AppFonts.monoFallback.first,
                      fontSize: 11,
                      color: p.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 2. Alertas de Errores Sintácticos en Vivo
        if (diag.erroresSintacticos.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.bug_report_rounded,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${diag.erroresSintacticos.length} Corrección(es) Sintáctica(s) Requerida(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final err in diag.erroresSintacticos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            err,
                            style: TextStyle(fontSize: 11.5, color: p.text),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 3. Salida Estimada en Consola (Simulación)
        if (diag.salidaSimulada != null) ...[
          Container(
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
                    const Icon(
                      Icons.terminal_rounded,
                      size: 15,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Salida Estimada en Consola (Simulación)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    diag.salidaSimulada!,
                    style: TextStyle(
                      fontFamily: AppFonts.monoFallback.first,
                      fontSize: 12,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4. Variables Detectadas en Memoria
        if (diag.variables.isNotEmpty) ...[
          Text(
            'VARIABLES EN MEMORIA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: p.subtle,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: diag.variables
                .map(
                  (v) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.borderSoft),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              v.nombre,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: p.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${v.tipoDato})',
                              style: TextStyle(fontSize: 10, color: p.subtle),
                            ),
                          ],
                        ),
                        Text(
                          v.rolPedagogico,
                          style: TextStyle(fontSize: 10, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
        ],

        // 5. Desglose Línea por Línea
        Text(
          'EXPLICACIÓN LÍNEA POR LÍNEA EN TIEMPO REAL',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: p.subtle,
          ),
        ),
        const SizedBox(height: 8),
        for (final l in diag.lineas)
          if (l.tipo != 'espacio')
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: l.tieneError
                    ? AppColors.danger.withValues(alpha: 0.08)
                    : p.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: l.tieneError
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : p.borderSoft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: l.tieneError ? AppColors.danger : p.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'L${l.numeroLinea}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.codigoOriginal.trim(),
                          style: TextStyle(
                            fontFamily: AppFonts.monoFallback.first,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _badgeTipoLinea(l.tipo, p),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.explicacionDidactica,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: p.muted,
                      height: 1.35,
                    ),
                  ),
                  if (l.errorSintactico != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 13,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            l.errorSintactico!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (l.correccionSugerida != null)
                          FilledButton.tonal(
                            onPressed: () => _aplicarCorreccion(
                              l.numeroLinea,
                              l.correccionSugerida!,
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            child: const Text(
                              'Corregir',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }

  Widget _badgeTipoLinea(String tipo, AppPalette p) {
    Color color;
    String label;
    switch (tipo) {
      case 'variable':
        color = p.primary;
        label = 'Variable';
        break;
      case 'condicional':
        color = Colors.orange;
        label = 'Condicional';
        break;
      case 'bucle':
        color = Colors.purple;
        label = 'Bucle';
        break;
      case 'funcion':
        color = Colors.teal;
        label = 'Función';
        break;
      case 'clase':
        color = Colors.indigo;
        label = 'Clase';
        break;
      case 'print':
        color = AppColors.success;
        label = 'Consola';
        break;
      case 'pregunta':
        color = AppColors.accent;
        label = 'Pregunta';
        break;
      case 'comentario':
        color = p.subtle;
        label = 'Comentario';
        break;
      default:
        color = p.muted;
        label = 'Código';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _metricasView(
    AppPalette p,
    Map<String, dynamic> stats,
    DiagnosticoAutomatico diag,
  ) {
    final funciones = stats['nombresFunciones'] as List<String>;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text(
            'Telemetría Estructural del Código',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          _metricRow(p, 'Líneas totales de código', '${stats["lineas"]}'),
          _metricRow(
            p,
            'Variables detectadas en memoria',
            '${diag.variables.length}',
          ),
          _metricRow(p, 'Funciones declaradas', '${stats["funciones"]}'),
          _metricRow(p, 'Clases declaradas', '${stats["clases"]}'),
          _metricRow(
            p,
            'Estructuras condicionales (if/elif/else)',
            '${diag.estructuras.where((e) => e.tipo == 'if' || e.tipo == 'elif' || e.tipo == 'else').length}',
          ),
          _metricRow(
            p,
            'Estructuras de bucle (for/while)',
            '${stats["bucles"]}',
          ),
          _metricRow(p, 'Módulos importados', '${stats["imports"]}'),
          _metricRow(
            p,
            'Complejidad estimada por bucles',
            '${stats["complejidad"]}',
          ),
          const SizedBox(height: 16),
          if (diag.variables.isNotEmpty) ...[
            Text(
              'Variables en Memoria y Roles:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: diag.variables
                  .map(
                    (v) => Chip(
                      label: Text(
                        '${v.nombre}: ${v.tipoDato}',
                        style: TextStyle(fontSize: 11, color: p.primary),
                      ),
                      backgroundColor: p.surface2,
                      side: BorderSide(color: p.borderSoft),
                      padding: EdgeInsets.zero,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (funciones.isNotEmpty) ...[
            Text(
              'Funciones Declaradas:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: funciones
                  .map(
                    (f) => Chip(
                      label: Text(
                        'def $f()',
                        style: TextStyle(fontSize: 11, color: p.primary),
                      ),
                      backgroundColor: p.surface2,
                      side: BorderSide(color: p.borderSoft),
                      padding: EdgeInsets.zero,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(AppPalette p, String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: p.surface2.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
          Text(
            valor,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: p.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio(AppPalette p) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology_alt_outlined,
            size: 42,
            color: p.subtle.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Listo para explicar tu código',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Presiona "Explicar" arriba para recibir una explicación adaptada.',
            style: TextStyle(fontSize: 11.5, color: p.subtle),
          ),
        ],
      ),
    );
  }

  Widget _selectorModo(AppPalette p) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.borderSoft),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ModoExplicacion>(
          value: _modo,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: p.muted),
          style: TextStyle(fontSize: 11.5, color: p.text),
          items: ModoExplicacion.values.map((m) {
            return DropdownMenuItem(value: m, child: Text(m.label));
          }).toList(),
          onChanged: (m) {
            if (m != null) setState(() => _modo = m);
          },
        ),
      ),
    );
  }

  Widget _selectorNivel(AppPalette p) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.borderSoft),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _nivel,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: p.muted),
          style: TextStyle(fontSize: 11.5, color: p.text),
          items: const [
            DropdownMenuItem(
              value: 'principiante',
              child: Text('Nivel: Principiante'),
            ),
            DropdownMenuItem(
              value: 'intermedio',
              child: Text('Nivel: Intermedio'),
            ),
            DropdownMenuItem(value: 'avanzado', child: Text('Nivel: Avanzado')),
          ],
          onChanged: (n) {
            if (n != null) setState(() => _nivel = n);
          },
        ),
      ),
    );
  }

  Widget _tabsArchivos(AppPalette p) {
    return Container(
      height: 34,
      color: p.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _archivos.length,
        itemBuilder: (_, i) {
          final a = _archivos[i];
          final activo = a.key == _nombreArchivo;
          return Container(
            margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: activo ? p.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: activo ? p.primary : p.borderSoft),
            ),
            child: Row(
              children: [
                Text(
                  a.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: activo ? p.text : p.muted,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _cerrarArchivo(a.key),
                  child: Icon(Icons.close, size: 12, color: p.subtle),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
