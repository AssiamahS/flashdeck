#!/usr/bin/env python3
"""Generate exam explanations for lettered multiple-choice decks.

For every card: `why` (why the keyed answer is right) and `whyNot` (letter -> why
that option is wrong). `keyDoubt` is set when the answer key looks wrong for the
current SY0-701 exam. Results cache per deck in tools/explain/<deck>.json, then
--merge writes them into decks.json. Uses the local `claude -p` (no API key).
"""
import json, re, subprocess, sys, concurrent.futures as cf
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPT = re.compile(r"^([A-H])\.\s*(.+)$")
BATCH = 15

PROMPT = """You are a CompTIA Security+ (SY0-701) instructor writing answer explanations for a practice test.
For each question below, the answer key is given. Return ONLY a JSON array, no prose, no code fence. One object per question:
{"n": <number>, "why": "<1-2 sentences: why the keyed answer is correct, naming the concept>", "whyNot": {"<letter>": "<one short sentence why this option is wrong>", ...every NON-keyed letter...}, "keyDoubt": "<ONLY when you would pick a DIFFERENT letter than the key: start with that letter, then why, one sentence. If the key is right or merely loosely worded, OMIT this field.>"}
Plain text, no markdown. Keep each sentence under 30 words.

"""

def lettered(card):
    opts = [l.strip() for l in card["front"].split("\n") if OPT.match(l.strip())]
    keys = [m.group(1) for l in card["back"].split("\n") if (m := OPT.match(l.strip()))]
    return len(opts) >= 2 and keys

def run_batch(items):
    body = "\n\n".join(f"Q{n}:\n{c['front']}\nKEY: {', '.join(k)}" for n, c, k in items)
    for _ in range(3):
        out = subprocess.run(
            ["claude", "-p", "--model", "sonnet", "--strict-mcp-config",
             "--tools", "", "--no-session-persistence"],
            input=PROMPT + body, capture_output=True, text=True, timeout=600).stdout
        m = re.search(r"\[.*\]", out, re.S)
        try:
            rows = json.loads(m.group(0))
            return {r["n"]: r for r in rows if "why" in r}
        except Exception:
            continue
    print("batch failed", items[0][0], file=sys.stderr)
    return {}

def generate(deck_id):
    decks = json.loads((ROOT / "decks.json").read_text())["decks"]
    deck = next(d for d in decks if d["id"] == deck_id)
    cache_path = ROOT / "tools/explain" / f"{deck_id}.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    todo = [(n, c, k) for n, c in enumerate(deck["cards"])
            if (k := lettered(c)) and str(n) not in cache]
    batches = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    print(f"{deck_id}: {len(todo)} to explain in {len(batches)} batches")
    with cf.ThreadPoolExecutor(6) as pool:
        for got in pool.map(run_batch, batches):
            for n, r in got.items():
                cache[str(n)] = {k: r[k] for k in ("why", "whyNot", "keyDoubt") if r.get(k)}
            cache_path.write_text(json.dumps(cache, indent=1, ensure_ascii=False))
            print(f"  {len(cache)} done", flush=True)

def merge():
    path = ROOT / "decks.json"
    data = json.loads(path.read_text())
    for deck in data["decks"]:
        cache_path = ROOT / "tools/explain" / f"{deck['id']}.json"
        if not cache_path.exists():
            continue
        cache = json.loads(cache_path.read_text())
        for n, card in enumerate(deck["cards"]):
            row = dict(cache.get(str(n), {}))
            # a "doubt" that names a keyed letter is the model agreeing, not a doubt
            doubt = row.get("keyDoubt", "")
            if doubt and (doubt[0] in (lettered(card) or []) or not doubt[0].isalpha()):
                row.pop("keyDoubt")
            card.update(row)
        print(deck["id"], sum(1 for c in deck["cards"] if "why" in c), "explained")
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

if __name__ == "__main__":
    if sys.argv[1:] == ["--merge"]:
        merge()
    else:
        for d in sys.argv[1:]:
            generate(d)
