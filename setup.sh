#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · Instalador Integral (Producción)
# ─────────────────────────────────────────────────────────────────────────────
set -e
BOLD='\033[1m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}   🤖  ASISTENTE VIRTUAL IA · Despliegue          ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"

# 1. Entorno y Dependencias
echo -e "\n${CYAN}─── 1. Preparando entorno virtual y dependencias...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
echo -e "${GREEN}   ✅ Entorno listo.${NC}"

# 2. Configuración de claves
if [ ! -f ".env" ]; then
    echo -e "\n${BOLD}─── 2. Configuración de acceso:${NC}"
    read -p "   👉 Introduce tu GROQ_API_KEY: " GROQ_KEY
    read -p "   👉 Define una CLIENT_API_KEY (X-API-Key): " CLIENT_KEY
    echo "GROQ_API_KEY=$GROQ_KEY" > .env
    echo "CLIENT_API_KEY=$CLIENT_KEY" >> .env
    echo "API_PORT=8000" >> .env
    echo "APP_URL=*" >> .env
    echo -e "${GREEN}   ✅ Archivo .env generado.${NC}"
else
    echo -e "\n${YELLOW}   ⚠️  El archivo .env ya existe. Saltando configuración.${NC}"
fi

# 3. Procesar Manuales PDF
echo -e "\n${CYAN}─── 3. Procesando manuales en data/...${NC}"
mkdir -p data logs
for lang in es en ca pt; do
    if [ -f "data/manual_$lang.pdf" ]; then
        echo -e "   📄 Procesando manual [$lang]..."
        python3 src/process_manual.py --lang "$lang" --pdf "data/manual_$lang.pdf"
    fi
done

# 4. Generar Script de Arranque
echo -e "\n${CYAN}─── 4. Generando script de arranque (start.sh)...${NC}"
cat > start.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
PORT=$(grep API_PORT .env | cut -d'=' -f2)
PORT=${PORT:-8000}
# Limpiar puerto para evitar "Address already in use"
fuser -k $PORT/tcp 2>/dev/null || true
echo "🤖 Arrancando asistente en 127.0.0.1:$PORT..."
nohup uvicorn src.api:app --host 127.0.0.1 --port $PORT > logs/api.log 2>&1 &
echo "✅ En ejecución segura (background). Logs en logs/api.log"
EOF
chmod +x start.sh

# 5. Generar Interfaz HTML (chatbot_ejemplo.html)
echo -e "${CYAN}─── 5. Generando interfaz chatbot_ejemplo.html...${NC}"
# Extraemos la key para meterla en el HTML automáticamente
CK=$(grep CLIENT_API_KEY .env | cut -d'=' -f2)

cat > chatbot_ejemplo.html << EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Asistente Virtual</title>
  <style>
    :root { --primary: #1F4E79; --bg: #f4f7f6; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); display: flex; justify-content: center; align-items: center; min-height: 100vh; }
    .chat-card { background: white; width: 95%; max-width: 800px; height: 85vh; border-radius: 15px; box-shadow: 0 8px 30px rgba(0,0,0,0.1); display: flex; flex-direction: column; overflow: hidden; }
    .chat-header { background: var(--primary); color: white; padding: 20px; font-size: 1.2rem; font-weight: bold; }
    .messages { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 15px; }
    .msg { max-width: 80%; padding: 12px 18px; border-radius: 18px; font-size: 15px; line-height: 1.4; position: relative; }
    .msg.user { background: var(--primary); color: white; align-self: flex-end; border-bottom-right-radius: 4px; }
    .msg.bot { background: #edf2f7; color: #2d3748; align-self: flex-start; border-bottom-left-radius: 4px; }
    .source-tag { display: block; margin-top: 8px; font-size: 0.75rem; color: #718096; border-top: 1px solid #cbd5e0; padding-top: 5px; }
    .input-bar { padding: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 10px; background: white; }
    input { flex: 1; padding: 12px; border: 1px solid #e2e8f0; border-radius: 10px; outline: none; }
    select { padding: 10px; border-radius: 10px; border: 1px solid #e2e8f0; }
    button { background: var(--primary); color: white; border: none; padding: 0 20px; border-radius: 10px; cursor: pointer; font-weight: bold; }
    button:disabled { opacity: 0.6; }
  </style>
</head>
<body>
<div class="chat-card">
  <div class="chat-header">🤖 Asistente Virtual IA</div>
  <div class="messages" id="box"><div class="msg bot">Hola, ¿en qué puedo ayudarte hoy?</div></div>
  <div class="input-bar">
    <select id="lang"><option value="es">ES</option><option value="en">EN</option><option value="ca">CA</option></select>
    <input type="text" id="query" placeholder="Escribe tu consulta...">
    <button id="btn">Enviar</button>
  </div>
</div>
<script>
  const API_KEY = "$CK"; 
  const API_PATH = "/proyecto/chatbot-manual/api/query";
  const box = document.getElementById('box');
  const query = document.getElementById('query');
  const btn = document.getElementById('btn');

  async function ask() {
    const text = query.value.trim();
    if(!text) return;
    addMsg(text, 'user');
    query.value = '';
    btn.disabled = true;
    try {
      const r = await fetch(API_PATH, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-API-Key': API_KEY },
        body: JSON.stringify({ question: text, lang: document.getElementById('lang').value })
      });
      const d = await r.json();
      addMsg(d.answer, 'bot', d.sources);
    } catch(e) {
      addMsg("Error al conectar con el servidor.", 'bot');
    }
    btn.disabled = false;
  }

  function addMsg(t, s, sources = []) {
    const d = document.createElement('div');
    d.className = 'msg ' + s;
    d.textContent = t;
    if(sources.length > 0) {
      const span = document.createElement('span');
      span.className = 'source-tag';
      span.textContent = "📚 Referencias: " + [...new Set(sources.map(src => src.section + ' (p.' + src.page + ')'))].join(' | ');
      d.appendChild(span);
    }
    box.appendChild(d);
    box.scrollTop = box.scrollHeight;
  }
  btn.onclick = ask;
  query.onkeypress = (e) => e.key === 'Enter' && ask();
</script>
</body>
</html>
EOF

# 6. Resumen Final
SERVER_IP=$(hostname -I | awk '{print $1}')
API_PORT=$(grep API_PORT .env | cut -d'=' -f2)

echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}   ✅  INSTALACIÓN COMPLETADA                      ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "\n  ${BOLD}Comandos de control:${NC}"
echo -e "      Arrancar:  ${CYAN}bash start.sh${NC}"
echo -e "      Logs:      ${CYAN}tail -f logs/api.log${NC}"
echo -e "\n  ${BOLD}Datos del Servidor:${NC}"
echo -e "      IP Privada:   ${YELLOW}$SERVER_IP${NC}"
echo -e "      Puerto API:   ${YELLOW}$API_PORT${NC}"
echo -e "      Archivo Web:  ${YELLOW}chatbot_ejemplo.html${NC}"
echo -e "      X-API-Key:    ${YELLOW}$CK${NC}"
echo ""