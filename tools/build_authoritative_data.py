#!/usr/bin/env python3
"""v0.5.0 authoritative data builder — replaces the PM port (port_pm_data.py).

Reads wago.tools DBC tables for each Classic expansion build and emits our
Data/Recipes/*.lua. Each output entry is sourced 100% from Blizzard's actual
client database — no crowd-sourced PM data, no MTSL approximations.

Recipe universe per expansion (validated by tools/wago_probe.py):
    Vanilla  1.15.8.67156  →  1,648 recipes across 11 professions
    TBC      2.5.5.67511   →  (TBA — Anniversary build, similar to Vanilla+TBC)
    Wrath    3.4.5.63697   →  3,721 recipes
    Cata     4.4.2.60895   →  4,417 recipes
    MoP      5.5.3.67509   →  5,477 recipes  (current upper bound)

Output strategy (first cut): UNION across all 5 expansions into a single
Data/Recipes/<Prof>.lua per profession. The same Data/ tree is loaded by every
TOC variant, matching the addon's current single-DB shape. Latest-expansion
wins on difficulty / requiredSkill (MoP rebalance is the authoritative current
gameplay value). Per-expansion output trees can be added later for clients
that want to scope to their content (e.g. hide MoP recipes from Vanilla users).

Source data (vendor / drop / quest / trainer) is Phase B — added in a separate
pass that reads TrinityCore Cata TDB + AzerothCore Wrath world DBs and emits
Data/Sources/*.lua. This file only touches Data/Recipes/.

Re-run safe: caches wago.tools CSVs in tools/wago_cache/. Pass --refresh to
force re-download.
"""

import argparse
import pathlib
import sys

SCRIPT_DIR  = pathlib.Path(__file__).resolve().parent
ADDON_ROOT  = SCRIPT_DIR.parent
RECIPES_DIR = ADDON_ROOT / "Data" / "Recipes"

# Reuse the wago.tools fetch helper from the probe script.
sys.path.insert(0, str(SCRIPT_DIR))
from wago_probe import fetch_csv  # type: ignore

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Build IDs validated against wago.tools /api/builds. Listed oldest -> newest;
# the merge order matters because later expansions overwrite earlier values for
# difficulty / required skill (recipes get rebalanced across expansions).
EXPANSION_BUILDS = [
    ("Vanilla", "1.15.8.67156"),
    ("TBC",     "2.5.5.67511"),
    ("Wrath",   "3.4.5.63697"),
    ("Cata",    "4.4.2.60895"),
    ("MoP",     "5.5.3.67509"),
]

# Profession ID -> (output filename, [extra skill line IDs]).
# A handful of professions have sub-skill lines that produce recipes shown
# under the primary profession's UI (Mining is the canonical case: gathering
# is skill 186, smelting is skill 2575, but both surface as "Mining" recipes
# in-game). Add sub-skills here so they land in the same output file.
PROF_FILES = {
    164: ("Blacksmithing",  []),
    165: ("Leatherworking", []),
    171: ("Alchemy",        []),
    185: ("Cooking",        []),
    186: ("Mining",         [2575]),    # +Smelting
    197: ("Tailoring",      []),
    202: ("Engineering",    []),
    333: ("Enchanting",     []),
    129: ("Firstaid",       []),         # matches existing TOC filename
    356: ("Fishing",        []),
    755: ("Jewelcrafting",  []),
    773: ("Inscription",    []),
    # Herbalism (182) and Skinning (393) are gathering only — current
    # addon doesn't ship Data files for them. Skip unless the user adds
    # them to PROF_NAMES on the Lua side.
}


# ---------------------------------------------------------------------------
# Per-expansion recipe extraction
# ---------------------------------------------------------------------------

