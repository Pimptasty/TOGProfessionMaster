# TOGProfessionMaster — Copilot Instructions

WoW Classic Era addon. Lua 5.1, AceGUI-3.0, AceDB-3.0.

## Always

- **Use AceGUI widgets** — never raw `CreateFrame()` unless a specific WoW API requires it.
- **Use AceGUI methods** — e.g. `widget:SetFont()` not `widget.label:SetFont()`. Raw fontstring calls leak into recycled widgets.
- **Persistent windows** — never call `Release()` on a window that stays open. Use `ReleaseChildren()` + `Show()` to refresh content, matching the PersonalShopper/Grouper pattern.
- **Tooltip positioning** — always use `addon.Tooltip.Owner(frame)` (defined in Compat.lua). Never call `GameTooltip:SetOwner()` directly.
- **Look at other addons in the workspace first** — PersonalShopper, Grouper, etc. often have the exact pattern needed. Check them before inventing a solution.
- **Fix lint/compile errors automatically** without being asked.
