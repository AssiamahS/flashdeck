# Changelog

All notable changes to Flash Deck. Versions are git tags; every change that
alters behavior gets an entry here plus a worked/didn't note in docs/LOG.md.

## v0.4.1 — 2026-07-16

Fix: accented characters could render/speak garbled (first hit: Brasília).

- The runtime `decks.json` fetch accumulated the HTTP body with per-chunk
  string conversion; a multi-byte UTF-8 character straddling a chunk boundary
  decoded as `��` (so "Brasília" → "Bras��lia", intermittently, depending on
  how the network chunked the response). Now buffers are concatenated before
  a single UTF-8 decode. Reproduced deterministically with a forced
  mid-character split; also protects "¿Cómo estás?" and every future
  non-English deck.

## v0.4.0 — 2026-07-16

Store-quality: real home screen, brand assets, website, release channel.

- **Home screen v2** ("Alexa, open flash deck"): 2-column tappable deck-tile
  grid with per-deck accent colors, live stats line (decks · cards · mastered,
  computed from Leitner progress), rotating "try saying" hint bar. Same
  trigger, same tap-to-study — just a real product home now.
- Launch speech tightened to match ("N decks, M cards ready").
- **Brand assets**: 108/512 skill icons (stacked-cards + Leitner dots),
  generated in `media/icons/`, wired into the manifest via jsDelivr.
- **Manifest**: store-grade summary/description/keywords, real testing
  instructions, privacy policy URL.
- **Website** (GitHub Pages root): landing page with hero, demo video,
  feature grid, phrase chips, Download button (latest GitHub release) —
  the deck editor moved to `/editor.html` (tokens carry over automatically).
- `docs/privacy.html` — required for store certification.
- README rebuilt as a marketable repo front page (badges, website/editor/
  download links, run-your-own guide, roadmap). MIT LICENSE added.

## v0.3.0 — 2026-07-15

Add cards from your phone — no redeploy needed.

- `decks.json` (repo root) is now the live deck source: the lambda fetches it
  from GitHub raw at runtime (60s in-memory cache + minute-bucketed cache
  buster), overriding bundled decks by id. Bundled `lambda/decks/` remain the
  offline fallback. Edit → commit → live on the Show in ~1 minute.
- Phone editor at `docs/index.html` (GitHub Pages): mobile-first deck editor —
  browse decks, add/delete cards (front/back/image/video), create decks.
  Saves by committing `decks.json` via the GitHub contents API with a
  fine-grained PAT stored only in the phone's localStorage. Add to Home
  Screen for an app-like feel.
- New decks studyable by name immediately: custom slot types accept
  out-of-list values, and `findDeck` loose-matches, so no model rebuild.
- Known tradeoff: Leitner progress is keyed by card index, so inserting or
  deleting cards mid-deck shifts what progress maps to. Fine at this scale.

## v0.2.0 — 2026-07-15

Animated cards (GIF workflow) + new home at github.com/AssiamahS/flashdeck.

- `tools/gif2mp4.sh`: converts any GIF (file or URL) into an APL-safe looping
  mp4 (h264/yuv420p, even dims, faststart, muted). GIFs never animate in APL —
  the Video component is the only path, and it needs mp4.
- mp4s live in `media/` and are served via jsDelivr
  (`cdn.jsdelivr.net/gh/AssiamahS/flashdeck@main/media/...`) — correct
  video/mp4 content type, free CDN, no S3 juggling.
- New starter deck: **Exercise Form** ("study exercise form" / "workout") —
  squat anatomy animation on the first two cards, form-cue cards after.
- DECK slot: added exercise form + synonyms.
- Repo moved: origin is now AssiamahS/flashdeck (was setitoff).

## v0.1.0 — 2026-07-15

First scaffold. Not yet deployed (waiting on Amazon developer account auth).

- Alexa custom skill, invocation **"flash deck"**, en-US model
- APL card screen: image on front, tap-to-flip, mp4 video support (looping,
  muted), progress counter, front/back color change
- APL menu screen: tappable deck list with card counts
- Leitner spaced repetition (boxes 1–5): "got it" promotes, "missed it"
  resets to box 1; lowest boxes studied first; persisted to S3 between sessions
- Voice notes: "note ..." saves a card into a My Notes deck, shown
  full-screen post-it style; "study my notes" reviews them
- Starter decks: World Capitals (flag images), Spanish Basics, Security Plus
- Decks are plain JSON in `lambda/decks/`
