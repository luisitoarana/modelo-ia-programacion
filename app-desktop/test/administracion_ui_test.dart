import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app_desktop/api.dart';
import 'package:app_desktop/models.dart';
import 'package:app_desktop/providers.dart';
import 'package:app_desktop/screens/home_screen.dart';
import 'package:app_desktop/theme.dart';
import 'package:app_desktop/widgets/settings/section_administracion.dart';
import 'package:app_desktop/widgets/sidebar.dart';

class _ApiDocente extends ApiClient {
  @override
  Future<Map<String, dynamic>> estadoModelo() async => {};
  @override
  Future<Map<String, dynamic>> resumenAdmin() async => {'usuarios': 2};
  @override
  Future<List<Map<String, dynamic>>> usuariosAdmin() async => [];
  @override
  Future<List<Map<String, dynamic>>> intentosDocente({int offset = 0}) async => [
    {
      'id': '1', 'usuario_id': 'ana', 'usuario_nombre': 'Ana',
      'usuario_email': 'ana@example.test', 'fase': 'pre',
      'leccion_id': 'm1_l1_variables', 'pregunta': '¿Qué guarda edad?',
      'codigo_inicial': 'edad = 20', 'codigo_final': 'print(20)',
      'prediccion': 'Mostrará 20', 'explicacion_propia': 'Guarda la edad.',
    },
    {
      'id': '2', 'usuario_id': 'bea', 'usuario_nombre': 'Bea',
      'usuario_email': 'bea@example.test', 'fase': 'post',
      'leccion_id': 'm1_l1_variables', 'pregunta': '¿Qué guarda edad?',
      'codigo_inicial': 'edad = 21', 'codigo_final': 'print(21)',
      'prediccion': 'Mostrará 21', 'explicacion_propia': 'Guarda un número.',
    },
  ];
}

class _AuthDocente extends AuthProvider {
  final String rol;
  _AuthDocente(super.api, this.rol);
  @override
  Usuario get usuario => Usuario(id: 'docente', nombre: 'Luis',
      email: 'luis@example.test', rol: rol);
}

Widget _app(Widget home, {String rol = 'administrador'}) {
  final api = _ApiDocente();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthDocente(api, rol)),
      ChangeNotifierProvider(create: (_) => ChatProvider(api)),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: home)),
  );
}

void main() {
  testWidgets('el administrador abre la revisión directamente desde el menú', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(Row(children: [
      Sidebar(vista: VistaPrincipal.chat, onCambiarVista: (_) {}, onToggleColapsado: () {}),
    ])));
    expect(find.text('Administración'), findsOneWidget);
    await tester.tap(find.text('Administración'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Administración y revisión docente'), findsOneWidget);
    expect(find.text('Exportar CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el estudiante no recibe el acceso de administración', (tester) async {
    await tester.pumpWidget(_app(Row(children: [
      Sidebar(vista: VistaPrincipal.chat, onCambiarVista: (_) {}, onToggleColapsado: () {}),
    ]), rol: 'estudiante'));
    expect(find.text('Administración'), findsNothing);
  });

  testWidgets('la revisión muestra pregunta y código inicial y filtra por fase', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(const SingleChildScrollView(
      child: Padding(padding: EdgeInsets.all(20), child: AdministracionSection()),
    )));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Ana · m1_l1_variables'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byWidgetPredicate((w) => w is SelectableText &&
        (w.data?.contains('Código inicial:\nedad = 20') ?? false) &&
        (w.data?.contains('¿Qué guarda edad?') ?? false)), findsOneWidget);
    await tester.tap(find.text('Todas las fases'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Pre-test').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 intentos del filtro · 2 cargados'), findsOneWidget);
    expect(find.text('Bea · m1_l1_variables'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
