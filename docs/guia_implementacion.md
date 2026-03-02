# Asistente Virtual IA — Guía de Implementación

**Sistema RAG multiidioma para consulta de manuales empresariales**

---

## Introducción

El Asistente Virtual IA es un sistema de chatbot basado en RAG (Retrieval-Augmented Generation) que permite a los usuarios consultar manuales en lenguaje natural. El sistema extrae información relevante del manual y genera respuestas precisas usando un modelo de lenguaje.

**Modos disponibles:**

| Modo | Descripción | Uso recomendado |
|------|-------------|-----------------|
| **Producción** | PDFs pre-procesados. Respuestas rápidas, índice estático. | Despliegue en cliente final |
| **Desarrollo** | Acepta cualquier PDF subido desde la web en tiempo real. | Demos y pruebas |

---

## Requisitos previos

### Servidor

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB |
| Disco | 3 GB libres | 5 GB libres |
| SO | Ubuntu 20.04+ | Ubuntu 22.04+ |
| Python | 3.11 | 3.12 |

### Cuentas necesarias

- **Groq API Key** (gratuita): [console.groq.com](https://console.groq.com)

### Paquetes del sistema

```bash
sudo apt update
sudo apt install -y git python3.11 python3.11-venv python3-pip
```

---

## Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/Chupacharcos/chatbot.git
cd chatbot
```

---

## Paso 2 — Colocar los PDFs del manual

> Solo necesario en **modo Producción**. En modo Desarrollo los PDFs se suben desde la web.

Copia el manual con la nomenclatura correspondiente al idioma:

```
data/manual_es.pdf   ← Español (obligatorio si el cliente usa español)
data/manual_en.pdf   ← English (opcional)
data/manual_ca.pdf   ← Català  (opcional)
data/manual_pt.pdf   ← Português (opcional)
```

---

## Paso 3 — Obtener la clave de Groq

1. Regístrate en [console.groq.com](https://console.groq.com)
2. Ve a **API Keys** → **Create API Key**
3. Guarda la clave (empieza por `gsk_...`)

---

## Paso 4 — Ejecutar el instalador

```bash
bash setup.sh
```

El instalador realiza los siguientes pasos de forma automática:

### 4.1 Selección de modo

```
Selecciona el modo de instalación:

  1) PRODUCCIÓN (Estático - PDFs pre-procesados)
  2) DESARROLLO (Dinámico - Soporta PDFs desde web)

    👉 Opción [1-2]:
```

Selecciona `1` para producción o `2` para desarrollo.

### 4.2 Instalación de dependencias (~2 GB, 2-4 min)

Crea el entorno virtual Python e instala todas las librerías de IA:
FAISS, Sentence Transformers, PyMuPDF, FastAPI, Groq, etc.

### 4.3 Configuración del archivo `.env`

Si no existe `.env`, el instalador lo crea de forma interactiva:

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `GROQ_API_KEY` | **Obligatoria.** Clave de Groq | `gsk_XXXX...` |
| `CLIENT_API_KEY` | Contraseña de acceso a la API | `mi_clave_segura` |
| `API_PORT` | Puerto del servidor | `8088` |
| `APP_URL` | Origen CORS permitido | `*` o `https://tudominio.com` |

> **Seguridad**: En producción establece `APP_URL` al dominio exacto del cliente, no uses `*`.

### 4.4 Procesado de PDFs (solo modo Producción)

El instalador ejecuta automáticamente:

```bash
python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
```

Este proceso:
1. Extrae el texto del PDF
2. Identifica secciones y capítulos
3. Genera chunks de texto (fragmentos)
4. Calcula embeddings con el modelo `intfloat/multilingual-e5-large`
5. Construye el índice FAISS y lo guarda en `faiss_index/es/`

> La primera ejecución descarga el modelo (~500 MB). Puede tardar 5-10 minutos.

### 4.5 Servicio systemd

