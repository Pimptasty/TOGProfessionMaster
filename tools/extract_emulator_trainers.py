#!/usr/bin/env python3
"""Extract trainer NPC -> recipe spell mappings from emulator world DBs.

Per-expansion data sources:
    Vanilla  : CMaNGOS-Classic
    TBC      : CMaNGOS-TBC
    Wrath    : AzerothCore           (most active, normalized schema)
    Cata     : TrinityCore (4.3.4 branch)
    MoP      : TrinityCore (5.4.8 branch)

Each emulator has a slightly different schema. This module abstracts the
differences and emits a unified shape:

    {profId: {spellId: [npcId, npcId, ...]}}

This output is then merged into our Data/Sources/<Prof>.lua sourceDB by the
main converter (port_pm_data.py).

Downloads SQL dumps to tools/emulator_data/<source>_<file>.sql. Subsequent
runs reuse the cached files; pass --refresh to re-download.

NOTE on schema variants:
    - AzerothCore (Wrath) uses a normalized schema:
        creature_default_trainer:  (CreatureId, TrainerId)
        trainer_spell:             (TrainerId, SpellId, ReqSkillLine, ...)
      We join on TrainerId. ReqSkillLine identifies which profession.
    - CMaNGOS (Vanilla/TBC) uses the older flat schema:
        npc_trainer: (entry, spell, ...)  -- direct NPC -> spell map
        (npc_trainer_template if a TrainerEntry is referenced)
    - TrinityCore Cata+ uses the same normalized schema as AzerothCore.

We probe both layouts at parse time so a single function handles each
source's file pair.
"""

import argparse
import pathlib
import re
import sys
import urllib.request

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
CACHE_DIR  = SCRIPT_DIR / "emulator_data"

# Source descriptors. Each entry knows its expansion, files to fetch, and
# which parser layout applies.
_AC_BASE = "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/master/data/sql/base/db_world"

SOURCES = [
    {
        "name":      "azerothcore_wrath",
        "expansion": "wrath",
        "layout":    "normalized",
        "files": {
            # Trainer tables (Phase A — trainer-only, original use of this script)
            "creature_default_trainer": f"{_AC_BASE}/creature_default_trainer.sql",
            "trainer_spell":            f"{_AC_BASE}/trainer_spell.sql",
            # Phase B additions: source data for vendor / drop / quest / GO
            "npc_vendor":               f"{_AC_BASE}/npc_vendor.sql",
            "creature_loot_template":   f"{_AC_BASE}/creature_loot_template.sql",
            "gameobject_loot_template": f"{_AC_BASE}/gameobject_loot_template.sql",
            "item_loot_template":       f"{_AC_BASE}/item_loot_template.sql",
            "reference_loot_template":  f"{_AC_BASE}/reference_loot_template.sql",
            "quest_template":           f"{_AC_BASE}/quest_template.sql",
            "creature_template":        f"{_AC_BASE}/creature_template.sql",
        },
    },
    {
        # TrinityCore's Cata Classic TDB. Distributed as a single ~60 MB
        # 7z archive containing one big world.sql; we extract only the two
        # trainer-related tables we need, cached as trinity_cata_*.sql.
        # The local files are produced by the run_once helper below; this
        # entry just points the normalized parser at them.
        "name":      "trinitycore_cata",
        "expansion": "cata",
        "layout":    "normalized",
        "files_local": {
            "creature_default_trainer": "trinity_cata_creature_trainer.sql",
            "trainer_spell":            "trinity_cata_trainer_spell.sql",
        },
        "prepare": "trinity_cata_extract",
    },
    # MoP follows when we locate a current MoP emulator dump (TrinityCore
    # dropped active MoP support; a fork or PandaCore branch likely has it).
    # Vanilla and TBC via CMaNGOS use the older flat layout (single
    # npc_trainer table) and need a different parser; tracked for a later
    # patch since MTSL already covers those expansions reasonably well.
]

# Profession ID -> profession name. Used only for log output / debugging.
PROF_NAMES = {
    171: "Alchemy",        164: "Blacksmithing",  185: "Cooking",
    333: "Enchanting",     202: "Engineering",    129: "First Aid",
    356: "Fishing",        165: "Leatherworking", 186: "Mining",
    197: "Tailoring",      755: "Jewelcrafting",  773: "Inscription",
}


