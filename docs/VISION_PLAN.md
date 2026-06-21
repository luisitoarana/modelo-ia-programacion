# Plan de Visión Multimodal — Subir imágenes al chat

> Permitir que el usuario adjunte capturas de pantalla, fotos de
> código en pizarra, diagramas a mano o errores de consola y el
> asistente las **vea** y razone sobre ellas.

---

## 1. Casos de uso prioritarios

| Caso | Ejemplo concreto | Impacto pedagógico |
|---|---|---|
| **Diagnosticar error de consola** | Foto de un `TypeError` en VSCode | Alto — desbloquea al estudiante atascado |
| **Explicar diagrama a mano** | Foto de un flowchart en pizarra | Medio — útil en clases presenciales |
| **Convertir imagen → código** | Foto de pseudocódigo en papel | Alto — acelera práctica |
| **Revisar UI mockup** | Screenshot de Figma | Bajo — fuera del scope Python pero útil |
| **Diagrama de BD** | Foto de modelo entidad-relación | Medio — útil para clases de bases de datos |

---

## 2. Arquitectura

```
┌──────────┐ ┌──────────────────┐ ┌─────────────┐
│ Frontend │──> │ POST /chat/enviar │ -> │ Backend │
│ (image) │ │ multipart form │ │ │
└──────────┘ └──────────────────┘ └──────┬──────┘
 │
 ┌─────────────┴─────────────┐
 v v
 ┌────────────┐ ┌─────────────────┐
 │ ¿Hay │ sí │ Gemini Vision │
 │ imagen? │ ───────> │ (gemini-2.0- │
 └────────────┘ │ flash-exp) │
 │ no └─────────────────┘
 v │
 ┌────────────┐ │
 │ Texto only │ │
 │ → routing │ │
 │ habitual │ │
 └────────────┘ │
 └──────────────┬───────────┘
 v
 ┌───────────────────┐
 │ Respuesta + audit │
 └───────────────────┘
```

---

## 3. Cambios necesarios

### Backend (FastAPI)

```python
# app/api/chat.py
from fastapi import UploadFile, File, Form

@router.post("/enviar")
async def enviar(
 contenido: str = Form(...),
 conversacion_id: Optional[str] = Form(None),
 nivel: str = Form("basico"),
 buscar_web: bool = Form(False),
 imagenes: List[UploadFile] = File(default=[]), # ← NUEVO
):
 # Validaciones
 for img in imagenes:
 if img.size > 5 * 1024 * 1024: # 5 MB
 raise HTTPException(400, "Imagen demasiado grande")
 if img.content_type not in ("image/png", "image/jpeg", "image/webp"):
 raise HTTPException(400, "Formato no soportado")

 # Convertir a bytes para pasar al provider
 imagenes_bytes = [(await img.read(), img.content_type) for img in imagenes]

 return await chat_service.procesar(
 contenido=contenido,
 imagenes=imagenes_bytes,
...
 )
```

```python
# app/services/proveedor_gemini.py
import google.generativeai as genai

async def generar_con_imagen(
 prompt: str,
 imagenes_bytes: List[Tuple[bytes, str]],
) -> str:
 model = genai.GenerativeModel("gemini-2.0-flash-exp")
 partes = [prompt]
 for bytes_, mime in imagenes_bytes:
 partes.append({"mime_type": mime, "data": bytes_})
 response = await model.generate_content_async(partes)
 return response.text
```

### Frontend (Next.js)

El composer ya tiene `<input type="file">`. Cambiar `accept`:

```tsx
<input
 type="file"
 accept=".py,.txt,.md,.json,image/png,image/jpeg,image/webp" // ← añadir
 multiple
...
/>
```

Y cuando enviamos, distinguir adjuntos de texto vs imágenes:

```ts
const form = new FormData();
form.append('contenido', mensaje);
form.append('nivel', nivel);
for (const a of adjuntos) {
 if (a.tipo === 'imagen') form.append('imagenes', a.blob);
 else { /* concat al contenido como antes */ }
}
await fetch('/api/chat/enviar', { method: 'POST', body: form });
```

