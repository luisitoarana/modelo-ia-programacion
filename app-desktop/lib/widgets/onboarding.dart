import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/i18n.dart';
import '../theme.dart';

const _kKeyCompletado = 'explicador.onboarding_v1';

/// Onboarding interactivo de 5 slides. Se invoca con showOnboarding(context).
/// Devuelve true si lo completó, false si lo saltó.
///
/// Auto-cierre con Esc, navegación con ←→ Enter.
/// Marca completado en SharedPreferences para no mostrarse de nuevo.
Future<bool> showOnboarding(BuildContext context) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false, // no se cierra por click fuera
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, anim, _) => const _OnboardingContent(),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
  if (result ?? false) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyCompletado, true);
  }
  return result ?? false;
}

/// Comprueba si el onboarding ya se completó; si no, lo lanza.
Future<void> mostrarOnboardingSiPrimeraVez(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final completado = prefs.getBool(_kKeyCompletado) ?? false;
  if (completado) return;
  // Delay para que la UI haya pintado.
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (context.mounted) await showOnboarding(context);
}

class _Slide {
  final IconData icono;
  final String tituloKey;
  final String subtituloKey;
  final String? descKey;
  final bool esAtajos;
  const _Slide({
    required this.icono,
    required this.tituloKey,
    required this.subtituloKey,
    this.descKey,
    this.esAtajos = false,
  });
}

const _slides = [
  _Slide(icono: Icons.auto_awesome, tituloKey: 'tour.1.titulo', subtituloKey: 'tour.1.subtitulo', descKey: 'tour.1.desc'),
  _Slide(icono: Icons.chat_bubble_outline, tituloKey: 'tour.2.titulo', subtituloKey: 'tour.2.subtitulo', descKey: 'tour.2.desc'),
  _Slide(icono: Icons.keyboard, tituloKey: 'tour.3.titulo', subtituloKey: 'tour.3.subtitulo', esAtajos: true),
  _Slide(icono: Icons.palette_outlined, tituloKey: 'tour.4.titulo', subtituloKey: 'tour.4.subtitulo', descKey: 'tour.4.desc'),
  _Slide(icono: Icons.mic_none, tituloKey: 'tour.5.titulo', subtituloKey: 'tour.5.subtitulo', descKey: 'tour.5.desc'),
];

const _atajosPreview = [
  ('Ctrl + K', 'Búsqueda global'),
  ('Ctrl + N', 'Nuevo chat'),
  ('Ctrl + ,', 'Configuración'),
  ('Ctrl + /', 'Ver atajos'),
];

class _OnboardingContent extends StatefulWidget {
  const _OnboardingContent();

  @override
  State<_OnboardingContent> createState() => _OnboardingContentState();
}

class _OnboardingContentState extends State<_OnboardingContent> {
  int _paso = 0;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _avanzar() {
    if (_paso < _slides.length - 1) {
      setState(() => _paso++);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _atras() {
    if (_paso > 0) setState(() => _paso--);
  }

  void _saltar() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final slide = _slides[_paso];

    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: (evt) {
        if (evt is! KeyDownEvent) return;
        if (evt.logicalKey == LogicalKeyboardKey.escape) {
          _saltar();
        } else if (evt.logicalKey == LogicalKeyboardKey.arrowRight ||
            evt.logicalKey == LogicalKeyboardKey.enter) {
          _avanzar();
        } else if (evt.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _atras();
        }
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.borderSoft),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // Botón saltar
                  Positioned(
                    right: 10,
                    top: 10,
                    child: IconButton(
                      tooltip: I18n.t('tour.saltar'),
                      onPressed: _saltar,
                      icon: Icon(Icons.close, size: 18, color: p.muted),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cuerpo
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(32, 44, 32, 20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.03, 0),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey(_paso),
                            children: [
                              Container(
                                height: 64,
                                width: 64,
                                decoration: BoxDecoration(
                                  color:
                                      p.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(slide.icono,
                                    size: 30, color: p.primary),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                I18n.t(slide.tituloKey),
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                        color: p.text,
                                        fontSize: 22),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                I18n.t(slide.subtituloKey),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (slide.esAtajos)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: p.surface
                                        .withValues(alpha: 0.5),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border:
                                        Border.all(color: p.borderSoft),
                                  ),
                                  child: Column(
                                    children: [
                                      for (final a in _atajosPreview)
                                        Padding(
                                          padding: const EdgeInsets
                                              .symmetric(vertical: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(a.$2,
                                                    style: TextStyle(
                                                        fontSize: 12.5,
                                                        color: p.text)),
                                              ),
                                              _KbdMini(combo: a.$1),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  I18n.t(slide.descKey!),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: p.muted,
                                      height: 1.55),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: p.borderSoft),
                      // Footer
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            // Dots
                            Row(
                              children: [
                                for (var i = 0; i < _slides.length; i++)
                                  AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 220),
                                    margin: const EdgeInsets.only(
                                        right: 4),
                                    height: 5,
                                    width: i == _paso ? 22 : 5,
                                    decoration: BoxDecoration(
                                      color: i == _paso
                                          ? p.primary
                                          : i < _paso
                                              ? p.primary
                                                  .withValues(alpha: 0.4)
                                              : p.border,
                                      borderRadius:
                                          BorderRadius.circular(99),
                                    ),
                                  ),
                              ],
                            ),
                            const Spacer(),
                            if (_paso > 0)
                              TextButton(
                                onPressed: _atras,
                                child: Text(I18n.t('tour.atras')),
                              ),
                            const SizedBox(width: 4),
                            FilledButton.icon(
                              onPressed: _avanzar,
                              icon: Icon(
                                _paso == _slides.length - 1
                                    ? Icons.check
                                    : Icons.arrow_forward,
                                size: 13,
                              ),
                              label: Text(
                                _paso == _slides.length - 1
                                    ? I18n.t('tour.terminar')
                                    : (_paso == 0
                                        ? I18n.t('tour.empezar')
                                        : I18n.t('tour.siguiente')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KbdMini extends StatelessWidget {
  final String combo;
  const _KbdMini({required this.combo});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.borderSoft),
      ),
      child: Text(
        combo,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: p.text,
          fontFamily: AppFonts.monoFallback.first,
          fontFamilyFallback: AppFonts.monoFallback,
        ),
      ),
    );
  }
}
