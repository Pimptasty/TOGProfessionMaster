#!/usr/bin/env python3
"""v0.5.0 Phase B: Source DB builder.

Pairs with build_authoritative_data.py (Phase A) to produce the OTHER half
of the data the addon needs — Data/Sources/<Prof>.lua. Without these source
entries, BuildMissingList in GUI/MissingRecipesTab.lua filters out every
recipe (the `hasUsableSource` gate at line 260 requires a sourceDB entry).

Inputs (all cached locally; populate via the prep step at the top of main):
  - tools/wago_cache/<build>__SkillLineAbility.csv + ItemEffect.csv
        (read via build_authoritative_data.extract_recipes_for_build)
  - tools/emulator_data/trinity_cata_*.sql              (Cata coverage)
  - tools/emulator_data/azerothcore_wrath_*.sql         (Wrath coverage)

Strategy:
  1. Build {spellId: profId} and {itemId: (profId, spellId)} from the MoP
     recipe universe (broadest coverage — includes every spell that ever
     existed as a recipe across the Vanilla→MoP timeline).
  2. Per emulator world DB:
        - trainer_spell + creature_trainer  →  spell → [trainerNpcId]
        - npc_vendor                        →  item  → [vendorNpcId]
        - creature_loot_template            →  item  → [creatureNpcId]
        - gameobject_loot_template          →  item  → [gameObjectId]
        - reference_loot_template           →  used to expand the two
                                               loot tables when an entry
                                               references a shared sub-table
  3. Merge across both world DBs; filter to recipe spells.
  4. Emit:
        addon.sourceDB[profId] = {
            [spellId] = {
                vendor  = {[npcId] = ""},
                drop    = {[npcId] = ""},   -- creature drops + GO contents
                trainer = {[npcId] = ""},
            },
        }

Quest rewards and item-container (clam) loot are deferred to a v0.5.1
patch — quest_template has a many-column schema that varies between Trinity
and AzerothCore and needs per-version mapping; item_loot_template is small
enough to add cheaply but covers only a handful of recipes.
"""

import argparse
import pathlib
import sys

SCRIPT_DIR  = pathlib.Path(__file__).resolve().parent
ADDON_ROOT  = SCRIPT_DIR.parent
SOURCES_DIR = ADDON_ROOT / "Data" / "Sources"

sys.path.insert(0, str(SCRIPT_DIR))
from build_authoritative_data import (  # type: ignore
    EXPANSION_BUILDS, PROF_FILES, extract_recipes_for_build, lua_value,
)
from extract_emulator_trainers import (  # type: ignore
    _prepare_trinity_cata, ensure_files, parse_insert_rows, SOURCES,
    CACHE_DIR as EMUL_CACHE,
)


# ---------------------------------------------------------------------------
# Recipe ↔ profession reverse maps (built once from Phase A's data path)
# ---------------------------------------------------------------------------

def build_reverse_maps():
    """Re-run Phase A's wago.tools extraction for every expansion (cached) so
    we know which spells are recipes for which professions, AND which items
    teach which spells.

    Returns:
        spell_to_prof: {spellId: profId}
        item_to_spell: {itemId: (profId, spellId)}
    """
    print("\n[reverse maps] building spell→prof and item→spell from wago.tools",
          file=sys.stderr)
    spell_to_prof = {}
    item_to_spell = {}
    # We walk every expansion so a recipe that existed in Vanilla but was
    # removed by MoP still has source entries. Latest-wins on conflicts.
    for label, build in EXPANSION_BUILDS:
        per_prof = extract_recipes_for_build(build)
        for prof_id, recipes in per_prof.items():
            for spell_id, entry in recipes.items():
                spell_to_prof[spell_id] = prof_id
                for iid in entry.get("items", []):
                    item_to_spell[iid] = (prof_id, spell_id)
    print(f"  recipe spells: {len(spell_to_prof):,}", file=sys.stderr)
    print(f"  recipe items:  {len(item_to_spell):,}", file=sys.stderr)
    return spell_to_prof, item_to_spell


# ---------------------------------------------------------------------------
# Per-source parsers
# ---------------------------------------------------------------------------

