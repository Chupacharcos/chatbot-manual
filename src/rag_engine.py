import os
import pickle
import faiss
from datetime import datetime
from sentence_transformers import SentenceTransformer, CrossEncoder
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# --- CONSTANTES REQUERIDAS POR LA API ---
MAX_HISTORY = 5  # Número de mensajes que recuerda el chat
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

        # 2. Re-ranking — reducido de 3 a 2
        pairs = [(question, d["text"]) for d in docs]
        scores = self.reranker.predict(pairs)
        reranked = [d for _, d in sorted(zip(scores, docs), reverse=True)][:2]

        # 3. Construcción del Prompt — texto truncado a 400 chars por chunk
        context = "\n\n".join([f"[{d['section']} p.{d['page']}]: {d['text'][:400]}" for d in reranked])
        messages = [
            {
                "role": "system",
                "content": f"Eres un asistente corporativo experto. Responde siempre en {lang} basándote en el contexto proporcionado. Si no sabes la respuesta, admítelo."
            },
            {
                "role": "user",
                "content": f"Contexto:\n{context}\n\nPregunta: {question}"
            }
        ]

        res = self.llm.chat.completions.create(
            model=LLM_MODEL,
            messages=messages,
            temperature=0
        )

        return {
            "answer": res.choices[0].message.content,
            "sources": reranked,
            "lang": lang
        }

    def query_with_context(self, question: str, context: str, lang: str = "es", history: list = None) -> dict:
        """
        Genera una respuesta usando un contexto específico (de PDFs dinámicos).
        
        Útil para procesamiento de PDFs subidos sin necesidad de tener
        índices FAISS pre-procesados.
        
        Args:
            question: La pregunta del usuario
            context: El contexto extraído por FAISS (chunks relevantes)
            lang: Idioma de respuesta
            history: Historial de conversación
        
        Returns:
            dict con 'answer', 'lang', 'sources'
        """
        if not history:
            history = []

        # Detectar idioma
        detected_lang = lang if lang in self.lang_map else "es"

        # Construcción del prompt mejorado
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        system_prompt = f"""Eres un asistente inteligente especializado en análisis de documentos.
Responde siempre en {self.lang_map.get(detected_lang, 'español')}.

Analiza el contexto proporcionado y responde preguntas basándote ÚNICAMENTE en la información contenida.

Reglas:
1. El contexto son fragmentos seleccionados del documento por relevancia semántica, no el documento completo.
2. Si la información pedida no aparece en los fragmentos, di: "No tengo ese fragmento disponible. Intenta preguntar de forma más específica."
3. Nunca inventes ni supongas información que no esté en el contexto.
4. Cita siempre la sección y página de donde extraes la información.
5. Sé conciso pero completo. Usa tono profesional.
6. Si el usuario pide un listado completo (todos los capítulos, todos los puntos, etc.), responde con lo que encuentres en los fragmentos disponibles y aclara que el listado puede estar incompleto."""

        # Construir mensajes incluyendo historial
        messages = [{"role": "system", "content": system_prompt}]

        # Añadir historial relevante (últimos 4 mensajes)
        recent_history = history[-4:] if history else []
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
                max_tokens=1024
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