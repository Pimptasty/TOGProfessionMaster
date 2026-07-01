-- TOG Profession Master -- Filipino (filPH) locale
--
-- IMPORTANT: filPH is NOT a WoW-recognized locale code. GetLocale() will
-- never return "filPH" on any Blizzard client, so AceLocale will never
-- auto-select this file. This locale is reachable ONLY via the Settings
-- "UI Language Override" dropdown (default Auto). Filipino-speaking
-- players on enUS or zhTW WoW builds can opt into Filipino addon UI
-- while in-game item / spell / NPC names continue to render in their
-- client's actual locale (since those come from Blizzard's APIs, not
-- from this addon).
--
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("filPH")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Talaan ng Sync"

-- Tab labels
L["TabProfessions"]     = "Mga Propesyon"
L["TabCooldowns"]       = "Mga Cooldown"
L["TabReagents"]        = "Mga Sangkap"
L["TabMissingRecipes"]  = "Mga Kulang na Resipi"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Maghanap ng resipi…"
L["ViewGuild"]          = "Guild"
L["ViewMine"]           = "Aking mga karakter"
L["AllProfessions"]     = "Lahat ng propesyon"
L["PanelProfessions"]   = "Mga Propesyon"
L["PanelCharacters"]    = "Mga Karakter"
L["SelectProfession"]   = "Pumili ng propesyon"
L["NoDataYet"]          = "|cffaaaaaa(wala pang data)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Pumili ng propesyon upang makita kung sino ang may alam nito.|r"
L["NoProfMembers"]      = "|cffaaaaaa(walang miyembro ng guild na may propesyong ito)|r"
L["BackToCharacters"]   = "|cff00aaff← Bumalik sa mga karakter|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(walang tumutugmang resipi)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Ikaw"
L["BrowserScanAH"]          = "I-scan ang AH"
L["BrowserScanAHProgress"]  = "Sina-scan %d/%d"
L["BrowserScanAHDesc"]      = "Ini-scan ang auction house para sa bawat sangkap sa iyong listahan ng pamimili. Ang mga hanay na ang sangkap ay nasa AH ngayon ay nakakakuha ng pindutang [AH]; pindutin upang tumalon nang direkta sa paghahanap ng AH."
L["CooldownsScanAHDesc"]    = "Ini-scan ang auction house para sa bawat natatanging sangkap sa nakikitang mga hanay ng cooldown. Ang mga hanay na ang sangkap ay nasa AH ngayon ay nakakakuha ng pindutang [AH] (sa kaliwa ng [Bangko]); pindutin upang tumalon sa paghahanap."

