#!/usr/bin/env python3
"""Spike: fetch a full profession's recipe list from wago.tools DBC tables.

Validates the v0.5.0 pipeline by pulling Cata Tailoring (skill line 197) from
build 4.4.2.60895 and joining:

    SkillLine        ->  profession definitions (find "Tailoring")
    SkillLineAbility ->  spell-id -> profession link (filter by SkillLine=197)
    SpellName        ->  spell-id -> localized name
    ItemEffect       ->  spell-id -> recipe item that teaches it
    ItemSparse       ->  item-id  -> recipe item name
    SpellReagents    ->  spell-id -> {reagent itemId: count}  (if available)

Reports:
    - Total recipe count from DBC (authoritative)
    - Comparison to PM's count for the same profession
    - 10 sample recipes with all joined fields

CSV downloads are cached in tools/wago_cache/ so re-runs are fast. Pass
--refresh to re-fetch.
"""

import argparse
import csv
import io
import pathlib
import sys
import urllib.request
import urllib.error

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
CACHE_DIR  = SCRIPT_DIR / "wago_cache"

# Build IDs validated against /api/builds; see CHANGELOG context for the full
# table. We default to Cata 4.4.2 here because it has the broadest profession
# coverage (Inscription, Jewelcrafting present; not yet MoP-rebalanced).
DEFAULT_BUILD = "4.4.2.60895"

# Skill line ID -> profession name. From SkillLine table; hardcoded here for
# the spike since these IDs are stable across every expansion.
PROF_NAMES = {
    164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy",
    182: "Herbalism",     185: "Cooking",        186: "Mining",
    197: "Tailoring",     202: "Engineering",    333: "Enchanting",
    129: "First Aid",     356: "Fishing",        755: "Jewelcrafting",
    773: "Inscription",   393: "Skinning",
}


def fetch_csv(table: str, build: str, refresh: bool = False,
              locale: str | None = None) -> list[dict]:
    """Download a wago.tools CSV table and return parsed rows as dicts.

    Cached under tools/wago_cache/<build>__<table>[__<locale>].csv so repeat
    runs are instant. enUS (the wago default) uses the un-suffixed cache name,
    so existing caches keep working and aren't re-downloaded. Other locales add
    &locale=<locale> to the request and a __<locale> cache suffix. Raises on
    HTTP errors (no fallback — we want to know).
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    loc = locale if (locale and locale != "enUS") else None
    suffix = f"__{loc}" if loc else ""
    cache = CACHE_DIR / f"{build}__{table}{suffix}.csv"
    if not cache.exists() or refresh:
        url = f"https://wago.tools/db2/{table}/csv?build={build}"
        if loc:
            url += f"&locale={loc}"
        print(f"  fetching {url}", file=sys.stderr)
        req = urllib.request.Request(url, headers={"User-Agent": "TOGPM/0.5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            cache.write_bytes(resp.read())
        print(f"    wrote {cache.name}: {cache.stat().st_size:,} bytes",
              file=sys.stderr)
    text = cache.read_text(encoding="utf-8", errors="replace")
    reader = csv.DictReader(io.StringIO(text))
    return list(reader)


def find_profession_id(skill_line_rows: list[dict], name_hint: str) -> int | None:
    """Look up a skill line by the 'DisplayName_lang' column. wago.tools' CSV
    column name for the localised display includes the _lang suffix because
    Blizzard's DB2 wide format stores per-locale columns."""
    for row in skill_line_rows:
        if (row.get("DisplayName_lang") or "").strip().lower() == name_hint.lower():
            try:
                return int(row["ID"])
            except (TypeError, ValueError, KeyError):
                return None
    return None


def pm_recipe_count(prof_id: int) -> int | None:
    """Quick sanity check vs. ProfessionMaster's data (if installed alongside
    our addon). Returns count of recipes PM has for prof_id, or None when PM
    isn't available."""
    pm_root = SCRIPT_DIR.parent.parent / "ProfessionMaster"
    if not pm_root.exists():
        return None
    try:
        from port_pm_data import load_pm, strip_lua_chrome  # type: ignore
    except ImportError:
        return None
    total = 0
    for exp in ("vanilla", "bcc", "wrath", "cata", "mop"):
        path = pm_root / "models" / "skills" / f"{exp}.lua"
        if not path.exists():
            continue
        try:
            skills = load_pm(path)
        except Exception:
            continue
        if not isinstance(skills, dict):
            continue
        seen = set()
        for spell_id, entry in skills.items():
            if isinstance(entry, dict) and entry.get("p") == prof_id:
                try:
                    seen.add(int(spell_id))
                except (TypeError, ValueError):
                    pass
        total = max(total, len(seen))
    return total


