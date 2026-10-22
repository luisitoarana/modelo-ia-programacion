import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_desktop/services/proceso_interactivo.dart';

void main() {
  test('Python muestra el prompt antes de recibir entrada y utiliza los datos reales', () async {
    final proceso = await ProcesoInteractivo.python(
      'nombre = input("Nombre: ")\nedad = int(input("Edad: "))\nprint(f"RESULTADO: {nombre} {edad + 1}")');
    final primerPrompt = Completer<void>();
    final segundoPrompt = Completer<void>();
    var salida = '';
    final lecturas = proceso.salida.forEach((trozo) {
      salida += trozo;
      if (salida.contains('Nombre:') && !primerPrompt.isCompleted) primerPrompt.complete();
      if (salida.contains('Edad:') && !segundoPrompt.isCompleted) segundoPrompt.complete();
    });
    final errores = proceso.errores.join();
    try {
      await primerPrompt.future.timeout(const Duration(seconds: 10));
      expect(salida.contains('RESULTADO:'), isFalse);
      proceso.enviar('María');
      await segundoPrompt.future.timeout(const Duration(seconds: 10));
      proceso.enviar('21');
      expect(await proceso.finalizado.timeout(const Duration(seconds: 10)), 0);
      await lecturas;
      expect(await errores, isEmpty);
      expect(salida, contains('RESULTADO: María 22'));
      expect(salida, isNot(contains('valores de prueba')));
    } finally {
      proceso.detener();
      await proceso.finalizado;
      await proceso.limpiar();
    }
  });

  test('permite entrada vacía y detener un programa que espera input', () async {
    final proceso = await ProcesoInteractivo.python('valor = input("Dato: ")\nprint("RECIBIDO", repr(valor))\ninput("Esperando: ")');
    final esperando = Completer<void>();
    var salida = '';
    final leer = proceso.salida.forEach((s) {
      salida += s;
      if (salida.contains('Esperando:') && !esperando.isCompleted) esperando.complete();
    });
    final errores = proceso.errores.drain<void>();
    try {
      proceso.enviar('');
      await esperando.future.timeout(const Duration(seconds: 10));
      expect(salida, contains("RECIBIDO ''"));
      proceso.detener();
      await proceso.finalizado.timeout(const Duration(seconds: 10));
      await Future.wait([leer, errores]);
    } finally {
      proceso.detener();
      await proceso.finalizado;
      await proceso.limpiar();
    }
  });
}
