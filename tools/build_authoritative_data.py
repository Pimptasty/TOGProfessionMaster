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
import re
import sys

SCRIPT_DIR  = pathlib.Path(__file__).resolve().parent
ADDON_ROOT  = SCRIPT_DIR.parent
RECIPES_DIR = ADDON_ROOT / "Data" / "Recipes"

# Reuse the wago.tools fetch helper from the probe script.
sys.path.insert(0, str(SCRIPT_DIR))
from wago_probe import fetch_csv  # type: ignore
from extract_emulator_trainers import extract_all_skill_ranks  # type: ignore

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

# Patterns that mark a Blizzard internal / non-shippable item name. When
# ItemEffect maps a recipe spell to multiple items (e.g. the ZZOLD variant
# kept around for legacy data plus the live version), we must NOT pick the
# obsolete one as the recipe's `itemId` or the in-game UI displays the bad
# name (item 41404 = "ZZOLD Design: Bracing Earthsiege Diamond", etc.).
#
# These tokens were chosen by scanning every shipped `itemId` against
# ItemSparse names — they're the discriminators that show up on confirmed
# obsolete items and never on a live recipe scroll. Conservative on purpose:
# matches must be word-boundary or unique-bracket forms so the filter never
# eats a legitimate item.
_OBSOLETE_NAME_PATTERNS = [
    re.compile(r"\bTEST\b"),          # "59 TEST Green Shaman Chest"
    re.compile(r"\bQA\b"),            # internal QA items
    re.compile(r"\bDEPRECATED\b", re.IGNORECASE),
    re.compile(r"\bUNUSED\b",     re.IGNORECASE),
    re.compile(r"^ZZ",            re.IGNORECASE),  # ZZOLD prefix on legacy gems
    re.compile(r"\[PH\]",         re.IGNORECASE),  # [PH] placeholder marker
    re.compile(r"\bOLD$",         re.IGNORECASE),  # trailing OLD marker
]


def is_obsolete_item_name(name: str) -> bool:
    """True if `name` looks like a Blizzard internal / dev / placeholder item.
    Used to skip such items when picking the `itemId` to ship for a recipe."""
    if not name:
        return False
    for pat in _OBSOLETE_NAME_PATTERNS:
        if pat.search(name):
            return True
    return False


# Lazy-loaded hand-curated overrides for recipes whose requiredSkill isn't
# discoverable from any DBC / emulator source (apprentice auto-grants, quest-
# direct-grants without scroll items, vendor scrolls that fell out of the
# current DBC extract). Wins over every other source — values are
# user-verified against the in-game trainer tooltip or Wowhead. See
# tools/manual_skill_overrides.json for the source-of-truth file.
_MANUAL_SKILL_OVERRIDES = None

def _load_manual_skill_overrides() -> dict:
    global _MANUAL_SKILL_OVERRIDES
    if _MANUAL_SKILL_OVERRIDES is not None:
        return _MANUAL_SKILL_OVERRIDES
    import json
    p = SCRIPT_DIR / "manual_skill_overrides.json"
    if not p.exists():
        _MANUAL_SKILL_OVERRIDES = {}
        return _MANUAL_SKILL_OVERRIDES
    raw = json.loads(p.read_text(encoding="utf-8"))
    # Filter out the metadata key, keep spell_id -> reqSkill
    _MANUAL_SKILL_OVERRIDES = {
        int(k): v["reqSkill"]
        for k, v in raw.items()
        if k.isdigit() and isinstance(v, dict) and "reqSkill" in v
    }
    print(f"  loaded {len(_MANUAL_SKILL_OVERRIDES)} hand-curated requiredSkill overrides from "
          f"manual_skill_overrides.json", file=sys.stderr)
    return _MANUAL_SKILL_OVERRIDES


# Lazy-loaded trainer-rank cache. Built once (across every source) the first
# time extract_recipes_for_build needs it. Subsequent builds reuse — the data
# is build-agnostic (trainers are server-side, not per-client-build).
_TRAINER_SKILL_RANKS = None

