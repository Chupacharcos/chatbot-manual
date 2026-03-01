#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · setup.sh
#  Instalación inicial — ejecutar UNA SOLA VEZ
#  Uso: bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_header() {
    clear
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  🤖  ASISTENTE VIRTUAL IA · Instalación          ${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() { echo ""; echo -e "${CYAN}${BOLD}─── $1 ${NC}"; echo ""; }
print_ok()   { echo -e "${GREEN}  ✅  $1${NC}"; }
print_warn() { echo -e "${YELLOW}  ⚠️   $1${NC}"; }
print_error(){ echo -e "${RED}  ❌  $1${NC}"; }

ask() { echo -e "${BOLD}  👉  $1${NC}"; read -r REPLY; }
confirm() { echo -e "${BOLD}  👉  $1 [s/n]: ${NC}"; read -r ans; [[ "$ans" =~ ^[ssSyY] ]]; }

# ─────────────────────────────────────────────────────────────────────────────
print_header
echo "  Este asistente te guiará por la instalación paso a paso."
echo ""
echo "  Antes de continuar, asegúrate de tener:"
echo "    ✔  El archivo .env con tu GROQ_API_KEY en la raíz del proyecto"
echo "    ✔  Los PDFs de tus manuales en la carpeta data/"
echo ""
read -rp "  Pulsa Enter para comenzar..."

# ─── 1. Verificar estructura ──────────────────────────────────────────────────
print_step "1/8 · Verificando el proyecto"

if [ ! -f "requirements.txt" ] || [ ! -d "src" ]; then
    print_error "No estás en la carpeta raíz del proyecto."
    print_error "Ejecuta: cd chatbot-manual && bash setup.sh"
    exit 1
fi
print_ok "Estructura del proyecto correcta"

# ─── 2. Verificar Python ──────────────────────────────────────────────────────
print_step "2/8 · Verificando Python"

if ! command -v python3 &>/dev/null; then
    print_error "Python3 no está instalado."
    echo "  Instálalo con: sudo apt update && sudo apt install python3 python3-pip python3-venv -y"
    exit 1
fi

PYTHON_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')
PYTHON_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
PYTHON_VERSION="$PYTHON_MAJOR.$PYTHON_MINOR"

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 11 ]; }; then
    print_error "Se requiere Python 3.11+. Versión actual: $PYTHON_VERSION"
    exit 1
fi
print_ok "Python $PYTHON_VERSION encontrado"

# ─── 3. Verificar .env y Groq API Key ────────────────────────────────────────
print_step "3/8 · Verificando API Key de Groq"

if [ ! -f ".env" ]; then
    print_error "No se encuentra el archivo .env"
    echo "  Créalo a partir de .env.example:"
    echo "    cp .env.example .env && nano .env"
    exit 1
fi

if ! grep -q "GROQ_API_KEY" .env || grep -qE "GROQ_API_KEY=(tu_clave_aqui)?$" .env; then
    print_error "La GROQ_API_KEY no está configurada en el archivo .env"
    echo "  Edítalo con: nano .env"
    exit 1
fi
print_ok "Groq API Key encontrada"

# ─── 4. Instalar dependencias ─────────────────────────────────────────────────
print_step "4/8 · Instalando dependencias"
echo "  ⏳ Esto puede tardar 10-15 minutos la primera vez..."
echo ""

if [ ! -d "venv" ]; then
    python3 -m venv venv
    print_ok "Entorno virtual creado"
else
    print_ok "Entorno virtual ya existe, reutilizando"
fi

source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
print_ok "Dependencias instaladas"

# ─── 5. Configurar clave de acceso al asistente ──────────────────────────────
print_step "5/8 · Clave de acceso al asistente (autenticación)"

echo "  Esta clave deberán usarla los desarrolladores que integren el asistente"
echo "  en su app web. Se enviará en la cabecera X-API-Key de cada petición."
echo ""
ask "Introduce una clave de acceso segura (Enter = sin autenticación):"
CLIENT_API_KEY=${REPLY:-""}

if [ -z "$CLIENT_API_KEY" ]; then
    print_warn "Sin clave de acceso — cualquiera con la URL puede usar el asistente"
else
    print_ok "Clave de acceso configurada"
fi

grep -q "^CLIENT_API_KEY=" .env \
    && sed -i "s|^CLIENT_API_KEY=.*|CLIENT_API_KEY=$CLIENT_API_KEY|" .env \
    || echo "CLIENT_API_KEY=$CLIENT_API_KEY" >> .env

# ─── 6. Configurar puerto y CORS ─────────────────────────────────────────────
print_step "6/8 · Configuración del servidor"

ask "¿En qué puerto escuchará el servidor? (Enter = 8000):"
PORT=${REPLY:-8000}
print_ok "Puerto: $PORT"

