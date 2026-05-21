#!/usr/bin/env python3
"""
TOGProfessionMaster v0.4.6 data port: ProfessionMaster (PM) -> our format.

Reads PM's per-expansion data files and emits our Data/Recipes/*.lua and
Data/Sources/*.lua. Trainer info is NOT in PM's static files (PM discovers
trainers at runtime when the user opens a trainer window). For full trainer
coverage this script needs to be paired with the Wowhead trainer scraper
(scrape_wowhead_trainers.py).

PM source layout (relative to PM's addon root):
    models/skills/{vanilla,bcc,wrath,cata,mop}.lua
        local <expansion>Skills = { [spellId] = { p, itemId, itemAmount,
                                                  reagents, d, r } }
    models/recipe-sources/{vanilla,bcc,wrath,cata,mop}.lua
        local <expansion>Sources = { [itemId] = { vendors = {{npcId, zoneId,
                                                  side}}, drops = {...},
                                                  worldDrop = bool, quests }}

Our target layout:
    Data/Recipes/{Alchemy,Blacksmithing,...}.lua
        addon.recipeDB[profId] = { [spellId] = { difficulty, teaches,
                                                 requiredSkill } }
    Data/Sources/{Alchemy,Blacksmithing,...}.lua
        addon.sourceDB[profId] = { [spellId] = { vendor = {[npcId]=""},
                                                 drop = {[npcId]=""},
                                                 quest = {[questId]=""},
                                                 trainer = {[npcId]=""} } }

Mapping:
    PM["p"]            -> profId (used to bucket into per-profession files)
    PM["d"]            -> difficulty (array of 4)
    PM["d"][1]         -> requiredSkill
    PM["r"]            -> recipeItem (used to look up sources by itemId)
                          and used as `teaches` field — wait, no, the
                          recipe spellId IS the `teaches` field for our
                          format. PM's "r" is the item that teaches the
                          spell. We set teaches = spellId so the
                          knownByChar lookup matches the scanned spell id.
    PM sources         -> our source schema (key transformation: PM keys
                          sources by recipeItem itemId; we key by spellId).
                          Many recipes have no item (trainer-taught only)
                          and won't have a PM source entry; those get an
                          empty placeholder so they still show in the list
                          (the Wowhead scraper fills them in later).
"""

import os
import re
import sys
import pathlib
import textwrap

try:
    from slpp import slpp
except ImportError:
    print("Missing 'slpp'. Install with: python -m pip install slpp", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Resolved relative to where this script lives so the user can run it from
# anywhere.
SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ADDON_ROOT = SCRIPT_DIR.parent
PM_ROOT    = ADDON_ROOT.parent / "ProfessionMaster"
MTSL_ROOT  = ADDON_ROOT.parent / "MissingTradeSkillsList"

# MTSL uses profession-name strings as keys; map to our profIds.
MTSL_NAME_TO_PROF_ID = {
    "Alchemy":        171,
    "Blacksmithing":  164,
    "Cooking":        185,
    "Enchanting":     333,
    "Engineering":    202,
    "First Aid":      129,
    "Fishing":        356,
    "Herbalism":      182,
    "Inscription":    773,
    "Jewelcrafting":  755,
    "Leatherworking": 165,
    "Mining":         186,
    "Skinning":       393,
    "Tailoring":      197,
}

EXPANSIONS = ["vanilla", "bcc", "wrath", "cata", "mop"]

# Profession ID -> our Data/Recipes/<file>.lua name. Matches the existing
# TOC layout. Skinning/Herbalism/Fishing only have output for completeness;
# they have no craftable recipes in PM either.
PROF_FILES = {
    171: "Alchemy",
    164: "Blacksmithing",
    185: "Cooking",
    333: "Enchanting",
    202: "Engineering",
    129: "Firstaid",   # PM uses 129 for First Aid
    356: "Fishing",
    165: "Leatherworking",
    186: "Mining",
    197: "Tailoring",
    755: "Jewelcrafting",
    773: "Inscription",
}


# ---------------------------------------------------------------------------
# Lua-table parser (specific to PM's auto-generated file shape)
# ---------------------------------------------------------------------------

def strip_lua_chrome(src: str) -> str:
    """Strip block comments and pull out just the table value for slpp.

    PM files look like:
        --[[ ... ]]
        -- comments
        local fooSkills = {
            ...
        };
        _G.professionMaster:CreateModel("vanilla-skills", vanillaSkills);

    We want just the `{...}` part. Trailing lines after the table are
    dropped via a brace-counting walk from the first `{` of the top-level
    table.
    """
    # Strip block comments  --[[ ... ]]
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.DOTALL)
    # Strip line comments  -- ...   (PM has no strings outside the table
    # body that contain unescaped `--`, so this is safe for PM files).
    src = re.sub(r"--[^\n]*", "", src)

    # Locate the opening `{` of the first top-level table (right after the
    # first `=` we encounter).
    eq_idx = src.find("=")
    if eq_idx < 0:
        raise ValueError("No `=` found in source")
    brace_start = src.find("{", eq_idx)
    if brace_start < 0:
        raise ValueError("No opening `{` after `=`")

    # Walk the source counting braces. PM files are pure data — no string
    # literals with embedded `{` or `}` — so a naive counter is enough.
    depth = 0
    end = -1
    for i in range(brace_start, len(src)):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end < 0:
        raise ValueError("Unbalanced braces in PM file")
    return src[brace_start:end + 1]


