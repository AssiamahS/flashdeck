# Experiment log — what works / what doesn't

Running record so we can see what moved the needle. Newest first.
Format: date · tried · result · verdict.

## 2026-07-15 · v0.3.0 — phone editing via runtime decks

| Tried | Result | Verdict |
| --- | --- | --- |
| "Do we need an iPhone app to add cards?" | No native app: lambda now pulls `decks.json` from GitHub raw at runtime; anything that can commit to the repo is an editor. Built a mobile web editor on GitHub Pages (PAT in localStorage, contents API PUT) — Add to Home Screen ≈ app | ✅ zero App Store, zero backend |
| raw.githubusercontent freshness | ~5 min CDN cache would lag edits; minute-bucketed `?v=` query busts it → edits live in ~1 min | ✅ |
| New decks without model rebuild | Custom slot types pass out-of-list values through, `findDeck` loose-matches the transcript | ✅ say the deck name naturally |
| Leitner progress vs edits | Progress keyed by card index — inserting/deleting mid-deck shifts mappings | ⚠️ acceptable; revisit with per-card ids if it annoys |

## 2026-07-15 · v0.2.0 — animated (GIF→mp4) cards

| Tried | Result | Verdict |
| --- | --- | --- |
| GIF on a card via makeagif URL | Reconfirmed: APL Image = static first frame. Converted with `tools/gif2mp4.sh` (ffmpeg h264/yuv420p/even-dims/faststart) → plays looping + muted in APL Video | ✅ this is the pattern for all animated cards |
| Hosting card mp4s | Committed to `media/` in the GitHub repo, served via jsDelivr (`cdn.jsdelivr.net/gh/AssiamahS/flashdeck@main/media/squat.mp4`). raw.githubusercontent.com sends `application/octet-stream`, which the Show's player can refuse; jsDelivr sends real `video/mp4` | ✅ jsDelivr; keep files small (CDN cap 20MB) |
| Squat anatomy source | makeagif user upload (unknown license) — fine for a personal dev-mode skill, but swap for wger/everkinetic (CC) assets before any store submission | ⚠️ licensing note |

## 2026-07-15 · v0.1.0

| Tried | Result | Verdict |
| --- | --- | --- |
| Animated GIFs on cards | APL's Image component renders GIFs as a static frame — confirmed limitation, not worth fighting | ❌ use MP4 in APL Video (looping, muted) instead |
| Research: existing Quizlet/Alexa skills | "Quizlet study flashcards" store skill (B06XYD5C3N) is voice-only, old, and forces awkward "study X" phrasing; SpartahackX (2025) pipes Quizlet sets in via PIN + grades answers with Gemini AI but has no screen support; Amazon's own course builds a quiz skill with APL + DynamoDB leaderboard | ✅ gap confirmed: nobody combines Show visuals + spaced repetition + cert content |
| Research: Duolingo on Alexa | No official Duolingo skill; closest is Glot, a 2017 one-lesson prototype | ✅ "Duolingo for Echo Show" lane is open |
| Reddit/X/Substack searches | Reddit returned a JS page shell (no content), X and Substack returned zero hits | ❌ web + GitHub searches were the only useful sources today |
| Leitner boxes over S3 persistence | Implemented, syntax-checked; not yet observed on device | ⏳ verify after first deploy |
| flagcdn.com flag images in capitals deck | URLs follow w640/{iso}.png pattern | ⏳ verify they render on the Show |

**Blocked on:** Amazon developer account sign-in (same account as the Echo
Show) + `ask configure`. Everything after that is automated.

**Next candidates (from research):**
- AI answer grading: say the answer out loud and have an LLM judge it
  (SpartahackX/QuizMe pattern) instead of self-grading — the single biggest
  UX upgrade toward Duolingo territory
- Quizlet set import (their export gives term/definition text)
- Streaks + daily goal (Duolingo mechanic; Reminders API for study nudges)
- Echo Show 15 widget for the fridge notes board

## 2026-07-15 — deployed to Alexa-hosted
- Skill ID: `amzn1.ask.skill.b1f80163-d80e-424e-ac6d-85c84f6b2e9f` (vendor M1RK36PT6B98GB, us-east-1, auto-enabled on account)
- Deploy vehicle: CodeCommit repo `b1f80163-...` — push to `master` = deploy. Credential helper wired via ask-cli; re-clone anytime with `ask init --hosted-skill-id <id>`.
- Simulator smoke test passed: "open flash deck" → welcome speech w/ 3 decks + APL RenderDocument.
- LESSON: `ask new` driven by expect mangles typed skill name (prompt echo re-triggers matches) — name defaulted to "hosted hello world"; harmless, first manifest push renames it.
