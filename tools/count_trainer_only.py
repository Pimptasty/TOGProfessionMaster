#!/usr/bin/env python3
"""Count recipes in our Data/Sources/*.lua that have NO source data
(empty src entry = trainer-only candidate). Helps scope the Wowhead
trainer scrape: how many spell pages do we actually need to fetch?"""

import pathlib
import sys
import re

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ADDON_ROOT = SCRIPT_DIR.parent

try:
    from slpp import slpp
except ImportError:
    print("Install slpp first.", file=sys.stderr)
    sys.exit(1)


def parse_table(path: pathlib.Path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.DOTALL)
    text = re.sub(r"--[^\n]*", "", text)
    brace = text.find("{")
    if brace < 0:
        return {}
    depth = 0
    end = -1
    for i in range(brace, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    return slpp.decode(text[brace:end + 1]) if end >= 0 else {}


PROF_NAMES = {
    171: "Alchemy",        164: "Blacksmithing",  185: "Cooking",
    333: "Enchanting",     202: "Engineering",    129: "First Aid",
    165: "Leatherworking", 186: "Mining",         197: "Tailoring",
    755: "Jewelcrafting",  773: "Inscription",
}

total_empty = 0
total_all = 0
per_prof_empty = {}

for src in (ADDON_ROOT / "Data" / "Sources").glob("*.lua"):
    data = parse_table(src)
    if not isinstance(data, dict):
        continue
    empty = sum(1 for v in data.values() if not v)  # empty {} = trainer-only
    nonempty = sum(1 for v in data.values() if v)
    per_prof_empty[src.stem] = (empty, len(data))
    total_empty += empty
    total_all += len(data)

print(f"Per-profession recipes with no source data (trainer-only candidates):")
for name, (empty, total) in sorted(per_prof_empty.items()):
    print(f"  {name:20s} {empty:5d} / {total:5d}")
print(f"\nTotal: {total_empty} / {total_all}")
