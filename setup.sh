#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · Instalador Pro (FIX FINAL)
# ─────────────────────────────────────────────────────────────────────────────
set -e
BOLD='\033[1m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}    🤖   ASISTENTE VIRTUAL IA · Instalación         ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"

# 1. Entorno
echo -e "\n${CYAN}─── 1. Preparando entorno...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 2. Configuración
if [ ! -f ".env" ]; then
    read -p "    👉 GROQ_API_KEY: " GROQ_KEY
    read -p "    👉 CLIENT_API_KEY: " CLIENT_KEY
    read -p "    👉 Puerto [8088]: " SELECTED_PORT
    SELECTED_PORT=${SELECTED_PORT:-8088}
    echo "GROQ_API_KEY=$GROQ_KEY" > .env
    echo "CLIENT_API_KEY=$CLIENT_KEY" >> .env
    echo "API_PORT=$SELECTED_PORT" >> .env
    echo "APP_URL=*" >> .env
else
    SELECTED_PORT=$(grep API_PORT .env | cut -d'=' -f2)
fi

# 3. Manuales y Carpetas
mkdir -p data logs faiss_index
for lang in es en ca pt; do
    if [ -f "data/manual_$lang.pdf" ]; then
        python3 src/process_manual.py --lang "$lang" --pdf "data/manual_$lang.pdf" > /dev/null 2>&1
    fi
done

# 4. Servicio Systemd
USER_NAME=$(whoami)
CUR_DIR=$(pwd)
sudo bash -c "cat > /etc/systemd/system/chatbot.service << EOF
[Unit]
Description=Chatbot IA
After=network.target
[Service]
User=$USER_NAME
WorkingDirectory=$CUR_DIR
ExecStart=$CUR_DIR/venv/bin/uvicorn src.api:app --host 127.0.0.1 --port $SELECTED_PORT
Restart=always
StandardOutput=append:$CUR_DIR/logs/api.log
StandardError=append:$CUR_DIR/logs/api.log
[Install]
WantedBy=multi-user.target
EOF"
sudo systemctl daemon-reload
sudo systemctl enable chatbot
sudo systemctl restart chatbot

# 5. Generar HTML (BLINDADO)
CK=$(grep CLIENT_API_KEY .env | cut -d'=' -f2)

cat > chatbot_ejemplo.html << 'EOF_WRAPPER'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Asistente IA</title>
    <style>
        :root { --p: #1F4E79; --bg: #f4f7f6; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: system-ui, sans-serif; background: var(--bg); display: flex; justify-content: center; align-items: center; min-height: 100vh; }
        .chat { background: white; width: 95%; max-width: 700px; height: 85vh; border-radius: 15px; display: flex; flex-direction: column; box-shadow: 0 8px 30px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: var(--p); color: white; padding: 20px; font-weight: bold; }
        .msgs { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 12px; }
        .m { max-width: 80%; padding: 12px 18px; border-radius: 15px; font-size: 15px; }
        .u { background: var(--p); color: white; align-self: flex-end; }
        .b { background: #edf2f7; align-self: flex-start; }
        .bar { padding: 20px; border-top: 1px solid #eee; display: flex; gap: 10px; }
        input { flex: 1; padding: 12px; border: 1px solid #ddd; border-radius: 10px; }
        input:disabled { background: #f0f0f0; }
        button { background: var(--p); color: white; border: none; padding: 0 20px; border-radius: 10px; cursor: pointer; }
    </style>
</head>
<body>
<div class="chat">
    <div class="header">🤖 Asistente IA</div>
    <div id="box" class="msgs"><div class="m b">Hola. ¿En qué puedo ayudarte?</div></div>
    <div class="bar">
        <select id="lang"><option value="es">ES</option><option value="en">EN</option></select>
        <input type="text" id="q" placeholder="Escribe aquí...">
        <button id="go">Enviar</button>
    </div>
</div>
<script>
    const box = document.getElementById('box'), q = document.getElementById('q'), btn = document.getElementById('go'), lg = document.getElementById('lang');
    const API_KEY = "TOKEN_PLACEHOLDER";
    
    // IMPORTANTE: Si accedes por IP directamente, asegúrate de que esta ruta sea accesible
    const API_PATH = "/proyecto/chatbot-manual/api/query";

    async function send() {
        const val = q.value.trim();
        if(!val) return;

        addMsg('u', val);
        q.value = '';
        q.disabled = btn.disabled = true;

        try {
            console.log("Enviando petición...");
            const response = await fetch(API_PATH, {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'X-API-Key': API_KEY 
                },
                body: JSON.stringify({ question: val, lang: lg.value })
            });

            if(!response.ok) throw new Error('Error en respuesta');
            
            const data = await response.json();
            addMsg('b', data.answer);
        } catch (error) {
            console.error(error);
            addMsg('b', '❌ Error: No se pudo conectar con la API. Revisa la consola (F12).');
        } finally {
            // Esto se ejecuta SIEMPRE, liberando el input
            q.disabled = btn.disabled = false;
            q.focus();
        }
    }

    function addMsg(s, t) {
        const d = document.createElement('div');
        d.className = 'm ' + s;
        d.textContent = t;
        box.appendChild(d);
        box.scrollTop = box.scrollHeight;
    }

    btn.onclick = send;
    q.onkeypress = (e) => { if(e.key === 'Enter') send(); };
</script>
</body>
</html>
EOF_WRAPPER

sed -i "s/TOKEN_PLACEHOLDER/$CK/" chatbot_ejemplo.html

echo -e "\n${GREEN}✅ Instalación terminada. Chatbot en puerto $SELECTED_PORT.${NC}"