def parse_lua_table(src: str):
    table_src = strip_lua_chrome(src)
    return slpp.decode(table_src)


def load_pm(rel_path: pathlib.Path):
    """Load and parse a PM data file, returning the top-level dict."""
    text = rel_path.read_text(encoding="utf-8")
    return parse_lua_table(text)


# ---------------------------------------------------------------------------
# Conversion logic
# ---------------------------------------------------------------------------

def convert_skills(pm_skills: dict, pm_sources_by_item: dict, recipe_db: dict, source_db: dict, mtsl_trainers: dict | None = None, emulator_trainers_by_spell: dict | None = None):
    """Merge a single expansion's PM data into the per-profession dicts.

    pm_skills:   { spellId: { p, itemId, d, r, ... } } (keys may be int)
    pm_sources_by_item: { itemId: { vendors, drops, quests, worldDrop } }
    recipe_db / source_db: accumulators keyed by profId.
    """
    if not isinstance(pm_skills, dict):
        return
    for spell_id, entry in pm_skills.items():
        if not isinstance(entry, dict):
            continue
        prof_id = entry.get("p")
        diff    = entry.get("d") or []
        # `r` is the item that TEACHES the spell. PM sources are keyed by
        # this item id. None means trainer-taught (no item).
        recipe_item = entry.get("r")

        if prof_id is None or not isinstance(prof_id, (int, float)):
            continue
        prof_id = int(prof_id)
        spell_id_i = int(spell_id)

        # ---- recipeDB ------------------------------------------------------
        # difficulty is a 4-elem array {orange, yellow, green, grey}. PM's
        # `d` already matches this shape when present. requiredSkill is the
        # orange threshold (d[1]).
        if isinstance(diff, dict):
            # slpp returns Lua arrays as 1-keyed dicts. Normalize to a list.
            diff_list = [diff[k] for k in sorted(diff.keys()) if isinstance(k, (int, float))]
        elif isinstance(diff, list):
            diff_list = list(diff)
        else:
            diff_list = []
        required_skill = diff_list[0] if diff_list else 1

        recipe_db.setdefault(prof_id, {})[spell_id_i] = {
            "difficulty":    diff_list,
            "teaches":       spell_id_i,   # we treat the recipe spell as self-teaching
                                            # so the live-scan crafters[charKey]
                                            # lookup matches by spell id.
            "requiredSkill": required_skill,
        }

        # ---- sourceDB ------------------------------------------------------
        # PM keys sources by the recipe ITEM id; we key by spell id. For
        # trainer-taught recipes (no item) PM has no source entry — we
        # emit a placeholder { } table so the recipe still surfaces in the
        # Missing list (HasUsableSource only requires srcEntry non-nil).
        # The Wowhead scraper populates concrete trainer NPC ids later.
        # PM's `r` can be an int (single item) or a list of ints (multiple
        # items teach the same recipe — e.g. drop variants). Normalize to
        # a list and merge sources from all of them.
        target = {}
        recipe_item_ids = []
        if recipe_item is not None:
            if isinstance(recipe_item, (int, float)):
                recipe_item_ids.append(int(recipe_item))
            elif isinstance(recipe_item, dict):
                # slpp returns Lua arrays as 1-keyed dicts
                for k in sorted(recipe_item.keys()):
                    v = recipe_item[k]
                    if isinstance(v, (int, float)):
                        recipe_item_ids.append(int(v))
            elif isinstance(recipe_item, list):
                for v in recipe_item:
                    if isinstance(v, (int, float)):
                        recipe_item_ids.append(int(v))
        for r_item in recipe_item_ids:
            pm_src = pm_sources_by_item.get(r_item)
            if isinstance(pm_src, dict):
                # vendors -> { vendor = {[npcId]=""} }
                vendors = pm_src.get("vendors")
                if isinstance(vendors, dict):
                    npc_map = {}
                    for _, row in vendors.items():
                        if isinstance(row, dict) and row.get(1):
                            npc_map[int(row[1])] = ""
                    if npc_map:
                        target["vendor"] = npc_map
                # drops -> { drop = {[npcId]=""} }
                drops = pm_src.get("drops")
                if isinstance(drops, dict):
                    npc_map = {}
                    for _, row in drops.items():
                        if isinstance(row, dict) and row.get(1):
                            npc_map[int(row[1])] = ""
                    if npc_map:
                        target["drop"] = npc_map
                # quests -> { quest = {[questId]=""} }
                quests = pm_src.get("quests")
                if isinstance(quests, dict):
                    quest_map = {}
                    for _, row in quests.items():
                        if isinstance(row, dict) and row.get(1):
                            quest_map[int(row[1])] = ""
                    if quest_map:
                        target["quest"] = quest_map
                # worldDrop -> { drop = { [-1] = "" } } as a generic "any mob"
                # entry. The Missing tab's FormatSources call only checks
                # the source-type keys, not the inner npcId values, so a
                # placeholder npc id is fine.
                if pm_src.get("worldDrop"):
                    target.setdefault("drop", {})[-1] = ""
        # Layer trainer NPCs from MTSL (Vanilla + TBC + partial Wrath) AND
        # from emulator DB dumps (AzerothCore Wrath today). Both contribute
        # to the union — duplicates are deduped via the dict-key trick.
        # MTSL is keyed by (profId, spellId); emulator data is keyed by
        # spellId alone (profession is implicit). When neither source has
        # data we leave the trainer field absent; downstream HasNonTrainerSource
        # will see vendor/drop/quest from PM as the visibility gate.
        trainer_npcs = set()
        if mtsl_trainers:
            for npc in mtsl_trainers.get(prof_id, {}).get(spell_id_i, ()):
                trainer_npcs.add(int(npc))
        if emulator_trainers_by_spell:
            for npc in emulator_trainers_by_spell.get(spell_id_i, ()):
                trainer_npcs.add(int(npc))
        if trainer_npcs:
            target["trainer"] = {npc: "" for npc in sorted(trainer_npcs)}
        # Union into the accumulator. Each PM expansion file lists the same
        # spell separately (often only vanilla.lua has a populated
        # recipe-source while later expansions repeat the skill with no
        # source mapping). Replacing the accumulator entry would silently
        # drop earlier sources — instead deep-merge field by field.
        prof_slot = source_db.setdefault(prof_id, {})
        existing  = prof_slot.get(spell_id_i)
        if not isinstance(existing, dict):
            prof_slot[spell_id_i] = target
        else:
            for field, sub in target.items():
                if not isinstance(sub, dict) or not sub:
                    continue
                cur_sub = existing.get(field)
                if not isinstance(cur_sub, dict):
                    existing[field] = dict(sub)
                else:
                    for k_npc, v_npc in sub.items():
                        if k_npc not in cur_sub:
                            cur_sub[k_npc] = v_npc


