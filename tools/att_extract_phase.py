#!/usr/bin/env python3
"""Phase B+ extractor (v0.5.4) — TBC per-recipe phase derivation from ATT.

Walks AllTheThings' per-expansion db/<Exp>/Categories/*.lua files via the
lupa-based att_probe primitives, merges per-recipe field data across files
(crucially: Zones.lua often has `minReputation` and `awp` fields that
Professions.lua omits for the same spellId), then derives a content-phase
integer per recipe using these signals in order of confidence:

  1. Boss-drop containment in a known TBC raid `inst()`
       745 -> 1 (Karazhan)
       748 -> 2 (Serpentshrine Cavern)
       749 -> 2 (Tempest Keep: The Eye)
       750 -> 3 (Battle of Mount Hyjal)
       751 -> 3 (Black Temple)
       249 -> 4 (Magisters' Terrace)
       752 -> 4 (Sunwell Plateau)

  2. Reputation gate (minReputation field)
       faction 935 (Shattered Sun Offensive) -> phase 4
       faction 933 (Scale of the Sands)      -> phase 3
       faction 1012 (Ashtongue Deathsworn)   -> phase 3
       (Aldor/Scryer/CE/etc. are launch reps and don't gate phase here)

  3. Patch tag (awp field)
       awp >= 20400 -> phase 4 (patch 2.4 Sunwell)
       awp >= 20300 -> phase 3 (patch 2.3 Zul'Aman / mid-TBC content)

  4. Fallback -> phase 1 (TBC launch / unidentified)

Output: tools/wago_cache/att_phase_map.json -> {"spellId": phase} for every
spell ATT covers in TBC. The consumer (build_authoritative_data.py) reads
this map and stamps `phase = N` onto matching entries in the emitted
Data/Recipes/*.lua. The Lua addon then filters Missing Recipes by
client-current phase.

Only TBC is covered in v0.5.4 (matches the immediate user-reported bug
scope). Wrath/Cata/MoP phases follow the same shape and will be added in
later patches.
"""

import json
import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from att_probe import execute_att_file, ATT_ANNIV  # type: ignore


# TBC raid/instance -> phase number. Identified by their `lore` field in
# ATT (see tools/att_probe.py verification step).
TBC_RAID_PHASE = {
    745: 1,  # Karazhan
    748: 2,  # Serpentshrine Cavern
    749: 2,  # Tempest Keep: The Eye
    750: 3,  # Battle of Mount Hyjal
    751: 3,  # Black Temple
    249: 4,  # Magisters' Terrace (5-man Sunwell-era)
    752: 4,  # Sunwell Plateau
}

# Reputation faction id -> phase. Curated from Wowhead faction pages.
TBC_FACTION_PHASE = {
    935:  4,  # Shattered Sun Offensive (Sunwell daily / quartermaster)
    933:  3,  # Scale of the Sands (Hyjal attunement / rewards)
    1012: 3,  # Ashtongue Deathsworn (Black Temple)
}


# Files to merge for TBC. Order matters only for the inst() walk — the
# field merge keeps every key from every file (first-seen wins per key).
TBC_FILES = [
    "Professions.lua",
    "Instances.lua",
    "Zones.lua",
    "WorldDrops.lua",
    "Craftables.lua",
]


def merge_recipe_fields(captures):
    """Union recipe field dicts across multiple ATT captures.

    First-seen wins per field (a later file ADDS missing fields but won't
    overwrite an existing one). Crucial because Professions.lua often has
    only a few fields while Zones.lua has the phase-relevant ones for the
    same spellId.
    """
    merged = {}
    for cap in captures:
        for sid, fields in cap["recipes"].items():
            if sid not in merged:
                merged[sid] = dict(fields)
            else:
                for k, v in fields.items():
                    if k not in merged[sid]:
                        merged[sid][k] = v
    return merged


