# Asistente Virtual IA — Chatbot RAG Multiidioma

Sistema de chatbot inteligente para consultar documentos empresariales basado en RAG (Retrieval-Augmented Generation). Combina búsqueda semántica vectorial con búsqueda por palabras clave para garantizar que el asistente encuentre la información relevante independientemente de cómo formule la pregunta el usuario.

## Características

- **Búsqueda híbrida**: semántica (FAISS) + palabras clave, con normalización de acentos
- **Multiidioma automático**: responde en el mismo idioma que use el usuario (sin configuración)
- **Personalidad configurable**: el cliente puede definir el rol y actitud del asistente
- **Markdown en respuestas**: formato enriquecido (listas, negritas, encabezados)
- **Historial de conversación**: el asistente recuerda el contexto de los últimos mensajes
- **Dos modos**: índices estáticos pre-procesados (producción) o PDFs dinámicos desde la web

## Stack tecnológico

- **Python 3.11+**
- **FAISS** — búsqueda vectorial semántica
- **Sentence Transformers** (`intfloat/multilingual-e5-large`) — embeddings multiidioma
- **Cross-Encoder** (`mmarco-mMiniLMv2-L12-H384`) — re-ranking de resultados
- **Groq API · Llama 3.1 8B** — generación de respuestas
- **FastAPI + Uvicorn** — API REST asíncrona

---

## Estructura del proyecto

```
chatbot/
├── src/
│   ├── api.py               # Servidor FastAPI (API REST)
│   ├── rag_engine.py        # Motor RAG (búsqueda semántica + LLM)
│   ├── chatbot.py           # Interfaz de línea de comandos (CLI)
│   └── process_manual.py    # Procesamiento de PDFs e índices FAISS
├── data/                    # Colocar aquí los PDFs del manual
│   └── manual_es.pdf        # Nomenclatura: manual_{es,en,ca,pt}.pdf
├── faiss_index/             # Índices generados automáticamente
│   └── es/
│       ├── index.faiss
│       └── chunks.pkl
├── docs/                    # Documentación de referencia
├── logs/                    # Logs generados automáticamente
├── uploads/                 # PDFs subidos dinámicamente (modo desarrollo)
├── faiss_sessions/          # Índices por sesión (modo desarrollo)
├── .env                     # Variables de entorno (NO versionar)
├── .env.example             # Plantilla de variables de entorno
├── requirements.txt         # Dependencias Python
├── setup.sh                 # Script de instalación automatizada
└── chatbot_ejemplo.html     # Demo web interactiva (generada por setup.sh)
```

---

## Instalación

### Requisitos previos

- Ubuntu Server 20.04 o superior
- Python 3.11+
- Git
- Acceso `sudo` para configurar el servicio

### Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/Chupacharcos/chatbot.git
cd chatbot
```

### Paso 2 — Colocar el PDF del manual

Copia el manual del cliente con el nombre correspondiente al idioma:

```
data/manual_es.pdf   ← español
data/manual_en.pdf   ← english (opcional)
data/manual_ca.pdf   ← català  (opcional)
data/manual_pt.pdf   ← português (opcional)
```

### Paso 3 — Obtener la clave de Groq

El sistema utiliza Groq como proveedor LLM (gratuito):

1. Regístrate en https://console.groq.com
2. Ve a **API Keys** y genera una nueva clave
3. Guárdala para el paso siguiente

### Paso 4 — Ejecutar el instalador

```bash
bash setup.sh
```

El script hace todo automáticamente:

1. **Selección de modo:**
   - `1` — **PRODUCCIÓN**: índices pre-procesados del PDF (recomendado para cliente final)
   - `2` — **DESARROLLO**: acepta PDFs subidos desde la web en tiempo real

2. **Instala dependencias** (~2 GB, puede tardar 2-4 minutos)

3. **Configura el archivo `.env`** de forma interactiva:
   - `GROQ_API_KEY` — clave de https://console.groq.com **(obligatoria)**
   - `CLIENT_API_KEY` — contraseña de acceso a la API
   - Puerto del servidor (por defecto: `8088`)

4. **Procesa los PDFs** y genera los índices FAISS (solo modo producción)

5. **Configura el servicio systemd** para arranque automático

Al finalizar muestra un resumen con la URL, API key y comandos útiles.

---

## Gestión del servicio

```bash
sudo systemctl status chatbot      # Ver estado
sudo systemctl start chatbot       # Iniciar
sudo systemctl stop chatbot        # Detener
sudo systemctl restart chatbot     # Reiniciar
tail -f logs/api.log               # Ver logs en tiempo real
```

---

## Actualizar el manual

Para procesar un nuevo PDF sin reinstalar:

```bash
./venv/bin/python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
sudo systemctl restart chatbot
```

---

## API REST

URL base: `http://IP_DEL_SERVIDOR:PUERTO`

