import os
import sys
import uuid
import logging
import time
import unicodedata
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException, Security, Depends, UploadFile, File, Form, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
from dotenv import load_dotenv
import faiss
import numpy as np
from sentence_transformers import SentenceTransformer

from rag_engine import RAGEngine, MAX_HISTORY
from process_manual import (
    extract_text_from_pdf,
    extract_sections,
    create_chunks,
    EMBEDDINGS_MODEL,
)
from saas import (
    init_db,
    get_client_by_key,
    create_client,
    list_clients,
    update_client,
    check_quota,
    log_usage,
    get_usage_report,
    get_client_remaining,
    PLANS,
)

load_dotenv()

# ─── Init SaaS DB ─────────────────────────────────────────────────────────────

init_db()

# ─── Logging ──────────────────────────────────────────────────────────────────

os.makedirs("logs", exist_ok=True)
os.makedirs("uploads", exist_ok=True)

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
    title="Asistente Virtual IA — SaaS",
    description="API REST para el chatbot RAG multiidioma con gestión multi-tenant",
    version="3.0"
)

# ─── CORS ─────────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://adrianmoreno-dev.com", "http://127.0.0.1", "http://localhost"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Autenticación multi-tenant ───────────────────────────────────────────────

ADMIN_SECRET = os.getenv("ADMIN_SECRET", "")
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def get_current_client(key: str = Security(api_key_header)):
    """Valida la API key contra la DB SaaS y devuelve el cliente."""
    if not key:
        raise HTTPException(status_code=403, detail="Se requiere X-API-Key")
    client = get_client_by_key(key)
    if not client:
        log.warning(f"Acceso denegado — clave inválida o cliente inactivo: {key[:12]}...")
        raise HTTPException(status_code=403, detail="API Key inválida o cliente inactivo")
    return client


def require_admin(x_admin_secret: str = Header(default="")):
    """Protege los endpoints /admin/* con ADMIN_SECRET."""
    if not ADMIN_SECRET:
        raise HTTPException(status_code=500, detail="ADMIN_SECRET no configurado en el servidor")
    if x_admin_secret != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail="Admin secret incorrecto")


# ─── RAG Engine ───────────────────────────────────────────────────────────────

rag = RAGEngine()

# Reutilizar el modelo ya cargado por RAGEngine: antes se instanciaba una
# SEGUNDA copia del mismo modelo (~1GB duplicado en RAM).
embedding_model = rag.embeddings_model

# ─── Sesiones ─────────────────────────────────────────────────────────────────

sessions: dict[str, dict] = {}
SESSION_TTL_HOURS = 4


def cleanup_expired_sessions():
    cutoff = datetime.now() - timedelta(hours=SESSION_TTL_HOURS)
    expired = [
        sid for sid, s in sessions.items()
        if datetime.fromisoformat(s.get("created_at", datetime.now().isoformat())) < cutoff
    ]
    for sid in expired:
        session = sessions.pop(sid)
        pdf_path = session.get("pdf_path")
        if pdf_path and os.path.exists(pdf_path):
            try:
                os.remove(pdf_path)
            except Exception:
                pass
    if expired:
        log.info(f"🧹 Sesiones expiradas eliminadas: {len(expired)}")


# ─── Modelos Pydantic ─────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    question: str
    lang: str = "es"
    session_id: str = ""

class QueryResponse(BaseModel):
    answer: str
    lang: str
    sources: list
    session_id: str

class UploadResponse(BaseModel):
    success: bool
    session_id: str
    message: str
    chunks: int = 0

class CreateClientRequest(BaseModel):
    name: str
    plan: str = "free"
    api_key: str = ""

class UpdateClientRequest(BaseModel):
    plan: str = None
    active: bool = None


# ─── Funciones auxiliares ─────────────────────────────────────────────────────

