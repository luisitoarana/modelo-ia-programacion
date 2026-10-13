import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../lib/api.dart';
import '../lib/providers.dart';
import '../lib/screens/login_screen.dart';
import '../lib/theme.dart';

void main() {
  testWidgets('permite abrir el registro de estudiantes desde la app', (tester) async {
    final api = ApiClient();
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AuthProvider(api))],
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );
    await tester.tap(find.text('¿No tienes cuenta? Crear usuario aquí'));
    // El fondo de la pantalla anima continuamente y nunca llega a settle.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Nombre completo'), findsOneWidget);
    expect(find.text('Confirmar contraseña'), findsOneWidget);
    expect(find.text('Crear cuenta de estudiante'), findsOneWidget);
  });
}
