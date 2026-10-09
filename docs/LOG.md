# Experiment log — what works / what doesn't

Running record so we can see what moved the needle. Newest first.
Format: date · tried · result · verdict.

## 2026-10-09 · v0.12.1 — watch Q/A colors

| Tried | Result | Verdict |
| --- | --- | --- |
| Watch card face: one grey card for both sides + 9pt "answer" caption | easy to lose track of which side is showing mid-session | ❌ |
| Blue Q / green A badge + tinted card + border per side (`WatchTheme.question` / `.answer`) | no watch SDK on the Mac (CLT only) → verified by the CI compile; TestFlight carries the watch app, ad hoc IPA never did | ✅ |

## 2026-09-28 · v0.10.1 — Mac save

| Tried | Result | Verdict |
| --- | --- | --- |
| Save an imported Quizlet deck (31 cards) from the Mac app | "This build has no editor access" — `gh secret list` has no FLASHDECK_GITHUB_TOKEN; CI log shows it expanding to empty on every build since 1.3 | ❌ the baked-token plan never ran |
| Mac: `gh auth token` via `Process` (absolute path, unsandboxed app) | harness using the app's own `GitHubService.fetch()` → 7 decks, sha 56bb255 | ✅ Mac saves with the CLI login; nothing secret in the zip |
| macOS default `Form` style in a sheet | two-column labels, long rows clipped off the right edge | ❌ → `.formStyle(.grouped)` via `platformFormStyle()` |

## 2026-09-28 · v0.10.0 — import from a link

| Tried | Result | Verdict |
| --- | --- | --- |
| `curl` a Quizlet set with a Safari UA from the home IP | 403 "Captcha Challenge" (PerimeterX), 0 terms | ❌ plain fetch is dead, worker-side fetch would be worse (datacenter IP) |
| Offscreen `WKWebView` (CLT `swiftc` probe, `probe.swift`) + DOM extractor | real page on try 1, 99 `.TermText` pairs, title "Duolingo flash cards" | ✅ in-app WebKit view + `CardExtractor.script`; keep the view visible so a press-and-hold check can be completed |
| "Duolingo flashcard set URL" | Tinycards is dead; Duolingo has no shareable set links — the sets people share are Quizlet | ℹ️ importer is site-agnostic (TermText → card layouts → dl → 2-col tables) |

## 2026-09-28 · v0.9.0 — Mac target

| Tried | Result | Verdict |
| --- | --- | --- |
| Separate macOS target on the shared `FlashDeck/` sources instead of Catalyst / "Designed for iPad" | those two need App Store distribution; a native target + `codesign -s -` zip works with the ad hoc lane; ~10 iOS-only call sites, all shimmed | ✅ `FlashDeckMac` in project.yml, own icon set (mac idiom needs the 10 sizes, `sips` from icon1024) |
| `ToolbarItem(placement: .topBarTrailing)` | not available on macOS | ❌ → `.primaryAction` (same spot on iPhone) |
| `WatchConnectivity` on macOS | framework doesn't exist there | ❌ → `#if canImport(WatchConnectivity)` with a no-op `LeitnerSync` stub so `DeckStore` is untouched |

## 2026-09-28 · v0.8.1 — double read-aloud

| Tried | Result | Verdict |
| --- | --- | --- |
| Two `onChange` hooks (`flipped`, `index`) both calling `readCurrent()` | swipe on a flipped card fires both in one update; `synth.isSpeaking` is still false for the just-queued utterance so `stop()` skipped it → card read twice from card 2 on | ❌ replaced with one `onChange` on an `(index, flipped)` struct + unconditional `stopSpeaking` |

## 2026-09-16 · v0.7.0 — read-aloud + image links + bundled token

| Tried | Result | Verdict |
| --- | --- | --- |
| Deploy a Cloudflare Worker to hold the GitHub token so the app carries no secret | wrangler logged out on this Mac (clock 25h behind kills OAuth), Dia CDP down, fine-grained PATs are UI-only | ❌ for now — bake a repo-scoped PAT into the TestFlight build via CI secret instead; only the user's own IPA carries it |
| Wikimedia `Special:FilePath/<name>?width=1280` for pasted `File:` pages | 302 → 301 → PNG for SVG sources, 200 image/png | ✅ one rewrite covers every Wikipedia flag/diagram link |
| `thumb.wikimedia.org` link with `?utm_*` (what the iPhone share sheet hands you) | 200 as-is; stripping utm keeps decks.json clean | ✅ |
| SwiftUI `Image` for animated GIFs | first frame only | ❌ → UIImageView + `UIImage.animatedImage` via UIViewRepresentable |
| `xcrun swiftc` on CLT-only Mac to unit-run `ImageURL.normalize` | compiles with Foundation, 12/12 cases | ✅ cheap pre-CI check for pure-Foundation files |

## 2026-07-16 · v0.4.2 — code-review pass