def _load_trainer_skill_ranks() -> dict:
    global _TRAINER_SKILL_RANKS
    if _TRAINER_SKILL_RANKS is not None:
        return _TRAINER_SKILL_RANKS
    try:
        _TRAINER_SKILL_RANKS = extract_all_skill_ranks(refresh=False)
    except Exception as exc:
        print(f"  trainer skill-ranks extraction failed: {exc}; "
              f"trainer-taught requiredSkill will fall back to SLA heuristic",
              file=sys.stderr)
        _TRAINER_SKILL_RANKS = {}
    return _TRAINER_SKILL_RANKS


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
    item_sparse  = fetch_csv("ItemSparse",       build, refresh=refresh)
    spell_effects = fetch_csv("SpellEffect",     build, refresh=refresh)

    # Trainer skill-ranks (build-agnostic; loads from emulator SQL the
    # first time and caches). Used downstream as the authoritative source
    # for trainer-taught recipes' requiredSkill.
    trainer_skill_ranks = _load_trainer_skill_ranks()

    # Hand-curated manual overrides — top priority for requiredSkill.
    manual_skill_overrides = _load_manual_skill_overrides()

    # ItemSparse indices —
    #   name_by_item:        used to filter obsolete recipe-scroll items
    #                        (ZZOLD/TEST/DEPRECATED) out of items_by_spell
    #                        before we pick items[0] as the shipped `itemId`.
    #   skill_rank_by_item:  RequiredSkillRank from the scroll's
    #                        ItemSparse row — this IS the literal "Requires
    #                        Blacksmithing (175)" / "Requires Tailoring
    #                        (300)" value the in-game tooltip shows. Used
    #                        downstream to ship an authoritative requiredSkill
    #                        for scroll-taught recipes; falls back to the
    #                        SLA TrivialSkillLineRankLow heuristic for
    #                        trainer-taught recipes that have no scroll.
    name_by_item = {}
    skill_rank_by_item = {}
    for row in item_sparse:
        try:
            iid = int(row.get("ID") or 0)
        except (TypeError, ValueError):
            continue
        nm = row.get("Display_lang") or row.get("Name_lang") or ""
        if iid and nm:
            name_by_item[iid] = nm
        try:
            rank = int(row.get("RequiredSkillRank") or 0)
            if iid and rank > 0:
                skill_rank_by_item[iid] = rank
        except (TypeError, ValueError):
            continue

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
    n_skipped_obsolete = 0
    for row in item_effects:
        try:
            sid = int(row.get("SpellID") or row.get("Spell") or 0)
            iid = int(row.get("ParentItemID") or row.get("ItemID") or 0)
            if sid and iid:
                # Skip ZZOLD/TEST/DEPRECATED variants — see _OBSOLETE_NAME_PATTERNS.
                # The live recipe scroll for the same spell stays in the set.
                if is_obsolete_item_name(name_by_item.get(iid, "")):
                    n_skipped_obsolete += 1
                    continue
                items_by_spell.setdefault(sid, set()).add(iid)
        except (TypeError, ValueError, KeyError):
            continue

    # Recipe-scroll name-match supplemental linker.
    #
    # ItemEffect only contains direct spell-teach mappings — but many WoW
    # recipe scrolls implement their teaching via a generic "Learning" spell
    # (spell 483) whose effect is then chained server-side to grant the
    # specific craft spell. ItemEffect captures the item→Learning link, not
    # the item→specific-craft link. As a result our items_by_spell map
    # misses ~80-100 recipes per profession whose scrolls exist but aren't
    # directly linked in DBC.
    #
    # Workaround: WoW's recipe scroll items follow a predictable naming
    # convention — "Pattern: <CraftName>" for Tailoring/LW, "Plans: ..."
    # for BS, "Recipe: ..." for Alchemy/Cooking/FA, "Formula: ..." for
    # Enchanting, "Schematic: ..." for Engineering, "Design: ..." for JC,
    # "Manual: ..." for some FA, "Technique: ..." for Inscription. Strip
    # the prefix and the remainder exactly matches the craft spell's name
    # in SpellName. Cross-validated at 97% hit rate on Vanilla data
    # (1,047 of 1,082 recipe scrolls match a spell by stripped name).
    #
    # When the same spell name appears multiple times (e.g. rank variants
    # of an enchant), we associate the scroll with the first matching
    # spell — same convention as items[0] downstream. Misses (35 in
    # Vanilla) are mostly singular/plural mismatches, legacy "Imbue X"
    # naming, and skill-rank books which aren't recipes.
    spell_by_name: dict[str, list[int]] = {}
    for sid, sname in name_by_spell.items():
        if sname:
            spell_by_name.setdefault(sname, []).append(sid)

    SCROLL_PREFIXES = (
        "Pattern: ", "Plans: ", "Recipe: ", "Formula: ",
        "Schematic: ", "Design: ", "Manual: ", "Technique: ",
    )
    n_name_match = 0
    n_name_match_new = 0
    n_name_unmatched = 0
    for iid, iname in name_by_item.items():
        if is_obsolete_item_name(iname):
            continue
        for pfx in SCROLL_PREFIXES:
            if iname.startswith(pfx):
                craft_name = iname[len(pfx):]
                matched_spells = spell_by_name.get(craft_name)
                if matched_spells:
                    n_name_match += 1
                    for sp in matched_spells:
                        bucket = items_by_spell.setdefault(sp, set())
                        if iid not in bucket:
                            bucket.add(iid)
                            n_name_match_new += 1
                else:
                    n_name_unmatched += 1
                break
    print(f"  recipe-scroll name-match: {n_name_match:,} scrolls matched "
          f"({n_name_match_new:,} new spell-scroll links), "
          f"{n_name_unmatched:,} unmatched (edge cases / non-recipe books)",
          file=sys.stderr)
    if n_skipped_obsolete:
        print(f"  skipped {n_skipped_obsolete} obsolete item-teach rows "
              f"(ZZOLD/TEST/DEPRECATED variants)", file=sys.stderr)

    # SpellEffect[Effect=24] = "Create Item". For each craft spell, the
    # EffectItemType column gives the item id the spell produces. We ship
    # this as `craftedItemId` so the runtime UI (icon resolution, tooltip
    # link, etc.) has a reliable handle to the produced item even for
    # trainer-taught recipes that have no scroll item. Without it, the
    # Missing Recipes tab fell back to GetSpellTexture for trainer-only
    # rows, which Blizzard often assigned generic placeholder textures
    # (the "funky icon" the user kept seeing for Heavy Weightstone,
    # Coarse Sharpening Stone, etc.).
    #
    # Some spells have multiple Effect=24 rows (multi-output crafts).
    # Take the first one — that's the primary output. Filter obsolete
    # items here too so we never tag a craftedItemId pointing at a
    # ZZOLD/TEST item even when those are the spell's primary output.
    created_item_by_spell: dict[int, int] = {}
    for row in spell_effects:
        try:
            effect = int(row.get("Effect") or 0)
            if effect != 24:  # CREATE_ITEM
                continue
            sid = int(row.get("SpellID") or 0)
            iid = int(row.get("EffectItemType") or 0)
            if sid and iid and sid not in created_item_by_spell:
                if not is_obsolete_item_name(name_by_item.get(iid, "")):
                    created_item_by_spell[sid] = iid
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

            # requiredSkill — ONLY authoritative sources, in priority order:
            #
            # 0. Hand-curated manual override (manual_skill_overrides.json) —
            #    user-verified value for recipes whose data isn't in any DBC
            #    or emulator source (apprentice auto-grants, quest-direct-
            #    grants, removed-from-DBC vendor scrolls). Highest priority
            #    so the maintainer can correct any of the lower-tier
            #    sources by adding an entry to the JSON file.
            #
            # 1. Recipe-scroll ItemSparse.RequiredSkillRank — the LITERAL
            #    "Requires Blacksmithing (175)" / "Requires Tailoring (300)"
            #    value the in-game tooltip shows on the scroll. Blizzard
            #    sets it per-scroll and the game uses it to gate learning.
            #
            # 2. Trainer SQL `trainer_spell.ReqSkillRank` — the LITERAL
            #    "Requires Blacksmithing (100)" value the TRAINER NPC
            #    enforces when teaching the spell. Sourced from
            #    AzerothCore Wrath + TrinityCore Cata trainer SQL.
            #
            # If neither source has data, requiredSkill = None. The
            # downstream emitter omits the field and the runtime UI shows
            # "-" so the gap is visible and we can fill it later. We do
            # NOT fall back to SLA MinSkillLineRank or
            # TrivialSkillLineRankLow ("green" threshold) — both run 0-10
            # points off the real learn requirement for many recipes
            # (e.g. Coarse Sharpening Stone: MinSkillLineRank=75, trainer
            # SQL=65; Silver Rod: MinSkillLineRank=1 placeholder,
            # green=105, trainer SQL=100). Shipping those heuristic
            # values masks the data gap and produces a false sense of
            # accuracy in the UI.
            scroll_items = sorted(items_by_spell.get(spell_id, set()))
            scroll_rank = None
            for sid_item in scroll_items:
                r = skill_rank_by_item.get(sid_item)
                if r:
                    scroll_rank = r
                    break
            trainer_rank = trainer_skill_ranks.get(spell_id)
            manual_override = manual_skill_overrides.get(spell_id)
            # Priority: manual > scroll > trainer > None
            required_skill = manual_override or scroll_rank or trainer_rank

            recipes[spell_id] = {
                "name":           name_by_spell.get(spell_id, ""),
                "difficulty":     difficulty,
                "teaches":        spell_id,  # self-teaching; scanner returns spell id
                "requiredSkill":  required_skill,
                "reagents":       reagents_by_spell.get(spell_id, {}),
                "items":          sorted(items_by_spell.get(spell_id, set())),
                "craftedItemId":  created_item_by_spell.get(spell_id),
                "expansion":      build,
            }
        out[prof_id] = recipes
    return out


