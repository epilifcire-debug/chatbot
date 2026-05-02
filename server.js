const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: 'https://epilifcire-debug.github.io',
    methods: ['GET', 'POST'],
    credentials: true
  }
});

app.use(cors({
  origin: 'https://epilifcire-debug.github.io',
  methods: ['GET', 'POST'],
  credentials: true
}));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ─── Fluxo ───────────────────────────────────────────────────
let flow = JSON.parse(fs.readFileSync('./flow.json', 'utf8'));
let flowEnabled = true; // ← toggle ativar/desativar

app.get('/api/flow', (req, res) => res.json(flow));
app.post('/api/flow', (req, res) => {
  flow = req.body;
  fs.writeFileSync('./flow.json', JSON.stringify(flow, null, 2));
  res.json({ ok: true });
});

// Toggle ativar/desativar fluxo
app.get('/api/flow/status', (req, res) => res.json({ enabled: flowEnabled }));
app.post('/api/flow/toggle', (req, res) => {
  flowEnabled = !flowEnabled;
  io.emit('flow_status', { enabled: flowEnabled });
  res.json({ enabled: flowEnabled });
});

// ─── Estado ──────────────────────────────────────────────────
const sessions = {};
const contacts = {};
const messages = {};
let botStatus = 'desconectado';
let lastQR = null;

// ─── Detectar Chrome ─────────────────────────────────────────
function findChrome() {
  const candidates = [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    process.env.LOCALAPPDATA + '\\Google\\Chrome\\Application\\chrome.exe',
    '/usr/bin/google-chrome','/usr/bin/google-chrome-stable',
    '/usr/bin/chromium-browser','/usr/bin/chromium','/snap/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  try {
    const pp = require('puppeteer');
    const ep = pp.executablePath?.();
    if (ep && fs.existsSync(ep)) return ep;
  } catch {}
  for (const p of candidates) {
    if (p && fs.existsSync(p)) { console.log('🌐 Chrome:', p); return p; }
  }
  return null;
}

const chromePath = findChrome();
const puppeteerArgs = {
  headless: true,
  args: ['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage',
         '--disable-gpu','--no-first-run','--no-zygote','--single-process','--disable-extensions'],
};
if (chromePath) puppeteerArgs.executablePath = chromePath;

const client = new Client({
  authStrategy: new LocalAuth({ dataPath: './.wwebjs_auth' }),
  puppeteer: puppeteerArgs,
  webVersionCache: {
    type: 'remote',
    remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.2412.54.html',
  },
});

client.on('qr', async (qr) => {
  console.log('📱 QR Code!');
  botStatus = 'aguardando_qr';
  try { lastQR = await qrcode.toDataURL(qr); io.emit('qr', lastQR); io.emit('status', botStatus); } catch {}
});
client.on('authenticated', () => { lastQR = null; botStatus = 'autenticado'; io.emit('status', botStatus); });
client.on('ready', async () => {
  botStatus = 'conectado'; lastQR = null;
  io.emit('status', botStatus); io.emit('qr', null);
  console.log('✅ WhatsApp conectado!');
  await loadAllChats();
});
client.on('auth_failure', () => { botStatus = 'erro_auth'; io.emit('status', botStatus); });
client.on('disconnected', (r) => { botStatus = 'desconectado'; io.emit('status', botStatus); console.log('❌ Desconectado:', r); });
process.on('unhandledRejection', (err) => console.error('⚠️', err?.message || err));

// ─── Foto de perfil (com cache) ───────────────────────────────
const photoCache = {};
async function getContactPhoto(number) {
  if (photoCache[number]) return photoCache[number];
  try {
    const url = await client.getProfilePicUrl(number);
    if (url) { photoCache[number] = url; return url; }
  } catch {}
  return null;
}

// ─── Carregar chats ───────────────────────────────────────────
async function loadAllChats() {
  console.log('📂 Carregando chats...');
  try {
    const chats = await client.getChats();
    const privados = chats.filter(c => !c.isGroup);

    for (const chat of privados) {
      const number = chat.id._serialized;
      const photo = await getContactPhoto(number);
      contacts[number] = {
        name: chat.name || number,
        number,
        photo: photo || null,
        unread: chat.unreadCount || 0,
        lastMsg: chat.lastMessage?.body || '',
        lastTime: chat.lastMessage?.timestamp
          ? new Date(chat.lastMessage.timestamp * 1000).toISOString() : null,
      };
    }

    io.emit('contacts', sortContacts());
    console.log(`✅ ${Object.keys(contacts).length} contatos`);

    for (const chat of privados) {
      const number = chat.id._serialized;
      try {
        const msgs = await chat.fetchMessages({ limit: 30 });
        messages[number] = msgs.filter(m => m.body).map(m => ({
          from: m.fromMe ? 'bot' : 'user',
          text: m.body,
          time: new Date(m.timestamp * 1000).toISOString(),
        }));
      } catch { messages[number] = []; }
    }
    console.log('📬 Histórico carregado');
  } catch (err) { console.error('Erro:', err.message); }
}

function sortContacts() {
  return Object.values(contacts).sort((a, b) => (b.lastTime || '').localeCompare(a.lastTime || ''));
}

