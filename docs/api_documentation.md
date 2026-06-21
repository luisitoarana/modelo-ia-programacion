# Documentación de API

> Documentación interactiva en `http://localhost:8000/docs`.
> Esta página resume contratos clave para citas en el proyecto.

## Autenticación

### `POST /api/v1/auth/registro`

Request:
```json
{
 "nombre": "Ana",
 "email": "ana@uni.edu",
 "password": "claveSegura123",
 "rol": "estudiante",
 "institucion": "UNS",
 "nivel_academico": "pregrado"
}
```

### `POST /api/v1/auth/login`

Request:
```json
{ "email": "ana@uni.edu", "password": "claveSegura123" }
```

Response:
```json
{ "access_token": "eyJ...", "token_type": "bearer", "expires_in_seconds": 86400 }
```

## Orquestador IA

### `POST /api/v1/ai/generar`

Request:
```json
{
 "prompt": "Genera un programa que calcule el promedio de notas",
 "nivel_solicitado": "basico",
 "tema_solicitado": "funciones",
 "proveedor": "auto",
 "temperatura": 0.4
}
```

Response (resumen):
```json
{
 "id": "uuid",
 "estado": "completada",
 "modelo_usado": "gemini",
 "tokens_totales": 1234,
 "latencia_segundos": 2.31,
 "intentos_reparacion_json": 0,
 "respuesta": {
 "nivel": "basico",
 "tema": "funciones",
 "pregunta": "...",
 "codigo": "...",
 "explicacion_general": "...",
 "explicacion_linea_por_linea": [{ "linea_numero": 1,... }],
 "conceptos_clave": [{ "concepto": "...",... }],
 "analisis_complejidad": { "temporal": "O(n)",... },
 "actividad_evaluativa": { "tipo": "opcion_multiple",... },
 "fuente_ia": "gemini",
 "metadata": { "tokens_totales": 1234, "latencia_segundos": 2.31 }
 }
}
```

## Dataset

### `POST /api/v1/dataset/{id}/validar`

Request:
```json
{
 "validado": true,
 "validado_por": "Dra. Pérez",
 "observaciones_validacion": "OK"
}
```

### `POST /api/v1/dataset/exportar-jsonl`

Query: `solo_validados=true&nombre_archivo=finetune_v1.jsonl`

Response:
```json
{ "cantidad": 87, "ruta": "datasets/processed/finetune_v1.jsonl" }
```

## Códigos de error relevantes

| Código | Significado en este sistema |
|--------|-----------------------------|
| 401 | JWT inválido o expirado |
| 403 | Rol insuficiente |
| 404 | Recurso (dataset/consulta) inexistente |
| 409 | Email ya registrado |
| 502 | El proveedor IA no produjo JSON válido tras los reintentos |
