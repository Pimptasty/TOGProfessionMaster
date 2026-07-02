-- TOG Profession Master -- Traditional Chinese (zhTW) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("zhTW")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — 同步紀錄"

-- Tab labels
L["TabProfessions"]     = "專業技能"
L["TabCooldowns"]       = "冷卻時間"
L["TabReagents"]        = "材料"
L["TabMissingRecipes"]  = "缺少的配方"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "搜尋配方…"
L["ViewGuild"]          = "公會"
L["ViewMine"]           = "我的角色"
L["AllProfessions"]     = "所有專業"
L["PanelProfessions"]   = "專業"
L["PanelCharacters"]    = "角色"
L["SelectProfession"]   = "選擇一項專業"
L["NoDataYet"]          = "|cffaaaaaa(尚無資料)|r"
L["SelectProfHint"]     = "|cffaaaaaa← 選擇一項專業以查看誰擁有。|r"
L["NoProfMembers"]      = "|cffaaaaaa(沒有公會成員擁有此專業)|r"
L["BackToCharacters"]   = "|cff00aaff← 返回角色|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(沒有相符的配方)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "你"
L["BrowserScanAH"]          = "掃描拍賣場"
L["BrowserScanAHProgress"]  = "掃描中 %d/%d"
L["BrowserScanAHDesc"]      = "掃描拍賣場中購物清單上的每種材料。目前在拍賣場有貨的材料列會顯示 [拍] 按鈕;點擊直接跳到拍賣場搜尋。"
L["CooldownsScanAHDesc"]    = "掃描拍賣場中可見冷卻時間列的每種獨特材料。目前在拍賣場有貨的材料列會顯示 [拍] 按鈕(位於 [銀行] 左側);點擊跳到搜尋。"

-- Skill-tier filter (Browser toolbar)
L["BrowserSkillTier"]       = "技能等級"
L["BrowserSkillTierTip"]    = "技能等級篩選"
L["BrowserSkillTierDesc"]   = "只顯示勾選的技能等級中的配方。取消勾選較低等級即可從清單中隱藏其配方。可勾選多個等級;選單會保持開啟。使用底部的全選 / 全部清除。沒有已知技能等級的配方永遠保持可見。"
L["FilterSelectAll"]        = "全選"
L["FilterClearAll"]         = "全部清除"
L["TierApprentice"]         = "學徒"
L["TierJourneyman"]         = "熟練"
L["TierExpert"]             = "專家"
L["TierArtisan"]            = "大師"
L["TierMaster"]             = "宗師"
L["TierGrandMaster"]        = "大宗師"
L["TierIllustrious"]        = "卓越"
L["TierZenMaster"]          = "禪師"

-- Guild tab
L["TabGuild"]               = "公會"
L["GuildTabChars"]          = "已追蹤 %d 個角色"
L["GuildColProfession"]     = "專業"
L["GuildColProfessionDesc"] = "每項專業以及有多少公會角色擁有它。當已知專精時,子列會依專精進一步細分。"
L["GuildColCount"]          = "角色數"
L["GuildColCountDesc"]      = "擁有該專業(或專精)的公會角色數量。依同步的技能加上所有已知會製作其配方的角色計算。"
L["GuildUnspecialized"]     = "無專精"
L["GuildTabEmpty"]          = "尚無專業資料。當使用此插件的公會成員同步其技能後,資料就會填入。"

