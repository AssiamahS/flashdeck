# Changelog

All notable changes to Flash Deck. Versions are git tags; every change that
alters behavior gets an entry here plus a worked/didn't note in docs/LOG.md.

## v0.13.0 — 2026-10-09

Practice Test on the Apple Watch (iOS + watch 1.9.0).

- Tapping a deck on the watch opens a deck screen: Flashcards or
  Practice test. Home also has a Practice test button for the last deck.
- Same questions as the phone (Security+ lettered multiple choice, other
  decks get three distractors from the same deck), weakest Leitner box first.
- One colored tile per answer. Tap to answer; "Select TWO" questions take
  the picks and a Check button. Right answer gets a check, a wrong pick an
  ✗, haptic on each, then Next. Crown scrolls long questions.
- Every answer grades the card's box and syncs to the phone like a swipe.
- End screen: score, percent against the 85% exam bar, Retry missed.

## v0.12.1 — 2026-10-09

Watch: color-coded question / answer (iOS + watch 1.8.1).

- The study card on the watch now says which side you're on: a blue "Q ·
  Question" header with a blue tinted card for the front, a green "A ·
  Answer" header with a green tinted card once you flip. Same blue/green
  as the ✗/✓ grading.
- Nothing else on the phone, Mac or Echo Show changes.

## v0.12.0 — 2026-10-07

Practice Test mode (iPhone + Mac 1.8.0).

- New quiz screen in the style of the CompTIA practice-question apps:
  "Points: x/y", progress bar, the question, and one colored tile per
  answer. Tap an answer → the right one gets a check, a wrong pick gets
  an ✗, then the arrow moves on.
- Security+ cards are parsed as real multiple choice (the "A. … D." lines
  in the front, the answer line(s) in the back). "Select TWO/THREE"
  questions ask for that many picks before checking.
- Term/definition decks get four options too: the right back plus three
  backs from the same deck. Image/video cards are left out.
- Order is weakest Leitner box first; every answer grades the card's box,
  so quizzing and swiping share progress. End screen shows the score,
  the 85% exam bar, and "Retry the N missed".
- Open it from the clipboard button in a deck's toolbar, or long-press a
  deck on the home screen → Practice Test.

## v0.11.0 — 2026-09-30

Keyboard study controls (iPhone/iPad with a keyboard + Mac 1.7).

- Space or ↑ flips the card, ↓ skips it, ← = missed, → = got it
  (same directions as the swipes). Works flipped or unflipped.

## v0.10.1 — 2026-09-28

Mac 1.6.1: saving imported decks works.

