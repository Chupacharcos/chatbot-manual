#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · Instalador Pro - Modo Dual (Estático + Dinámico)
# ─────────────────────────────────────────────────────────────────────────────
set -e
BOLD='\033[1m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}    🤖   ASISTENTE VIRTUAL IA · Instalación         ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"

# ─── SELECCIONAR MODO ───────────────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}Selecciona el modo de instalación:${NC}\n"
echo -e "  ${BLUE}1)${NC} PRODUCCIÓN (Estático - PDFs pre-procesados)"
echo -e "  ${BLUE}2)${NC} DESARROLLO (Dinámico - Soporta PDFs desde web)"
echo -e ""
read -p "    👉 Opción [1-2]: " INSTALL_MODE
INSTALL_MODE=${INSTALL_MODE:-1}

if [ "$INSTALL_MODE" != "1" ] && [ "$INSTALL_MODE" != "2" ]; then
    echo -e "${RED}❌ Opción inválida${NC}"
    exit 1
fi

# ─── 1. ENTORNO Y DEPENDENCIAS ─────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 1. Instalando librerías de IA ─────────────────${NC}"
echo -e "${YELLOW}⏳ Paso pesado: descargando ~2GB (2-4 min)...${NC}"

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip --quiet

# Animación de progreso
(pip install -r requirements.txt --quiet) & 
pid=$!
spinner=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
i=0
while kill -0 $pid 2>/dev/null; do
    echo -ne "   ${BLUE}📦 Instalando dependencias... ${spinner[$i]}${NC}\r"
    i=$(( (i+1) % 10 ))
    sleep 0.3
done
wait $pid
echo -e "${GREEN}    ✅ Librerías instaladas correctamente.         ${NC}"

# ─── 2. CONFIGURACIÓN DE RED Y SEGURIDAD ───────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 2. Configuración de Red ───────────────────────${NC}"

if [ ! -f ".env" ]; then
    echo -e "${YELLOW}No se encontró .env. Configurando...${NC}\n"
    
    read -p "    👉 GROQ_API_KEY: " GROQ_KEY
    read -p "    👉 OPENAI_API_KEY (opcional): " OPENAI_KEY
    read -p "    👉 CLIENT_API_KEY (seguridad): " CLIENT_KEY
    read -p "    👉 Puerto deseado [8088]: " SELECTED_PORT
    SELECTED_PORT=${SELECTED_PORT:-8088}

    cat > .env << EOF
GROQ_API_KEY=$GROQ_KEY
OPENAI_API_KEY=$OPENAI_KEY
CLIENT_API_KEY=$CLIENT_KEY
API_PORT=$SELECTED_PORT
APP_URL=*
EOF
    echo -e "${GREEN}    ✅ Archivo .env creado${NC}"
else
    SELECTED_PORT=$(grep "API_PORT" .env | cut -d'=' -f2)
    echo -e "${GREEN}    ✅ Usando configuración existente (.env).${NC}"
fi

# ─── 3. DIRECTORIOS NECESARIOS ──────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 3. Preparando directorios ─────────────────────${NC}"

mkdir -p data logs faiss_index

if [ "$INSTALL_MODE" = "2" ]; then
    mkdir -p uploads faiss_sessions
    echo -e "    ${CYAN}📁 uploads/${NC} (para PDFs subidos desde web)"
    echo -e "    ${CYAN}📁 faiss_sessions/${NC} (para índices dinámicos)"
fi

echo -e "${GREEN}    ✅ Directorios listos.${NC}"

# ─── 4. PROCESAR MANUALES (SOLO EN MODO PRODUCCIÓN) ────────────────────────
echo -e "\n${CYAN}${BOLD}─── 4. Procesando Manuales PDF ────────────────────${NC}"

if [ "$INSTALL_MODE" = "1" ]; then
    # MODO PRODUCCIÓN: Procesar todos los PDFs
    FOUND_PDFS=0
    for lang in es en ca pt; do
        if [ -f "data/manual_$lang.pdf" ]; then
            FOUND_PDFS=$((FOUND_PDFS + 1))
            echo -e "    ${CYAN}📄 Procesando manual_$lang.pdf${NC}"
            python3 src/process_manual.py --lang "$lang" --pdf "data/manual_$lang.pdf" || {
                echo -e "    ${YELLOW}⚠️  Error procesando $lang (continuando...)${NC}"
            }
        fi
    done
    
    if [ $FOUND_PDFS -eq 0 ]; then
        echo -e "    ${YELLOW}⚠️  No se encontraron PDFs en data/manual_*.pdf${NC}"
        echo -e "    ${YELLOW}    Coloca los PDFs ahí y ejecuta: python3 src/process_manual.py --lang es --pdf data/manual_es.pdf${NC}"
    else
        echo -e "${GREEN}    ✅ $FOUND_PDFS manual(es) procesado(s).${NC}"
    fi