Autenticación: cabecera `X-API-Key: tu_client_api_key`

### Endpoints

| Método   | Endpoint                  | Auth | Descripción                               |
|----------|---------------------------|------|-------------------------------------------|
| `GET`    | `/`                       | No   | Estado del servidor                       |
| `POST`   | `/upload`                 | No   | Subir PDF y crear sesión dinámica         |
| `POST`   | `/query`                  | Sí   | Consultar el manual                       |
| `GET`    | `/stats`                  | Sí   | Sesiones activas y mensajes totales       |
| `DELETE` | `/history/{session_id}`   | Sí   | Borrar historial de un usuario            |
| `DELETE` | `/history`                | Sí   | Borrar historial de todas las sesiones    |
| `GET`    | `/docs`                   | No   | Documentación Swagger interactiva         |

### POST `/query`

**Request:**
```json
{
  "question": "¿Cómo se realiza el proceso de alta de usuario?",
  "lang": "es",
  "session_id": ""
}
```

| Parámetro    | Tipo   | Obligatorio | Descripción                                                        |
|--------------|--------|-------------|--------------------------------------------------------------------|
| `question`   | string | Sí          | Pregunta en lenguaje natural                                       |
| `lang`       | string | No          | Idioma para el índice estático: `es`, `en`, `ca`, `pt` (default: `es`). En modo dinámico el idioma se detecta automáticamente de la pregunta. |
| `session_id` | string | No          | ID de sesión — vacío en la primera llamada                         |

**Response:**
```json
{
  "answer": "Para crear una organización accede al menú de Administración...",
  "lang": "es",
  "sources": [
    {"section": "Gestión de organizaciones", "page": 12, "text": "..."}
  ],
  "session_id": "a1b2c3d4-..."
}
```

### POST `/upload`

Sube un PDF y crea una sesión de consulta dinámica (modo desarrollo).

**Request:** `multipart/form-data`

| Campo        | Tipo   | Descripción                                                                 |
|--------------|--------|-----------------------------------------------------------------------------|
| `pdf`        | file   | Archivo PDF                                                                 |
| `lang`       | string | Idioma para el índice (default: `es`). Las respuestas se auto-adaptan al idioma de cada pregunta. |
| `session_id` | string | ID de sesión (se genera si está vacío)                                      |
| `persona`    | string | Rol y actitud del asistente, p.ej. "Respondo de forma técnica y precisa."  |

**Response:**
```json
{
  "success": true,
  "session_id": "a1b2c3d4-...",
  "message": "PDF 'manual.pdf' procesado correctamente",
  "chunks": 87
}
```

---

## Personalidad del asistente

El campo `persona` en `/upload` permite configurar el comportamiento del chatbot para cada cliente:

```
"Soy el asistente de AcmeCorp, especializado en soporte técnico B2B. Respondo de forma precisa y profesional."
```

```
"Responde siempre de forma amigable y cercana, usando un lenguaje sencillo sin tecnicismos."
```

El asistente mantiene esa actitud durante toda la sesión.

---

## Idiomas soportados

El asistente responde automáticamente en el idioma que use el usuario en su pregunta. No requiere configuración: si el usuario escribe en inglés, responde en inglés; si escribe en español, responde en español.

En modo producción (índice estático), cada idioma necesita su propio PDF procesado:

| Código | Idioma    | PDF requerido         |
|--------|-----------|-----------------------|
| `es`   | Español   | `data/manual_es.pdf`  |
| `en`   | English   | `data/manual_en.pdf`  |
| `ca`   | Català    | `data/manual_ca.pdf`  |
| `pt`   | Português | `data/manual_pt.pdf`  |

---

## Integración en aplicación web

```javascript
let sessionId = sessionStorage.getItem('chatbot_session_id') || '';

async function preguntar(pregunta) {
  const res = await fetch('http://IP_SERVIDOR:PUERTO/query', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': 'tu_client_api_key'
    },
    body: JSON.stringify({ question: pregunta, session_id: sessionId })
  });

  const data = await res.json();
  sessionId = data.session_id;
  sessionStorage.setItem('chatbot_session_id', sessionId);

  return data.answer;
}
```

---

## Variables de entorno

Referencia completa de `.env`:

| Variable         | Obligatoria | Descripción                                          |
|------------------|-------------|------------------------------------------------------|
| `GROQ_API_KEY`   | **Sí**      | Clave API de https://console.groq.com                |
| `CLIENT_API_KEY` | Recomendada | Contraseña de acceso a la API (dejar vacío = sin auth) |
| `API_PORT`       | No          | Puerto del servidor (default: `8088`)                |
| `APP_URL`        | No          | Origen CORS permitido (default: `*` = todos)         |

---

## Logs

Los logs se guardan en `logs/api.log`. Para verlos en tiempo real:

```bash
tail -f logs/api.log
```