-- Recipe detail popup
L["PopupCrafters"]       = "Kilala ng"
L["PopupOnList"]         = "Nasa listahan ng pamimili"
L["PopupNotOnList"]      = "Wala sa listahan"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Handa lamang"
L["ShowAll"]                = "Lahat"
L["FilterColProfession"]    = "Propesyon"
L["FilterColCooldown"]      = "Cooldown"
L["FilterColView"]          = "Tingnan"
L["FilterProfessionDesc"]   = "I-filter ang listahan ng cooldown sa isang propesyon (Alkimya, Pananahi, atbp.)."
L["FilterCooldownDesc"]     = "Sa loob ng napiling propesyon, i-filter ayon sa isang nakabahaging cooldown (hal. Transmute, Mooncloth)."
L["FilterViewDesc"]         = "Lumipat sa pagitan ng mga cooldown ng lahat ng miyembro ng guild at sa iyong sariling mga karakter lamang."
L["AllCooldowns"]           = "Lahat ng cooldown"
L["FilterTransmute"]            = "Transmute"
L["FilterAlchResearch"]         = "Pananaliksik sa Alkimya"
L["FilterMooncloth"]            = "Telang Buwan"
L["FilterSpecialtyCloth"]       = "Espesyal na Tela"
L["FilterGlacialBag"]           = "Bag na Glacial"
L["FilterDreamcloth"]           = "Telang Panaginip"
L["FilterImperialSilk"]         = "Imperyal na Sutla"
L["FilterSaltShaker"]           = "Lalagyan ng Asin"
L["FilterMagicSphere"]          = "Mahiwagang Sphere"
L["FilterShaCrystal"]           = "Kristal ng Sha"
L["FilterBrilliantGlass"]       = "Salaming Maningning"
L["FilterIcyPrism"]             = "Prismang Malamig"
L["FilterFirePrism"]            = "Prismang Apoy"
L["FilterJcDaily"]              = "Araw-araw na Paggupit ng Hiyas"
L["FilterInscriptionResearch"]  = "Pananaliksik sa Pagsulat"
L["FilterForgedDocuments"]      = "Pekeng mga Dokumento"
L["FilterScrollOfWisdom"]       = "Balumbon ng Karunungan"
L["FilterTitansteelBar"]        = "Bareta ng Titansteel"
L["FilterBsIngot"]              = "Pagtunaw"
L["FilterMagnificence"]         = "Kadakilaan"
L["FilterJards"]                = "Enerhiya ni Jard"
L["ColCharacter"]           = "Karakter"
L["ColCooldown"]            = "Cooldown"
L["ColReagent"]             = "Sangkap"
L["ColTimeLeft"]            = "Natitirang Oras"
L["NoCooldownData"]         = "|cffaaaaaa(wala pang data ng cooldown — magbukas ng trade skill window)|r"
L["Ready"]                  = "|cff00ff00Handa|r"
L["Transmute"]              = "Transmute"
L["MailBtn"]                = "Sulat"
L["MailBtnTooltip"]         = "Magpadala ng sulat na suplay"
L["MailBtnTooltipDesc"]     = "Magbukas ng mailbox, pagkatapos ay pindutin upang ilakip ang mga sangkap at sumulat ng suplay na sulat sa manlalaro na ito."
L["BankBtn"]                = "[Bangko]"
L["CloseBtn"]               = "Isara"

