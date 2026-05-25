#!/usr/bin/env python3
"""ATT phase-data extractor — verification probe.

Iteratively-developed parser for AllTheThings' per-expansion
db/<Expansion>/Categories/Professions.lua files. Strategy: execute ATT's
Lua directly via lupa with stubbed helpers (r, prof, cat, etc.) that
record their arguments into Python, instead of parsing Lua text by hand.
We never write our own parsing logic — we just let Lua do what it does
and capture the call args.

This is the SMALL-SUBSET verification step. Hard-coded ground-truth
recipe IDs below are the things we visually confirmed in ATT's file by
eye; output must match them exactly before we trust the extractor on
the rest of ATT's data.
"""

import pathlib
import sys

from lupa import LuaRuntime

ATT_ANNIV = pathlib.Path(
    "c:/Program Files (x86)/World of Warcraft/_anniversary_"
    "/Interface/AddOns/AllTheThings/db"
)
ATT_ERA = pathlib.Path(
    "c:/Program Files (x86)/World of Warcraft/_classic_era_"
    "/Interface/AddOns/AllTheThings/db"
)

# Per-expansion ground-truth subsets — recipe entries we visually verified
# in each file. The probe MUST reproduce these exactly before we trust the
# parser to ingest the rest of ATT's data.
#
# Note: ATT's per-expansion files INHERIT recipes from earlier expansions
# (the three TBC Alchemy specs 28677/28675/28672 appear in Wrath/Cata/Mists
# files too as the cumulative profession tree carries forward). That's
# expected — our parser will store the most-recently-seen entry per spellId
# when we run all files in order.
EXPECTED = {
    "TBC": {
        "path": ATT_ANNIV / "TBC" / "Categories" / "Professions.lua",
        "checks": {
            28677: {"requireSkill": 28677},
            28675: {"requireSkill": 28675},
            28672: {"requireSkill": 28672},
            24844: {"awp": 20001, "lvl": 10, "rank": 1, "crs": {1: 20797}},
            36258: {"awp": 20001, "learnedAt": 375, "requireSkill": 17039, "u": 17},
            34537: {"awp": 20001, "learnedAt": 375, "requireSkill": 17039, "u": 17},
            34535: {"awp": 20001, "learnedAt": 350, "requireSkill": 17039, "u": 17},
            34538: {"awp": 20001, "learnedAt": 350, "requireSkill": 17039, "u": 17},
        },
    },
    "Wrath": {
        "path": ATT_ANNIV / "Wrath" / "Categories" / "Professions.lua",
        "checks": {
            # Inherited TBC entries appear in Wrath file too
            28677: {"requireSkill": 28677},
            # Wrath-specific entry
            66659: {"learnedAt": 440, "requireSkill": 171, "u": 32},
        },
    },
    "Cata": {
        "path": ATT_ANNIV / "Cata" / "Categories" / "Professions.lua",
        "checks": {
            28677: {"requireSkill": 28677},
            28675: {"requireSkill": 28675},
        },
    },
    "Mists": {
        "path": ATT_ANNIV / "Mists" / "Categories" / "Professions.lua",
        "checks": {
            28677: {"requireSkill": 28677},
            28675: {"requireSkill": 28675},
        },
    },
    "Vanilla": {
        "path": ATT_ERA / "Vanilla" / "Categories" / "Professions.lua",
        "checks": {
            # Vanilla file starts with pet-ability recipes (Hunter pet skill line)
            24493: {"lvl": 20, "rank": 1},
            24497: {"lvl": 30, "rank": 2},
            24500: {"lvl": 40, "rank": 3},
            24501: {"lvl": 50, "rank": 4},
        },
    },
}


def lua_table_to_py(t, depth=0):
    """Convert a lupa Lua table to a plain Python dict/list, recursively.

    lupa returns Lua tables as a proxy object; we copy into native Python
    so the captured data survives after the LuaRuntime is GC'd.
    """
    if t is None:
        return None
    # lupa-LuaTable: detect via duck-typing on .items()
    if hasattr(t, "items"):
        out = {}
        for k, v in t.items():
            # Lua's `nil` shouldn't surface but guard anyway
            if k is None:
                continue
            out[k] = lua_table_to_py(v, depth + 1)
        return out
    return t


