# Manual del administrador / investigador

## Roles

| Rol | Acceso |
|-----|--------|
| `estudiante` | Solicita y consulta sus propias generaciones. |
| `investigador` | Valida el dataset, exporta JSONL, ve reportes. |
| `administrador` | Todo lo anterior + gestión futura de usuarios. |

## Crear cuenta de investigador

```bash
curl -X POST http://localhost:8000/api/v1/auth/registro \
 -H "Content-Type: application/json" \
 -d '{"nombre":"Investigador","email":"inv@uni.edu","password":"ClaveSegura123","rol":"investigador"}'
```

## Validación del dataset

`POST /api/v1/dataset/{id}/validar`

```json
{
 "validado": true,
 "validado_por": "Dra. Pérez",
 "observaciones_validacion": "Respuesta pedagógicamente correcta; verifiqué la complejidad."
}
```

## Exportar dataset para fine-tuning

```bash
curl -X POST "http://localhost:8000/api/v1/dataset/exportar-jsonl?solo_validados=true&nombre_archivo=finetune_v1.jsonl" \
 -H "Authorization: Bearer <token>"
```

Salida: `datasets/processed/finetune_v1.jsonl`.

## Reporte de investigación

`GET /api/v1/research/reporte-general` devuelve:

- Total de usuarios.
- Consultas: total / completadas / fallidas / latencia promedio / por fuente IA.
- Dataset: total / validados / por nivel / por tema.
- Puntaje promedio de evaluaciones.

Estas métricas alimentan directamente los capítulos de resultados de el proyecto.