-- Recipe detail popup
L["PopupCrafters"]       = "擁有者"
L["PopupOnList"]         = "在購物清單中"
L["PopupNotOnList"]      = "不在購物清單中"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "僅就緒"
L["ShowAll"]                = "全部"
L["FilterColProfession"]    = "專業"
L["FilterColCooldown"]      = "冷卻"
L["FilterColView"]          = "檢視"
L["FilterProfessionDesc"]   = "依單一專業(鍊金術、裁縫等)篩選冷卻時間清單。"
L["FilterCooldownDesc"]     = "在所選專業內,依單一共享冷卻時間(例如轉化、月布)篩選。"
L["FilterViewDesc"]         = "在所有公會成員的冷卻時間和僅你的角色之間切換。"
L["AllCooldowns"]           = "所有冷卻時間"
L["FilterTransmute"]            = "轉化"
L["FilterAlchResearch"]         = "鍊金研究"
L["FilterMooncloth"]            = "月布"
L["FilterSpecialtyCloth"]       = "特殊布料"
L["FilterGlacialBag"]           = "冰河袋"
L["FilterDreamcloth"]           = "夢境布"
L["FilterImperialSilk"]         = "皇家絲綢"
L["FilterSaltShaker"]           = "鹽罐"
L["FilterMagicSphere"]          = "魔法球"
L["FilterShaCrystal"]           = "煞水晶"
L["FilterBrilliantGlass"]       = "璀璨玻璃"
L["FilterIcyPrism"]             = "冰冷稜鏡"
L["FilterFirePrism"]            = "火焰稜鏡"
L["FilterJcDaily"]              = "珠寶設計每日切割"
L["FilterInscriptionResearch"]  = "銘文研究"
L["FilterForgedDocuments"]      = "偽造文件"
L["FilterScrollOfWisdom"]       = "智慧卷軸"
L["FilterTitansteelBar"]        = "泰坦鋼錠"
L["FilterBsIngot"]              = "熔煉"
L["FilterMagnificence"]         = "宏偉之力"
L["FilterJards"]                = "賈德之能"
L["ColCharacter"]           = "角色"
L["ColCooldown"]            = "冷卻"
L["ColReagent"]             = "材料"
L["ColTimeLeft"]            = "剩餘時間"
L["NoCooldownData"]         = "|cffaaaaaa(尚無冷卻時間資料 — 打開專業視窗)|r"
L["Ready"]                  = "|cff00ff00就緒|r"
L["Transmute"]              = "轉化"
L["MailBtn"]                = "郵件"
L["MailBtnTooltip"]         = "寄送補給郵件"
L["MailBtnTooltipDesc"]     = "打開信箱,然後點擊附加材料並向此玩家撰寫補給郵件。"
L["BankBtn"]                = "[銀行]"
L["CloseBtn"]               = "關閉"