def build_lua_stubs(lua, captured):
    """Inject stub implementations of ATT's helper functions into the
    Lua environment. Every call records its arguments into `captured`
    so we can inspect them post-execute.

    Functions stubbed correspond to the local-aliases at the top of
    ATT's Professions.lua:
        ach (CreateAchievement), cat (CreateCategory), flt (CreateFilter),
        h (CreateCustomHeader), i (CreateItem), prof (CreateProfession),
        q (CreateQuest), qo (CreateQuestObjective), r (CreateRecipe),
        x (CreateExpansion)
    Plus _.AddEventHandler which the file uses to register the deferred
    builder callback.
    """
    captured["recipes"]    = {}      # spellId -> last-seen fields dict
    captured["all_calls"]  = []      # debug: every helper call in order
    # NEW: every node creation returns a sentinel Lua table tagged with its
    # type + id. When a CONTAINER helper (h/inst/e/cat/etc.) is called, its
    # received fields table contains its children (often under fields.g) —
    # since Lua evaluates inner calls first, those children are our sentinel
    # tables. Walking the captured fields lets us recover ancestor → child
    # relationships post-execute, which is how we find e.g. recipes nested
    # inside Sunwell Plateau's inst() wrapper.
    captured["nodes"] = []  # list of (node_type, id, fields) tuples

    def make_stub(name, store_recipes_by_id=False):
        def stub(arg1=None, arg2=None, *rest):
            id_val   = arg1
            fields   = lua_table_to_py(arg2)
            captured["all_calls"].append((name, id_val, fields))
            if store_recipes_by_id and isinstance(id_val, (int, float)):
                captured["recipes"][int(id_val)] = fields or {}
            try:
                int_id = int(id_val) if isinstance(id_val, (int, float)) else id_val
            except (TypeError, ValueError):
                int_id = id_val
            captured["nodes"].append((name, int_id, fields))
            # Return the ORIGINAL Lua fields table (arg2) with our type/id
            # stamped onto it. This preserves the nested child sentinels:
            # when a parent helper later receives this in its g={...}, the
            # parent's lua_table_to_py descends into the same Lua table and
            # finds the type/id stamps on every nested level. Without this
            # pass-through, parents only saw {_TYPE, _ID} with NO children
            # and the tree walk found nothing.
            if arg2 is not None:
                try:
                    arg2["_TOGPM_TYPE"] = name
                    arg2["_TOGPM_ID"]   = int_id if isinstance(int_id, (int, float)) else 0
                    return arg2
                except (TypeError, KeyError, AttributeError):
                    pass
            return lua.table_from({
                "_TOGPM_TYPE": name,
                "_TOGPM_ID":   int_id if isinstance(int_id, (int, float)) else 0,
            })
        return stub

    # The _ object (ATT's private table). Enumerate every helper we've
    # observed across the per-expansion Categories files. New unknown
    # helpers in a future expansion's file will surface as a clear Lua
    # "attempt to call a nil value (local 'X')" error naming the missing
    # alias — easy to add. Tried a __index metatable approach but lupa's
    # table_from + setmetatable interaction was fragile; explicit table
    # is cleaner.
    underscore = lua.table_from({
        "AddEventHandler":          lambda evt, fn: captured.setdefault("handlers", []).append((evt, fn)),
        # Recipe constructor — the one we actually care about
        "CreateRecipe":             make_stub("r", store_recipes_by_id=True),
        # Generic constructors used across TBC / Wrath / Cata / Mists files
        "CreateAchievement":        make_stub("ach"),
        "CreateAchievementCriteria": make_stub("crit"),
        "CreateCategory":           make_stub("cat"),
        "CreateCustomHeader":       make_stub("h"),
        "CreateExpansion":          make_stub("x"),
        "CreateFilter":             make_stub("flt"),
        "CreateHeader":             make_stub("ah"),
        "CreateItem":               make_stub("i"),
        "CreateNPC":                make_stub("n"),
        # Instance / encounter / object stubs (used in Instances.lua, Zones.lua)
        "CreateInstance":           make_stub("inst"),
        "CreateEncounter":          make_stub("e"),
        "CreateObject":             make_stub("o"),
        "CreateDifficulty":         make_stub("d"),
        "CreateCharacterClass":     make_stub("cl"),
        "CreateCharacterUnlockSpell": make_stub("cs"),
        "CreateMount":              make_stub("mnt"),
        "CreateToy":                make_stub("toy"),
        # Zones.lua additions
        "CreateExploration":        make_stub("exp"),
        "CreateFlightPath":         make_stub("fp"),
        "CreateMap":                make_stub("m"),
        "CreateCurrencyClass":      make_stub("cu"),
        "CreateFaction":            make_stub("faction"),
        "CreateHeirloom":           make_stub("heir"),
        "CreateProfession":         make_stub("prof"),
        "CreateQuest":              make_stub("q"),
        "CreateQuestObjective":     make_stub("qo"),
        "CreateSpecies":            make_stub("p"),
        "CreateItemSource":         make_stub("s"),
        "CreateSpell":              make_stub("sp"),
        "CreateTitle":              make_stub("title"),
        "CreateVignette":           make_stub("vig"),
        # Non-function members ATT files reference as tables
        "OnTooltipDB":              lua.table_from({}),
        "OnUpdateDB":               lua.table_from({}),
        # OnInitDB is accessed dynamically: ATT does
        #   (_.OnInitDB.GenerateCompareOtherKey_NNNNN)(i(...))
        # — the field name is auto-generated per item. We can't enumerate
        # them, but the call shape is always wrapper(thing) returning the
        # thing. Make it a proxy table whose __index always returns the
        # identity function so ATT's wrapper-then-call pattern just passes
        # the inner value through unchanged. Built in Lua-land below
        # because lupa's table_from + metatables don't compose cleanly
        # from Python.
        "OnSaveDB":                 lua.table_from({}),
        "OnLoadDB":                 lua.table_from({}),
        "Settings":                 lua.table_from({}),
        # Utility functions ATT calls inline. Each just returns nil so the
        # surrounding expression evaluates harmlessly. Not data-bearing.
        "ResolveQuestData":         lambda *a: None,
        "GetRelativeValue":         lambda *a: None,
        "GetRelativeField":         lambda *a: None,
        "Merge":                    lambda *a: None,
        "ApplyClassicPhases":       lambda *a: None,
    })
    # Replace OnInitDB with a Lua-side proxy table whose __index returns an
    # identity function for any field. ATT's pattern is
    #   (_.OnInitDB.GenerateCompareOtherKey_NNNNN)(i(itemId, {...}))
    # where the field name is auto-generated per item. We can't enumerate
    # them; the identity proxy makes every such wrapper a no-op.
    lua.execute("""
        _TOGPM_IDENTITY = function(x) return x end
        _TOGPM_PROXY = setmetatable({}, {__index = function(t, k) return _TOGPM_IDENTITY end})
    """)
    underscore["OnInitDB"] = lua.globals()["_TOGPM_PROXY"]

    lua.globals()["_TOGPM_UNDERSCORE"] = underscore


