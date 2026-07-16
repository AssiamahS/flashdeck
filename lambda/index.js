const Alexa = require('ask-sdk-core');
const fs = require('fs');
const path = require('path');
const https = require('https');

const CARD_DOC = require('./apl/card.json');
const MENU_DOC = require('./apl/menu.json');

const FRONT_BG = '#141A26';
const BACK_BG = '#0E2A1F';

// Bundled decks — drop more JSON files into lambda/decks/ to add decks.
const BUNDLED_DECKS = {};
for (const f of fs.readdirSync(path.join(__dirname, 'decks'))) {
  if (f.endsWith('.json')) {
    const deck = require(path.join(__dirname, 'decks', f));
    BUNDLED_DECKS[deck.id] = deck;
  }
}

/* ---------- helpers ---------- */

function supportsAPL(handlerInput) {
  const interfaces = Alexa.getSupportedInterfaces(handlerInput.requestEnvelope);
  return interfaces['Alexa.Presentation.APL'] !== undefined;
}

async function getPersistent(handlerInput) {
  try {
    return (await handlerInput.attributesManager.getPersistentAttributes()) || {};
  } catch (e) {
    console.log('persistence read skipped:', e.message);
    return {};
  }
}

async function savePersistent(handlerInput, attrs) {
  try {
    handlerInput.attributesManager.setPersistentAttributes(attrs);
    await handlerInput.attributesManager.savePersistentAttributes();
  } catch (e) {
    console.log('persistence write skipped:', e.message);
  }
}

// decks.json in the GitHub repo is the live source of truth — edited from the
// phone (docs/ editor). Remote decks override bundled ones by id; bundled
// decks are the offline fallback. raw.githubusercontent caches ~5min, so the
// minute-bucketed query param keeps edits showing up within ~a minute.
const REMOTE_DECKS_URL = 'https://raw.githubusercontent.com/AssiamahS/flashdeck/main/decks.json';
let remoteDecksCache = { at: 0, decks: null };

function fetchRemoteDecks() {
  return new Promise((resolve) => {
    const bust = Math.floor(Date.now() / 60000);
    const req = https.get(`${REMOTE_DECKS_URL}?v=${bust}`, { timeout: 3500 }, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        return resolve(null);
      }
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve(Array.isArray(parsed) ? parsed : parsed.decks || null);
        } catch (e) {
          console.log('remote decks parse failed:', e.message);
          resolve(null);
        }
      });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve(null);
    });
    req.on('error', (e) => {
      console.log('remote decks fetch failed:', e.message);
      resolve(null);
    });
  });
}

async function allDecks(persistent) {
  const decks = { ...BUNDLED_DECKS };
  if (Date.now() - remoteDecksCache.at > 60000) {
    const remote = await fetchRemoteDecks();
    remoteDecksCache = { at: Date.now(), decks: remote || remoteDecksCache.decks };
  }
  for (const d of remoteDecksCache.decks || []) {
    if (d && d.id && Array.isArray(d.cards)) decks[d.id] = d;
  }
  decks.notes = { id: 'notes', name: 'My Notes', cards: persistent.notes || [] };
  return decks;
}

function findDeck(decks, spoken) {
  if (!spoken) return null;
  const s = spoken.toLowerCase().trim();
  for (const deck of Object.values(decks)) {
    if (deck.id === s || deck.name.toLowerCase() === s) return deck;
  }
  // loose match: any word overlap
  for (const deck of Object.values(decks)) {
    const words = deck.name.toLowerCase().split(/\s+/);
    if (words.some((w) => s.includes(w))) return deck;
  }
  return null;
}

// Leitner-style: lower box = seen less / missed more = studied first.
function studyOrder(deck, progress) {
  return deck.cards
    .map((c, i) => ({ i, box: (progress[i] && progress[i].box) || 1 }))
    .sort((a, b) => a.box - b.box || a.i - b.i)
    .map((x) => x.i);
}

function renderMenu(handlerInput, decks) {
  if (!supportsAPL(handlerInput)) return;
  handlerInput.responseBuilder.addDirective({
    type: 'Alexa.Presentation.APL.RenderDocument',
    token: 'menu',
    document: MENU_DOC,
    datasources: {
      menuData: {
        decks: Object.values(decks).map((d) => ({
          id: d.id,
          name: d.name,
          count: d.cards.length
        }))
      }
    }
  });
}

