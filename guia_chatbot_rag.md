# Guía de Instalación - Asistente Virtual IA
## Chatbot RAG Multiidioma - Manual Empresarial ISO

---

**Sistema Operativo:** Windows 10/11  
**Versión:** 2.0  

---

## ÍNDICE

1. [Requisitos del Sistema](#1-requisitos)
2. [Instalación de Software Base](#2-software)
3. [Configuración del Proyecto](#3-proyecto)
4. [Instalación de Dependencias](#4-dependencias)
5. [Configuración de API Keys](#5-apikeys)
6. [Procesar los Manuales](#6-manuales)
7. [Ejecutar el Chatbot](#7-ejecutar)
8. [Gestión con Git y GitHub](#8-git)
9. [Solución de Problemas](#9-problemas)
10. [Comandos de Referencia](#10-comandos)

---

## 1. Requisitos del Sistema {#1-requisitos}

### Hardware mínimo
- **RAM:** 8GB (16GB recomendado)
- **Disco:** 15GB libres (modelos de IA ocupan espacio)
- **CPU:** Intel i5 / AMD Ryzen 5 o superior

### Software necesario
- Windows 10/11 64-bit
- Conexión a Internet

### Cuentas necesarias
- **Groq** (gratis): https://console.groq.com

---

## 2. Instalación de Software Base {#2-software}

### 2.1 Visual Studio Code

1. Descargar: https://code.visualstudio.com/
2. Ejecutar instalador como Administrador
3. Marcar durante instalación:
   - ✅ Add to PATH
   - ✅ Create desktop icon
   - ✅ Add 'Open with Code' action
4. Instalar extensiones en VS Code (`Ctrl+Shift+X`):
   - **Python** (Microsoft)
   - **Pylance** (Microsoft)

> **Error 5 permisos:** Click derecho en instalador → "Ejecutar como administrador"

---

### 2.2 Python 3.11+

1. Descargar: https://www.python.org/downloads/
2. Ejecutar instalador
3. ⚠️ **CRÍTICO:** Marcar **"Add Python to PATH"**
4. Click "Install Now"

**Verificar:**
```bash
python --version
# Debe mostrar: Python 3.11.x o superior
```

---

### 2.3 Git

1. Descargar: https://git-scm.com/download/win
2. Instalar con opciones por defecto
3. En pantalla de editor: seleccionar **"Use Visual Studio Code"**

**Verificar:**
```bash
git --version
```

**Configurar (una sola vez):**
```bash
git config --global user.name "Tu Nombre"
git config --global user.email "tu@email.com"
```

---

## 3. Configuración del Proyecto {#3-proyecto}

### 3.1 Crear estructura de carpetas

```bash
cd C:\Users\TU_USUARIO\Documents
mkdir Proyectos
cd Proyectos
mkdir chatbot-manual
cd chatbot-manual
mkdir src
mkdir data
mkdir docs
```

### 3.2 Abrir en VS Code

```bash
code .
```

O: File → Open Folder → seleccionar carpeta

### 3.3 Crear entorno virtual

En terminal de VS Code (`Ctrl + Ñ`):

```bash
python -m venv venv
```

**Activar entorno virtual:**

PowerShell:
```bash
venv\Scripts\activate
```

CMD:
```bash
venv\Scripts\activate.bat
```

Debes ver `(venv)` al inicio de la línea.

> **Error scripts PowerShell deshabilitados:**
> ```powershell
> # Abrir PowerShell como Administrador y ejecutar:
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> # Escribir S y Enter
> ```

### 3.4 Estructura final del proyecto

```
chatbot-manual/
├── src/
│   ├── process_manual.py    # Procesamiento de PDFs
│   ├── rag_engine.py        # Motor RAG con IA
│   └── chatbot.py           # Interfaz de usuario
├── data/
│   ├── manual_es.pdf        # Manual en español
│   ├── manual_en.pdf        # Manual en inglés
│   ├── manual_ca.pdf        # Manual en catalán
│   └── manual_pt.pdf        # Manual en portugués
├── faiss_index/             # Generado automáticamente
│   ├── es/
│   ├── en/
│   ├── ca/
│   └── pt/
├── .env                     # API Keys (NO subir a Git)
├── .gitignore
├── requirements.txt
└── README.md
```

---

## 4. Instalación de Dependencias {#4-dependencias}

Con el entorno virtual activado `(venv)`:

```bash
pip install -r requirements.txt
```

> Esto tardará **10-15 minutos** la primera vez.  
> Docling, torch y sentence-transformers son pesados.  
> Es normal ver muchas líneas instalándose.

**Si prefieres instalar manualmente:**

```bash
# LLM y RAG
pip install langchain langchain-community langchain-core
pip install langchain-groq langchain-huggingface
pip install langchain-text-splitters langchain-experimental
pip install groq

# Embeddings y búsqueda
pip install sentence-transformers torch faiss-cpu

# Docling (extracción inteligente de PDF)
pip install docling

# Detección de idioma
pip install langdetect

# API y utilidades
pip install fastapi uvicorn python-dotenv pypdf
```

**Verificar instalación:**
```bash
pip list
```

---

## 5. Configuración de API Keys {#5-apikeys}

### 5.1 Obtener API Key de Groq (gratis)

1. Ir a: https://console.groq.com/
2. Registrarse (gratis, sin tarjeta)
3. Menú izquierdo → "API Keys"
4. "Create API Key" → Nombre: "chatbot-manual"
5. Copiar la key (empieza con `gsk_...`)

### 5.2 Crear archivo .env

En la raíz del proyecto, crear archivo `.env`:

```env
GROQ_API_KEY=gsk_tu_key_aqui_pegala_completa
```

> ⚠️ **NUNCA** subir este archivo a Git  
> ⚠️ El archivo `.gitignore` ya lo excluye

---

## 6. Procesar los Manuales {#6-manuales}

### 6.1 Colocar los PDFs

Copiar los manuales en la carpeta `data/`:
```
data/manual_es.pdf
data/manual_en.pdf
data/manual_ca.pdf
data/manual_pt.pdf
```

### 6.2 Procesar cada manual

Ejecutar para cada idioma disponible:

```bash
# Español
python src/process_manual.py --lang es --pdf data/manual_es.pdf

# Inglés
python src/process_manual.py --lang en --pdf data/manual_en.pdf

# Catalán
python src/process_manual.py --lang ca --pdf data/manual_ca.pdf

# Portugués
python src/process_manual.py --lang pt --pdf data/manual_pt.pdf
```

> ⏱️ **Primera ejecución:** Tardará 5-10 minutos por idioma  
> (descarga el modelo de embeddings ~1.5GB la primera vez)  
> Las siguientes ejecuciones son más rápidas.

**Resultado esperado:**
```
🚀 PROCESANDO MANUAL: data/manual_es.pdf [ES]
📖 Extrayendo estructura del PDF con Docling...
✅ Extraídas 45 secciones
🧮 Cargando modelo de embeddings...
🔪 Aplicando chunking Parent-Child semántico...
✅ Creados 45 parents y 187 children
💾 Guardando índice FAISS (es)...
✅ MANUAL [ES] PROCESADO CORRECTAMENTE
```

### 6.3 Actualización mensual

Cuando cambie el manual, solo reprocesa el idioma afectado:

```bash
python src/process_manual.py --lang es --pdf data/manual_es.pdf
```

El sistema borra automáticamente el índice anterior y crea uno nuevo.

---

## 7. Ejecutar el Chatbot {#7-ejecutar}

```bash
python src/chatbot.py
```

**Comandos disponibles en el chat:**
- `salir` / `exit` / `sortir` / `sair` → Cerrar
- `limpiar` / `clear` / `netejar` / `limpar` → Borrar historial

**Ejemplo de uso:**
```
👤 Tú: What is ISO 9001?
🌍 Idioma detectado: EN
🤖 Asistente: ISO 9001 is an international standard...
📚 Fuentes: Quality Management (p.5) | Introduction (p.1)

👤 Tú: cuants dies de vacances tinc?
🌍 Idioma detectado: CA
🤖 Asistente: Segons el manual, els empleats tenen dret a...
```

---

## 8. Gestión con Git y GitHub {#8-git}

### 8.1 Inicializar repositorio

```bash
cd C:\Users\TU_USUARIO\Documents\Proyectos\chatbot-manual
git init
git add .
git status
```

Verificar que NO aparezcan: `.env`, `venv/`, `data/`, `faiss_index/`

```bash
git commit -m "Initial commit: RAG chatbot multiidioma"
```

### 8.2 Crear repositorio en GitHub

1. Ir a: https://github.com → "+" → "New repository"
2. Nombre: `chatbot-manual`
3. ⚠️ Seleccionar **"Private"**
4. NO marcar ninguna opción adicional
5. "Create repository"

### 8.3 Conectar y subir

```bash
git remote add origin https://github.com/TU_USUARIO/chatbot-manual.git
git branch -M main
git push -u origin main
```

**Si pide autenticación - Personal Access Token:**
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token" → marcar `repo`
3. Copiar token (`ghp_...`)
4. Usarlo como contraseña al hacer push

### 8.4 Workflow diario

```bash
git add .
git commit -m "descripción del cambio"
git push
```

---

## 9. Solución de Problemas {#9-problemas}

### Python no se reconoce como comando
**Solución:** Reinstalar Python marcando "Add to PATH"

### Error scripts PowerShell deshabilitados
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Error al instalar docling
```bash
pip install docling --no-cache-dir
```

### Error FAISS: "unable to open database file"
```bash
# Borrar índice corrupto y reprocesar
Remove-Item -Recurse -Force .\faiss_index\
python src/process_manual.py --lang es --pdf data/manual_es.pdf
```

### No detecta bien el idioma
- El sistema usa fallback a español si no detecta el idioma
- Frases muy cortas pueden no detectarse bien (es normal)

### Respuestas lentas la primera vez
- Los modelos de embeddings se cargan en memoria la primera vez
- Las consultas siguientes son más rápidas

### Error "No module named X"
```bash
# Verificar que el entorno virtual está activo (debe verse (venv))
venv\Scripts\activate
pip install -r requirements.txt
```

### Modelo Groq decommissioned
Cambiar en `src/rag_engine.py`:
```python
LLM_MODEL = "llama-3.3-70b-versatile"  # Modelo actual
```
Modelos disponibles en: https://console.groq.com/docs/models

---

## 10. Comandos de Referencia {#10-comandos}

### Entorno virtual
```bash
# Activar (PowerShell)
venv\Scripts\activate

# Activar (CMD)
venv\Scripts\activate.bat

# Desactivar
deactivate
```

### Procesar manuales
```bash
python src/process_manual.py --lang es --pdf data/manual_es.pdf
python src/process_manual.py --lang en --pdf data/manual_en.pdf
python src/process_manual.py --lang ca --pdf data/manual_ca.pdf
python src/process_manual.py --lang pt --pdf data/manual_pt.pdf
```

### Ejecutar chatbot
```bash
python src/chatbot.py
```

### Git
```bash
git add .
git commit -m "mensaje"
git push
git status
git log --oneline
```

### Pip
```bash
pip install -r requirements.txt
pip list
pip freeze > requirements.txt
```

---

## Checklist de Instalación

- [ ] VS Code instalado con extensiones Python y Pylance
- [ ] Python 3.11+ instalado con PATH configurado
- [ ] Git instalado y configurado
- [ ] Carpeta del proyecto creada
- [ ] Entorno virtual creado y activado `(venv)`
- [ ] Dependencias instaladas sin errores
- [ ] Archivo `.env` creado con API Key de Groq
- [ ] PDFs colocados en `data/`
- [ ] Manuales procesados (carpetas en `faiss_index/`)
- [ ] Chatbot ejecutado correctamente
- [ ] Repositorio GitHub privado creado y subido

---

**Versión:** 2.0 | **Estado:** Producción lista ✅