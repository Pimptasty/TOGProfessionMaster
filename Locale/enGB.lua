-- TOG Profession Master -- English (Great Britain) locale
--
-- enGB clients fall back to enUS for every key not explicitly overridden
-- below. The TOGPM string set has no current US/UK divergence (no "color"
-- vs "colour" / "center" vs "centre" / etc. that the user would see), so
-- this file just registers the locale so the client recognises it and
-- inherits enUS verbatim. Add UK-specific overrides here if any string
-- ever genuinely needs to differ from US English.

local _, addon = ...
local L = addon.NewLocale("enGB")  --luacheck: ignore L

-- (no overrides — full fallback to enUS via AceLocale and addon.Locales)
