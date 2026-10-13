import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers.dart';
import '../../theme.dart';
import 'settings_common.dart';

class CapacidadesSection extends StatefulWidget {
  final SettingsProvider settings;
  const CapacidadesSection({super.key, required this.settings});

  @override
  State<CapacidadesSection> createState() => _CapacidadesSectionState();
}

class _CapacidadesSectionState extends State<CapacidadesSection> {
  bool _mostrarClavesAvanzadas = false;

  final Map<String, TextEditingController> _ctrls = {
    'groq': TextEditingController(),
    'gemini': TextEditingController(),
    'deepseek': TextEditingController(),
    'openrouter': TextEditingController(),
    'openai': TextEditingController(),
    'anthropic': TextEditingController(),
  };

  final Map<String, String?> _estadosPrueba = {};
  final Map<String, bool> _probando = {};

  @override
  void initState() {
    super.initState();
    _cargarKeys();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarKeys() async {
    final auth = context.read<AuthProvider>();
    if (!auth.autenticado || !auth.usuario!.esInvestigador) return;

    try {
      final keys = await auth.api.estadoApiKeys();
      if (mounted) {
        setState(() {
          for (final item in keys) {
            final prov = item['proveedor']?.toString() ?? '';
            final enmascarada = item['valor_enmascarado']?.toString() ?? '';
            if (_ctrls.containsKey(prov) && enmascarada.isNotEmpty) {
              _ctrls[prov]!.text = enmascarada;
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _guardarYProbarKey(String proveedor) async {
    final auth = context.read<AuthProvider>();
    final texto = _ctrls[proveedor]?.text.trim() ?? '';
    if (texto.isEmpty || texto.startsWith('sk-...') || texto.startsWith('AIza...')) {
      _probarKey(proveedor);
      return;
    }

    setState(() => _probando[proveedor] = true);
    try {
      await auth.api.guardarApiKey(proveedor, texto);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clave de $proveedor vinculada correctamente.')),
        );
      }
      await _probarKey(proveedor);
    } catch (e) {
      if (mounted) {
        setState(() => _estadosPrueba[proveedor] = 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _probando[proveedor] = false);
    }
  }

  Future<void> _probarKey(String proveedor) async {
    final auth = context.read<AuthProvider>();
    setState(() => _probando[proveedor] = true);
    try {
      final res = await auth.api.probarApiKey(proveedor);
      if (mounted) {
        setState(() {
          _estadosPrueba[proveedor] = res.ok
              ? 'Conexión verificada exitosamente'
              : 'Fallo: ${res.detalle}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _estadosPrueba[proveedor] = 'Error de conexión: $e');
      }
    } finally {
      if (mounted) setState(() => _probando[proveedor] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final auth = context.watch<AuthProvider>();
    final esInvestigador = auth.autenticado && auth.usuario!.esInvestigador;
    final modoActual = widget.settings.modoAcompanamiento;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsTitulo(
            titulo: 'Condición Cuasiexperimental de Tesis',
            descripcion:
                'Modo local para explorar la aplicación. En el estudio, la condición y fase las asigna el docente desde el servidor.',
          ),
          const SizedBox(height: 12),
          if (widget.settings.asignacionActiva)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Condición fijada por el docente · fase: ${widget.settings.faseEstudio}',
                  style: TextStyle(color: p.primary, fontWeight: FontWeight.w600)),
            ),
          _tarjetaModo(
            p,
            id: 'con_acompanamiento',
            titulo: 'Grupo Experimental (Con Acompañamiento Didáctico)',
            descripcion:
                'Andamiaje pedagógico integral: desglose línea por línea, variables clave, estructuras de control, complejidad Big-O, prevención de bugs y preguntas de autoevaluación.',
            icono: Icons.school_rounded,
            colorIcono: p.primary,
            seleccionado: modoActual == 'con_acompanamiento',
            onTap: widget.settings.asignacionActiva ? () {} : () => widget.settings.setModoAcompanamiento('con_acompanamiento'),
          ),
          const SizedBox(height: 8),
          _tarjetaModo(
            p,
            id: 'sin_acompanamiento',
            titulo: 'Grupo Control (Sin Acompañamiento - Solo Código)',
            descripcion:
                'Generación directa de código Python funcional sin explicaciones didácticas ni desgloses pedagógicos conceptuales.',
            icono: Icons.code_rounded,
            colorIcono: p.muted,
            seleccionado: modoActual == 'sin_acompanamiento',
            onTap: widget.settings.asignacionActiva ? () {} : () => widget.settings.setModoAcompanamiento('sin_acompanamiento'),
          ),
          const SizedBox(height: 8),
          _tarjetaModo(
            p,
            id: 'bloqueado_post_test',
            titulo: 'Fase de Evaluación Post-Test (Asistente IA Bloqueado)',
            descripcion:
                'Deshabilita temporalmente el asistente de IA para que los estudiantes resuelvan y ejecuten sus ejercicios de programación de forma independiente.',
            icono: Icons.lock_clock_rounded,
            colorIcono: AppColors.danger,
            seleccionado: modoActual == 'bloqueado_post_test',
            onTap: widget.settings.asignacionActiva ? () {} : () => widget.settings.setModoAcompanamiento('bloqueado_post_test'),
          ),
          const SizedBox(height: 24),
          const SettingsTitulo(
            titulo: 'Catálogo de Motores de Inteligencia (Estilo OpenCode / Hub)',
            descripcion:
                'Motores neuronales gestionados por la plataforma para alta concurrencia y trabajo offline.',
          ),
          const SizedBox(height: 10),
          _tarjetaMotorCatalogo(
            p,
            titulo: 'Motor de Alta Velocidad (L-Engine / Flash Fire)',
            descripcion: 'Inferencia ultra-rápida (350+ tok/s) ideal para 20 estudiantes concurrentes.',
            tipo: 'Gratuito · Nube',
            icono: Icons.bolt_rounded,
            color: Colors.amber,
            activo: true,
          ),
          const SizedBox(height: 8),
          _tarjetaMotorCatalogo(
            p,
            titulo: 'Motor de Contexto Extenso (G-Engine / Gemini Flash)',
            descripcion: 'Capacidad de ventana masiva (1 millón de tokens) para proyectos completos.',
            tipo: 'Gratuito · Nube',
            icono: Icons.auto_awesome_rounded,
            color: Colors.lightBlueAccent,
            activo: true,
          ),
          const SizedBox(height: 8),
          _tarjetaMotorCatalogo(
            p,
            titulo: 'Motor Propio Local Offline (Edge-Engine · Tesis)',
            descripcion: 'Inferencia neuronal 100% autónoma en CPU/GPU local, sin internet ni APIs.',
            tipo: '100% Local · Offline',
            icono: Icons.memory_rounded,
            color: p.primary,
            activo: true,
          ),
          const SizedBox(height: 8),
          _tarjetaMotorCatalogo(
            p,
            titulo: 'Motor de Razonamiento Profundo (D-Engine / Deep-Code)',
            descripcion: 'Especializado en auditoría de bugs lógicos, AST Map-Reduce y casos límite.',
            tipo: 'Razonamiento',
            icono: Icons.psychology_outlined,
            color: Colors.purpleAccent,
            activo: true,
          ),
          const SizedBox(height: 24),
          const SettingsTitulo(
            titulo: 'Capacidades adicionales',
            descripcion: 'Herramientas complementarias para el asistente.',
          ),
          SettingsFila(
            label: 'Búsqueda en internet',
            descripcion:
                'El asistente puede consultar la web cuando la pregunta lo amerite. Las fuentes se citan en la respuesta.',
            control: SettingsSwitch(
              value: widget.settings.buscarWeb,
              onChanged: widget.settings.setBuscarWeb,
            ),
          ),
          if (esInvestigador) ...[
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _mostrarClavesAvanzadas = !_mostrarClavesAvanzadas),
                icon: Icon(
                  _mostrarClavesAvanzadas ? Icons.expand_less : Icons.tune_rounded,
                  size: 16,
                  color: p.muted,
                ),
                label: Text(
                  _mostrarClavesAvanzadas
                      ? 'Ocultar configuración avanzada de credenciales privadas'
                      : 'Configuración avanzada de credenciales privadas (Opcional)',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
            ),
            if (_mostrarClavesAvanzadas) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.surface2.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credenciales Privadas Personalizadas (BYOK)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Opcional: Si cuentas con claves propias de OpenAI, Anthropic, Groq o Gemini para tu servidor, puedes vincularlas aquí para utilizarlas en lugar de los motores por defecto.',
                      style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    _filaProveedorCloud(p, id: 'groq', nombre: 'Groq (Alta Velocidad)', hint: 'gsk_...'),
                    _filaProveedorCloud(p, id: 'gemini', nombre: 'Google Gemini (Contexto Extenso)', hint: 'AIzaSy...'),
                    _filaProveedorCloud(p, id: 'deepseek', nombre: 'DeepSeek', hint: 'sk-...'),
                    _filaProveedorCloud(p, id: 'openrouter', nombre: 'OpenRouter (Distribuido)', hint: 'sk-or-...'),
                    _filaProveedorCloud(p, id: 'openai', nombre: 'OpenAI (GPT-4o)', hint: 'sk-proj-...'),
                    _filaProveedorCloud(p, id: 'anthropic', nombre: 'Anthropic (Claude 3.5)', hint: 'sk-ant-...'),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tarjetaMotorCatalogo(
    AppPalette p, {
    required String titulo,
    required String descripcion,
    required String tipo,
    required IconData icono,
    required Color color,
    required bool activo,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icono, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: p.borderSoft),
                      ),
                      child: Text(
                        tipo,
                        style: TextStyle(fontSize: 9.5, color: p.subtle, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 11.5, color: p.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 12, color: Colors.greenAccent),
                SizedBox(width: 4),
                Text(
                  'Activado',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.greenAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaModo(
    AppPalette p, {
    required String id,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color colorIcono,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: seleccionado ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado ? colorIcono : p.borderSoft,
            width: seleccionado ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorIcono.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, size: 20, color: colorIcono),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                      ),
                      Radio<String>(
                        value: id,
                        groupValue: widget.settings.modoAcompanamiento,
                        onChanged: (_) => onTap(),
                        activeColor: colorIcono,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descripcion,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: p.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaProveedorCloud(
    AppPalette p, {
    required String id,
    required String nombre,
    required String hint,
  }) {
    final ctrl = _ctrls[id]!;
    final estado = _estadosPrueba[id];
    final enProgreso = _probando[id] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  obscureText: true,
                  style: TextStyle(fontSize: 11.5, color: p.text),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 11, color: p.subtle),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: p.borderSoft),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: enProgreso ? null : () => _guardarYProbarKey(id),
                child: enProgreso
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Vincular', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (estado != null) ...[
            const SizedBox(height: 4),
            Text(
              estado,
              style: TextStyle(
                fontSize: 10.5,
                color: estado.contains('exitosa') ? Colors.greenAccent : AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
