import os
import pickle
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer, CrossEncoder
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# ─── Configuración ───────────────────────────────────────────────────────────

EMBEDDINGS_MODEL  = "intfloat/multilingual-e5-large"
RERANKER_MODEL    = "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
FAISS_BASE_PATH   = "./faiss_index"
LLM_MODEL         = "llama-3.3-70b-versatile"
RETRIEVAL_K       = 10
RERANKED_K        = 3
MAX_HISTORY       = 6
SUPPORTED_LANGS   = ["es", "en", "ca", "pt"]

# ─── Tipos de pregunta ───────────────────────────────────────────────────────

QUESTION_TYPES = {
    "definition": {
        "keywords": ["qué es", "what is", "que és", "o que é"],
        "instruction": "Da una definición clara y completa."
    },
    "process": {
        "keywords": ["cómo", "how", "com", "como", "pasos", "steps"],
        "instruction": "Explica el proceso paso a paso."
    },
    "requirement": {
        "keywords": ["requisito", "requirement", "requisit", "necesito", "need"],
        "instruction": "Lista los requisitos claramente."
    },
}

# ─── Prompts por idioma ──────────────────────────────────────────────────────

PROMPTS = {
    "es": """Eres un asistente experto en el manual de la empresa, especializado en ISO y gestión empresarial.

Historial reciente:
{history}

Contexto del manual:
{context}

Pregunta: {question}

Instrucciones:
- Responde SOLO con información del contexto
- Si no está, di: "No encuentro esa información en el manual"
- {type_instruction}
- Cita la sección cuando sea posible
- Responde en español

Respuesta:""",

    "en": """You are an expert assistant for the company's manual, specialized in ISO and business management.

Recent history:
{history}

Manual context:
{context}

Question: {question}

Instructions:
- Answer ONLY with information from context
- If not found: "I cannot find that information in the manual"
- {type_instruction}
- Cite the section when possible
- Answer in English

Answer:""",

    "ca": """Ets un assistent expert en el manual de l'empresa, especialitzat en ISO i gestió empresarial.

Historial recent:
{history}

Context del manual:
{context}

Pregunta: {question}

Instruccions:
- Respon NOMÉS amb informació del context
- Si no hi és: "No trobo aquesta informació al manual"
- {type_instruction}
- Cita la secció quan sigui possible
- Respon en català

Resposta:""",

    "pt": """Você é um assistente especialista no manual da empresa, especializado em ISO e gestão empresarial.

Histórico recente:
{history}

Contexto do manual:
{context}

Pergunta: {question}

Instruções:
- Responda APENAS com informações do contexto
- Se não estiver: "Não encontro essa informação no manual"
- {type_instruction}
- Cite a seção quando possível
- Responda em português

Resposta:"""
}

# ─── RAG Engine ──────────────────────────────────────────────────────────────

