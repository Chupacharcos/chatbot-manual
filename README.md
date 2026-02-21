# 🤖 Asistente Virtual IA — Chatbot RAG Multiidioma

Sistema de chatbot inteligente para consultar manuales empresariales, basado en RAG (Retrieval-Augmented Generation) con búsqueda semántica y re-ranking.

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
│   ├── process_manual.py    # Procesa el PDF y genera el índice FAISS
│   ├── rag_engine.py        # Motor RAG (búsqueda + respuesta)
│   ├── chatbot.py           # Interfaz de línea de comandos
│   └── api.py               # Servidor FastAPI (API REST)
├── data/                    # Colocar aquí los PDFs del manual
├── docs/
│   └── guia_instalacion.pdf  # Guía completa de instalación
├── .env.example             # Plantilla para configurar la API Key
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

**2. Configurar la API Key**

Crea el archivo `.env` en la raíz del proyecto:
```
GROQ_API_KEY=gsk_tu_clave_aqui
```
Obtén tu clave gratuita en: https://console.groq.com

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
El script instala dependencias, configura el servidor y procesa el manual automáticamente.

**5. Arrancar el servidor**
```bash
bash start.sh
```

---

## 🔌 Integración en tu app web

Una vez el servidor está arrancado, añade este snippet en tu HTML:

```javascript
async function preguntar(pregunta) {
  const res = await fetch('http://IP_DEL_SERVIDOR:8000/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ question: pregunta, lang: 'es' })
  });
  const data = await res.json();
  return data.answer;
}
```

### Endpoints disponibles

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| `POST` | `/query` | Consultar el manual |
| `DELETE` | `/history` | Borrar historial de conversación |
| `GET` | `/docs` | Documentación Swagger interactiva |

---

## 📖 Guía de instalación completa

Consulta la guía paso a paso para clientes en:

📄 [`docs/guia_instalacion.pdf`](docs/guia_instalacion.pdf)

Incluye instrucciones detalladas para el cliente (configuración de API Key y PDF) y para el equipo IT (instalación, puesta en marcha e integración en la app web).

---

## 🔐 Seguridad

- El archivo `.env` nunca se sube al repositorio
- Los PDFs del cliente nunca se suben al repositorio
- En producción, configura `APP_URL` en `.env` con el dominio exacto de tu app para restringir el CORS

---

## 🔄 Actualizar el manual

Cuando cambie el PDF, solo hay que reprocesarlo:

```bash
source venv/bin/activate
python3 src/process_manual.py --lang es --pdf data/manual_es.pdf
bash start.sh
```