def parse_trainers(label: str):
    """Returns {spellId: set([trainerNpcId, ...])}.

    label is "trinity_cata" or "azerothcore_wrath" — used to locate the
    correct file pair in tools/emulator_data/.
    """
    if label == "trinity_cata":
        ct = EMUL_CACHE / "trinity_cata_creature_trainer.sql"
    else:
        ct = EMUL_CACHE / f"{label}_creature_default_trainer.sql"
    ts = EMUL_CACHE / f"{label}_trainer_spell.sql"

    # creature_trainer / creature_default_trainer: (CreatureID, TrainerID, ...)
    trainer_to_npcs: dict[int, list[int]] = {}
    for cols in parse_insert_rows(ct):
        if len(cols) < 2:
            continue
        try:
            cid = int(cols[0])
            tid = int(cols[1])
        except ValueError:
            continue
        trainer_to_npcs.setdefault(tid, []).append(cid)

    # trainer_spell: (TrainerID, SpellID, MoneyCost, ReqSkillLine, ...)
    out: dict[int, set[int]] = {}
    for cols in parse_insert_rows(ts):
        if len(cols) < 2:
            continue
        try:
            tid = int(cols[0])
            sid = int(cols[1])
        except ValueError:
            continue
        for nid in trainer_to_npcs.get(tid, ()):
            out.setdefault(sid, set()).add(nid)
    return out


def parse_npc_vendor(label: str):
    """Returns {itemId: set([vendorNpcId, ...])}.

    Both TC Cata and AC Wrath schemas place (entry, slot, item, ...) at the
    first three columns, so the parser is identical."""
    path = EMUL_CACHE / f"{label}_npc_vendor.sql"
    out: dict[int, set[int]] = {}
    for cols in parse_insert_rows(path):
        if len(cols) < 3:
            continue
        try:
            npc_id  = int(cols[0])
            item_id = int(cols[2])
        except ValueError:
            continue
        if item_id:
            out.setdefault(item_id, set()).add(npc_id)
    return out


def _parse_loot_template(loot_sql, ref_sql):
    """Common parser for creature_loot_template + gameobject_loot_template.

    Schema (both TC + AC, both creature + GO):
        (Entry, Item, Reference, Chance, QuestRequired, LootMode, GroupId,
         MinCount, MaxCount, Comment)

    Returns {entryId: set([itemId, ...])} with reference loot tables expanded
    (an entry of (E, 0, R, ...) inherits all items from reference_loot_template
    where Entry == R).
    """
    # Build reference -> set(itemId). References can themselves chain, so we
    # iterate to a fixed point.
    ref_to_items: dict[int, set[int]] = {}
    ref_to_refs:  dict[int, set[int]] = {}
    for cols in parse_insert_rows(ref_sql):
        if len(cols) < 3:
            continue
        try:
            rid  = int(cols[0])
            item = int(cols[1])
            sub  = int(cols[2])
        except ValueError:
            continue
        if item:
            ref_to_items.setdefault(rid, set()).add(item)
        if sub:
            ref_to_refs.setdefault(rid, set()).add(sub)

    # Resolve chained references (DFS, memoized)
    resolved_cache: dict[int, set[int]] = {}
    def resolve(rid: int, visiting: set[int]) -> set[int]:
        if rid in resolved_cache:
            return resolved_cache[rid]
        if rid in visiting:
            return set()  # cycle
        visiting.add(rid)
        result = set(ref_to_items.get(rid, ()))
        for sub in ref_to_refs.get(rid, ()):
            result |= resolve(sub, visiting)
        visiting.remove(rid)
        resolved_cache[rid] = result
        return result

    out: dict[int, set[int]] = {}
    for cols in parse_insert_rows(loot_sql):
        if len(cols) < 3:
            continue
        try:
            entry = int(cols[0])
            item  = int(cols[1])
            ref   = int(cols[2])
        except ValueError:
            continue
        bucket = out.setdefault(entry, set())
        if item:
            bucket.add(item)
        if ref:
            bucket |= resolve(ref, set())
    return out


def parse_creature_loot(label: str):
    return _parse_loot_template(
        EMUL_CACHE / f"{label}_creature_loot_template.sql",
        EMUL_CACHE / f"{label}_reference_loot_template.sql",
    )


def parse_gameobject_loot(label: str):
    return _parse_loot_template(
        EMUL_CACHE / f"{label}_gameobject_loot_template.sql",
        EMUL_CACHE / f"{label}_reference_loot_template.sql",
    )


def parse_item_loot(label: str):
    """Container-style loot. The Entry is an ITEM ID (e.g. a clam or lockbox);
    the value is the item dropped when the container is opened. Recipes from
    Crafty Quest Reward Boxes (Wrath+) and the like land here."""
    return _parse_loot_template(
        EMUL_CACHE / f"{label}_item_loot_template.sql",
        EMUL_CACHE / f"{label}_reference_loot_template.sql",
    )