# ---------------------------------------------------------------------------
# Download helpers
# ---------------------------------------------------------------------------

def _download(url: str, dest: pathlib.Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "TOGPM-data-port/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    dest.write_bytes(data)
    print(f"  downloaded {dest.name}: {len(data):,} bytes", file=sys.stderr)


def ensure_files(source: dict, refresh: bool = False) -> dict:
    """Return {logical_name: local_path} for each file in `source`. Downloads
    on first use; reuses cached file otherwise. Handles two modes:

      - `files`:        URL map; download each.
      - `files_local`:  filenames already in CACHE_DIR; assume produced by
                        a `prepare` step (e.g. extracting a 7z that has
                        too many files to want as raw downloads).
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if "files_local" in source:
        # Ensure local files exist; run the prepare step if any is missing.
        out = {logical: CACHE_DIR / fname for logical, fname in source["files_local"].items()}
        missing = [p for p in out.values() if not p.exists()]
        if missing and source.get("prepare") == "trinity_cata_extract":
            _prepare_trinity_cata(refresh=refresh)
        # Verify after prepare
        for logical, path in out.items():
            if not path.exists():
                raise FileNotFoundError(f"{source['name']}: missing {path}")
        return out
    out = {}
    for logical, url in source["files"].items():
        dest = CACHE_DIR / f"{source['name']}_{logical}.sql"
        if not dest.exists() or refresh:
            _download(url, dest)
        else:
            print(f"  using cached {dest.name}", file=sys.stderr)
        out[logical] = dest
    return out


# All TrinityCore Cata world DB tables we want for the source-DB build (Phase
# B of v0.5.0). Trainer tables stay in here for the original trainer-only
# extraction path; vendor / loot / quest tables join recipe items back to
# their source NPCs / quests / containers.
TRINITY_CATA_TABLES = (
    "creature_trainer",
    "trainer_spell",
    "npc_vendor",
    "creature_loot_template",
    "gameobject_loot_template",
    "item_loot_template",       # container-style loot (clams, lockboxes)
    "reference_loot_template",
    "quest_template",
    "creature_template",
)


def _prepare_trinity_cata(refresh: bool = False) -> None:
    """Download TrinityCore's Cata TDB 7z, extract the full world.sql, then
    stream-extract each table in TRINITY_CATA_TABLES into its own smaller
    cached file. Idempotent: returns early when every requested table is
    already extracted (so adding a new table to the tuple above auto-runs the
    extraction on the next call, without re-downloading).
    """
    import py7zr
    import re

    targets = set(TRINITY_CATA_TABLES)
    out_paths = {t: CACHE_DIR / f"trinity_cata_{t}.sql" for t in targets}
    if all(p.exists() for p in out_paths.values()) and not refresh:
        print(f"  [trinitycore_cata] all {len(targets)} tables already extracted, skipping prep",
              file=sys.stderr)
        return

    tdb_url = ("https://github.com/TrinityCore/TrinityCore/releases/download/"
               "TDB442.25051/TDB_full_442.25051_2025_05_11.7z")
    archive_path = CACHE_DIR / "trinity_cata_TDB.7z"
    if not archive_path.exists() or refresh:
        _download(tdb_url, archive_path)
    sql_path = CACHE_DIR / "TDB_full_world_442.25051_2025_05_11.sql"
    if not sql_path.exists() or refresh:
        print(f"  [trinitycore_cata] extracting 7z (~60MB compressed -> ~350MB sql)",
              file=sys.stderr)
        with py7zr.SevenZipFile(archive_path, "r") as z:
            z.extract(path=CACHE_DIR, targets=[sql_path.name])
        print(f"  [trinitycore_cata] extracted: {sql_path.stat().st_size:,} bytes",
              file=sys.stderr)

    print(f"  [trinitycore_cata] streaming for {len(targets)} table INSERTs: "
          f"{sorted(targets)}", file=sys.stderr)
    buffers = {t: [] for t in targets}
    current = None
    insert_re = re.compile(r"INSERT INTO `(\w+)`")
    with open(sql_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = insert_re.match(line)
            if m:
                current = m.group(1) if m.group(1) in targets else None
            if current:
                buffers[current].append(line)
            if line.startswith("--") or line.startswith("CREATE"):
                current = None
    for tbl, lines in buffers.items():
        out_paths[tbl].write_text("".join(lines), encoding="utf-8")
        print(f"  [trinitycore_cata]   {tbl}: {sum(len(l) for l in lines):,} bytes "
              f"({len(lines):,} lines)", file=sys.stderr)


# ---------------------------------------------------------------------------
# SQL INSERT parser (extracts row tuples without a real SQL engine)
# ---------------------------------------------------------------------------

def parse_insert_rows(sql_path: pathlib.Path):
    """Yield tuples of column values for every row in every `INSERT INTO ...
    VALUES (...), (...), ...;` statement in the file.

    Values are returned as raw strings (`'foo'`, `123`, `NULL`, `0.5`).
    Caller is responsible for coercing to types. Handles multi-line VALUES
    lists (each tuple on its own line is common in mysqldump output),
    multiple INSERT statements per file, AND tuples containing quoted
    strings with embedded parentheses (common in quest_template /
    creature_template — descriptions like `"$N (level X)"` would otherwise
    confuse a simple `\\([^()]*\\)` outer split).

    Also handles semicolons inside quoted strings — the previous regex
    `[^;]*?...;` would terminate a multi-tuple INSERT early if any quoted
    quest description contained a `;`. We now walk the file char-by-char,
    state-machine style: locate `VALUES`, then scan for top-level `()`
    tuples while tracking quote state for both `(`/`)`/`;`.
    """
    text = sql_path.read_text(encoding="utf-8", errors="replace")
    insert_re = re.compile(r"INSERT\s+INTO\s+`[^`]+`[^;\(]*VALUES\s*", re.IGNORECASE)
    pos = 0
    while True:
        m = insert_re.search(text, pos)
        if not m:
            return
        i = m.end()
        # Walk tuple-by-tuple from the position right after `VALUES`. We finish
        # the statement when we hit an unquoted `;`.
        n = len(text)
        while i < n:
            # Skip whitespace + commas between tuples
            while i < n and text[i] in " \t\r\n,":
                i += 1
            if i >= n or text[i] == ";":
                i += 1  # consume the trailing semicolon
                break
            if text[i] != "(":
                # malformed — bail out of this statement
                break
            # Walk the tuple body, tracking quoted-string state, until we
            # find the matching `)`. Strings use single quotes; doubled
            # `''` is the escaped-quote convention.
            depth = 1
            j = i + 1
            in_str = False
            tuple_start = j
            while j < n and depth > 0:
                c = text[j]
                if in_str:
                    if c == "'" and j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    if c == "\\" and j + 1 < n:
                        # backslash-escape — skip the next char (mysqldump
                        # uses this for embedded quotes, newlines, etc.)
                        j += 2
                        continue
                    if c == "'":
                        in_str = False
                    j += 1
                    continue
                if c == "'":
                    in_str = True
                    j += 1
                    continue
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if depth != 0:
                # Unbalanced — malformed input, give up on this statement.
                break
            yield _split_csv(text[tuple_start:j])
            i = j + 1
        pos = i


def _split_csv(row_body: str):
    """Split a row body like `1215,2330,100,0,0,12340` into ['1215','2330',...].
    Handles single-quoted string values (no quoted parens in our data files)."""
    out = []
    buf = []
    in_str = False
    i = 0
    while i < len(row_body):
        c = row_body[i]
        if in_str:
            if c == "'" and (i + 1 < len(row_body) and row_body[i + 1] == "'"):
                buf.append("''")
                i += 2
                continue
            if c == "'":
                in_str = False
                buf.append(c)
                i += 1
                continue
            buf.append(c)
            i += 1
            continue
        if c == "'":
            in_str = True
            buf.append(c)
            i += 1
            continue
        if c == ",":
            out.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if buf:
        out.append("".join(buf).strip())
    return out


# ---------------------------------------------------------------------------
# Per-layout extractors
# ---------------------------------------------------------------------------

def extract_normalized(files: dict, source_label: str):
    """Normalized schema: creature_default_trainer + trainer_spell.

    Returns {spellId: [npcId, ...]} keyed by all profession recipe spells.
    ReqSkillLine on trainer_spell tells us which profession a spell belongs
    to; rows where ReqSkillLine is 0 are class spells (not recipes) and are
    dropped. We do NOT split by profession here — the caller's downstream
    merge keys by spellId regardless of profId.
    """
    # trainer_spell: (TrainerId, SpellId, MoneyCost, ReqSkillLine, ReqSkillRank, ReqAb1, ReqAb2, ReqAb3, ReqLevel, VerifiedBuild)
    trainer_spells = {}  # trainerId -> [(spellId, reqSkillLine), ...]
    n_spells = 0
    for cols in parse_insert_rows(files["trainer_spell"]):
        if len(cols) < 4:
            continue
        try:
            trainer_id   = int(cols[0])
            spell_id     = int(cols[1])
            req_skill    = int(cols[3])
        except ValueError:
            continue
        if req_skill == 0:
            continue  # class skill, not a profession recipe
        trainer_spells.setdefault(trainer_id, []).append((spell_id, req_skill))
        n_spells += 1

    # creature_default_trainer: (CreatureId, TrainerId)
    creature_to_trainer = {}
    for cols in parse_insert_rows(files["creature_default_trainer"]):
        if len(cols) < 2:
            continue
        try:
            cid = int(cols[0])
            tid = int(cols[1])
        except ValueError:
            continue
        creature_to_trainer[cid] = tid

    print(f"  [{source_label}] {len(creature_to_trainer):,} NPC->trainer mappings, "
          f"{n_spells:,} trainer-spell rows ({len(trainer_spells):,} trainers)", file=sys.stderr)

    # Join: for each NPC, look up trainer's spells. Build the inverse:
    # {spellId: [npcId, ...]} merging NPCs across trainers as needed.
    out = {}
    for cid, tid in creature_to_trainer.items():
        for spell_id, _req_skill in trainer_spells.get(tid, ()):
            out.setdefault(spell_id, []).append(cid)

    print(f"  [{source_label}] joined: {len(out):,} unique spells, "
          f"{sum(len(v) for v in out.values()):,} (spell, npc) pairs", file=sys.stderr)
    return out


LAYOUT_EXTRACTORS = {
    "normalized": extract_normalized,
}


# ---------------------------------------------------------------------------
# Main API
# ---------------------------------------------------------------------------

def extract_all(refresh: bool = False) -> dict:
    """Process every configured source and return a unified
    {spellId: [npcId, ...]} mapping.

    When multiple sources cover the same spellId, NPCs are merged (deduped).
    """
    merged_spell_to_npcs = {}
    for source in SOURCES:
        print(f"[{source['name']}] fetching files...", file=sys.stderr)
        files = ensure_files(source, refresh=refresh)
        extractor = LAYOUT_EXTRACTORS[source["layout"]]
        per_source = extractor(files, source["name"])
        for spell_id, npcs in per_source.items():
            bucket = merged_spell_to_npcs.setdefault(spell_id, set())
            bucket.update(npcs)

    # Convert sets to sorted lists for deterministic output.
    return {sid: sorted(npcs) for sid, npcs in merged_spell_to_npcs.items()}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--refresh", action="store_true",
                    help="Re-download cached SQL files instead of reusing them.")
    ap.add_argument("--show", type=int, default=0,
                    help="Print the first N (spellId, [npcIds]) entries to stdout for inspection.")
    args = ap.parse_args()
    data = extract_all(refresh=args.refresh)
    print(f"\nTotal: {len(data):,} unique spells with trainer NPC mappings", file=sys.stderr)
    if args.show:
        for i, (sid, npcs) in enumerate(sorted(data.items())):
            if i >= args.show:
                break
            print(f"  spell {sid}: {npcs[:5]}{'...' if len(npcs) > 5 else ''}")


if __name__ == "__main__":
    main()
