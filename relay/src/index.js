// flashdeck-relay — lets the web import page pull a Quizlet set by link.
//
// Quizlet captchas every datacenter IP and every non-browser TLS handshake
// (Workers, GCP, curl, reader proxies all get the challenge). A home
// connection with a browser-grade TLS fingerprint gets straight through, so
// the fetching happens on the Mac (tools/quizlet_agent.py), which keeps a
// websocket open to this Worker. The page POSTs a link here, the Durable
// Object hands it to the Mac and returns the cards.

const ORIGINS = ['https://assiamahs.github.io', 'http://localhost:8931', 'http://127.0.0.1:8931'];
const TIMEOUT_MS = 45000;

function cors(req) {
  const origin = req.headers.get('Origin') || '';
  return {
    'Access-Control-Allow-Origin': ORIGINS.includes(origin) ? origin : ORIGINS[0],
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    Vary: 'Origin',
  };
}

const json = (req, body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors(req) } });

// https://quizlet.com/220018802/greetings-flash-cards/ → "220018802"
function setId(link) {
  try {
    const u = new URL(String(link).trim());
    if (!/(^|\.)quizlet\.com$/i.test(u.hostname)) return null;
    const m = u.pathname.match(/\/(\d{4,})(\/|$)/) || u.search.match(/[?&](?:setId|id)=(\d{4,})/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: cors(req) });
    const hub = env.HUB.get(env.HUB.idFromName('mac'));
    const { pathname } = new URL(req.url);

    if (pathname === '/agent') {
      if (new URL(req.url).searchParams.get('key') !== env.AGENT_KEY) return new Response('forbidden', { status: 403 });
      return hub.fetch(req);
    }
    if (pathname === '/health') {
      const r = await hub.fetch('https://hub/health');
      return json(req, await r.json());
    }
    if (pathname === '/import' && req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      const id = setId(body.url);
      if (!id) return json(req, { error: 'That doesn’t look like a Quizlet set link (quizlet.com/<number>/…).' }, 400);
      const r = await hub.fetch('https://hub/ask', { method: 'POST', body: JSON.stringify({ op: 'fetch', setId: id }) });
      return json(req, await r.json(), r.status);
    }
    if (pathname === '/save' && req.method === 'POST') {
      // no token on the web: the Mac re-fetches the set itself and commits with its own
      // GitHub login, so this can only ever write real Quizlet content, never posted text
      const body = await req.json().catch(() => ({}));
      const id = setId(body.url);
      const name = String(body.name || '').trim().slice(0, 80);
      const drop = Array.isArray(body.drop) ? body.drop.filter(Number.isInteger).slice(0, 5000) : [];
      if (!id) return json(req, { error: 'That doesn’t look like a Quizlet set link.' }, 400);
      if (!name) return json(req, { error: 'Give the deck a name.' }, 400);
      const r = await hub.fetch('https://hub/ask', { method: 'POST', body: JSON.stringify({ op: 'save', setId: id, name, drop }) });
      return json(req, await r.json(), r.status);
    }
    return json(req, { error: 'not found' }, 404);
  },
};

export class Hub {
  constructor(ctx) {
    this.ctx = ctx;
    this.pending = new Map();
    // keepalive pings from the Mac never wake the object
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  agent() {
    return this.ctx.getWebSockets('agent').at(-1);
  }

  async fetch(req) {
    const { pathname } = new URL(req.url);
    if (pathname === '/agent') {
      // one Mac at a time: a reconnect replaces the old socket
      for (const old of this.ctx.getWebSockets('agent')) old.close(1000, 'replaced');
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server, ['agent']);
      return new Response(null, { status: 101, webSocket: client });
    }
    if (pathname === '/health') return Response.json({ mac: !!this.agent() });
    if (pathname === '/ask') {
      const ws = this.agent();
      if (!ws) return Response.json({ error: 'mac-offline' }, { status: 503 });
      const ask = await req.json();
      const rid = crypto.randomUUID();
      const result = await new Promise(resolve => {
        const timer = setTimeout(() => { this.pending.delete(rid); resolve({ error: 'The Mac didn’t answer in time — try again.' }); }, TIMEOUT_MS);
        this.pending.set(rid, r => { clearTimeout(timer); resolve(r); });
        ws.send(JSON.stringify({ rid, ...ask }));
      });
      return Response.json(result, { status: result.error ? 502 : 200 });
    }
    return new Response('not found', { status: 404 });
  }

  webSocketMessage(ws, message) {
    let msg;
    try { msg = JSON.parse(message); } catch { return; }
    const done = this.pending.get(msg.rid);
    if (!done) return;
    this.pending.delete(msg.rid);
    delete msg.rid;
    done(msg);
  }

  webSocketClose(ws, code) {
    try { ws.close(code === 1005 ? 1000 : code, 'bye'); } catch {}
  }
}
