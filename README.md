# Asistente Virtual IA — Chatbot RAG Multiidioma

Sistema de chatbot inteligente para consultar manuales empresariales basado en RAG (Retrieval-Augmented Generation) con búsqueda semántica, re-ranking y chunking semántico.

## Stack tecnológico

- **Python 3.11+**
- **FAISS** — búsqueda semántica vectorial
- **Sentence Transformers** (`intfloat/multilingual-e5-large`) — embeddings multiidioma
- **Cross-Encoder** (`mmarco-mMiniLMv2-L12-H384`) — re-ranking de resultados
- **Groq API · Llama 3.1 8B** — generación de respuestas
- **FastAPI + Uvicorn** — API REST asíncrona

## Idiomas soportados

`es` Español · `en` English · `ca` Català · `pt` Português

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
source venv/bin/activate
python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
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

| Parámetro    | Tipo   | Obligatorio | Descripción                                    |
|--------------|--------|-------------|------------------------------------------------|
| `question`   | string | Sí          | Pregunta en lenguaje natural                   |
| `lang`       | string | No          | Idioma: `es`, `en`, `ca`, `pt` (default: `es`) |
| `session_id` | string | No          | ID de sesión — vacío en la primera llamada     |

**Response:**
```json
{
  "answer": "Según el manual, el proceso de alta de usuario consiste en...",
  "lang": "es",
  "sources": [
    {"section": "Gestión de usuarios", "page": 5, "text": "..."}
  ],
  "session_id": "a1b2c3d4-..."
}
```

### POST `/upload`

Sube un PDF y crea una sesión de consulta dinámica (modo desarrollo).

**Request:** `multipart/form-data`

| Campo        | Tipo   | Descripción                            |
|--------------|--------|----------------------------------------|
| `pdf`        | file   | Archivo PDF                            |
| `lang`       | string | Idioma (default: `es`)                 |
| `session_id` | string | ID de sesión (se genera si está vacío) |

**Response:**
```json
{
  "success": true,
  "session_id": "a1b2c3d4-...",
  "message": "PDF 'manual.pdf' procesado correctamente",
  "chunks": 45
}
```

---

## Integración en aplicación web

```javascript
let sessionId = sessionStorage.getItem('chatbot_session_id') || '';

async function preguntar(pregunta, lang = 'es') {
  const res = await fetch('http://IP_SERVIDOR:PUERTO/query', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': 'tu_client_api_key'
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

Los logs se guardan en `logs/chatbot.log`. Para verlos en tiempo real:

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