# ---------------------------------------------------------------------------
# Cross-expansion merge
# ---------------------------------------------------------------------------

def merge_expansions(per_build_data: list[dict]) -> dict:
    """Union across all expansion builds. Latest expansion wins on field values
    (a Wrath-rebalanced recipe carries Wrath's difficulty into the merged DB;
    a Cata further rebalance overwrites it; MoP overwrites Cata).

    Each recipe also gets a `minExpansion` field — the index of the earliest
    build (1=Vanilla, 2=TBC, 3=Wrath, 4=Cata, 5=MoP) where the spell first
    appeared in SkillLineAbility. The addon filters on this at runtime to
    block cross-expansion bleed: a Wrath-introduced recipe with
    `minExpansion=3` is hidden on TBC clients (CLIENT_EXP=2) regardless of
    whatever requiredSkill / phase data it carries. This catches the bug
    where wago.tools' MoP build inherits every spell ever shipped — a Wrath
    transmute like 53771 was leaking into TBC's data because we unioned
    forward but had no per-expansion gate at runtime.

    The merge order is the order of per_build_data, which matches the
    EXPANSION_BUILDS list (oldest → newest, hence index 1..5).
    """
    merged: dict = {}
    for build_idx, build_data in enumerate(per_build_data, start=1):
        for prof_id, recipes in build_data.items():
            slot = merged.setdefault(prof_id, {})
            for spell_id, entry in recipes.items():
                if spell_id in slot:
                    # Preserve the earlier minExpansion across the overwrite.
                    prior_min = slot[spell_id].get("minExpansion", build_idx)
                    slot[spell_id] = dict(entry)
                    slot[spell_id]["minExpansion"] = prior_min
                else:
                    slot[spell_id] = dict(entry)
                    slot[spell_id]["minExpansion"] = build_idx
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