### Desktop (Flutter)

El composer ya tiene `file_picker`. Cambiar el filtro:

```dart
final result = await FilePicker.platform.pickFiles(
 type: FileType.custom,
 allowedExtensions: ['py', 'txt', 'md', 'json', 'png', 'jpg', 'jpeg', 'webp'],
 allowMultiple: true,
);
```

Y al enviar usar multipart (igual que web).

---

## 4. UX — Cómo se ve

### En el composer
- Chip con miniatura de la imagen (96×96 px) + nombre + tamaño
- Botón ✗ para quitar
- Hasta 3 imágenes por mensaje

### En el chat (bubble del usuario)
- Imágenes muestran como thumbnails (200×200 max), click para fullscreen
- Si son varias, grid 2×2 estilo Slack

### En el chat (bubble del asistente)
- Cuando responde a una pregunta con imagen, prefijar con:
 > 📷 *Analizando la imagen…*
- Luego responde con su análisis estructurado:
 > **Lo que veo**: …
 > **El problema**: …
 > **La solución**: …

---

## 5. Routing inteligente

Cuando llega una request con imagen:

1. **Si hay imagen** → forzar Gemini Vision (DeepSeek no tiene visión)
2. **Si no hay imagen** → routing habitual (modelo propio → fallback API)
3. El modelo propio futuro multimodal usará el mismo endpoint (cuando
 entrenemos uno)

---

## 6. Límites y validaciones

| Límite | Valor | Por qué |
|---|---|---|
| Tamaño por imagen | 5 MB | Suficiente para foto de celular hi-res |
| Imágenes por mensaje | 3 | Más confunde a Gemini (context overload) |
| Formatos | PNG, JPEG, WebP | Los más comunes y soportados por Gemini |
| Total payload | 16 MB | Límite del backend FastAPI default |

Validar EN EL FRONTEND también para feedback inmediato.

---

## 7. Costos (Gemini Vision)

Precios actuales (2025-06):

- **gemini-2.0-flash**: $0.10 / 1M tokens entrada (texto), $0.30 / 1M
 tokens entrada (imagen)
- Una imagen 1080p ≈ 250 tokens
- Una consulta promedio (texto + 1 imagen + respuesta) ≈ 1500 tokens

**Costo por consulta multimodal**: ~$0.0005 (medio centavo).

Con 1000 consultas multimodales/día → $0.50/día → $15/mes. Manejable.

---

## 8. Privacidad

- Las imágenes NO se guardan en disco del servidor
- Se procesan en memoria y se borran después de la respuesta
- En el audit log solo queda: `[imagen 1: 800KB png]` — sin contenido
- El usuario debe consentir explícitamente al primer uso
- Opción en Settings → Privacidad: "No usar imágenes para mejorar el
 modelo" (default ON)

---

## 9. Visión propia (fase tardía)

Cuando el modelo base esté maduro (Fase 7), entrenar una versión
multimodal:

- Base: nuestro Transformer 46M
- Encoder de imagen: usar **CLIP** pretrained (no reinventar la rueda)
- Adapter MLP entre CLIP features y embedding del modelo
- Dataset: COCO captions (es) + screenshots de error (sintéticos)

Esto es trabajo de **semanas**, no días. Por ahora delegamos a Gemini.

---

## 10. Timeline

| Día | Tarea |
|---|---|
| 1 | Backend: aceptar `imagenes` en `/chat/enviar` |
| 1 | Backend: integrar Gemini Vision en proveedor |
| 2 | Frontend web: composer admite imágenes, preview, envío multipart |
| 2 | Frontend web: bubbles muestran thumbs |
| 3 | Desktop: file_picker admite imágenes |
| 3 | Desktop: chip de miniatura en composer |
| 4 | Testing end-to-end con 10 capturas reales de error |
| 4 | Documentar en MANUAL_USUARIO.md |
