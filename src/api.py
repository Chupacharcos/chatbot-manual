import os
import sys
import uuid
import logging
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException, Security, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
from dotenv import load_dotenv

from rag_engine import RAGEngine, MAX_HISTORY

load_dotenv()

# ─── Logging ──────────────────────────────────────────────────────────────────

os.makedirs("logs", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/chatbot.log", encoding="utf-8"),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Asistente Virtual IA",
    description="API REST para el chatbot RAG multiidioma",
    version="2.0"
)

# ─── CORS (ARREGLADO) ─────────────────────────────────────────────────────────

# En producción detrás de Nginx es mejor permitir todo
# y controlar seguridad con API Key

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],   # ← IMPORTANTE (antes faltaba OPTIONS)
    allow_headers=["*"],
)

# ─── Autenticación por API Key ────────────────────────────────────────────────

CLIENT_API_KEY = os.getenv("CLIENT_API_KEY", "")
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

def verify_api_key(key: str = Security(api_key_header)):
    if not CLIENT_API_KEY:
        return
    if key != CLIENT_API_KEY:
        log.warning(f"Intento de acceso con clave inválida: {key}")
        raise HTTPException(status_code=403, detail="API Key inválida o ausente")

# ─── RAG Engine ───────────────────────────────────────────────────────────────

rag = RAGEngine()

# ─── Sesiones ─────────────────────────────────────────────────────────────────

sessions: dict[str, list] = {}

# ─── Modelos ──────────────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    question: str
    lang: str = "es"
    session_id: str = ""

class QueryResponse(BaseModel):
    answer: str
    lang: str
    sources: list
    session_id: str

# ─── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"status": "ok", "message": "Asistente Virtual IA activo"}


@app.post("/query", response_model=QueryResponse, dependencies=[Depends(verify_api_key)])
def query(request: QueryRequest):

    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La pregunta no puede estar vacía")

    session_id = request.session_id.strip() or str(uuid.uuid4())

    if session_id not in sessions:
        sessions[session_id] = []

    history = sessions[session_id]

    start = time.time()

    result = rag.query(
        question=request.question,
        lang=request.lang,
        history=history
    )

    elapsed = round(time.time() - start, 2)

    history.append({"role": "user", "content": request.question})
    history.append({"role": "assistant", "content": result["answer"]})

    if len(history) > MAX_HISTORY * 2:
        sessions[session_id] = history[-(MAX_HISTORY * 2):]

    sources_info = " | ".join([
        f"{d.get('section','?')} p.{d.get('page','?')}"
        for d in result["sources"]
    ])

    log.info(
        f"QUERY | session={session_id[:8]}... | lang={request.lang} | "
        f"time={elapsed}s | sources=[{sources_info}] | "
        f"q={request.question[:80]!r}"
    )

    return {
        "answer": result["answer"],
        "lang": result["lang"],
        "sources": result["sources"],
        "session_id": session_id
    }


@app.delete("/history/{session_id}", dependencies=[Depends(verify_api_key)])
def clear_session(session_id: str):
    if session_id in sessions:
        sessions.pop(session_id)
        log.info(f"HISTORY_CLEAR | session={session_id[:8]}...")
    return {"status": "ok", "message": f"Historial de sesión '{session_id}' borrado"}


@app.delete("/history", dependencies=[Depends(verify_api_key)])
def clear_all_history():
    count = len(sessions)
    sessions.clear()
    log.info(f"HISTORY_CLEAR_ALL | sesiones eliminadas={count}")
    return {"status": "ok", "message": f"{count} sesiones borradas"}


@app.get("/stats", dependencies=[Depends(verify_api_key)])
def stats():
    return {
        "sesiones_activas": len(sessions),
        "mensajes_totales": sum(len(h) for h in sessions.values()),
    }