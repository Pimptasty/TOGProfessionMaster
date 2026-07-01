-- TOG Profession Master -- Simplified Chinese (zhCN) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("zhCN")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — 同步日志"

-- Tab labels
L["TabProfessions"]     = "专业"
L["TabCooldowns"]       = "冷却时间"
L["TabReagents"]        = "材料"
L["TabMissingRecipes"]  = "缺失的配方"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "搜索配方…"
L["ViewGuild"]          = "公会"
L["ViewMine"]           = "我的角色"
L["AllProfessions"]     = "所有专业"
L["PanelProfessions"]   = "专业"
L["PanelCharacters"]    = "角色"
L["SelectProfession"]   = "选择一个专业"
L["NoDataYet"]          = "|cffaaaaaa(暂无数据)|r"
L["SelectProfHint"]     = "|cffaaaaaa← 选择一个专业以查看谁掌握它。|r"
L["NoProfMembers"]      = "|cffaaaaaa(没有公会成员拥有此专业)|r"
L["BackToCharacters"]   = "|cff00aaff← 返回角色|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(没有匹配的配方)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "你"
L["BrowserScanAH"]          = "扫描拍卖行"
L["BrowserScanAHProgress"]  = "扫描中 %d/%d"
L["BrowserScanAHDesc"]      = "扫描拍卖行中购物清单上的每种材料。当前在拍卖行有货的材料行会显示 [拍] 按钮;点击直接跳转到拍卖行搜索。"
L["CooldownsScanAHDesc"]    = "扫描拍卖行中可见冷却时间行的每种独特材料。当前在拍卖行有货的材料行会显示 [拍] 按钮(位于 [银行] 左侧);点击跳转到搜索。"

-- Recipe detail popup
L["PopupCrafters"]       = "掌握者"
L["PopupOnList"]         = "在购物清单中"
L["PopupNotOnList"]      = "不在购物清单中"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "仅就绪"
L["ShowAll"]                = "全部"
L["FilterColProfession"]    = "专业"
L["FilterColCooldown"]      = "冷却"
L["FilterColView"]          = "视图"
L["FilterProfessionDesc"]   = "按单一专业(炼金术、裁缝等)筛选冷却时间列表。"
L["FilterCooldownDesc"]     = "在所选专业内,按单一共享冷却时间(例如转化、月布)筛选。"
L["FilterViewDesc"]         = "在所有公会成员的冷却时间和仅你的角色之间切换。"
L["AllCooldowns"]           = "所有冷却时间"
L["FilterTransmute"]            = "转化"
L["FilterAlchResearch"]         = "炼金研究"
L["FilterMooncloth"]            = "月布"
L["FilterSpecialtyCloth"]       = "特殊布料"
L["FilterGlacialBag"]           = "冰川袋"
L["FilterDreamcloth"]           = "梦境布"
L["FilterImperialSilk"]         = "帝皇丝绸"
L["FilterSaltShaker"]           = "盐瓶"
L["FilterMagicSphere"]          = "魔法球"
L["FilterShaCrystal"]           = "煞水晶"
L["FilterBrilliantGlass"]       = "璀璨玻璃"
L["FilterIcyPrism"]             = "冰冷棱镜"
L["FilterFirePrism"]            = "火焰棱镜"
L["FilterJcDaily"]              = "珠宝加工日常切割"
L["FilterInscriptionResearch"]  = "铭文研究"
L["FilterForgedDocuments"]      = "伪造文件"
L["FilterScrollOfWisdom"]       = "智慧卷轴"
L["FilterTitansteelBar"]        = "泰坦钢锭"
L["FilterBsIngot"]              = "熔炼"
L["FilterMagnificence"]         = "宏伟之力"
L["FilterJards"]                = "贾德之能"
L["ColCharacter"]           = "角色"
L["ColCooldown"]            = "冷却"
L["ColReagent"]             = "材料"
L["ColTimeLeft"]            = "剩余时间"
L["NoCooldownData"]         = "|cffaaaaaa(暂无冷却时间数据 — 打开专业窗口)|r"
L["Ready"]                  = "|cff00ff00就绪|r"
L["Transmute"]              = "转化"
L["MailBtn"]                = "邮件"
L["MailBtnTooltip"]         = "发送补给邮件"
L["MailBtnTooltipDesc"]     = "打开邮箱,然后点击附加材料并向此玩家撰写补给邮件。"
L["BankBtn"]                = "[银行]"
L["CloseBtn"]               = "关闭"

