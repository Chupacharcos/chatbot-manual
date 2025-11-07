from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings  # ✅ USAR ESTE
from langchain_community.vectorstores import FAISS
import os
import shutil

def cleanup_faiss_db(path):
    """Limpia completamente la base de datos FAISS existente"""
    if os.path.exists(path):
        try:
            shutil.rmtree(path)
            print(f"🧹 Limpiada base de datos existente: {path}")
        except Exception as e:
            print(f"⚠️  No se pudo limpiar {path}: {e}")

def process_manual(pdf_path, db_path="./faiss_db"):
    """
    Procesa un PDF y lo almacena en FAISS
    """
    print(f"📄 Cargando PDF: {pdf_path}")
    
    # 1. Cargar PDF
    loader = PyPDFLoader(pdf_path)
    documents = loader.load()
    print(f"✅ Cargadas {len(documents)} páginas")
    
    # 2. Dividir en chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200,
        separators=["\n\n", "\n", ". ", " ", ""]
    )
    chunks = text_splitter.split_documents(documents)
    print(f"✅ Creados {len(chunks)} chunks")
    
    # 3. Crear embeddings
    print("🧮 Generando embeddings...")
    embeddings = HuggingFaceEmbeddings(
        model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        model_kwargs={'device': 'cpu'},
        encode_kwargs={'normalize_embeddings': True}
    )
    
    # 4. Limpiar base de datos existente
    cleanup_faiss_db(db_path)
    
    # Asegurar que el directorio existe
    os.makedirs(db_path, exist_ok=True)
    
    print(f"💾 Guardando en FAISS: {db_path}")
    
    try:
        # Configurar FAISS
        vectorstore = FAISS.from_documents(
            documents=chunks,
            embedding=embeddings
        )
        
        # Guardar en disco
        vectorstore.save_local(db_path)
        
        print("✅ Manual procesado correctamente")
        return vectorstore
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

if __name__ == "__main__":
    pdf_path = "data/manual.pdf"
    if os.path.exists(pdf_path):
        result = process_manual(pdf_path)
        if result:
            print("🎉 Proceso completado exitosamente!")
        else:
            print("💥 Error en el procesamiento")
    else:
        print(f"❌ No se encontró el archivo: {pdf_path}")
        print("📝 Crea un PDF de prueba o coloca tu manual en data/manual.pdf")