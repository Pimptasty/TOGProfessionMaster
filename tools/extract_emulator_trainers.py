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
    {
        # CMaNGOS-Classic ships its full DB as a single gzip dump. We
        # download it once, gunzip, stream-extract just the trainer
        # tables — same pattern as TrinityCore Cata above.
        #
        # Why this source matters for skill-rank coverage: AzerothCore
        # Wrath and TrinityCore Cata strip out Apprentice-tier Vanilla
        # recipes from their trainer_spell tables (by Wrath those are
        # auto-taught when you pick up the profession). CMaNGOS-Classic
        # is a Vanilla-era emulator and keeps the full apprentice
        # rosters, so it's the only source that has ReqSkillRank for
        # recipes like Linen Bandage / Smelt Copper / Light Leather /
        # Minor Healing Potion.
        #
        # Schema is the older flat layout (no normalized trainer_spell
        # join needed): npc_trainer rows are
        # (entry, spell, spellcost, reqskill, reqskillvalue, reqlevel,
        #  condition_id) — entry IS the NPC id, no TrainerId indirection.
        "name":      "cmangos_classic",
        "expansion": "vanilla",
        "layout":    "flat",
        "files_local": {
            "npc_trainer":          "cmangos_classic_npc_trainer.sql",
            "npc_trainer_template": "cmangos_classic_npc_trainer_template.sql",
        },
        "prepare": "cmangos_classic_extract",
    },
    # MoP follows when we locate a current MoP emulator dump (TrinityCore
    # dropped active MoP support; a fork or PandaCore branch likely has it).
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
        if missing and source.get("prepare") == "cmangos_classic_extract":
            _prepare_cmangos_classic(refresh=refresh)
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


# CMaNGOS-Classic ships its full world DB as a single gzip-compressed SQL
# dump. We need just the trainer tables. Same idempotent extract pattern as
# the TrinityCore Cata prep.
CMANGOS_CLASSIC_TABLES = (
    "npc_trainer",
    "npc_trainer_template",
)

