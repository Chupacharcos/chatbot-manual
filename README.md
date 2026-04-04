# Asistente Virtual IA — Chatbot RAG Multiidioma

Sistema de chatbot inteligente para consultar documentos empresariales basado en RAG (Retrieval-Augmented Generation). Combina búsqueda semántica vectorial con búsqueda por palabras clave para garantizar que el asistente encuentre la información relevante independientemente de cómo formule la pregunta el usuario.

## Características

- **Búsqueda híbrida**: semántica (FAISS) + palabras clave, con normalización de acentos
- **Multiidioma automático**: responde en el mismo idioma que use el usuario (sin configuración)
- **Personalidad configurable**: el cliente puede definir el rol y actitud del asistente
- **Markdown en respuestas**: formato enriquecido (listas, negritas, encabezados)
- **Historial de conversación**: el asistente recuerda el contexto de los últimos mensajes
- **Dos modos**: índices estáticos pre-procesados (producción) o PDFs dinámicos desde la web
- **SaaS multi-tenant nativo**: múltiples clientes empresa con API keys independientes, planes de tokens y panel de administración REST

## Stack tecnológico

- **Python 3.11+**
- **FAISS** — búsqueda vectorial semántica (índices en disco y en RAM por sesión)
- **Sentence Transformers** (`intfloat/multilingual-e5-large`) — embeddings multiidioma
- **Cross-Encoder** (`mmarco-mMiniLMv2-L12-H384`) — re-ranking de resultados
- **Groq API · Llama 3.1 8B** — generación de respuestas (sin coste de infra)
- **FastAPI + Uvicorn** — API REST asíncrona v3.0
- **SQLite** — base de datos SaaS embebida (clientes, planes, uso de tokens)

---

## Estructura del proyecto

