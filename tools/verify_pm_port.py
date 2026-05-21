#!/usr/bin/env python3
"""Verify the v0.4.6 PM port against ProfessionMaster's source data.

Re-parses PM's models/skills/*.lua + models/recipe-sources/*.lua and our
Data/Recipes/*.lua + Data/Sources/*.lua, then reports:

  1. Recipe coverage: counts per profession (PM vs. ours), per-expansion;
     lists any spell ids PM has that we don't (the "dropped" set) and
     ours-only entries (legacy PersonalShopper data PM didn't have).

  2. Field accuracy: per-recipe checks on `difficulty` and `requiredSkill`
     for the subset present in both. Mismatches are bucketed and a sample
     of each bucket is printed.

  3. Source linkage: for each PM recipe whose recipe-item has vendor /
     drop / quest entries in PM's sources file, confirm the corresponding
     spell in our sourceDB has at least one matching source kind. Catches
     the failure mode where the recipeItem -> spellId conversion silently
     loses vendor/drop/quest sources.

Exits 0 always (this is an audit, not a gate). Output is grouped by
profession with summary counters; pass --sample N to widen the printed
example list per bucket (default 5).
"""

import argparse
import pathlib
import re
import sys

try:
    from slpp import slpp
except ImportError:
    print("Missing 'slpp'. Install with: python -m pip install slpp", file=sys.stderr)
    sys.exit(1)

# Reuse the shared parsing primitives + config from port_pm_data.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from port_pm_data import (  # type: ignore
    ADDON_ROOT, PM_ROOT, EXPANSIONS, PROF_FILES,
    strip_lua_chrome, parse_lua_table, load_pm,
)


PROF_NAMES = {
    164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy",
    182: "Herbalism",     185: "Cooking",        186: "Mining",
    197: "Tailoring",     202: "Engineering",    333: "Enchanting",
    129: "First Aid",     356: "Fishing",        755: "Jewelcrafting",
    773: "Inscription",   393: "Skinning",
}


# ---------------------------------------------------------------------------
# Load sides
# ---------------------------------------------------------------------------

def load_pm_all():
    """Return {profId: {spellId: {"d": [...], "r": <item|list>, "exp": "vanilla"|...}}}
    and {profId: {spellId: <recipeItem ids list>}} (the second copy is just
    a convenience for the source check)."""
    by_prof: dict = {}
    pm_sources_by_exp: dict = {}  # {exp: {itemId: {...}}}
    for exp in EXPANSIONS:
        skills_path  = PM_ROOT / "models" / "skills" / f"{exp}.lua"
        sources_path = PM_ROOT / "models" / "recipe-sources" / f"{exp}.lua"
        if not skills_path.exists() or not sources_path.exists():
            continue
        skills  = load_pm(skills_path)
        sources = load_pm(sources_path)
        pm_sources_by_exp[exp] = {}
        if isinstance(sources, dict):
            for k, v in sources.items():
                try:
                    pm_sources_by_exp[exp][int(k)] = v
                except (ValueError, TypeError):
                    pass
        if not isinstance(skills, dict):
            continue
        for spell_id, entry in skills.items():
            if not isinstance(entry, dict):
                continue
            prof_id = entry.get("p")
            if not isinstance(prof_id, (int, float)):
                continue
            prof_id = int(prof_id)
            try:
                spell_id_i = int(spell_id)
            except (ValueError, TypeError):
                continue
            # Normalize difficulty to a list
            diff = entry.get("d") or []
            if isinstance(diff, dict):
                diff_list = [diff[k] for k in sorted(diff.keys()) if isinstance(k, (int, float))]
            elif isinstance(diff, list):
                diff_list = list(diff)
            else:
                diff_list = []
            # Normalize recipe-item to a list
            r = entry.get("r")
            r_ids: list = []
            if isinstance(r, (int, float)):
                r_ids.append(int(r))
            elif isinstance(r, dict):
                for k in sorted(r.keys()):
                    v = r[k]
                    if isinstance(v, (int, float)):
                        r_ids.append(int(v))
            elif isinstance(r, list):
                for v in r:
                    if isinstance(v, (int, float)):
                        r_ids.append(int(v))
            slot = by_prof.setdefault(prof_id, {})
            # Last expansion wins, matching port_pm_data.convert_skills
            # which does `recipe_db[prof][spell] = {...}` on every pass.
            # Many recipes appear in multiple expansion files with rebalanced
            # difficulty curves; the latest balance is what ships.
            slot[spell_id_i] = {
                "d":   diff_list,
                "r":   r_ids,
                "exp": exp,
            }
    return by_prof, pm_sources_by_exp