// ─── Mensagens recebidas ──────────────────────────────────────
client.on('message', async (msg) => {
  if (msg.isGroupMsg || msg.from === 'status@broadcast') return;
  const number = msg.from;
  const text = msg.body.trim();
  const contact = await msg.getContact();
  const name = contact.pushname || contact.name || number;

  // Foto na primeira mensagem
  if (!contacts[number]?.photo) {
    const photo = await getContactPhoto(number);
    if (!contacts[number]) contacts[number] = { name, number, unread: 0, photo: photo || null };
    else contacts[number].photo = photo || null;
  }

  if (!contacts[number]) contacts[number] = { name, number, unread: 0, photo: null };
  contacts[number].name = name;
  contacts[number].lastMsg = text;
  contacts[number].unread = (contacts[number].unread || 0) + 1;
  contacts[number].lastTime = new Date().toISOString();

  if (!messages[number]) messages[number] = [];
  messages[number].push({ from: 'user', text, time: new Date().toISOString() });

  io.emit('contacts', sortContacts());
  io.emit('message', { number, from: 'user', text, time: new Date().toISOString() });
  console.log(`📨 [${name}] ${text}`);

  // Só processa o fluxo se estiver ativado
  if (!flowEnabled) return;

  if (!sessions[number]) sessions[number] = { node: flow.startNode, vars: {} };
  await processFlow(number, text, msg);
});

// ─── Motor do Fluxo ──────────────────────────────────────────
async function processFlow(number, userText, msg) {
  const session = sessions[number];
  let node = flow.nodes[session.node];
  if (!node) { session.node = flow.startNode; node = flow.nodes[flow.startNode]; }

  if (node.type === 'choice') {
    const key = userText.toLowerCase().trim();
    const nextId = node.options[key] || node.options[userText] || null;
    if (nextId) { session.node = nextId; await executeNode(number, nextId, msg); }
    else if (node.fallback) { session.node = node.fallback; await executeNode(number, node.fallback, msg); }
    return;
  }
  if (node.type === 'capture') {
    session.vars[node.saveAs] = userText;
    session.node = node.next;
    await executeNode(number, node.next, msg);
    return;
  }
  session.node = flow.startNode;
  await executeNode(number, flow.startNode, msg);
}

async function executeNode(number, nodeId, msg) {
  const session = sessions[number];
  const node = flow.nodes[nodeId];
  if (!node) return;

  let text = (node.text || '').replace(/\{(\w+)\}/g, (_, k) => {
    if (k === 'timestamp') return `SUP${Date.now().toString().slice(-6)}`;
    return session.vars[k] || `{${k}}`;
  });

  if (text) {
    await msg.reply(text);
    if (!messages[number]) messages[number] = [];
    messages[number].push({ from: 'bot', text, time: new Date().toISOString() });
    io.emit('message', { number, from: 'bot', text, time: new Date().toISOString() });
  }

  session.node = nodeId;

  if ((node.type === 'message' || node.type === 'action') && node.next) {
    const next = flow.nodes[node.next];
    if (next) {
      if (next.type === 'end' && next.text) {
        session.node = node.next;
        setTimeout(async () => {
          await msg.reply(next.text);
          messages[number].push({ from: 'bot', text: next.text, time: new Date().toISOString() });
          io.emit('message', { number, from: 'bot', text: next.text, time: new Date().toISOString() });
          delete sessions[number];
        }, 1000);
      } else if (next.type !== 'end') {
        setTimeout(() => executeNode(number, node.next, msg), 500);
      }
    }
  }
  if (node.type === 'end') delete sessions[number];
}

// ─── API REST ─────────────────────────────────────────────────
app.get('/api/status',   (req, res) => res.json({ status: botStatus }));
app.get('/api/contacts', (req, res) => res.json(sortContacts()));
app.get('/api/messages/:number', (req, res) => res.json(messages[req.params.number] || []));
app.get('/api/contact/:number/photo', async (req, res) => {
  const photo = await getContactPhoto(req.params.number);
  res.json({ photo });
});

app.post('/api/send', async (req, res) => {
  const { number, text } = req.body;
  try {
    await client.sendMessage(number, text);
    if (!messages[number]) messages[number] = [];
    messages[number].push({ from: 'bot', text, time: new Date().toISOString() });
    io.emit('message', { number, from: 'bot', text, time: new Date().toISOString() });
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/reset-session/:number', (req, res) => {
  delete sessions[req.params.number];
  res.json({ ok: true });
});

app.post('/api/reload-chats', async (req, res) => {
  res.json({ ok: true });
  await loadAllChats();
});

// ─── Socket.io ───────────────────────────────────────────────
io.on('connection', (socket) => {
  console.log('🌐 Dashboard conectado');
  socket.emit('status', botStatus);
  socket.emit('contacts', sortContacts());
  socket.emit('flow_status', { enabled: flowEnabled });
  if (lastQR && botStatus === 'aguardando_qr') socket.emit('qr', lastQR);

  socket.on('get_messages', (number) => {
    socket.emit('history', { number, msgs: messages[number] || [] });
  });
  socket.on('reload_chats', async () => {
    if (botStatus === 'conectado') await loadAllChats();
  });
});

// ─── Start ───────────────────────────────────────────────────
const PORT = 3000;
server.listen(PORT, () => {
  console.log(`\n🚀 Dashboard em http://localhost:${PORT}`);
  console.log('⏳ Iniciando WhatsApp...\n');
  client.initialize().catch(err => {
    console.error('\n❌ ERRO:', err.message);
  });
});