def build_faiss_index_from_pdf(pdf_path: str, lang: str = "es") -> tuple:
    log.info(f"📄 Procesando PDF: {pdf_path}")
    pages = extract_text_from_pdf(pdf_path)
    if not pages:
        raise Exception("No se pudo extraer texto del PDF")
    sections = extract_sections(pages)
    log.info(f"✅ {len(sections)} secciones identificadas")

    total_chars = sum(len(s["content"]) for s in sections)
    if total_chars < 15000:
        dyn_chunk, dyn_overlap = 700, 80
    elif total_chars < 60000:
        dyn_chunk, dyn_overlap = 1000, 120
    else:
        dyn_chunk, dyn_overlap = 1200, 150

    chunks = create_chunks(sections, dyn_chunk, dyn_overlap)
    log.info(f"✅ {len(chunks)} chunks (chunk_size={dyn_chunk})")

    texts = [c["text"] for c in chunks]
    embeddings = embedding_model.encode(texts, show_progress_bar=False)
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))
    log.info(f"✅ Índice FAISS creado con {len(chunks)} vectores")
    return index, chunks, embeddings


def _normalize(text: str) -> str:
    return unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode('ascii').lower()


def keyword_search_chunks(chunks: list, query: str, top_k: int = 5) -> list:
    stopwords = {
        "como", "una", "unos", "unas", "los", "las", "que", "del", "con",
        "por", "para", "en", "de", "la", "el", "un", "es", "se", "al",
        "mas", "pero", "hay", "tambien", "dime", "que", "sobre", "cual",
    }
    query_words = [
        _normalize(w).strip("¿?.,;:!¡")
        for w in query.split()
        if len(w) > 3 and _normalize(w) not in stopwords
    ]
    if not query_words:
        return []
    scored = []
    for chunk in chunks:
        text_norm = _normalize(chunk["text"])
        matches = sum(1 for w in query_words if w in text_norm)
        if matches > 0:
            scored.append((matches, chunk))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [chunk for _, chunk in scored[:top_k]]


def query_session_index(session_id: str, question: str, lang: str = "es", top_k: int = 8) -> dict:
    if session_id not in sessions:
        raise Exception(f"Sesión {session_id} no encontrada")
    session = sessions[session_id]
    index = session["faiss_index"]
    chunks = session["chunks"]
    q_emb = embedding_model.encode([question], show_progress_bar=False)[0]
    distances, indices = index.search(
        np.array([q_emb]).astype('float32'),
        min(top_k, len(chunks))
    )
    relevant_chunks = [chunks[i] for i in indices[0] if i < len(chunks)]
    return {"relevant_chunks": relevant_chunks, "distances": distances[0].tolist()}


# ─── Endpoints públicos ───────────────────────────────────────────────────────

@app.get("/")
def root():
    return {
        "status": "ok",
        "message": "Asistente Virtual IA activo",
        "version": "3.0",
        "features": ["static_index", "dynamic_pdf_upload", "saas_multi_tenant"],
    }


