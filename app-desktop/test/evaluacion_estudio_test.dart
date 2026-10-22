import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:app_desktop/api.dart';
import 'package:app_desktop/providers.dart';
import 'package:app_desktop/widgets/evaluacion_estudio.dart';

class _Api extends ApiClient {
  Map<String, dynamic>? enviada;
  bool falla = false;
  bool preview = false;
  int revision = 1;
  Map<String, dynamic> entrega([bool finalizada = false]) => {
    'id': 'entrega-1',
    'fase': 'pre',
    'version': 'piloto-6-v1',
    'estado': finalizada ? 'enviado' : 'borrador',
    'revision': revision,
    'iniciada_en': '2026-10-22T12:00:00Z',
    'enviada_en': finalizada ? '2026-10-22T12:10:00Z' : null,
    'preguntas': [
      {
        'id': 'm1_1',
        'modulo': 1,
        'competencia': 'Variables',
        'consigna': 'Muestra Ana y su edad.',
      },
    ],
    'respuestas': enviada ?? {},
  };
  @override
  Future<Map<String, dynamic>> vistaPreviaEvaluacion(String fase) async {
    preview = true;
    return {'fase': fase, 'version': 'piloto-6-v1',
      'abierto_estudiantes': false, 'preguntas': entrega()['preguntas']};
  }
  @override
  Future<Map<String, dynamic>> estudioActual() async => {
    'fase': 'pre',
    'abierto': true,
    'entrega': null,
  };
  @override
  Future<Map<String, dynamic>> iniciarEvaluacion() async {
    expect(preview, isFalse, reason: 'Una vista previa no crea una entrega real');
    return entrega();
  }
  @override
  Future<Map<String, dynamic>> guardarEvaluacion(
    String id,
    Map<String, dynamic> respuestas,
    int rev, {
    bool finalizar = false,
  }) async {
    expect(preview, isFalse, reason: 'Una vista previa no guarda respuestas reales');
    if (falla) throw ApiException('Sin conexión');
    expect(id, 'entrega-1');
    expect(rev, revision);
    enviada = respuestas;
    revision++;
    return entrega(finalizar);
  }
}

Future<void> montar(WidgetTester tester, _Api api) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()
            ..setAsignacionEstudio({
              'asignado': true,
              'fase': 'pre',
              'modo_efectivo': 'bloqueado_post_test',
            }),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: EvaluacionEstudio())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Iniciar evaluación'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('vista previa docente permite responder con evaluación cerrada sin enviar datos', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ], child: const MaterialApp(home: Scaffold(body: EvaluacionEstudio(vistaPrevia: 'post')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('SIMULACIÓN DOCENTE'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('evaluacion-codigo-m1_1')), 'print(20)');
    await tester.ensureVisible(find.text('Guardar borrador'));
    await tester.tap(find.text('Guardar borrador'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar evaluación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    expect(find.text('Simulación completada. No se envió una entrega de estudiante.'), findsOneWidget);
    expect(api.enviada, isNull);
    expect(api.preview, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'guarda código y explicación breve; entrega final queda de solo lectura',
    (tester) async {
      final api = _Api();
      await montar(tester, api);
      await tester.enterText(
        find.byKey(const ValueKey('evaluacion-codigo-m1_1')),
        "print('Ana')",
      );
      await tester.enterText(
        find.byKey(const ValueKey('evaluacion-texto-m1_1')),
        'Muestra Ana.',
      );
      await tester.ensureVisible(find.text('Guardar borrador'));
      await tester.tap(find.text('Guardar borrador'));
      await tester.pumpAndSettle();
      expect(api.enviada!['m1_1']['explicacion'], 'Muestra Ana.');
      await tester.tap(find.text('Entregar evaluación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Entrega recibida por el servidor:'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('evaluacion-codigo-m1_1')),
            )
            .readOnly,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('fallo de red no simula guardado ni borra lo escrito', (
    tester,
  ) async {
    final api = _Api()..falla = true;
    await montar(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('evaluacion-texto-m1_1')),
      'No estoy seguro.',
    );
    await tester.ensureVisible(find.text('Guardar borrador'));
    await tester.tap(find.text('Guardar borrador'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se confirmó el guardado'), findsOneWidget);
    expect(api.enviada, isNull);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('evaluacion-texto-m1_1')),
          )
          .controller!
          .text,
      'No estoy seguro.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
