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
  String respuesta = '```python\nprint(2)\n```';
  Completer<void>? espera;

  @override
  Future<Map<String, dynamic>> tareasEstudio() async => {
    'tareas': [
      {
        'id': 'm1_1',
        'modulo': 1,
        'competencia': 'Variables',
        'consigna': 'Pide código para mostrar una edad.',
        'solicitud': 'Crea código para mostrar una edad.',
      },
    ],
  };

  @override
  Future<String> crearConversacion(String titulo) async {
    conversaciones++;
    return 'editor-1';
  }

  @override
  Future<Map<String, dynamic>> validarSintaxisPython(String codigo) async => {
    'valido': true,
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
    'solo código: genera desde una tarea y aplica correcciones sucesivas en el mismo archivo',
    (tester) async {
      final api = _ApiEditor();
      await _montar(tester, api, soloCodigo: true);
      await _nuevo(tester, 'inicial.py');
      await tester.ensureVisible(find.text('Práctica: generar código'));
      await tester.tap(find.text('Práctica: generar código'));
      await tester.pumpAndSettle();
      expect(find.text('Copiar consigna'), findsOneWidget);
      await tester.tap(find.text('Generar código'));
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
