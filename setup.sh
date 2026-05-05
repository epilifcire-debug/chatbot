#!/bin/bash

# ═══════════════════════════════════════════════════════════════
#  FlowBot — Script de instalação automática
#  Oracle Cloud Ubuntu 22.04
#  Uso: bash setup.sh
# ═══════════════════════════════════════════════════════════════

set -e  # Para se algum comando falhar

# ── Cores ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sem cor

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }
step() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}"
echo "  ███████╗██╗      ██████╗ ██╗    ██╗██████╗  ██████╗ ████████╗"
echo "  ██╔════╝██║     ██╔═══██╗██║    ██║██╔══██╗██╔═══██╗╚══██╔══╝"
echo "  █████╗  ██║     ██║   ██║██║ █╗ ██║██████╔╝██║   ██║   ██║   "
echo "  ██╔══╝  ██║     ██║   ██║██║███╗██║██╔══██╗██║   ██║   ██║   "
echo "  ██║     ███████╗╚██████╔╝╚███╔███╔╝██████╔╝╚██████╔╝   ██║   "
echo "  ╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═════╝  ╚═════╝   ╚═╝   "
echo -e "${NC}"
echo -e "${YELLOW}  Instalação automática — Oracle Cloud Ubuntu 22.04${NC}"
echo ""
sleep 1

# ═══════════════════════════════════════════════════════════════
step "1/7 — Atualizando o sistema"
# ═══════════════════════════════════════════════════════════════
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
ok "Sistema atualizado"

# ═══════════════════════════════════════════════════════════════
step "2/7 — Instalando Node.js 20 LTS"
# ═══════════════════════════════════════════════════════════════
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -qq
sudo apt-get install -y nodejs -qq
NODE_VER=$(node --version)
ok "Node.js instalado: $NODE_VER"

# ═══════════════════════════════════════════════════════════════
step "3/7 — Instalando Chromium e dependências do Puppeteer"
# ═══════════════════════════════════════════════════════════════
sudo apt-get install -y -qq \
  chromium-browser \
  libgbm-dev \
  libxkbcommon-dev \
  libglib2.0-0 \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libdrm2 \
  libxcomposite1 \
  libxdamage1 \
  libxfixes3 \
  libxrandr2 \
  libxss1 \
  libxtst6 \
  ca-certificates \
  fonts-liberation \
  libappindicator3-1 \
  xdg-utils \
  wget \
  unzip

CHROME_PATH=$(which chromium-browser 2>/dev/null || which chromium 2>/dev/null || echo "")
if [ -z "$CHROME_PATH" ]; then
  warn "chromium-browser não encontrado no PATH padrão, tentando localizar..."
  CHROME_PATH=$(find /usr -name "chromium*" -type f 2>/dev/null | head -1)
fi
ok "Chromium instalado: $CHROME_PATH"

# ═══════════════════════════════════════════════════════════════
step "4/7 — Instalando PM2 (gerenciador de processos)"
# ═══════════════════════════════════════════════════════════════
sudo npm install -g pm2 -q
pm2 --version > /dev/null
ok "PM2 instalado"

# ═══════════════════════════════════════════════════════════════
step "5/7 — Instalando cloudflared"
# ═══════════════════════════════════════════════════════════════
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
rm /tmp/cloudflared.deb
ok "cloudflared instalado: $(cloudflared --version 2>&1 | head -1)"

# ═══════════════════════════════════════════════════════════════
step "6/7 — Criando estrutura do projeto"
# ═══════════════════════════════════════════════════════════════
mkdir -p ~/chatbot/public
cd ~/chatbot

# ── package.json ────────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "flowbot",
  "version": "1.0.0",
  "description": "FlowBot — Autoatendimento WhatsApp",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.6.1",
    "whatsapp-web.js": "^1.23.0",
    "qrcode": "^1.5.3",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

# ── flow.json básico (se não existir) ────────────────────────
if [ ! -f flow.json ]; then
cat > flow.json << 'EOF'
{
  "startNode": "start",
  "nodes": {
    "start": {
      "type": "start",
      "next": "menu",
      "x": 60, "y": 60, "w": 200
    },
    "menu": {
      "type": "message",
      "text": "Olá! 👋 Como posso te ajudar?\n\n1 - Informações\n2 - Falar com atendente",
      "next": "opcoes",
      "x": 320, "y": 60, "w": 200
    },
    "opcoes": {
      "type": "choice",
      "text": "Escolha uma opção:",
      "options": { "1": "info", "2": "atendente" },
      "fallback": "fallback",
      "x": 580, "y": 60, "w": 200
    },
    "info": {
      "type": "message",
      "text": "ℹ️ Aqui estão nossas informações!\n\nEdite este texto no editor de fluxo.",
      "next": "fim",
      "x": 840, "y": 20, "w": 200
    },
    "atendente": {
      "type": "end",
      "text": "👩‍💼 Transferindo para um atendente. Aguarde!",
      "x": 840, "y": 180, "w": 200
    },
    "fallback": {
      "type": "message",
      "text": "🤔 Não entendi. Por favor, digite 1 ou 2.",
      "next": "opcoes",
      "x": 840, "y": 340, "w": 200
    },
    "fim": {
      "type": "end",
      "text": "✅ Obrigado pelo contato! Até logo 👋",
      "x": 1100, "y": 20, "w": 200
    }
  }
}
EOF
  info "flow.json básico criado — você pode importar o seu depois"