function renderCard(handlerInput, deck, session) {
  if (!supportsAPL(handlerInput)) return;
  const card = deck.cards[session.order[session.pos]];
  const isFront = session.side === 'front';
  handlerInput.responseBuilder.addDirective({
    type: 'Alexa.Presentation.APL.RenderDocument',
    token: 'card',
    document: CARD_DOC,
    datasources: {
      cardData: {
        deckName: deck.name,
        progress: `${session.pos + 1} / ${session.order.length}`,
        side: session.side,
        text: isFront ? card.front : card.back,
        image: card.image || '',
        video: card.video || '',
        hint: isFront
          ? 'Say “flip” — or tap the card'
          : 'Say “got it” or “missed it”',
        bg: isFront ? FRONT_BG : BACK_BG
      }
    }
  });
}

async function startStudy(handlerInput, deckId) {
  const persistent = await getPersistent(handlerInput);
  const decks = await allDecks(persistent);
  const deck = decks[deckId];
  if (!deck || deck.cards.length === 0) {
    const names = Object.values(decks)
      .filter((d) => d.cards.length > 0)
      .map((d) => d.name)
      .join(', ');
    renderMenu(handlerInput, decks);
    return handlerInput.responseBuilder
      .speak(`That deck is empty. You can study: ${names}. Which one?`)
      .reprompt('Which deck do you want to study?')
      .getResponse();
  }
  const progress = (persistent.progress && persistent.progress[deck.id]) || {};
  const session = {
    deckId: deck.id,
    order: studyOrder(deck, progress),
    pos: 0,
    side: 'front',
    right: 0,
    wrong: 0
  };
  handlerInput.attributesManager.setSessionAttributes({ study: session });
  const card = deck.cards[session.order[0]];
  renderCard(handlerInput, deck, session);
  return handlerInput.responseBuilder
    .speak(`${deck.name}, ${deck.cards.length} cards. First card: ${card.front}. Say flip when you're ready.`)
    .reprompt('Say flip to see the answer.')
    .getResponse();
}

async function advance(handlerInput, correct) {
  const attrs = handlerInput.attributesManager.getSessionAttributes();
  const session = attrs.study;
  if (!session) return notStudying(handlerInput);

  const persistent = await getPersistent(handlerInput);
  const decks = await allDecks(persistent);
  const deck = decks[session.deckId];
  const cardIndex = session.order[session.pos];

  if (correct !== null) {
    persistent.progress = persistent.progress || {};
    persistent.progress[deck.id] = persistent.progress[deck.id] || {};
    const entry = persistent.progress[deck.id][cardIndex] || { box: 1 };
    entry.box = correct ? Math.min((entry.box || 1) + 1, 5) : 1;
    entry.last = Date.now();
    persistent.progress[deck.id][cardIndex] = entry;
    await savePersistent(handlerInput, persistent);
    if (correct) session.right += 1;
    else session.wrong += 1;
  }

  session.pos += 1;
  session.side = 'front';

  if (session.pos >= session.order.length) {
    const total = session.right + session.wrong;
    const summary =
      total > 0
        ? `Deck done! You got ${session.right} out of ${total}. Cards you missed will come up first next time.`
        : 'Deck done!';
    handlerInput.attributesManager.setSessionAttributes({});
    renderMenu(handlerInput, decks);
    return handlerInput.responseBuilder
      .speak(`${summary} Want to study another deck?`)
      .reprompt('Say a deck name, or say stop.')
      .getResponse();
  }

  handlerInput.attributesManager.setSessionAttributes({ study: session });
  const card = deck.cards[session.order[session.pos]];
  renderCard(handlerInput, deck, session);
  const prefix = correct === null ? 'Skipped. ' : correct ? 'Nice. ' : 'It’ll come back around. ';
  return handlerInput.responseBuilder
    .speak(`${prefix}Next: ${card.front}.`)
    .reprompt('Say flip to see the answer.')
    .getResponse();
}

function notStudying(handlerInput) {
  return handlerInput.responseBuilder
    .speak('You’re not in a deck right now. Say, study world capitals, or, list decks.')
    .reprompt('Say a deck name to start.')
    .getResponse();
}

