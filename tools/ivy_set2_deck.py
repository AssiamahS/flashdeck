#!/usr/bin/env python3
"""Ivy's second PDF (Security_Plus_501.pdf, 2026-10-22): answers are the colored
option lines. Parse with tools/parse_colored_key.py → JSON, then this writes deck
`security-plus-set2` into decks.json. Questions 1-4 are sims (tools/sims_quiz.py)."""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
qs = json.load(open(sys.argv[1]))
cards = []
for x in qs:
    if len(x["opts"]) < 2 or not x["key"]:
        continue
    prompt = " ".join(p.strip() for p in x["prompt"] if p.strip())
    front = prompt + "\n" + "\n".join(f"{l}. {t.strip()}" for l, t in x["opts"])
    back = "\n".join(f"{l}. {t.strip()}" for l, t in x["opts"] if l in x["key"])
    cards.append({"front": front, "back": back})
path = ROOT / "decks.json"
data = json.loads(path.read_text())
deck = {"id": "security-plus-set2", "name": "Security Plus Set Two", "cards": cards}
data["decks"] = [d for d in data["decks"] if d["id"] != deck["id"]]
i = next(n for n, d in enumerate(data["decks"]) if d["id"] == "security-plus-dump") + 1
data["decks"].insert(i, deck)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(len(cards), "cards")
