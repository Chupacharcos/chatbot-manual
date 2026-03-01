#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · Instalador Pro con Auto-Arranque (Systemd)
# ─────────────────────────────────────────────────────────────────────────────
set -e
BOLD='\033[1m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}    🤖   ASISTENTE VIRTUAL IA · Instalación         ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"

# 1. Entorno y Dependencias
echo -e "\n${CYAN}${BOLD}─── 1. Instalando librerías de IA ─────────────────${NC}"
echo -e "${YELLOW}⏳ Paso pesado: descargando ~2GB (2-4 min)...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip --quiet

# Animación de progreso simple
(pip install -r requirements.txt --quiet) & 
pid=$!
while kill -0 $pid 2>/dev/null; do
    echo -ne "    ${BLUE}📦 Instalando dependencias... [====|    ]${NC}\r" ; sleep 1
    echo -ne "    ${BLUE}📦 Instalando dependencias... [========|]${NC}\r" ; sleep 1
done
echo -e "${GREEN}    ✅ Librerías instaladas correctamente.         ${NC}"

# 2. Configuración de Red y Seguridad
echo -e "\n${CYAN}${BOLD}─── 2. Configuración de Red ───────────────────────${NC}"
if [ ! -f ".env" ]; then
    read -p "    👉 Introduce GROQ_API_KEY: " GROQ_KEY
    read -p "    👉 Define CLIENT_API_KEY (Pass Web): " CLIENT_KEY
    read -p "    👉 Puerto para el Chatbot [8088]: " SELECTED_PORT
    SELECTED_PORT=${SELECTED_PORT:-8088}

    echo "GROQ_API_KEY=$GROQ_KEY" > .env
    echo "CLIENT_API_KEY=$CLIENT_KEY" >> .env
    echo "API_PORT=$SELECTED_PORT" >> .env
    echo "APP_URL=*" >> .env
else
    SELECTED_PORT=$(grep API_PORT .env | cut -d'=' -f2)
    echo -e "${GREEN}    ✅ Usando configuración existente (.env) en puerto $SELECTED_PORT.${NC}"
fi

# 3. Procesar Manuales
echo -e "\n${CYAN}${BOLD}─── 3. Procesando Manuales PDF ────────────────────${NC}"
mkdir -p data logs faiss_index
for lang in es en ca pt; do
    if [ -f "data/manual_$lang.pdf" ]; then
        echo -e "    📄 Procesando [$lang]... "
        python3 src/process_manual.py --lang "$lang" --pdf "data/manual_$lang.pdf" > /dev/null 2>&1
    fi
done

# 4. CREAR SERVICIO DE SISTEMA (Auto-arranque)
echo -e "\n${CYAN}${BOLD}─── 4. Configurando Servicio de Sistema ───────────${NC}"
USER_NAME=$(whoami)
CUR_DIR=$(pwd)

sudo bash -c "cat > /etc/systemd/system/chatbot.service << EOF
[Unit]
Description=Servicio Chatbot IA
After=network.target

[Service]
User=$USER_NAME
WorkingDirectory=$CUR_DIR
ExecStart=$CUR_DIR/venv/bin/uvicorn src.api:app --host 127.0.0.1 --port $SELECTED_PORT
Restart=always
RestartSec=5
StandardOutput=append:$CUR_DIR/logs/api.log
StandardError=append:$CUR_DIR/logs/api.log

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable chatbot
sudo systemctl restart chatbot
echo -e "${GREEN}    ✅ Servicio 'chatbot' creado y activo.${NC}"

# 5. Generar Interfaz HTML Completa (USANDO ESCAPE SEGURO)
echo -e "\n${CYAN}${BOLD}─── 5. Generando Interfaz Demo ────────────────────${NC}"
CK=$(grep CLIENT_API_KEY .env | cut -d'=' -f2)

