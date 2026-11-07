// Claude connector (MCP over streamable HTTP, stateless JSON) — add decks from any Claude chat,
// Mac on or off. URL = https://<relay>/mcp/<MCP_KEY>; the key in the path is the only auth,
// so treat the URL like a password. Writes go straight to decks.json with GITHUB_TOKEN.

const REPO = 'AssiamahS/flashdeck';
const API = `https://api.github.com/repos/${REPO}/contents/decks.json`;
const gh = (env, accept, init = {}) => fetch(API + (init.method ? '' : '?ref=main'), {
  ...init,
  headers: { Authorization: `Bearer ${env.GITHUB_TOKEN}`, Accept: accept, 'User-Agent': 'flashdeck-relay', ...(init.headers || {}) },
});

// Same rule as Deck.slug in the apps and tools/quizlet_agent.py
const slug = name => [...name.toLowerCase().replaceAll(' ', '-')].filter(c => /[\p{L}\p{N}-]/u.test(c)).join('');

function b64(text) {
  const bytes = new TextEncoder().encode(text);
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

// decks.json is >1 MB, so the contents API omits `content`: sha from the JSON form, body from raw.
async function load(env) {
  const [meta, raw] = await Promise.all([gh(env, 'application/vnd.github+json'), gh(env, 'application/vnd.github.raw')]);
  if (!meta.ok || !raw.ok) throw new Error(`GitHub read failed (${meta.status}/${raw.status})`);
  return { sha: (await meta.json()).sha, data: await raw.json() };
}

async function commit(env, mutate) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { sha, data } = await load(env);
    const { message, result } = mutate(data);
    if (!message) return result;
    const r = await gh(env, 'application/vnd.github+json', {
      method: 'PUT',
      body: JSON.stringify({ message, branch: 'main', sha, content: b64(JSON.stringify(data, null, 2) + '\n') }),
    });
    if (r.ok) return result;
    if (r.status !== 409 && r.status !== 422) throw new Error(`GitHub write failed (${r.status}): ${(await r.text()).slice(0, 200)}`);
  }
  throw new Error('decks.json kept changing — try again.');
}

const clean = c => {
  const card = { front: String(c.front ?? '').trim(), back: String(c.back ?? '').trim() };
  if (c.why) card.why = String(c.why).trim();
  return card;
};

function addCards(env, { deck, cards }) {
  const name = String(deck ?? '').trim().slice(0, 80);
  const fresh = (Array.isArray(cards) ? cards : []).map(clean).filter(c => c.front && c.back);
  if (!name) throw new Error('deck is required');
  if (!fresh.length) throw new Error('cards must be a non-empty list of {front, back}');
  return commit(env, data => {
    const id = slug(name);
    const existing = data.decks.find(d => d.id === id || d.name.toLowerCase() === name.toLowerCase());
    if (!existing) {
      data.decks.push({ id, name, cards: fresh });
      return { message: `feat: add deck ${id} (${fresh.length} cards) from claude connector`, result: `Created deck "${name}" (id ${id}) with ${fresh.length} cards.` };
    }
    const have = new Set(existing.cards.map(c => c.front));
    const add = fresh.filter(c => !have.has(c.front));
    if (!add.length) return { result: `All ${fresh.length} cards are already in "${existing.name}".` };
    existing.cards.push(...add);
    return { message: `feat: add ${add.length} cards to ${existing.id} from claude connector`, result: `Added ${add.length} cards to "${existing.name}" (${fresh.length - add.length} duplicates skipped).` };
  });
}

async function listDecks(env) {
  const { data } = await load(env);
  return data.decks.map(d => `${d.id} — ${d.name} (${d.cards.length} cards)`).join('\n');
}

async function getDeck(env, { deck }) {
  const { data } = await load(env);
  const d = data.decks.find(x => x.id === deck || x.name.toLowerCase() === String(deck).toLowerCase());
  if (!d) throw new Error(`No deck "${deck}". Use list_decks.`);
  return JSON.stringify({ id: d.id, name: d.name, cards: d.cards.slice(0, 300).map(c => ({ front: c.front, back: c.back })) }, null, 1);
}