# ---------------------------------------------------------------------------
# Emitter
# ---------------------------------------------------------------------------

def lua_value(value, indent_level: int) -> str:
    """Render a Python value as Lua. Handles nested dicts/lists/scalars."""
    pad = "\t" * indent_level
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if isinstance(value, float) and value.is_integer():
            return str(int(value))
        return str(value)
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, list):
        if not value:
            return "{}"
        parts = [lua_value(v, indent_level + 1) for v in value]
        body = "\n" + "\t" * (indent_level + 1) + (",\n" + "\t" * (indent_level + 1)).join(parts)
        return "{" + body + ",\n" + pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = []
        for k, v in sorted(value.items(), key=lambda kv: (str(type(kv[0])), kv[0])):
            key_repr = f"[{k}]" if isinstance(k, (int, float)) else f'["{k}"]'
            items.append(f"{key_repr} = {lua_value(v, indent_level + 1)}")
        body = "\n" + "\t" * (indent_level + 1) + (",\n" + "\t" * (indent_level + 1)).join(items)
        return "{" + body + ",\n" + pad + "}"
    return "nil"


def parse_existing_lua(target_path: pathlib.Path):
    """Parse our existing Data/{Recipes,Sources}/<Prof>.lua and return the
    inner table dict. Returns {} when the file doesn't exist or doesn't
    contain a parseable assignment.

    Format:
        local _, addon = ...

        addon.recipeDB[171] = { [118] = {...}, ... }
    """
    if not target_path.exists():
        return {}
    text = target_path.read_text(encoding="utf-8")
    try:
        return parse_lua_table(text)
    except Exception as exc:
        print(f"  WARNING: could not parse existing {target_path}: {exc}", file=sys.stderr)
        return {}