# Quest template column positions per emulator (verified by inspecting the
# CREATE TABLE in each cached SQL file).
#
# Item-bearing columns:
#   StartItem            an item the player gets to KICK OFF the quest
#                        (the quest may itself reward a recipe later; treat
#                         StartItem the same as RewardItem since either kind
#                         is "obtainable via this quest" from the player's POV).
#   RewardItem1..4       items always rewarded on completion.
#   RewardChoiceItemID1..N items the player CHOOSES from on completion.
#
# AzerothCore Wrath:
#   StartItem        col 19
#   RewardItem1-4    cols 22, 24, 26, 28
#   RewardChoice1-6  cols 38, 40, 42, 44, 46, 48  (step 2 = item id + qty)
#
# TrinityCore Cata:
#   StartItem        col 22
#   RewardItem1-4    cols 29, 31, 33, 35
#   RewardChoice1-6  cols 45, 48, 51, 54, 57, 60  (step 3 = id + qty + display)
QUEST_COLUMNS = {
    "azerothcore_wrath": {
        "start":  19,
        "reward": (22, 24, 26, 28),
        "choice": (38, 40, 42, 44, 46, 48),
    },
    "trinity_cata": {
        "start":  22,
        "reward": (29, 31, 33, 35),
        "choice": (45, 48, 51, 54, 57, 60),
    },
}


def parse_quest_rewards(label: str):
    """Parse quest_template and return {itemId: set([questId, ...])}.

    Pulls StartItem, RewardItem1-4, and RewardChoiceItem1-N. We don't try
    to distinguish "guaranteed reward" from "choice" or "start item" — for
    the Missing Recipes tab the relevant signal is "can I get this recipe
    by doing some quest", and any of those three column families satisfies
    that."""
    layout = QUEST_COLUMNS[label]
    item_cols = (layout["start"],) + layout["reward"] + layout["choice"]
    max_col = max(item_cols)

    path = EMUL_CACHE / f"{label}_quest_template.sql"
    out: dict[int, set[int]] = {}
    for cols in parse_insert_rows(path):
        if len(cols) <= max_col:
            continue
        try:
            quest_id = int(cols[0])
        except ValueError:
            continue
        for ci in item_cols:
            try:
                item_id = int(cols[ci])
            except ValueError:
                continue
            if item_id:
                out.setdefault(item_id, set()).add(quest_id)
    return out


# ---------------------------------------------------------------------------
# Per-source aggregation
# ---------------------------------------------------------------------------

def collect_sources_from(label: str, item_to_spell: dict, spell_to_prof: dict):
    """Build {profId: {spellId: {field: {npcId: ""}}}} for one emulator source.

    Trainer entries are keyed by spell directly (the trainer table already
    tells us which spell). Vendor / drop entries need the item→spell reverse
    lookup to know which recipe each item teaches.
    """
    print(f"\n[{label}] parsing trainer / vendor / loot / quest / container tables",
          file=sys.stderr)
    trainers_by_spell = parse_trainers(label)
    print(f"  trainers:  {len(trainers_by_spell):,} spell-NPC mappings",
          file=sys.stderr)
    vendor_by_item    = parse_npc_vendor(label)
    print(f"  vendors:   {len(vendor_by_item):,} items on vendors",
          file=sys.stderr)
    creature_loot     = parse_creature_loot(label)
    print(f"  c-loot:    {len(creature_loot):,} creatures with loot",
          file=sys.stderr)
    go_loot           = parse_gameobject_loot(label)
    print(f"  GO-loot:   {len(go_loot):,} GOs with loot",
          file=sys.stderr)
    item_loot         = parse_item_loot(label)
    print(f"  i-loot:    {len(item_loot):,} container items with contents",
          file=sys.stderr)
    quest_by_item     = parse_quest_rewards(label)
    print(f"  quests:    {len(quest_by_item):,} items as quest reward / start",
          file=sys.stderr)

    sources: dict[int, dict[int, dict[str, set[int]]]] = {}

    # Trainer: spell → [npcId]. Filter to recipe spells only.
    for spell_id, npcs in trainers_by_spell.items():
        prof_id = spell_to_prof.get(spell_id)
        if prof_id is None:
            continue
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("trainer", set()).update(npcs)

    # Vendor: item → [npcId]; convert via item_to_spell.
    for item_id, npcs in vendor_by_item.items():
        target = item_to_spell.get(item_id)
        if not target:
            continue
        prof_id, spell_id = target
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("vendor", set()).update(npcs)

    # Creature loot: drop. Reverse the {creature: items} index.
    item_to_creatures: dict[int, set[int]] = {}
    for cid, items in creature_loot.items():
        for iid in items:
            item_to_creatures.setdefault(iid, set()).add(cid)
    for item_id, creatures in item_to_creatures.items():
        target = item_to_spell.get(item_id)
        if not target:
            continue
        prof_id, spell_id = target
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("drop", set()).update(creatures)

    # GO loot: also "drop" (chests / nodes — players think of them as drops).
    item_to_gos: dict[int, set[int]] = {}
    for goid, items in go_loot.items():
        for iid in items:
            item_to_gos.setdefault(iid, set()).add(goid)
    for item_id, gos in item_to_gos.items():
        target = item_to_spell.get(item_id)
        if not target:
            continue
        prof_id, spell_id = target
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("drop", set()).update(gos)

    # Item loot (containers): mapped to the "container" source kind in our
    # SRC_LABELS — clams, crafty quest reward boxes, etc. The Entry of an
    # item_loot_template row is itself an item id; we credit the container
    # item id as the source.
    item_to_containers: dict[int, set[int]] = {}
    for container_item, items in item_loot.items():
        for iid in items:
            item_to_containers.setdefault(iid, set()).add(container_item)
    for item_id, containers in item_to_containers.items():
        target = item_to_spell.get(item_id)
        if not target:
            continue
        prof_id, spell_id = target
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("container", set()).update(containers)

    # Quest rewards / starts: credit the questId (NOT an NPC id). The addon's
    # MissingRecipesTab SRC_LABELS has "quest" tied to a localized "Quest"
    # tag; it doesn't display the questId, just the category.
    for item_id, quests in quest_by_item.items():
        target = item_to_spell.get(item_id)
        if not target:
            continue
        prof_id, spell_id = target
        slot = sources.setdefault(prof_id, {}).setdefault(spell_id, {})
        slot.setdefault("quest", set()).update(quests)

    return sources