class RAGEngine:
    def __init__(self):
        print("🔧 Inicializando RAG Engine...")

        self.embeddings_model = SentenceTransformer(EMBEDDINGS_MODEL)

        print("📊 Cargando re-ranker...")
        self.reranker = CrossEncoder(RERANKER_MODEL)

        self.llm = Groq(api_key=os.getenv("GROQ_API_KEY"))

        # Índices por idioma (compartidos entre todas las sesiones)
        self.indices     = {}
        self.chunks_data = {}

        print("✅ RAG Engine listo\n")

    def _load_index(self, lang: str) -> bool:
        if lang in self.indices:
            return True

        faiss_path  = os.path.join(FAISS_BASE_PATH, lang)
        index_file  = os.path.join(faiss_path, "index.faiss")
        chunks_file = os.path.join(faiss_path, "chunks.pkl")

        if not os.path.exists(index_file):
            return False

        print(f"📂 Cargando índice [{lang.upper()}]...")
        self.indices[lang] = faiss.read_index(index_file)

        with open(chunks_file, "rb") as f:
            self.chunks_data[lang] = pickle.load(f)

        return True

    def _preprocess_query(self, question: str, lang: str) -> str:
        prompts = {
            "es": f"Corrige errores y reformula clara y brevemente: {question}",
            "en": f"Fix errors and rephrase clearly and briefly: {question}",
            "ca": f"Corregeix errors i reformula clarament i breument: {question}",
            "pt": f"Corrija erros e reformule clara e brevemente: {question}",
        }
        try:
            response = self.llm.chat.completions.create(
                model=LLM_MODEL,
                messages=[{"role": "user", "content": prompts.get(lang, prompts["es"])}],
                temperature=0,
                max_tokens=100
            )
            return response.choices[0].message.content.strip()
        except Exception:
            return question

    def _detect_question_type(self, question: str) -> str:
        q_lower = question.lower()
        for q_type, data in QUESTION_TYPES.items():
            if any(kw in q_lower for kw in data["keywords"]):
                return q_type
        return "general"

    def _retrieve(self, question: str, lang: str, k: int = RETRIEVAL_K):
        query_embedding = self.embeddings_model.encode([question])
        distances, indices = self.indices[lang].search(query_embedding.astype('float32'), k)

        results = []
        for idx in indices[0]:
            if idx < len(self.chunks_data[lang]):
                results.append(self.chunks_data[lang][idx])
        return results

    def _rerank(self, question: str, docs: list) -> list:
        if not docs:
            return docs
        pairs  = [(question, doc["text"]) for doc in docs]
        scores = self.reranker.predict(pairs)
        ranked = sorted(zip(scores, docs), key=lambda x: x[0], reverse=True)
        return [doc for _, doc in ranked[:RERANKED_K]]

    def _format_history(self, history: list) -> str:
        """Formatea el historial recibido como parámetro (nunca global)."""
        if not history:
            return "Sin conversación previa."
        lines = []
        for msg in history[-MAX_HISTORY:]:
            lines.append(f"{msg['role'].capitalize()}: {msg['content']}")
        return "\n".join(lines)

    def query(self, question: str, lang: str, history: list) -> dict:
        """
        Consulta el manual.

        Args:
            question: Pregunta del usuario
            lang:     Idioma (es, en, ca, pt)
            history:  Historial de la sesión — gestionado externamente por api.py
        """
        if lang not in SUPPORTED_LANGS:
            return {"answer": f"Idioma '{lang}' no soportado.", "lang": lang, "sources": []}

        if not self._load_index(lang):
            return {"answer": f"No hay manual disponible para '{lang}'.", "lang": lang, "sources": []}

        # Preprocesar
        processed = self._preprocess_query(question, lang)
        if processed != question:
            print(f"✏️  Reformulada: {processed}")

        # Tipo de pregunta
        q_type    = self._detect_question_type(processed)
        type_instr = QUESTION_TYPES.get(q_type, {}).get("instruction", "Responde claramente.")
        print(f"📌 Tipo: {q_type}")

        # Búsqueda + re-ranking
        docs     = self._retrieve(processed, lang, RETRIEVAL_K)
        reranked = self._rerank(processed, docs)
        print(f"🔍 Recuperados: {len(docs)} → Re-rankeados: {len(reranked)}")

        # Contexto
        context_parts = []
        for doc in reranked:
            section = doc.get("section", "Sin sección")
            page    = doc.get("page", "?")
            context_parts.append(f"[Sección: {section} | Pág: {page}]\n{doc['text']}")
        context = "\n\n---\n\n".join(context_parts)

        # Generar respuesta
        prompt = PROMPTS.get(lang, PROMPTS["es"]).format(
            history=self._format_history(history),
            context=context,
            question=processed,
            type_instruction=type_instr
        )

        response = self.llm.chat.completions.create(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0
        )

        answer = response.choices[0].message.content

        return {
            "answer":  answer,
            "lang":    lang,
            "sources": reranked
        }