async function flip(handlerInput) {
  const attrs = handlerInput.attributesManager.getSessionAttributes();
  const session = attrs.study;
  if (!session) return notStudying(handlerInput);
  const persistent = await getPersistent(handlerInput);
  const deck = (await allDecks(persistent))[session.deckId];
  session.side = session.side === 'front' ? 'back' : 'front';
  handlerInput.attributesManager.setSessionAttributes({ study: session });
  const card = deck.cards[session.order[session.pos]];
  renderCard(handlerInput, deck, session);
  const speech =
    session.side === 'back'
      ? `${card.back}. Did you get it?`
      : `${card.front}. Say flip for the answer.`;
  return handlerInput.responseBuilder
    .speak(speech)
    .reprompt(session.side === 'back' ? 'Got it, or missed it?' : 'Say flip when ready.')
    .getResponse();
}

/* ---------- handlers ---------- */

const LaunchRequestHandler = {
  canHandle: (h) => Alexa.getRequestType(h.requestEnvelope) === 'LaunchRequest',
  async handle(h) {
    const persistent = await getPersistent(h);
    const decks = await allDecks(persistent);
    const names = Object.values(decks)
      .filter((d) => d.cards.length > 0)
      .map((d) => d.name)
      .join(', ');
    renderMenu(h, decks);
    return h.responseBuilder
      .speak(`Welcome to Flash Deck. You have: ${names}. Say study and a deck name — or say, note something, to save a quick note.`)
      .reprompt('Which deck do you want to study?')
      .getResponse();
  }
};

const StudyIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'StudyIntent',
  async handle(h) {
    const spoken = Alexa.getSlotValue(h.requestEnvelope, 'deck');
    const persistent = await getPersistent(h);
    const decks = await allDecks(persistent);
    const deck = findDeck(decks, spoken);
    if (deck) return startStudy(h, deck.id);
    const names = Object.values(decks)
      .filter((d) => d.cards.length > 0)
      .map((d) => d.name)
      .join(', ');
    renderMenu(h, decks);
    return h.responseBuilder
      .speak(`Which deck? You have: ${names}.`)
      .reprompt('Say a deck name.')
      .getResponse();
  }
};

const FlipIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'FlipIntent',
  handle: (h) => flip(h)
};

const GotItIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    ['GotItIntent', 'AMAZON.YesIntent'].includes(Alexa.getIntentName(h.requestEnvelope)) &&
    h.attributesManager.getSessionAttributes().study &&
    h.attributesManager.getSessionAttributes().study.side === 'back',
  handle: (h) => advance(h, true)
};

const MissedIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    ['MissedIntent', 'AMAZON.NoIntent'].includes(Alexa.getIntentName(h.requestEnvelope)) &&
    h.attributesManager.getSessionAttributes().study &&
    h.attributesManager.getSessionAttributes().study.side === 'back',
  handle: (h) => advance(h, false)
};

const NextIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'AMAZON.NextIntent',
  handle: (h) => advance(h, null)
};

// Yes/No outside of grading: yes = show menu, no = goodbye
const YesNoFallthroughHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    ['AMAZON.YesIntent', 'AMAZON.NoIntent'].includes(Alexa.getIntentName(h.requestEnvelope)),
  async handle(h) {
    if (Alexa.getIntentName(h.requestEnvelope) === 'AMAZON.NoIntent') {
      return h.responseBuilder.speak('Okay, happy studying!').getResponse();
    }
    const persistent = await getPersistent(h);
    const decks = await allDecks(persistent);
    renderMenu(h, decks);
    return h.responseBuilder
      .speak('Which deck?')
      .reprompt('Say a deck name.')
      .getResponse();
  }
};

const AddNoteIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'AddNoteIntent',
  async handle(h) {
    const text = Alexa.getSlotValue(h.requestEnvelope, 'text');
    if (!text) {
      return h.responseBuilder
        .speak('What should the note say?')
        .reprompt('Say, note, and then your note.')
        .getResponse();
    }
    const persistent = await getPersistent(h);
    const stamp = new Date().toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric'
    });
    persistent.notes = persistent.notes || [];
    persistent.notes.push({ front: text, back: `Note • ${stamp}`, created: Date.now() });
    await savePersistent(h, persistent);
    if (supportsAPL(h)) {
      h.responseBuilder.addDirective({
        type: 'Alexa.Presentation.APL.RenderDocument',
        token: 'card',
        document: CARD_DOC,
        datasources: {
          cardData: {
            deckName: 'My Notes',
            progress: `${persistent.notes.length} saved`,
            side: 'front',
            text: text,
            image: '',
            video: '',
            hint: 'Say “study my notes” any time to review',
            bg: '#26200E'
          }
        }
      });
    }
    return h.responseBuilder
      .speak(`Noted: ${text}. Say, study my notes, any time to review them.`)
      .getResponse();
  }
};

const ListDecksIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'ListDecksIntent',
  async handle(h) {
    const persistent = await getPersistent(h);
    const decks = await allDecks(persistent);
    const names = Object.values(decks)
      .filter((d) => d.cards.length > 0)
      .map((d) => `${d.name}, ${d.cards.length} cards`)
      .join('. ');
    renderMenu(h, decks);
    return h.responseBuilder
      .speak(`${names}. Which one?`)
      .reprompt('Say a deck name to start.')
      .getResponse();
  }
};

// Taps on the screen (APL SendEvent)
const APLUserEventHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'Alexa.Presentation.APL.UserEvent',
  async handle(h) {
    const args = h.requestEnvelope.request.arguments || [];
    if (args[0] === 'study' && args[1]) return startStudy(h, args[1]);
    if (args[0] === 'flip') return flip(h);
    return h.responseBuilder.getResponse();
  }
};

const HelpIntentHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'AMAZON.HelpIntent',
  handle: (h) =>
    h.responseBuilder
      .speak(
        'Say study and a deck name to start. On each card, say flip to see the answer, then got it or missed it — I remember what you miss and show it more often. You can also say, note, followed by anything, to save a quick note.'
      )
      .reprompt('Say a deck name, or say list decks.')
      .getResponse()
};

const StopHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    ['AMAZON.StopIntent', 'AMAZON.CancelIntent'].includes(Alexa.getIntentName(h.requestEnvelope)),
  handle: (h) => h.responseBuilder.speak('Later! Keep stacking those cards.').getResponse()
};

const FallbackHandler = {
  canHandle: (h) =>
    Alexa.getRequestType(h.requestEnvelope) === 'IntentRequest' &&
    Alexa.getIntentName(h.requestEnvelope) === 'AMAZON.FallbackIntent',
  handle: (h) =>
    h.responseBuilder
      .speak('Didn’t catch that. Say flip, got it, missed it, or a deck name.')
      .reprompt('Say help if you want the full list of commands.')
      .getResponse()
};

const SessionEndedHandler = {
  canHandle: (h) => Alexa.getRequestType(h.requestEnvelope) === 'SessionEndedRequest',
  handle: (h) => h.responseBuilder.getResponse()
};

const ErrorHandler = {
  canHandle: () => true,
  handle(h, error) {
    console.log('ERROR:', error.stack || error.message);
    return h.responseBuilder
      .speak('Something glitched. Try that again.')
      .reprompt('Say a deck name, or say help.')
      .getResponse();
  }
};

/* ---------- skill builder ---------- */

function persistenceAdapter() {
  if (process.env.S3_PERSISTENCE_BUCKET) {
    const { S3PersistenceAdapter } = require('ask-sdk-s3-persistence-adapter');
    return new S3PersistenceAdapter({ bucketName: process.env.S3_PERSISTENCE_BUCKET });
  }
  return undefined;
}

const builder = Alexa.SkillBuilders.custom();
const adapter = persistenceAdapter();
if (adapter) builder.withPersistenceAdapter(adapter);

exports.handler = builder
  .addRequestHandlers(
    LaunchRequestHandler,
    StudyIntentHandler,
    FlipIntentHandler,
    GotItIntentHandler,
    MissedIntentHandler,
    NextIntentHandler,
    AddNoteIntentHandler,
    ListDecksIntentHandler,
    APLUserEventHandler,
    HelpIntentHandler,
    StopHandler,
    YesNoFallthroughHandler,
    FallbackHandler,
    SessionEndedHandler
  )
  .addErrorHandlers(ErrorHandler)
  .lambda();
