import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:app_desktop/api.dart';
import 'package:app_desktop/providers.dart';
import 'package:app_desktop/widgets/estudio_docente.dart';

class _ApiEstudio extends ApiClient {
  Map<String, dynamic>? guardada;
  @override
  Future<Map<String, dynamic>> configuracionEstudio() async => {
    'estudio_activo': false,
    'pre_abierto': false,
    'post_abierto': false,
    'practica_guiada': true,
    'preguntas_activas': ['m1_1', 'm2_1', 'm3_1'],
    'banco': [
      for (var m = 1; m <= 3; m++)
        {
          'id': 'm${m}_1',
          'modulo': m,
          'competencia': 'Competencia $m',
          'pre': 'Pre $m',
          'post': 'Post $m',
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> resumenEstudio() async => {
    'participantes': [],
    'entregas': [],
  };
  @override
  Future<void> configurarEstudio(Map<String, dynamic> datos) async {
    guardada = datos;
  }
}

void main() {
  testWidgets(
    'el docente abre el pretest y aplica la configuración al servidor',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _ApiEstudio();
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api),
          child: const MaterialApp(home: Scaffold(body: EstudioDocente())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir pretest'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aplicar activación y preguntas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar activación y preguntas'));
      await tester.pumpAndSettle();
      expect(api.guardada!['pre_abierto'], isTrue);
      expect(api.guardada!['post_abierto'], isFalse);
      expect(api.guardada!['preguntas_activas'], ['m1_1', 'm2_1', 'm3_1']);
      expect(api.guardada!.containsKey('estudio_activo'), isTrue);
      expect(
        find.text('Configuración aplicada en el servidor.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
