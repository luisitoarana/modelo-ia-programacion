from app.routes.herramientas import _exec_sandbox


def test_sandbox_no_inventa_datos_de_entrada():
    resultado = _exec_sandbox('nombre = input("Nombre: ")\nprint("Hola", nombre)', timeout_segundos=3)
    assert resultado.exit_code != 0
    assert 'EOFError' in resultado.stderr
    assert 'valores de prueba' not in resultado.stdout
    assert 'Hola 10' not in resultado.stdout


def test_sandbox_respeta_entrada_explicita_con_varias_lineas():
    resultado = _exec_sandbox('nombre=input("Nombre: ")\nedad=int(input("Edad: "))\nprint(nombre, edad+1)',
                             stdin_texto='María\n21\n', timeout_segundos=3)
    assert resultado.exit_code == 0
    assert 'María 22' in resultado.stdout
