import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/api.dart';
import '../lib/models.dart';
import '../lib/providers.dart';
import '../lib/theme.dart';
import '../lib/widgets/code_view.dart';

class _ApiEditor extends ApiClient {
  final ids = <String>[];
  final preguntas = <String>[];
  final modos = <String?>[];
  int conversaciones = 0;
  bool falla = false;
  bool propuestaInvalida = false;
  String respuesta = '```python\nprint(2)\n```';
  Completer<void>? espera;

  @override
  Future<String> crearConversacion(String titulo) async {
    conversaciones++;
    return 'editor-1';
  }

  @override
  Future<Map<String, dynamic>> validarSintaxisPython(String codigo) async => {
    'valido': true,
    'valido_para_aplicar': !propuestaInvalida,
    'mensaje': propuestaInvalida ? "undefined name 'nota'" : 'Sintaxis válida',
  };

  @override
  Future<RespuestaEnvio> enviarMensaje(
    String convId,
    String contenido, {
    String idioma = 'es',
    bool buscarWeb = false,
    String proveedor = 'auto',
    String? modoAcompanamiento,
    String? nivelModulo,
  }) async {
    ids.add(convId);
    modos.add(modoAcompanamiento);
    preguntas.add(contenido);
    if (falla) {
      falla = false;
      throw ApiException('Motor ocupado');
    }
    await espera?.future;
    return RespuestaEnvio(
      conversacionId: convId,
      titulo: 'Editor',
      mensajeUsuario: Mensaje(id: 'u', rol: 'usuario', contenido: contenido),
      mensajeAsistente: Mensaje(
        id: 'a',
        rol: 'asistente',
        contenido: respuesta,
      ),
    );
  }
}

Future<void> _montar(
  WidgetTester tester,
  _ApiEditor api, {
  bool soloCodigo = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider();
  if (soloCodigo) await settings.setModoAcompanamiento('sin_acompanamiento');
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CodeView()),
      ),
    ),
  );
}

Future<void> _nuevo(WidgetTester tester, String nombre) async {
  await tester.tap(find.byTooltip('Nuevo'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'sin_titulo.py'),
    nombre,
  );
  await tester.tap(find.text('Crear'));
  await tester.pumpAndSettle();
}

Future<void> _enviar(WidgetTester tester, String pregunta) async {
  tester
      .widget<TextField>(find.byKey(const ValueKey('editor-pregunta')))
      .onSubmitted!(pregunta);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _codigo(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('editor-codigo')))
    .controller!
    .text;

void main() {
  testWidgets(
    'no aplica una propuesta con nombres indefinidos aunque su sintaxis sea válida',
    (tester) async {
      final api = _ApiEditor()
        ..propuestaInvalida = true
        ..respuesta = '```python\nprint(nota)\n```';
      await _montar(tester, api, soloCodigo: true);
      await _nuevo(tester, 'actual.py');
      await tester.enterText(
        find.byKey(const ValueKey('editor-codigo')),
        'print(1)',
      );
      await _enviar(tester, 'Corrige este archivo');
      expect(_codigo(tester), 'print(1)');
      expect(find.textContaining("undefined name 'nota'"), findsWidgets);
      expect(find.text('Generando respuesta...'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'imprime un nombre abre otra creación sin arrastrar el archivo anterior',
    (tester) async {
      final api = _ApiEditor()..respuesta = '```python\nprint("Luis")\n```';
      await _montar(tester, api, soloCodigo: true);
      await _nuevo(tester, 'suma.py');
      await tester.enterText(
        find.byKey(const ValueKey('editor-codigo')),
        'print(100+200)',
      );
      await _enviar(tester, 'Imprime el nombre Luis');
      expect(api.preguntas.last, contains('[EDITOR_OPERACION:crear]'));
      expect(api.preguntas.last, isNot(contains('100+200')));
      expect(_codigo(tester), 'print("Luis")');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'solo código: genera desde una pregunta del módulo y aplica correcciones sucesivas en el mismo archivo',
    (tester) async {
      final api = _ApiEditor();
      await _montar(tester, api, soloCodigo: true);
      await _nuevo(tester, 'inicial.py');
      await tester.ensureVisible(find.text('Preguntas de los módulos'));
      await tester.tap(find.text('Preguntas de los módulos'));
      await tester.pumpAndSettle();
      expect(find.text('Copiar pregunta'), findsWidgets);
      expect(find.textContaining('Ver Pistas'), findsNothing);
      await tester.tap(find.text('Generar código').first);
      await tester.pumpAndSettle();
      expect(_codigo(tester), 'print(2)');
      api.respuesta = '```python\nprint(3)\n```';
      await _enviar(tester, 'Genera la corrección, no funciona');
      expect(_codigo(tester), 'print(3)');
      expect(api.preguntas.last, contains('Código actual en el editor'));
      expect(api.preguntas.last, contains('print(2)'));
      api.respuesta = '```python\nprint(4)\n```';
      await _enviar(tester, 'Me da error, repara el archivo');
      expect(_codigo(tester), 'print(4)');
      expect(api.modos.toSet(), {'sin_acompanamiento'});
      expect(api.conversaciones, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'corrige con cursor -1, conserva conversación y recupera un fallo',
    (tester) async {
      final api = _ApiEditor();
      await _montar(tester, api);
      await _nuevo(tester, 'primero.py');
      await tester.enterText(
        find.byKey(const ValueKey('editor-codigo')),
        'print(1)',
      );
      tester
          .widget<TextField>(find.byKey(const ValueKey('editor-codigo')))
          .controller!
          .selection = const TextSelection.collapsed(
        offset: -1,
      );
      await _enviar(tester, 'Corrige el archivo para mostrar 2');
      expect(_codigo(tester), 'print(2)');
      expect(api.preguntas.single, contains('print(1)'));
      expect(find.text('Generando respuesta...'), findsNothing);

      api.respuesta = '¿Quieres que corrija la salida para mostrar 3?';
      await _enviar(tester, '¿Se puede mostrar 3?');
      api.respuesta = '```python\nprint(3)\n```';
      await _enviar(tester, 'Sí');
      expect(_codigo(tester), 'print(3)');
      expect(api.preguntas.last, contains('Aplica la corrección'));

      api.falla = true;
      await _enviar(tester, 'Corrige nuevamente');
      expect(find.text('Generando respuesta...'), findsNothing);
      api.respuesta = '```python\nprint(4)\n```';
      await _enviar(tester, 'Ahora cambia la salida a 4');
      expect(_codigo(tester), 'print(4)');
      expect(api.conversaciones, 1);
      expect(api.ids.toSet(), {'editor-1'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cambiar pestaña durante una respuesta no reemplaza otro archivo',
    (tester) async {
      final api = _ApiEditor()..espera = Completer<void>();
      await _montar(tester, api);
      await _nuevo(tester, 'primero.py');
      await tester.enterText(
        find.byKey(const ValueKey('editor-codigo')),
        'print(1)',
      );
      await _enviar(tester, 'Corrige para mostrar 2');
      // No pumpAndSettle mientras el indicador está girando.
      await tester.tap(find.byTooltip('Nuevo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(
        find.widgetWithText(TextField, 'sin_titulo.py'),
        'segundo.py',
      );
      await tester.tap(find.text('Crear'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(_codigo(tester), '');
      api.espera!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_codigo(tester), '');
      await tester.tap(find.text('primero.py').first);
      await tester.pump();
      expect(_codigo(tester), 'print(2)');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