def _prepare_cmangos_classic(refresh: bool = False) -> None:
    """Download CMaNGOS-Classic's Full DB (gzipped SQL), gunzip in memory,
    stream-extract npc_trainer + npc_trainer_template INSERTs into their
    own cached files. Idempotent."""
    import gzip
    import re

    targets = set(CMANGOS_CLASSIC_TABLES)
    out_paths = {t: CACHE_DIR / f"cmangos_classic_{t}.sql" for t in targets}
    if all(p.exists() for p in out_paths.values()) and not refresh:
        print(f"  [cmangos_classic] all {len(targets)} tables already extracted, skipping prep",
              file=sys.stderr)
        return

    # CMaNGOS-Classic dump lives at the repo's Full_DB/. Filename includes a
    # version + zXXXX revision suffix that bumps on dump updates; using the
    # GitHub API to discover the current filename keeps us future-proof
    # without hardcoding a stale name.
    import json
    api_url = "https://api.github.com/repos/cmangos/classic-db/contents/Full_DB"
    req = urllib.request.Request(api_url, headers={"User-Agent": "TOGPM-data-port/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        entries = json.loads(resp.read().decode("utf-8"))
    dump_entry = next((e for e in entries if e["name"].endswith(".sql.gz")), None)
    if not dump_entry:
        raise RuntimeError("CMaNGOS-Classic Full_DB has no .sql.gz dump file")
    dump_url   = dump_entry["download_url"]
    archive_path = CACHE_DIR / f"cmangos_classic_{dump_entry['name']}"
    if not archive_path.exists() or refresh:
        _download(dump_url, archive_path)

    print(f"  [cmangos_classic] streaming {dump_entry['name']} for {sorted(targets)}",
          file=sys.stderr)
    buffers = {t: [] for t in targets}
    current = None
    insert_re = re.compile(r"INSERT INTO `(\w+)`")
    with gzip.open(archive_path, "rt", encoding="utf-8", errors="replace") as f:
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
        print(f"  [cmangos_classic]   {tbl}: {sum(len(l) for l in lines):,} bytes "
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


def extract_flat(files: dict, source_label: str):
    """Flat schema (CMaNGOS Classic / TBC): a single npc_trainer table where
    each row is (entry, spell, spellcost, reqskill, reqskillvalue, reqlevel,
    condition_id). `entry` is the NPC id directly — no TrainerId
    indirection. Returns {spellId: [npcId, ...]}.

    Also reads npc_trainer_template if present and joins via entry-of-type
    referenced trainers. CMaNGOS uses entry > 200000 as template references
    in some places, but the simpler interpretation (entry IS the NPC) works
    for the vast majority of profession trainers and matches what we need
    for ReqSkillRank extraction.
    """
    npc_to_spells = {}
    n_rows = 0
    for tbl_key in ("npc_trainer", "npc_trainer_template"):
        path = files.get(tbl_key)
        if not path or not path.exists():
            continue
        for cols in parse_insert_rows(path):
            if len(cols) < 5:
                continue
            try:
                entry      = int(cols[0])
                spell_id   = int(cols[1])
                req_skill  = int(cols[3])
            except ValueError:
                continue
            if req_skill == 0:
                continue  # class spell
            npc_to_spells.setdefault(entry, []).append(spell_id)
            n_rows += 1
    print(f"  [{source_label}] flat-layout rows: {n_rows:,} "
          f"across {len(npc_to_spells):,} trainer entries", file=sys.stderr)

    out = {}
    for entry, spells in npc_to_spells.items():
        for sid in spells:
            out.setdefault(sid, []).append(entry)
    return out


LAYOUT_EXTRACTORS = {
    "normalized": extract_normalized,
    "flat":       extract_flat,
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


def extract_all_skill_ranks(refresh: bool = False) -> dict:
    """Walk every configured trainer source and return the authoritative
    `{spellId: ReqSkillRank}` map — the literal "Requires Blacksmithing
    (150)" / "Requires Tailoring (300)" / etc. value the trainer NPC
    enforces at point-of-learn. Used by build_authoritative_data.py to
    populate `requiredSkill` for trainer-taught recipes where the DBC's
    MinSkillLineRank is the placeholder 1.

    When a spell appears in multiple sources (e.g. a Vanilla recipe in
    AzerothCore Wrath AND TrinityCore Cata), the LATER expansion wins —
    Blizzard occasionally rebalances trainer requirements between
    expansions and the newer value matches the current live game state
    for that content.

    SOURCES is ordered oldest → newest (AzerothCore Wrath → TrinityCore
    Cata → future MoP), so a straight overwrite as we iterate gives the
    right precedence.
    """
    # Per-layout column indices into a trainer-spell row tuple. Both
    # layouts have (..., spell_id, ..., req_skill_line, req_skill_rank, ...)
    # but at different positions:
    #   normalized (AzerothCore Wrath / TrinityCore Cata trainer_spell):
    #     (TrainerId, SpellId, MoneyCost, ReqSkillLine, ReqSkillRank, ...)
    #   flat (CMaNGOS Classic / TBC npc_trainer + npc_trainer_template):
    #     (entry, spell, spellcost, reqskill, reqskillvalue, reqlevel, ...)
    LAYOUT_COLS = {
        "normalized": {"spell": 1, "line": 3, "rank": 4, "files": ("trainer_spell",)},
        "flat":       {"spell": 1, "line": 3, "rank": 4, "files": ("npc_trainer", "npc_trainer_template")},
    }
    skill_ranks: dict[int, int] = {}
    for source in SOURCES:
        layout = source["layout"]
        cols_def = LAYOUT_COLS.get(layout)
        if not cols_def:
            continue
        print(f"[{source['name']}] reading trainer rows for ReqSkillRank "
              f"(layout={layout})...", file=sys.stderr)
        files = ensure_files(source, refresh=refresh)
        n_rows = 0
        n_skipped_class = 0
        for tbl_key in cols_def["files"]:
            tbl_path = files.get(tbl_key)
            if not tbl_path or not tbl_path.exists():
                continue
            for cols in parse_insert_rows(tbl_path):
                if len(cols) <= cols_def["rank"]:
                    continue
                try:
                    spell_id = int(cols[cols_def["spell"]])
                    req_line = int(cols[cols_def["line"]])
                    req_rank = int(cols[cols_def["rank"]])
                except ValueError:
                    continue
                if req_line == 0:
                    n_skipped_class += 1
                    continue
                if req_rank <= 0:
                    continue
                # Precedence:
                #   - Vanilla-era source (CMaNGOS Classic): GAP-FILL ONLY.
                #     Use setdefault so it never overwrites a value already
                #     supplied by a later-expansion source. CMaNGOS gives
                #     us apprentice-tier Vanilla recipes that AzerothCore
                #     Wrath / TrinityCore Cata strip out; for everything
                #     else, the later source wins (Blizzard occasionally
                #     rebalanced trainer requirements between expansions).
                #   - Later-expansion sources (Wrath / Cata / future MoP):
                #     overwrite freely — last write wins, source order in
                #     SOURCES is oldest-non-vanilla → newest.
                if source.get("expansion") == "vanilla":
                    skill_ranks.setdefault(spell_id, req_rank)
                else:
                    skill_ranks[spell_id] = req_rank
                n_rows += 1
        print(f"  [{source['name']}] absorbed {n_rows:,} (spell, rank) entries "
              f"(skipped {n_skipped_class:,} class-spell rows)", file=sys.stderr)
    print(f"\nTotal trainer skill-rank entries: {len(skill_ranks):,}", file=sys.stderr)
    return skill_ranks


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
