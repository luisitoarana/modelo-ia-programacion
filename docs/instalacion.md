# Guía de instalación

## Opción A — Docker Compose (recomendado)

```bash
cp.env.example.env
# Editar.env: GEMINI_API_KEY, DEEPSEEK_API_KEY, SECRET_KEY
docker compose up --build
```

Servicios:
- `db`: PostgreSQL 16.
- `backend`: FastAPI en `:8000`.
- `frontend`: Next.js en `:3000`.

Las tablas se crean automáticamente al arrancar en modo `development`.

## Opción B — Local (sin Docker, Windows + PowerShell)

### PostgreSQL

Instala PostgreSQL 16. Crea la base de datos:

```sql
CREATE DATABASE sistema_explicador;
```

### Backend

```powershell
cd backend
python -m venv.venv
..\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item..\.env.example..\.env # editar valores
$env:PYTHONPATH = "$PWD"
uvicorn app.main:app --reload --port 8000
```

### Frontend

```powershell
cd frontend
npm install
npm run dev
```

## Verificación

- `http://localhost:8000/health` → `{"status":"ok",...}`
- `http://localhost:8000/docs` → Swagger UI.
- `http://localhost:3000` → Frontend (redirige a /login si no hay sesión).

## Creación del primer investigador

```bash
curl -X POST http://localhost:8000/api/v1/auth/registro ^
 -H "Content-Type: application/json" ^
 -d "{\"nombre\":\"Investigador\",\"email\":\"tu@correo.com\",\"password\":\"unaclavefuerte\",\"rol\":\"investigador\"}"
```

## Migraciones (opcional)

Para entornos productivos, usa Alembic en lugar de `init_models`:

```bash
cd backend
alembic init alembic
# configurar env.py para usar settings.database_url
alembic revision --autogenerate -m "init"
alembic upgrade head
```