echo ""
echo "  Introduce la URL de tu aplicación web donde se integrará el asistente."
echo "  Ejemplos: https://miempresa.com  |  http://192.168.1.50  |  http://localhost:3000"
echo "  Varios dominios separados por coma: https://miempresa.com,https://admin.miempresa.com"
echo ""
ask "URL de tu aplicación web (Enter = cualquier origen):"
APP_URL=${REPLY:-"*"}

grep -q "^API_PORT=" .env && sed -i "s|^API_PORT=.*|API_PORT=$PORT|" .env || echo "API_PORT=$PORT" >> .env
grep -q "^APP_URL="  .env && sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|"  .env || echo "APP_URL=$APP_URL"  >> .env

print_ok "Puerto y CORS guardados en .env"

# ─── 7. Procesar manuales PDF ────────────────────────────────────────────────
print_step "7/8 · Procesando manuales PDF"

LANGS=("es" "en" "ca" "pt")
LANG_NAMES=("Español" "English" "Català" "Português")
PROCESSED=0

echo "  Se buscan PDFs en data/ con el formato: manual_es.pdf, manual_en.pdf..."
echo ""

for i in "${!LANGS[@]}"; do
    LANG="${LANGS[$i]}"
    LANG_NAME="${LANG_NAMES[$i]}"
    PDF_PATH="data/manual_${LANG}.pdf"

    if [ -f "$PDF_PATH" ]; then
        echo -e "  📄 Encontrado: ${BOLD}$PDF_PATH${NC} ($LANG_NAME)"
        if confirm "  ¿Procesar este manual?"; then
            echo "  ⏳ Procesando $LANG_NAME (chunking semántico incluido)..."
            python3 src/process_manual.py --lang "$LANG" --pdf "$PDF_PATH"
            print_ok "$LANG_NAME procesado"
            PROCESSED=$((PROCESSED + 1))
        fi
    fi
done

if [ $PROCESSED -eq 0 ]; then
    print_warn "No se procesó ningún manual."
    echo "  Cuando tengas los PDFs en data/ ejecuta:"
    echo "    source venv/bin/activate"
    echo "    python3 src/process_manual.py --lang es --pdf data/manual_es.pdf"
else
    print_ok "$PROCESSED manual(es) procesado(s)"
fi

# ─── 8. Generar start.sh y chatbot_ejemplo.html ──────────────────────────────
print_step "8/8 · Generando archivos de arranque y ejemplo"

SERVER_IP=$(hostname -I | awk '{print $1}')
API_URL="http://${SERVER_IP}:${PORT}"

# ── start.sh ──
cat > start.sh << EOF
#!/bin/bash
# Arranca el servidor. Ejecutar tras cada reinicio.
# Uso: bash start.sh

source venv/bin/activate
source .env
PORT=\${API_PORT:-8000}
IP=\$(hostname -I | awk '{print \$1}')

echo ""
echo "  🤖  Asistente Virtual IA"
echo "  🚀  Servidor arrancando en puerto \$PORT..."
echo "  📡  URL de la API:         http://\$IP:\$PORT"
echo "  📖  Documentación Swagger: http://\$IP:\$PORT/docs"
echo "  📊  Logs en:               logs/chatbot.log"
echo ""
echo "  Ctrl+C para detener"
echo ""

uvicorn src.api:app --host 0.0.0.0 --port "\$PORT"
EOF
chmod +x start.sh
print_ok "start.sh generado"