-- Tagapagpahiwatig ng bonus output ng espesyalisasyon ng propesyon
L["SpecBonusGuaranteedDouble"]  = "Garantisadong 2x na produksyon"
L["SpecBonusProcChance"]        = "Tsansa na makagawa ng karagdagang produksyon"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Listahan ng Pamimili"
L["SectionMissingReagents"] = "Mga Kulang na Sangkap"
L["SectionReagentWatch"]    = "Pagsubaybay sa Sangkap"
L["ShoppingListEmpty"]      = "|cffaaaaaa(walang laman — pindutin ang isang hanay ng resipi sa tab na Mga Propesyon upang magdagdag ng item sa iyong listahan ng pamimili)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(walang laman ang listahan ng pamimili o lahat ng sangkap ay nasa mga bag)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(walang sinusubaybayang item — magpasok ng ID ng item o link sa itaas)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(hindi naka-load ang module ng ReagentWatch)|r"
L["WatchInputLabel"]        = "ID ng item o link"
L["WatchBtn"]               = "Subaybayan"
L["WatchedItemsHeading"]    = "Mga Sinusubaybayang Item"
L["ColHave"]                = "Mayroon"
L["ColNeed"]                = "Kailangan"
L["ColShort"]               = "Kulang"
L["ColItem"]                = "Item"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Karakter|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Propesyon|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Maghanap ng resipi…|r"
L["MissingIncludeTrainer"]      = "Isama ang mga eksklusibong galing sa trainer"
L["MissingIncludeTrainerDesc"]  = "Isinasama ang mga resipi na natutunan lamang mula sa isang trainer (walang AH scroll)."
L["MissingScanAH"]              = "I-scan ang AH"
L["MissingScanAHProgress"]      = "Sina-scan %d/%d (pindutin upang kanselahin)"
L["MissingScanAHDesc"]          = "Magbukas ng auction house, pagkatapos ay pindutin upang i-scan ito para sa bawat scroll ng resipi sa nakikitang listahan. Ang mga hanay na may aktibong listings ay nakakakuha ng pindutang [AH]; pindutin upang tumalon sa paghahanap."
L["MissingNoCharacters"]        = "|cffaaaaaa(wala pang mga karakter na may data ng propesyon — magbukas ng trade skill window)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(ang karakter na ito ay wala pang sinusubaybayang propesyon — magbukas ng trade skill window)|r"
L["MissingNoneFound"]           = "|cff00ff00Natutunan na ang lahat ng kilalang resipi para sa propesyong ito.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Pumili ng propesyon upang makita kung ano ang kulang.|r"
L["MissingNoData"]              = "|cffff8888(walang available na data ng resipi para sa propesyong ito)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Resipi"
L["MissingColSkill"]            = "Kakayahan"
L["MissingColSource"]           = "Mga Pinagmulan"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Subaybayan ang scroll ng resiping ito"
L["MissingAddToWatchDesc"]      = "Idagdag ang scroll ng resipi sa iyong listahan ng Pagsubaybay sa Sangkap upang makita ito sa sandaling pumasok ito sa iyong mga bag."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Sinusubaybayan na — pindutin upang itigil ang pagsubaybay"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Kulang na Resipi"
L["MissingCountPlural"]         = "Mga Kulang na Resipi"
L["MissingTruncatedHint"]       = "(ipinapakita ang unang %d — mag-type sa search box upang paliitin ang listahan)"
L["MissingCharTooltipTitle"]    = "Filter ng Karakter"
L["MissingCharTooltipDesc"]     = "Piliin kung alin sa iyong mga karakter ang titingnan para sa mga kulang na resipi. Default ang kasalukuyang naka-log in na karakter."
L["MissingProfTooltipTitle"]    = "Filter ng Propesyon"
L["MissingProfTooltipDesc"]     = "Pumili ng propesyon upang makita ang mga scroll na hindi pa natututunan ng karakter na ito."
L["MissingSearchTooltipTitle"]  = "Maghanap ng Resipi"
L["MissingSearchTooltipDesc"]   = "Mag-type upang i-filter ang listahan ng kulang na resipi ayon sa pangalan."
L["MissingHdrCountTitle"]       = "Mga Kulang na Resipi"
L["MissingHdrCountDesc"]        = "Mga resiping hindi pa natututunan ng napiling karakter ngunit makukuha sa bersyon ng laro na ito. Ang numero ay sumasalamin sa kasalukuyang filter (propesyon, paghahanap, switch ng trainer)."
L["MissingHdrSkillTitle"]       = "Antas ng Kakayahan"
L["MissingHdrSkillDesc"]        = "Ang antas ng kakayahan ng propesyon na kinakailangan upang matutunan ang resiping ito. Ang mga hanay na kulay abo ay nangangahulugang hindi pa sapat ang antas ng karakter."
L["MissingHdrSourceTitle"]      = "Mga Pinagmulan"
L["MissingHdrSourceDesc"]       = "Paano makukuha ang resiping ito — trainer, drop, vendor, quest, o ginawa. I-hover ang teksto ng pinagmulan ng isang hanay para sa partikular na NPC / mob / hakbang."
L["MissingRowTooltipShift"]     = "Shift-click upang i-link sa chat."
L["MissingSrcVendor"]           = "Vendor"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Quest"
L["MissingSrcCrafted"]          = "Ginawa"
L["MissingSrcFishing"]          = "Pangingisda"
L["MissingSrcContainer"]        = "Lalagyan"
L["MissingSrcTrainer"]          = "Trainer"
L["MissingSrcOther"]            = "Iba pa"
L["MissingSrcUnknown"]          = "Hindi alam"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Tooltip ng Item"
L["SettingsTooltipShowCrafters"]    = "Ipakita ang mga tagagawa ng guild sa mga tooltip ng item"
L["SettingsTooltipShowCraftersDesc"]= "Magdaragdag ng linyang [TOGPM] na naglilista ng bawat kasama sa guild na maaaring gumawa ng item na iyong ini-hover. Online sa puti, offline sa kulay abo. Ang mga item na bound-on-pickup ay nilalaktawan (hindi naman maipagpapalit)."
L["SettingsTooltipShowIds"]         = "Ipakita ang item ID / spell ID sa mga tooltip"
L["SettingsTooltipShowIdsDesc"]     = "Magdaragdag ng linyang [TOGPM] na may item ID at (kung alam) spell ID ng resipi. Higit na kapaki-pakinabang para sa pag-diagnose ng maling icon o kulang na resipi — i-paste ang mga ID sa Wowhead upang i-verify ang tugma."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Phase ng TBC Anniversary"
L["SettingsTBCPhase"]           = "Kasalukuyang phase ng nilalaman"
L["SettingsTBCPhaseDesc"]       = "Itinatago ang mga Kulang na Resipi mula sa mas huling phase kaysa sa kasalukuyang phase ng Anniversary. Itaas ang halagang ito sa bawat oras na isulong ng Blizzard ang phase. (Ang mga resiping naa-access na sa aktibong phase ay nananatiling nakikita.)"
L["SettingsTBCPhase1"]          = "Phase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Phase 2 — Serpentshrine Cavern / Tempest Keep"
L["SettingsTBCPhase3"]          = "Phase 3 — Black Temple / Mount Hyjal"
L["SettingsTBCPhase4"]          = "Phase 4 — Sunwell / Magisters' Terrace"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Pagpapakita"
L["SettingsMinimapBtn"]          = "Ipakita ang pindutan ng minimap"
L["SettingsMinimapBtnDesc"]      = "Ipinapakita o itinatago ang launcher button sa minimap."
L["SettingsPersistProfFilter"]     = "Tandaan ang filter ng propesyon"
L["SettingsPersistProfFilterDesc"] = "Ibinabalik ang napiling propesyon kapag nag-log in o nag-reload."
L["SettingsSyncHeader"]     = "Sync"
L["SettingsGuildMode"]      = "Guild-only sync mode (mga pribadong server)"
L["SettingsGuildModeDesc"]  = "Para sa mga pribado o emulated na server (hal. Whitemane) na hindi naghahatid ng mga addon message sa pamamagitan ng whisper, na pumipigil sa mga miyembro ng guild na matanggap ang datos ng propesyon ng isa't isa. Kapag NAKABUKAS, ang lahat ng sync traffic ay iruruta sa guild channel. Buksan lamang ito kung hindi gumagana ang guild sync sa iyong server. |cffffd100Dapat itong buksan ng lahat sa guild|r — gumagana lamang ito sa pagitan ng mga miyembrong parehong nakabukas ito. Awtomatikong na-disable ang cross-guild sharing habang nakabukas ito. Naaangkop sa bawat character sa realm na ito. (Nakatago kung hindi ito suportado ng naka-install mong bersyon ng DeltaSync.)"
L["SettingsCooldownsHeader"]= "Mga Cooldown"
L["SettingsMailReadyOnly"]  = "Sulat: ipakita lamang ang mga handang cooldown"
L["SettingsMailReadyOnlyDesc"] = "Kapag sumusulat ng supply mail mula sa panel ng cooldown, ilista lamang ang mga miyembro ng guild na ang cooldown ay handa na."
L["SettingsDevHeader"]      = "Developer"
L["SettingsDebug"]          = "Debug output"
L["SettingsDebugDesc"]      = "Naglilimbag ng mga detalyadong mensahe ng debug sa chat frame."
L["SettingsDataHeader"]     = "Data"
L["SettingsSyncNow"]        = "Pwersahing mag-resync"
L["SettingsSyncNowDesc"]    = "I-broadcast ang iyong data ng propesyon sa guild kaagad."
L["SettingsPurgeGuild"]     = "Burahin ang lahat ng data ng guild"
L["SettingsPurgeGuildDesc"] = "Tatanggalin ang lahat ng nakaimbak na data ng propesyon at cooldown para sa bawat miyembro ng guild sa account na ito. Hindi maibabalik."
L["SettingsPurgeGuildConfirm"] = "Tanggalin ang LAHAT ng data ng guild para sa account na ito?"
L["SettingsPurgeMine"]      = "Burahin ang data ng aking karakter"
L["SettingsPurgeMineDesc"]  = "Tatanggalin lamang ang nakaimbak na data ng iyong sariling karakter mula sa database ng guild."
L["SettingsPurgeMineConfirm"] = "Tanggalin ang iyong sariling data ng propesyon at cooldown?"
L["SettingsSyncLogHeader"]  = "Talaan ng Sync"
L["SettingsViewLog"]        = "Tingnan ang talaan ng sync"
L["SettingsViewLogDesc"]    = "Nagbubukas ng nasusulyap na listahan ng mga kamakailang kaganapan ng sync (huling 200)."
L["SettingsClearLog"]       = "Burahin ang talaan ng sync"
L["SettingsClearLogConfirm"]= "Burahin ang lahat ng entry sa talaan ng sync?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(hindi naka-load ang module ng SyncLog)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(wala pang naitalang kaganapan ng sync)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Nakatago ang pindutan ng minimap. Gamitin ang |cffda8cff/togpm minimap|r upang ibalik."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Ginawa ni:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Handang gawin:|r %s × %d  (%s × %d sa mga bag)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "I-enable ang alerto ng tagagawa para sa resiping ito"
L["ShoppingAlertDisable"]              = "I-disable ang alerto ng tagagawa para sa resiping ito"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s ay online — maaaring gumawa: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s ay online (alt ni %s) — maaaring gumawa: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "I-enable ang alerto ng handa para sa cooldown na ito"
L["CooldownAlertDisable"]              = "I-disable ang alerto ng handa para sa cooldown na ito"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Handa ang cooldown: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Mga Alerto ng Tagagawa"
L["SettingsCrafterAlert"]              = "I-enable ang mga alerto ng tagagawa"
L["SettingsCrafterAlertDesc"]          = "Nagpe-play ng tunog at nagpapakislap sa screen kapag ang isang miyembro ng guild na maaaring gumawa ng inalertong item sa listahan ng pamimili ay nag-online."
L["SettingsCrafterAlertSuppressAudio"]     = "Pigilin ang tunog ng alerto"
L["SettingsCrafterAlertSuppressAudioDesc"] = "I-disable ang tunog kapag nag-online ang isang crafter (lalabas pa rin ang screen flash at mensahe sa chat)."
L["SettingsCrafterAlertSuppressVisual"]    = "Pigilin ang visual na alerto"
L["SettingsCrafterAlertSuppressVisualDesc"] = "I-disable ang visual na alerto sa screen (screen flash, banner, atbp.) kapag nag-online ang isang crafter (lalabas pa rin ang tunog at mensahe sa chat)."
L["AlertCrafterOnlineBanner"]              = "Online ang crafter ng guild"
L["SettingsCrafterAlertSound"]             = "Tunog ng alerto"
L["SettingsCrafterAlertSoundDesc"]         = "Kung aling tunog ang tutugtog kapag nag-online ang isang crafter na kayang mong abutin. Ang pagpili ng isa ay magpe-preview nito. Walang epekto habang pinipigilan ang tunog ng alerto sa itaas."
L["SettingsCrafterAlertVisual"]            = "Visual na alerto"
L["SettingsCrafterAlertVisualDesc"]        = "Kung aling epekto sa screen ang magpapaputok kapag nag-online ang isang crafter — isang full-screen na flash sa piniling mong kulay, o isang taskbar flash para kapag naka-alt-tab ka. Ang pagpili ng isa ay magpe-preview nito. Walang epekto habang pinipigilan ang screen flash sa itaas."
L["SettingsCrafterAlertSuppressLogin"]     = "Pigilin ang mga alerto sa pag-log in"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Huwag mag-fire ng mga alerto sa panahon ng panimulang pagsiklab ng mga online notification sa pag-log in o pag-reload."
L["SettingsCooldownAlertSuppressProtected"]     = "I-mute ang mga alerto sa mga instance"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Huwag mag-ping o magpalimbag ng mga alerto ng handang cooldown habang nasa raid, dungeon, battleground, arena, o scenario. Hindi pinipigilan ang mga kabisera — magpa-ping pa rin ang iyong transmute habang AFK ka sa Stormwind. Ang mga nakabinbing alerto ay magta-trigger sa sandaling umalis ka sa instance."
L["SettingsCooldownReminderInterval"]      = "Paalala ng handang cooldown"
L["SettingsCooldownReminderIntervalDesc"]  = "Muling magpapatupad ng bawat naka-arm na alerto ng cooldown tuwing N minuto habang nananatiling handa ang cooldown (ibig sabihin, hanggang gumawa ka talaga). Magpasok ng 0, walang laman, o 'off' upang mag-fire lamang nang isang beses sa bawat handang cycle. Wastong saklaw: 1–1440 minuto (24 na oras)."
L["SettingsCooldownReminderInvalid"]       = "Magpasok ng buong numero mula 0 hanggang 1440, o 'off'."