| Tried | Result | Verdict |
| --- | --- | --- |
| Full sweep (codehawk + manual read) | codehawk: only known false positives + trivial boilerplate dups. Manual read found the real ones: (1) grading intents unhandled on the card front → generic error speech; (2) live phone edits mid-session can orphan the current card → crash | ✅ the live-update feature needs guards everywhere a session dereferences a deck |
| Handler-coverage rule of thumb | Every custom intent needs a handler for EVERY state it can fire in — canHandle guards that narrow to one state silently drop the rest to the error handler | ✅ audit canHandle conditions per intent, not per handler |

## 2026-07-16 · v0.4.1 — the Brazil bug

| Tried | Result | Verdict |
| --- | --- | --- |
| User report: "messed up a bit when I got to Brazil" | Brasília is the FIRST non-ASCII text in the capitals deck — `body += chunk` in the decks.json fetch converts each chunk separately, so a í split across chunks decodes as `��`. Proved with a forced mid-character split (old: `Bras��lia`, new: clean). Fixed with `Buffer.concat(chunks)` before one decode | ✅ always concat buffers before decoding; never `+=` HTTP chunks |
| Reading the live CloudWatch line for it | Alexa-hosted skill logs aren't reachable from ask-cli — console-only | ⚠️ debugging hosted skills = reproduce locally, not log-dive |

## 2026-07-16 · v0.4.0 — store-quality pass

| Tried | Result | Verdict |
| --- | --- | --- |
| GridSequence for the home deck grid | 2-col tile grid with childWidth 49% renders on APL 1.3 (Show 11 runtime) | ✅ home feels like an app, not a list |
| Manifest icons via jsDelivr URLs | smallIconUri/largeIconUri accept any HTTPS URL — no S3/console upload needed | ✅ icons versioned in the repo like everything else |
| Editor moved / to /editor.html | localStorage is per-origin not per-path — saved token survives the move | ✅ landing takes the root URL |
| Store cert reality check | Needs: icons ✅ privacy policy ✅ example phrases ✅ … but certification review will test everything; personal decks (exercise mp4 licensing!) must be swapped for licensed content first | ⚠️ dev-mode is fine today; swap media before submitting |

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

## 2026-09-14 — Security+ decks from Ivy's PDFs
- PDFs came in on the hcp Gmail; the Gmail MCP has no attachment download, so pulled them over IMAP (`cony-hcp-imap` keychain app password, `[Gmail]/All Mail`, search FROM).
- `pdftotext -layout` + a small state-machine parser: 226/226 and 532/532 questions parsed, 0 rejects. Dump options sit on their own line ("A." then text) — the regex must allow empty option text. `\s*` before the sim-type group swallowed newlines and made every question a "sim" (1090 renders) — use `[ \t]*`.
- Sims: `pdftoppm -r 110` one page per side, crop 5% header/footer, autocrop whitespace (Pillow). 12 sims → 24 PNGs, 5.5 MB, served by jsDelivr.
- **TRAP: never rsync skill.json from GitHub over the hosted repo copy.** The hosted manifest carries the Lambda `endpoint` + `regions` block that the GitHub copy lacks; the deploy went green but every simulation failed with "No endpoint was found for the specified region". Fix = `git checkout HEAD~1 -- skill-package/skill.json` in the hosted clone + `ask smapi update-skill-manifest` (the hosted pipeline alone did not restore it).
- Hosted repo clone: `printf 'FlashDeck\n' | ask init --hosted-skill-id <id>` (the folder-name prompt blocks otherwise). Push `master` = deploy; `ask smapi get-skill-status` shows hostedSkillDeployment/manifest/interactionModel.
- Simulator: `ask smapi simulate-skill` returns 409 while a previous simulation is still IN_PROGRESS — poll `get-skill-simulation` to completion before the next utterance. Session persists across calls unless `--session-mode FORCE_NEW_SESSION`.

## 2026-09-16 — Apple Watch app
- Single-target watch app (`type: application, platform: watchOS`, `WKApplication` + `WKCompanionAppBundleIdentifier`) added to the same XcodeGen project; the iOS target lists it as a dependency so xcodegen emits "Embed Watch Content". Models.swift + LeitnerSync.swift are shared by path; the App Intents hook in `load()` is `#if os(iOS)`.
- Sync = WatchConnectivity. Phone is the source of truth: `updateApplicationContext` with the full boxes + learnedAt snapshot on every change and on activation; the watch sends one `transferUserInfo` per grade (delivered even when the phone app is closed — iOS launches it in the background), the phone applies it and re-pushes the snapshot. No merge rules beyond "latest learnedAt wins".
- All timestamps stay `Double` epoch seconds — watch hardware is arm64_32 (32-bit Int), `Int(epoch)` traps on device only.
- Watch icon = the same 1024 PNG in its own asset catalog with `platform: watchos` (no alpha, already checked).
