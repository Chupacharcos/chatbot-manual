import os
import re
import shutil
import argparse
import pickle
import fitz  # PyMuPDF
import numpy as np
from sentence_transformers import SentenceTransformer
import faiss

# ─── Configuración ────────────────────────────────────────────────────────────

EMBEDDINGS_MODEL = "intfloat/multilingual-e5-large"
FAISS_BASE_PATH  = "./faiss_index"
SUPPORTED_LANGS  = ["es", "en", "ca", "pt"]

# Tamaños de chunk en caracteres
CHUNK_SIZE    = 1000
CHUNK_OVERLAP = 200

# Umbral de similitud para fusionar chunks consecutivos (0-1)
# Con normalize_embeddings=True el dot product es cosine similarity.
# Chunks del mismo manual suelen tener similitud ~0.85-0.92; usar 0.95+
# para fusionar solo contenido casi idéntico (ej. listas partidas en dos).
SEMANTIC_THRESHOLD = 0.95

# ─── Extracción ───────────────────────────────────────────────────────────────

def extract_text_from_pdf(pdf_path):
    """Extrae texto del PDF con PyMuPDF."""
    print(f"📄 Extrayendo texto del PDF...")
    doc = fitz.open(pdf_path)
    pages_data = []

    for page_num in range(len(doc)):
        page = doc[page_num]
        text = page.get_text()
        if text.strip():
            pages_data.append({"page": page_num + 1, "text": text})
        else:
            print(f"  ⚠️  Página {page_num + 1} sin texto (¿escaneada?). Se omite.")

    doc.close()
    print(f"✅ Extraídas {len(pages_data)} páginas con texto")
    return pages_data


def extract_sections(pages_data):
    """Identifica secciones en el documento."""
    sections = []
    current_section = {"title": "Inicio", "content": "", "page": 1}

    # Patrones explícitos: secciones numeradas y capítulos
    explicit_patterns = [
        r'^\d+\.\s+[A-ZÁÉÍÓÚÑ]',       # "1. Título"
        r'^\d+\.\d+\s+',                # "1.1 Subtítulo"
        r'^(Capítulo|CAPÍTULO|Capítol)\s+\d+',
        r'^(Chapter|CHAPTER)\s+\d+',
        r'^(Sección|SECCIÓN|Section|SECTION)\s+\d+',
        r'^(Anexo|ANEXO|Annex)\s+',
        r'^¿.{5,70}\?$',               # Pregunta como cabecera: "¿Qué es...?"
    ]

    # Palabras que indican claramente una cabecera temática
    header_keywords = re.compile(
        r'^(Introducción|Introduction|Conclusi|Objetivos|Objetivo|'
        r'Descripción|Overview|Summary|Resumen|Requisitos|Requirements|'
        r'Instalación|Installation|Configuración|Configuration|'
        r'Funcionalidades|Features|Características|Uso|Usage|'
        r'Integración|Integration|Seguridad|Security|'
        r'Contacto|Contact|Soporte|Support|Preguntas)',
        re.IGNORECASE
    )

    for page_data in pages_data:
        lines    = page_data["text"].split('\n')
        page_num = page_data["page"]

        for line in lines:
            line = line.strip()
            if not line:
                continue

            is_section = False

            # 1. Coincide con patrón explícito
            if any(re.match(p, line) for p in explicit_patterns) and len(line) < 100:
                is_section = True

            # 2. Línea corta que parece título:
            #    - entre 4 y 80 chars
            #    - no termina en puntuación de frase (. , ; :)
            #    - empieza en mayúscula o es todo mayúsculas
            #    - no es solo números/símbolos
            elif (4 <= len(line) <= 80
                  and not re.search(r'[.,;:]$', line)
                  and re.match(r'^[A-ZÁÉÍÓÚÑ¿]', line)
                  and re.search(r'[a-záéíóúñA-ZÁÉÍÓÚÑ]{3,}', line)
                  and (line.isupper() or header_keywords.match(line)
                       or re.match(r'^[A-ZÁÉÍÓÚÑ][a-záéíóúñ]', line))):
                # Evitar líneas que son claramente contenido (más de 8 palabras)
                if len(line.split()) <= 8:
                    is_section = True

            if is_section:
                if current_section["content"].strip():
                    sections.append(current_section.copy())
                current_section = {"title": line, "content": "", "page": page_num}
            else:
                current_section["content"] += line + " "

    if current_section["content"].strip():
        sections.append(current_section)

    # Filtrar secciones con contenido casi vacío.
    # Los índices/TOC generan cientos de "secciones" que solo contienen
    # el número de página de referencia (ej: "9 1.1. ") — son inútiles
    # para RAG y contaminan el índice con chunks sin información real.
    # Un umbral de 50 chars elimina estas entradas de TOC (que tienen
    # 3-30 chars) sin afectar secciones reales (que tienen 50+ chars).
    sections = [s for s in sections if len(s["content"].strip()) >= 50]

    return sections