-- 专业特化产出加成指示器
L["SpecBonusGuaranteedDouble"]  = "保证 2 倍产出"
L["SpecBonusProcChance"]        = "有几率产生额外产出"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "购物清单"
L["SectionMissingReagents"] = "缺失材料"
L["SectionReagentWatch"]    = "材料监视"
L["ShoppingListEmpty"]      = "|cffaaaaaa(为空 — 在专业选项卡中点击配方行将物品添加到购物清单)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(购物清单为空或所有材料都在背包中)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(没有监视的物品 — 在上方输入物品 ID 或链接)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch 模块未加载)|r"
L["WatchInputLabel"]        = "物品 ID 或链接"
L["WatchBtn"]               = "监视"
L["WatchedItemsHeading"]    = "监视的物品"
L["ColHave"]                = "拥有"
L["ColNeed"]                = "需要"
L["ColShort"]               = "短缺"
L["ColItem"]                = "物品"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "角色|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "专业|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "搜索配方…|r"
L["MissingIncludeTrainer"]      = "包含训练师专属"
L["MissingIncludeTrainerDesc"]  = "包含只能从训练师那里学到的配方(无拍卖行卷轴)。"
L["MissingScanAH"]              = "扫描拍卖行"
L["MissingScanAHProgress"]      = "扫描中 %d/%d (点击取消)"
L["MissingScanAHDesc"]          = "打开拍卖行,然后点击扫描可见列表中每个配方卷轴。有活跃挂牌的行会显示 [拍] 按钮;点击跳转到搜索。"
L["MissingNoCharacters"]        = "|cffaaaaaa(还没有带专业数据的角色 — 打开专业窗口)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(此角色尚未追踪任何专业 — 打开专业窗口)|r"
L["MissingNoneFound"]           = "|cff00ff00此专业所有已知配方都已学会。|r"
L["MissingPickProfession"]      = "|cffaaaaaa← 选择一个专业以查看缺什么。|r"
L["MissingNoData"]              = "|cffff8888(此专业暂无可用配方数据)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "配方"
L["MissingColSkill"]            = "技能"
L["MissingColSource"]           = "来源"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "监视此配方卷轴"
L["MissingAddToWatchDesc"]      = "将配方卷轴添加到你的材料监视列表,它一进入背包你就会看到。"
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "已在监视中 — 点击停止监视"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "缺失的配方"
L["MissingCountPlural"]         = "缺失的配方"
L["MissingTruncatedHint"]       = "(显示前 %d 个 — 在搜索框中输入以缩小列表)"
L["MissingCharTooltipTitle"]    = "角色筛选"
L["MissingCharTooltipDesc"]     = "选择要查看缺失配方的角色。默认为当前登录的角色。"
L["MissingProfTooltipTitle"]    = "专业筛选"
L["MissingProfTooltipDesc"]     = "选择一个专业以查看此角色尚未学会的卷轴。"
L["MissingSearchTooltipTitle"]  = "搜索配方"
L["MissingSearchTooltipDesc"]   = "输入以按名称筛选缺失配方列表。"
L["MissingHdrCountTitle"]       = "缺失的配方"
L["MissingHdrCountDesc"]        = "所选角色尚未学会但可在此游戏版本中获得的配方。数字反映当前筛选(专业、搜索、训练师开关)。"
L["MissingHdrSkillTitle"]       = "技能等级"
L["MissingHdrSkillDesc"]        = "学习此配方所需的专业技能等级。灰色行表示角色尚未达到所需等级。"
L["MissingHdrSourceTitle"]      = "来源"
L["MissingHdrSourceDesc"]       = "如何获得此配方 — 训练师、掉落、商人、任务或制造。将鼠标悬停在行的来源文本上以查看具体的 NPC / 怪物 / 步骤。"
L["MissingRowTooltipShift"]     = "Shift-点击在聊天中链接。"
L["MissingSrcVendor"]           = "商人"
L["MissingSrcDrop"]             = "掉落"
L["MissingSrcQuest"]            = "任务"
L["MissingSrcCrafted"]          = "制造"
L["MissingSrcFishing"]          = "钓鱼"
L["MissingSrcContainer"]        = "容器"
L["MissingSrcTrainer"]          = "训练师"
L["MissingSrcOther"]            = "其他"
L["MissingSrcUnknown"]          = "未知"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "物品提示"
L["SettingsTooltipShowCrafters"]    = "在物品提示中显示公会制造者"
L["SettingsTooltipShowCraftersDesc"]= "添加一行 [TOGPM],列出可以制造你正在悬停的物品的每个公会成员。在线为白色,离线为灰色。拾取绑定的物品会被跳过(无论如何都不能交易)。"
L["SettingsTooltipShowIds"]         = "在物品提示中显示物品 ID / 法术 ID"
L["SettingsTooltipShowIdsDesc"]     = "添加一行 [TOGPM],包含物品 ID 和(如果已知)配方法术 ID。主要用于诊断错误的图标或缺失的配方 — 将 ID 粘贴到 Wowhead 以验证匹配。"

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC 周年阶段"
L["SettingsTBCPhase"]           = "当前内容阶段"
L["SettingsTBCPhaseDesc"]       = "隐藏来自比当前周年阶段更晚阶段的缺失配方。每当暴雪推进阶段时,提升该值。(当前活跃阶段已可访问的配方保持可见。)"
L["SettingsTBCPhase1"]          = "第 1 阶段 — 卡拉赞 / 格鲁尔 / 玛瑟里顿"
L["SettingsTBCPhase2"]          = "第 2 阶段 — 毒蛇神殿 / 风暴要塞"
L["SettingsTBCPhase3"]          = "第 3 阶段 — 黑暗神殿 / 海加尔山"
L["SettingsTBCPhase4"]          = "第 4 阶段 — 太阳之井 / 大法师学院"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "显示"
L["SettingsMinimapBtn"]          = "显示小地图按钮"
L["SettingsMinimapBtnDesc"]      = "显示或隐藏小地图启动器按钮。"
L["SettingsPersistProfFilter"]     = "记住专业筛选"
L["SettingsPersistProfFilterDesc"] = "登录或重新加载时恢复所选专业。"
L["SettingsSyncHeader"]     = "同步"
L["SettingsGuildMode"]      = "仅公会同步模式（私服）"
L["SettingsGuildModeDesc"]  = "适用于不通过密语传递插件消息的私服或模拟服务器（例如 Whitemane），这会导致公会成员无法收到彼此的专业数据。开启后，所有同步流量将改为通过公会频道传输。仅在你的服务器上公会同步无法正常工作时才开启。|cffffd100公会中的所有人都应开启它|r——只有双方都开启的成员之间才有效。开启此项时会自动禁用跨公会共享。适用于此服务器上的所有角色。（如果你安装的 DeltaSync 版本不支持，则会隐藏。）"
L["SettingsCooldownsHeader"]= "冷却时间"
L["SettingsMailReadyOnly"]  = "邮件:仅显示已就绪的冷却时间"
L["SettingsMailReadyOnlyDesc"] = "从冷却时间面板撰写补给邮件时,仅列出冷却时间已就绪的公会成员。"
L["SettingsDevHeader"]      = "开发者"
L["SettingsDebug"]          = "调试输出"
L["SettingsDebugDesc"]      = "将详细调试信息打印到聊天框。"
L["SettingsDataHeader"]     = "数据"
L["SettingsSyncNow"]        = "强制重新同步"
L["SettingsSyncNowDesc"]    = "立即将你的专业数据广播到公会。"
L["SettingsPurgeGuild"]     = "清除所有公会数据"
L["SettingsPurgeGuildDesc"] = "删除此账户上每个公会成员存储的所有专业和冷却时间数据。无法撤销。"
L["SettingsPurgeGuildConfirm"] = "删除此账户的所有公会数据?"
L["SettingsPurgeMine"]      = "清除我的角色数据"
L["SettingsPurgeMineDesc"]  = "仅从公会数据库中删除你自己角色的存储数据。"
L["SettingsPurgeMineConfirm"] = "删除你自己的专业和冷却时间数据?"
L["SettingsSyncLogHeader"]  = "同步日志"
L["SettingsViewLog"]        = "查看同步日志"
L["SettingsViewLogDesc"]    = "打开最近同步事件(最近 200 条)的可滚动列表。"
L["SettingsClearLog"]       = "清除同步日志"
L["SettingsClearLogConfirm"]= "清除所有同步日志条目?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog 模块未加载)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(尚未记录同步事件)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "小地图按钮已隐藏。使用 |cffda8cff/togpm minimap|r 恢复。"

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "制造者:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00可以制造:|r %s × %d  (%s × %d 在背包中)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "为此配方启用制造者提醒"
L["ShoppingAlertDisable"]              = "为此配方禁用制造者提醒"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s 在线 — 可以制造:%s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s 在线(%s 的小号)— 可以制造:%s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "为此冷却时间启用就绪提醒"
L["CooldownAlertDisable"]              = "为此冷却时间禁用就绪提醒"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r 冷却时间就绪:%s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "制造者提醒"
L["SettingsCrafterAlert"]              = "启用制造者提醒"
L["SettingsCrafterAlertDesc"]          = "当可以制造已提醒的购物清单物品的公会成员上线时,播放声音并使屏幕闪烁。"
L["SettingsCrafterAlertSuppressAudio"]     = "禁用提示音"
L["SettingsCrafterAlertSuppressAudioDesc"] = "当制作者上线时禁用提示音(屏幕闪烁和聊天消息仍会出现)。"
L["SettingsCrafterAlertSuppressVisual"]    = "禁用提示视觉效果"
L["SettingsCrafterAlertSuppressVisualDesc"] = "当制作者上线时禁用屏幕视觉提示(屏幕闪烁、横幅等)(声音和聊天消息仍会出现)。"
L["AlertCrafterOnlineBanner"]              = "公会制造者上线"
L["SettingsCrafterAlertSound"]             = "提示音效"
L["SettingsCrafterAlertSoundDesc"]         = "当你能联系到的制造者上线时播放的音效。选择某项即可试听。当上方已禁用提示音时,此设置无效。"
L["SettingsCrafterAlertVisual"]            = "视觉提示"
L["SettingsCrafterAlertVisualDesc"]        = "当制造者上线时触发的屏幕效果 — 可选择以你所选色调进行全屏闪烁,或在你切换到其他窗口时使任务栏闪烁。选择某项即可预览。当上方已禁用屏幕闪烁时,此设置无效。"
L["SettingsCrafterAlertSuppressLogin"]     = "登录时禁用提醒"
L["SettingsCrafterAlertSuppressLoginDesc"] = "登录或重新加载 UI 时,不在初始上线通知爆发期间触发提醒。"
L["SettingsCooldownAlertSuppressProtected"]     = "在副本中静音提醒"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "在团队副本、地下城、战场、竞技场或场景中时,不发出冷却时间就绪提醒。首都不会被静音 — 即使你在暴风城挂机,你的转化也会继续提醒。待处理的提醒会在你离开副本时立即触发。"
L["SettingsCooldownReminderInterval"]      = "冷却时间就绪提醒间隔"
L["SettingsCooldownReminderIntervalDesc"]  = "在冷却时间保持就绪状态时(即直到你实际制造),每 N 分钟重新触发每个已启用的冷却时间提醒。输入 0、空或 'off' 表示每个就绪周期仅触发一次。有效范围:1–1440 分钟(24 小时)。"
L["SettingsCooldownReminderInvalid"]       = "输入 0 到 1440 之间的整数,或 'off'。"

