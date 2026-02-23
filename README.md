# 🤖 Asistente Virtual IA — Chatbot RAG Multiidioma

Sistema de chatbot inteligente para consultar manuales empresariales, basado en RAG (Retrieval-Augmented Generation) con búsqueda semántica, re-ranking y chunking semántico.

## 🛠️ Stack

- **Python 3.11+**
- **FAISS** — búsqueda semántica sobre el manual
- **Sentence Transformers + Cross-Encoder** — embeddings y re-ranking
- **Groq API · Llama 3.3 70B** — generación de respuestas
- **FastAPI** — API REST para integración en apps web

## 🌍 Idiomas soportados

`es` Español · `en` English · `ca` Català · `pt` Português

---

## 📦 Estructura del proyecto

```
chatbot-manual/
├── src/
│   ├── process_manual.py    # Procesa el PDF (chunking semántico + índice FAISS)
│   ├── rag_engine.py        # Motor RAG (búsqueda + respuesta)
│   ├── chatbot.py           # Interfaz de línea de comandos
│   └── api.py               # Servidor FastAPI (API REST)
├── data/                    # Colocar aquí los PDFs del manual
│   └── .gitkeep
├── logs/                    # Logs generados automáticamente
├── docs/
│   └── guia_instalacion.pdf # Guía completa de instalación
├── .env.example             # Plantilla para configurar variables de entorno
├── .gitignore
├── requirements.txt
├── setup.sh                 # Instalación automática — ejecutar una sola vez
└── README.md
```

---

## 🚀 Instalación rápida

### Requisitos previos
- Ubuntu Server 20.04 o superior
- Python 3.11+
- Git

### Pasos

**1. Clonar el repositorio**
```bash
git clone https://github.com/Chupacharcos/chatbot-manual.git
cd chatbot-manual
```

**2. Configurar variables de entorno**
```bash
cp .env.example .env
nano .env
```
Rellena `GROQ_API_KEY` con tu clave de https://console.groq.com

**3. Colocar el PDF del manual**
```
data/manual_es.pdf   ← español
data/manual_en.pdf   ← english
data/manual_ca.pdf   ← català
data/manual_pt.pdf   ← português
```

**4. Ejecutar el setup**
```bash
bash setup.sh
```

**5. Arrancar el servidor**
```bash
bash start.sh
```

---

## 🔌 Integración en tu app web

Cada usuario tiene su propia sesión de conversación mediante `session_id`. Si la autenticación está activa, envía también la cabecera `X-API-Key`.

```javascript
let sessionId = sessionStorage.getItem('chatbot_session_id') || '';

async function preguntar(pregunta, lang = 'es') {
  const res = await fetch('http://IP_DEL_SERVIDOR:8000/query', {
    method:  'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key':    'tu_client_api_key'   // si la autenticación está activa
    },
    body: JSON.stringify({ question: pregunta, lang, session_id: sessionId })
  });

  const data = await res.json();

  sessionId = data.session_id;
  sessionStorage.setItem('chatbot_session_id', sessionId);

  return data.answer;
}
```

### Endpoints disponibles

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| `GET`    | `/`                      | No  | Estado del servidor |
| `POST`   | `/query`                 | Sí  | Consultar el manual |
| `GET`    | `/stats`                 | Sí  | Sesiones activas y mensajes totales |
| `DELETE` | `/history/{session_id}`  | Sí  | Borrar historial de un usuario |
| `DELETE` | `/history`               | Sí  | Borrar historial de todas las sesiones |
| `GET`    | `/docs`                  | No  | Documentación Swagger interactiva |

### Parámetros de `/query`

| Parámetro    | Tipo   | Default | Descripción |
|--------------|--------|---------|-------------|
| `question`   | string | —       | Pregunta en lenguaje natural |
| `lang`       | string | `es`    | Idioma: `es`, `en`, `ca`, `pt` |
| `session_id` | string | `""`    | ID de sesión — vacío en la primera llamada |

---

## 📊 Logs

Los logs se guardan automáticamente en `logs/chatbot.log`. Para verlos en tiempo real:

```bash
tail -f logs/chatbot.log
```

Formato de cada entrada:
```
2026-02-23 10:30:15 | INFO | QUERY | session=a1b2c3d4... | lang=es | time=1.23s | sources=[Sección 3 p.12] | q='¿Cuál es el procedimiento de auditoría?'
```

---

## 📖 Guía de instalación completa

📄 [`docs/guia_instalacion.pdf`](docs/guia_instalacion.pdf)

---

## 🔐 Seguridad

- `.env` nunca se sube al repositorio
- PDFs del cliente nunca se suben al repositorio
- `CLIENT_API_KEY` en `.env` protege el acceso a la API
- `APP_URL` en `.env` restringe el CORS al dominio del cliente
- Cada usuario tiene historial aislado por `session_id`

---

## 🔄 Actualizar el manual

```bash
source venv/bin/activate
python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
bash start.sh
```