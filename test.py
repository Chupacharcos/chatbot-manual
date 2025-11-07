from langchain_groq import ChatGroq
from dotenv import load_dotenv
import os

# Cargar variables de entorno
load_dotenv()

print("🔧 Probando conexión con Groq...")

try:
    # Crear cliente con modelo actualizado
    llm = ChatGroq(
        temperature=0,
        model_name="llama-3.3-70b-versatile",  # Modelo actualizado
        groq_api_key=os.getenv("GROQ_API_KEY")
    )
    
    # Test simple
    response = llm.invoke("Di: '¡Todo funciona correctamente!'")
    print("\n✅ ÉXITO:")
    print(response.content)
    
except Exception as e:
    print(f"\n❌ ERROR: {e}")