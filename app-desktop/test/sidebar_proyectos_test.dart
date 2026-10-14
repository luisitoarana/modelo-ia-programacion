import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app_desktop/api.dart';
import 'package:app_desktop/models.dart';
import 'package:app_desktop/providers.dart';
import 'package:app_desktop/screens/home_screen.dart';
import 'package:app_desktop/theme.dart';
import 'package:app_desktop/widgets/code/divisores.dart';
import 'package:app_desktop/widgets/sidebar.dart';

class _FakeApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> estadoModelo() async => {};
  @override
  Future<List<ConversacionResumen>> listarConversaciones() async => [];
}

class _FakeAuth extends AuthProvider {
  _FakeAuth(super.api);
  @override
  Usuario get usuario => Usuario(id: 'est1', nombre: 'Estudiante', email: 'est@test.com', rol: 'estudiante');
}

Widget _crearWidgetPrueba({
  required SettingsProvider settings,
  bool colapsado = false,
  VoidCallback? onToggle,
}) {
  final api = _FakeApi();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider(api)),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(api)),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(paletaId: 'obsidiana'),
      home: Scaffold(
        body: Sidebar(
          vista: VistaPrincipal.chat,
          onCambiarVista: (_) {},
          colapsado: colapsado,
          onToggleColapsado: onToggle ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Sidebar muestra estado de proyectos limpio sin hardcodear repositorio del sistema', (tester) async {
    final settings = SettingsProvider();

    await tester.pumpWidget(
      _crearWidgetPrueba(
        settings: settings,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Verificar que NO aparece el repositorio del sistema
    expect(find.text('sistema-explicador-python-ia'), findsNothing);

    // 2. Verificar que se muestra la opción limpia de abrir proyecto
    expect(find.text('Abrir carpeta...'), findsOneWidget);
    expect(find.text('Ningún proyecto abierto'), findsOneWidget);

    // 3. Verificar presencia del DivisorVertical para redimensionar (<-->)
    expect(find.byType(DivisorVertical), findsOneWidget);

    // 4. Cambiar carpeta de proyecto a un proyecto de prueba (ej: bot-autonomo)
    settings.setCarpetaProyecto('C:/proyectos/bot-autonomo');
    await tester.pump(const Duration(milliseconds: 200));

    // 5. Verificar que ahora se muestra el proyecto activo
    expect(find.text('bot-autonomo'), findsOneWidget);
    expect(find.text('Ningún proyecto abierto'), findsNothing);
  });

  testWidgets('Clic en Explicador IA activa callback de colapsado/expandido', (tester) async {
    final settings = SettingsProvider();
    bool toggleLlamado = false;

    await tester.pumpWidget(
      _crearWidgetPrueba(
        settings: settings,
        colapsado: false,
        onToggle: () => toggleLlamado = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Clic en el título "Explicador IA" en el encabezado
    final titulo = find.text('Explicador IA');
    expect(titulo, findsWidgets);
    await tester.tap(titulo.first);
    await tester.pump(const Duration(milliseconds: 200));

    expect(toggleLlamado, isTrue);
  });
}
