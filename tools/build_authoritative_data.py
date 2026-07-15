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

# Profession-specialization spells. A spec-locked recipe scroll carries the
# required spec as ItemSparse.RequiredAbility (e.g. Pattern: Molten Helm ->
# 10658 Elemental Leatherworking). That id is the SAME spell IsSpellKnown
# returns for the spec, so the addon can compare `requiredSpec` directly
# against gdb.specializations. We whitelist the real spec spells here so that
# any OTHER (non-spec) RequiredAbility never becomes a requiredSpec and wrongly
# hides a recipe. Keep in sync with SPEC_SPELLS in Scanner.lua.
SPEC_ABILITIES = {
    10656, 10658, 10660,               # Leatherworking: Dragonscale / Elemental / Tribal
    9788, 9787, 17039, 17040, 17041,   # Blacksmithing: Armorsmith / Weaponsmith / Sword / Hammer / Axe
    20219, 20222,                      # Engineering: Gnomish / Goblin
    26797, 26798, 26801,               # Tailoring: Spellfire / Mooncloth / Shadoweave (26802 was "Detect Amore" — a holiday spell, never Mooncloth)
}

# Build labels whose recipes are still gated by a profession specialization.
# The LW/BS/Engineering/Tailoring specs existed Vanilla..Wrath and were removed
# by patch 4.0.1 (Cata), so Cata/MoP recipes have NO spec requirement.
SPEC_ACTIVE_BUILDS = {"Vanilla", "TBC", "Wrath"}


def build_spec_map(build: str, refresh: bool = False) -> dict:
    """{ itemId -> spec spell } from a build's ItemSparse.RequiredAbility, limited
    to real profession-spec spells (SPEC_ABILITIES). Only the Vanilla DBC extract
    reliably populates RequiredAbility on these Vanilla-era patterns — the TBC and
    Wrath extracts zero it out even though the spec still gated the recipe then —
    so we compute the map from Vanilla once and reuse it for every pre-Cata build."""
    out = {}
    for row in fetch_csv("ItemSparse", build, refresh=refresh):
        try:
            iid = int(row.get("ID") or 0)
            req = int(row.get("RequiredAbility") or 0)
        except (TypeError, ValueError):
            continue
        if iid and req in SPEC_ABILITIES:
            out[iid] = req
    return out


# ---------------------------------------------------------------------------
# Effect text (enrichment for description search)
# ---------------------------------------------------------------------------

# NOTE: We deliberately do NOT enrich crafted *gear* with a synthetic stat
# string. The live client already renders the real item tooltip (with the
# authoritative, current stats) for any created item, so a parallel
# ItemSparse-derived "+N Stat" line was both redundant and prone to drift
# (the StatModifier columns don't always match what the client shows). Only
# *enchants* get an `effect` string — enchants have no item to hover, so the
# SpellItemEnchantment name is the only searchable description of what they do.


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


