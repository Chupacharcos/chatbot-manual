#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  ASISTENTE VIRTUAL IA · Instalador completo
#  Uso: bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -e

BOLD='\033[1m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

_ok()   { echo -e "${GREEN}    ✅ $1${NC}"; }
_info() { echo -e "    ${CYAN}ℹ  $1${NC}"; }
_warn() { echo -e "    ${YELLOW}⚠️  $1${NC}"; }
_err()  { echo -e "    ${RED}❌ $1${NC}"; }
_step() { echo -e "\n${CYAN}${BOLD}── $1${NC}"; }
_rule() { echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ─── BANNER ─────────────────────────────────────────────────────────────────
clear
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}    🤖   ASISTENTE VIRTUAL IA · Instalación        ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"

# ═══════════════════════════════════════════════════════════════════════════
# 0. PRE-FLIGHT: comprobar requisitos del sistema
# ═══════════════════════════════════════════════════════════════════════════
_step "0. Comprobando requisitos del sistema"

NGINX_AVAILABLE=0

if ! command -v python3 &>/dev/null; then
    _err "python3 no encontrado."
    echo -e "       Instala con: ${CYAN}sudo apt update && sudo apt install -y python3 python3-venv python3-pip${NC}"
    exit 1
fi

if ! python3 -c "import venv" 2>/dev/null; then
    _err "python3-venv no instalado."
    echo -e "       Instala con: ${CYAN}sudo apt install -y python3-venv${NC}"
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    _err "sudo no disponible."; exit 1
fi

_ok "python3 $(python3 --version 2>&1 | cut -d' ' -f2)"

if command -v nginx &>/dev/null; then
    NGINX_AVAILABLE=1
    _ok "nginx disponible"
else
    _warn "nginx no detectado. Instala con: sudo apt install -y nginx"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 1. SELECCIONAR MODO
# ═══════════════════════════════════════════════════════════════════════════
_step "1. Modo de instalación"
echo ""
echo -e "  ${BLUE}1)${NC} ${BOLD}PRODUCCIÓN${NC}  — Documentos pre-cargados (manual, catálogo, FAQ...)"
echo -e "     └─ Sube tus PDFs una vez → el chatbot responde sobre ese contenido siempre."
echo ""
echo -e "  ${BLUE}2)${NC} ${BOLD}DESARROLLO${NC}  — PDFs dinámicos subidos desde el navegador"
echo -e "     └─ Cada visitante sube su propio PDF y el chatbot lo analiza al momento."
echo ""
read -p "    👉 Opción [1]: " INSTALL_MODE
INSTALL_MODE=${INSTALL_MODE:-1}

if [[ "$INSTALL_MODE" != "1" && "$INSTALL_MODE" != "2" ]]; then
    _err "Opción inválida"; exit 1
fi

FOUND_PDFS=0

# ═══════════════════════════════════════════════════════════════════════════
# 2. COMPROBACIÓN TEMPRANA DE PDFs (solo modo Producción)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$INSTALL_MODE" = "1" ]; then
    _step "2. Comprobación de documentos PDF"
    echo ""
    mkdir -p data
    for lang in es en ca pt; do
        if [ -f "data/manual_$lang.pdf" ]; then
            FOUND_PDFS=$((FOUND_PDFS + 1))
            _ok "Encontrado: data/manual_$lang.pdf"
        fi
    done

    if [ "$FOUND_PDFS" -eq 0 ]; then
        echo ""
        _warn "No se encontraron PDFs en data/"
        echo ""
        echo -e "    ${BOLD}El chatbot necesita tus documentos PDF para poder responder.${NC}"
        echo -e "    Coloca tus archivos con estos nombres:"
        echo -e "      ${CYAN}data/manual_es.pdf${NC}  ← versión en español"
        echo -e "      ${CYAN}data/manual_en.pdf${NC}  ← versión en inglés (opcional)"
        echo ""
        echo -e "    Puedes añadirlos ahora (abre otro terminal y cópialos) o continuar"
        echo -e "    sin ellos y procesarlos después con:"
        echo -e "      ${CYAN}./venv/bin/python3 src/process_manual.py --lang es --pdf data/manual_es.pdf${NC}"
        echo -e "      ${CYAN}sudo systemctl restart chatbot${NC}"
        echo ""
        read -p "    👉 ¿Continuar sin PDFs ahora? [s/N]: " CONT
        CONT=${CONT:-N}
        if [[ ! "$CONT" =~ ^[sS]$ ]]; then
            echo -e "\n${YELLOW}Instalación pausada. Añade tus PDFs a data/ y vuelve a ejecutar setup.sh${NC}\n"
            exit 0
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 3. INSTALAR DEPENDENCIAS
# ═══════════════════════════════════════════════════════════════════════════
_step "3. Instalando librerías de IA"
echo -e "    ${YELLOW}⏳ Descargando modelos de IA (~2 GB). Puede tardar 3-5 minutos...${NC}\n"

[ ! -d "venv" ] && python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip --quiet

(pip install -r requirements.txt --quiet) &
pid=$!
spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
i=0
while kill -0 $pid 2>/dev/null; do
    echo -ne "   ${BLUE}📦 Instalando dependencias... ${spinner[$i]}${NC}\r"
    i=$(( (i+1) % 10 )); sleep 0.3
done
wait $pid
_ok "Dependencias instaladas"