def emit_lua_file(target_path: pathlib.Path, db_var: str, prof_id: int, prof_data: dict):
    """Write a single per-profession Data/{Recipes,Sources}/<Prof>.lua,
    merging with whatever is already in the file.

    Recipe entries (db_var == "recipeDB"): PM wins on field values
    (difficulty / requiredSkill / teaches). Spot-checked against MTSL — the
    pre-existing PS-era Vanilla numbers (typically 300/315/330/345 placeholders)
    routinely disagree with PM, MTSL agrees with PM. PS entries that PM does
    NOT have (~1,500 extras) are preserved as-is so we don't lose recipes.

    Source entries (db_var == "sourceDB"): deep-merge the per-source dicts
    (vendor/drop/quest/trainer) by union of keys. PS hand-curated trainer
    NPCs survive; PM/MTSL/emulator data adds on top. New keys win; existing
    NPC ids stay put."""
    existing = parse_existing_lua(target_path)
    merged = {}
    # Normalize existing keys to int (slpp returns numbers as int/float)
    for k, v in (existing or {}).items():
        try:
            merged[int(k)] = v
        except (ValueError, TypeError):
            pass

    added = 0
    is_source = (db_var == "sourceDB")
    for spell_id, entry in prof_data.items():
        if spell_id not in merged:
            merged[spell_id] = entry
            added += 1
        elif is_source and isinstance(entry, dict) and isinstance(merged[spell_id], dict):
            # Deep-merge source fields: union the inner dicts by key.
            cur = merged[spell_id]
            for field in ("vendor", "drop", "quest", "trainer"):
                new_sub = entry.get(field)
                if not isinstance(new_sub, dict) or not new_sub:
                    continue
                cur_sub = cur.get(field)
                if not isinstance(cur_sub, dict):
                    cur[field] = dict(new_sub)
                else:
                    for k_npc, v_npc in new_sub.items():
                        # Coerce npc id keys to int so the Lua output stays
                        # integer-keyed (slpp may have read them as floats).
                        try:
                            k_int = int(k_npc)
                        except (ValueError, TypeError):
                            k_int = k_npc
                        if k_int not in cur_sub:
                            cur_sub[k_int] = v_npc
        elif (not is_source) and isinstance(entry, dict) and isinstance(merged[spell_id], dict):
            # Recipe entries: PM wins on field values. We overwrite difficulty,
            # requiredSkill, and teaches with PM's values; any extra PS-only
            # fields (e.g. legacy reagents metadata) are preserved untouched.
            cur = merged[spell_id]
            for field in ("difficulty", "requiredSkill", "teaches"):
                if field in entry:
                    cur[field] = entry[field]
    body = lua_value(merged, 1)
    contents = f"local _, addon = ...\n\naddon.{db_var}[{prof_id}] = {body}\n"
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(contents, encoding="utf-8")
    return added, len(merged)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_mtsl_trainers():
    """Parse MTSL's data/skills.lua and return a {profId: {spellId: [trainerNpcIds]}}
    map. MTSL covers Vanilla + TBC + partial Wrath skill levels. Returns {}
    when MTSL isn't installed alongside this addon."""
    skills_path = MTSL_ROOT / "data" / "skills.lua"
    if not skills_path.exists():
        print(f"MTSL not found at {skills_path}; skipping trainer-data merge", file=sys.stderr)
        return {}
    text = skills_path.read_text(encoding="utf-8")
    table_src = strip_lua_chrome(text)
    parsed = slpp.decode(table_src)
    if not isinstance(parsed, dict):
        return {}
    out: dict = {}
    for prof_name, skills_list in parsed.items():
        prof_id = MTSL_NAME_TO_PROF_ID.get(prof_name)
        if prof_id is None:
            continue
        # skills_list is a 1-keyed Lua array; slpp returns either a list or
        # a 1-keyed dict depending on shape.
        if isinstance(skills_list, dict):
            entries = [skills_list[k] for k in sorted(skills_list.keys())]
        elif isinstance(skills_list, list):
            entries = list(skills_list)
        else:
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            sid = entry.get("id")
            trainers = entry.get("trainers") if isinstance(entry.get("trainers"), dict) else None
            if sid is None or trainers is None:
                continue
            srcs = trainers.get("sources")
            if isinstance(srcs, dict):
                npcs = [int(srcs[k]) for k in sorted(srcs.keys())
                        if isinstance(srcs[k], (int, float))]
            elif isinstance(srcs, list):
                npcs = [int(v) for v in srcs if isinstance(v, (int, float))]
            else:
                npcs = []
            if npcs:
                out.setdefault(prof_id, {})[int(sid)] = npcs
    return out


