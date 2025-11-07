from langchain_community.embeddings import HuggingFaceEmbeddings  # ✅ USAR ESTE
from langchain_community.vectorstores import FAISS
from langchain_groq import ChatGroq
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate
import os
from dotenv import load_dotenv

load_dotenv()

class RAGEngine:
    def __init__(self, db_path="./faiss_db"):
        # Cargar embeddings
        self.embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
        )
        
        # Cargar vectorstore FAISS
        self.vectorstore = FAISS.load_local(
            db_path,
            self.embeddings,
            allow_dangerous_deserialization=True
        )
        
        # Configurar LLM
        self.llm = ChatGroq(
            groq_api_key=os.getenv("GROQ_API_KEY"),
            model_name="llama-3.1-8b-instant",
            temperature=0.1
        )
        
        # Crear prompt personalizado
        self.prompt = PromptTemplate(
            template="""Eres un asistente especializado en el manual de la empresa. 
Responde la pregunta basándote únicamente en el contexto proporcionado.

Contexto: {context}

Pregunta: {question}

Si la respuesta no está en el contexto, di amablemente que no tienes esa información en el manual.

Respuesta:""",
            input_variables=["context", "question"]
        )
        
        # Crear cadena de QA
        self.qa_chain = RetrievalQA.from_chain_type(
            llm=self.llm,
            chain_type="stuff",
            retriever=self.vectorstore.as_retriever(
                search_type="similarity",
                search_kwargs={"k": 3}
            ),
            chain_type_kwargs={"prompt": self.prompt},
            return_source_documents=True
        )
    
    def query(self, question):
        try:
            result = self.qa_chain({"query": question})
            return {
                "answer": result["result"],
                "sources": result.get("source_documents", [])
            }
        except Exception as e:
            return {
                "answer": f"Error al procesar la consulta: {str(e)}",
                "sources": []
            }