# Hand-curated exclusion list. Recipes in wago.tools / DBC data that were
# never actually obtainable in the live game across any expansion — planned-
# but-cut content, leftover dev test entries, etc. Each entry needs a
# `# source` comment documenting why we know it shouldn't ship. Without
# the comment the line is just noise; without a citation the next
# maintainer can't audit whether the entry is still correct.
#
# Filter applied at emit time in emit_recipe_file — these spells never
# appear in any client's recipeDB, so the Missing tab never tries to
# display them. Add to this list when a user reports a recipe that
# shouldn't exist; verify against Wowhead / wowwiki / community
# documentation before adding.
MANUAL_EXCLUDED_SPELLS = {
    22430,   # Alchemy "Refined Scale of Onyxia" — planned for Vanilla AQ40
             # but never implemented (would have bottlenecked Onyxia loot
             # turn-ins). Verified non-obtainable via Wowhead comments and
             # community reports. User-reported on TBC Anniversary Phase 2.
    22434,   # Enchanting "Charged Scale of Onyxia" — sibling never-shipped
             # Onyxia-scale enchant. Same provenance as 22430.
             # User-reported on TBC Anniversary Phase 2 (Galdof, 2026-05).
    11447,   # Alchemy "Elixir of Waterwalking" — DBC says Alchemy but Wowhead
             # community confirms this is actually a daily quest reward, not
             # an Alchemy craft. Filtering out so it doesn't pollute the
             # Alchemy Missing list. User-reported (Galdof, 2026-05).
    # Engineering never-implemented recipes — DBC has them but they were
    # cut before going live. User-reported (Galdof, 2026-05) on TBC Anniversary.
    12719,   # "Explosive Arrow"
    12720,   # name truncated in DBC ("Goblin \") — placeholder, never shipped
    12722,   # "Goblin Radio"
    12900,   # "Mobile Alarm"
    12904,   # "Gnomish Ham Radio"
    30561,   # "Goblin Tonk Controller"
    30573,   # "Gnomish Tonk Controller"
}