def load_ours():
    """Parse our Data/Recipes/*.lua + Data/Sources/*.lua. Returns
       ({profId: {spellId: {difficulty, requiredSkill, teaches}}},
        {profId: {spellId: {vendor:{}, drop:{}, quest:{}, trainer:{}}}}).
    """
    recipes_by_prof: dict = {}
    sources_by_prof: dict = {}
    for prof_id, fname in PROF_FILES.items():
        rec_path = ADDON_ROOT / "Data" / "Recipes"  / f"{fname}.lua"
        src_path = ADDON_ROOT / "Data" / "Sources"  / f"{fname}.lua"
        if rec_path.exists():
            try:
                parsed = parse_lua_table(rec_path.read_text(encoding="utf-8"))
            except Exception as exc:
                print(f"  could not parse {rec_path}: {exc}", file=sys.stderr)
                parsed = {}
            slot = recipes_by_prof.setdefault(prof_id, {})
            if isinstance(parsed, dict):
                for k, v in parsed.items():
                    try:
                        slot[int(k)] = v
                    except (ValueError, TypeError):
                        pass
        if src_path.exists():
            try:
                parsed = parse_lua_table(src_path.read_text(encoding="utf-8"))
            except Exception as exc:
                print(f"  could not parse {src_path}: {exc}", file=sys.stderr)
                parsed = {}
            slot = sources_by_prof.setdefault(prof_id, {})
            if isinstance(parsed, dict):
                for k, v in parsed.items():
                    try:
                        slot[int(k)] = v
                    except (ValueError, TypeError):
                        pass
    return recipes_by_prof, sources_by_prof


# ---------------------------------------------------------------------------
# Diff logic
# ---------------------------------------------------------------------------

def coverage_diff(pm_by_prof: dict, ours_recipes: dict, sample_n: int):
    """Per-profession recipe count + missing-id report.

    Skips profs not in PROF_FILES (PM emits 182 Herbalism / 393 Skinning
    with no recipes; both are profession-only-extra and we never carried
    them)."""
    print("\n=== Recipe coverage ===")
    print(f"{'profId':>6}  {'profession':<14} {'PM':>6}  {'Ours':>6}  "
          f"{'dropped':>8}  {'extra':>6}")
    total_pm = 0
    total_ours = 0
    total_dropped = 0
    total_extra = 0
    dropped_by_prof: dict = {}
    extra_by_prof: dict = {}
    all_profs = sorted(set(pm_by_prof) | set(ours_recipes))
    for prof_id in all_profs:
        pm_set   = set(pm_by_prof.get(prof_id, {}).keys())
        ours_set = set(ours_recipes.get(prof_id, {}).keys())
        dropped  = pm_set - ours_set
        extra    = ours_set - pm_set
        dropped_by_prof[prof_id] = dropped
        extra_by_prof[prof_id]   = extra
        total_pm      += len(pm_set)
        total_ours    += len(ours_set)
        total_dropped += len(dropped)
        total_extra   += len(extra)
        flag = "" if prof_id in PROF_FILES else "  (skipped: no Data file)"
        print(f"{prof_id:>6}  {PROF_NAMES.get(prof_id,'?'):<14} "
              f"{len(pm_set):>6}  {len(ours_set):>6}  "
              f"{len(dropped):>8}  {len(extra):>6}{flag}")
    print(f"{'TOTAL':>6}  {'':<14} {total_pm:>6}  {total_ours:>6}  "
          f"{total_dropped:>8}  {total_extra:>6}")

    # Show sample of dropped per prof (limited to tracked profs)
    for prof_id, dropped in sorted(dropped_by_prof.items()):
        if prof_id not in PROF_FILES or not dropped:
            continue
        sample = sorted(dropped)[:sample_n]
        more = "" if len(dropped) <= sample_n else f" (+{len(dropped)-sample_n} more)"
        print(f"  [drop {PROF_NAMES.get(prof_id,'?')}] sample spells: "
              f"{sample}{more}")
    for prof_id, extra in sorted(extra_by_prof.items()):
        if prof_id not in PROF_FILES or not extra:
            continue
        sample = sorted(extra)[:sample_n]
        more = "" if len(extra) <= sample_n else f" (+{len(extra)-sample_n} more)"
        print(f"  [extra {PROF_NAMES.get(prof_id,'?')}] sample spells: "
              f"{sample}{more}  (legacy PS data / not in PM)")