# ─── Chunking ─────────────────────────────────────────────────────────────────

def create_chunks(sections, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    """Crea chunks de texto con solapamiento para no perder contexto."""
    chunks = []

    for section in sections:
        text = f"{section['title']}\n\n{section['content']}"

        for i in range(0, len(text), chunk_size - overlap):
            chunk_text = text[i:i + chunk_size]
            if len(chunk_text.strip()) > 50:
                chunks.append({
                    "text":    chunk_text,
                    "section": section["title"],
                    "page":    section["page"]
                })

    return chunks


def merge_semantic_chunks(chunks, model, threshold=SEMANTIC_THRESHOLD):
    """
    Chunking semántico: fusiona chunks consecutivos que tratan el mismo tema.

    En lugar de cortar el texto en trozos fijos independientemente del contenido,
    compara cada chunk con el siguiente. Si son muy similares semánticamente
    (hablan del mismo tema), los fusiona en uno solo.

    Esto evita que una explicación que ocupa dos chunks quede partida a la mitad,
    perdiendo contexto en las respuestas.
    """
    if len(chunks) <= 1:
        return chunks

    print(f"🔗 Aplicando chunking semántico (threshold={threshold})...")

    texts      = [c["text"] for c in chunks]
    embeddings = model.encode(texts, show_progress_bar=False, normalize_embeddings=True)

    merged   = []
    i        = 0
    fusiones = 0

    while i < len(chunks):
        current = chunks[i].copy()

        # Comparar con el siguiente chunk
        while i + 1 < len(chunks):
            sim = float(np.dot(embeddings[i], embeddings[i + 1]))

            if sim >= threshold:
                # Fusionar — mismo tema, no cortar aquí
                current["text"] += "\n\n" + chunks[i + 1]["text"]
                i += 1
                fusiones += 1
            else:
                break

        merged.append(current)
        i += 1

    print(f"  📎 {fusiones} fusiones aplicadas: {len(chunks)} → {len(merged)} chunks")
    return merged

# ─── Pipeline principal ───────────────────────────────────────────────────────

def process_manual(pdf_path, lang):
    print("=" * 60)
    print(f"🚀 PROCESANDO: {pdf_path} [{lang.upper()}]")
    print("=" * 60)

    if not os.path.exists(pdf_path):
        print(f"❌ No encontrado: {pdf_path}")
        return

    # 1. Extraer texto
    pages = extract_text_from_pdf(pdf_path)
    if not pages:
        print("❌ No se pudo extraer texto. ¿Es un PDF escaneado?")
        return

    # 2. Secciones
    print("\n🔍 Identificando secciones...")
    sections = extract_sections(pages)
    print(f"✅ {len(sections)} secciones")

    if sections:
        print("\n📋 Primeras secciones:")
        for i, s in enumerate(sections[:3]):
            print(f"  {i+1}. {s['title'][:60]} (p.{s['page']})")

    # 3. Chunks base con solapamiento
    print("\n🔪 Creando chunks...")
    chunks = create_chunks(sections)
    print(f"✅ {len(chunks)} chunks base")

    # 4. Embeddings
    print(f"\n🧮 Cargando modelo de embeddings: {EMBEDDINGS_MODEL}")
    print("⏳ Primera vez ~5 min (descarga del modelo)...")
    model = SentenceTransformer(EMBEDDINGS_MODEL)

    # 5. Chunking semántico — fusiona chunks del mismo tema
    chunks = merge_semantic_chunks(chunks, model)

    # 6. Generar embeddings finales
    print(f"\n🧮 Generando embeddings finales para {len(chunks)} chunks...")
    texts      = [c["text"] for c in chunks]
    embeddings = model.encode(texts, show_progress_bar=True)

    # 7. Guardar índice FAISS
    faiss_path = os.path.join(FAISS_BASE_PATH, lang)

    if os.path.exists(faiss_path):
        print(f"\n🗑️  Eliminando índice anterior...")
        shutil.rmtree(faiss_path)

    os.makedirs(faiss_path, exist_ok=True)

    print(f"💾 Guardando índice FAISS...")
    dimension = embeddings.shape[1]
    index     = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))

    faiss.write_index(index, os.path.join(faiss_path, "index.faiss"))

    with open(os.path.join(faiss_path, "chunks.pkl"), "wb") as f:
        pickle.dump(chunks, f)

    print("\n" + "=" * 60)
    print(f"✅ COMPLETADO [{lang.upper()}]")
    print(f"   {len(chunks)} chunks indexados")
    print("=" * 60)
    print(f"\nEjecuta: bash start.sh")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", required=True, choices=SUPPORTED_LANGS)
    parser.add_argument("--pdf",  required=True)
    args = parser.parse_args()

    process_manual(args.pdf, args.lang)