L["SettingsAHHeader"]                      = "Auction House"
L["SettingsAHScanDelay"]                   = "AH scan delay (segundo)"
L["SettingsAHScanDelayDesc"]               = "Mga segundo sa pagitan ng mga query ng AH scan. Walang laman / 0 / 'off' ay gumagamit ng default ng bersyon (1.5s sa Classic Era at Anniversary; 3.0s sa TBC, Wrath, Cata, MoP — mas mahigpit ang throttle ng mga server na iyon). Bawasan upang mas mabilis na scan, dagdagan kung huminto ang scan. Wastong saklaw: 0.5–10 segundo."
L["SettingsAHScanDelayInvalid"]            = "Magpasok ng numero mula 0.5 hanggang 10, o 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Resipi"
L["TooltipRecipeDesc"]           = "Ang pangalan ng magagawang item o spell."
L["TooltipCraftersTitle"]        = "Mga Tagagawa"
L["TooltipCraftersDesc"]         = "Mga miyembro ng guild na may alam sa resiping ito. Pindutin ang resipi para sa buong listahan."
L["CraftersColHeader"]           = "Mga Tagagawa"
L["TooltipBankTitle"]            = "Humiling mula sa Bangko"
L["TooltipBankDescScroll"]       = "Magpadala ng kahilingan sa isang banker ng guild na TOGBankClassic para sa scroll ng resiping ito."
L["TooltipBankDescGeneric"]      = "Magpadala ng kahilingan sa isang banker ng guild na TOGBankClassic."
L["TooltipAHTitle"]              = "Maghanap sa Auction House"
L["TooltipAHDescScroll"]         = "Buksan ang scroll ng resiping ito sa paghahanap ng AH."
L["TooltipAHDescReagent"]        = "Buksan ang sangkap na ito sa paghahanap ng AH."
L["TooltipSettingsTitle"]        = "Mga Setting"
L["TooltipSettingsDesc"]         = "Buksan ang panel ng setting ng TOG Profession Master (|cffffd700ESC > Mga Opsyon > Mga AddOn > TOG Profession Master|r). Parehong target ng |cffffd700/togpm settings|r at Shift+kaliwang click sa pindutan ng minimap."
L["TooltipWhisperRightClick"]    = "Kanang-click upang mag-whisper"
L["TooltipClickTransmutes"]      = "Pindutin upang makita ang mga transmute"
L["TooltipClickDetailsFormat"]   = "Pindutin upang makita ang %s"
L["TooltipClickDetailsFallback"] = "mga detalye"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Suplay ng cooldown: %s"
L["MailBodyFormat"]         = "Hi %s! Mangyaring gamitin ang mga materyales na ito upang gawin ang %s. Mangyaring ipadala sa akin ang %s kapag may panahon kang gawin ito. Salamat!"
L["MailMsgNoEmptyBag"]      = "Walang bakanteng slot ng bag para sa paghahati."
L["MailMsgOpenMailbox"]     = "Magbukas muna ng mailbox."
L["MailMsgHasItems"]        = "May nakalakip nang mga item sa sulat — ipadala o tanggalin muna ang mga ito."
L["MailMsgCannotFulfill"]   = "Hindi kayang tuparin."
L["MailMsgCouldNotAttach"]  = "Hindi maikabit ang mga item."
L["MailMsgAttachedFormat"]  = "Naikabit ang %dx %s para kay %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Kaliwang click|r upang i-toggle ang browser ng propesyon"
L["MinimapTooltipRightClick"]  = "|cffffd100Kanang click|r upang i-toggle ang mga sangkap"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+Kaliwa|r upang buksan ang mga setting"
L["MinimapButtonShown"]        = "Ipinakita ang pindutan ng minimap."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- hindi isinasalin ang mga pangalan ng utos
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — mga utos:"
L["SlashHelpOpen"]          = "buksan ang browser ng propesyon"
L["SlashHelpReagents"]      = "buksan ang mga kulang na sangkap"
L["SlashHelpMinimap"]       = "ipakita ang pindutan ng minimap"
L["SlashHelpPurge"]         = "buksan ang dialog ng pagbura"
L["SlashHelpSync"]          = "pwersahing buong pag-resync ng guild"
L["SlashHelpStatus"]        = "i-dump ang sync/comm diagnostic info"
L["SlashHelpVersionCheck"]  = "tingnan ang mga bersyon ng addon sa guild"
L["SlashHelpDebug"]         = "i-toggle ang debug output"
L["SlashHelpHelp"]          = "ipakita ang listahang ito"
L["SlashForceSyncSent"]     = "Ipinadala ang pwersadong sync."
L["AHScannerOpenAH"]        = "Magbukas ng auction house upang maghanap."
L["AHOpenFirst"]            = "Magbukas muna ng auction house."
L["AHNoItemsToScan"]        = "Walang item na isi-scan sa kasalukuyang view."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Humiling sa Guild Bank"
L["BankDialogBanker"]       = "Banker:"
L["BankDialogQty"]          = "Dami:"
L["BankDialogSend"]         = "Ipadala ang kahilingan"
L["BankDialogCancel"]       = "Kanselahin"