def field_diff(pm_by_prof: dict, ours_recipes: dict, sample_n: int):
    """Compare `difficulty` array and `requiredSkill` on the intersection."""
    print("\n=== Field accuracy (difficulty + requiredSkill) ===")
    diff_mismatches: list = []
    req_mismatches: list = []
    teaches_mismatches: list = []
    compared = 0
    for prof_id, pm_recipes in pm_by_prof.items():
        if prof_id not in PROF_FILES:
            continue
        our_recipes = ours_recipes.get(prof_id, {})
        for spell_id, pm_entry in pm_recipes.items():
            our_entry = our_recipes.get(spell_id)
            if not isinstance(our_entry, dict):
                continue
            compared += 1
            pm_diff = pm_entry["d"]
            our_diff = our_entry.get("difficulty")
            if isinstance(our_diff, dict):
                our_diff_list = [our_diff[k] for k in sorted(our_diff.keys()) if isinstance(k, (int, float))]
            elif isinstance(our_diff, list):
                our_diff_list = list(our_diff)
            else:
                our_diff_list = []
            # Coerce to ints for comparison; PM stores ints; PS-curated data
            # sometimes came in as floats. Tolerate that.
            def _norm(xs):
                out = []
                for x in xs:
                    try:
                        out.append(int(x))
                    except (TypeError, ValueError):
                        out.append(x)
                return out
            if _norm(pm_diff) != _norm(our_diff_list):
                diff_mismatches.append((prof_id, spell_id, pm_diff, our_diff_list))

            # requiredSkill should equal first difficulty step
            expected_req = pm_diff[0] if pm_diff else 1
            our_req = our_entry.get("requiredSkill")
            try:
                if int(our_req) != int(expected_req):
                    req_mismatches.append((prof_id, spell_id, expected_req, our_req))
            except (TypeError, ValueError):
                req_mismatches.append((prof_id, spell_id, expected_req, our_req))

            # teaches should equal the spell id (self-teaching, see port_pm_data
            # comment). Anything else is a bug in the converter.
            our_teaches = our_entry.get("teaches")
            try:
                if int(our_teaches) != spell_id:
                    teaches_mismatches.append((prof_id, spell_id, spell_id, our_teaches))
            except (TypeError, ValueError):
                teaches_mismatches.append((prof_id, spell_id, spell_id, our_teaches))
    print(f"compared:                  {compared:>5} (PM intersect ours)")
    print(f"difficulty mismatches:     {len(diff_mismatches):>5}")
    print(f"requiredSkill mismatches:  {len(req_mismatches):>5}")
    print(f"teaches mismatches:        {len(teaches_mismatches):>5}")
    for label, rows in (("difficulty", diff_mismatches),
                        ("requiredSkill", req_mismatches),
                        ("teaches", teaches_mismatches)):
        for prof_id, spell, expected, got in rows[:sample_n]:
            print(f"  [{label}] {PROF_NAMES.get(prof_id,'?')} spell={spell} "
                  f"expected={expected!r} got={got!r}")