# ---------------------------------------------------------------------------
# Merge + emit
# ---------------------------------------------------------------------------

def merge_sources(*per_source_dicts):
    """Union {profId: {spellId: {field: set}}} dicts across emulators. Sets
    union element-wise per (prof, spell, field)."""
    merged: dict = {}
    for src in per_source_dicts:
        for prof_id, recipes in src.items():
            prof_slot = merged.setdefault(prof_id, {})
            for spell_id, fields in recipes.items():
                spell_slot = prof_slot.setdefault(spell_id, {})
                for field, ids in fields.items():
                    spell_slot.setdefault(field, set()).update(ids)
    return merged


def emit_source_file(prof_id: int, filename: str, recipes: dict):
    """Write Data/Sources/<filename>.lua in the addon's expected shape."""
    cleaned = {}
    for spell_id, fields in recipes.items():
        # Convert {field: set} → {field: {[id]=""}}
        out_fields = {}
        for field_name, ids in fields.items():
            if not ids:
                continue
            out_fields[field_name] = {nid: "" for nid in sorted(ids)}
        if out_fields:
            cleaned[spell_id] = out_fields
    body = lua_value(cleaned, 1)
    target = SOURCES_DIR / f"{filename}.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        "local _, addon = ...\n"
        "\n"
        f"addon.sourceDB[{prof_id}] = {body}\n"
    )
    target.write_text(contents, encoding="utf-8")
    return len(cleaned), target


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--refresh", action="store_true",
                    help="Re-download cached emulator SQL files.")
    args = ap.parse_args()

    # Make sure all SQL caches exist (download/extract on first run).
    print("[prep] ensuring TrinityCore Cata tables are extracted",
          file=sys.stderr)
    _prepare_trinity_cata(refresh=args.refresh)
    print("[prep] ensuring AzerothCore Wrath tables are downloaded",
          file=sys.stderr)
    for src in SOURCES:
        if src["name"] == "azerothcore_wrath":
            ensure_files(src, refresh=args.refresh)

    spell_to_prof, item_to_spell = build_reverse_maps()

    cata_sources  = collect_sources_from("trinity_cata",      item_to_spell, spell_to_prof)
    wrath_sources = collect_sources_from("azerothcore_wrath", item_to_spell, spell_to_prof)
    merged        = merge_sources(cata_sources, wrath_sources)

    print(f"\n=== Emitting Data/Sources/*.lua ===")
    print(f"{'profession':<18} {'sourced':>8}  {'output'}")
    total = 0
    for prof_id, (filename, _) in sorted(PROF_FILES.items(),
                                           key=lambda kv: kv[1][0]):
        recipes = merged.get(prof_id, {})
        count, path = emit_source_file(prof_id, filename, recipes)
        total += count
        print(f"{filename:<18} {count:>8}  {path.relative_to(ADDON_ROOT)}")
    print(f"{'TOTAL':<18} {total:>8}")


if __name__ == "__main__":
    main()