-- ---------------------------------------------------------------------------
-- Mga kumpirmasyon ng pagbura at iba pang slash output
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Binura ang lahat ng data ng guild."
L["MsgOwnDataPurged"]        = "Binura ang data ng iyong karakter."
L["SlashForceBroadcastSent"] = "Ipinadala ang pwersadong broadcast."
L["SlashDebugEnabled"]       = "|cff00ff00naka-enable|r"
L["SlashDebugDisabled"]      = "|cffff4444naka-disable|r"
L["SlashDebugToggleFormat"]  = "Debug output %s"

-- ---------------------------------------------------------------------------
-- Mga pangalan ng propesyon (lahat 15 — pagsasalin ng komunidad, malugod na tinatanggap ang pagsusuri)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alkimya"
L["ProfBlacksmithing"]  = "Pagpapanday"
L["ProfCooking"]        = "Pagluluto"
L["ProfEnchanting"]     = "Pang-eengkanto"
L["ProfEngineering"]    = "Inhinyerya"
L["ProfFirstAid"]       = "Unang Lunas"
L["ProfLeatherworking"] = "Pagtatrabaho sa Balat"
L["ProfMining"]         = "Pagmimina"
L["ProfTailoring"]      = "Pananahi"
L["ProfHerbalism"]      = "Halamang-gamot"
L["ProfSkinning"]       = "Pagbabalat"
L["ProfJewelcrafting"]  = "Paggawa ng Hiyas"
L["ProfInscription"]    = "Pagsulat"
L["ProfFishing"]        = "Pangingisda"
L["ProfSmelting"]       = "Pagtunaw"