L["SettingsAHHeader"]                      = "拍卖行"
L["SettingsAHScanDelay"]                   = "拍卖行扫描延迟(秒)"
L["SettingsAHScanDelayDesc"]               = "拍卖行扫描查询之间的秒数。空 / 0 / 'off' 使用版本默认值(Classic Era 和 Anniversary 上为 1.5 秒;TBC、Wrath、Cata、MoP 上为 3.0 秒 — 这些服务器限制更严格)。降低值以加快扫描,如果扫描停滞则提高。有效范围:0.5–10 秒。"
L["SettingsAHScanDelayInvalid"]            = "输入 0.5 到 10 之间的数字,或 'off'。"

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "配方"
L["TooltipRecipeDesc"]           = "可制造物品或法术的名称。"
L["TooltipCraftersTitle"]        = "制造者"
L["TooltipCraftersDesc"]         = "掌握此配方的公会成员。点击配方查看完整列表。"
L["CraftersColHeader"]           = "制造者"
L["TooltipBankTitle"]            = "向银行请求"
L["TooltipBankDescScroll"]       = "向 TOGBankClassic 公会银行家发送此配方卷轴的请求。"
L["TooltipBankDescGeneric"]      = "向 TOGBankClassic 公会银行家发送请求。"
L["TooltipAHTitle"]              = "搜索拍卖行"
L["TooltipAHDescScroll"]         = "在拍卖行搜索中打开此配方卷轴。"
L["TooltipAHDescReagent"]        = "在拍卖行搜索中打开此材料。"
L["TooltipSettingsTitle"]        = "设置"
L["TooltipSettingsDesc"]         = "打开 TOG Profession Master 设置面板(|cffffd700ESC > 选项 > 插件 > TOG Profession Master|r)。与 |cffffd700/togpm settings|r 和 Shift+左键单击小地图按钮目标相同。"
L["TooltipWhisperRightClick"]    = "右键单击私聊"
L["TooltipClickTransmutes"]      = "点击查看转化"
L["TooltipClickDetailsFormat"]   = "点击查看 %s"
L["TooltipClickDetailsFallback"] = "详情"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "冷却时间补给:%s"
L["MailBodyFormat"]         = "你好 %s!请使用这些材料制作 %s。请在有时间制造时给我寄回 %s。谢谢!"
L["MailMsgNoEmptyBag"]      = "没有空的背包格用于拆分。"
L["MailMsgOpenMailbox"]     = "请先打开邮箱。"
L["MailMsgHasItems"]        = "邮件已附加物品 — 请先发送或移除它们。"
L["MailMsgCannotFulfill"]   = "无法完成。"
L["MailMsgCouldNotAttach"]  = "无法附加物品。"
L["MailMsgAttachedFormat"]  = "已为 %s 附加 %dx %s。"

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100左键单击|r 切换专业浏览器"
L["MinimapTooltipRightClick"]  = "|cffffd100右键单击|r 切换材料"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+左键|r 打开设置"
L["MinimapButtonShown"]        = "小地图按钮已显示。"

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- 命令名称不翻译
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — 命令:"
L["SlashHelpOpen"]          = "打开专业浏览器"
L["SlashHelpReagents"]      = "打开缺失的材料"
L["SlashHelpMinimap"]       = "显示小地图按钮"
L["SlashHelpPurge"]         = "打开清除对话框"
L["SlashHelpSync"]          = "强制完整公会重新同步"
L["SlashHelpStatus"]        = "转储同步/通信诊断信息"
L["SlashHelpVersionCheck"]  = "检查公会中的插件版本"
L["SlashHelpDebug"]         = "切换调试输出"
L["SlashHelpHelp"]          = "显示此列表"
L["SlashForceSyncSent"]     = "强制同步已发送。"
L["AHScannerOpenAH"]        = "打开拍卖行以搜索。"
L["AHOpenFirst"]            = "请先打开拍卖行。"
L["AHNoItemsToScan"]        = "当前视图中没有可扫描的物品。"

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "向公会银行请求"
L["BankDialogBanker"]       = "银行家:"
L["BankDialogQty"]          = "数量:"
L["BankDialogSend"]         = "发送请求"
L["BankDialogCancel"]       = "取消"

