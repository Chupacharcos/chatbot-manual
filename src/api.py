import os
import sys
import uuid
import logging
import time
import pickle
import shutil
import unicodedata
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException, Security, Depends, UploadFile, File, Form
from datetime import timedelta
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
    CHUNK_SIZE,
    CHUNK_OVERLAP,
)

load_dotenv()

# ─── Logging ──────────────────────────────────────────────────────────────────

os.makedirs("logs", exist_ok=True)
os.makedirs("uploads", exist_ok=True)
os.makedirs("faiss_sessions", exist_ok=True)

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
    description="API REST para el chatbot RAG multiidioma con soporte para PDFs dinámicos",
    version="2.1"
)

# ─── CORS ─────────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://adrianmoreno-dev.com", "http://127.0.0.1", "http://localhost"],
    allow_credentials=True,
    allow_methods=["*"],
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

# Cargar modelo de embeddings una sola vez
print("🧮 Cargando modelo de embeddings...")
embedding_model = SentenceTransformer(EMBEDDINGS_MODEL)
print("✅ Modelo de embeddings cargado")

# ─── Sesiones y almacenamiento de índices ──────────────────────────────────────

sessions: dict[str, dict] = {}

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

class UploadResponse(BaseModel):
    success: bool
    session_id: str
    message: str
    chunks: int = 0

# ─── Funciones auxiliares ─────────────────────────────────────────────────────

SESSION_TTL_HOURS = 4  # Sesiones inactivas se eliminan tras 4 horas

def cleanup_expired_sessions():
    """Elimina sesiones creadas hace más de SESSION_TTL_HOURS horas."""
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


def build_faiss_index_from_pdf(pdf_path: str, lang: str = "es") -> tuple:
    """
    Procesa un PDF y crea un índice FAISS listo para usar.
    
    Retorna: (index_faiss, chunks, embeddings)
    """
    log.info(f"📄 Procesando PDF: {pdf_path}")
    
    # 1. Extraer texto
    pages = extract_text_from_pdf(pdf_path)
    if not pages:
        raise Exception("No se pudo extraer texto del PDF")
    
    # 2. Identificar secciones
    sections = extract_sections(pages)
    log.info(f"✅ {len(sections)} secciones identificadas")
    
    # 3. Crear chunks con tamaño adaptativo.
    # Chunks más pequeños = mejor precisión FAISS + menos contenido descartado en contexto.
    total_chars = sum(len(s["content"]) for s in sections)
    if total_chars < 15000:       # PDF corto (<15 págs aprox)
        dyn_chunk, dyn_overlap = 700, 80
    elif total_chars < 60000:     # PDF mediano
        dyn_chunk, dyn_overlap = 1000, 120
    else:                         # PDF grande (>60 págs aprox)
        dyn_chunk, dyn_overlap = 1200, 150

    chunks = create_chunks(sections, dyn_chunk, dyn_overlap)
    log.info(f"✅ {len(chunks)} chunks creados (chunk_size={dyn_chunk})")

    # 4. Generar embeddings
    log.info(f"🧮 Generando embeddings para {len(chunks)} chunks...")
    texts = [c["text"] for c in chunks]
    embeddings = embedding_model.encode(texts, show_progress_bar=False)
    
    # 6. Crear índice FAISS
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))
    
    log.info(f"✅ Índice FAISS creado con {len(chunks)} vectores")
    
    return index, chunks, embeddings

def query_session_index(
    session_id: str,
    question: str,
    lang: str = "es",
    top_k: int = 8
) -> dict:
    """
    Consulta el índice FAISS de una sesión específica.
    """
    if session_id not in sessions:
        raise Exception(f"Sesión {session_id} no encontrada")
    
    session = sessions[session_id]
    index = session["faiss_index"]
    chunks = session["chunks"]
    
    # Generar embedding de la pregunta
    question_embedding = embedding_model.encode(
        [question],
        show_progress_bar=False
    )[0]
    
    # Buscar en FAISS
    distances, indices = index.search(
        np.array([question_embedding]).astype('float32'),
        min(top_k, len(chunks))
    )
    
    # Extraer chunks relevantes
    relevant_chunks = [chunks[i] for i in indices[0] if i < len(chunks)]

    return {
        "relevant_chunks": relevant_chunks,
        "distances": distances[0].tolist()
    }


