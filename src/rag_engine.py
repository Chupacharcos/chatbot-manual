import os, pickle, faiss
from sentence_transformers import SentenceTransformer, CrossEncoder
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# Configuración
EMBEDDINGS_MODEL = "intfloat/multilingual-e5-large"
RERANKER_MODEL   = "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
LLM_MODEL        = "llama-3.1-8b-instant"

class RAGEngine:
    def __init__(self):
        self.embeddings_model = SentenceTransformer(EMBEDDINGS_MODEL)
        self.reranker = CrossEncoder(RERANKER_MODEL)
        self.llm = Groq(api_key=os.getenv("GROQ_API_KEY"))
        self.indices = {}
        self.chunks_data = {}

    def _load_index(self, lang):
        if lang in self.indices: return True
        path = f"./faiss_index/{lang}"
        if not os.path.exists(f"{path}/index.faiss"): return False
        self.indices[lang] = faiss.read_index(f"{path}/index.faiss")
        with open(f"{path}/chunks.pkl", "rb") as f: self.chunks_data[lang] = pickle.load(f)
        return True

    def query(self, question, lang, history):
        if not self._load_index(lang): return {"answer": "Manual no disponible.", "sources": []}
        
        # Recuperación
        q_emb = self.embeddings_model.encode([question])
        _, idxs = self.indices[lang].search(q_emb.astype('float32'), 10)
        docs = [self.chunks_data[lang][i] for i in idxs[0] if i < len(self.chunks_data[lang])]
        
        # Re-ranking
        pairs = [(question, d["text"]) for d in docs]
        scores = self.reranker.predict(pairs)
        reranked = [d for _, d in sorted(zip(scores, docs), reverse=True)][:3]

        context = "\n\n".join([f"[{d['section']} p.{d['page']}]: {d['text']}" for d in reranked])
        prompt = f"Eres un asistente experto. Usa el contexto para responder en {lang}.\nContexto:\n{context}\nPregunta: {question}"

        res = self.llm.chat.completions.create(model=LLM_MODEL, messages=[{"role": "user", "content": prompt}], temperature=0)
        return {"answer": res.choices[0].message.content, "sources": reranked}