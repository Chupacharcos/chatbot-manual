# 🤖 Chatbot RAG - Manual Empresarial

Sistema de chatbot inteligente con RAG (Retrieval-Augmented Generation) usando FAISS y re-ranking semántico.

## 🛠️ Stack

- Python 3.11+
- FAISS (búsqueda semántica)
- Sentence Transformers + Cross-Encoder (embeddings y re-ranking)
- Groq API (Llama 3.3 70B)

## 🌍 Idiomas soportados

`es` Español · `en` English · `ca` Català · `pt` Português

## 📋 Instalación
```bash
# Clonar
git clone [URL]
cd chatbot-manual

# Entorno virtual
python -m venv venv
venv\Scripts\activate  # Windows
source venv/bin/activate  # Linux/Mac

# Dependencias
pip install -r requirements.txt
```

## ⚙️ Configuración

Crea un archivo `.env` en la raíz:
```
GROQ_API_KEY=tu_key_aqui
```

## 🚀 Uso

**1. Procesar el manual PDF:**
```bash
python src/process_manual.py --lang es --pdf data/manual_es.pdf
python src/process_manual.py --lang en --pdf data/manual_en.pdf
```

**2. Ejecutar el chatbot:**
```bash
python src/chatbot.py
```

## 🔐 Seguridad

- No subir `.env`
- No subir PDFs
- No subir la carpeta `faiss_index/`
- Repositorio privado recomendado