def _normalize(text: str) -> str:
    """Elimina acentos y pasa a minúsculas para comparación robusta."""
    return unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode('ascii').lower()


def keyword_search_chunks(chunks: list, query: str, top_k: int = 5) -> list:
    """
    Búsqueda por palabras clave como complemento al FAISS semántico.
    Normaliza acentos para que "organizacion" encuentre "organización".
    """
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


# ─── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {
        "status": "ok",
        "message": "Asistente Virtual IA activo",
        "version": "2.1",
        "features": ["static_index", "dynamic_pdf_upload"]
    }

@app.post("/upload", response_model=UploadResponse)
async def upload_pdf(
    pdf: UploadFile = File(...),
    session_id: str = Form(default=""),
    lang: str = Form(default="es"),
    persona: str = Form(default=""),
):
    """
    Endpoint para subir un PDF y crear una sesión de chatbot.
    
    Procesa el PDF en tiempo real y crea un índice FAISS específico para esta sesión.
    """
    try:
        # Limpiar sesiones expiradas antes de crear una nueva
        cleanup_expired_sessions()

        # Validar tipo de archivo
        if not pdf.filename.endswith('.pdf'):
            raise HTTPException(status_code=400, detail="Solo se aceptan archivos PDF")
        
        # Generar session_id si no se proporciona
        if not session_id.strip():
            session_id = str(uuid.uuid4())
        
        # Guardar PDF temporalmente
        upload_dir = Path("uploads")
        upload_dir.mkdir(exist_ok=True)
        pdf_path = upload_dir / f"{session_id}.pdf"

        log.info(f"📥 Recibiendo PDF: {pdf.filename} → {pdf_path}")

        content = await pdf.read()

        # Validar tamaño máximo: 10 MB
        MAX_PDF_BYTES = 10 * 1024 * 1024
        if len(content) > MAX_PDF_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"El PDF supera el tamaño máximo permitido (10 MB). Tamaño recibido: {len(content) // (1024*1024)} MB"
            )

        with open(pdf_path, "wb") as f:
            f.write(content)
        
        # Procesar PDF y crear índice FAISS
        log.info(f"⏳ Procesando PDF (puede tardar 30-60s)...")
        index, chunks, embeddings = build_faiss_index_from_pdf(str(pdf_path), lang)
        
        # Guardar sesión
        sessions[session_id] = {
            "history": [],
            "pdf_path": str(pdf_path),
            "pdf_filename": pdf.filename,
            "faiss_index": index,
            "chunks": chunks,
            "embeddings": embeddings,
            "lang": lang,
            "persona": persona,
            "created_at": datetime.now().isoformat()
        }
        
        log.info(
            f"✅ PDF procesado | session={session_id[:8]}... | "
            f"chunks={len(chunks)} | lang={lang}"
        )
        
        return {
            "success": True,
            "session_id": session_id,
            "message": f"PDF '{pdf.filename}' procesado correctamente",
            "chunks": len(chunks)
        }
        
    except Exception as e:
        log.error(f"❌ Error en /upload: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error procesando PDF: {str(e)}")