def probe_one(args, prof_name: str, prof_id_hint: int | None,
              skill_lines, sla, spell_names, item_effects, item_sparse,
              verbose: bool = True):
    """Run the join for a single profession using pre-fetched tables. Returns
    (dbc_count, pm_count, recipes_list)."""
    prof_id = prof_id_hint or find_profession_id(skill_lines, prof_name)
    if prof_id is None:
        if verbose:
            print(f"  {prof_name!r} not found in SkillLine table", file=sys.stderr)
        return 0, None, []

    recipes = []
    for row in sla:
        try:
            if int(row.get("SkillLine") or 0) == prof_id:
                recipes.append({
                    "spell":   int(row["Spell"]),
                    "minRank": int(row.get("MinSkillLineRank") or 0),
                })
        except (TypeError, ValueError, KeyError):
            continue

    name_by_spell = {}
    for row in spell_names:
        try:
            name_by_spell[int(row["ID"])] = row.get("Name_lang", "")
        except (TypeError, ValueError, KeyError):
            continue

    spell_to_items: dict[int, set[int]] = {}
    for row in item_effects:
        try:
            sid = int(row.get("SpellID") or row.get("Spell") or 0)
            iid = int(row.get("ParentItemID") or row.get("ItemID") or 0)
            if sid and iid:
                spell_to_items.setdefault(sid, set()).add(iid)
        except (TypeError, ValueError, KeyError):
            continue

    for r in recipes:
        r["name"]  = name_by_spell.get(r["spell"], "?")
        r["items"] = sorted(spell_to_items.get(r["spell"], set()))

    pm_count = pm_recipe_count(prof_id)
    return len(recipes), pm_count, recipes


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--build", default=DEFAULT_BUILD,
                    help=f"wago.tools build ID (default: {DEFAULT_BUILD})")
    ap.add_argument("--profession", default="Tailoring",
                    help="Profession DisplayName to probe (default: Tailoring)")
    ap.add_argument("--all", action="store_true",
                    help="Probe every profession in PROF_NAMES instead of a single one.")
    ap.add_argument("--refresh", action="store_true",
                    help="Force re-download cached CSVs.")
    args = ap.parse_args()

    print(f"== wago.tools probe ==", file=sys.stderr)
    print(f"   build:      {args.build}", file=sys.stderr)
    print(f"   profession: {'<all>' if args.all else args.profession}",
          file=sys.stderr)

    # Fetch all tables once; both single and --all modes reuse them.
    print(f"\nfetching DBC tables", file=sys.stderr)
    skill_lines  = fetch_csv("SkillLine",        args.build, refresh=args.refresh)
    sla          = fetch_csv("SkillLineAbility", args.build, refresh=args.refresh)
    spell_names  = fetch_csv("SpellName",        args.build, refresh=args.refresh)
    item_effects = fetch_csv("ItemEffect",       args.build, refresh=args.refresh)
    item_sparse  = fetch_csv("ItemSparse",       args.build, refresh=args.refresh)

    if args.all:
        print(f"\n=== Per-profession DBC vs PM coverage (build {args.build}) ===")
        print(f"{'profession':<18} {'DBC':>6} {'PM':>6} {'delta':>7} {'PM coverage':>13}")
        totals = {"dbc": 0, "pm": 0}
        for pid, pname in sorted(PROF_NAMES.items(), key=lambda kv: kv[1]):
            dbc, pm, _ = probe_one(args, pname, pid,
                                    skill_lines, sla, spell_names,
                                    item_effects, item_sparse,
                                    verbose=False)
            totals["dbc"] += dbc
            totals["pm"]  += (pm or 0)
            pm_str = str(pm) if pm is not None else "-"
            delta_str = f"+{dbc - (pm or 0)}" if pm is not None else "-"
            pct = (pm * 100 / dbc) if (pm and dbc) else 0
            pct_str = f"{pct:5.1f}%" if pm is not None and dbc else "-"
            print(f"{pname:<18} {dbc:>6} {pm_str:>6} {delta_str:>7} {pct_str:>13}")
        delta_total = totals["dbc"] - totals["pm"]
        pct_total = (totals["pm"] * 100 / totals["dbc"]) if totals["dbc"] else 0
        print(f"{'TOTAL':<18} {totals['dbc']:>6} {totals['pm']:>6} "
              f"{'+'+str(delta_total):>7} {pct_total:5.1f}%")
        return

    # Single-profession mode (default): run the probe + show samples.
    dbc, pm, recipes = probe_one(args, args.profession, None,
                                  skill_lines, sla, spell_names,
                                  item_effects, item_sparse,
                                  verbose=True)
    if dbc == 0:
        sys.exit(1)

    # Hydrate item names for the sample block below.
    name_by_item = {}
    for row in item_sparse:
        try:
            name_by_item[int(row["ID"])] = row.get("Display_lang", "")
        except (TypeError, ValueError, KeyError):
            continue
    for r in recipes:
        r["itemNames"] = [name_by_item.get(iid, "?") for iid in r["items"]]

    # Report.
    print(f"\n=========================================")
    print(f"DBC: {dbc} {args.profession} recipes "
          f"(build {args.build})")
    if pm is not None:
        delta = dbc - pm
        sign = "+" if delta >= 0 else ""
        print(f"PM:  {pm} {args.profession} recipes  "
              f"(delta {sign}{delta} vs DBC)")
    print(f"=========================================\n")

    # Sample first 10 recipes (sorted by required skill rank).
    recipes.sort(key=lambda r: (r["minRank"], r["spell"]))
    print(f"First 10 by minRank:")
    for r in recipes[:10]:
        item_str = (", ".join(f"[{iid}] {n}" for iid, n in
                              zip(r["items"], r["itemNames"]))
                    if r["items"] else "(no recipe item; trainer-taught)")
        print(f"  spell={r['spell']:>6}  minRank={r['minRank']:>3}  "
              f"{r['name']:<30}  via: {item_str}")

    # Count how many recipes have no recipe item (trainer-taught) vs have one.
    trainer_only = sum(1 for r in recipes if not r["items"])
    with_item    = len(recipes) - trainer_only
    print(f"\nBreakdown:")
    print(f"  trainer-taught (no item):  {trainer_only}")
    print(f"  taught by recipe scroll:    {with_item}")


if __name__ == "__main__":
    main()
