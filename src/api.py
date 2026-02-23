import os
import sys
import uuid
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from rag_engine import RAGEngine, MAX_HISTORY

load_dotenv()

# ─── App ─────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Asistente Virtual IA",
    description="API REST para el chatbot RAG multiidioma",
    version="2.0"
)

# ─── CORS ────────────────────────────────────────────────────────────────────
# Los orígenes permitidos se leen del .env (variable APP_URL).
# El setup.sh configura esto automáticamente durante la instalación.

app_url = os.getenv("APP_URL", "*")
origins = ["*"] if app_url == "*" else [o.strip() for o in app_url.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_methods=["POST", "DELETE", "GET"],
    allow_headers=["*"],
)

# ─── RAG Engine (una sola instancia — índices compartidos entre sesiones) ────

rag = RAGEngine()

# ─── Sesiones ─────────────────────────────────────────────────────────────────
# Cada session_id tiene su propio historial de conversación independiente.
# El cliente genera el session_id la primera vez y lo reutiliza en cada llamada.

sessions: dict[str, list] = {}

# ─── Modelos de datos ────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    question:   str
    lang:       str  = "es"
    session_id: str  = ""    # Si vacío, se genera uno nuevo automáticamente

class QueryResponse(BaseModel):
    answer:     str
    lang:       str
    sources:    list
    session_id: str          # Siempre se devuelve para que el cliente lo guarde

# ─── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/")
def root():
    """Comprueba que el servidor está funcionando."""
    return {"status": "ok", "message": "Asistente Virtual IA activo"}


@app.post("/query", response_model=QueryResponse)
def query(request: QueryRequest):
    """
    Consulta el manual empresarial.

    - **question**:   Pregunta en lenguaje natural
    - **lang**:       Idioma del manual (es, en, ca, pt)
    - **session_id**: ID de sesión del usuario. Si no se envía, se genera uno nuevo.
    """
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La pregunta no puede estar vacía")

    # Obtener o crear sesión
    session_id = request.session_id.strip() or str(uuid.uuid4())
    if session_id not in sessions:
        sessions[session_id] = []

    history = sessions[session_id]

    # Consultar el motor RAG pasándole el historial de esta sesión
    result = rag.query(
        question=request.question,
        lang=request.lang,
        history=history
    )

    # Actualizar historial de esta sesión
    history.append({"role": "user",      "content": request.question})
    history.append({"role": "assistant", "content": result["answer"]})

    # Limitar tamaño del historial
    if len(history) > MAX_HISTORY * 2:
        sessions[session_id] = history[-(MAX_HISTORY * 2):]

    return {
        "answer":     result["answer"],
        "lang":       result["lang"],
        "sources":    result["sources"],
        "session_id": session_id
    }


@app.delete("/history/{session_id}")
def clear_history(session_id: str):
    """Borra el historial de una sesión concreta."""
    if session_id in sessions:
        sessions.pop(session_id)
    return {"status": "ok", "message": f"Historial de sesión '{session_id}' borrado"}


@app.delete("/history")
def clear_all_history():
    """Borra el historial de todas las sesiones (solo para administración)."""
    sessions.clear()
    return {"status": "ok", "message": "Historial de todas las sesiones borrado"}