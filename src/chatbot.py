import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rag_engine import RAGEngine

def main():
    print("=" * 60)
    print("🤖 ASISTENTE VIRTUAL - MANUAL EMPRESARIAL")
    print("=" * 60)
    print("\nCargando sistema...")

    try:
        rag = RAGEngine()
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)

    # Seleccionar idioma al inicio
    print("\n🌍 Selecciona idioma:")
    print("  es - Español")
    print("  en - English")
    print("  ca - Català")
    print("  pt - Português")

    while True:
        selected_lang = input("\nIdioma (es/en/ca/pt): ").strip().lower()
        if selected_lang in ["es", "en", "ca", "pt"]:
            break
        print("❌ Idioma no válido")

    print(f"\n✅ Usando manual en: {selected_lang.upper()}")
    print("─" * 60)
    print("Comandos:")
    print("  'salir'    → Cerrar")
    print("  'limpiar'  → Borrar historial")
    print("  'idioma'   → Cambiar idioma")
    print("─" * 60)
    print()

    # Historial local de la sesión CLI
    history = []

    while True:
        try:
            question = input("👤 Tú: ").strip()

            if not question:
                continue

            if question.lower() in ["salir", "exit", "quit"]:
                print("\n👋 ¡Hasta luego!")
                break

            if question.lower() in ["limpiar", "clear"]:
                history = []
                print("🗑️  Historial borrado\n")
                continue

            if question.lower() == "idioma":
                print("\n🌍 Selecciona nuevo idioma (es/en/ca/pt):")
                new_lang = input("Idioma: ").strip().lower()
                if new_lang in ["es", "en", "ca", "pt"]:
                    selected_lang = new_lang
                    history = []  # Resetear historial al cambiar idioma
                    print(f"✅ Cambiado a: {selected_lang.upper()}\n")
                continue

            # Consultar pasando el historial de esta sesión
            response = rag.query(
                question=question,
                lang=selected_lang,
                history=history
            )

            # Actualizar historial local
            history.append({"role": "user",      "content": question})
            history.append({"role": "assistant",  "content": response["answer"]})

            print(f"\n🤖 Asistente: {response['answer']}")

            if response["sources"]:
                sections = set()
                for doc in response["sources"]:
                    section = doc.get("section", "?")
                    page    = doc.get("page", "?")
                    sections.add(f"{section} (p.{page})")
                print(f"\n📚 Fuentes: {' | '.join(sorted(sections))}")

            print()

        except KeyboardInterrupt:
            print("\n\n👋 ¡Hasta luego!")
            break
        except Exception as e:
            print(f"\n❌ Error: {e}\n")

if __name__ == "__main__":
    main()