# ── chatbot_ejemplo.html ──
cat > chatbot_ejemplo.html << EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Asistente Virtual</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Arial, sans-serif; background: #f0f4f8; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
    .chat-container { background: white; border-radius: 16px; box-shadow: 0 4px 24px rgba(0,0,0,0.10); width: 100%; max-width: 700px; display: flex; flex-direction: column; overflow: hidden; }
    .chat-header { background: #1F4E79; color: white; padding: 20px 24px; font-size: 18px; font-weight: bold; }
    .chat-messages { padding: 24px; display: flex; flex-direction: column; gap: 16px; min-height: 300px; max-height: 500px; overflow-y: auto; }
    .mensaje { max-width: 80%; padding: 12px 16px; border-radius: 12px; font-size: 15px; line-height: 1.5; }
    .mensaje.usuario   { background: #1F4E79; color: white; align-self: flex-end; border-bottom-right-radius: 4px; }
    .mensaje.asistente { background: #f0f4f8; color: #222;  align-self: flex-start; border-bottom-left-radius: 4px; }
    .mensaje.cargando  { background: #f0f4f8; color: #888;  align-self: flex-start; font-style: italic; }
    .fuentes { font-size: 12px; color: #888; align-self: flex-start; }
    .chat-input { display: flex; padding: 16px; gap: 10px; border-top: 1px solid #e0e7ef; }
    .chat-input select { padding: 10px 12px; border: 1px solid #cdd8e3; border-radius: 8px; font-size: 14px; background: white; cursor: pointer; }
    .chat-input input { flex: 1; padding: 12px 16px; border: 1px solid #cdd8e3; border-radius: 8px; font-size: 15px; outline: none; }
    .chat-input input:focus { border-color: #2E75B6; }
    .chat-input button { padding: 12px 20px; background: #1F4E79; color: white; border: none; border-radius: 8px; font-size: 15px; font-weight: bold; cursor: pointer; }
    .chat-input button:hover    { background: #2E75B6; }
    .chat-input button:disabled { background: #aaa; cursor: not-allowed; }
  </style>
</head>
<body>
<div class="chat-container">
  <div class="chat-header">🤖 Asistente Virtual · Manual Empresarial</div>
  <div class="chat-messages" id="mensajes">
    <div class="mensaje asistente">¡Hola! Soy el asistente virtual. ¿En qué puedo ayudarte?</div>
  </div>
  <div class="chat-input">
    <select id="idioma">
      <option value="es">🇪🇸 ES</option>
      <option value="en">🇬🇧 EN</option>
      <option value="ca">🏴 CA</option>
      <option value="pt">🇵🇹 PT</option>
    </select>
    <input type="text" id="pregunta" placeholder="Escribe tu pregunta..."
           onkeydown="if(event.key==='Enter') preguntar()"/>
    <button id="boton" onclick="preguntar()">Enviar</button>
  </div>
</div>

<script>
  // ── Configuración (generado automáticamente por setup.sh) ──
  const API_URL    = "${API_URL}";
  const CLIENT_KEY = "${CLIENT_API_KEY}";
  // ───────────────────────────────────────────────────────────

  const mensajesDiv   = document.getElementById('mensajes');
  const inputPregunta = document.getElementById('pregunta');
  const boton         = document.getElementById('boton');

  let sessionId = sessionStorage.getItem('chatbot_session_id') || '';

  function agregarMensaje(texto, tipo, id = null) {
    const div = document.createElement('div');
    div.className = \`mensaje \${tipo}\`;
    if (id) div.id = id;
    div.textContent = texto;
    mensajesDiv.appendChild(div);
    mensajesDiv.scrollTop = mensajesDiv.scrollHeight;
    return div;
  }

  function agregarFuentes(fuentes) {
    if (!fuentes || fuentes.length === 0) return;
    const secciones = [...new Set(fuentes.map(f => \`\${f.section} (p.\${f.page})\`))];
    const div = document.createElement('div');
    div.className = 'fuentes';
    div.textContent = '📚 ' + secciones.join(' · ');
    mensajesDiv.appendChild(div);
    mensajesDiv.scrollTop = mensajesDiv.scrollHeight;
  }

  async function preguntar() {
    const pregunta = inputPregunta.value.trim();
    const lang     = document.getElementById('idioma').value;
    if (!pregunta) return;

    agregarMensaje(pregunta, 'usuario');
    inputPregunta.value = '';
    boton.disabled = true;

    const loadingId = 'loading-' + Date.now();
    agregarMensaje('Consultando el manual...', 'cargando', loadingId);

    try {
      const headers = { 'Content-Type': 'application/json' };
      if (CLIENT_KEY) headers['X-API-Key'] = CLIENT_KEY;

      const res = await fetch(\`\${API_URL}/query\`, {
        method:  'POST',
        headers,
        body: JSON.stringify({ question: pregunta, lang, session_id: sessionId })
      });

      if (res.status === 403) {
        document.getElementById(loadingId)?.remove();
        agregarMensaje('❌ Acceso denegado. Clave de acceso incorrecta.', 'cargando');
        boton.disabled = false;
        return;
      }

      const data = await res.json();

      if (data.session_id) {
        sessionId = data.session_id;
        sessionStorage.setItem('chatbot_session_id', sessionId);
      }

      document.getElementById(loadingId)?.remove();
      agregarMensaje(data.answer, 'asistente');
      agregarFuentes(data.sources);

    } catch (err) {
      document.getElementById(loadingId)?.remove();
      agregarMensaje('❌ No se pudo conectar con el servidor. Comprueba que está arrancado.', 'cargando');
    }

    boton.disabled = false;
    inputPregunta.focus();
  }
</script>
</body>
</html>
EOF
print_ok "chatbot_ejemplo.html generado"

# ─── Resumen final ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅  Instalación completada                       ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Arrancar el servidor:${NC}"
echo -e "  ${CYAN}    bash start.sh${NC}"
echo ""
echo -e "  ${BOLD}Ejemplo listo para usar:${NC}"
echo -e "  ${CYAN}    chatbot_ejemplo.html${NC}"
echo ""
echo -e "  ${BOLD}Logs del servidor:${NC}"
echo -e "  ${CYAN}    tail -f logs/chatbot.log${NC}"
echo ""
echo -e "  ${BOLD}API disponible en:${NC}"
echo -e "  ${CYAN}    http://${SERVER_IP}:${PORT}${NC}"
echo ""