```
chatbot/
├── src/
│   ├── api.py               # Servidor FastAPI v3.0 (API REST + SaaS)
│   ├── rag_engine.py        # Motor RAG (búsqueda semántica + LLM + token tracking)
│   ├── saas.py              # Sistema multi-tenant (clientes, planes, cuotas SQLite)
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

Autenticación de cliente: cabecera `X-API-Key: {api_key_del_cliente}`
Autenticación de admin: cabecera `X-Admin-Secret: {admin_secret}`

### Endpoints de cliente

| Método   | Endpoint                  | Auth          | Descripción                               |
|----------|---------------------------|---------------|-------------------------------------------|
| `GET`    | `/`                       | No            | Estado del servidor y versión             |
| `POST`   | `/upload`                 | X-API-Key     | Subir PDF y crear sesión dinámica         |
| `POST`   | `/query`                  | X-API-Key     | Consultar el manual (consume cuota)       |
| `GET`    | `/stats`                  | X-API-Key     | Sesiones activas + cuota restante hoy     |
| `DELETE` | `/history/{session_id}`   | X-API-Key     | Borrar historial de una sesión propia     |
| `GET`    | `/docs`                   | No            | Documentación Swagger interactiva         |

### Endpoints de administración

| Método    | Endpoint                   | Auth            | Descripción                              |
|-----------|----------------------------|-----------------|------------------------------------------|
| `POST`    | `/admin/clients`           | X-Admin-Secret  | Crear nuevo cliente con plan             |
| `GET`     | `/admin/clients`           | X-Admin-Secret  | Listar todos los clientes y cuotas       |
| `PATCH`   | `/admin/clients/{id}`      | X-Admin-Secret  | Cambiar plan o desactivar cliente        |
| `GET`     | `/admin/usage?days=7`      | X-Admin-Secret  | Informe de uso de tokens por cliente     |
| `GET`     | `/admin/plans`             | X-Admin-Secret  | Ver planes disponibles y límites         |

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

| Variable         | Obligatoria | Descripción                                                     |
|------------------|-------------|-----------------------------------------------------------------|
| `GROQ_API_KEY`   | **Sí**      | Clave API de https://console.groq.com                           |
| `CLIENT_API_KEY` | Recomendada | API key del cliente demo/principal (se registra automáticamente en SQLite al arrancar) |
| `ADMIN_SECRET`   | Recomendada | Contraseña para los endpoints `/admin/*` (generar con `openssl rand -hex 24`) |
| `API_PORT`       | No          | Puerto del servidor (default: `8088`)                           |
| `APP_URL`        | No          | Origen CORS permitido (default: `*` = todos)                    |
| `SAAS_DB_PATH`   | No          | Ruta a la DB SQLite SaaS (default: `chatbot_saas.db`)           |

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

- `.env` y `chatbot_saas.db` nunca se suben al repositorio (incluidos en `.gitignore`)
- Los PDFs del cliente nunca se suben al repositorio
- Cada cliente tiene su propia `X-API-Key` — autenticación multi-tenant con SQLite
- Los endpoints `/admin/*` requieren cabecera `X-Admin-Secret` separada
- `APP_URL` restringe CORS al dominio del cliente (usar dominio concreto en producción, no `*`)
- Cada usuario tiene historial aislado por `session_id`, vinculado a su cliente

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

## Despliegue multi-tenant (SaaS)

El sistema incluye soporte nativo para múltiples clientes desde un único servidor. No requiere Redis ni dependencias externas: usa SQLite embebido.

### Arquitectura

```
┌─────────────────────────────────────────────────┐
│              Servidor central (SaaS)              │
│                                                   │
│  ┌───────────────────────────────────────────┐   │
│  │  Chatbot Service v3.0 (FastAPI)            │   │
│  │                                            │   │
│  │  FAISS index (manuales) — compartido       │   │
│  │  SQLite (chatbot_saas.db) — clientes/cuota │   │
│  └───────────────────────────────────────────┘   │
│                                                   │
└───────────────────────────────────────────────────┘
         ▲                 ▲                ▲
    Cliente A          Cliente B        Cliente C
    plan=free          plan=basic       plan=enterprise
    5k tokens/día      50k tokens/día   ilimitado
```

### Planes disponibles

| Plan         | Tokens/día | PDF máximo | Descripción                    |
|--------------|-----------|------------|--------------------------------|
| `free`       | 5.000     | 5 MB       | Pruebas y demos                |
| `basic`      | 50.000    | 20 MB      | Pequeñas empresas              |
| `pro`        | 500.000   | 50 MB      | Uso intensivo                  |
| `enterprise` | Ilimitado | 100 MB     | Sin restricciones              |

### Gestión de clientes (API admin)

```bash
# Variables necesarias
ADMIN_SECRET="tu_admin_secret_del_.env"
API_URL="http://127.0.0.1:8088"

# Crear nuevo cliente
curl -X POST $API_URL/admin/clients \
  -H "X-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"name": "Empresa ABC", "plan": "basic"}'
# Devuelve: {"client": {"id": 2, "api_key": "ck_...", "plan": "basic"}}

# Listar clientes con cuota restante hoy
curl $API_URL/admin/clients -H "X-Admin-Secret: $ADMIN_SECRET"

# Cambiar plan de un cliente
curl -X PATCH $API_URL/admin/clients/2 \
  -H "X-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"plan": "pro"}'

# Desactivar cliente (bloquear acceso sin borrar)
curl -X PATCH $API_URL/admin/clients/2 \
  -H "X-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"active": false}'

# Informe de uso últimos 7 días
curl "$API_URL/admin/usage?days=7" -H "X-Admin-Secret: $ADMIN_SECRET"
```

### Flujo de integración

1. Tú creas el cliente con `POST /admin/clients` → recibes su `api_key`
2. Proporcionas esa `api_key` al cliente (en su panel, por email, etc.)
3. El cliente incluye `X-API-Key: {api_key}` en cada llamada
4. El sistema verifica la cuota antes de cada consulta al LLM
5. Si supera la cuota diaria → HTTP 429 automático
6. Los contadores se reinician a las 00:00 UTC cada día

### Consultar cuota desde el lado cliente

```bash
curl http://IP:PUERTO/stats -H "X-API-Key: ck_abc123..."
# {"plan":"basic","quota":{"daily_limit":50000,"used_today":1234,"remaining":48766}}
```