-- ---------------------------------------------------------------------------
-- Crafting tab (added in v0.8.0) -- TODO: translate (English fallback for now)
-- ---------------------------------------------------------------------------
L["TabCrafting"]        = "Crafting"
L["CraftOpenAProfession"] = "Open a profession to craft."
L["CraftBlizzardUI"]      = "WoW UI"
L["CraftScanAH"]          = "Scan AH"
L["CraftScanAHProgress"]  = "%d/%d"
L["CraftScanAHDesc"]      = "Scan the Auction House for the selected recipe's reagents. Afterwards, an [AH] button appears next to each reagent that's for sale. Open the Auction House first."
L["CraftScanAHNoItems"]   = "Select a recipe first to scan its reagents."
L["CraftHaveMaterials"]   = "Have Materials"
L["CraftCostLabel"]       = "Crafting Cost"
L["CraftCostDesc"]        = "Estimated material cost for one craft: each reagent priced from the Auction House (Auctionator if installed, otherwise TOGPM's own AH scan) or vendor. \"*\" means one or more reagents had no price yet, so the total is a lower bound. \"~\" means a price is stale (>14 days)."
L["CraftCostNone"]        = "—"
L["CraftColCostHdr"]      = "Cost"
L["CraftColCostHdrDesc"]  = "Per-reagent cost: the price for the quantity this recipe needs (unit price × needed). Priced from the Auction House (Auctionator if enabled, else TOGPM's own scan) or vendor; \"—\" when no price is known yet."
L["CraftSearchDesc"]      = "Filter recipes by name or by what they do. Searches the enriched effect text too, so \"5 damage\", \"agility\", or \"mining\" all find matching recipes."
L["CraftColRecipe"]       = "Recipe Name"
L["CraftColRecipeDesc"]   = "The recipes you can make in this profession. Colour shows skill-up difficulty (orange/yellow/green/grey)."
L["CraftColCount"]        = "Craft"
L["CraftColCountDesc"]    = "How many you can craft right now with the materials on hand."
L["CraftColSkill"]        = "Skill"
L["CraftSortHint"]        = "Click to sort. Click again to reverse, once more to return to categories."
L["CraftNoRecipes"]       = "No recipes match."
L["CraftSelectRecipe"]    = "Select a recipe to see its reagents."
L["CraftReagents"]        = "Reagents"
L["CraftQuantity"]        = "Qty"
L["CraftMax"]             = "Max"
L["CraftMissingMaterials"] = "Missing Materials"
L["CraftBankReagentDesc"] = "A guild-bank character has this reagent. Click to request it."
L["CraftAHReagentDesc"]   = "The Auction House has this reagent (from your last scan). Click to search for it."
L["CraftReagentsDesc"]    = "Materials required to craft the selected recipe. The number is how many you have vs. how many you need; red means you're short."
L["CraftMissingMaterialsDesc"] = "Appears when you don't have enough of at least one reagent to craft this recipe."
L["CraftQueueHeaderTitle"] = "Queue"
L["CraftQueueHeaderDesc"]  = "Recipes you've queued to craft, in priority order. Drag rows to reorder; Craft Next makes the top one you can craft right now."
L["CraftHaveMaterialsDesc"] = "Show only recipes you can make right now with the materials on hand."
L["CraftButton"]          = "Craft"
L["CraftNoProfessions"]   = "You don't have any professions."
L["CraftProfessionDesc"]  = "Choose one of your professions. Selecting it opens that profession so you can craft."
L["CraftOpenToView"]      = "Open %s to view and craft its recipes."
L["CraftOpenButton"]      = "Open %s"
L["CraftCantOpenInCombat"] = "Can't open a profession while in combat."
L["CraftQueueTitle"]      = "Queue (%d)"
L["CraftQueueButton"]     = "Queue"
L["CraftCraftNext"]       = "Craft Next"
L["CraftClearAll"]        = "Clear All"
L["CraftMaxDesc"]         = "Set quantity to the most you can make with materials on hand."
L["CraftIncrease"]        = "Increase quantity"
L["CraftDecrease"]        = "Decrease quantity"
L["CraftButtonDesc"]      = "Craft the selected recipe now."
L["CraftQueueDesc"]       = "Add the selected recipe to the queue."
L["SettingsUseAuctionator"]                = "Use Auctionator pricing"