# ═══════════════════════════════════════════════════════════════════════════
# 4. CONFIGURACIÓN .env
# ═══════════════════════════════════════════════════════════════════════════
_step "4. Configuración de acceso"

if [ ! -f ".env" ]; then
    echo ""
    echo -e "    ${BOLD}Necesitas una clave API de Groq (gratuita en 5 minutos):${NC}"
    echo -e "    ${CYAN}→ https://console.groq.com${NC}  →  'API Keys'  →  'Create API Key'"
    echo ""
    read -p "    👉 GROQ_API_KEY: " GROQ_KEY
    echo ""
    read -p "    👉 CLIENT_API_KEY (contraseña de acceso al chatbot): " CLIENT_KEY
    echo ""
    read -p "    👉 Puerto del servidor [8088]: " SELECTED_PORT
    SELECTED_PORT=${SELECTED_PORT:-8088}
    echo ""

    echo -e "    ${CYAN}${BOLD}¿Cómo accederán los visitantes al chatbot desde sus navegadores?${NC}"
    echo ""
    echo -e "  ${BLUE}1)${NC} ${BOLD}Via nginx / proxy inverso${NC}  ${YELLOW}← recomendado si tienes dominio con nginx${NC}"
    echo -e "     └─ URL limpia: https://misitio.com/chatbot-api  (seguro, HTTPS)"
    echo ""
    echo -e "  ${BLUE}2)${NC} ${BOLD}Acceso directo IP:puerto${NC}"
    echo -e "     └─ URL: http://IP:${SELECTED_PORT}  (requiere abrir puerto en firewall)"
    echo ""
    read -p "    👉 Opción [1]: " ACCESS_MODE
    ACCESS_MODE=${ACCESS_MODE:-1}

    if [ "$ACCESS_MODE" = "1" ]; then
        BIND_HOST="127.0.0.1"
        echo ""
        echo -e "    ${CYAN}URL completa donde quedará accesible el chatbot vía nginx.${NC}"
        echo -e "    ${YELLOW}Ejemplo: https://misitio.com/chatbot-api${NC}"
        echo ""
        read -p "    👉 PUBLIC_API_URL: " PUBLIC_API_URL
        PUBLIC_API_URL=${PUBLIC_API_URL:-http://127.0.0.1:$SELECTED_PORT}
    else
        BIND_HOST="0.0.0.0"
        echo ""
        read -p "    👉 IP pública o dominio de este servidor: " SERVER_HOST
        PUBLIC_API_URL="http://${SERVER_HOST}:${SELECTED_PORT}"
    fi

    cat > .env << EOF
GROQ_API_KEY=$GROQ_KEY
CLIENT_API_KEY=$CLIENT_KEY
API_PORT=$SELECTED_PORT
BIND_HOST=$BIND_HOST
PUBLIC_API_URL=$PUBLIC_API_URL
APP_URL=*
EOF
    _ok "Archivo .env creado"
else
    SELECTED_PORT=$(grep "^API_PORT" .env | cut -d'=' -f2)
    BIND_HOST=$(grep "^BIND_HOST" .env 2>/dev/null | cut -d'=' -f2 || echo "127.0.0.1")
    BIND_HOST=${BIND_HOST:-127.0.0.1}
    PUBLIC_API_URL=$(grep "^PUBLIC_API_URL" .env | cut -d'=' -f2)
    PUBLIC_API_URL=${PUBLIC_API_URL:-http://127.0.0.1:$SELECTED_PORT}
    ACCESS_MODE="1"
    [ "$BIND_HOST" = "0.0.0.0" ] && ACCESS_MODE="2"
    _ok "Usando configuración existente (.env)"
fi

CK=$(grep "^CLIENT_API_KEY" .env | cut -d'=' -f2)

# ═══════════════════════════════════════════════════════════════════════════
# 5. DIRECTORIOS
# ═══════════════════════════════════════════════════════════════════════════
_step "5. Preparando directorios"
mkdir -p data logs faiss_index
[ "$INSTALL_MODE" = "2" ] && mkdir -p uploads faiss_sessions
_ok "Directorios listos"

# ═══════════════════════════════════════════════════════════════════════════
# 6. PROCESAR PDFs
# ═══════════════════════════════════════════════════════════════════════════
_step "6. Procesando documentos PDF"

if [ "$INSTALL_MODE" = "1" ]; then
    FOUND_PDFS=0
    for lang in es en ca pt; do
        if [ -f "data/manual_$lang.pdf" ]; then
            FOUND_PDFS=$((FOUND_PDFS + 1))
            _info "Indexando manual_$lang.pdf..."
            python3 src/process_manual.py --lang "$lang" --pdf "data/manual_$lang.pdf" || \
                _warn "Error procesando $lang (puedes reintentar manualmente)"
        fi
    done
    [ "$FOUND_PDFS" -gt 0 ] && _ok "$FOUND_PDFS documento(s) indexado(s)" || _info "Sin PDFs que procesar ahora"
else
    _info "Modo dinámico: los PDFs se indexan al subirlos"
    _ok "Listo"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 7. SERVICIO SYSTEMD
# ═══════════════════════════════════════════════════════════════════════════
_step "7. Configurando servicio del sistema (auto-arranque)"

USER_NAME=$(whoami)
CUR_DIR=$(pwd)

cat > start_chatbot.sh << 'EOF_START'
#!/bin/bash
source venv/bin/activate
exec uvicorn src.api:app --host WILL_BE_HOST --port WILL_BE_PORT
EOF_START
chmod +x start_chatbot.sh
sed -i "s/WILL_BE_HOST/$BIND_HOST/" start_chatbot.sh
sed -i "s/WILL_BE_PORT/$SELECTED_PORT/" start_chatbot.sh

sudo bash -c "cat > /etc/systemd/system/chatbot.service << EOF_SVC
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
EOF_SVC"

sudo systemctl daemon-reload
sudo systemctl enable chatbot --quiet 2>/dev/null || true
_ok "Servicio chatbot configurado y activado en el arranque"

# ═══════════════════════════════════════════════════════════════════════════
# 8. CONFIGURAR NGINX
# ═══════════════════════════════════════════════════════════════════════════
_step "8. Configurando nginx"

# Extraer path del PUBLIC_API_URL para el location de nginx
PROXY_PATH=$(python3 -c "
from urllib.parse import urlparse
u = urlparse('$PUBLIC_API_URL')
p = u.path.rstrip('/')
if not p: p = '/chatbot-api'
p = p + '/'
print(p)
" 2>/dev/null || echo "/chatbot-api/")

# Generar siempre el snippet por si el auto-config falla
cat > nginx_chatbot.conf << EOF_NGINX
# ── Chatbot IA — Añadir DENTRO del bloque server{} de tu nginx ─────────────
    # CHATBOT_IA_WIDGET — no eliminar este comentario
    location ${PROXY_PATH} {
        proxy_pass         http://127.0.0.1:${SELECTED_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
    }
EOF_NGINX

NGINX_CONFIGURED=0

if [ "$BIND_HOST" = "0.0.0.0" ]; then
    _info "Modo IP directa — nginx no necesario"
    _warn "Abre el puerto en el firewall: sudo ufw allow $SELECTED_PORT/tcp"
    NGINX_CONFIGURED=1

elif [ "$NGINX_AVAILABLE" -eq 0 ]; then
    _warn "nginx no instalado — instálalo y añade nginx_chatbot.conf a tu server{}"

else
    # Buscar configs nginx activas
    NGINX_FILES=()
    for f in /etc/nginx/sites-enabled/*; do
        [ -e "$f" ] && NGINX_FILES+=("$f")
    done
    for f in /etc/nginx/conf.d/*.conf; do
        [ -e "$f" ] && NGINX_FILES+=("$f")
    done

    if [ ${#NGINX_FILES[@]} -eq 0 ]; then
        _warn "No se encontraron configs nginx activas"
        _info "Añade manualmente nginx_chatbot.conf a tu bloque server{}"
    else
        echo ""
        echo -e "    ${BOLD}Configuraciones nginx encontradas:${NC}"
        for i in "${!NGINX_FILES[@]}"; do
            echo -e "      ${BLUE}$((i+1)))${NC} ${NGINX_FILES[$i]}"
        done
        echo -e "      ${BLUE}0)${NC} Configurar manualmente (no tocar ninguno)"
        echo ""
        read -p "    👉 ¿En qué archivo está el bloque server{} de tu dominio? [1]: " NCHOICE
        NCHOICE=${NCHOICE:-1}

        if [ "$NCHOICE" = "0" ]; then
            _info "Saltado. Añade nginx_chatbot.conf a tu server{} manualmente."

        elif [[ "$NCHOICE" =~ ^[0-9]+$ ]] && [ "$NCHOICE" -ge 1 ] && [ "$NCHOICE" -le "${#NGINX_FILES[@]}" ]; then
            NGINX_FILE="${NGINX_FILES[$((NCHOICE-1))]}"
            NGINX_REAL=$(readlink -f "$NGINX_FILE")
            _info "Archivo: $NGINX_REAL"

            # Comprobar si ya está configurado
            if grep -q "CHATBOT_IA_WIDGET" "$NGINX_REAL" 2>/dev/null; then
                _ok "nginx ya tiene el bloque del chatbot. Sin cambios."
                NGINX_CONFIGURED=1
            else
                # Hacer backup
                TS=$(date +%s)
                BKFILE="${NGINX_REAL}.bak.${TS}"
                sudo cp "$NGINX_REAL" "$BKFILE"
                _info "Backup: $BKFILE"

                # Script Python para insertar el location block
                PYSCRIPT=$(mktemp /tmp/nginx_insert_XXXXXX.py)
                cat > "$PYSCRIPT" << 'PYEOF'
import sys

nginx_file = sys.argv[1]
proxy_path = sys.argv[2]
port       = sys.argv[3]

block = (
    "\n    # CHATBOT_IA_WIDGET — no eliminar este comentario\n"
    "    location " + proxy_path + " {\n"
    "        proxy_pass         http://127.0.0.1:" + port + "/;\n"
    "        proxy_http_version 1.1;\n"
    "        proxy_set_header   Host              $host;\n"
    "        proxy_set_header   X-Real-IP         $remote_addr;\n"
    "        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;\n"
    "        proxy_set_header   X-Forwarded-Proto $scheme;\n"
    "        proxy_read_timeout 120s;\n"
    "        proxy_connect_timeout 30s;\n"
    "    }\n"
)

with open(nginx_file, 'r') as f:
    content = f.read()

# Buscar el cierre del bloque server{} (línea que empieza con '}' sin sangría)
lines = content.split('\n')
insert_at = -1
for i in range(len(lines) - 1, -1, -1):
    stripped = lines[i].strip()
    if stripped == '}' and (lines[i].startswith('}') or lines[i] == '}'):
        insert_at = i
        break

if insert_at == -1:
    # Fallback: insertar antes del último }
    idx = content.rfind('}')
    if idx == -1:
        print('ERROR: no closing brace found')
        sys.exit(1)
    new_content = content[:idx] + block + content[idx:]
else:
    lines.insert(insert_at, block.rstrip('\n'))
    new_content = '\n'.join(lines)

with open(nginx_file, 'w') as f:
    f.write(new_content)

print('ok')
PYEOF

                INSERT_RESULT=$(sudo python3 "$PYSCRIPT" "$NGINX_REAL" "$PROXY_PATH" "$SELECTED_PORT" 2>&1)
                rm -f "$PYSCRIPT"

                if [ "$INSERT_RESULT" = "ok" ]; then
                    if sudo nginx -t 2>/dev/null; then
                        sudo systemctl reload nginx
                        _ok "nginx configurado y recargado automáticamente"
                        NGINX_CONFIGURED=1
                    else
                        _warn "nginx -t falló. Restaurando backup..."
                        sudo cp "$BKFILE" "$NGINX_REAL"
                        sudo nginx -t 2>/dev/null && _ok "Backup restaurado correctamente"
                        echo ""
                        _warn "Inserta manualmente en tu server{} el contenido de nginx_chatbot.conf:"
                        echo ""
                        cat nginx_chatbot.conf
                    fi
                else
                    sudo cp "$BKFILE" "$NGINX_REAL" 2>/dev/null || true
                    _warn "No se pudo auto-insertar ($INSERT_RESULT). Inserta nginx_chatbot.conf manualmente."
                fi
            fi
        else
            _warn "Opción inválida. Configura nginx manualmente."
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 9. GENERAR WIDGET EMBEBIBLE
# ═══════════════════════════════════════════════════════════════════════════
_step "9. Generando widget embebible"

if [ "$INSTALL_MODE" = "1" ]; then
# ── Widget Producción (índice estático, selector de idioma) ──────────────────
cat > chatbot_widget.html << 'EOF_WIDGET'
<!-- ═══════════════════════════════════════════════════════════════════
     CHATBOT WIDGET — Pega este bloque completo antes de </body>
     El botón 💬 aparecerá en todas las páginas automáticamente.
═══════════════════════════════════════════════════════════════════ -->
<div id="_cw_btn" onclick="_cwToggle()" role="button" aria-label="Abrir/cerrar chatbot"><span>🤖 Asistente Virtual</span><span id="_cw_btn_icon">▲</span></div>
<div id="_cw_box" role="dialog" aria-label="Chatbot">
  <div id="_cw_hdr">
    <span>🤖 Asistente Virtual</span>
    <div>
      <select id="_cw_lang" aria-label="Idioma">
        <option value="es">🇪🇸 ES</option>
        <option value="en">🇬🇧 EN</option>
      </select>
      <button id="_cw_close" onclick="_cwToggle()" aria-label="Cerrar">✕</button>
    </div>
  </div>
  <div id="_cw_msgs" role="log"></div>
  <div id="_cw_foot">
    <input id="_cw_inp" type="text" placeholder="Escribe tu pregunta..." autocomplete="off"
           onkeypress="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();_cwSend();}">
    <button id="_cw_send" onclick="_cwSend()" aria-label="Enviar">➤</button>
  </div>
</div>
<style>
  #_cw_btn{position:fixed;bottom:0;right:24px;width:240px;height:44px;background:#1F4E79;color:#fff;border-radius:12px 12px 0 0;display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:14px;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;cursor:pointer;box-shadow:0 -2px 12px rgba(0,0,0,.2);z-index:9998;user-select:none;border:none;transition:background .2s}
  #_cw_btn:hover{background:#1a3f62}
  #_cw_box{position:fixed;bottom:44px;right:24px;width:360px;max-height:520px;background:#fff;border-radius:16px 16px 0 0;box-shadow:0 8px 32px rgba(0,0,0,.2);display:none;flex-direction:column;z-index:9999;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:14px}
  #_cw_hdr{background:#1F4E79;color:#fff;padding:13px 15px;display:flex;justify-content:space-between;align-items:center;font-weight:600;font-size:14px}
  #_cw_hdr>div{display:flex;gap:8px;align-items:center}
  #_cw_lang{background:rgba(255,255,255,.9);color:#1F4E79;border:none;padding:3px 6px;border-radius:6px;cursor:pointer;font-size:12px;outline:none;font-weight:600}
  #_cw_close{background:none;border:none;color:rgba(255,255,255,.8);font-size:18px;cursor:pointer;padding:0 2px;line-height:1;transition:color .2s}
  #_cw_close:hover{color:#fff}
  #_cw_msgs{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:9px;min-height:100px;max-height:370px;scroll-behavior:smooth}
  .cw-b,.cw-u{max-width:84%;padding:9px 13px;border-radius:12px;word-wrap:break-word;line-height:1.5;white-space:pre-wrap}
  .cw-b{background:#f0f4f8;color:#2d3748;align-self:flex-start;border-bottom-left-radius:3px}
  .cw-u{background:#1F4E79;color:#fff;align-self:flex-end;border-bottom-right-radius:3px}
  .cw-typing{color:#aaa;font-style:italic;font-size:13px;align-self:flex-start;padding:6px 12px}
  #_cw_foot{padding:11px;border-top:1px solid #eee;display:flex;gap:8px;align-items:center}
  #_cw_inp{flex:1;padding:9px 13px;border:1px solid #ddd;border-radius:10px;font-size:14px;outline:none;transition:border-color .2s}
  #_cw_inp:focus{border-color:#1F4E79}
  #_cw_inp:disabled{background:#f5f5f5;cursor:not-allowed}
  #_cw_send{background:#1F4E79;color:#fff;border:none;padding:9px 14px;border-radius:10px;cursor:pointer;font-size:16px;transition:background .2s,opacity .2s;line-height:1}
  #_cw_send:hover:not(:disabled){background:#1a3f62}
  #_cw_send:disabled{opacity:.45;cursor:not-allowed}
  @media(max-width:420px){#_cw_box{width:calc(100vw - 16px);right:8px;bottom:44px}#_cw_btn{right:8px;width:calc(100vw - 16px)}}
</style>
<script>
(function(){
  var API="WILL_BE_API_URL";
  var KEY="WILL_BE_API_KEY";
  var sid=sessionStorage.getItem('_cw_sid')||"";
  var open=false;
  var box,msgs,inp,snd;
  function _init(){
    box=document.getElementById('_cw_box');
    msgs=document.getElementById('_cw_msgs');
    inp=document.getElementById('_cw_inp');
    snd=document.getElementById('_cw_send');
    var lang=document.getElementById('_cw_lang').value;
    _addMsg(lang==='en'?'Hi! \uD83D\uDC4B How can I help you?':'\u00a1Hola! \uD83D\uDC4B \u00bfEn qu\u00e9 puedo ayudarte?','cw-b');
  }
  window._cwToggle=function(){
    if(!box){_init();}
    open=!open;
    box.style.display=open?'flex':'none';
    document.getElementById('_cw_btn_icon').textContent=open?'\u25BC':'\u25B2';
    if(open){inp.focus();}
  };
  window._cwSend=function(){
    if(!box){_init();}
    var txt=inp.value.trim();
    if(!txt||snd.disabled)return;
    _addMsg(txt,'cw-u');
    inp.value='';
    _setLoading(true);
    var lang=document.getElementById('_cw_lang').value;
    var typing=_addMsg(lang==='en'?'Typing\u2026':'Escribiendo\u2026','cw-typing');
    fetch(API+'/query',{
      method:'POST',
      headers:{'Content-Type':'application/json','X-API-Key':KEY},
      body:JSON.stringify({question:txt,lang:lang,session_id:sid})
    }).then(function(r){
      if(!r.ok)throw new Error('HTTP '+r.status);
      return r.json();
    }).then(function(d){
      typing.remove();
      if(d.session_id){sid=d.session_id;sessionStorage.setItem('_cw_sid',sid);}
      _addMsg(d.answer,'cw-b');
    }).catch(function(e){
      typing.remove();
      _addMsg('\u274c '+(e.message||'Error de conexi\u00f3n'),'cw-b');
    }).finally(function(){
      _setLoading(false);
      inp.focus();
    });
  };
  function _addMsg(txt,cls){
    var d=document.createElement('div');
    d.className=cls;d.textContent=txt;
    msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight;
    return d;
  }
  function _setLoading(on){inp.disabled=on;snd.disabled=on;}
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',_init);}
  else{_init();}
})();
</script>
<!-- ══════════════════════ FIN CHATBOT WIDGET ══════════════════════ -->
EOF_WIDGET

else
# ── Widget Desarrollo (flujo PDF-upload + chat dinámico) ─────────────────────
cat > chatbot_widget.html << 'EOF_WIDGET_DYN'
<!-- ═══════════════════════════════════════════════════════════════════
     CHATBOT WIDGET (Modo Dinámico) — Pega este bloque antes de </body>
═══════════════════════════════════════════════════════════════════ -->
<div id="_cw_btn" onclick="_cwToggle()" role="button" aria-label="Abrir/cerrar chatbot"><span>🤖 Asistente Virtual</span><span id="_cw_btn_icon">▲</span></div>
<div id="_cw_box" role="dialog" aria-label="Chatbot">
  <div id="_cw_hdr">
    <span>🤖 Asistente Virtual</span>
    <button id="_cw_close" onclick="_cwToggle()" aria-label="Cerrar">✕</button>
  </div>
  <div id="_cw_upload_area">
    <div id="_cw_drop" onclick="document.getElementById('_cw_file').click()">
      <div>📄</div><div>Sube tu PDF aquí</div>
      <div style="font-size:12px;color:#aaa;margin-top:4px">o haz clic para seleccionar</div>
      <input type="file" id="_cw_file" accept=".pdf" style="display:none">
    </div>
    <div id="_cw_uploading" style="display:none;text-align:center;padding:24px 16px;color:#888;font-style:italic;font-size:13px">
      ⏳ Procesando PDF… (30-60 segundos)
    </div>
  </div>
  <div id="_cw_chat_area" style="display:none;flex-direction:column;flex:1;overflow:hidden">
    <div id="_cw_msgs" role="log"></div>
    <div id="_cw_foot">
      <input id="_cw_inp" type="text" placeholder="Pregunta sobre el documento..." autocomplete="off"
             onkeypress="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();_cwSend();}">
      <button id="_cw_send" onclick="_cwSend()" aria-label="Enviar">➤</button>
    </div>
  </div>
</div>
<style>
  #_cw_btn{position:fixed;bottom:0;right:24px;width:240px;height:44px;background:#1F4E79;color:#fff;border-radius:12px 12px 0 0;display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:14px;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;cursor:pointer;box-shadow:0 -2px 12px rgba(0,0,0,.2);z-index:9998;user-select:none;border:none;transition:background .2s}
  #_cw_btn:hover{background:#1a3f62}
  #_cw_box{position:fixed;bottom:44px;right:24px;width:360px;background:#fff;border-radius:16px 16px 0 0;box-shadow:0 8px 32px rgba(0,0,0,.2);display:none;flex-direction:column;z-index:9999;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:14px}
  #_cw_hdr{background:#1F4E79;color:#fff;padding:13px 15px;display:flex;justify-content:space-between;align-items:center;font-weight:600;font-size:14px}
  #_cw_close{background:none;border:none;color:rgba(255,255,255,.8);font-size:18px;cursor:pointer;padding:0 2px;line-height:1;transition:color .2s}
  #_cw_close:hover{color:#fff}
  #_cw_upload_area{padding:20px}
  #_cw_drop{border:2px dashed #1F4E79;border-radius:12px;padding:28px 20px;text-align:center;cursor:pointer;transition:background .2s;font-size:15px;color:#555}
  #_cw_drop:hover{background:#f0f4f8}
  #_cw_drop div:first-child{font-size:38px;margin-bottom:8px}
  #_cw_msgs{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:9px;max-height:300px;scroll-behavior:smooth}
  .cw-b,.cw-u{max-width:84%;padding:9px 13px;border-radius:12px;word-wrap:break-word;line-height:1.5;white-space:pre-wrap}
  .cw-b{background:#f0f4f8;color:#2d3748;align-self:flex-start;border-bottom-left-radius:3px}
  .cw-u{background:#1F4E79;color:#fff;align-self:flex-end;border-bottom-right-radius:3px}
  .cw-typing{color:#aaa;font-style:italic;font-size:13px;align-self:flex-start;padding:6px 12px}
  #_cw_foot{padding:11px;border-top:1px solid #eee;display:flex;gap:8px;align-items:center}
  #_cw_inp{flex:1;padding:9px 13px;border:1px solid #ddd;border-radius:10px;font-size:14px;outline:none;transition:border-color .2s}
  #_cw_inp:focus{border-color:#1F4E79}
  #_cw_inp:disabled{background:#f5f5f5;cursor:not-allowed}
  #_cw_send{background:#1F4E79;color:#fff;border:none;padding:9px 14px;border-radius:10px;cursor:pointer;font-size:16px;line-height:1;transition:background .2s,opacity .2s}
  #_cw_send:hover:not(:disabled){background:#1a3f62}
  #_cw_send:disabled{opacity:.45;cursor:not-allowed}
  @media(max-width:420px){#_cw_box{width:calc(100vw - 16px);right:8px;bottom:44px}#_cw_btn{right:8px;width:calc(100vw - 16px)}}
</style>
<script>
(function(){
  var API="WILL_BE_API_URL";
  var KEY="WILL_BE_API_KEY";
  var sid="";
  var open=false;
  var box,msgs,inp,snd;
  function _init(){
    box=document.getElementById('_cw_box');
    msgs=document.getElementById('_cw_msgs');
    inp=document.getElementById('_cw_inp');
    snd=document.getElementById('_cw_send');
    var fi=document.getElementById('_cw_file');
    fi.addEventListener('change',function(e){if(e.target.files[0])_cwUpload(e.target.files[0]);});
    var drop=document.getElementById('_cw_drop');
    ['dragenter','dragover','dragleave','drop'].forEach(function(ev){
      drop.addEventListener(ev,function(e){e.preventDefault();e.stopPropagation();});
    });
    ['dragenter','dragover'].forEach(function(ev){drop.addEventListener(ev,function(){drop.style.background='#e8f0fe';});});
    ['dragleave','drop'].forEach(function(ev){drop.addEventListener(ev,function(){drop.style.background='';});});
    drop.addEventListener('drop',function(e){if(e.dataTransfer.files[0])_cwUpload(e.dataTransfer.files[0]);});
  }
  window._cwToggle=function(){
    if(!box){_init();}
    open=!open;
    box.style.display=open?'flex':'none';
    document.getElementById('_cw_btn_icon').textContent=open?'\u25BC':'\u25B2';
  };
  window._cwUpload=function(file){
    if(!file.name.toLowerCase().endsWith('.pdf')){alert('Solo se aceptan archivos PDF');return;}
    document.getElementById('_cw_drop').style.display='none';
    document.getElementById('_cw_uploading').style.display='block';
    var fd=new FormData();
    fd.append('pdf',file);fd.append('lang','es');
    fetch(API+'/upload',{method:'POST',headers:{'X-API-Key':KEY},body:fd})
    .then(function(r){if(!r.ok)throw new Error('HTTP '+r.status);return r.json();})
    .then(function(d){
      sid=d.session_id;
      document.getElementById('_cw_upload_area').style.display='none';
      var ca=document.getElementById('_cw_chat_area');
      ca.style.display='flex';
      _addMsg('Documento cargado \u2705 \u00bfQu\u00e9 quieres saber?','cw-b');
      inp.focus();
    })
    .catch(function(e){
      document.getElementById('_cw_drop').style.display='block';
      document.getElementById('_cw_uploading').style.display='none';
      alert('Error subiendo PDF: '+e.message);
    });
  };
  window._cwSend=function(){
    if(!box){_init();}
    var txt=inp.value.trim();
    if(!txt||snd.disabled)return;
    _addMsg(txt,'cw-u');
    inp.value='';
    _setLoading(true);
    var typing=_addMsg('Escribiendo\u2026','cw-typing');
    fetch(API+'/query',{
      method:'POST',
      headers:{'Content-Type':'application/json','X-API-Key':KEY},
      body:JSON.stringify({question:txt,lang:'es',session_id:sid})
    }).then(function(r){
      if(!r.ok)throw new Error('HTTP '+r.status);
      return r.json();
    }).then(function(d){
      typing.remove();
      _addMsg(d.answer,'cw-b');
    }).catch(function(e){
      typing.remove();
      _addMsg('\u274c '+(e.message||'Error de conexi\u00f3n'),'cw-b');
    }).finally(function(){_setLoading(false);inp.focus();});
  };
  function _addMsg(txt,cls){
    var d=document.createElement('div');
    d.className=cls;d.textContent=txt;
    msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight;
    return d;
  }
  function _setLoading(on){inp.disabled=on;snd.disabled=on;}
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',_init);}
  else{_init();}
})();
</script>
<!-- ══════════════════════ FIN CHATBOT WIDGET ══════════════════════ -->
EOF_WIDGET_DYN
fi

# Sustituir placeholders con valores reales
sed -i "s|WILL_BE_API_URL|$PUBLIC_API_URL|g" chatbot_widget.html
sed -i "s|WILL_BE_API_KEY|$CK|g" chatbot_widget.html

# Generar página de prueba
cat > chatbot_ejemplo.html << EOF_TEST
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Test — Chatbot IA Widget</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f7fa;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
    .card{background:#fff;padding:36px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,.1);max-width:500px;text-align:center}
    h2{color:#1F4E79;margin:0 0 10px}p{color:#666;line-height:1.6;margin:8px 0}
    .badge{background:#1F4E79;color:#fff;padding:6px 14px;border-radius:20px;font-size:13px;display:inline-block;margin:14px 0}
    .url{font-family:monospace;background:#f0f4f8;padding:8px 14px;border-radius:8px;font-size:12px;color:#555;word-break:break-all;margin-top:8px}
    small{display:block;margin-top:16px;color:#999;font-size:12px}
  </style>
</head>
<body>
  <div class="card">
    <h2>🤖 Chatbot IA</h2>
    <p>Pulsa el botón <strong>💬</strong> (esquina inferior derecha) para probar el widget.</p>
    <div class="badge">✅ Widget activo</div>
    <div class="url">API: $PUBLIC_API_URL</div>
    <small>Para embeber en tu web: copia <strong>chatbot_widget.html</strong> antes de &lt;/body&gt;</small>
  </div>
$(cat chatbot_widget.html)
</body>
</html>
EOF_TEST

_ok "chatbot_widget.html — snippet embebible generado"
_ok "chatbot_ejemplo.html — página de prueba generada"

# ═══════════════════════════════════════════════════════════════════════════
# 10. INICIAR SERVICIO
# ═══════════════════════════════════════════════════════════════════════════
_step "10. Iniciando el servicio"

sudo systemctl start chatbot 2>/dev/null || true
sleep 3

SERVICE_OK=0
if sudo systemctl is-active --quiet chatbot; then
    _ok "Servicio chatbot activo"
    SERVICE_OK=1
else
    _warn "El servicio no arrancó. Revisa: sudo journalctl -u chatbot -n 30"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 11. HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════════════
_step "11. Verificando que la API responde"

API_OK=0
if command -v curl &>/dev/null && [ "$SERVICE_OK" -eq 1 ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 "http://127.0.0.1:${SELECTED_PORT}/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        _ok "API respondiendo en http://127.0.0.1:${SELECTED_PORT}"
        API_OK=1
    else
        _warn "API devolvió HTTP $HTTP_CODE — revisa los logs:"
        _info "tail -f logs/api.log"
    fi
else
    _info "Comprueba manualmente: curl http://127.0.0.1:${SELECTED_PORT}/health"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 12. RESUMEN FINAL
# ═══════════════════════════════════════════════════════════════════════════
clear
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}    ✅   INSTALACIÓN COMPLETADA                    ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"

echo -e "\n${CYAN}${BOLD}ESTADO:${NC}"
[ "$SERVICE_OK" -eq 1 ] \
    && echo -e "  ${GREEN}🟢 Chatbot API:  en funcionamiento${NC}" \
    || echo -e "  ${RED}🔴 Chatbot API:  error al arrancar — sudo journalctl -u chatbot -n 30${NC}"
[ "$API_OK" -eq 1 ] \
    && echo -e "  ${GREEN}🟢 Health check: OK${NC}" \
    || echo -e "  ${YELLOW}🟡 Health check: no verificado${NC}"

echo -e "\n${CYAN}${BOLD}ACCESO:${NC}"
echo -e "  URL pública:  ${CYAN}$PUBLIC_API_URL${NC}"
echo -e "  URL local:    ${CYAN}http://127.0.0.1:$SELECTED_PORT${NC}"
echo -e "  API Key:      ${CYAN}$CK${NC}"

echo -e "\n${CYAN}${BOLD}ARCHIVOS GENERADOS:${NC}"
echo -e "  ${GREEN}chatbot_widget.html${NC}  ← código a embeber en cualquier web"
echo -e "  ${GREEN}chatbot_ejemplo.html${NC} ← página de prueba (ábrela en el navegador)"
[ "$BIND_HOST" = "127.0.0.1" ] && \
    echo -e "  ${GREEN}nginx_chatbot.conf${NC}   ← bloque nginx (si lo necesitas insertar manualmente)"

# ── Pendientes detectados automáticamente ────────────────────────────────────
PENDIENTE=0
if [ "$INSTALL_MODE" = "1" ] && [ "$FOUND_PDFS" -eq 0 ]; then
    PENDIENTE=1
    echo -e "\n${YELLOW}${BOLD}  ⚠️  PENDIENTE — Sin documentos PDF:${NC}"
    echo -e "  El chatbot no responderá hasta que proceses tus PDFs:"
    echo -e "  ${CYAN}./venv/bin/python3 src/process_manual.py --lang es --pdf data/manual_es.pdf${NC}"
    echo -e "  ${CYAN}sudo systemctl restart chatbot${NC}"
fi

if [ "$BIND_HOST" = "127.0.0.1" ] && [ "$NGINX_CONFIGURED" -eq 0 ]; then
    PENDIENTE=1
    echo -e "\n${YELLOW}${BOLD}  ⚠️  PENDIENTE — nginx no configurado:${NC}"
    echo -e "  El chatbot no será accesible desde internet hasta que configures nginx."
    echo -e "  Edita tu archivo de sitio nginx y añade el contenido de nginx_chatbot.conf:"
    echo -e "  ${CYAN}sudo nano /etc/nginx/sites-available/TU-SITIO${NC}"
    echo -e "  ${CYAN}  → Pega el contenido de nginx_chatbot.conf dentro del bloque server{}${NC}"
    echo -e "  ${CYAN}sudo nginx -t && sudo systemctl reload nginx${NC}"
fi

# ── Cómo embeber el widget ────────────────────────────────────────────────────
echo ""
_rule
echo -e "${CYAN}${BOLD}  CÓMO PONER EL CHATBOT EN TU WEB                ${NC}"
_rule
echo ""
echo -e "  Archivo a usar: ${GREEN}chatbot_widget.html${NC} (ya está en este directorio)"
echo -e "  Contiene el botón 💬 + panel de chat completo."
echo ""
echo -e "  ${BOLD}Pégalo justo antes de </body> en el template de tu web:${NC}"
echo ""
echo -e "  ${BLUE}▸ HTML estático${NC} (index.html, landing pages...)"
echo -e "    Abre tu HTML → copia el contenido de chatbot_widget.html → pega antes de </body>"
echo ""
echo -e "  ${BLUE}▸ PHP / WordPress${NC}"
echo -e "    En WordPress: ${CYAN}Apariencia → Editor de temas → footer.php${NC}"
echo -e "    Pega el contenido de chatbot_widget.html antes de </body>"
echo -e "    O añade en functions.php:"
echo -e "    ${CYAN}add_action('wp_footer', function(){ include 'chatbot_widget.html'; });${NC}"
echo ""
echo -e "  ${BLUE}▸ Laravel / Blade${NC}"
echo -e "    ${CYAN}cp chatbot_widget.html /ruta/tu-app/resources/views/partials/chatbot.blade.php${NC}"
echo -e "    Añade en tu layout antes de </body>: ${CYAN}@include('partials.chatbot')${NC}"
echo ""
echo -e "  ${BLUE}▸ Vue / React / Next.js${NC}"
echo -e "    Copia el CSS a tu hoja de estilos global."
echo -e "    Copia el HTML al componente raíz (App.vue, _app.tsx, layout.tsx...)."
echo -e "    Copia el <script> al final de ese mismo componente."
echo ""
echo -e "  ${BLUE}▸ Cualquier otro CMS / framework${NC}"
echo -e "    Busca el archivo donde está </body> → pega chatbot_widget.html antes."
echo ""
echo -e "  ${BOLD}Para probar antes de tocarlo en tu web:${NC}"
echo -e "    Sube ${CYAN}chatbot_ejemplo.html${NC} a tu servidor y ábrelo en el navegador."
echo -e "    Verás el botón 💬 en la esquina inferior derecha."

# ── Gestión del servicio ──────────────────────────────────────────────────────
echo ""
_rule
echo -e "${CYAN}${BOLD}  GESTIÓN DEL SERVICIO                            ${NC}"
_rule
echo ""
echo -e "  Estado:    ${CYAN}sudo systemctl status chatbot${NC}"
echo -e "  Logs:      ${CYAN}tail -f logs/api.log${NC}"
echo -e "  Reiniciar: ${CYAN}sudo systemctl restart chatbot${NC}"
echo -e "  Parar:     ${CYAN}sudo systemctl stop chatbot${NC}"

echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"