else
    # MODO DESARROLLO: Saltar procesamiento (se hace dinámicamente)
    echo -e "    ${CYAN}📄 Modo Dinámico: PDFs se procesan al subirlos desde web${NC}"
    echo -e "${GREEN}    ✅ Listo para recibir PDFs.${NC}"
fi

# ─── 5. CREAR SERVICIO SYSTEMD ──────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 5. Configurando auto-arranque (Systemd) ───────${NC}"

USER_NAME=$(whoami)
CUR_DIR=$(pwd)
SERVICE_NAME="chatbot"

# Crear script wrapper que activa venv
cat > start_chatbot.sh << 'EOF_START'
#!/bin/bash
source venv/bin/activate
exec uvicorn src.api:app --host 127.0.0.1 --port $API_PORT
EOF_START
chmod +x start_chatbot.sh

# Reemplazar puerto en script
sed -i "s|\$API_PORT|$SELECTED_PORT|g" start_chatbot.sh

# Crear servicio systemd
sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF_SERVICE
[Unit]
Description=Chatbot IA - Asistente Virtual
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$CUR_DIR
Environment=\"PATH=$CUR_DIR/venv/bin\"
ExecStart=$CUR_DIR/start_chatbot.sh
Restart=always
RestartSec=10
StandardOutput=append:$CUR_DIR/logs/api.log
StandardError=append:$CUR_DIR/logs/api.log

[Install]
WantedBy=multi-user.target
EOF_SERVICE
"

# Activar servicio
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

echo -e "${GREEN}    ✅ Servicio systemd configurado.${NC}"

# ─── 6. CREAR ARCHIVO HTML DE DEMO ──────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 6. Generando archivo HTML de demostración ────${NC}"

CK=$(grep "CLIENT_API_KEY" .env | cut -d'=' -f2)

if [ "$INSTALL_MODE" = "1" ]; then
    # VERSIÓN PRODUCCIÓN: API Key directa
    cat > chatbot_ejemplo.html << 'EOF_STATIC'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chatbot IA</title>
    <style>
        :root { --primary: #1F4E79; --bg: #f4f7f6; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: var(--bg);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            background: white;
            width: 95%;
            max-width: 700px;
            height: 85vh;
            border-radius: 15px;
            display: flex;
            flex-direction: column;
            box-shadow: 0 8px 30px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: var(--primary);
            color: white;
            padding: 20px;
            font-weight: bold;
            text-align: center;
        }
        .messages {
            flex: 1;
            padding: 20px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .message {
            max-width: 80%;
            padding: 12px 18px;
            border-radius: 15px;
            font-size: 15px;
            word-wrap: break-word;
        }
        .user-msg {
            background: var(--primary);
            color: white;
            align-self: flex-end;
        }
        .bot-msg {
            background: #edf2f7;
            align-self: flex-start;
        }
        .footer {
            padding: 20px;
            border-top: 1px solid #eee;
            display: flex;
            gap: 10px;
        }
        input, select {
            padding: 12px;
            border: 1px solid #ddd;
            border-radius: 10px;
            font-size: 15px;
        }
        input {
            flex: 1;
        }
        input:disabled {
            background: #f0f0f0;
            cursor: not-allowed;
        }
        button {
            background: var(--primary);
            color: white;
            border: none;
            padding: 12px 20px;
            border-radius: 10px;
            cursor: pointer;
            font-weight: bold;
        }
        button:hover:not(:disabled) {
            opacity: 0.9;
        }
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">🤖 Chatbot IA</div>
    <div id="messages" class="messages">
        <div class="message bot-msg">Hola 👋 ¿En qué puedo ayudarte?</div>
    </div>
    <div class="footer">
        <select id="language">
            <option value="es">🇪🇸 Español</option>
            <option value="en">🇬🇧 English</option>
            <option value="ca">🇨🇦 Català</option>
            <option value="pt">🇵🇹 Português</option>
        </select>
        <input type="text" id="input" placeholder="Escribe tu pregunta...">
        <button id="send">Enviar</button>
    </div>
</div>

<script>
    const messagesBox = document.getElementById('messages');
    const inputField = document.getElementById('input');
    const sendBtn = document.getElementById('send');
    const langSelect = document.getElementById('language');
    
    const API_KEY = "WILL_BE_REPLACED";
    const API_URL = "http://127.0.0.1:WILL_BE_PORT/query";

    async function sendMessage() {
        const text = inputField.value.trim();
        if (!text) return;

        // Mostrar mensaje del usuario
        addMessage(text, 'user');
        inputField.value = '';
        inputField.disabled = true;
        sendBtn.disabled = true;

        try {
            const response = await fetch(API_URL, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-API-Key': API_KEY
                },
                body: JSON.stringify({
                    question: text,
                    lang: langSelect.value
                })
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            addMessage(data.answer, 'bot');
        } catch (error) {
            addMessage(`❌ Error: ${error.message}`, 'bot');
        } finally {
            inputField.disabled = false;
            sendBtn.disabled = false;
            inputField.focus();
        }
    }

    function addMessage(text, sender) {
        const div = document.createElement('div');
        div.className = `message ${sender === 'user' ? 'user-msg' : 'bot-msg'}`;
        div.textContent = text;
        messagesBox.appendChild(div);
        messagesBox.scrollTop = messagesBox.scrollHeight;
    }

    sendBtn.addEventListener('click', sendMessage);
    inputField.addEventListener('keypress', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });
</script>
</body>
</html>
EOF_STATIC
    sed -i "s/WILL_BE_REPLACED/$CK/" chatbot_ejemplo.html
    sed -i "s/WILL_BE_PORT/$SELECTED_PORT/" chatbot_ejemplo.html
    
else
    # VERSIÓN DESARROLLO: Con soporte para PDFs dinámicos
    cat > chatbot_ejemplo.html << 'EOF_DYNAMIC'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chatbot IA con PDF</title>
    <style>
        :root { --primary: #1F4E79; --accent: #64ffda; --bg: #020617; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg);
            color: #8892b0;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container { width: 100%; max-width: 900px; }
        #setup-area {
            text-align: center;
            padding: 60px 20px;
        }
        .upload-box {
            max-width: 500px;
            margin: 0 auto;
            padding: 40px;
            border: 2px dashed var(--accent);
            border-radius: 15px;
            cursor: pointer;
            transition: all 0.3s;
        }
        .upload-box:hover {
            border-color: #fff;
            background: rgba(100, 255, 218, 0.05);
        }
        .upload-box input { display: none; }
        .icon { font-size: 60px; margin-bottom: 20px; }
        .upload-text { font-size: 18px; margin-bottom: 10px; }
        .help-text { font-size: 12px; color: #8892b0; }
        
        #chat-area { display: none; }
        .chat-container {
            background: rgba(17, 34, 64, 0.4);
            border: 1px solid rgba(100, 255, 218, 0.1);
            border-radius: 15px;
            display: flex;
            flex-direction: column;
            height: 600px;
        }
        .chat-header {
            padding: 15px;
            border-bottom: 1px solid rgba(100, 255, 218, 0.1);
            font-size: 12px;
            color: var(--accent);
        }
        .chat-messages {
            flex: 1;
            overflow-y: auto;
            padding: 20px;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .message {
            max-width: 70%;
            padding: 12px 16px;
            border-radius: 10px;
            font-size: 14px;
        }
        .user-msg {
            background: rgba(100, 255, 218, 0.1);
            border: 1px solid rgba(100, 255, 218, 0.2);
            color: var(--accent);
            align-self: flex-end;
        }
        .bot-msg {
            background: #112240;
            border: 1px solid rgba(255, 255, 255, 0.05);
            color: #ccd6f6;
            align-self: flex-start;
        }
        .chat-input-area {
            padding: 15px;
            border-top: 1px solid rgba(100, 255, 218, 0.1);
            display: flex;
            gap: 10px;
        }
        input[type="text"] {
            flex: 1;
            background: #112240;
            border: 1px solid rgba(100, 255, 218, 0.2);
            padding: 10px 15px;
            color: #ccd6f6;
            border-radius: 8px;
            font-size: 14px;
        }
        input[type="text"]:focus {
            outline: none;
            border-color: var(--accent);
        }
        input[type="text"]:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        button {
            background: var(--primary);
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            font-size: 12px;
        }
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .loader {
            color: var(--accent);
            font-size: 12px;
            animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 0.5; }
            50% { opacity: 1; }
        }
    </style>
</head>
<body>
<div class="container">
    <div id="setup-area">
        <div class="upload-box" id="dropZone">
            <div class="icon">📄</div>
            <div class="upload-text">Sube tu PDF aquí</div>
            <div class="help-text">o haz clic para seleccionar</div>
            <input type="file" id="pdfInput" accept=".pdf">
        </div>
        <div id="loader" class="loader" style="margin-top: 20px; display: none;">
            Procesando PDF... puede tardar 30-60 segundos
        </div>
    </div>

    <div id="chat-area">
        <div class="chat-container">
            <div class="chat-header">📄 <span id="filename"></span> | Modo: RAG Engine</div>
            <div class="chat-messages" id="messages">
                <div class="message bot-msg">He procesado el documento. ¿Qué quieres saber?</div>
            </div>
            <div class="chat-input-area">
                <input type="text" id="input" placeholder="Pregunta sobre el documento...">
                <button id="send">Consultar</button>
            </div>
        </div>
    </div>
</div>

<script>
    const dropZone = document.getElementById('dropZone');
    const pdfInput = document.getElementById('pdfInput');
    const setupArea = document.getElementById('setup-area');
    const chatArea = document.getElementById('chat-area');
    const messagesBox = document.getElementById('messages');
    const inputField = document.getElementById('input');
    const sendBtn = document.getElementById('send');
    const loader = document.getElementById('loader');
    const filenameSpan = document.getElementById('filename');
    
    const API_KEY = "WILL_BE_REPLACED";
    const API_BASE = "http://127.0.0.1:WILL_BE_PORT";
    
    let sessionId = null;

    // Drag & drop
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(evt => {
        dropZone.addEventListener(evt, (e) => {
            e.preventDefault();
            e.stopPropagation();
        });
    });

    ['dragenter', 'dragover'].forEach(evt => {
        dropZone.addEventListener(evt, () => {
            dropZone.style.borderColor = '#fff';
        });
    });

    ['dragleave', 'drop'].forEach(evt => {
        dropZone.addEventListener(evt, () => {
            dropZone.style.borderColor = 'var(--accent)';
        });
    });

    dropZone.addEventListener('drop', (e) => {
        const files = e.dataTransfer.files;
        if (files.length) uploadPDF(files[0]);
    });

    dropZone.addEventListener('click', () => pdfInput.click());
    pdfInput.addEventListener('change', (e) => {
        if (e.target.files.length) uploadPDF(e.target.files[0]);
    });

    async function uploadPDF(file) {
        if (file.type !== 'application/pdf') {
            alert('Solo se aceptan archivos PDF');
            return;
        }

        const formData = new FormData();
        formData.append('pdf', file);
        formData.append('lang', 'es');

        loader.style.display = 'block';

        try {
            const response = await fetch(`${API_BASE}/upload`, {
                method: 'POST',
                headers: { 'X-API-Key': API_KEY },
                body: formData
            });

            if (!response.ok) throw new Error(`Error ${response.status}`);
            
            const data = await response.json();
            sessionId = data.session_id;
            filenameSpan.textContent = file.name;
            
            setupArea.style.display = 'none';
            chatArea.style.display = 'block';
            inputField.focus();
        } catch (error) {
            alert(`Error: ${error.message}`);
        } finally {
            loader.style.display = 'none';
        }
    }

    async function sendMessage() {
        const text = inputField.value.trim();
        if (!text || !sessionId) return;

        addMessage(text, 'user');
        inputField.value = '';
        inputField.disabled = true;
        sendBtn.disabled = true;

        try {
            const response = await fetch(`${API_BASE}/query`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-API-Key': API_KEY
                },
                body: JSON.stringify({
                    question: text,
                    session_id: sessionId,
                    lang: 'es'
                })
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            addMessage(data.answer, 'bot');
        } catch (error) {
            addMessage(`❌ Error: ${error.message}`, 'bot');
        } finally {
            inputField.disabled = false;
            sendBtn.disabled = false;
            inputField.focus();
        }
    }

    function addMessage(text, sender) {
        const div = document.createElement('div');
        div.className = `message ${sender === 'user' ? 'user-msg' : 'bot-msg'}`;
        div.textContent = text;
        messagesBox.appendChild(div);
        messagesBox.scrollTop = messagesBox.scrollHeight;
    }

    sendBtn.addEventListener('click', sendMessage);
    inputField.addEventListener('keypress', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });
</script>
</body>
</html>
EOF_DYNAMIC
    sed -i "s/WILL_BE_REPLACED/$CK/" chatbot_ejemplo.html
    sed -i "s/WILL_BE_PORT/$SELECTED_PORT/" chatbot_ejemplo.html
fi

echo -e "${GREEN}    ✅ HTML de demostración creado.${NC}"

# ─── 7. INICIAR SERVICIO ───────────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}─── 7. Iniciando el servicio ──────────────────────${NC}"

sudo systemctl start "$SERVICE_NAME"
sleep 2

if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}    ✅ Chatbot iniciado correctamente.${NC}"
else
    echo -e "${YELLOW}    ⚠️  Intenta iniciar manualmente: sudo systemctl start chatbot${NC}"
fi

# ─── RESUMEN FINAL ──────────────────────────────────────────────────────────
clear
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}    ✅  INSTALACIÓN COMPLETADA                     ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"

echo -e "\n${CYAN}${BOLD}MODO SELECCIONADO:${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
    echo -e "  ${GREEN}📚 PRODUCCIÓN (Índices Pre-procesados)${NC}"
    echo -e "  • PDFs procesados con: python3 src/process_manual.py"
    echo -e "  • Consultas rápidas contra índices FAISS estáticos"
    echo -e "  • Ideal para servidores del cliente"
