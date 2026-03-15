import os
import pickle
import faiss
from datetime import datetime
from sentence_transformers import SentenceTransformer, CrossEncoder
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# --- CONSTANTES REQUERIDAS POR LA API ---
MAX_HISTORY = 4  # Número de turnos (pares user/assistant) que recuerda el chat
EMBEDDINGS_MODEL = "intfloat/multilingual-e5-large"
RERANKER_MODEL = "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
LLM_MODEL = "llama-3.1-8b-instant"


class RAGEngine:
    def __init__(self):
        print("🔧 Inicializando RAG Engine...")
        self.embeddings_model = SentenceTransformer(EMBEDDINGS_MODEL)
        self.reranker = CrossEncoder(RERANKER_MODEL)
        self.llm = Groq(api_key=os.getenv("GROQ_API_KEY"))
        self.indices = {}
        self.chunks_data = {}
        
        # Mapa de idiomas para mensajes
        self.lang_map = {
            "es": "Español",
            "en": "English",
            "ca": "Català",
            "pt": "Português"
        }

    def _load_index(self, lang):
        if lang in self.indices:
            return True
        path = f"./faiss_index/{lang}"
        if not os.path.exists(f"{path}/index.faiss"):
            print(f"⚠️ No se encontró índice para: {lang}")
            return False
        self.indices[lang] = faiss.read_index(f"{path}/index.faiss")
        with open(f"{path}/chunks.pkl", "rb") as f:
            self.chunks_data[lang] = pickle.load(f)
        return True

    def query(self, question, lang, history):
        """
        Consulta el RAG con una pregunta usando índices pre-procesados.
        """
        if not self._load_index(lang):
            return {
                "answer": "Lo siento, el manual en este idioma no está disponible.",
                "sources": [],
                "lang": lang
            }

        # 1. Recuperación (Retrieval) — reducido de 10 a 5 para no superar límite de tokens
        q_emb = self.embeddings_model.encode([question])
        _, idxs = self.indices[lang].search(q_emb.astype('float32'), 5)
        docs = [self.chunks_data[lang][i] for i in idxs[0] if i < len(self.chunks_data[lang])]

        # 2. Re-ranking
        pairs = [(question, d["text"]) for d in docs]
        scores = self.reranker.predict(pairs)
        scored_docs = sorted(zip(scores, docs), reverse=True)
        reranked = [d for _, d in scored_docs][:4]
        reranker_scores = [float(s) for s, _ in scored_docs][:4]
        for i, d in enumerate(reranked):
            d["_reranker_score"] = reranker_scores[i]

        # 3. Construcción del Prompt — texto truncado a 600 chars por chunk
        context = "\n\n".join([f"[{d['section']} p.{d['page']}]: {d['text'][:600]}" for d in reranked])
        lang_name = self.lang_map.get(lang, lang)
        messages = [
            {
                "role": "system",
                "content": f"Eres un asistente experto. Responde siempre en {lang_name} basándote en el contexto proporcionado. Si no sabes la respuesta, admítelo."
            }
        ]

        # Incluir historial reciente para mantener coherencia conversacional
        recent_history = history[-(MAX_HISTORY * 2):] if history else []
        messages.extend(recent_history)

        messages.append({
            "role": "user",
            "content": f"Contexto:\n{context}\n\nPregunta: {question}"
        })

        res = self.llm.chat.completions.create(
            model=LLM_MODEL,
            messages=messages,
            temperature=0,
            max_tokens=1024
        )

        return {
            "answer": res.choices[0].message.content,
            "sources": reranked,
            "lang": lang
        }

    def query_with_context(self, question: str, context: str, lang: str = "es", history: list = None, persona: str = "") -> dict:
        """
        Genera una respuesta usando un contexto específico (de PDFs dinámicos).

        Args:
            question: La pregunta del usuario
            context: El contexto extraído por FAISS (chunks relevantes)
            lang: Idioma de respuesta
            history: Historial de conversación
            persona: Descripción de rol/actitud del asistente (configurable por el cliente)

        Returns:
            dict con 'answer', 'lang', 'sources'
        """
        if not history:
            history = []

        # Detectar idioma
        detected_lang = lang if lang in self.lang_map else "es"

        # Línea de personalidad personalizada
        persona_line = f"\n\nRol y actitud: {persona.strip()}" if persona.strip() else ""

        system_prompt = f"""Eres un asistente inteligente especializado en análisis de documentos.{persona_line}
Responde SIEMPRE en el mismo idioma que use el usuario en su pregunta. Si el usuario escribe en inglés, responde en inglés. Si escribe en español, responde en español. Nunca cambies de idioma.

Analiza el contexto proporcionado y responde preguntas basándote ÚNICAMENTE en la información contenida.

Reglas:
1. El contexto son fragmentos seleccionados del documento por relevancia semántica, no el documento completo.
2. Si la información pedida no aparece claramente en los fragmentos, responde con lo que encuentres relacionado e indica que puede haber más detalles en otras secciones del documento.
3. Nunca inventes ni supongas información que no esté en el contexto.
4. Cita siempre la sección y página de donde extraes la información.
5. Sé conciso pero completo.
6. Si el usuario pide un listado completo (todos los capítulos, todos los puntos, etc.), responde con lo que encuentres en los fragmentos disponibles y aclara que el listado puede estar incompleto.
7. Nunca empieces la respuesta con frases como "Según el contexto proporcionado", "Basándome en el contexto", "En el contexto se menciona" o similares. Responde directamente al usuario."""

        # Construir mensajes incluyendo historial
        messages = [{"role": "system", "content": system_prompt}]

        # Añadir historial relevante
        recent_history = history[-(MAX_HISTORY * 2):] if history else []
        messages.extend(recent_history)

        # Añadir contexto y pregunta actual
        user_message = f"""Contexto del documento:
---
{context}
---

Pregunta: {question}"""

        messages.append({"role": "user", "content": user_message})

        try:
            # Llamar a Groq
            response = self.llm.chat.completions.create(
                model=LLM_MODEL,
                messages=messages,
                temperature=0.3,
                max_tokens=2048
            )

            answer = response.choices[0].message.content.strip()

            return {
                "answer": answer,
                "lang": detected_lang,
                "sources": [],
                "model": LLM_MODEL
            }

        except Exception as e:
            return {
                "answer": f"Error generando respuesta: {str(e)}",
                "lang": detected_lang,
                "sources": [],
                "error": str(e)
            }