# Locales to build into ProfessionDB beyond the canonical enUS pass. enGB is a
# WoW client locale but its game text == enUS, so we mirror enUS rather than
# fetch it. These are the official client locales wago.tools serves.
EXTRA_LOCALES = ["deDE", "esES", "esMX", "frFR", "itIT",
                 "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]
MIRROR_LOCALES = {"enGB": "enUS"}   # locale -> source locale whose strings it copies

_ENCH_PH   = re.compile(r"\$(\d*)[a-zA-Z](\d)")
_ENCH_JUNK = re.compile(r"\$\S+")


def build_enchant_names(item_ench: list, spell_points: dict) -> dict:
    """SpellItemEnchantment id -> clean display name (e.g. 1897 -> "+5 Weapon
    Damage"). Builds store the name with placeholder tokens WoW substitutes at
    runtime:
        $k1 / $s1     — this enchant's own effect value, slot 1 (its own
                        EffectPointsMin_{slot-1}).
        $<spellId>s1  — a cross-spell reference: effect 1 of spell <spellId>,
                        e.g. "+$13624s1 All Stats" -> spell 13624 effect 1 = 1
                        -> "+1 All Stats". Resolved via spell_points (locale-
                        independent numbers from SpellEffect) — so the same
                        spell_points feeds every locale's string pass.
    Any token we can't resolve is stripped (with its orphaned "+") so we never
    ship a raw "$..." or a misleading "+0 Mining". The Name_lang column carries
    the localized text, so passing a localized SpellItemEnchantment CSV yields
    localized enchant names with identical placeholder handling."""
    out: dict[int, str] = {}
    for row in item_ench:
        try:
            eid = int(row.get("ID") or 0)
            nm = (row.get("Name_lang") or "").strip()
            if not (eid and nm):
                continue
            if "$" in nm:
                pts = []
                for i in range(3):
                    try:
                        pts.append(int(row.get(f"EffectPointsMin_{i}") or 0))
                    except (TypeError, ValueError):
                        pts.append(0)

                def _resolve(m, pts=pts):
                    spellid, idx = m.group(1), int(m.group(2))
                    if not (1 <= idx <= 3):
                        return ""
                    if spellid == "":
                        v = pts[idx - 1]                 # own effect value
                    else:
                        v = spell_points.get(int(spellid), {}).get(idx - 1, 0)
                    return str(abs(v)) if v != 0 else "" # strip unresolved/zero

                nm = _ENCH_PH.sub(_resolve, nm)
                nm = _ENCH_JUNK.sub("", nm)             # leftover scaling tokens ($i/$n/$f)
                nm = re.sub(r"\([+\-/\s]*\)", "", nm)   # collapsed empty "(+)" / "(/)" groups
                nm = re.sub(r"\s*\([+\-/\s]*$", "", nm) # dangling unclosed "(+" tail
                nm = re.sub(r"\+\s+", "", nm)           # orphaned "+" from a stripped value
                nm = re.sub(r"\s{2,}", " ", nm).strip() # tidy whitespace
            out[eid] = nm
        except (TypeError, ValueError, KeyError):
            continue
    return out


def localize_entries(out: dict, ctx: dict, build: str, locale: str,
                     refresh: bool = False) -> dict:
    """Produce a localized copy of one build's {profId: {spellId: entry}} by
    overriding ONLY the translated fields — recipe `name` (localized SpellName)
    and enchant `effect` (localized SpellItemEnchantment). Everything structural
    (which recipes exist, difficulty, reagents, ids, phase) is reused verbatim
    from the canonical enUS extraction, so the recipe SET is identical across
    every locale — only the text differs. Falls back to the enUS string when a
    locale is missing a translation."""
    name_by_spell_loc: dict[int, str] = {}
    for row in fetch_csv("SpellName", build, refresh=refresh, locale=locale):
        try:
            nm = (row.get("Name_lang") or "").strip()
            if nm:
                name_by_spell_loc[int(row["ID"])] = nm
        except (TypeError, ValueError, KeyError):
            continue

    item_ench_loc = fetch_csv("SpellItemEnchantment", build,
                              refresh=refresh, locale=locale)
    enchant_name_loc = build_enchant_names(item_ench_loc, ctx["spell_points"])
    ench_by_spell = ctx["enchant_id_by_spell"]

    res: dict = {}
    for prof_id, recipes in out.items():
        slot: dict = {}
        for spell_id, entry in recipes.items():
            e = dict(entry)
            nm = name_by_spell_loc.get(spell_id)
            if nm:
                e["name"] = nm
            if entry.get("effect"):           # enchant — re-resolve its effect
                eid = ench_by_spell.get(spell_id)
                loc_eff = enchant_name_loc.get(eid) if eid else None
                if loc_eff:
                    e["effect"] = loc_eff
            slot[spell_id] = e
        res[prof_id] = slot
    return res


# ---------------------------------------------------------------------------
# Enchant enrichment — target slot + structured stats (LibProfessionDB extras)
#
# These enrich the Enchanting (333) entries the library ships so consumers don't
# have to re-derive them from the display string. Both are extracted
# AUTHORITATIVELY from DBC — no recipe-name grepping, no effect-string parsing:
#   * enchantSlot — from the recipe spell's SpellEquippedItems restriction.
#   * stats       — from the SpellItemEnchantment effects (chasing the hidden
#                   apply spell's SpellEffect auras for the common stat case).
# Keys are WoW-canonical (ITEM_MOD_*_SHORT / RESISTANCEn_NAME, the GetItemStats
# space), so a consumer can sum them straight into item-stat totals.
# ---------------------------------------------------------------------------

# EquippedItemInvTypes bit -> slot category (INVTYPE enum). Armor only; weapons
# come through as EquippedItemClass==2 with an empty inv-type mask (see below).
# INVTYPE_ROBE (20) is a chest piece, so it collapses onto CHEST.
_ENCH_INV_SLOT = {
    1: "HEAD", 3: "SHOULDER", 5: "CHEST", 6: "WAIST", 7: "LEGS", 8: "FEET",
    9: "WRIST", 10: "HANDS", 14: "SHIELD", 15: "RANGED", 16: "BACK", 20: "CHEST",
}

# SpellEffect.EffectAura ids we translate into structured enchant stats, mapped
# to their canonical GetItemStats key. MOD_STAT (29) is handled separately because
# the primary is selected by EffectMiscValue_0. These are the auras the shipped
# enchant apply-spells actually use; anything else (procs, %-haste, ...) yields no
# static stat and simply contributes nothing.
_ENCH_AURA_KEY = {
    13:  "ITEM_MOD_SPELL_POWER",              # MOD_DAMAGE_DONE (spell damage)
    34:  "ITEM_MOD_HEALTH",                    # MOD_INCREASE_HEALTH
    35:  "ITEM_MOD_MANA",                      # MOD_INCREASE_ENERGY (mana)
    85:  "ITEM_MOD_POWER_REGEN0_SHORT",        # MOD_POWER_REGEN (mp5)
    99:  "ITEM_MOD_ATTACK_POWER_SHORT",        # MOD_ATTACK_POWER
    124: "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", # MOD_RANGED_ATTACK_POWER
    135: "ITEM_MOD_SPELL_HEALING_DONE",        # MOD_HEALING_DONE
    158: "ITEM_MOD_BLOCK_VALUE",               # MOD_SHIELD_BLOCKVALUE
}
# MOD_STAT (29) and MOD_RESISTANCE (22) are handled specially (misc-driven); the
# rest map straight through _ENCH_AURA_KEY.
_ENCH_INTERESTING_AURAS = frozenset({29, 22}) | frozenset(_ENCH_AURA_KEY)

# MOD_STAT (aura 29) EffectMiscValue_0 -> primary key. -1 = all primaries.
_ENCH_STAT_MISC = {
    0: "ITEM_MOD_STRENGTH_SHORT",
    1: "ITEM_MOD_AGILITY_SHORT",
    2: "ITEM_MOD_STAMINA_SHORT",
    3: "ITEM_MOD_INTELLECT_SHORT",
    4: "ITEM_MOD_SPIRIT_SHORT",
}
_ENCH_ALL_PRIMARIES = tuple(_ENCH_STAT_MISC.values())

# SpellItemEnchantment.Effect_i == 4 (RESISTANCE): EffectArg_i is the resistance
# school (0 = armor, 1 = holy, 2 = fire, 3 = nature, 4 = frost, 5 = shadow,
# 6 = arcane). RESISTANCE0_NAME is the game's own "armor" stat key.
_ENCH_RES_KEY = {i: f"RESISTANCE{i}_NAME" for i in range(0, 7)}

# SpellItemEnchantment.Effect_i == 5 (STAT, direct): EffectArg_i is an ItemMod
# (ItemStatType) index. Rare in Classic (stats ship as type-3 equip spells), but
# handled for later builds that encode them directly.
_ENCH_ITEMMOD_KEY = {
    0: "ITEM_MOD_MANA", 1: "ITEM_MOD_HEALTH",
    3: "ITEM_MOD_AGILITY_SHORT", 4: "ITEM_MOD_STRENGTH_SHORT",
    5: "ITEM_MOD_INTELLECT_SHORT", 6: "ITEM_MOD_SPIRIT_SHORT",
    7: "ITEM_MOD_STAMINA_SHORT",
}


def enchant_slot_from_equip(spell_id: int, equip_by_spell: dict, name: str):
    """Authoritative target slot for an enchant recipe, from the recipe spell's
    SpellEquippedItems restriction. Armor slots come straight from the
    EquippedItemInvTypes bitmask. Weapons (EquippedItemClass 2) carry no inv-type
    bits in this table, so the 1H/2H split falls back to the enchant name — the
    only residual name dependency, and enchant names are stable ("Enchant 2H
    Weapon - ..." vs "Enchant Weapon - ..."). Returns a category string
    (WEAPON1H/WEAPON2H/WRIST/HANDS/FEET/CHEST/BACK/SHIELD/HEAD/...) or None."""
    info = equip_by_spell.get(spell_id)
    if not info:
        return None
    cls, invmask, _subclass = info
    if cls == 2:  # weapon: mask has no handedness, so read it off the name
        n = (name or "").lower()
        if "2h weapon" in n or "two-hand" in n or "two hand" in n:
            return "WEAPON2H"
        return "WEAPON1H"
    cats = {cat for bit, cat in _ENCH_INV_SLOT.items() if invmask & (1 << bit)}
    if len(cats) == 1:
        return next(iter(cats))
    return None   # unrestricted / ambiguous — leave for the consumer to skip


def enchant_stats_from_dbc(eid: int, sie_by_id: dict, aura_by_spell: dict) -> dict:
    """Structured { statKey: amount } for a SpellItemEnchantment, from DBC only:
      * Effect 4 (RESISTANCE): EffectArg = school (0 = armor), amount = EffectPointsMin.
      * Effect 5 (STAT, direct): EffectArg = ItemMod index, amount = EffectPointsMin.
      * Effect 3 (EQUIP_SPELL): EffectArg = hidden apply spell; read ITS SpellEffect
        auras. Classic stores these flat auras as (value - 1), so the granted
        amount = EffectBasePoints + 1.
    Proc / damage / use effects (Crusader, Fiery Weapon, ...) carry no static stat
    and contribute nothing. Empty dict when nothing structural was found."""
    row = sie_by_id.get(eid)
    if not row:
        return {}
    stats: dict[str, int] = {}

    def add(key, amount):
        if key and amount:
            stats[key] = stats.get(key, 0) + amount

    for i in range(3):
        try:
            et = int(row.get(f"Effect_{i}") or 0)
        except (TypeError, ValueError):
            continue
        if et == 0:
            continue
        try:
            arg = int(row.get(f"EffectArg_{i}") or 0)
            pts = int(row.get(f"EffectPointsMin_{i}") or 0)
        except (TypeError, ValueError):
            arg, pts = 0, 0
        if et == 4:      # resistance / armor — amount is direct
            add(_ENCH_RES_KEY.get(arg), pts)
        elif et == 5:    # direct stat — amount is direct
            add(_ENCH_ITEMMOD_KEY.get(arg), pts)
        elif et == 3:    # equip spell — chase the apply spell's auras
            for aura, misc, base in aura_by_spell.get(arg, ()):
                amt = base + 1   # classic BasePoints store (value - 1)
                if aura == 29:                       # MOD_STAT — misc selects the primary
                    if misc == -1:
                        for k in _ENCH_ALL_PRIMARIES:
                            add(k, amt)
                    else:
                        add(_ENCH_STAT_MISC.get(misc), amt)
                elif aura == 22:                     # MOD_RESISTANCE — misc is a school bitmask
                    for school in range(0, 7):       # 0=armor,1=holy,2=fire,3=nature,4=frost,5=shadow,6=arcane
                        if misc & (1 << school):     # (-1 = all schools, decodes correctly)
                            add(_ENCH_RES_KEY.get(school), amt)
                else:
                    add(_ENCH_AURA_KEY.get(aura), amt)
    return stats


def extract_recipes_for_build(build: str, spec_map: dict = None, refresh: bool = False) -> tuple:
    """Pull every recipe for every profession in PROF_FILES from one build.

    Returns (out, ctx):
        out = {profId: {spellId: {
            name, difficulty=[orange,yellow,green,grey], requiredSkill,
            reagents={[itemId]=count}, items=[recipe item ids], expansion=<build>
        }}}
        ctx = { enchant_id_by_spell, spell_points } — the locale-independent
              maps localize_entries() needs to re-resolve enchant effects.
    """
    print(f"  fetching DBC tables for build {build}", file=sys.stderr)
    sla          = fetch_csv("SkillLineAbility", build, refresh=refresh)
    spell_names  = fetch_csv("SpellName",        build, refresh=refresh)
    spell_reag   = fetch_csv("SpellReagents",    build, refresh=refresh)
    item_effects = fetch_csv("ItemEffect",       build, refresh=refresh)
    item_sparse  = fetch_csv("ItemSparse",       build, refresh=refresh)
    spell_effects = fetch_csv("SpellEffect",     build, refresh=refresh)
    item_ench    = fetch_csv("SpellItemEnchantment", build, refresh=refresh)
    # Per-spell equipped-item restriction — the authoritative source for an
    # enchant recipe's target slot (which inventory types it can be cast on).
    spell_equipped = fetch_csv("SpellEquippedItems", build, refresh=refresh)

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
    # spec_by_item ({itemId -> spec spell}) is passed in, not built here: it must
    # come from the Vanilla DBC (see build_spec_map) because TBC/Wrath zero out
    # RequiredAbility, and it's empty for Cata/MoP (specs removed in 4.0.1).
    spec_by_item = spec_map or {}
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
            pass

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
    # SpellItemEnchantment rows keyed by enchant id (Effect/EffectArg/EffectPointsMin
    # decode for structured stats — see enchant_stats_from_dbc).
    sie_by_id: dict[int, dict] = {}
    for row in item_ench:
        try:
            eid = int(row.get("ID") or 0)
            if eid:
                sie_by_id[eid] = row
        except (TypeError, ValueError):
            continue

    # Recipe spell -> (EquippedItemClass, EquippedItemInvTypes, EquippedItemSubclass).
    # First row per spell wins. Authoritative source for enchant target slots.
    equip_by_spell: dict[int, tuple] = {}
    for row in spell_equipped:
        try:
            sid = int(row.get("SpellID") or 0)
            if sid and sid not in equip_by_spell:
                equip_by_spell[sid] = (
                    int(row.get("EquippedItemClass") or -1),
                    int(row.get("EquippedItemInvTypes") or 0),
                    int(row.get("EquippedItemSubclass") or 0),
                )
        except (TypeError, ValueError):
            continue

    created_item_by_spell: dict[int, int] = {}
    enchant_id_by_spell: dict[int, int] = {}   # spell -> SpellItemEnchantment id (Effect 53)
    # Apply-spell auras a type-3 (equip-spell) enchant grants. spell -> list of
    # (EffectAura, EffectMiscValue_0, EffectBasePoints), filtered to the auras
    # enchant_stats_from_dbc translates.
    aura_by_spell: dict[int, list] = {}
    # spellId -> {effectIndex(0-based): displayed value}. Used to resolve
    # cross-spell enchant-name placeholders like "+$13624s1 All Stats", where
    # $<spellId>s<n> means "effect n of spell <spellId>". The displayed amount is
    # EffectPointsMin when present, else EffectBasePoints.
    spell_points: dict[int, dict[int, int]] = {}
    for row in spell_effects:
        try:
            effect = int(row.get("Effect") or 0)
            sid = int(row.get("SpellID") or 0)
            if not sid:
                continue
            try:
                eidx = int(row.get("EffectIndex") or 0)
                pmin = int(row.get("EffectPointsMin") or 0)
                base = int(row.get("EffectBasePoints") or 0)
                val = pmin if pmin != 0 else base
                if val != 0:
                    spell_points.setdefault(sid, {})[eidx] = val
                aura = int(row.get("EffectAura") or 0)
                if aura in _ENCH_INTERESTING_AURAS:
                    misc = int(row.get("EffectMiscValue_0") or 0)
                    aura_by_spell.setdefault(sid, []).append((aura, misc, base))
            except (TypeError, ValueError):
                pass
            if effect == 24:  # CREATE_ITEM
                iid = int(row.get("EffectItemType") or 0)
                if iid and sid not in created_item_by_spell:
                    if not is_obsolete_item_name(name_by_item.get(iid, "")):
                        created_item_by_spell[sid] = iid
            elif effect == 53:  # ENCHANT_ITEM (permanent)
                ench = int(row.get("EffectMiscValue_0") or 0)
                if ench and sid not in enchant_id_by_spell:
                    enchant_id_by_spell[sid] = ench
        except (TypeError, ValueError, KeyError):
            continue

    # SpellItemEnchantment id -> display name (e.g. 1897 -> "Weapon Damage +5").
    # Localized re-resolution (per-locale string passes) reuses this via the
    # standalone build_enchant_names(), which is why it takes the locale-
    # independent spell_points map as an argument.
    enchant_name_by_id = build_enchant_names(item_ench, spell_points)

    # Spells this build must not emit (forward-ported DBC leftovers not
    # obtainable in this flavour). See BUILD_EXCLUDED_SPELLS. `build` is the
    # build-id string here, so resolve it back to its EXPANSION_BUILDS label.
    _build_label = next((lbl for lbl, bid in EXPANSION_BUILDS if bid == build), build)
    build_excluded = BUILD_EXCLUDED_SPELLS.get(_build_label, frozenset())

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
                if spell_id in build_excluded:
                    continue
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

            # Correct the tiers for pattern/drop recipes. wago's MinSkillLineRank
            # is a placeholder 1 for these — the real learn level is requiredSkill
            # (Polar Bracers: SLA min=1 but the pattern requires 300). For these,
            # the real tiers are [requiredSkill, TrivialLow, mid(Low,High),
            # TrivialHigh] — i.e. orange = learn level, yellow = TrivialLow, green
            # = midpoint, grey = TrivialHigh. Verified vs WoWhead:
            #   Impact {200,220,240,260}, Polar {300,320,330,340}.
            # (difficulty[2]=TrivialLow / green, difficulty[3]=TrivialHigh / grey
            # from the array built above.) Recipes with a real MinSkillLineRank
            # (>1) keep their SLA-derived values — e.g. Medium {75,95,115,130}.
            if difficulty[0] <= 1 and required_skill and required_skill > 1:
                o    = required_skill
                low  = difficulty[2] if (difficulty[2] and difficulty[2] > o)   else o
                high = difficulty[3] if (difficulty[3] and difficulty[3] > low) else low
                difficulty = [o, low, (low + high) // 2, high]

            # Searchable effect text: the enchant effect name for Enchanting
            # recipes (e.g. "+5 Weapon Damage", "+1 All Stats"). nil otherwise —
            # crafted gear has a real client tooltip, so we never fabricate one.
            ench_id = enchant_id_by_spell.get(spell_id)
            effect = enchant_name_by_id.get(ench_id) if ench_id else None
            # Enchant enrichment (locale-independent): authoritative target slot
            # (SpellEquippedItems) + structured stats (DBC effects). Only meaningful
            # for enchants; None on every other recipe so clean_recipes omits them.
            ench_slot = enchant_slot_from_equip(
                spell_id, equip_by_spell, name_by_spell.get(spell_id, "")) if ench_id else None
            ench_stats = enchant_stats_from_dbc(
                ench_id, sie_by_id, aura_by_spell) if ench_id else None

            # Specialization gate: if any recipe-scroll item for this spell
            # requires a profession spec (ItemSparse.RequiredAbility), ship it so
            # the addon can hide recipes a character's spec can't learn.
            spec_req = next((spec_by_item[i]
                             for i in items_by_spell.get(spell_id, set())
                             if i in spec_by_item), None)
            # Vanilla encodes the spec on the recipe SCROLL (Plans: Arcanite
            # Reaper -> Axesmith), which the scroll lookup above catches. But
            # TBC/Wrath moved the gate onto the CRAFTED item itself (Lionheart
            # Blade, item 28428 -> 17039 Master Swordsmith) and leave the scroll
            # ungated — so every post-Vanilla spec recipe (BS/LW/Engineering, ~65
            # TBC / ~72 Wrath) shipped untagged and its crafters fell to
            # "Unspecialized". Fall back to the produced item's RequiredAbility.
            if not spec_req:
                _crafted = created_item_by_spell.get(spell_id)
                if _crafted and _crafted in spec_by_item:
                    spec_req = spec_by_item[_crafted]

            recipes[spell_id] = {
                "name":           name_by_spell.get(spell_id, ""),
                "difficulty":     difficulty,
                "teaches":        spell_id,  # self-teaching; scanner returns spell id
                "requiredSkill":  required_skill,
                "requiredSpec":   spec_req,
                "effect":         effect,
                "enchantId":      ench_id,
                "enchantSlot":    ench_slot,
                "stats":          ench_stats or None,
                "reagents":       reagents_by_spell.get(spell_id, {}),
                "items":          sorted(items_by_spell.get(spell_id, set())),
                "craftedItemId":  created_item_by_spell.get(spell_id),
                "expansion":      build,
            }
        out[prof_id] = recipes
    ctx = {
        "enchant_id_by_spell": enchant_id_by_spell,
        "spell_points":        spell_points,
    }
    return out, ctx


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
                    prior_min    = slot[spell_id].get("minExpansion", build_idx)
                    prior_effect = slot[spell_id].get("effect")
                    slot[spell_id] = dict(entry)
                    slot[spell_id]["minExpansion"] = prior_min
                    # Don't let a later build's missing effect clobber a good one.
                    if not slot[spell_id].get("effect") and prior_effect:
                        slot[spell_id]["effect"] = prior_effect
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
    19106,   # Leatherworking "Onyxia Scale Breastplate" — planned matching
             # chest piece to the shipped "Onyxia Scale Cloak" (spell 19092);
             # cut before live. Recipe scroll item 15780 and crafted item
             # 15141 also never shipped. User-reported on Classic Era
             # (Galdof, 2026-05).
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
    818,     # Cooking "Basic Campfire" — not a craftable recipe at all: it's
             # the learned ability that summons a cooking fire (no produced
             # item). SkillLineAbility lists it under Cooking so it slipped in.
             # Never obtainable as a "recipe" in any expansion. User-reported
             # (Classic Era).
}


# Per-build exclusions: spells the client's DBC carries as forward-ported
# content that ISN'T obtainable in THAT flavour. Unlike MANUAL_EXCLUDED_SPELLS
# (dropped from every build), these are dropped only from the listed build's
# extraction, so merge_expansions pins their `minExpansion` to the first
# flavour where the recipe IS real — keeping them visible on later clients
# while the runtime expansion gate hides them on the earlier one. Keyed by
# EXPANSION_BUILDS label.
BUILD_EXCLUDED_SPELLS = {
    "Vanilla": {
        30021,   # First Aid "Crystal Infused Bandage" — a TBC recipe (skill
                 # 300→360, Netherweave-based). The 1.15.x Anniversary client
                 # ships its SkillLineAbility row, but it isn't learnable in
                 # Classic Era. Dropping it from the Vanilla build only pins
                 # minExpansion=2, so it still ships to TBC clients.
                 # User-reported (Classic Era).
    },
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


# Lazy-loaded hand-curated phase overrides. Win over the ATT-derived phase
# map for spells ATT misclassified (e.g. world-drop formulas wrongly gated
# behind a later phase via an awp/reputation tag). See
# tools/manual_phase_overrides.json.
_MANUAL_PHASE_OVERRIDES = None

def _load_manual_phase_overrides():
    global _MANUAL_PHASE_OVERRIDES
    if _MANUAL_PHASE_OVERRIDES is not None:
        return _MANUAL_PHASE_OVERRIDES
    import json
    p = SCRIPT_DIR / "manual_phase_overrides.json"
    if not p.exists():
        _MANUAL_PHASE_OVERRIDES = {}
        return _MANUAL_PHASE_OVERRIDES
    raw = json.loads(p.read_text(encoding="utf-8"))
    _MANUAL_PHASE_OVERRIDES = {
        int(k): v["phase"]
        for k, v in raw.items()
        if k.isdigit() and isinstance(v, dict) and "phase" in v
    }
    print(f"  loaded {len(_MANUAL_PHASE_OVERRIDES)} hand-curated phase overrides from "
          f"manual_phase_overrides.json", file=sys.stderr)
    return _MANUAL_PHASE_OVERRIDES


def clean_recipes(prof_id: int, recipes: dict) -> dict:
    """Return the runtime-ready {spellId: entry} dict for a profession.

    Strips helper-only fields (`items`, `expansion`) and non-recipe spells
    (rank-ups, specs, gathering toggles), and adds `itemId` / `craftedItemId`
    / `phase` where available. Shared by BOTH the TOGPM merged emit
    (emit_recipe_file) and the per-version ProfessionDB library emit
    (emit_library_file) so the two outputs can never drift.

    When ATT's phase map is available (att_extract_phase.py output), each
    recipe gets a `phase` field for client-side content-phase filtering.
    Only TBC has phase data today; other expansions get no `phase` field
    and the addon's filter treats them as always-visible."""
    phase_map = _load_phase_map()
    phase_overrides = _load_manual_phase_overrides()
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
        # requiredSpec: profession-specialization spell required to learn the
        # recipe (ItemSparse.RequiredAbility). Absent for spec-agnostic recipes.
        if entry.get("requiredSpec"):
            out["requiredSpec"] = entry["requiredSpec"]
        # effect: searchable effect text — enchant effect name (e.g. "Weapon
        # Damage +5") or formatted gear stats ("+10 Agility, +15 Stamina").
        # Omitted when there's nothing to show.
        if entry.get("effect"):
            out["effect"] = entry["effect"]
        # Enchant enrichment — present on any recipe whose craft applies a
        # permanent enchant (all Enchanting recipes, plus Engineering scopes /
        # belt tinkers); absent on ordinary item-producing recipes:
        #   enchantId   — the SpellItemEnchantment id (the number in an item
        #                 link's enchant slot), so a consumer can map a worn
        #                 enchant back to its recipe.
        #   enchantSlot — authoritative target slot category (from SpellEquippedItems).
        #   stats       — structured { GetItemStats-key: amount } from DBC effects.
        if entry.get("enchantId"):
            out["enchantId"] = entry["enchantId"]
        if entry.get("enchantSlot"):
            out["enchantSlot"] = entry["enchantSlot"]
        if entry.get("stats"):
            out["stats"] = entry["stats"]
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
        # Manual phase override wins over the ATT-derived value (ATT
        # occasionally misclassifies world-drop formulas as a later phase).
        phase = phase_overrides.get(spell_id, phase_map.get(spell_id))
        if phase and phase > 1:
            # Only emit `phase` when it's beyond Phase 1 (the default).
            # Recipes without a phase entry — or tagged Phase 1 — get no
            # field and the addon treats them as always-visible. A manual
            # override of phase=1 therefore strips the field, un-hiding a
            # recipe ATT wrongly gated behind a later phase.
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
    return cleaned


def emit_recipe_file(prof_id: int, filename: str, recipes: dict):
    """TOGPM (live addon) output: Data/Recipes/<filename>.lua, populating the
    addon-private `addon.recipeDB`. This is the MERGED, all-expansion union the
    Classic addon ships today; the per-client expansion gates in the GUI keep a
    given client to its own content."""
    cleaned = clean_recipes(prof_id, recipes)
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


# Build label -> ProfessionDB game-folder name. MoP ships under "Mists" to
# match the live TOGProfessionMaster_Mists.toc naming.
LIBRARY_GAME_FOLDER = {
    "Vanilla": "Vanilla", "TBC": "TBC", "Wrath": "Wrath",
    "Cata": "Cata", "MoP": "Mists",
}
# ProfessionDB library data root (sibling addon next to TOGProfessionMaster).
LIBRARY_DATA_ROOT = ADDON_ROOT.parent / "ProfessionDB" / "Data"


def emit_core_file(prof_id: int, filename: str, recipes: dict, game: str):
    """ProfessionDB CORE output (locale-independent), once per game + profession:
    ProfessionDB/Data/<game>/_core/<filename>.lua.

    Holds the structural fields that are byte-identical across every language —
    difficulty / reagents / requiredSkill / teaches / craftedItemId / itemId /
    phase, plus the enchant enrichment (enchantId / enchantSlot / stats) — so
    they're parsed and loaded exactly once instead of duplicated in all 12 locale
    files. Guarded by IsGameVersion only (no GetLocale); the per-flavour TOC lists
    core files BEFORE the locale name files."""
    cleaned = clean_recipes(prof_id, recipes)
    # A profession can be present in a build's SkillLineAbility yet contribute no
    # craftable recipes (e.g. Fishing in Vanilla). Don't write an empty file.
    if not cleaned:
        return 0, None
    core = {}
    for spell_id, e in cleaned.items():
        c = {
            "difficulty": e["difficulty"],
            "teaches":    e["teaches"],
            "reagents":   e["reagents"],
        }
        if e.get("requiredSkill"): c["requiredSkill"] = e["requiredSkill"]
        if e.get("requiredSpec"):  c["requiredSpec"]  = e["requiredSpec"]
        if e.get("itemId"):        c["itemId"]        = e["itemId"]
        if e.get("craftedItemId"): c["craftedItemId"] = e["craftedItemId"]
        if e.get("phase"):         c["phase"]         = e["phase"]
        # Enchant enrichment (locale-independent — the id, slot and stat amounts
        # don't change across languages, so they live in _core, not the name files).
        if e.get("enchantId"):     c["enchantId"]     = e["enchantId"]
        if e.get("enchantSlot"):   c["enchantSlot"]   = e["enchantSlot"]
        if e.get("stats"):         c["stats"]         = e["stats"]
        core[spell_id] = c
    body = lua_value(core, 1)
    target = LIBRARY_DATA_ROOT / game / "_core" / f"{filename}.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        f"-- LibProfessionDB core data — WoW {game}, {filename} (locale-independent)\n"
        "-- Auto-generated by the TOGProfessionMaster authoritative-data "
        "pipeline. Do not hand-edit.\n"
        f"-- {len(core)} recipes\n"
        "\n"
        'local lib = LibStub and LibStub("LibProfessionDB-1.0", true)\n'
        f'if not lib or not lib:IsGameVersion("{game}") then return end\n'
        "\n"
        f"lib:LoadCore({prof_id}, {body})\n"
    )
    target.write_text(contents, encoding="utf-8")
    return len(core), target


def emit_names_file(prof_id: int, filename: str, recipes: dict,
                    game: str, locale: str):
    """ProfessionDB NAMES output (localized strings), per game + locale + prof:
    ProfessionDB/Data/<game>/<locale>/<filename>.lua.

    Holds ONLY the localized fields — name (+ effect for enchants) — keyed by
    recipe id. Guarded by GetLocale() + IsGameVersion so only the matching
    language registers; the structural data comes from the _core file."""
    cleaned = clean_recipes(prof_id, recipes)
    if not cleaned:
        return 0, None
    names = {}
    for spell_id, e in cleaned.items():
        n = {"name": e["name"]}
        if e.get("effect"):
            n["effect"] = e["effect"]
        names[spell_id] = n
    body = lua_value(names, 1)
    target = LIBRARY_DATA_ROOT / game / locale / f"{filename}.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        f"-- LibProfessionDB names — WoW {game}, {locale}, {filename}\n"
        "-- Auto-generated by the TOGProfessionMaster authoritative-data "
        "pipeline. Do not hand-edit.\n"
        f"-- {len(names)} recipes\n"
        "\n"
        f'if GetLocale() ~= "{locale}" then return end\n'
        'local lib = LibStub and LibStub("LibProfessionDB-1.0", true)\n'
        f'if not lib or not lib:IsGameVersion("{game}") then return end\n'
        "\n"
        f"lib:LoadNames({prof_id}, {body})\n"
    )
    target.write_text(contents, encoding="utf-8")
    return len(names), target


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


