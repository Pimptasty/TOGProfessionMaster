-- TOG Profession Master -- Thai (thTH) locale
--
-- IMPORTANT: thTH is NOT a WoW-recognized locale code. GetLocale() will
-- never return "thTH" on any Blizzard client, so AceLocale will never
-- auto-select this file. This locale is reachable ONLY via the Settings
-- "UI Language Override" dropdown (default Auto). Thai-speaking players
-- on enUS or zhTW WoW builds can opt into Thai addon UI while in-game
-- item / spell / NPC names continue to render in their client's actual
-- locale (since those come from Blizzard's APIs, not from this addon).
--
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("thTH")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — บันทึกการซิงค์"

-- Tab labels
L["TabProfessions"]     = "วิชาชีพ"
L["TabCooldowns"]       = "เวลาคูลดาวน์"
L["TabReagents"]        = "ส่วนผสม"
L["TabMissingRecipes"]  = "สูตรที่ขาดหายไป"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "ค้นหาสูตร…"
L["ViewGuild"]          = "กิลด์"
L["ViewMine"]           = "ตัวละครของฉัน"
L["AllProfessions"]     = "วิชาชีพทั้งหมด"
L["PanelProfessions"]   = "วิชาชีพ"
L["PanelCharacters"]    = "ตัวละคร"
L["SelectProfession"]   = "เลือกวิชาชีพ"
L["NoDataYet"]          = "|cffaaaaaa(ยังไม่มีข้อมูล)|r"
L["SelectProfHint"]     = "|cffaaaaaa← เลือกวิชาชีพเพื่อดูว่าใครรู้สูตรนี้|r"
L["NoProfMembers"]      = "|cffaaaaaa(ไม่มีสมาชิกกิลด์ที่มีวิชาชีพนี้)|r"
L["BackToCharacters"]   = "|cff00aaff← กลับไปที่ตัวละคร|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(ไม่พบสูตรที่ตรงกัน)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "คุณ"
L["BrowserScanAH"]          = "สแกน AH"
L["BrowserScanAHProgress"]  = "สแกน %d/%d"
L["BrowserScanAHDesc"]      = "สแกนตลาดประมูลสำหรับทุกส่วนผสมในรายการซื้อของคุณ แถวที่ส่วนผสมอยู่ใน AH จะมีปุ่ม [AH]; คลิกเพื่อกระโดดไปยังการค้นหา AH โดยตรง"
L["CooldownsScanAHDesc"]    = "สแกนตลาดประมูลสำหรับทุกส่วนผสมเฉพาะในแถวเวลาคูลดาวน์ที่มองเห็น แถวที่ส่วนผสมอยู่ใน AH จะมีปุ่ม [AH] (ทางซ้ายของ [Bank]); คลิกเพื่อกระโดดไปยังการค้นหา"

-- Recipe detail popup
L["PopupCrafters"]       = "ผู้รู้สูตร"
L["PopupOnList"]         = "อยู่ในรายการซื้อ"
L["PopupNotOnList"]      = "ไม่อยู่ในรายการซื้อ"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "พร้อมเท่านั้น"
L["ShowAll"]                = "ทั้งหมด"
L["FilterColProfession"]    = "วิชาชีพ"
L["FilterColCooldown"]      = "คูลดาวน์"
L["FilterColView"]          = "มุมมอง"
L["FilterProfessionDesc"]   = "กรองรายการคูลดาวน์ตามวิชาชีพเดียว (เล่นแร่แปรธาตุ, ตัดเย็บผ้า ฯลฯ)"
L["FilterCooldownDesc"]     = "ภายในวิชาชีพที่เลือก กรองตามคูลดาวน์ที่ใช้ร่วมกันเดียว (เช่น Transmute, Mooncloth)"
L["FilterViewDesc"]         = "สลับระหว่างคูลดาวน์ของสมาชิกกิลด์ทั้งหมดและตัวละครของคุณเท่านั้น"
L["AllCooldowns"]           = "คูลดาวน์ทั้งหมด"
L["FilterTransmute"]            = "แปรธาตุ"
L["FilterAlchResearch"]         = "งานวิจัยเล่นแร่แปรธาตุ"
L["FilterMooncloth"]            = "ผ้าจันทรา"
L["FilterSpecialtyCloth"]       = "ผ้าพิเศษ"
L["FilterGlacialBag"]           = "กระเป๋าน้ำแข็ง"
L["FilterDreamcloth"]           = "ผ้าฝัน"
L["FilterImperialSilk"]         = "ผ้าไหมจักรพรรดิ"
L["FilterSaltShaker"]           = "ที่ใส่เกลือ"
L["FilterMagicSphere"]          = "ทรงกลมเวทมนตร์"
L["FilterShaCrystal"]           = "คริสตัล Sha"
L["FilterBrilliantGlass"]       = "แก้วเปล่งประกาย"
L["FilterIcyPrism"]             = "ปริซึมน้ำแข็ง"
L["FilterFirePrism"]            = "ปริซึมไฟ"
L["FilterJcDaily"]              = "การเจียระไนรายวัน"
L["FilterInscriptionResearch"]  = "งานวิจัยการจารึก"
L["FilterForgedDocuments"]      = "เอกสารปลอม"
L["FilterScrollOfWisdom"]       = "ม้วนกระดาษแห่งปัญญา"
L["FilterTitansteelBar"]        = "แท่ง Titansteel"
L["FilterBsIngot"]              = "การหลอม"
L["FilterMagnificence"]         = "ความสง่างาม"
L["FilterJards"]                = "พลังของ Jard"
L["ColCharacter"]           = "ตัวละคร"
L["ColCooldown"]            = "คูลดาวน์"
L["ColReagent"]             = "ส่วนผสม"
L["ColTimeLeft"]            = "เวลาที่เหลือ"
L["NoCooldownData"]         = "|cffaaaaaa(ยังไม่มีข้อมูลคูลดาวน์ — เปิดหน้าต่างวิชาชีพ)|r"
L["Ready"]                  = "|cff00ff00พร้อม|r"
L["Transmute"]              = "แปรธาตุ"
L["MailBtn"]                = "จดหมาย"
L["MailBtnTooltip"]         = "ส่งจดหมายเสบียง"
L["MailBtnTooltipDesc"]     = "เปิดกล่องจดหมาย จากนั้นคลิกเพื่อแนบส่วนผสมและเขียนจดหมายเสบียงถึงผู้เล่นคนนี้"
L["BankBtn"]                = "[ธนาคาร]"
L["CloseBtn"]               = "ปิด"

-- ตัวบ่งชี้โบนัสจากความเชี่ยวชาญวิชาชีพ
L["SpecBonusGuaranteedDouble"]  = "ผลผลิต 2 เท่ารับประกัน"
L["SpecBonusProcChance"]        = "โอกาสได้ผลผลิตพิเศษ"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "รายการซื้อ"
L["SectionMissingReagents"] = "ส่วนผสมที่ขาด"
L["SectionReagentWatch"]    = "ติดตามส่วนผสม"
L["ShoppingListEmpty"]      = "|cffaaaaaa(ว่างเปล่า — คลิกแถวสูตรในแท็บวิชาชีพเพื่อเพิ่มไอเทมในรายการซื้อ)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(รายการซื้อว่างเปล่าหรือส่วนผสมทั้งหมดอยู่ในกระเป๋าแล้ว)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(ไม่มีไอเทมที่ติดตาม — ป้อน ID ไอเทมหรือลิงก์ด้านบน)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(โมดูล ReagentWatch ไม่ได้โหลด)|r"
L["WatchInputLabel"]        = "ID ไอเทมหรือลิงก์"
L["WatchBtn"]               = "ติดตาม"
L["WatchedItemsHeading"]    = "ไอเทมที่ติดตาม"
L["ColHave"]                = "มี"
L["ColNeed"]                = "ต้องการ"
L["ColShort"]               = "ขาด"
L["ColItem"]                = "ไอเทม"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "ตัวละคร|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "วิชาชีพ|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "ค้นหาสูตร…|r"
L["MissingIncludeTrainer"]      = "รวมเฉพาะจากครูฝึก"
L["MissingIncludeTrainerDesc"]  = "รวมสูตรที่เรียนได้จากครูฝึกเท่านั้น (ไม่มีม้วนกระดาษใน AH)"
L["MissingScanAH"]              = "สแกน AH"
L["MissingScanAHProgress"]      = "สแกน %d/%d (คลิกเพื่อยกเลิก)"
L["MissingScanAHDesc"]          = "เปิดตลาดประมูล จากนั้นคลิกเพื่อสแกนหาทุกม้วนสูตรในรายการที่มองเห็น แถวที่มีการประมูลจะมีปุ่ม [AH]; คลิกเพื่อกระโดดไปยังการค้นหา"
L["MissingNoCharacters"]        = "|cffaaaaaa(ยังไม่มีตัวละครที่มีข้อมูลวิชาชีพ — เปิดหน้าต่างวิชาชีพ)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(ตัวละครนี้ยังไม่มีวิชาชีพที่ติดตาม — เปิดหน้าต่างวิชาชีพ)|r"
L["MissingNoneFound"]           = "|cff00ff00เรียนรู้สูตรที่รู้จักทั้งหมดของวิชาชีพนี้แล้ว|r"
L["MissingPickProfession"]      = "|cffaaaaaa← เลือกวิชาชีพเพื่อดูว่าขาดอะไร|r"
L["MissingNoData"]              = "|cffff8888(ไม่มีข้อมูลสูตรสำหรับวิชาชีพนี้)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "สูตร"
L["MissingColSkill"]            = "ทักษะ"
L["MissingColSource"]           = "แหล่งที่มา"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "ติดตามม้วนสูตรนี้"
L["MissingAddToWatchDesc"]      = "เพิ่มม้วนสูตรในรายการติดตามส่วนผสม เพื่อให้คุณเห็นทันทีที่มันเข้าไปในกระเป๋า"
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "ติดตามอยู่แล้ว — คลิกเพื่อหยุดติดตาม"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "สูตรที่ขาด"
L["MissingCountPlural"]         = "สูตรที่ขาด"
L["MissingTruncatedHint"]       = "(แสดง %d รายการแรก — พิมพ์ในกล่องค้นหาเพื่อแคบรายการ)"
L["MissingCharTooltipTitle"]    = "ตัวกรองตัวละคร"
L["MissingCharTooltipDesc"]     = "เลือกตัวละครของคุณที่จะดูสูตรที่ขาด ค่าเริ่มต้นคือตัวละครที่ล็อกอินอยู่"
L["MissingProfTooltipTitle"]    = "ตัวกรองวิชาชีพ"
L["MissingProfTooltipDesc"]     = "เลือกวิชาชีพเพื่อดูม้วนกระดาษที่ตัวละครนี้ยังไม่ได้เรียนรู้"
L["MissingSearchTooltipTitle"]  = "ค้นหาสูตร"
L["MissingSearchTooltipDesc"]   = "พิมพ์เพื่อกรองรายการสูตรที่ขาดตามชื่อ"
L["MissingHdrCountTitle"]       = "สูตรที่ขาด"
L["MissingHdrCountDesc"]        = "สูตรที่ตัวละครที่เลือกยังไม่ได้เรียน แต่สามารถหาได้ในเกมเวอร์ชันนี้ ตัวเลขสะท้อนตัวกรองปัจจุบัน (วิชาชีพ, การค้นหา, ตัวสลับครูฝึก)"
L["MissingHdrSkillTitle"]       = "ระดับทักษะ"
L["MissingHdrSkillDesc"]        = "ระดับทักษะวิชาชีพที่จำเป็นในการเรียนสูตรนี้ แถวสีเทาหมายความว่าตัวละครยังไม่สูงพอ"
L["MissingHdrSourceTitle"]      = "แหล่งที่มา"
L["MissingHdrSourceDesc"]       = "วิธีรับสูตรนี้ — ครูฝึก ดรอป พ่อค้า เควสต์ หรือผลิต วางเมาส์เหนือข้อความแหล่งที่มาในแถวเพื่อดู NPC / มอนสเตอร์ / ขั้นตอนเฉพาะ"
L["MissingRowTooltipShift"]     = "Shift-คลิกเพื่อเชื่อมโยงในแชท"
L["MissingSrcVendor"]           = "พ่อค้า"
L["MissingSrcDrop"]             = "ดรอป"
L["MissingSrcQuest"]            = "เควสต์"
L["MissingSrcCrafted"]          = "ผลิต"
L["MissingSrcFishing"]          = "ตกปลา"
L["MissingSrcContainer"]        = "ภาชนะ"
L["MissingSrcTrainer"]          = "ครูฝึก"
L["MissingSrcOther"]            = "อื่นๆ"
L["MissingSrcUnknown"]          = "ไม่ทราบ"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "คำแนะนำไอเทม"
L["SettingsTooltipShowCrafters"]    = "แสดงผู้ผลิตในกิลด์บนคำแนะนำไอเทม"
L["SettingsTooltipShowCraftersDesc"]= "เพิ่มบรรทัด [TOGPM] ที่แสดงรายชื่อสมาชิกกิลด์ทุกคนที่สามารถผลิตไอเทมที่คุณกำลังชี้อยู่ ออนไลน์เป็นสีขาว ออฟไลน์เป็นสีเทา ไอเทมผูกเมื่อหยิบจะถูกข้าม (ไม่สามารถซื้อขายได้อยู่แล้ว)"
L["SettingsTooltipShowIds"]         = "แสดง ID ไอเทม / ID คาถาบนคำแนะนำไอเทม"
L["SettingsTooltipShowIdsDesc"]     = "เพิ่มบรรทัด [TOGPM] พร้อม ID ไอเทมและ (ถ้าทราบ) ID คาถาของสูตร มีประโยชน์ส่วนใหญ่สำหรับการวินิจฉัยไอคอนผิดหรือสูตรที่ขาด — วาง ID ใน Wowhead เพื่อตรวจสอบการจับคู่"

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "เฟส TBC Anniversary"
L["SettingsTBCPhase"]           = "เฟสเนื้อหาปัจจุบัน"
L["SettingsTBCPhaseDesc"]       = "ซ่อนสูตรที่ขาดจากเฟสที่หลังกว่าเฟสปัจจุบันของ Anniversary เพิ่มค่านี้ทุกครั้งที่ Blizzard ขยับเฟสไปข้างหน้า (สูตรที่เข้าถึงได้ในเฟสที่ใช้งานอยู่จะยังคงมองเห็น)"
L["SettingsTBCPhase1"]          = "เฟส 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "เฟส 2 — Serpentshrine Cavern / Tempest Keep"
L["SettingsTBCPhase3"]          = "เฟส 3 — Black Temple / Mount Hyjal"
L["SettingsTBCPhase4"]          = "เฟส 4 — Sunwell / Magisters' Terrace"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "การแสดงผล"
L["SettingsMinimapBtn"]          = "แสดงปุ่มมินิแมป"
L["SettingsMinimapBtnDesc"]      = "แสดงหรือซ่อนปุ่มเปิดที่มินิแมป"
L["SettingsPersistProfFilter"]     = "จำตัวกรองวิชาชีพ"
L["SettingsPersistProfFilterDesc"] = "กู้คืนวิชาชีพที่เลือกเมื่อล็อกอินหรือโหลดใหม่"
L["SettingsSyncHeader"]     = "การซิงค์"
L["SettingsGuildMode"]      = "โหมดซิงค์เฉพาะกิลด์ (เซิร์ฟเวอร์ส่วนตัว)"
L["SettingsGuildModeDesc"]  = "สำหรับเซิร์ฟเวอร์ส่วนตัวหรือเซิร์ฟเวอร์จำลอง (เช่น Whitemane) ที่ไม่ส่งข้อความแอดดอนผ่านการกระซิบ ซึ่งทำให้สมาชิกกิลด์ไม่ได้รับข้อมูลอาชีพของกันและกัน เมื่อเปิด การรับส่งข้อมูลซิงค์ทั้งหมดจะถูกส่งผ่านช่องกิลด์แทน เปิดใช้งานเฉพาะเมื่อการซิงค์กิลด์ไม่ทำงานบนเซิร์ฟเวอร์ของคุณ |cffffd100ทุกคนในกิลด์ควรเปิดใช้งาน|r — จะได้ผลเฉพาะระหว่างสมาชิกที่เปิดใช้งานทั้งสองฝ่าย การแชร์ข้ามกิลด์จะถูกปิดโดยอัตโนมัติขณะที่เปิดใช้งานนี้ มีผลกับตัวละครทุกตัวบนเรียลม์นี้ (จะถูกซ่อนหากเวอร์ชัน DeltaSync ที่ติดตั้งไม่รองรับ)"
L["SettingsCooldownsHeader"]= "คูลดาวน์"
L["SettingsMailReadyOnly"]  = "จดหมาย: แสดงเฉพาะคูลดาวน์ที่พร้อม"
L["SettingsMailReadyOnlyDesc"] = "เมื่อเขียนจดหมายเสบียงจากแผงคูลดาวน์ แสดงเฉพาะสมาชิกที่มีคูลดาวน์พร้อม"
L["SettingsDevHeader"]      = "ผู้พัฒนา"
L["SettingsDebug"]          = "ผลผลิตดีบัก"
L["SettingsDebugDesc"]      = "พิมพ์ข้อความดีบักโดยละเอียดในหน้าต่างแชท"
L["SettingsDataHeader"]     = "ข้อมูล"
L["SettingsSyncNow"]        = "บังคับซิงค์ใหม่"
L["SettingsSyncNowDesc"]    = "ส่งข้อมูลวิชาชีพของคุณไปยังกิลด์ทันที"
L["SettingsPurgeGuild"]     = "ล้างข้อมูลกิลด์ทั้งหมด"
L["SettingsPurgeGuildDesc"] = "ลบข้อมูลวิชาชีพและคูลดาวน์ที่บันทึกไว้ทั้งหมดสำหรับสมาชิกกิลด์ทุกคนในบัญชีนี้ ไม่สามารถยกเลิกได้"
L["SettingsPurgeGuildConfirm"] = "ลบข้อมูลกิลด์ทั้งหมดของบัญชีนี้?"
L["SettingsPurgeMine"]      = "ล้างข้อมูลตัวละครของฉัน"
L["SettingsPurgeMineDesc"]  = "ลบข้อมูลที่บันทึกไว้เฉพาะของตัวละครของคุณจากฐานข้อมูลกิลด์"
L["SettingsPurgeMineConfirm"] = "ลบข้อมูลวิชาชีพและคูลดาวน์ของคุณ?"
L["SettingsSyncLogHeader"]  = "บันทึกการซิงค์"
L["SettingsViewLog"]        = "ดูบันทึกการซิงค์"
L["SettingsViewLogDesc"]    = "เปิดรายการเลื่อนของกิจกรรมการซิงค์ล่าสุด (200 รายการล่าสุด)"
L["SettingsClearLog"]       = "ล้างบันทึกการซิงค์"
L["SettingsClearLogConfirm"]= "ล้างรายการบันทึกการซิงค์ทั้งหมด?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(โมดูล SyncLog ไม่ได้โหลด)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(ยังไม่มีกิจกรรมการซิงค์ที่บันทึก)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "ซ่อนปุ่มมินิแมปแล้ว ใช้ |cffda8cff/togpm minimap|r เพื่อกู้คืน"

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "ผลิตโดย:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00พร้อมผลิต:|r %s × %d  (%s × %d ในกระเป๋า)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "เปิดใช้งานการแจ้งเตือนผู้ผลิตสำหรับสูตรนี้"
L["ShoppingAlertDisable"]              = "ปิดการแจ้งเตือนผู้ผลิตสำหรับสูตรนี้"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s ออนไลน์ — สามารถผลิต: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s ออนไลน์ (ตัวรองของ %s) — สามารถผลิต: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "เปิดใช้งานการแจ้งเตือนพร้อมสำหรับคูลดาวน์นี้"
L["CooldownAlertDisable"]              = "ปิดการแจ้งเตือนพร้อมสำหรับคูลดาวน์นี้"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r คูลดาวน์พร้อม: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "การแจ้งเตือนผู้ผลิต"
L["SettingsCrafterAlert"]              = "เปิดใช้งานการแจ้งเตือนผู้ผลิต"
L["SettingsCrafterAlertDesc"]          = "เล่นเสียงและทำให้หน้าจอกะพริบเมื่อสมาชิกกิลด์ที่สามารถผลิตไอเทมในรายการซื้อที่ตั้งแจ้งเตือนได้เข้าสู่ระบบ"
L["SettingsCrafterAlertSuppressAudio"]     = "ปิดเสียงแจ้งเตือน"
L["SettingsCrafterAlertSuppressAudioDesc"] = "ปิดเสียงเมื่อผู้ผลิตออนไลน์ (การกะพริบหน้าจอและข้อความในแชทยังคงปรากฏ)"
L["SettingsCrafterAlertSuppressVisual"]    = "ปิดการแจ้งเตือนแบบภาพ"
L["SettingsCrafterAlertSuppressVisualDesc"] = "ปิดการแจ้งเตือนแบบภาพบนหน้าจอ (การกะพริบหน้าจอ แบนเนอร์ ฯลฯ) เมื่อผู้ผลิตออนไลน์ (เสียงและข้อความในแชทยังคงปรากฏ)"
L["AlertCrafterOnlineBanner"]              = "ผู้ผลิตในกิลด์ออนไลน์"
L["SettingsCrafterAlertSound"]             = "เสียงแจ้งเตือน"
L["SettingsCrafterAlertSoundDesc"]         = "เสียงที่จะเล่นเมื่อผู้ผลิตที่คุณติดต่อได้ออนไลน์ การเลือกจะเป็นการฟังตัวอย่างเสียงนั้น ไม่มีผลขณะที่เสียงแจ้งเตือนถูกปิดด้านบน"
L["SettingsCrafterAlertVisual"]            = "เอฟเฟกต์แจ้งเตือนบนหน้าจอ"
L["SettingsCrafterAlertVisualDesc"]        = "เอฟเฟกต์บนหน้าจอที่จะทำงานเมื่อผู้ผลิตออนไลน์ — แสงวาบเต็มหน้าจอในโทนสีที่คุณเลือก หรือการกะพริบที่แถบงานสำหรับตอนที่คุณสลับหน้าต่างออกไป (alt-tab) การเลือกจะเป็นการดูตัวอย่าง ไม่มีผลขณะที่การกะพริบหน้าจอถูกปิดด้านบน"
L["SettingsCrafterAlertSuppressLogin"]     = "ปิดการแจ้งเตือนเมื่อล็อกอิน"
L["SettingsCrafterAlertSuppressLoginDesc"] = "ไม่จุดการแจ้งเตือนในช่วงการแจ้งเตือนเข้าสู่ระบบเริ่มต้นที่ล็อกอินหรือโหลดใหม่"
L["SettingsCooldownAlertSuppressProtected"]     = "ปิดเสียงการแจ้งเตือนในอินสแตนซ์"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "ไม่ส่งเสียงหรือพิมพ์การแจ้งเตือนคูลดาวน์พร้อมขณะอยู่ในเรด ดันเจี้ยน สนามรบ อารีน่า หรือสถานการณ์ เมืองหลวงไม่ถูกปิดเสียง — ขณะ AFK ใน Stormwind การ transmute ของคุณจะยังคงส่งเสียง การแจ้งเตือนที่รอจะเริ่มทันทีที่คุณออกจากอินสแตนซ์"
L["SettingsCooldownReminderInterval"]      = "การเตือนคูลดาวน์พร้อม"
L["SettingsCooldownReminderIntervalDesc"]  = "จุดการแจ้งเตือนคูลดาวน์ที่เปิดใช้งานแต่ละครั้งทุก N นาทีในขณะที่คูลดาวน์ยังคงพร้อม (จนกว่าคุณจะผลิตจริง) ป้อน 0, ว่าง หรือ 'off' เพื่อจุดเพียงครั้งเดียวต่อรอบพร้อม ช่วงที่ใช้ได้: 1–1440 นาที (24 ชั่วโมง)"
L["SettingsCooldownReminderInvalid"]       = "ป้อนตัวเลขเต็มจาก 0 ถึง 1440 หรือ 'off'"

L["SettingsAHHeader"]                      = "ตลาดประมูล"
L["SettingsAHScanDelay"]                   = "การหน่วงสแกน AH (วินาที)"
L["SettingsAHScanDelayDesc"]               = "วินาทีระหว่างคำขอสแกน AH ว่าง / 0 / 'off' ใช้ค่าเริ่มต้นของเวอร์ชัน (1.5 วินาที บน Classic Era และ Anniversary; 3.0 วินาที บน TBC, Wrath, Cata, MoP — เซิร์ฟเวอร์เหล่านั้นจำกัดเข้มงวดกว่า) ลดค่าเพื่อสแกนเร็วขึ้น เพิ่มหากสแกนหยุดชะงัก ช่วงที่ใช้ได้: 0.5–10 วินาที"
L["SettingsAHScanDelayInvalid"]            = "ป้อนตัวเลขจาก 0.5 ถึง 10 หรือ 'off'"

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "สูตร"
L["TooltipRecipeDesc"]           = "ชื่อของไอเทมที่ผลิตได้หรือคาถา"
L["TooltipCraftersTitle"]        = "ผู้ผลิต"
L["TooltipCraftersDesc"]         = "สมาชิกกิลด์ที่รู้สูตรนี้ คลิกสูตรเพื่อดูรายการทั้งหมด"
L["CraftersColHeader"]           = "ผู้ผลิต"
L["TooltipBankTitle"]            = "ขอจากธนาคาร"
L["TooltipBankDescScroll"]       = "ส่งคำขอไปยังพนักงานธนาคารกิลด์ TOGBankClassic สำหรับม้วนสูตรนี้"
L["TooltipBankDescGeneric"]      = "ส่งคำขอไปยังพนักงานธนาคารกิลด์ TOGBankClassic"
L["TooltipAHTitle"]              = "ค้นหาตลาดประมูล"
L["TooltipAHDescScroll"]         = "เปิดม้วนสูตรนี้ในการค้นหา AH"
L["TooltipAHDescReagent"]        = "เปิดส่วนผสมนี้ในการค้นหา AH"
L["TooltipSettingsTitle"]        = "การตั้งค่า"
L["TooltipSettingsDesc"]         = "เปิดแผงการตั้งค่า TOG Profession Master (|cffffd700ESC > ตัวเลือก > ส่วนเสริม > TOG Profession Master|r) เป้าหมายเดียวกับ |cffffd700/togpm settings|r และ Shift+คลิกซ้ายที่ปุ่มมินิแมป"
L["TooltipWhisperRightClick"]    = "คลิกขวาเพื่อกระซิบ"
L["TooltipClickTransmutes"]      = "คลิกเพื่อดูการแปรธาตุ"
L["TooltipClickDetailsFormat"]   = "คลิกเพื่อดู %s"
L["TooltipClickDetailsFallback"] = "รายละเอียด"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "เสบียงคูลดาวน์: %s"
L["MailBodyFormat"]         = "สวัสดี %s! โปรดใช้วัสดุเหล่านี้เพื่อทำ %s ส่ง %s กลับมาให้ฉันเมื่อมีเวลาผลิต ขอบคุณ!"
L["MailMsgNoEmptyBag"]      = "ไม่มีช่องกระเป๋าว่างเพื่อแบ่ง"
L["MailMsgOpenMailbox"]     = "เปิดกล่องจดหมายก่อน"
L["MailMsgHasItems"]        = "จดหมายมีไอเทมแนบอยู่แล้ว — ส่งหรือลบออกก่อน"
L["MailMsgCannotFulfill"]   = "ไม่สามารถดำเนินการได้"
L["MailMsgCouldNotAttach"]  = "ไม่สามารถแนบไอเทมได้"
L["MailMsgAttachedFormat"]  = "แนบ %dx %s สำหรับ %s แล้ว"

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100คลิกซ้าย|r เพื่อสลับเบราว์เซอร์วิชาชีพ"
L["MinimapTooltipRightClick"]  = "|cffffd100คลิกขวา|r เพื่อสลับส่วนผสม"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+ซ้าย|r เพื่อเปิดการตั้งค่า"
L["MinimapButtonShown"]        = "แสดงปุ่มมินิแมปแล้ว"

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- ชื่อคำสั่งไม่แปล
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — คำสั่ง:"
L["SlashHelpOpen"]          = "เปิดเบราว์เซอร์วิชาชีพ"
L["SlashHelpReagents"]      = "เปิดส่วนผสมที่ขาด"
L["SlashHelpMinimap"]       = "แสดงปุ่มมินิแมป"
L["SlashHelpPurge"]         = "เปิดกล่องโต้ตอบล้างข้อมูล"
L["SlashHelpSync"]          = "บังคับซิงค์กิลด์เต็มรูปแบบใหม่"
L["SlashHelpStatus"]        = "ถ่ายโอนข้อมูลการวินิจฉัย sync/comm"
L["SlashHelpVersionCheck"]  = "ตรวจสอบเวอร์ชันส่วนเสริมในกิลด์"
L["SlashHelpDebug"]         = "สลับผลผลิตดีบัก"
L["SlashHelpHelp"]          = "แสดงรายการนี้"
L["SlashForceSyncSent"]     = "ส่งซิงค์บังคับแล้ว"
L["AHScannerOpenAH"]        = "เปิดตลาดประมูลเพื่อค้นหา"
L["AHOpenFirst"]            = "เปิดตลาดประมูลก่อน"
L["AHNoItemsToScan"]        = "ไม่มีไอเทมที่จะสแกนในมุมมองปัจจุบัน"

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "ขอจากธนาคารกิลด์"
L["BankDialogBanker"]       = "พนักงานธนาคาร:"
L["BankDialogQty"]          = "จำนวน:"
L["BankDialogSend"]         = "ส่งคำขอ"
L["BankDialogCancel"]       = "ยกเลิก"

-- ---------------------------------------------------------------------------
-- การยืนยันการล้างและผลผลิตคำสั่งอื่นๆ
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "ล้างข้อมูลกิลด์ทั้งหมดแล้ว"
L["MsgOwnDataPurged"]        = "ล้างข้อมูลตัวละครของคุณแล้ว"
L["SlashForceBroadcastSent"] = "ส่งบรอดคาสต์บังคับแล้ว"
L["SlashDebugEnabled"]       = "|cff00ff00เปิดใช้งานแล้ว|r"
L["SlashDebugDisabled"]      = "|cffff4444ปิดใช้งานแล้ว|r"
L["SlashDebugToggleFormat"]  = "ผลผลิตดีบัก %s"

-- ---------------------------------------------------------------------------
-- ชื่อวิชาชีพ (ทั้ง 15 — การแปลโดยชุมชน, ตรวจสอบโดยเจ้าของภาษาที่ยินดี)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "การเล่นแร่แปรธาตุ"
L["ProfBlacksmithing"]  = "การตีเหล็ก"
L["ProfCooking"]        = "การปรุงอาหาร"
L["ProfEnchanting"]     = "การร่ายมนตร์"
L["ProfEngineering"]    = "วิศวกรรม"
L["ProfFirstAid"]       = "การปฐมพยาบาล"
L["ProfLeatherworking"] = "การฟอกหนัง"
L["ProfMining"]         = "การทำเหมือง"
L["ProfTailoring"]      = "การตัดเย็บผ้า"
L["ProfHerbalism"]      = "การเก็บสมุนไพร"
L["ProfSkinning"]       = "การถลกหนัง"
L["ProfJewelcrafting"]  = "ช่างเครื่องประดับ"
L["ProfInscription"]    = "การจารึก"
L["ProfFishing"]        = "การตกปลา"
L["ProfSmelting"]       = "การหลอม"

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
