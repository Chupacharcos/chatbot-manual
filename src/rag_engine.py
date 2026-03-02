# ⚠️  IMPORTANTE: Copia SOLO este método y pégalo al final de la clase RAGEngine
# en tu archivo src/rag_engine.py
# Busca la clase "class RAGEngine:" y al final, antes del último "}", pega esto

    def query_with_context(self, question: str, context: str, lang: str = "es", history: list = None) -> dict:
        """
        Genera una respuesta usando un contexto específico (de PDFs dinámicos).
        
        Útil para procesamiento de PDFs subidos sin necesidad de tener
        índices FAISS pre-procesados.
        """
        from datetime import datetime
        
        if not history:
            history = []
        
        # Detectar idioma si es necesario
        detected_lang = lang or self.detect_language(question)
        
        # Construcción del prompt
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        system_prompt = f"""Eres un asistente inteligente especializado en análisis de documentos.
Responde siempre en {self.lang_map.get(detected_lang, 'español')}.
Timestamp actual: {timestamp}

Analiza el contexto proporcionado y responde preguntas basándote ÚNICAMENTE en la información contenida.

Reglas:
1. Si la respuesta no está en el contexto, di claramente "No encontré información sobre esto en el documento"
2. Cita siempre la sección del documento de donde extraes la información
3. Sé conciso pero completo
4. Usa un tono profesional y amable"""

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
            # Llamar a OpenAI o Groq según esté configurado
            response = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=0.3,
                max_tokens=1024
            )
            
            answer = response.choices[0].message.content.strip()
            
            # Extraer sources del contexto (si es posible)
            sources = []
            # Las sources vendrán del query_session_index en api.py
            
            return {
                "answer": answer,
                "lang": detected_lang,
                "sources": sources,
                "model": self.model
            }
            
        except Exception as e:
            return {
                "answer": f"Error generando respuesta: {str(e)}",
                "lang": detected_lang,
                "sources": [],
                "error": str(e)
            }