Formato de cada entrada:
```
2026-03-01 10:30:15 | INFO | QUERY | session=a1b2c3d4... | lang=es | time=1.23s | sources=[Gestión de usuarios p.5] | q='¿Cómo se realiza el proceso de alta de usuario?'
```

---

## Seguridad

- `.env` nunca se sube al repositorio (incluido en `.gitignore`)
- Los PDFs del cliente nunca se suben al repositorio
- `CLIENT_API_KEY` protege el acceso a todos los endpoints autenticados
- `APP_URL` restringe CORS al dominio del cliente (usar dominio concreto en producción, no `*`)
- Cada usuario tiene historial aislado por `session_id`

---

## Requisitos del servidor

| Recurso | Mínimo  | Recomendado |
|---------|---------|-------------|
| CPU     | 2 cores | 4+ cores    |
| RAM     | 4 GB    | 8 GB        |
| Disco   | 3 GB    | 5 GB        |
| SO      | Ubuntu 20.04+ | Ubuntu 22.04+ |
| Python  | 3.11    | 3.12        |

---

## Despliegue multi-organización (SaaS)

Este apartado documenta cómo distribuir el chatbot a múltiples organizaciones desde un único servidor centralizado — por ejemplo, como complemento de una plataforma SaaS donde cada organización contratante tiene una cuota de consultas diarias.

### Arquitectura

```
┌─────────────────────────────────────────────┐
│           Servidor central (SaaS)            │
│                                              │
│  ┌──────────────────────────────────────┐   │
│  │  Chatbot Service (FastAPI)            │   │
│  │                                      │   │
│  │  FAISS index único (manuales SaaS)   │   │
│  │  Redis → cuotas por org_id           │   │
│  └──────────────────────────────────────┘   │
│                                              │
└──────────────────────────────────────────────┘
         ▲                ▲               ▲
    Organización A   Organización B   Organización C
    (100 q/día)      (100 q/día)      (500 q/día)
```

El índice FAISS es **compartido** — contiene los manuales del proveedor SaaS, indexados una sola vez. No hay aislamiento de documentos por cliente porque todos consultan la misma base de conocimiento.

### Cambios necesarios en el código

**1. Añadir `org_id` al endpoint `/query`**

```python
class QueryRequest(BaseModel):
    question: str
    session_id: str = ""
    lang: str = "es"
    org_id: str  # ← nuevo campo obligatorio
```

**2. Middleware de cuota diaria (Redis)**

```python
import redis
from fastapi import HTTPException

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

CUOTAS = {
    "standard_plus": 100,   # queries/día
    "premium":       500,
}

def check_quota(org_id: str, plan: str):
    key = f"quota:{org_id}:{date.today()}"
    uso = r.incr(key)
    if uso == 1:
        r.expire(key, 86400)  # expira a medianoche (24h)
    limite = CUOTAS.get(plan, 100)
    if uso > limite:
        raise HTTPException(429, f"Cuota diaria alcanzada ({limite} consultas/día)")
```

**3. Auth por organización**

En lugar de una `CLIENT_API_KEY` global, cada organización tiene su propia key que identifica el `org_id` y el `plan` contratado:

```python
ORG_KEYS = {
    "key_org_abc123": {"org_id": "org_A", "plan": "standard_plus"},
    "key_org_xyz789": {"org_id": "org_B", "plan": "premium"},
}

def get_org(api_key: str = Header(..., alias="X-API-Key")):
    org = ORG_KEYS.get(api_key)
    if not org:
        raise HTTPException(401, "API key inválida")
    return org
```

En producción, estas keys se almacenarían en base de datos y se generarían automáticamente al activar el complemento para cada organización.

**4. Endpoint `/query` con cuota integrada**

```python
@app.post("/query")
async def query(req: QueryRequest, org=Depends(get_org)):
    check_quota(org["org_id"], org["plan"])
    # ... lógica RAG normal
```

### Variables de entorno adicionales

| Variable       | Descripción                                  |
|----------------|----------------------------------------------|
| `REDIS_URL`    | URL de Redis (default: `redis://localhost:6379`) |
| `DEFAULT_PLAN` | Plan por defecto si no se especifica (`standard_plus`) |

### Resumen del flujo

1. La plataforma SaaS activa el complemento para una organización → genera una `X-API-Key` única
2. El frontend SaaS incluye esa key en cada llamada al chatbot
3. El chatbot valida la key, identifica la organización y verifica la cuota diaria en Redis
4. Si hay cuota disponible, responde; si no, devuelve `HTTP 429`
5. El contador se reinicia automáticamente cada 24 horas

### Requisitos adicionales

- **Redis 6+** instalado en el mismo servidor o accesible por red interna
- La gestión de organizaciones y keys debería hacerse desde un panel de administración o directamente desde la base de datos de la plataforma SaaS