def extract_recipes_for_build(build: str, refresh: bool = False) -> dict:
    """Pull every recipe for every profession in PROF_FILES from one build.

    Returns:
        {profId: {spellId: {
            name, difficulty=[orange,yellow,green,grey], requiredSkill,
            reagents={[itemId]=count}, items=[recipe item ids], expansion=<build>
        }}}
    """
    print(f"  fetching DBC tables for build {build}", file=sys.stderr)
    sla          = fetch_csv("SkillLineAbility", build, refresh=refresh)
    spell_names  = fetch_csv("SpellName",        build, refresh=refresh)
    spell_reag   = fetch_csv("SpellReagents",    build, refresh=refresh)
    item_effects = fetch_csv("ItemEffect",       build, refresh=refresh)

    # Index by spellId so per-recipe joins are O(1).
    name_by_spell = {}
    for row in spell_names:
        try:
            name_by_spell[int(row["ID"])] = row.get("Name_lang", "")
        except (TypeError, ValueError, KeyError):
            continue

    reagents_by_spell = {}
    for row in spell_reag:
        try:
            sid = int(row.get("SpellID") or 0)
            if not sid: continue
            r = {}
            for i in range(8):
                iid = int(row.get(f"Reagent_{i}") or 0)
                cnt = int(row.get(f"ReagentCount_{i}") or 0)
                if iid and cnt:
                    r[iid] = cnt
            if r:
                reagents_by_spell[sid] = r
        except (TypeError, ValueError):
            continue

    items_by_spell: dict[int, set[int]] = {}
    for row in item_effects:
        try:
            sid = int(row.get("SpellID") or row.get("Spell") or 0)
            iid = int(row.get("ParentItemID") or row.get("ItemID") or 0)
            if sid and iid:
                items_by_spell.setdefault(sid, set()).add(iid)
        except (TypeError, ValueError, KeyError):
            continue

    # Build the per-profession recipe dicts.
    out: dict = {}
    for prof_id, (_filename, sub_skills) in PROF_FILES.items():
        skill_lines_for_prof = {prof_id} | set(sub_skills)
        recipes = {}
        for row in sla:
            try:
                sl = int(row.get("SkillLine") or 0)
                if sl not in skill_lines_for_prof:
                    continue
                spell_id = int(row["Spell"])
                min_rank  = int(row.get("MinSkillLineRank") or 0)
                # Three more thresholds (yellow / green / grey). Schemas vary:
                # SkillLineAbility historically has TrivialSkillLineRankHigh
                # (grey) and TrivialSkillLineRankLow (green). Yellow is
                # interpolated by Blizzard at runtime; we approximate it.
                grey   = int(row.get("TrivialSkillLineRankHigh") or 0)
                green  = int(row.get("TrivialSkillLineRankLow")  or 0)
                # Yellow is midway between min and green (Blizzard's heuristic
                # for the colour-cap when neither field is set explicitly).
                yellow = (min_rank + green) // 2 if green > min_rank else min_rank
                difficulty = [min_rank, yellow, green, grey]
            except (TypeError, ValueError, KeyError):
                continue

            recipes[spell_id] = {
                "name":          name_by_spell.get(spell_id, ""),
                "difficulty":    difficulty,
                "teaches":       spell_id,  # self-teaching; scanner returns spell id
                "requiredSkill": min_rank,
                "reagents":      reagents_by_spell.get(spell_id, {}),
                "items":         sorted(items_by_spell.get(spell_id, set())),
                "expansion":     build,
            }
        out[prof_id] = recipes
    return out


# ---------------------------------------------------------------------------
# Cross-expansion merge
# ---------------------------------------------------------------------------

def merge_expansions(per_build_data: list[dict]) -> dict:
    """Union across all expansion builds. Latest expansion wins on field values
    (a Wrath-rebalanced recipe carries Wrath's difficulty into the merged DB;
    a Cata further rebalance overwrites it; MoP overwrites Cata). The merge
    order is determined by the order of per_build_data, which matches the
    EXPANSION_BUILDS list (oldest → newest).
    """
    merged: dict = {}
    for build_data in per_build_data:
        for prof_id, recipes in build_data.items():
            slot = merged.setdefault(prof_id, {})
            for spell_id, entry in recipes.items():
                slot[spell_id] = entry  # last-wins
    return merged


# ---------------------------------------------------------------------------
# Lua emitter
# ---------------------------------------------------------------------------

def lua_value(v, indent_level: int) -> str:
    """Render a Python value as a Lua literal (int/float/string/table)."""
    pad = "\t" * indent_level
    inner = "\t" * (indent_level + 1)
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        esc = v.replace("\\", "\\\\").replace("\"", "\\\"")
        return '"' + esc + '"'
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        # Numeric-indexed: emit as positional Lua array.
        items = ",\n".join(inner + lua_value(item, indent_level + 1) for item in v)
        return "{\n" + items + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        # Sorted for deterministic diff-friendly output.
        def sort_key(kv):
            k = kv[0]
            return (0, k) if isinstance(k, (int, float)) else (1, str(k))
        rendered = []
        for k, val in sorted(v.items(), key=sort_key):
            if isinstance(k, (int, float)):
                key_str = f"[{int(k)}]"
            else:
                key_str = '["' + str(k).replace('"', '\\"') + '"]'
            rendered.append(f"{inner}{key_str} = {lua_value(val, indent_level + 1)}")
        return "{\n" + ",\n".join(rendered) + ",\n" + pad + "}"
    raise TypeError(f"cannot serialise {type(v).__name__} to Lua")