-- 專業特化產出加成指示器
L["SpecBonusGuaranteedDouble"]  = "保證 2 倍產出"
L["SpecBonusProcChance"]        = "有機會產生額外產出"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "購物清單"
L["SectionMissingReagents"] = "缺少的材料"
L["SectionReagentWatch"]    = "材料監視"
L["ShoppingListEmpty"]      = "|cffaaaaaa(為空 — 在專業頁籤中點擊配方列以將物品加入購物清單)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(購物清單為空,或所有材料都在背包中)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(沒有監視的物品 — 在上方輸入物品 ID 或連結)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch 模組未載入)|r"
L["WatchInputLabel"]        = "物品 ID 或連結"
L["WatchBtn"]               = "監視"
L["WatchedItemsHeading"]    = "監視中的物品"
L["ColHave"]                = "擁有"
L["ColNeed"]                = "需要"
L["ColShort"]               = "短缺"
L["ColItem"]                = "物品"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "角色|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "專業|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "搜尋配方…|r"
L["MissingIncludeTrainer"]      = "包含訓練師專屬"
L["MissingIncludeTrainerDesc"]  = "包含只能從訓練師處學到的配方(無拍賣場卷軸)。"
L["MissingScanAH"]              = "掃描拍賣場"
L["MissingScanAHProgress"]      = "掃描中 %d/%d (點擊取消)"
L["MissingScanAHDesc"]          = "打開拍賣場,然後點擊掃描可見清單中每個配方卷軸。有活躍標售的列會顯示 [拍] 按鈕;點擊跳到搜尋。"
L["MissingNoCharacters"]        = "|cffaaaaaa(尚無帶專業資料的角色 — 打開專業視窗)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(此角色尚未追蹤任何專業 — 打開專業視窗)|r"
L["MissingNoneFound"]           = "|cff00ff00此專業所有已知配方都已學會。|r"
L["MissingPickProfession"]      = "|cffaaaaaa← 選擇一項專業以查看缺少什麼。|r"
L["MissingNoData"]              = "|cffff8888(此專業暫無可用配方資料)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "配方"
L["MissingColSkill"]            = "技能"
L["MissingColSource"]           = "來源"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "監視此配方卷軸"
L["MissingAddToWatchDesc"]      = "將配方卷軸加入你的材料監視清單,它一進入背包你就會看到。"
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "已在監視中 — 點擊停止監視"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "缺少的配方"
L["MissingCountPlural"]         = "缺少的配方"
L["MissingTruncatedHint"]       = "(顯示前 %d 個 — 在搜尋框中輸入以縮小清單)"
L["MissingCharTooltipTitle"]    = "角色篩選"
L["MissingCharTooltipDesc"]     = "選擇要查看缺少配方的角色。預設為目前登入的角色。"
L["MissingProfTooltipTitle"]    = "專業篩選"
L["MissingProfTooltipDesc"]     = "選擇一項專業以查看此角色尚未學會的卷軸。"
L["MissingSearchTooltipTitle"]  = "搜尋配方"
L["MissingSearchTooltipDesc"]   = "輸入以依名稱篩選缺少的配方清單。"
L["MissingHdrCountTitle"]       = "缺少的配方"
L["MissingHdrCountDesc"]        = "所選角色尚未學會但可在此遊戲版本中取得的配方。數字反映目前的篩選(專業、搜尋、訓練師開關)。"
L["MissingHdrSkillTitle"]       = "技能等級"
L["MissingHdrSkillDesc"]        = "學習此配方所需的專業技能等級。灰色列表示角色尚未達到所需等級。"
L["MissingHdrSourceTitle"]      = "來源"
L["MissingHdrSourceDesc"]       = "如何取得此配方 — 訓練師、掉落、商人、任務或製造。將滑鼠懸停在列的來源文字上以查看特定 NPC / 怪物 / 步驟。"
L["MissingRowTooltipShift"]     = "Shift-點擊在聊天中連結。"
L["MissingSrcVendor"]           = "商人"
L["MissingSrcDrop"]             = "掉落"
L["MissingSrcQuest"]            = "任務"
L["MissingSrcCrafted"]          = "製造"
L["MissingSrcFishing"]          = "釣魚"
L["MissingSrcContainer"]        = "容器"
L["MissingSrcTrainer"]          = "訓練師"
L["MissingSrcOther"]            = "其他"
L["MissingSrcUnknown"]          = "未知"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "物品提示"
L["SettingsTooltipShowCrafters"]    = "在物品提示中顯示公會製造者"
L["SettingsTooltipShowCraftersDesc"]= "新增一行 [TOGPM],列出可以製造你正在懸停的物品的每個公會成員。在線為白色,離線為灰色。拾取綁定的物品會被跳過(反正不能交易)。"
L["SettingsTooltipShowIds"]         = "在物品提示中顯示物品 ID / 法術 ID"
L["SettingsTooltipShowIdsDesc"]     = "新增一行 [TOGPM],包含物品 ID 和(如果已知)配方法術 ID。主要用於診斷錯誤的圖示或缺少的配方 — 將 ID 貼到 Wowhead 以驗證匹配。"

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC 週年階段"
L["SettingsTBCPhase"]           = "目前內容階段"
L["SettingsTBCPhaseDesc"]       = "隱藏來自比目前週年階段更晚階段的缺少配方。每當暴雪推進階段時,提高此值。(目前活躍階段已可存取的配方保持可見。)"
L["SettingsTBCPhase1"]          = "第 1 階段 — 卡拉贊 / 戈魯爾 / 瑪瑟里頓"
L["SettingsTBCPhase2"]          = "第 2 階段 — 毒蛇神殿 / 風暴要塞"
L["SettingsTBCPhase3"]          = "第 3 階段 — 黑暗神殿 / 海加爾山"
L["SettingsTBCPhase4"]          = "第 4 階段 — 太陽之井 / 大法師學院"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "顯示"
L["SettingsMinimapBtn"]          = "顯示小地圖按鈕"
L["SettingsMinimapBtnDesc"]      = "顯示或隱藏小地圖啟動器按鈕。"
L["SettingsPersistProfFilter"]     = "記住專業篩選"
L["SettingsPersistProfFilterDesc"] = "登入或重新載入時還原所選專業。"
L["SettingsSyncHeader"]     = "同步"
L["SettingsGuildMode"]      = "僅公會同步模式（私服）"
L["SettingsGuildModeDesc"]  = "適用於不透過密語傳遞插件訊息的私服或模擬伺服器（例如 Whitemane），這會導致公會成員無法收到彼此的專業資料。開啟後，所有同步流量將改為透過公會頻道傳輸。僅在你的伺服器上公會同步無法正常運作時才開啟。|cffffd100公會中的所有人都應開啟它|r——只有雙方都開啟的成員之間才有效。開啟此項時會自動停用跨公會共享。適用於此伺服器上的所有角色。（若你安裝的 DeltaSync 版本不支援，則會隱藏。）"
L["SettingsCooldownsHeader"]= "冷卻時間"
L["SettingsMailReadyOnly"]  = "郵件:僅顯示已就緒的冷卻時間"
L["SettingsMailReadyOnlyDesc"] = "從冷卻時間面板撰寫補給郵件時,僅列出冷卻時間已就緒的公會成員。"
L["SettingsDevHeader"]      = "開發者"
L["SettingsDebug"]          = "除錯輸出"
L["SettingsDebugDesc"]      = "將詳細除錯訊息列印到聊天框。"
L["SettingsDataHeader"]     = "資料"
L["SettingsSyncNow"]        = "強制重新同步"
L["SettingsSyncNowDesc"]    = "立即將你的專業資料廣播到公會。"
L["SettingsPurgeGuild"]     = "清除所有公會資料"
L["SettingsPurgeGuildDesc"] = "刪除此帳號上每個公會成員儲存的所有專業和冷卻時間資料。無法復原。"
L["SettingsPurgeGuildConfirm"] = "刪除此帳號的所有公會資料?"
L["SettingsPurgeMine"]      = "清除我的角色資料"
L["SettingsPurgeMineDesc"]  = "僅從公會資料庫中刪除你自己角色的儲存資料。"
L["SettingsPurgeMineConfirm"] = "刪除你自己的專業和冷卻時間資料?"
L["SettingsSyncLogHeader"]  = "同步紀錄"
L["SettingsViewLog"]        = "檢視同步紀錄"
L["SettingsViewLogDesc"]    = "打開最近同步事件(最近 200 條)的可捲動清單。"
L["SettingsClearLog"]       = "清除同步紀錄"
L["SettingsClearLogConfirm"]= "清除所有同步紀錄條目?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog 模組未載入)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(尚未記錄同步事件)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "小地圖按鈕已隱藏。使用 |cffda8cff/togpm minimap|r 還原。"

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "製造者:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00可以製造:|r %s × %d  (%s × %d 在背包中)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "為此配方啟用製造者提醒"
L["ShoppingAlertDisable"]              = "為此配方停用製造者提醒"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s 在線 — 可以製造:%s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s 在線(%s 的分身)— 可以製造:%s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "為此冷卻時間啟用就緒提醒"
L["CooldownAlertDisable"]              = "為此冷卻時間停用就緒提醒"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r 冷卻時間就緒:%s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "製造者提醒"
L["SettingsCrafterAlert"]              = "啟用製造者提醒"
L["SettingsCrafterAlertDesc"]          = "當可以製造已提醒的購物清單物品的公會成員上線時,播放聲音並使螢幕閃爍。"
L["SettingsCrafterAlertSuppressAudio"]     = "停用提示音效"
L["SettingsCrafterAlertSuppressAudioDesc"] = "當製作者上線時停用音效提示(螢幕閃爍和聊天訊息仍會出現)。"
L["SettingsCrafterAlertSuppressVisual"]    = "停用提示視覺效果"
L["SettingsCrafterAlertSuppressVisualDesc"] = "當製作者上線時停用螢幕視覺提示(螢幕閃爍、橫幅等)(聲音和聊天訊息仍會出現)。"
L["AlertCrafterOnlineBanner"]              = "公會製造者上線"
L["SettingsCrafterAlertSound"]             = "提示音效"
L["SettingsCrafterAlertSoundDesc"]         = "當你能聯繫到的製造者上線時播放的音效。選擇某項即可試聽。當上方已停用提示音時,此設定無效。"
L["SettingsCrafterAlertVisual"]            = "視覺提示"
L["SettingsCrafterAlertVisualDesc"]        = "當製造者上線時觸發的螢幕效果 — 可選擇以你所選色調進行全螢幕閃爍,或在你切換到其他視窗時使工作列閃爍。選擇某項即可預覽。當上方已停用螢幕閃爍時,此設定無效。"
L["SettingsCrafterAlertSuppressLogin"]     = "登入時禁用提醒"
L["SettingsCrafterAlertSuppressLoginDesc"] = "登入或重新載入 UI 時,不在初始上線通知爆發期間觸發提醒。"
L["SettingsCooldownAlertSuppressProtected"]     = "在副本中靜音提醒"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "在團隊副本、地下城、戰場、競技場或場景中時,不發出冷卻時間就緒提醒。首都不會被靜音 — 即使你在暴風城掛機,你的轉化也會繼續提醒。等待中的提醒會在你離開副本時立即觸發。"
L["SettingsCooldownReminderInterval"]      = "冷卻時間就緒提醒間隔"
L["SettingsCooldownReminderIntervalDesc"]  = "在冷卻時間保持就緒狀態時(即直到你實際製造),每 N 分鐘重新觸發每個已啟用的冷卻時間提醒。輸入 0、空或 'off' 表示每個就緒週期僅觸發一次。有效範圍:1–1440 分鐘(24 小時)。"
L["SettingsCooldownReminderInvalid"]       = "輸入 0 到 1440 之間的整數,或 'off'。"

