"""Parse a Word-exported exam PDF whose answer key is colored text (blue/red/orange).
Usage: uv run --no-project --with pymupdf python tools/parse_colored_key.py in.pdf out.json"""
import pymupdf as fitz, json, re, sys
from collections import Counter
doc = fitz.open(sys.argv[1])
lines = []  # (text, is_blue)
colors = Counter()
for page in doc:
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            spans = [s for s in l["spans"] if s["text"].strip()]
            if not spans: continue
            text = "".join(s["text"] for s in l["spans"]).strip()
            blue = any(s["color"] in (0x4472c4, 0xff0000, 0xed7d31) for s in spans)
            for s in spans: colors[hex(s["color"])] += 1
            lines.append((text, blue))
print(colors.most_common(6), file=sys.stderr)
qs, cur = [], None
qre, ore = re.compile(r"^(\d+)\.\s*(.*)$"), re.compile(r"^([A-H])\.\s*(.*)$")
for text, blue in lines:
    if (m := qre.match(text)) and (cur is None or int(m.group(1)) == cur["n"] + 1):
        cur = {"n": int(m.group(1)), "prompt": [m.group(2)], "opts": [], "key": []}; qs.append(cur); continue
    if cur is None: continue
    if (m := ore.match(text)):
        cur["opts"].append([m.group(1), m.group(2)])
        if blue: cur["key"].append(m.group(1))
    elif cur["opts"]:
        cur["opts"][-1][1] += " " + text
        if blue and cur["opts"][-1][0] not in cur["key"]: cur["key"].append(cur["opts"][-1][0])
    else:
        cur["prompt"].append(text)
json.dump(qs, open(sys.argv[2], "w"), indent=1)
ok = [q for q in qs if len(q["opts"]) >= 2 and q["key"]]
print(len(qs), "questions,", len(ok), "MC with key", file=sys.stderr)
for q in qs:
    if not (len(q["opts"]) >= 2 and q["key"]): print("NOKEY", q["n"], " ".join(q["prompt"])[:90], len(q["opts"]), file=sys.stderr)
