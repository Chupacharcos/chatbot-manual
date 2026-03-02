import os
import sys
import uuid
import logging
import time
import pickle
import shutil
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, HTTPException, Security, Depends, UploadFile, File, Form
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
    merge_semantic_chunks,
    EMBEDDINGS_MODEL,
    CHUNK_SIZE,
    CHUNK_OVERLAP,
    SEMANTIC_THRESHOLD
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
    allow_origins=["*"],
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
    
    # 3. Crear chunks
    chunks = create_chunks(sections, CHUNK_SIZE, CHUNK_OVERLAP)
    log.info(f"✅ {len(chunks)} chunks creados")
    
    # 4. Chunking semántico
    chunks = merge_semantic_chunks(chunks, embedding_model, SEMANTIC_THRESHOLD)
    log.info(f"✅ Chunks semánticamente optimizados: {len(chunks)}")
    
    # 5. Generar embeddings
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
    top_k: int = 3
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
    lang: str = Form(default="es")
):
    """
    Endpoint para subir un PDF y crear una sesión de chatbot.
    
    Procesa el PDF en tiempo real y crea un índice FAISS específico para esta sesión.
    """
    try:
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
        
        with open(pdf_path, "wb") as f:
            content = await pdf.read()
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
            "lang": request.lang
        }
    
    history = sessions[session_id].get("history", [])
    
    start = time.time()
    
    # Determinar si usar índice dinámico o estático
    if sessions[session_id]["faiss_index"] is not None:
        # Usar índice dinámico (PDF subido)
        log.info(f"🔍 Usando índice dinámico para sesión {session_id[:8]}...")
        
        try:
            rag_result = query_session_index(session_id, request.question, request.lang)
            relevant_chunks = rag_result["relevant_chunks"]
            
            # Construir contexto
            context = "\n\n".join([
                f"[{c['section']} - p.{c['page']}]\n{c['text']}"
                for c in relevant_chunks
            ])
            
            # Usar RAG engine para generar respuesta
            result = rag.query_with_context(
                question=request.question,
                context=context,
                lang=request.lang,
                history=history
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