L["SettingsAHHeader"]                      = "拍賣場"
L["SettingsAHScanDelay"]                   = "拍賣場掃描延遲(秒)"
L["SettingsAHScanDelayDesc"]               = "拍賣場掃描查詢之間的秒數。空 / 0 / 'off' 使用版本預設值(Classic Era 和 Anniversary 上為 1.5 秒;TBC、Wrath、Cata、MoP 上為 3.0 秒 — 這些伺服器限制更嚴格)。降低值以加快掃描,如果掃描停滯則提高。有效範圍:0.5–10 秒。"
L["SettingsAHScanDelayInvalid"]            = "輸入 0.5 到 10 之間的數字,或 'off'。"

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "配方"
L["TooltipRecipeDesc"]           = "可製造物品或法術的名稱。"
L["TooltipCraftersTitle"]        = "製造者"
L["TooltipCraftersDesc"]         = "擁有此配方的公會成員。點擊配方查看完整清單。"
L["CraftersColHeader"]           = "製造者"
L["TooltipBankTitle"]            = "向銀行請求"
L["TooltipBankDescScroll"]       = "向 TOGBankClassic 公會銀行員發送此配方卷軸的請求。"
L["TooltipBankDescGeneric"]      = "向 TOGBankClassic 公會銀行員發送請求。"
L["TooltipAHTitle"]              = "搜尋拍賣場"
L["TooltipAHDescScroll"]         = "在拍賣場搜尋中打開此配方卷軸。"
L["TooltipAHDescReagent"]        = "在拍賣場搜尋中打開此材料。"
L["TooltipSettingsTitle"]        = "設定"
L["TooltipSettingsDesc"]         = "打開 TOG Profession Master 設定面板(|cffffd700ESC > 選項 > 插件 > TOG Profession Master|r)。與 |cffffd700/togpm settings|r 和 Shift+左鍵點擊小地圖按鈕目標相同。"
L["TooltipWhisperRightClick"]    = "右鍵點擊密語"
L["TooltipClickTransmutes"]      = "點擊查看轉化"
L["TooltipClickDetailsFormat"]   = "點擊查看 %s"
L["TooltipClickDetailsFallback"] = "詳情"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "冷卻時間補給:%s"
L["MailBodyFormat"]         = "你好 %s!請使用這些材料製作 %s。請在有時間製造時寄回 %s。謝謝!"
L["MailMsgNoEmptyBag"]      = "沒有空的背包格用於拆分。"
L["MailMsgOpenMailbox"]     = "請先打開信箱。"
L["MailMsgHasItems"]        = "郵件已附加物品 — 請先發送或移除它們。"
L["MailMsgCannotFulfill"]   = "無法完成。"
L["MailMsgCouldNotAttach"]  = "無法附加物品。"
L["MailMsgAttachedFormat"]  = "已為 %s 附加 %dx %s。"

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100左鍵點擊|r 切換專業瀏覽器"
L["MinimapTooltipRightClick"]  = "|cffffd100右鍵點擊|r 切換材料"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+左鍵|r 打開設定"
L["MinimapButtonShown"]        = "小地圖按鈕已顯示。"

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- 命令名稱不翻譯
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — 命令:"
L["SlashHelpOpen"]          = "打開專業瀏覽器"
L["SlashHelpReagents"]      = "打開缺少的材料"
L["SlashHelpMinimap"]       = "顯示小地圖按鈕"
L["SlashHelpPurge"]         = "打開清除對話方塊"
L["SlashHelpSync"]          = "強制完整公會重新同步"
L["SlashHelpStatus"]        = "傾印同步/通訊診斷資訊"
L["SlashHelpVersionCheck"]  = "檢查公會中的插件版本"
L["SlashHelpDebug"]         = "切換除錯輸出"
L["SlashHelpHelp"]          = "顯示此清單"
L["SlashForceSyncSent"]     = "強制同步已發送。"
L["AHScannerOpenAH"]        = "打開拍賣場以搜尋。"
L["AHOpenFirst"]            = "請先打開拍賣場。"
L["AHNoItemsToScan"]        = "目前檢視中沒有可掃描的物品。"

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "向公會銀行請求"
L["BankDialogBanker"]       = "銀行員:"
L["BankDialogQty"]          = "數量:"
L["BankDialogSend"]         = "發送請求"
L["BankDialogCancel"]       = "取消"

