from rag_engine import RAGEngine
import sys

def main():
    print("=" * 60)
    print("🤖 CHATBOT - MANUAL EMPRESARIAL")
    print("=" * 60)
    print("\nCargando sistema RAG...")
    
    try:
        rag = RAGEngine()
    except Exception as e:
        print(f"\n❌ Error al cargar RAG: {e}")
        print("\n💡 ¿Has procesado el manual? Ejecuta primero:")
        print("   python src/process_manual.py")
        sys.exit(1)
    
    print("\n✅ Sistema listo. Escribe 'salir' para terminar.\n")
    
    while True:
        try:
            question = input("👤 Tú: ").strip()
            
            if not question:
                continue
            
            if question.lower() in ['salir', 'exit', 'quit']:
                print("\n👋 ¡Hasta luego!")
                break
            
            response = rag.query(question)
            
            print(f"\n🤖 Bot: {response['answer']}")
            
            # Mostrar fuentes
            if response['sources']:
                print(f"\n📚 Fuentes consultadas: {len(response['sources'])} secciones del manual")
            
            print()
            
        except KeyboardInterrupt:
            print("\n\n👋 ¡Hasta luego!")
            break
        except Exception as e:
            print(f"\n❌ Error: {e}\n")

if __name__ == "__main__":
    main()