@app.post("/upload", response_model=UploadResponse)
async def upload_pdf(
    pdf: UploadFile = File(...),
    session_id: str = Form(default=""),
    lang: str = Form(default="es"),
    persona: str = Form(default=""),
    client: dict = Depends(get_current_client),
):
    """Sube un PDF y crea una sesión de chatbot (requiere X-API-Key)."""
    try:
        cleanup_expired_sessions()

        if not pdf.filename.endswith('.pdf'):
            raise HTTPException(status_code=400, detail="Solo se aceptan archivos PDF")

        plan = PLANS.get(client["plan"], PLANS["free"])
        max_bytes = plan["max_pdf_mb"] * 1024 * 1024

        if not session_id.strip():
            session_id = str(uuid.uuid4())

        upload_dir = Path("uploads")
        upload_dir.mkdir(exist_ok=True)
        pdf_path = upload_dir / f"{session_id}.pdf"

        content = await pdf.read()

        if len(content) > max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"PDF supera el límite de tu plan ({plan['max_pdf_mb']} MB). "
                       f"Tamaño recibido: {len(content) // (1024*1024)} MB"
            )

        with open(pdf_path, "wb") as f:
            f.write(content)

        index, chunks, embeddings = build_faiss_index_from_pdf(str(pdf_path), lang)

        sessions[session_id] = {
            "history": [],
            "pdf_path": str(pdf_path),
            "pdf_filename": pdf.filename,
            "faiss_index": index,
            "chunks": chunks,
            "embeddings": embeddings,
            "lang": lang,
            "persona": persona,
            "client_id": client["id"],
            "created_at": datetime.now().isoformat(),
        }

        log.info(
            f"✅ PDF procesado | client={client['name']} | session={session_id[:8]}... | "
            f"chunks={len(chunks)} | lang={lang}"
        )

        return {
            "success": True,
            "session_id": session_id,
            "message": f"PDF '{pdf.filename}' procesado correctamente",
            "chunks": len(chunks),
        }

    except HTTPException:
        raise
    except Exception as e:
        log.error(f"❌ Error en /upload: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error procesando PDF: {str(e)}")


@app.post("/query", response_model=QueryResponse)
def query(request: QueryRequest, client: dict = Depends(get_current_client)):
    """Consulta el chatbot (requiere X-API-Key y cuota disponible)."""
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La pregunta no puede estar vacía")

    # Verificar cuota ANTES de llamar al LLM
    ok, msg = check_quota(client)
    if not ok:
        raise HTTPException(status_code=429, detail=msg)

    session_id = request.session_id.strip() or str(uuid.uuid4())

    if session_id not in sessions:
        sessions[session_id] = {
            "history": [],
            "faiss_index": None,
            "chunks": None,
            "lang": request.lang,
            "client_id": client["id"],
            "created_at": datetime.now().isoformat(),
        }

    history = sessions[session_id].get("history", [])
    start = time.time()

    if sessions[session_id]["faiss_index"] is not None:
        log.info(f"🔍 Índice dinámico — session={session_id[:8]} client={client['name']}")
        try:
            search_query = request.question
            if len(request.question.split()) <= 5 and history:
                last_user = next(
                    (h["content"] for h in reversed(history) if h["role"] == "user"), ""
                )
                if last_user:
                    search_query = f"{last_user} {request.question}"
                    log.info(f"🔄 Query reformulada: {search_query[:80]!r}")

            rag_result = query_session_index(session_id, search_query, request.lang)
            semantic_chunks = rag_result["relevant_chunks"]

            kw_chunks = keyword_search_chunks(sessions[session_id]["chunks"], search_query)
            seen_keys = {c["text"][:80] for c in semantic_chunks}
            for c in kw_chunks:
                key = c["text"][:80]
                if key not in seen_keys:
                    seen_keys.add(key)
                    semantic_chunks.append(c)

            relevant_chunks = semantic_chunks[:10]

            context = "\n\n".join([
                f"[{c['section']} - p.{c['page']}]\n{c['text'][:1000]}"
                for c in relevant_chunks
            ])

            result = rag.query_with_context(
                question=request.question,
                context=context,
                lang=request.lang,
                history=history,
                persona=sessions[session_id].get("persona", ""),
            )
            result["sources"] = relevant_chunks

        except Exception as e:
            log.error(f"Error en índice dinámico: {e}")
            result = {
                "answer": f"Error procesando la consulta: {str(e)}",
                "lang": request.lang,
                "sources": [],
                "tokens_in": 0,
                "tokens_out": 0,
            }
    else:
        log.info(f"🔍 Índice estático — session={session_id[:8]} client={client['name']}")
        result = rag.query(
            question=request.question,
            lang=request.lang,
            history=history,
        )

    elapsed = round(time.time() - start, 2)

    # Registrar uso de tokens
    tokens_in = result.get("tokens_in", 0)
    tokens_out = result.get("tokens_out", 0)
    if tokens_in or tokens_out:
        log_usage(client["id"], tokens_in, tokens_out)

    history.append({"role": "user", "content": request.question})
    history.append({"role": "assistant", "content": result["answer"]})

    if len(history) > MAX_HISTORY * 2:
        sessions[session_id]["history"] = history[-(MAX_HISTORY * 2):]
    else:
        sessions[session_id]["history"] = history

    sources_info = " | ".join([
        f"{d.get('section','?')} p.{d.get('page','?')}"
        for d in result.get("sources", [])
    ])

    log.info(
        f"QUERY | client={client['name']} | session={session_id[:8]}... | lang={request.lang} | "
        f"time={elapsed}s | tokens={tokens_in}+{tokens_out} | q={request.question[:80]!r}"
    )

    return {
        "answer": result["answer"],
        "lang": result.get("lang", request.lang),
        "sources": result.get("sources", []),
        "session_id": session_id,
    }