-- ---------------------------------------------------------------------------
-- 清除確認和其他命令輸出
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "所有公會資料已清除。"
L["MsgOwnDataPurged"]        = "你的角色資料已清除。"
L["SlashForceBroadcastSent"] = "強制廣播已發送。"
L["SlashDebugEnabled"]       = "|cff00ff00已啟用|r"
L["SlashDebugDisabled"]      = "|cffff4444已停用|r"
L["SlashDebugToggleFormat"]  = "除錯輸出 %s"

-- ---------------------------------------------------------------------------
-- 專業名稱(官方 Blizzard zhTW,全部 15 項)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "鍊金術"
L["ProfBlacksmithing"]  = "鍛造"
L["ProfCooking"]        = "烹飪"
L["ProfEnchanting"]     = "附魔"
L["ProfEngineering"]    = "工程學"
L["ProfFirstAid"]       = "急救"
L["ProfLeatherworking"] = "製皮"
L["ProfMining"]         = "採礦"
L["ProfTailoring"]      = "裁縫"
L["ProfHerbalism"]      = "草藥學"
L["ProfSkinning"]       = "剝皮"
L["ProfJewelcrafting"]  = "珠寶設計"
L["ProfInscription"]    = "銘文"
L["ProfFishing"]        = "釣魚"
L["ProfSmelting"]       = "熔煉"

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