def source_linkage_check(pm_by_prof: dict, pm_sources_by_exp: dict,
                          ours_sources: dict, sample_n: int):
    """For every PM recipe whose recipe-item carries vendor/drop/quest in
    PM's recipe-sources file, confirm our sourceDB has at least one source
    kind present for that spell.

    This catches the failure mode where recipeItem -> spellId conversion
    silently drops sources (e.g. mis-keyed lookup tables). Trainer-only
    PM recipes (r=null) are skipped: we layer those in from MTSL +
    emulator data, not PM.
    """
    print("\n=== Source linkage (vendor/drop/quest from PM -> our spell) ===")
    src_kinds = ("vendor", "drop", "quest")
    missing_kinds: list = []
    coverage_buckets = {"only_in_pm": 0, "matched": 0, "no_pm_source": 0}
    for prof_id, recipes in pm_by_prof.items():
        if prof_id not in PROF_FILES:
            continue
        our_src_for_prof = ours_sources.get(prof_id, {})
        for spell_id, entry in recipes.items():
            r_ids = entry["r"]
            exp = entry["exp"]
            # No item teaches this recipe → trainer-only, skip
            if not r_ids:
                continue
            # Aggregate PM's source kinds across all r_ids AND all expansions
            # for this spell. The converter unions sources across expansions
            # via the deep-merge in convert_skills; verify must do the same
            # or it will under-count "sources we should have surfaced."
            pm_kinds = set()
            for rid in r_ids:
                for src_by_item in pm_sources_by_exp.values():
                    pm_src = src_by_item.get(rid)
                    if not isinstance(pm_src, dict):
                        continue
                    if isinstance(pm_src.get("vendors"), dict) and pm_src["vendors"]:
                        pm_kinds.add("vendor")
                    if isinstance(pm_src.get("drops"), dict) and pm_src["drops"]:
                        pm_kinds.add("drop")
                    if isinstance(pm_src.get("quests"), dict) and pm_src["quests"]:
                        pm_kinds.add("quest")
                    if pm_src.get("worldDrop"):
                        pm_kinds.add("drop")  # we map worldDrop -> drop[-1]
            if not pm_kinds:
                coverage_buckets["no_pm_source"] += 1
                continue
            our_entry = our_src_for_prof.get(spell_id) or {}
            our_kinds = {k for k in src_kinds if isinstance(our_entry.get(k), dict)
                         and our_entry[k]}
            absent = pm_kinds - our_kinds
            if absent:
                missing_kinds.append((prof_id, spell_id, sorted(pm_kinds),
                                       sorted(our_kinds), sorted(absent)))
                coverage_buckets["only_in_pm"] += 1
            else:
                coverage_buckets["matched"] += 1

    print(f"PM recipes with sources:    "
          f"{coverage_buckets['matched'] + coverage_buckets['only_in_pm']:>5}")
    print(f"  fully matched in ours:    {coverage_buckets['matched']:>5}")
    print(f"  missing >=1 source kind:  {coverage_buckets['only_in_pm']:>5}")
    print(f"PM recipes w/o any sources: {coverage_buckets['no_pm_source']:>5}"
          f" (trainer / drop-only PM didn't catalog — not a bug)")
    for prof_id, spell, pm_kinds, our_kinds, absent in missing_kinds[:sample_n]:
        print(f"  [{PROF_NAMES.get(prof_id,'?')} spell={spell}] "
              f"PM has {pm_kinds}, ours has {our_kinds}, missing {absent}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sample", type=int, default=5,
                    help="Number of example rows to print per mismatch bucket.")
    args = ap.parse_args()

    if not PM_ROOT.exists():
        print(f"ProfessionMaster not found at {PM_ROOT}", file=sys.stderr)
        sys.exit(2)

    print("Loading PM source data...", file=sys.stderr)
    pm_by_prof, pm_sources_by_exp = load_pm_all()
    print("Loading our Data/* output...", file=sys.stderr)
    ours_recipes, ours_sources = load_ours()

    coverage_diff(pm_by_prof, ours_recipes, args.sample)
    field_diff(pm_by_prof, ours_recipes, args.sample)
    source_linkage_check(pm_by_prof, pm_sources_by_exp, ours_sources, args.sample)


if __name__ == "__main__":
    main()