@app.delete("/history/{session_id}")
def clear_session(session_id: str, client: dict = Depends(get_current_client)):
    if session_id in sessions:
        # Solo puede borrar sus propias sesiones
        if sessions[session_id].get("client_id") != client["id"]:
            raise HTTPException(status_code=403, detail="No tienes acceso a esta sesión")
        session = sessions.pop(session_id)
        pdf_path = session.get("pdf_path")
        if pdf_path and os.path.exists(pdf_path):
            try:
                os.remove(pdf_path)
            except Exception:
                pass
        log.info(f"HISTORY_CLEAR | client={client['name']} | session={session_id[:8]}...")
    return {"status": "ok", "message": f"Sesión '{session_id}' eliminada"}


@app.get("/stats")
def stats(client: dict = Depends(get_current_client)):
    """Estadísticas del cliente actual + cuota restante."""
    client_sessions = [s for s in sessions.values() if s.get("client_id") == client["id"]]
    remaining = get_client_remaining(client)
    return {
        "client": client["name"],
        "plan": client["plan"],
        "sesiones_activas": len(client_sessions),
        "mensajes_totales": sum(len(s.get("history", [])) for s in client_sessions),
        "sesiones_con_pdf": sum(1 for s in client_sessions if s.get("faiss_index") is not None),
        "quota": remaining,
    }


# ─── Endpoints Admin ──────────────────────────────────────────────────────────

@app.post("/admin/clients", dependencies=[Depends(require_admin)])
def admin_create_client(req: CreateClientRequest):
    """Crea un nuevo cliente SaaS."""
    try:
        client = create_client(name=req.name, plan=req.plan, api_key=req.api_key)
        log.info(f"ADMIN | Nuevo cliente: {client['name']} | plan={client['plan']}")
        return {"status": "created", "client": client}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/admin/clients", dependencies=[Depends(require_admin)])
def admin_list_clients():
    """Lista todos los clientes con su cuota restante hoy."""
    clients = list_clients()
    result = []
    for c in clients:
        remaining = get_client_remaining(c)
        result.append({**c, "quota": remaining})
    return {"clients": result, "plans": PLANS}


@app.patch("/admin/clients/{client_id}", dependencies=[Depends(require_admin)])
def admin_update_client(client_id: int, req: UpdateClientRequest):
    """Actualiza el plan o estado activo de un cliente."""
    try:
        client = update_client(client_id, plan=req.plan, active=req.active)
        if not client:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")
        log.info(f"ADMIN | Actualizado cliente id={client_id}: plan={req.plan} active={req.active}")
        return {"status": "updated", "client": client}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/admin/usage", dependencies=[Depends(require_admin)])
def admin_usage(days: int = 7):
    """Informe de uso de tokens de los últimos N días."""
    report = get_usage_report(days=days)
    return {"days": days, "usage": report}


@app.get("/admin/plans", dependencies=[Depends(require_admin)])
def admin_plans():
    """Lista los planes disponibles y sus límites."""
    return {"plans": PLANS}
