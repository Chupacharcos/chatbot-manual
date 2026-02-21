import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from rag_engine import RAGEngine

load_dotenv()

# ─── App ─────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Asistente Virtual IA",
    description="API REST para el chatbot RAG multiidioma",
    version="2.0"
)

# ─── CORS ────────────────────────────────────────────────────────────────────
# Los orígenes permitidos se leen del archivo .env (variable APP_URL).
# El setup.sh configura esto automáticamente durante la instalación.
# Si APP_URL no está definida, permite cualquier origen ("*").

app_url = os.getenv("APP_URL", "*")
origins = ["*"] if app_url == "*" else [o.strip() for o in app_url.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_methods=["POST", "DELETE", "GET"],
    allow_headers=["*"],
)

# ─── RAG Engine (se carga una sola vez al arrancar) ──────────────────────────

rag = RAGEngine()

# ─── Modelos de datos ────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    question: str
    lang: str = "es"  # Idioma por defecto: español

class QueryResponse(BaseModel):
    answer: str
    lang: str
    sources: list

# ─── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/")
def root():
    """Comprueba que el servidor está funcionando."""
    return {"status": "ok", "message": "Asistente Virtual IA activo"}


@app.post("/query", response_model=QueryResponse)
def query(request: QueryRequest):
    """
    Consulta el manual empresarial.

    - **question**: Pregunta en lenguaje natural
    - **lang**: Idioma del manual a consultar (es, en, ca, pt)
    """
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La pregunta no puede estar vacía")

    result = rag.query(request.question, lang=request.lang)
    return result


@app.delete("/history")
def clear_history():
    """Borra el historial de conversación."""
    rag.clear_history()
    return {"status": "ok", "message": "Historial borrado"}