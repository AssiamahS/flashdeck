# Changelog

All notable changes to Flash Deck. Versions are git tags; every change that
alters behavior gets an entry here plus a worked/didn't note in docs/LOG.md.

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