def emit_recipe_file(prof_id: int, filename: str, recipes: dict):
    """Write Data/Recipes/<filename>.lua. The recipe entries include the
    new `name` field which the existing addon doesn't use today — adding it
    is forward-compatible since Lua tables ignore extra fields.

    We strip the helper-only fields (`items`, `expansion`) before emit since
    they're for the importer's downstream Source-DB pass, not the runtime
    recipe DB."""
    cleaned = {}
    for spell_id, entry in recipes.items():
        # itemId = first recipe-scroll item that teaches this spell, or nil
        # for trainer-only recipes (no scroll exists in the game). Used by
        # GUI/MissingRecipesTab.lua for tooltip / icon / shift-click link
        # — those all need an ACTUAL item id, not the spell id (the spell
        # tooltip alone doesn't render reagents the way the recipe-scroll
        # item tooltip does). When nil, the GUI falls back to spell-based
        # display (GetSpellInfo / GameTooltip:SetSpellByID).
        items = entry.get("items") or []
        out = {
            "name":          entry["name"],
            "difficulty":    entry["difficulty"],
            "teaches":       entry["teaches"],
            "requiredSkill": entry["requiredSkill"],
            "reagents":      entry["reagents"],
        }
        if items:
            out["itemId"] = items[0]
        cleaned[spell_id] = out
    body = lua_value(cleaned, 1)
    target = RECIPES_DIR / f"{filename}.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        "local _, addon = ...\n"
        "\n"
        f"addon.recipeDB[{prof_id}] = {body}\n"
    )
    target.write_text(contents, encoding="utf-8")
    return len(cleaned), target


# ---------------------------------------------------------------------------
# Side-info dump for the source-DB pass (Phase B)
# ---------------------------------------------------------------------------

def emit_recipe_items_map(merged: dict):
    """Write tools/wago_cache/recipe_items_map.json — a JSON snapshot of
    {profId: {spellId: [recipe item ids]}} that the upcoming source-DB pass
    needs to convert TDB item-vendored / item-looted rows into spell-keyed
    source entries.

    JSON instead of Lua so the source-DB script can ingest it directly with
    json.load — keeps the two phases decoupled."""
    import json
    out = {}
    for prof_id, recipes in merged.items():
        out[str(prof_id)] = {
            str(spell_id): entry["items"]
            for spell_id, entry in recipes.items()
            if entry["items"]
        }
    target = SCRIPT_DIR / "wago_cache" / "recipe_items_map.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"\n  wrote {target.relative_to(ADDON_ROOT)} for Phase B input")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--refresh", action="store_true",
                    help="Force re-download cached wago.tools CSVs.")
    ap.add_argument("--builds", nargs="+", default=None,
                    help="Subset of expansion labels to merge "
                         "(default: all). Example: --builds Cata MoP")
    args = ap.parse_args()

    builds = EXPANSION_BUILDS
    if args.builds:
        wanted = set(b.lower() for b in args.builds)
        builds = [(label, bid) for (label, bid) in EXPANSION_BUILDS
                  if label.lower() in wanted]
        if not builds:
            print(f"No builds matched {args.builds}", file=sys.stderr)
            sys.exit(2)

    print(f"== Authoritative Data Builder ==", file=sys.stderr)
    print(f"   builds: {[b[0] for b in builds]}", file=sys.stderr)

    per_build = []
    for label, build_id in builds:
        print(f"\n[{label}] build {build_id}", file=sys.stderr)
        per_build.append(extract_recipes_for_build(build_id, refresh=args.refresh))

    merged = merge_expansions(per_build)

    # Per-profession emit + report.
    print(f"\n=== Emitting Data/Recipes/*.lua ===")
    print(f"{'profession':<18} {'recipes':>8}  {'output'}")
    total = 0
    for prof_id, (filename, _) in sorted(PROF_FILES.items(), key=lambda kv: kv[1][0]):
        recipes = merged.get(prof_id, {})
        count, path = emit_recipe_file(prof_id, filename, recipes)
        total += count
        print(f"{filename:<18} {count:>8}  {path.relative_to(ADDON_ROOT)}")
    print(f"{'TOTAL':<18} {total:>8}")

    # Stash the recipe-item linkage for Phase B (source DB builder).
    emit_recipe_items_map(merged)


if __name__ == "__main__":
    main()