const WIDGET = 'Home-screen widget rule: it only shows single-answer multiple-choice cards whose front is a question (<=200 chars) followed by lines "A. ...", "B. ...", "C. ...", "D. ..." (each option <=45 chars) and whose back is the correct line, e.g. "B. Value and urgency". Optional "why" = 1-2 sentence explanation. Vary which letter is correct.';

const TOOLS = [
  { name: 'list_decks', description: 'List every Flash Deck deck (id, name, card count).', inputSchema: { type: 'object', properties: {} } },
  { name: 'get_deck', description: 'Read a deck\'s cards (first 300) by id or name.', inputSchema: { type: 'object', properties: { deck: { type: 'string' } }, required: ['deck'] } },
  {
    name: 'add_cards',
    description: `Create a Flash Deck deck or append cards to an existing one (matched by name or id; duplicate fronts skipped). Saves to GitHub; the iPhone app, widget, watch, Mac app and web pick it up within a minute. Use this for cards the user pastes, screenshots, or asks you to write. ${WIDGET}`,
    inputSchema: {
      type: 'object',
      properties: {
        deck: { type: 'string', description: 'Deck name, e.g. "Verizon Sales Quiz"' },
        cards: { type: 'array', items: { type: 'object', properties: { front: { type: 'string' }, back: { type: 'string' }, why: { type: 'string' } }, required: ['front', 'back'] } },
      },
      required: ['deck', 'cards'],
    },
  },
  {
    name: 'import_quizlet',
    description: 'Import a Quizlet set by link into a deck. Quizlet blocks servers, so this goes through the user\'s Mac; if it returns mac-offline, ask the user to paste the cards\' text or screenshots and save them with add_cards instead.',
    inputSchema: { type: 'object', properties: { url: { type: 'string' }, name: { type: 'string', description: 'Deck name (defaults to the set title)' } }, required: ['url'] },
  },
];

export async function mcp(req, env, { hub, setId }) {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405, headers: { Allow: 'POST' } });
  const msg = await req.json().catch(() => null);
  if (!msg || Array.isArray(msg)) return Response.json({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }, { status: 400 });
  if (msg.id === undefined) return new Response(null, { status: 202 }); // notifications
  const reply = result => Response.json({ jsonrpc: '2.0', id: msg.id, result });
  const text = (t, isError = false) => reply({ content: [{ type: 'text', text: t }], isError });

  switch (msg.method) {
    case 'initialize':
      return reply({
        protocolVersion: msg.params?.protocolVersion || '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'flashdeck', version: '1.0.0' },
        instructions: `Flash Deck = the user's flashcard app (iPhone, home-screen widget, watch, Mac, Echo Show). Add decks with add_cards or import_quizlet. ${WIDGET}`,
      });
    case 'ping':
      return reply({});
    case 'tools/list':
      return reply({ tools: TOOLS });
    case 'tools/call': {
      const { name, arguments: args = {} } = msg.params || {};
      try {
        if (name === 'list_decks') return text(await listDecks(env));
        if (name === 'get_deck') return text(await getDeck(env, args));
        if (name === 'add_cards') return text(await addCards(env, args));
        if (name === 'import_quizlet') {
          const id = setId(args.url);
          if (!id) return text('That isn\'t a Quizlet set link (quizlet.com/<number>/...).', true);
          const got = await (await hub.fetch('https://hub/ask', { method: 'POST', body: JSON.stringify({ op: 'fetch', setId: id }) })).json();
          if (got.error) return text(got.error === 'mac-offline'
            ? 'mac-offline: the Mac that fetches Quizlet is off. Ask the user to paste the set\'s text or screenshots, then save with add_cards.'
            : `Quizlet fetch failed: ${got.error}`, true);
          return text(await addCards(env, { deck: args.name || got.title, cards: got.cards }));
        }
        return Response.json({ jsonrpc: '2.0', id: msg.id, error: { code: -32602, message: `Unknown tool ${name}` } });
      } catch (e) {
        return text(String(e.message || e), true);
      }
    }
    default:
      return Response.json({ jsonrpc: '2.0', id: msg.id, error: { code: -32601, message: `Method not found: ${msg.method}` } });
  }
}
