"""La configuración pública no hereda datos ni secretos del servidor privado."""
from app import config


def test_demo_ignora_configuracion_privada_y_persiste_sesion(monkeypatch, tmp_path):
    monkeypatch.setattr(config, '__file__', str(tmp_path / 'app' / 'config.py'))
    monkeypatch.setenv('PYTHONIA_DEMO_AISLADA', '1')
    monkeypatch.setenv('DATABASE_URL', 'sqlite+aiosqlite:///privada.db')
    monkeypatch.setenv('SECRET_KEY', 'secreto-privado-que-no-se-debe-heredar-123456')
    monkeypatch.setenv('ADMIN_EMAIL', 'privado@example.org')
    monkeypatch.setenv('GEMINI_API_KEY', 'clave-privada')
    config.get_settings.cache_clear()
    try:
        demo = config.get_settings()
        assert demo.admin_email == 'demo.admin@example.org'
        assert demo.database_url.endswith('/.runtime/demo-admin/demo.db')
        assert 'privada.db' not in demo.database_url
        assert demo.secret_key != 'secreto-privado-que-no-se-debe-heredar-123456'
        assert demo.gemini_api_key == ''
        assert demo.app_port == 8766 and demo.app_host == '127.0.0.1'
        config.get_settings.cache_clear()
        assert config.get_settings().secret_key == demo.secret_key
    finally:
        config.get_settings.cache_clear()