El instalador crea y activa el servicio `chatbot` que:
- Arranca automáticamente con el servidor
- Se reinicia si falla (`Restart=always`)
- Guarda los logs en `logs/api.log`

### 4.6 HTML de demostración

Se genera `chatbot_ejemplo.html` con la API Key ya configurada.
Abrirlo directamente en el navegador para hacer pruebas básicas.

---

## Paso 5 — Verificación

### Comprobar el servicio

```bash
sudo systemctl status chatbot
```

Debe mostrar: `Active: active (running)`

### Test básico con curl

```bash
curl http://127.0.0.1:PUERTO/
```

Respuesta esperada:
```json
{"status": "ok", "mode": "production"}
```

### Test de consulta

```bash
curl -X POST http://127.0.0.1:PUERTO/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: TU_CLIENT_API_KEY" \
  -d '{"question": "¿De qué trata el manual?", "lang": "es"}'
```

---

## Gestión del servicio

```bash
sudo systemctl status chatbot      # Ver estado
sudo systemctl start chatbot       # Iniciar
sudo systemctl stop chatbot        # Detener
sudo systemctl restart chatbot     # Reiniciar tras cambios
tail -f logs/api.log               # Ver logs en tiempo real
```

---

## Actualizar el manual

Cuando el cliente proporcione un nuevo PDF, procesar sin reinstalar:

```bash
cd /ruta/al/chatbot
source venv/bin/activate
python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
sudo systemctl restart chatbot
```

---

## Integración web

Ejemplo de integración JavaScript en la aplicación del cliente:

```javascript
let sessionId = sessionStorage.getItem('chatbot_session_id') || '';

async function preguntar(pregunta, lang = 'es') {
  const res = await fetch('http://IP_SERVIDOR:PUERTO/query', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': 'CLIENT_API_KEY'
    },
    body: JSON.stringify({ question: pregunta, lang, session_id: sessionId })
  });

  const data = await res.json();
  sessionId = data.session_id;
  sessionStorage.setItem('chatbot_session_id', sessionId);

  return data.answer;
}
```

---

## Referencia de la API

URL base: `http://IP_DEL_SERVIDOR:PUERTO`

Autenticación: cabecera `X-API-Key: CLIENT_API_KEY`

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| `GET` | `/` | No | Estado del servidor |
| `POST` | `/upload` | No | Subir PDF (modo desarrollo) |
| `POST` | `/query` | Sí | Consultar el manual |
| `GET` | `/stats` | Sí | Sesiones activas |
| `DELETE` | `/history/{session_id}` | Sí | Borrar historial de sesión |
| `DELETE` | `/history` | Sí | Borrar todo el historial |
| `GET` | `/docs` | No | Documentación Swagger |

### POST `/query` — Consultar

**Request:**
```json
{
  "question": "¿Cómo se realiza el proceso de alta?",
  "lang": "es",
  "session_id": ""
}
```

**Response:**
```json
{
  "answer": "Según el manual, el proceso consiste en...",
  "lang": "es",
  "sources": [
    {"section": "Gestión de usuarios", "page": 5, "text": "..."}
  ],
  "session_id": "a1b2c3d4-..."
}
```

---

## Idiomas soportados

| Código | Idioma | PDF requerido |
|--------|--------|---------------|
| `es` | Español | `data/manual_es.pdf` |
| `en` | English | `data/manual_en.pdf` |
| `ca` | Català | `data/manual_ca.pdf` |
| `pt` | Português | `data/manual_pt.pdf` |

---

## Seguridad

- El archivo `.env` nunca se sube al repositorio
- Los PDFs del cliente nunca se suben al repositorio
- `CLIENT_API_KEY` protege todos los endpoints autenticados
- `APP_URL` restringe CORS — en producción especificar el dominio exacto
- Cada usuario tiene historial aislado por `session_id`

---

*Asistente Virtual IA — Sistema RAG multiidioma*