else
  ok "flow.json já existe, mantido"
fi

# ── Instalar dependências npm ────────────────────────────────
info "Instalando dependências npm (pode demorar 2-3 min)..."
npm install --quiet
ok "Dependências instaladas"

# ═══════════════════════════════════════════════════════════════
step "7/7 — Configurando firewall e scripts de controle"
# ═══════════════════════════════════════════════════════════════

# Liberar porta 3000 no iptables
sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true

# Instalar iptables-persistent silenciosamente
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get install -y -qq iptables-persistent
sudo netfilter-persistent save 2>/dev/null || true
ok "Porta 3000 liberada no firewall"

# ── Script de start (bot + túnel) ───────────────────────────
cat > ~/start-bot.sh << 'STARTEOF'
#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}🤖 Iniciando FlowBot...${NC}"
cd ~/chatbot

# Para processos anteriores
pm2 delete flowbot   2>/dev/null || true
pm2 delete tunnel    2>/dev/null || true

# Inicia o servidor
pm2 start server.js --name flowbot \
  --log ~/chatbot/logs/bot.log \
  --error ~/chatbot/logs/bot-error.log \
  --time

echo -e "${GREEN}✅ Servidor iniciado!${NC}"
echo ""
echo -e "${YELLOW}Aguardando 3s para iniciar o túnel...${NC}"
sleep 3

# Inicia o túnel Cloudflare
TUNNEL_ID="4aceb63c-5e49-453e-9a2a-fc0c6e2dcf8b"
pm2 start "cloudflared tunnel --url http://localhost:3000" \
  --name tunnel \
  --log ~/chatbot/logs/tunnel.log \
  --error ~/chatbot/logs/tunnel-error.log \
  --time

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  FlowBot rodando!${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  📋 Ver logs do bot:    ${CYAN}pm2 logs flowbot${NC}"
echo -e "  🌐 Ver URL do túnel:   ${CYAN}pm2 logs tunnel${NC}"
echo -e "  🛑 Parar tudo:         ${CYAN}bash ~/stop-bot.sh${NC}"
echo ""
echo -e "${YELLOW}  👆 A URL do túnel aparece nos logs do tunnel${NC}"
echo -e "${YELLOW}     Cole essa URL no dashboard do GitHub Pages${NC}"
echo ""
STARTEOF
chmod +x ~/start-bot.sh

# ── Script de stop ───────────────────────────────────────────
cat > ~/stop-bot.sh << 'STOPEOF'
#!/bin/bash
echo "🛑 Parando FlowBot..."
pm2 delete flowbot 2>/dev/null || true
pm2 delete tunnel  2>/dev/null || true
echo "✅ Parado!"
STOPEOF
chmod +x ~/stop-bot.sh

# ── Script de status ─────────────────────────────────────────
cat > ~/status-bot.sh << 'STATUSEOF'
#!/bin/bash
echo "📊 Status do FlowBot:"
pm2 list
echo ""
echo "🌐 URL do túnel (últimas linhas do log):"
pm2 logs tunnel --lines 5 --nostream 2>/dev/null || echo "  Túnel não está rodando"
STATUSEOF
chmod +x ~/status-bot.sh

# ── Criar pasta de logs ──────────────────────────────────────
mkdir -p ~/chatbot/logs

# ── PM2 iniciar no boot ──────────────────────────────────────
pm2 startup | tail -1 | bash 2>/dev/null || true
ok "PM2 configurado para iniciar no boot"

# ═══════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ INSTALAÇÃO CONCLUÍDA!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📁 Projeto em:   ${CYAN}~/chatbot/${NC}"
echo ""
echo -e "${YELLOW}  PRÓXIMOS PASSOS:${NC}"
echo ""
echo -e "  1️⃣  Envie seus arquivos para a VM:"
echo -e "     ${CYAN}scp server.js flow.json ubuntu@163.176.251.224:~/chatbot/${NC}"
echo -e "     ${CYAN}scp public/index.html ubuntu@163.176.251.224:~/chatbot/public/${NC}"
echo ""
echo -e "  2️⃣  Inicie o bot + túnel:"
echo -e "     ${CYAN}bash ~/start-bot.sh${NC}"
echo ""
echo -e "  3️⃣  Veja a URL do túnel nos logs:"
echo -e "     ${CYAN}pm2 logs tunnel${NC}"
echo ""
echo -e "  4️⃣  Cole a URL no dashboard:"
echo -e "     ${CYAN}https://epilifcire-debug.github.io/chatbot/${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