def emit_vendor_prices(per_build: list):
    """Write TOGProfessionMaster/Data/VendorPrices.lua — { [itemId] = copper }
    for crafting reagents that a vendor ACTUALLY sells, priced from wago
    ItemSparse BuyPrice.

    Why the npc_vendor gate: ItemSparse BuyPrice is ~SellPrice*4 and present on
    almost every item (drop mats included), so it is NOT a vendor-availability
    signal. Vendor inventories are server-side (absent from client DBC / wago),
    so we take the authoritative "is it vendor-sold" list from the emulator
    npc_vendor tables (the same dumps Phase B already caches) and intersect with
    the reagents that appear in recipes. Result: thread / dye / vials / flux get
    a vendor price; drop/farmed mats (leather, ore, herbs, cloth) do not."""
    # Vendor-sold item set from cached emulator npc_vendor dumps, gated to
    # genuine GOLD STAPLES: maxcount == 0 (unlimited stock) AND ExtendedCost == 0
    # (bought with gold, not tokens/currency). npc_vendor schema across
    # AzerothCore / TrinityCore is (entry, slot, item, maxcount, incrtime,
    # ExtendedCost, ...). Without this gate, limited-stock or token-vendor
    # entries (a vendor with 3 Heavy Leather, a token quartermaster selling
    # Linen) would wrongly tag farmed/drop mats with a "vendor price" — exactly
    # what Auctionator avoids by only caching numAvailable == -1 items.
    emul_cache = SCRIPT_DIR / "emulator_data"
    vendor_files = sorted(emul_cache.glob("*_npc_vendor.sql"))
    if not vendor_files:
        print("  vendor prices: no npc_vendor data cached; skipping", file=sys.stderr)
        return
    _row = re.compile(r"\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)")
    vendor_items = set()
    for p in vendor_files:
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in _row.finditer(text):
            item     = int(m.group(3))
            maxcount = int(m.group(4))
            extcost  = int(m.group(6))
            if item and maxcount == 0 and extcost == 0:
                vendor_items.add(item)
    if not vendor_items:
        print("  vendor prices: npc_vendor parsed 0 unlimited gold items; skipping",
              file=sys.stderr)
        return

    # Reagent itemIds that actually appear in recipes (keeps the table small).
    reagent_ids = set()
    for out in per_build:
        for recipes in out.values():
            for entry in recipes.values():
                for iid in (entry.get("reagents") or {}):
                    reagent_ids.add(iid)

    # BuyPrice per item from ItemSparse (merged across builds; item-intrinsic).
    buy = {}
    for _label, build_id in EXPANSION_BUILDS:
        for row in fetch_csv("ItemSparse", build_id):
            try:
                iid = int(row.get("ID") or 0)
                bp  = int(row.get("BuyPrice") or 0)
            except (TypeError, ValueError):
                continue
            if iid and bp > 0 and iid not in buy:
                buy[iid] = bp

    table = {}
    for iid in (vendor_items & reagent_ids):
        bp = buy.get(iid)
        if bp and bp > 0:
            table[iid] = bp

    target = ADDON_ROOT / "Data" / "VendorPrices.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        "local _, addon = ...\n"
        "\n"
        "-- Vendor buy price (copper) for crafting reagents a vendor actually\n"
        "-- sells. Generated by tools/build_authoritative_data.py: emulator\n"
        "-- npc_vendor (vendor-sold gate) intersected with recipe reagents,\n"
        "-- priced from wago ItemSparse BuyPrice. Do not hand-edit.\n"
        f"addon.VendorPrices = {lua_value(table, 0)}\n"
    )
    target.write_text(contents, encoding="utf-8")
    print(f"  wrote {target.relative_to(ADDON_ROOT)}: "
          f"{len(table)} vendor-priced reagents "
          f"({len(vendor_items):,} vendor items x {len(reagent_ids):,} reagents)")


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
    ap.add_argument("--core-only", action="store_true",
                    help="Only (re)emit the locale-independent _core files; "
                         "skip the per-locale name files. Offline (no locale "
                         "CSV fetch). Use when a change touches only _core "
                         "fields such as requiredSpec.")
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

    # Spec-lock map = UNION of RequiredAbility across every pre-Cata build's
    # ItemSparse. Needed because no single build has all of it: Vanilla carries
    # the Vanilla-era LW/BS/Engineering patterns (TBC/Wrath zero those out), while
    # the TBC-introduced Tailoring cloth specs only appear from the TBC build on.
    # Reused for every pre-Cata build; Cata/MoP get none (specs removed in 4.0.1).
    global_spec_map = {}
    for _label, _bid in EXPANSION_BUILDS:
        if _label in SPEC_ACTIVE_BUILDS:
            global_spec_map.update(build_spec_map(_bid, refresh=args.refresh))
    print(f"   spec-locked recipe scrolls: {len(global_spec_map)}", file=sys.stderr)

    per_build = []   # list of canonical enUS {profId: {spell: entry}} dicts
    per_ctx   = []   # parallel list of locale-resolution context per build
    for label, build_id in builds:
        print(f"\n[{label}] build {build_id}", file=sys.stderr)
        spec_map = global_spec_map if label in SPEC_ACTIVE_BUILDS else {}
        out, ctx = extract_recipes_for_build(build_id, spec_map=spec_map, refresh=args.refresh)
        per_build.append(out)
        per_ctx.append(ctx)

    merged = merge_expansions(per_build)

    # NOTE: TOGProfessionMaster no longer ships a bundled, all-version-merged
    # Data/Recipes/*.lua set — it now consumes the per-version LibProfessionDB
    # library (emitted below) via Data/RecipeDB.lua. The merge is still computed
    # here ONLY to feed the Phase B source-DB builder its recipe→items linkage.
    # (emit_recipe_file is kept available for ad-hoc/debug use but is no longer
    # called by the pipeline.)
    emit_recipe_items_map(merged)

    # Static vendor-price table for TOGPM cost-to-craft (npc_vendor ∩ reagents).
    emit_vendor_prices(per_build)

    # ---- ProfessionDB library output: per-game, core + per-locale names ----
    # Structural data (difficulty/reagents/ids) is locale-independent, so it's
    # emitted ONCE per game into Data/<game>/_core/<Prof>.lua. Only the localized
    # strings (name + effect) are emitted per locale into Data/<game>/<locale>/.
    # Not merged across expansions — each game folder is that build's point-in-
    # time set. enUS is the canonical pass; every other official locale
    # re-resolves ONLY name + effect; enGB mirrors enUS.
    profs_sorted = sorted(PROF_FILES.items(), key=lambda kv: kv[1][0])
    print(f"\n=== Emitting ProfessionDB/Data/<game>/{{_core,<locale>}}/*.lua ===")
    print(f"{'game':<10} {'what':<8} {'recipes':>9}")
    core_total, name_total = 0, 0
    for (label, build_id), out, ctx in zip(builds, per_build, per_ctx):
        game = LIBRARY_GAME_FOLDER.get(label, label)

        # Core (locale-independent), once per profession from the canonical pass.
        g_core = 0
        for prof_id, (filename, _) in profs_sorted:
            recipes = out.get(prof_id, {})
            if not recipes:
                continue
            count, _ = emit_core_file(prof_id, filename, recipes, game)
            g_core += count
        core_total += g_core
        print(f"{game:<10} {'_core':<8} {g_core:>9}")

        # Names, per locale. Skipped in --core-only mode (requiredSpec and the
        # other _core fields are locale-independent, so the name files are
        # unchanged and don't need the per-locale CSV fetch).
        if args.core_only:
            continue
        by_locale = {"enUS": out}
        for loc in EXTRA_LOCALES:
            print(f"  [{label}] localizing {loc}", file=sys.stderr)
            by_locale[loc] = localize_entries(out, ctx, build_id, loc,
                                              refresh=args.refresh)
        for mloc, src in MIRROR_LOCALES.items():
            if src in by_locale:
                by_locale[mloc] = by_locale[src]
        for loc, data in sorted(by_locale.items()):
            loc_total = 0
            for prof_id, (filename, _) in profs_sorted:
                recipes = data.get(prof_id, {})
                if not recipes:
                    continue
                count, _ = emit_names_file(prof_id, filename, recipes, game, loc)
                loc_total += count
            name_total += loc_total
            print(f"{game:<10} {loc:<8} {loc_total:>9}")
    print(f"{'CORE TOTAL':<19} {core_total:>9}")
    print(f"{'NAMES TOTAL':<19} {name_total:>9}")


if __name__ == "__main__":
    main()
