import os, pickle, faiss
from sentence_transformers import SentenceTransformer, CrossEncoder
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# --- CONSTANTES REQUERIDAS POR LA API ---
MAX_HISTORY = 5  # Número de mensajes que recuerda el chat
EMBEDDINGS_MODEL = "intfloat/multilingual-e5-large"
RERANKER_MODEL   = "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
LLM_MODEL        = "llama-3.1-8b-instant"

class RAGEngine:
    def __init__(self):
        print("🔧 Inicializando RAG Engine...")
        self.embeddings_model = SentenceTransformer(EMBEDDINGS_MODEL)
        self.reranker = CrossEncoder(RERANKER_MODEL)
        self.llm = Groq(api_key=os.getenv("GROQ_API_KEY"))
        self.indices = {}
        self.chunks_data = {}

    def _load_index(self, lang):
        if lang in self.indices: return True
        path = f"./faiss_index/{lang}"
        if not os.path.exists(f"{path}/index.faiss"): 
            print(f"⚠️ No se encontró índice para: {lang}")
            return False
        self.indices[lang] = faiss.read_index(f"{path}/index.faiss")
        with open(f"{path}/chunks.pkl", "rb") as f: 
            self.chunks_data[lang] = pickle.load(f)
        return True

    def query(self, question, lang, history):
        if not self._load_index(lang): 
            return {"answer": "Lo siento, el manual en este idioma no está disponible.", "sources": [], "lang": lang}
        
        # 1. Recuperación (Retrieval) — reducido de 10 a 5 para no superar límite de tokens
        q_emb = self.embeddings_model.encode([question])
        _, idxs = self.indices[lang].search(q_emb.astype('float32'), 5)
        docs = [self.chunks_data[lang][i] for i in idxs[0] if i < len(self.chunks_data[lang])]
        
        # 2. Re-ranking — reducido de 3 a 2
        pairs = [(question, d["text"]) for d in docs]
        scores = self.reranker.predict(pairs)
        reranked = [d for _, d in sorted(zip(scores, docs), reverse=True)][:2]

        # 3. Construcción del Prompt — texto truncado a 400 chars por chunk
        context = "\n\n".join([f"[{d['section']} p.{d['page']}]: {d['text'][:400]}" for d in reranked])
        
        messages = [
            {"role": "system", "content": f"Eres un asistente corporativo experto. Responde siempre en {lang} basándote en el contexto proporcionado. Si no sabes la respuesta, admítelo."},
            {"role": "user", "content": f"Contexto:\n{context}\n\nPregunta: {question}"}
        ]

        res = self.llm.chat.completions.create(
            model=LLM_MODEL, 
            messages=messages, 
            temperature=0
        )
        
        # Cambio aplicado: ahora devuelve también el idioma en la respuesta
        return {"answer": res.choices[0].message.content, "sources": reranked, "lang": lang}