def execute_att_file(path: pathlib.Path):
    """Load and run an ATT Categories file under the Lua VM. Returns the
    `captured` dict containing recipes + all-call log."""
    captured = {}
    lua = LuaRuntime(unpack_returned_tuples=True)
    build_lua_stubs(lua, captured)

    # ATT files start with a UTF-8 BOM (EF BB BF) — WoW's Lua loader
    # silently strips it, standard Lua's `load` errors with
    # "unexpected symbol near '<\\239>'". Strip explicitly here.
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    source = raw.decode("utf-8", errors="replace")
    # ATT's file does `local appName, _ = ...;` to read varargs.
    # Wrap so we control what's passed.
    wrapped = (
        "local appName, _ = ...\n"
        + source
    )
    chunk = lua.eval(
        "function(src, name, underscore) "
        "  local f, err = load(src, '@att_chunk', 't') "
        "  if not f then error(err) end "
        "  return f(name, underscore) "
        "end"
    )
    chunk(wrapped, "AllTheThings", lua.globals()["_TOGPM_UNDERSCORE"])

    # The file registered an OnBuildDataCache handler; fire it with a
    # fake categories table to materialise the recipes.
    for evt, fn in captured.get("handlers", []):
        if evt == "OnBuildDataCache":
            fake_categories = lua.table_from({})
            fn(fake_categories)

    return captured


def verify_one(label: str, path: pathlib.Path, checks: dict) -> int:
    if not path.exists():
        print(f"[{label}] NOT FOUND at {path}", file=sys.stderr)
        return -1
    print(f"\n[{label}] executing {path.name}...", file=sys.stderr)
    captured = execute_att_file(path)
    print(f"  recipes captured: {len(captured['recipes'])}", file=sys.stderr)
    print(f"  total helper calls: {len(captured['all_calls'])}", file=sys.stderr)
    failures = 0
    for spell_id, expected in checks.items():
        got = captured["recipes"].get(spell_id)
        if got is None:
            print(f"  FAIL spell={spell_id}: NOT FOUND in captured data")
            failures += 1
            continue
        mismatches = []
        for k, v in expected.items():
            if got.get(k) != v:
                mismatches.append(f"{k}: expected {v!r}, got {got.get(k)!r}")
        if mismatches:
            print(f"  FAIL spell={spell_id}: {'; '.join(mismatches)}")
            print(f"       full captured: {got}")
            failures += 1
        else:
            print(f"  OK   spell={spell_id}: {got}")
    return failures


def main():
    total_fail = 0
    for label, cfg in EXPECTED.items():
        f = verify_one(label, cfg["path"], cfg["checks"])
        if f < 0:
            total_fail += 1
        else:
            total_fail += f
    print()
    if total_fail:
        print(f"FAILED: {total_fail} total mismatches across expansions", file=sys.stderr)
        sys.exit(1)
    print("All expansion subsets verified. Parser is trustworthy for full ingestion.")


if __name__ == "__main__":
    main()