def build_inst_spell_phases(inst_cap, raid_phase_map):
    """Walk Instances.lua captures to find recipes nested under each raid
    inst(). Returns {spellId: phase} for recipes that are boss/instance drops.

    Latest-phase wins on conflict (a recipe also referenced elsewhere stays
    at its highest known phase — Sunwell content beats a Karazhan re-mention).
    """
    def walk_for_recipes(obj, out):
        if isinstance(obj, dict):
            if obj.get("_TOGPM_TYPE") == "r":
                sid = obj.get("_TOGPM_ID")
                if isinstance(sid, (int, float)) and sid > 0:
                    out.add(int(sid))
            for v in obj.values():
                walk_for_recipes(v, out)
        elif isinstance(obj, list):
            for v in obj:
                walk_for_recipes(v, out)

    spell_phase = {}
    for ntype, nid, fields in inst_cap["nodes"]:
        if ntype != "inst" or nid not in raid_phase_map:
            continue
        spells = set()
        walk_for_recipes(fields, spells)
        ph = raid_phase_map[nid]
        for sid in spells:
            if ph > spell_phase.get(sid, 0):
                spell_phase[sid] = ph
    return spell_phase


def derive_phase(sid, fields, inst_phase_for_spell, faction_phase, awp_phase_thresholds):
    """Combine signals in confidence order. Returns phase int (1-4)."""
    # 1. boss-drop inst() containment
    p = inst_phase_for_spell.get(sid)
    if p:
        return p
    # 2. reputation gate
    mr = fields.get("minReputation") or {}
    faction = mr.get(1) if isinstance(mr, dict) else None
    p = faction_phase.get(faction)
    if p:
        return p
    # 3. patch-add tag
    awp = fields.get("awp") or 0
    for threshold, ph in awp_phase_thresholds:
        if awp >= threshold:
            return ph
    # 4. default
    return 1


def main():
    print("== ATT phase extractor (TBC) ==", file=sys.stderr)
    print("  loading ATT files via lupa...", file=sys.stderr)

    tbc_dir = ATT_ANNIV / "TBC" / "Categories"
    captures = []
    for f in TBC_FILES:
        path = tbc_dir / f
        if not path.exists():
            print(f"  WARNING: {path} missing, skipping", file=sys.stderr)
            continue
        cap = execute_att_file(path)
        print(f"    {f}: {len(cap['recipes'])} recipes captured", file=sys.stderr)
        captures.append(cap)

    merged_fields = merge_recipe_fields(captures)
    print(f"  merged unique recipes: {len(merged_fields)}", file=sys.stderr)

    # Inst-based phase data only from Instances.lua (other files don't have
    # inst() calls). Find it by index of TBC_FILES.
    inst_cap = next(c for c, name in zip(captures, TBC_FILES) if name == "Instances.lua")
    inst_phase_for_spell = build_inst_spell_phases(inst_cap, TBC_RAID_PHASE)
    print(f"  inst-boss-drop spells: {len(inst_phase_for_spell)}", file=sys.stderr)

    awp_thresholds = [(20400, 4), (20300, 3)]

    spell_phase = {}
    for sid, fields in merged_fields.items():
        spell_phase[sid] = derive_phase(
            sid, fields, inst_phase_for_spell, TBC_FACTION_PHASE, awp_thresholds
        )

    # Coverage stats
    import collections
    dist = collections.Counter(spell_phase.values())
    print(f"\n  TBC phase distribution across {len(spell_phase)} ATT recipes:", file=sys.stderr)
    for p in sorted(dist):
        print(f"    Phase {p}: {dist[p]:>4} recipes", file=sys.stderr)

    # Write JSON for the build pipeline. Keys as strings because JSON.
    out_path = SCRIPT_DIR / "wago_cache" / "att_phase_map.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out = {
        "expansion": "TBC",
        "build":     "anniversary 2.5.5",
        "phase_count": 4,
        "spell_phase": {str(sid): ph for sid, ph in spell_phase.items()},
    }
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"\n  wrote {out_path.relative_to(SCRIPT_DIR.parent)} "
          f"({out_path.stat().st_size:,} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
