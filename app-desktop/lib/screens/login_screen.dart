import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreCtrl = TextEditingController();
  final _nivelCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _cargando = false;
  bool _registrando = false;
  String? _errorFormulario;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _nivelCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_cargando) return;
    if (_registrando &&
        (_nombreCtrl.text.trim().length < 2 ||
         _passCtrl.text.length < 8 ||
         _passCtrl.text != _confirmarCtrl.text)) {
      setState(() => _errorFormulario =
          'Escribe tu nombre, una contraseña de al menos 8 caracteres y confírmala.');
      return;
    }
    setState(() => _errorFormulario = null);
    setState(() => _cargando = true);
    final auth = context.read<AuthProvider>();
    final ok = _registrando
        ? await auth.registrarEstudiante(
            nombre: _nombreCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            nivelAcademico: _nivelCtrl.text.trim(),
          )
        : await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted) setState(() => _cargando = false);
    if (ok && mounted) {
      context.read<ChatProvider>().cargarConversaciones();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          // Fondo ambiental con orbs flotantes que se mueven muy lentamente.
          // Le da al login un aire premium estilo Stripe / Linear.
          const Positioned.fill(child: AmbientBackground(intensity: 0.55)),
          // Contenido: card animada de entrada.
          Center(
            child: SingleChildScrollView(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                tween: Tween(begin: 0.0, end: 1.0),
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 12),
                    child: child,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      // Gradiente sutil para añadir profundidad sin ruido.
                      gradient: p.surfaceGradient,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: p.borderSoft),
                      // Elevación nivel 4 (modal) + halo terracota propio.
                      boxShadow: [
                        ...p.elevation(4),
                        BoxShadow(
                          color: p.primary.withValues(alpha: 0.06),
                          blurRadius: 72,
                          spreadRadius: -8,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo con gradiente diagonal + glow sutil.
                        Center(
                          child: Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              gradient: p.primaryGradient,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              boxShadow: [
                                BoxShadow(
                                  color: p.primary.withValues(alpha: 0.42),
                                  blurRadius: 22,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const BrandLogo(
                                size: 30,
                                color: Colors.white,
                              ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          AppConfig.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                color: p.text,
                                fontSize: 22,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tu asistente educativo de Python',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 13.5,
                              height: 1.4),
                        ),
                        const SizedBox(height: 28),
                        if (_registrando) ...[
                          _campo(p, _nombreCtrl, 'Nombre completo', Icons.person_outline),
                          const SizedBox(height: 12),
                          _campo(p, _nivelCtrl, 'Semestre o nivel académico (opcional)', Icons.school_outlined),
                          const SizedBox(height: 12),
                        ],
                        _campo(p, _emailCtrl, 'Correo', Icons.mail_outline),
                        const SizedBox(height: 12),
                        _campo(p, _passCtrl, 'Contraseña',
                            Icons.lock_outline,
                            obscure: true),
                        if (_registrando) ...[
                          const SizedBox(height: 12),
                          _campo(p, _confirmarCtrl, 'Confirmar contraseña',
                              Icons.lock_outline, obscure: true),
                        ],
                        if (auth.error != null || _errorFormulario != null) ...[
                          const SizedBox(height: 14),
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 250),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (_, t, child) => Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(0, (1 - t) * 4),
                                child: child,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.danger
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.danger
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: AppColors.danger,
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorFormulario ?? auth.error!,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        if (_registrando)
                          FilledButton(
                            onPressed: _cargando ? null : _entrar,
                            child: Text(_cargando ? 'Creando cuenta…' : 'Crear cuenta de estudiante'),
                          )
                        else
                          _BotonEntrar(cargando: _cargando, onTap: _entrar),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: _cargando ? null : () => setState(() {
                            _registrando = !_registrando;
                            _errorFormulario = null;
                          }),
                          child: Text(_registrando
                              ? 'Ya tengo cuenta: iniciar sesión'
                              : '¿No tienes cuenta? Crear usuario aquí'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tu cuenta se guarda en el servidor del sistema y sirve también para la web.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: p.subtle, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(AppPalette p, TextEditingController ctrl, String label,
      IconData icon,
      {bool obscure = false}) {
    return _CampoAnimado(
      controller: ctrl,
      label: label,
      icon: icon,
      obscure: obscure,
      onSubmitted: _entrar,
    );
  }
}

/// Input animado: el borde gana color terracota al hacer focus + tiny scale.
class _CampoAnimado extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final VoidCallback onSubmitted;

  const _CampoAnimado({
    required this.controller,
    required this.label,
    required this.icon,
    required this.obscure,
    required this.onSubmitted,
  });

  @override
  State<_CampoAnimado> createState() => _CampoAnimadoState();
}

class _CampoAnimadoState extends State<_CampoAnimado> {
  final FocusNode _focus = FocusNode();
  bool _enfocado = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _enfocado = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: _enfocado
            ? [
                BoxShadow(
                  color: p.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscure,
        onSubmitted: (_) => widget.onSubmitted(),
        style: TextStyle(color: p.text, fontSize: 14),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(color: p.muted, fontSize: 13),
          prefixIcon: Icon(
            widget.icon,
            color: _enfocado ? p.primary : p.muted,
            size: 18,
          ),
          filled: true,
          fillColor: p.surface2,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Botón Entrar con hover + animación de scale al pulsar.
class _BotonEntrar extends StatefulWidget {
  final bool cargando;
  final VoidCallback onTap;
  const _BotonEntrar({required this.cargando, required this.onTap});

  @override
  State<_BotonEntrar> createState() => _BotonEntrarState();
}

class _BotonEntrarState extends State<_BotonEntrar> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            height: 48,
            decoration: BoxDecoration(
              // Gradiente diagonal en lugar de color plano.
              gradient: p.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: [
                BoxShadow(
                  color: p.primary.withValues(alpha: _hover ? 0.40 : 0.24),
                  blurRadius: _hover ? 20 : 12,
                  spreadRadius: _hover ? -2 : -1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                onTap: widget.cargando ? null : widget.onTap,
                borderRadius: BorderRadius.circular(AppRadius.md),
                // Sutil veil claro al hover encima del gradiente.
                splashColor: Colors.white.withValues(alpha: 0.18),
                hoverColor: Colors.white.withValues(alpha: 0.06),
                child: Center(
                  child: widget.cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Entrar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
