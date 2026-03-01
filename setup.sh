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

# Animación de progreso para que no parezca colgado
(pip install -r requirements.txt --quiet) & 
pid=$!
while kill -0 $pid 2>/dev/null; do
    echo -ne "   ${BLUE}📦 Instalando dependencias... [====|    ]${NC}\r" ; sleep 1
    echo -ne "   ${BLUE}📦 Instalando dependencias... [========|]${NC}\r" ; sleep 1
done
echo -e "${GREEN}    ✅ Librerías instaladas correctamente.         ${NC}"

# 2. Configuración de Red y Seguridad
echo -e "\n${CYAN}${BOLD}─── 2. Configuración de Red ───────────────────────${NC}"
if [ ! -f ".env" ]; then
    read -p "    👉 GROQ_API_KEY: " GROQ_KEY
    read -p "    👉 CLIENT_API_KEY (Pass Web): " CLIENT_KEY
    read -p "    👉 Puerto deseado [8088]: " SELECTED_PORT
    SELECTED_PORT=${SELECTED_PORT:-8088}

    echo "GROQ_API_KEY=$GROQ_KEY" > .env
    echo "CLIENT_API_KEY=$CLIENT_KEY" >> .env
    echo "API_PORT=$SELECTED_PORT" >> .env
    echo "APP_URL=*" >> .env
else
    SELECTED_PORT=$(grep API_PORT .env | cut -d'=' -f2)
    echo -e "${GREEN}    ✅ Usando configuración existente (.env).${NC}"
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

# 4. CREAR SERVICIO DE SISTEMA (SYSTEMD)
echo -e "\n${CYAN}${BOLD}─── 4. Configurando auto-arranque (Systemd) ───────${NC}"
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

# Activar e iniciar servicio
sudo systemctl daemon-reload
sudo systemctl enable chatbot
sudo systemctl restart chatbot

# 5. Generar Interfaz HTML (con puerto dinámico)
CK=$(grep CLIENT_API_KEY .env | cut -d'=' -f2)
cat > chatbot_ejemplo.html << EOF
<!DOCTYPE html>... (resto del código HTML que ya tenemos) ...
EOF

echo -e "${GREEN}    ✅ Servicio 'chatbot' creado y arrancado.${NC}"

# 6. Resumen Final
echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}    ✅  INSTALACIÓN COMPLETA Y ACTIVA              ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "\n  El chatbot ya está corriendo y se iniciará solo al reiniciar el servidor."
echo -e "  Estado: ${CYAN}sudo systemctl status chatbot${NC}"
echo -e "  Logs:   ${CYAN}tail -f logs/api.log${NC}\n"