def load_emulator_trainers():
    """Load trainer NPC IDs from emulator DB dumps via the sibling
    `extract_emulator_trainers` module. Returns {spellId: [npcId, ...]}
    aggregated across all configured emulator sources.

    Coverage today (v0.4.6): AzerothCore Wrath + TrinityCore Cata Classic.
    Vanilla / TBC / MoP can be added by extending SOURCES in
    extract_emulator_trainers.py — same join logic for normalized schemas,
    a separate parser will be needed for CMaNGOS's flat npc_trainer table
    if we add Vanilla / TBC there. MoP needs a separate emulator fork
    (TrinityCore dropped active MoP support).
    """
    try:
        from extract_emulator_trainers import extract_all
    except ImportError as exc:
        print(f"  extract_emulator_trainers not importable: {exc}", file=sys.stderr)
        return {}
    try:
        return extract_all(refresh=False)
    except Exception as exc:
        print(f"  emulator trainer extraction failed: {exc}; skipping", file=sys.stderr)
        return {}


def main():
    if not PM_ROOT.exists():
        print(f"ProfessionMaster not found at {PM_ROOT}", file=sys.stderr)
        sys.exit(2)

    recipe_db: dict = {}
    source_db: dict = {}
    mtsl_trainers = load_mtsl_trainers()
    if mtsl_trainers:
        total_with_trainers = sum(len(v) for v in mtsl_trainers.values())
        print(f"MTSL trainer data: {total_with_trainers} spell entries across {len(mtsl_trainers)} professions")

    # Emulator trainer data is keyed by spellId only (no profession axis —
    # we look up by spell, the profession is implicit from PM's mapping).
    # AzerothCore covers Wrath; future patches can layer Cata / MoP via
    # TrinityCore and Vanilla / TBC via CMaNGOS.
    emulator_trainers_by_spell = load_emulator_trainers()
    if emulator_trainers_by_spell:
        print(f"Emulator trainer data: {len(emulator_trainers_by_spell)} spells, "
              f"{sum(len(v) for v in emulator_trainers_by_spell.values())} (spell, npc) pairs")

    for exp in EXPANSIONS:
        skills_path  = PM_ROOT / "models" / "skills" / f"{exp}.lua"
        sources_path = PM_ROOT / "models" / "recipe-sources" / f"{exp}.lua"
        print(f"[{exp}] parsing {skills_path.name} + {sources_path.name}")
        skills_data  = load_pm(skills_path)
        sources_data = load_pm(sources_path)
        if not isinstance(skills_data, dict) or not isinstance(sources_data, dict):
            print(f"  WARNING: unexpected top-level shape for {exp}", file=sys.stderr)
            continue
        # PM sources are keyed by item id. Normalize to int keys for lookup.
        sources_by_item = {}
        for k, v in sources_data.items():
            try:
                sources_by_item[int(k)] = v
            except (ValueError, TypeError):
                pass
        convert_skills(skills_data, sources_by_item, recipe_db, source_db,
                       mtsl_trainers, emulator_trainers_by_spell)
        print(f"  -> recipes accumulated for profs: {sorted(recipe_db.keys())}")

    # Emit per-profession files.
    recipes_dir = ADDON_ROOT / "Data" / "Recipes"
    sources_dir = ADDON_ROOT / "Data" / "Sources"

    for prof_id, prof_data in recipe_db.items():
        fname = PROF_FILES.get(prof_id)
        if not fname:
            print(f"  WARNING: no file mapping for profId={prof_id} ({len(prof_data)} recipes dropped)",
                  file=sys.stderr)
            continue
        added, total = emit_lua_file(recipes_dir / f"{fname}.lua", "recipeDB", prof_id, prof_data)
        print(f"  wrote {recipes_dir / f'{fname}.lua'}: +{added} new, {total} total")
    for prof_id, prof_data in source_db.items():
        fname = PROF_FILES.get(prof_id)
        if not fname:
            continue
        added, total = emit_lua_file(sources_dir / f"{fname}.lua", "sourceDB", prof_id, prof_data)
        print(f"  wrote {sources_dir / f'{fname}.lua'}: +{added} new, {total} total")

    print("done.")


if __name__ == "__main__":
    main()