-- ---------------------------------------------------------------------------
-- 清除确认和其他命令输出
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "所有公会数据已清除。"
L["MsgOwnDataPurged"]        = "你的角色数据已清除。"
L["SlashForceBroadcastSent"] = "强制广播已发送。"
L["SlashDebugEnabled"]       = "|cff00ff00已启用|r"
L["SlashDebugDisabled"]      = "|cffff4444已禁用|r"
L["SlashDebugToggleFormat"]  = "调试输出 %s"

-- ---------------------------------------------------------------------------
-- 专业名称(官方 Blizzard zhCN,全部 15 个)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "炼金术"
L["ProfBlacksmithing"]  = "锻造"
L["ProfCooking"]        = "烹饪"
L["ProfEnchanting"]     = "附魔"
L["ProfEngineering"]    = "工程学"
L["ProfFirstAid"]       = "急救"
L["ProfLeatherworking"] = "制皮"
L["ProfMining"]         = "采矿"
L["ProfTailoring"]      = "裁缝"
L["ProfHerbalism"]      = "草药学"
L["ProfSkinning"]       = "剥皮"
L["ProfJewelcrafting"]  = "珠宝加工"
L["ProfInscription"]    = "铭文"
L["ProfFishing"]        = "钓鱼"
L["ProfSmelting"]       = "熔炼"

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