else
    echo -e "  ${GREEN}🚀 DESARROLLO (PDFs Dinámicos)${NC}"
    echo -e "  • Sube PDFs desde web en tiempo real"
    echo -e "  • Se crean índices FAISS por sesión"
    echo -e "  • Ideal para demostración y desarrollo"
fi

echo -e "\n${CYAN}${BOLD}INFORMACIÓN DEL SERVICIO:${NC}"
echo -e "  Estado:  ${CYAN}sudo systemctl status chatbot${NC}"
echo -e "  Logs:    ${CYAN}tail -f logs/api.log${NC}"
echo -e "  Restart: ${CYAN}sudo systemctl restart chatbot${NC}"

echo -e "\n${CYAN}${BOLD}ACCESO:${NC}"
echo -e "  URL Local:    ${CYAN}http://127.0.0.1:$SELECTED_PORT${NC}"
echo -e "  HTML Demo:    ${CYAN}./chatbot_ejemplo.html${NC}"
echo -e "  API Key:      ${CYAN}${CK}${NC}"

echo -e "\n${CYAN}${BOLD}COMANDOS ÚTILES:${NC}"
echo -e "  Ver logs:     ${CYAN}tail -f logs/api.log${NC}"
echo -e "  Test API:     ${CYAN}curl -H 'X-API-Key: ${CK}' http://127.0.0.1:$SELECTED_PORT/${NC}"
echo -e "  Stop:         ${CYAN}sudo systemctl stop chatbot${NC}"
echo -e "  Restart:      ${CYAN}sudo systemctl restart chatbot${NC}"

if [ "$INSTALL_MODE" = "1" ]; then
    echo -e "\n${YELLOW}${BOLD}ℹ️  PARA PROCESAR NUEVOS PDFs EN PRODUCCIÓN:${NC}"
    echo -e "  ${CYAN}python3 src/process_manual.py --lang es --pdf data/manual_es.pdf${NC}"
    echo -e "  Luego reinicia: ${CYAN}sudo systemctl restart chatbot${NC}"
else
    echo -e "\n${YELLOW}${BOLD}ℹ️  PRUEBA LA DEMO CON PDFs DINÁMICOS:${NC}"
    echo -e "  1. Abre: ${CYAN}file://$(pwd)/chatbot_ejemplo.html${NC}"
    echo -e "  2. Sube un PDF"
    echo -e "  3. Haz preguntas sobre el PDF"
fi

echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"