# Lazy-loaded phase map keyed by spellId -> phase int. Populated from
# tools/wago_cache/att_phase_map.json (produced by att_extract_phase.py).
# Currently only TBC entries are present; recipes not in the map have no
# `phase` field emitted and the addon treats them as Phase 1 (always-show).
_PHASE_MAP = None


def _load_phase_map():
    global _PHASE_MAP
    if _PHASE_MAP is not None:
        return _PHASE_MAP
    import json
    p = SCRIPT_DIR / "wago_cache" / "att_phase_map.json"
    if not p.exists():
        print(f"  no att_phase_map.json found; recipes will ship without "
              f"`phase` field. Run tools/att_extract_phase.py first to "
              f"enable TBC Anniversary phase filtering.", file=sys.stderr)
        _PHASE_MAP = {}
        return _PHASE_MAP
    raw = json.loads(p.read_text(encoding="utf-8"))
    _PHASE_MAP = {int(k): v for k, v in (raw.get("spell_phase") or {}).items()}
    print(f"  loaded {len(_PHASE_MAP)} phase tags from {p.name}", file=sys.stderr)
    return _PHASE_MAP


def emit_recipe_file(prof_id: int, filename: str, recipes: dict):
    """Write Data/Recipes/<filename>.lua. The recipe entries include the
    new `name` field which the existing addon doesn't use today — adding it
    is forward-compatible since Lua tables ignore extra fields.

    We strip the helper-only fields (`items`, `expansion`) before emit since
    they're for the importer's downstream Source-DB pass, not the runtime
    recipe DB.

    When ATT's phase map is available (att_extract_phase.py output), each
    recipe gets a `phase` field for client-side content-phase filtering.
    Only TBC has phase data today; other expansions get no `phase` field
    and the addon's filter treats them as always-visible."""
    phase_map = _load_phase_map()
    cleaned = {}
    n_skipped_non_recipe = 0
    n_skipped_manual_exclude = 0
    for spell_id, entry in recipes.items():
        # Hand-curated exclusion list (planned-but-never-shipped recipes,
        # etc.) — see MANUAL_EXCLUDED_SPELLS at top of file.
        if spell_id in MANUAL_EXCLUDED_SPELLS:
            n_skipped_manual_exclude += 1
            continue
        # itemId = first recipe-scroll item that teaches this spell, or nil
        # for trainer-only recipes (no scroll exists in the game). Used by
        # GUI/MissingRecipesTab.lua for tooltip / icon / shift-click link
        # — those all need an ACTUAL item id, not the spell id (the spell
        # tooltip alone doesn't render reagents the way the recipe-scroll
        # item tooltip does). When nil, the GUI falls back to spell-based
        # display (GetSpellInfo / GameTooltip:SetSpellByID).
        items    = entry.get("items") or []
        reagents = entry.get("reagents") or {}

        # SkillLineAbility includes EVERY spell in a profession's skill line,
        # which is wider than just craftable recipes — it also covers
        # skill-rank-up spells (Apprentice/Journeyman/Expert Alchemy, etc.),
        # specialisation spells, gathering toggles like "Find Minerals", and
        # other utility spells the trainer hands out. Those aren't recipes
        # the user can "be missing" in any meaningful way. Filter them out
        # by the only signal that cleanly separates a craftable recipe from
        # everything else in SkillLineAbility: a real recipe either has at
        # least one reagent (every craft needs materials) OR is taught by
        # a recipe-scroll item (Pattern: / Plans: / Recipe: / Formula: /
        # Design: / Schematic:). Anything missing BOTH is not a craftable.
        if not reagents and not items:
            n_skipped_non_recipe += 1
            continue

        out = {
            "name":       entry["name"],
            "difficulty": entry["difficulty"],
            "teaches":    entry["teaches"],
            "reagents":   reagents,
        }
        # requiredSkill is omitted entirely when None — see comment in
        # extract_recipes_for_build. Runtime treats absent as "unknown"
        # and renders "-" in the UI so the gap is visible.
        if entry.get("requiredSkill"):
            out["requiredSkill"] = entry["requiredSkill"]
        if items:
            out["itemId"] = items[0]
        # craftedItemId: the item produced BY the craft spell (from
        # SpellEffect[Effect=24].EffectItemType). Distinct from itemId
        # (which is the recipe-scroll item). Lets the runtime UI render
        # the produced item's icon / link for trainer-taught crafts that
        # have no scroll. Skip when equal to itemId — saves bytes and
        # prevents downstream code from double-handling the same value.
        crafted = entry.get("craftedItemId")
        if crafted and crafted != out.get("itemId"):
            out["craftedItemId"] = crafted
        phase = phase_map.get(spell_id)
        if phase and phase > 1:
            # Only emit `phase` when it's beyond Phase 1 (the default).
            # Recipes without a phase entry — or tagged Phase 1 — get no
            # field and the addon treats them as always-visible.
            out["phase"] = phase
        # minExpansion: earliest build index (1=Vanilla..5=MoP) where the
        # spell first appeared. Set by merge_expansions. Emit only when
        # > 1 since Vanilla-origin recipes show on every client by default
        # and the absent-field check is cheaper than `entry.minExpansion <= 1`.
        min_exp = entry.get("minExpansion")
        if min_exp and min_exp > 1:
            out["minExpansion"] = min_exp
        cleaned[spell_id] = out
    if n_skipped_non_recipe:
        print(f"  {prof_id}: skipped {n_skipped_non_recipe} non-recipe spells "
              f"(rank-ups / specs / utility)", file=sys.stderr)
    if n_skipped_manual_exclude:
        print(f"  {prof_id}: skipped {n_skipped_manual_exclude} manually-excluded "
              f"spells (never-implemented content)", file=sys.stderr)
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