- The `FLASHDECK_GITHUB_TOKEN` repo secret was never created, so every
  build (iPhone and Mac) shipped with no editor access and Save failed
  with "This build has no editor access". The Mac app now uses this Mac's
  GitHub CLI login (`gh auth token`, the app isn't sandboxed); nothing is
  baked into the public download. iPhone still needs a token pasted in
  Settings once.
- Mac sheets (Import, Edit, Settings) use the grouped form style; the
  default two-column macOS form clipped the link, deck name and status.

## v0.10.0 — 2026-09-28

Import a whole flashcard set from a link (iPhone + Mac 1.6).

- **Import Cards** (↓ button on the home screen): paste a Quizlet (or any
  flashcard page) link, the page loads in an in-app WebKit view, and
  `CardExtractor` reads every term/definition pair off the rendered page.
  Preview, name the deck, Save → new deck in decks.json (or new cards into
  a deck with that name, duplicates skipped) → Echo Show + watch + Mac.
- Why a browser view: Quizlet answers plain HTTP fetches with a captcha
  page even from a home IP; WebKit with the normal Safari fingerprint gets
  the real page (99/99 cards on the first try in testing). If a site does
  show a press-and-hold check, it's right there in the sheet to complete.
- Deck slug logic shared (`Deck.slug`).

## v0.9.0 — 2026-09-28

Mac app.

- **FlashDeckMac target**: the same SwiftUI app builds for macOS 26 from the
  same sources. iPhone-only bits (audio session, haptics, keyboard type,
  inline title bar) sit behind `PlatformShims.swift` / `#if os(iOS)`;
  WatchConnectivity is stubbed out (no watch link from the Mac); card images
  use `NSImage` + `NSImageView`, which plays GIFs natively.
- CI: `mac` job builds, ad hoc signs, zips and publishes
  `docs/mac/FlashDeck-mac.zip`; the install page has a Mac section. Not
  notarized, so the first launch is right-click → Open. The compile check on
  every push builds the Mac target too.
- App version 1.5.

## v0.8.1 — 2026-09-28

iPhone app 1.4.1: read-aloud no longer says a card twice.

- Swiping a flipped card reset `flipped` and bumped `index` in the same
  SwiftUI update, and each had its own `onChange` hook calling the reader.
  The second utterance queued behind the first (the synthesizer isn't
  "speaking" yet when the first was just queued), so every card after the
  first was read twice. One trigger keyed on (index, flipped) now, and
  `stop()` clears the queue unconditionally.

## v0.8.0 — 2026-09-17

iPhone app 1.4: swipe to grade.

- **Card stack**: the study screen is a Tinder-style deck. The next card
  peeks out behind the current one, the top card tilts as you drag, and a
  GOT IT / MISSED stamp fades in. Swipe right = got it, swipe left = missed
  it, flipped or not; a short drag springs back. Tap still flips.
- **Hold to skip** (0.6 s) — swipe up stays free for scrolling long exam
  cards, which now scroll inside the card.
- **Undo**: the arrow between ✗ and ✓ brings the last card back and restores
  its Leitner box (and the learned stamp), synced to the watch.
- The ✗ / ✓ buttons stay as a fallback under the card. Drags that start in
  the left edge are ignored so the system back-swipe still works.
- Progress bar + counter above the deck, like the watch lesson screen.
- Watch and Echo Show unchanged (buttons / voice).

## v0.7.0 — 2026-09-16

iPhone app 1.3: read-aloud, smart image links, no token to type.

- **Read cards aloud**: the study screen speaks the question when a card
  appears and the answer when you flip (AVSpeechSynthesizer, same text
  cleanup the Echo uses for exam cards). Speaker icon in the nav bar mutes /
  unmutes and the choice sticks; a speaker button on the card reads that side
  on demand even while muted. Toggle also lives in Settings → Voice.
- **Paste any image link**: `ImageURL.normalize` rewrites what people
  actually paste — Google Images result pages (`imgres?imgurl=`), Wikipedia /
  Commons `File:` pages, bare SVGs on upload.wikimedia.org (→ the 1280px PNG
  thumb), Dropbox `dl=0`, Drive `file/d/…/view`, imgur and giphy pages — and
  strips `utm_*` / `fbclid` junk. Other SVGs go through wsrv.nl as PNG. Runs at
  save time so decks.json stays clean for the Show, and at display time for
  old cards. The editor shows a live preview under the URL field.
- **GIFs animate**: `RemoteImage` replaces AsyncImage on the phone. It decodes
  GIF frames with ImageIO, sends a real User-Agent (Wikimedia throttles the
  default one) and caches 300 MB on disk.
- **No GitHub token on the phone**: CI bakes a fine-grained PAT (Contents
  read/write on this repo only) into Info.plist from the
  `FLASHDECK_GITHUB_TOKEN` secret. A token pasted in Settings still overrides
  it. Until the secret exists the editor says so instead of asking for one.
- Watch: image links go through the same normalizer.

## v0.6.0 — 2026-09-16

Apple Watch app.

- **Flash Deck on the wrist**: a watchOS app ships inside the iPhone app
  (`ios/FlashDeckWatch`). Home shows cards learned this week + "Continue
  learning" (last deck) + "Decks"; the deck list has a mastery ring per deck
  and a Completed section; a lesson is a progress bar, tap-to-flip card, then
  ✗ / ✓ with haptics; the session ends on a got-it ring. Same `decks.json`,
  same Leitner order as the phone and the Show.
- **Boxes sync phone ⇄ watch** over WatchConnectivity: the watch queues each
  grade, the phone applies it and answers with the full snapshot. Mastery and
  "learned this week" match on both devices.
- iPhone app 1.2: `grade(deck:card:got:)` replaces the box arithmetic in the
  study view; `learnedAt` dates are stored as Doubles (watch `Int` is 32-bit).

## v0.5.0 — 2026-09-14

Security+ exam prep, built from the two practice PDFs Ivy sent.

- **Three Security+ decks**: `security plus` (+226 multiple-choice from the
  2017-2018 set), `security plus exam dump` (532 questions, SY0-501 v13.1),
  `security plus simulations` (12 drag-drop / hotspot / fill-in sims rendered
  from the PDF as image cards; flip shows the answer page). Say "study the
  dump" / "study the sims".
- **Long cards fit the Show**: font and line count scale with card length
  (52dp → 19dp), multi-line cards left-align, `&<>` are escaped for APL and
  newlines become line breaks. Speech reads options as "A. …, B. …".
- **`backImage`**: a card can show a different image on its answer side
  (lambda + iPhone app).
- **Deck slot uses entity resolution**: synonyms ("sims", "the dump", "cert
  prep") land on the canonical deck instead of a loose word match.
- iPhone: long cards shrink + left-align; sims show the answer image on flip.

## v0.4.2 — 2026-07-16

Code-review pass: two real bugs found and fixed.

- Saying "got it" / "missed it" while the card was still face-up had no
  matching handler — the SDK threw and the generic "Something glitched"
  error speech fired. Now answers: "Flip the card first — say flip, or
  tap it."
- Editing a deck from the phone **while studying it** could crash the
  session: the live 60-second deck refresh meant a deleted card (or
  deleted deck) left the session pointing at nothing. Flip/advance now
  detect it and reset gracefully ("That deck just changed…") instead of
  erroring.

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