# Usamos 'EOF' con comillas para que bash no intente procesar los símbolos de JS
cat > chatbot_ejemplo.html << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Asistente IA</title>
  <style>
    :root { --p: #1F4E79; --bg: #f4f7f6; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', sans-serif; background: var(--bg); display: flex; justify-content: center; align-items: center; min-height: 100vh; }
    .chat { background: white; width: 95%; max-width: 700px; height: 85vh; border-radius: 15px; display: flex; flex-direction: column; box-shadow: 0 8px 30px rgba(0,0,0,0.1); overflow: hidden; }
    .header { background: var(--p); color: white; padding: 20px; font-weight: bold; font-size: 1.2rem; }
    .msgs { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 12px; }
    .m { max-width: 80%; padding: 12px 18px; border-radius: 15px; font-size: 15px; line-height: 1.4; }
    .u { background: var(--p); color: white; align-self: flex-end; border-bottom-right-radius: 2px; }
    .b { background: #edf2f7; color: #2d3748; align-self: flex-start; border-bottom-left-radius: 2px; }
    .src { display: block; margin-top: 8px; font-size: 0.7rem; color: #718096; border-top: 1px solid #cbd5e0; padding-top: 5px; }
    .bar { padding: 20px; border-top: 1px solid #eee; display: flex; gap: 10px; background: white; }
    input { flex: 1; padding: 12px; border: 1px solid #ddd; border-radius: 10px; outline: none; }
    input:disabled { background: #f0f0f0; cursor: not-allowed; }
    button { background: var(--p); color: white; border: none; padding: 0 20px; border-radius: 10px; cursor: pointer; font-weight: bold; }
    button:disabled { opacity: 0.6; }
  </style>
</head>
<body>
<div class="chat">
  <div class="header">🤖 Asistente Virtual Corporativo</div>
  <div class="msgs" id="box"><div class="m b">¡Hola! Soy tu asistente IA. ¿En qué puedo ayudarte?</div></div>
  <div class="bar">
    <select id="lang" style="padding:10px; border-radius:10px; border:1px solid #ddd;">
        <option value="es">ES</option><option value="en">EN</option><option value="ca">CA</option><option value="pt">PT</option>
    </select>
    <input type="text" id="q" placeholder="Escribe tu consulta...">
    <button id="go">Enviar</button>
  </div>
</div>
<script>
  const box = document.getElementById('box'), q = document.getElementById('q'), btn = document.getElementById('go'), lg = document.getElementById('lang');
  const API_KEY = "CK_PLACEHOLDER";
  const API_PATH = "/proyecto/chatbot-manual/api/query";

  async function send() {
    const val = q.value.trim(); if(!val) return;
    add('u', val); q.value=''; q.disabled = btn.disabled = true;
    try {
      const r = await fetch(API_PATH, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-API-Key': API_KEY },
        body: JSON.stringify({ question: val, lang: lg.value })
      });
      if(!r.ok) throw new Error();
      const d = await r.json();
      add('b', d.answer, d.sources);
    } catch(e) { add('b', '❌ Error de conexión con el servidor.'); }
    finally { q.disabled = btn.disabled = false; q.focus(); }
  }

  function add(s, t, src = []) {
    const d = document.createElement('div'); d.className = 'm ' + s; d.textContent = t;
    if(src && src.length > 0) {
      const span = document.createElement('span'); span.className = 'src';
      span.textContent = '📚 Fuentes: ' + [...new Set(src.map(x => (x.section || 'Ref') + ' (p.' + (x.page || '?') + ')'))].join(' | ');
      d.appendChild(span);
    }
    box.appendChild(d); box.scrollTop = box.scrollHeight;
  }
  btn.onclick = send; q.onkeypress = (e) => e.key === 'Enter' && send();
</script>
</body>
</html>
EOF

# Inyectamos la API KEY real de forma segura usando sed
sed -i "s/CK_PLACEHOLDER/$CK/" chatbot_ejemplo.html

# 6. Resumen Final
echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}    ✅  INSTALACIÓN COMPLETADA Y CHATBOT ACTIVO    ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "\n  El chatbot arrancará solo si reinicias el servidor."
echo -e "  Estado del servicio: ${CYAN}sudo systemctl status chatbot${NC}"
echo -e "  Puerto de escucha:   ${YELLOW}$SELECTED_PORT${NC}"
echo -e "  Demo generada en:    ${YELLOW}chatbot_ejemplo.html${NC}\n"