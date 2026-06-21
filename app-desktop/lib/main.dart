import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'config.dart';
import 'providers.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/i18n.dart';
import 'theme.dart';
import 'widgets/artifacts_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await I18n.instance.cargar();
  final api = ApiClient();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..cargar()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..cargar()),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)..cargarSesion()),
        ChangeNotifierProvider(create: (_) => ChatProvider(api)..cargarOrden()),
        ChangeNotifierProvider(create: (_) => ArtifactsProvider()),
      ],
      child: const ExplicadorApp(),
    ),
  );
}

class ExplicadorApp extends StatelessWidget {
  const ExplicadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    // ValueListenableBuilder externo: rebuilds toda la app cuando cambia
    // el idioma de UI. Como las cadenas se leen vía I18n.t() en cada build,
    // todos los widgets descendientes se actualizan automáticamente.
    return ValueListenableBuilder<UiLang>(
      valueListenable: I18n.instance.idioma,
      builder: (_, __, ___) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(paletaId: themeProvider.paletaId),
          darkTheme: AppTheme.dark(paletaId: themeProvider.paletaId),
          themeMode: themeProvider.mode,
          home: const _Gate(),
        );
      },
    );
  }
}

/// Decide entre login y home según el estado de autenticación.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return auth.autenticado ? const HomeScreen() : const LoginScreen();
  }
}