@app.post("/query", response_model=QueryResponse, dependencies=[Depends(verify_api_key)])
def query(request: QueryRequest):
    """
    Endpoint de consulta mejorado que soporta:
    - Índices estáticos (por defecto)
    - Índices dinámicos de sesiones con PDFs subidos
    """
    
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La pregunta no puede estar vacía")
    
    session_id = request.session_id.strip() or str(uuid.uuid4())
    
    # Inicializar sesión si no existe
    if session_id not in sessions:
        sessions[session_id] = {
            "history": [],
            "faiss_index": None,
            "chunks": None,
            "lang": request.lang,
            "created_at": datetime.now().isoformat()
        }
    
    history = sessions[session_id].get("history", [])
    
    start = time.time()
    
    # Determinar si usar índice dinámico o estático
    if sessions[session_id]["faiss_index"] is not None:
        # Usar índice dinámico (PDF subido)
        log.info(f"🔍 Usando índice dinámico para sesión {session_id[:8]}...")
        
        try:
            # Reformular query si el mensaje es muy corto y hay historial.
            # Mensajes como "no, todos", "sí", "¿y el punto 3?" dependen
            # del contexto previo — sin reformulación FAISS no encuentra nada.
            search_query = request.question
            if len(request.question.split()) <= 5 and history:
                last_user = next(
                    (h["content"] for h in reversed(history) if h["role"] == "user"),
                    ""
                )
                if last_user:
                    search_query = f"{last_user} {request.question}"
                    log.info(f"🔄 Query reformulada: {search_query[:80]!r}")

            rag_result = query_session_index(session_id, search_query, request.lang)
            semantic_chunks = rag_result["relevant_chunks"]

            # Búsqueda por palabras clave para capturar lo que el embedding pierde
            kw_chunks = keyword_search_chunks(
                sessions[session_id]["chunks"], search_query
            )

            # Fusionar: semántico primero, luego keyword sin duplicados.
            # Clave = primeros 80 chars del texto (más fiable que section+page con chunks solapados)
            seen_keys = {c["text"][:80] for c in semantic_chunks}
            for c in kw_chunks:
                key = c["text"][:80]
                if key not in seen_keys:
                    seen_keys.add(key)
                    semantic_chunks.append(c)

            relevant_chunks = semantic_chunks[:10]  # máximo 10 chunks
            log.info(f"🔍 Chunks para contexto: {len(relevant_chunks)} (semántico+keyword)")

            # Construir contexto (1000 chars/chunk — alineado con nuevo chunk_size máx de 1200)
            context = "\n\n".join([
                f"[{c['section']} - p.{c['page']}]\n{c['text'][:1000]}"
                for c in relevant_chunks
            ])

            # Usar RAG engine para generar respuesta
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
                "sources": []
            }
    else:
        # Usar índice estático (RAG Engine por defecto)
        log.info(f"🔍 Usando índice estático para sesión {session_id[:8]}...")
        result = rag.query(
            question=request.question,
            lang=request.lang,
            history=history
        )
    
    elapsed = round(time.time() - start, 2)
    
    # Guardar en historial
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
        f"QUERY | session={session_id[:8]}... | lang={request.lang} | "
        f"time={elapsed}s | sources=[{sources_info}] | "
        f"q={request.question[:80]!r}"
    )
    
    return {
        "answer": result["answer"],
        "lang": result.get("lang", request.lang),
        "sources": result.get("sources", []),
        "session_id": session_id
    }


@app.delete("/history/{session_id}", dependencies=[Depends(verify_api_key)])
def clear_session(session_id: str):
    """Elimina una sesión específica."""
    if session_id in sessions:
        # Limpiar archivos si existen
        session = sessions[session_id]
        if "pdf_path" in session and os.path.exists(session["pdf_path"]):
            try:
                os.remove(session["pdf_path"])
                log.info(f"🗑️  PDF eliminado: {session['pdf_path']}")
            except:
                pass
        
        sessions.pop(session_id)
        log.info(f"HISTORY_CLEAR | session={session_id[:8]}...")
    
    return {"status": "ok", "message": f"Sesión '{session_id}' eliminada"}


@app.delete("/history", dependencies=[Depends(verify_api_key)])
def clear_all_history():
    """Elimina todas las sesiones y limpia archivos."""
    count = len(sessions)
    
    # Limpiar PDFs subidos
    for session_id, session in sessions.items():
        if "pdf_path" in session and os.path.exists(session["pdf_path"]):
            try:
                os.remove(session["pdf_path"])
            except:
                pass
    
    sessions.clear()
    log.info(f"HISTORY_CLEAR_ALL | sesiones eliminadas={count}")
    return {"status": "ok", "message": f"{count} sesiones borradas"}



@app.get("/stats", dependencies=[Depends(verify_api_key)])
def stats():
    """Estadísticas del servidor."""
    return {
        "sesiones_activas": len(sessions),
        "mensajes_totales": sum(
            len(s.get("history", [])) for s in sessions.values()
        ),
        "sesiones_con_pdf": sum(
            1 for s in sessions.values() 
            if s.get("faiss_index") is not None
        )
    }