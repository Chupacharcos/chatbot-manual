# 🤖 Chatbot RAG - Manual Empresarial

Sistema de chatbot inteligente con RAG usando FAISS.

## 🛠️ Stack

- Python 3.11+
- LangChain
- FAISS
- Groq API (Llama 3.3)

## 📋 Instalación
```bash
# Clonar
git clone [URL]
cd chatbot-manual

# Entorno virtual
python -m venv venv
venv\Scripts\activate

# Dependencias
pip install -r requirements.txt

# Configurar .env
GROQ_API_KEY=tu_key_aqui

# Procesar manual
python src/process_manual.py

# Ejecutar
python src/chatbot.py
```

## 🔐 Seguridad

- No subir `.env`
- No subir PDFs
- Repositorio privado