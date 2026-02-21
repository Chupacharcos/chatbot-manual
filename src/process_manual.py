import os
import re
import shutil
import argparse
import pickle
import fitz  # PyMuPDF
import numpy as np
from sentence_transformers import SentenceTransformer
import faiss

# Configuración
EMBEDDINGS_MODEL = "intfloat/multilingual-e5-large"
FAISS_BASE_PATH = "./faiss_index"
SUPPORTED_LANGS = ["es", "en", "ca", "pt"]

def extract_text_from_pdf(pdf_path):
    """Extrae texto del PDF con PyMuPDF"""
    print(f"📄 Extrayendo texto del PDF...")
    doc = fitz.open(pdf_path)
    pages_data = []
    
    for page_num in range(len(doc)):
        page = doc[page_num]
        text = page.get_text()
        pages_data.append({"page": page_num + 1, "text": text})
    
    doc.close()
    print(f"✅ Extraídas {len(pages_data)} páginas")
    return pages_data

def extract_sections(pages_data):
    """Identifica secciones en el documento"""
    sections = []
    current_section = {"title": "Inicio", "content": "", "page": 1}
    
    patterns = [
        r'^\d+\.\s+[A-ZÁÉÍÓÚÑ]',
        r'^\d+\.\d+\s+',
        r'^Capítulo\s+\d+',
        r'^CAPÍTULO\s+\d+',
    ]
    
    for page_data in pages_data:
        lines = page_data["text"].split('\n')
        page_num = page_data["page"]
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            is_section = any(re.match(p, line) for p in patterns) and len(line) < 100
            
            if is_section:
                if current_section["content"].strip():
                    sections.append(current_section.copy())
                current_section = {"title": line, "content": "", "page": page_num}
            else:
                current_section["content"] += line + " "
    
    if current_section["content"].strip():
        sections.append(current_section)
    
    return sections

def create_chunks(sections, chunk_size=1000, overlap=200):
    """Crea chunks de texto"""
    chunks = []
    
    for idx, section in enumerate(sections):
        text = f"{section['title']}\n\n{section['content']}"
        
        # Dividir en chunks
        for i in range(0, len(text), chunk_size - overlap):
            chunk_text = text[i:i + chunk_size]
            if len(chunk_text.strip()) > 50:
                chunks.append({
                    "text": chunk_text,
                    "section": section["title"],
                    "page": section["page"]
                })
    
    return chunks

def process_manual(pdf_path, lang):
    print("=" * 60)
    print(f"🚀 PROCESANDO: {pdf_path} [{lang.upper()}]")
    print("=" * 60)
    
    if not os.path.exists(pdf_path):
        print(f"❌ No encontrado: {pdf_path}")
        return
    
    # 1. Extraer texto
    pages = extract_text_from_pdf(pdf_path)
    
    # 2. Secciones
    print("\n🔍 Identificando secciones...")
    sections = extract_sections(pages)
    print(f"✅ {len(sections)} secciones")
    
    if sections:
        print("\n📋 Primeras secciones:")
        for i, s in enumerate(sections[:3]):
            print(f"  {i+1}. {s['title'][:50]}... (p.{s['page']})")
    
    # 3. Chunks
    print("\n🔪 Creando chunks...")
    chunks = create_chunks(sections)
    print(f"✅ {len(chunks)} chunks")
    
    # 4. Embeddings
    print(f"\n🧮 Generando embeddings: {EMBEDDINGS_MODEL}")
    print("⏳ Primera vez ~5 min...")
    model = SentenceTransformer(EMBEDDINGS_MODEL)
    
    texts = [c["text"] for c in chunks]
    embeddings = model.encode(texts, show_progress_bar=True)
    
    # 5. FAISS
    faiss_path = os.path.join(FAISS_BASE_PATH, lang)
    
    if os.path.exists(faiss_path):
        print(f"🗑️ Eliminando índice anterior...")
        shutil.rmtree(faiss_path)
    
    os.makedirs(faiss_path, exist_ok=True)
    
    print(f"💾 Guardando índice FAISS...")
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))
    
    faiss.write_index(index, os.path.join(faiss_path, "index.faiss"))
    
    with open(os.path.join(faiss_path, "chunks.pkl"), "wb") as f:
        pickle.dump(chunks, f)
    
    print("\n" + "=" * 60)
    print(f"✅ COMPLETADO [{lang.upper()}]")
    print("=" * 60)
    print(f"\nEjecuta: python src/chatbot.py")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", required=True, choices=SUPPORTED_LANGS)
    parser.add_argument("--pdf", required=True)
    args = parser.parse_args()
    
    process_manual(args.pdf, args.lang)