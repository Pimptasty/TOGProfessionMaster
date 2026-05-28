-- TOG Profession Master -- Korean (koKR) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("koKR")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — 동기화 기록"

-- Tab labels
L["TabProfessions"]     = "전문기술"
L["TabCooldowns"]       = "재사용 대기시간"
L["TabReagents"]        = "재료"
L["TabMissingRecipes"]  = "미보유 제조법"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "제조법 검색…"
L["ViewGuild"]          = "길드"
L["ViewMine"]           = "내 캐릭터"
L["AllProfessions"]     = "모든 전문기술"
L["PanelProfessions"]   = "전문기술"
L["PanelCharacters"]    = "캐릭터"
L["SelectProfession"]   = "전문기술을 선택하세요"
L["NoDataYet"]          = "|cffaaaaaa(데이터 없음)|r"
L["SelectProfHint"]     = "|cffaaaaaa← 전문기술을 선택하면 누가 보유했는지 표시됩니다.|r"
L["NoProfMembers"]      = "|cffaaaaaa(이 전문기술을 가진 길드원이 없습니다)|r"
L["BackToCharacters"]   = "|cff00aaff← 캐릭터로 돌아가기|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(일치하는 제조법이 없습니다)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "본인"
L["BrowserScanAH"]          = "경매장 검색"
L["BrowserScanAHProgress"]  = "검색 중 %d/%d"
L["BrowserScanAHDesc"]      = "쇼핑 목록의 각 재료에 대해 경매장을 검색합니다. 현재 경매장에 등록된 재료 행에는 [경] 버튼이 표시되며, 클릭하면 해당 경매장 검색으로 바로 이동합니다."
L["CooldownsScanAHDesc"]    = "표시된 재사용 대기시간 행의 각 고유 재료에 대해 경매장을 검색합니다. 현재 등록된 재료 행에는 [경] 버튼이 표시되며, 클릭하면 해당 검색으로 이동합니다."

-- Recipe detail popup
L["PopupCrafters"]       = "보유 캐릭터"
L["PopupOnList"]         = "쇼핑 목록에 있음"
L["PopupNotOnList"]      = "쇼핑 목록에 없음"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "준비 완료만"
L["ShowAll"]                = "전체"
L["FilterColProfession"]    = "전문기술"
L["FilterColCooldown"]      = "재사용 대기시간"
L["FilterColView"]          = "보기"
L["FilterProfessionDesc"]   = "재사용 대기시간 목록을 한 가지 전문기술(연금술, 재봉술 등)로 필터링합니다."
L["FilterCooldownDesc"]     = "선택한 전문기술 내에서 단일 공유 재사용 대기시간(예: 변환, 달의 천)으로 필터링합니다."
L["FilterViewDesc"]         = "모든 길드원의 재사용 대기시간과 자신의 캐릭터만 보기 사이를 전환합니다."
L["AllCooldowns"]           = "모든 재사용 대기시간"
L["FilterTransmute"]            = "변환"
L["FilterAlchResearch"]         = "연금술 연구"
L["FilterMooncloth"]            = "달의 천"
L["FilterSpecialtyCloth"]       = "특수 천"
L["FilterGlacialBag"]           = "빙하 가방"
L["FilterDreamcloth"]           = "꿈의 천"
L["FilterImperialSilk"]         = "황실 비단"
L["FilterSaltShaker"]           = "소금통"
L["FilterMagicSphere"]          = "마법의 구체"
L["FilterShaCrystal"]           = "사 수정"
L["FilterBrilliantGlass"]       = "찬란한 유리"
L["FilterIcyPrism"]             = "차가운 프리즘"
L["FilterFirePrism"]            = "화염 프리즘"
L["FilterJcDaily"]              = "보석 세공 일일 가공"
L["FilterInscriptionResearch"]  = "주문각인 연구"
L["FilterForgedDocuments"]      = "위조 문서"
L["FilterScrollOfWisdom"]       = "지혜의 두루마리"
L["FilterTitansteelBar"]        = "티타늄강철 주괴"
L["FilterBsIngot"]              = "제련"
L["FilterMagnificence"]         = "장엄함"
L["FilterJards"]                = "자드의 에너지"
L["ColCharacter"]           = "캐릭터"
L["ColCooldown"]            = "재사용 대기시간"
L["ColReagent"]             = "재료"
L["ColTimeLeft"]            = "남은 시간"
L["NoCooldownData"]         = "|cffaaaaaa(재사용 대기시간 데이터 없음 — 전문기술 창을 여세요)|r"
L["Ready"]                  = "|cff00ff00준비 완료|r"
L["Transmute"]              = "변환"
L["MailBtn"]                = "우편"
L["MailBtnTooltip"]         = "보급 우편 보내기"
L["MailBtnTooltipDesc"]     = "우편함을 연 다음 클릭하여 재료를 첨부하고 이 플레이어에게 보급 우편을 작성합니다."
L["BankBtn"]                = "[은행]"
L["CloseBtn"]               = "닫기"

-- 전문기술 특화 보너스 산출 표시기
L["SpecBonusGuaranteedDouble"]  = "확정 2배 산출"
L["SpecBonusProcChance"]        = "추가 산출 확률"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "쇼핑 목록"
L["SectionMissingReagents"] = "부족한 재료"
L["SectionReagentWatch"]    = "재료 감시"
L["ShoppingListEmpty"]      = "|cffaaaaaa(비어 있음 — 전문기술 탭에서 제조법 행을 클릭하여 쇼핑 목록에 아이템을 추가하세요)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(쇼핑 목록이 비어 있거나 모든 재료가 가방에 있음)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(감시 중인 아이템 없음 — 위에 아이템 ID 또는 링크를 입력하세요)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch 모듈이 로드되지 않음)|r"
L["WatchInputLabel"]        = "아이템 ID 또는 링크"
L["WatchBtn"]               = "감시"
L["WatchedItemsHeading"]    = "감시 중인 아이템"
L["ColHave"]                = "보유"
L["ColNeed"]                = "필요"
L["ColShort"]               = "부족"
L["ColItem"]                = "아이템"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "캐릭터|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "전문기술|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "제조법 검색…|r"
L["MissingIncludeTrainer"]      = "교관 전용 포함"
L["MissingIncludeTrainerDesc"]  = "교관에게서만 배울 수 있는 제조법을 포함합니다(경매장 두루마리 없음)."
L["MissingScanAH"]              = "경매장 검색"
L["MissingScanAHProgress"]      = "검색 중 %d/%d (취소하려면 클릭)"
L["MissingScanAHDesc"]          = "경매장을 연 다음 클릭하면 표시된 목록의 모든 제조법 두루마리를 검색합니다. 활성 매물이 있는 행에는 [경] 버튼이 표시되며 클릭하여 검색으로 이동할 수 있습니다."
L["MissingNoCharacters"]        = "|cffaaaaaa(전문기술 데이터가 있는 캐릭터 없음 — 전문기술 창을 여세요)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(이 캐릭터는 아직 추적되는 전문기술이 없습니다 — 전문기술 창을 여세요)|r"
L["MissingNoneFound"]           = "|cff00ff00이 전문기술의 알려진 모든 제조법을 배웠습니다.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← 무엇이 부족한지 보려면 전문기술을 선택하세요.|r"
L["MissingNoData"]              = "|cffff8888(이 전문기술의 제조법 데이터가 없습니다)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "제조법"
L["MissingColSkill"]            = "숙련도"
L["MissingColSource"]           = "획득처"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "이 제조법 두루마리 감시"
L["MissingAddToWatchDesc"]      = "제조법 두루마리를 재료 감시 목록에 추가하여 가방에 들어오는 순간 볼 수 있습니다."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "이미 감시 중 — 클릭하여 감시 중단"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "미보유 제조법"
L["MissingCountPlural"]         = "미보유 제조법"
L["MissingTruncatedHint"]       = "(처음 %d개 표시 — 검색창에 입력하여 목록을 좁히세요)"
L["MissingCharTooltipTitle"]    = "캐릭터 필터"
L["MissingCharTooltipDesc"]     = "어느 캐릭터의 미보유 제조법을 볼지 선택합니다. 기본은 현재 접속한 캐릭터입니다."
L["MissingProfTooltipTitle"]    = "전문기술 필터"
L["MissingProfTooltipDesc"]     = "전문기술을 선택하면 이 캐릭터가 아직 배우지 않은 두루마리가 표시됩니다."
L["MissingSearchTooltipTitle"]  = "제조법 검색"
L["MissingSearchTooltipDesc"]   = "입력하면 미보유 제조법 목록을 이름으로 필터링합니다."
L["MissingHdrCountTitle"]       = "미보유 제조법"
L["MissingHdrCountDesc"]        = "선택한 캐릭터가 아직 배우지 않았지만 이 게임 버전에서 획득 가능한 제조법입니다. 숫자는 현재 필터(전문기술, 검색, 교관 토글)를 반영합니다."
L["MissingHdrSkillTitle"]       = "숙련도 수치"
L["MissingHdrSkillDesc"]        = "이 제조법을 배우는 데 필요한 전문기술 숙련도입니다. 회색 행은 캐릭터가 아직 충분히 높지 않음을 의미합니다."
L["MissingHdrSourceTitle"]      = "획득처"
L["MissingHdrSourceDesc"]       = "이 제조법을 얻는 방법 — 교관, 드롭, 상인, 퀘스트 또는 제작. 행의 출처 텍스트 위에 마우스를 올리면 특정 NPC / 몹 / 단계를 볼 수 있습니다."
L["MissingRowTooltipShift"]     = "쉬프트-클릭으로 대화에 링크."
L["MissingSrcVendor"]           = "상인"
L["MissingSrcDrop"]             = "드롭"
L["MissingSrcQuest"]            = "퀘스트"
L["MissingSrcCrafted"]          = "제작"
L["MissingSrcFishing"]          = "낚시"
L["MissingSrcContainer"]        = "용기"
L["MissingSrcTrainer"]          = "교관"
L["MissingSrcOther"]            = "기타"
L["MissingSrcUnknown"]          = "알 수 없음"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "아이템 툴팁"
L["SettingsTooltipShowCrafters"]    = "아이템 툴팁에 길드 제작자 표시"
L["SettingsTooltipShowCraftersDesc"]= "현재 가리키는 아이템을 제작할 수 있는 모든 길드 동료를 나열하는 [TOGPM] 줄을 추가합니다. 접속 중은 흰색, 접속하지 않음은 회색. 획득 시 귀속 아이템은 건너뜁니다(어차피 거래 불가)."
L["SettingsTooltipShowIds"]         = "툴팁에 아이템 ID / 주문 ID 표시"
L["SettingsTooltipShowIdsDesc"]     = "아이템 ID와 (알 경우) 제조법 주문 ID를 포함한 [TOGPM] 줄을 추가합니다. 잘못된 아이콘이나 누락된 제조법을 진단할 때 주로 유용 — ID를 Wowhead에 붙여넣어 일치 여부를 확인하세요."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC 기념 단계"
L["SettingsTBCPhase"]           = "현재 콘텐츠 단계"
L["SettingsTBCPhaseDesc"]       = "현재 기념 단계보다 늦은 단계의 미보유 제조법을 숨깁니다. 블리자드가 단계를 진행할 때마다 값을 올리세요. (활성 단계에서 이미 접근 가능한 제조법은 계속 표시됩니다.)"
L["SettingsTBCPhase1"]          = "1단계 — 카라잔 / 그룰 / 마그테리돈"
L["SettingsTBCPhase2"]          = "2단계 — 뱀파이어 동굴 / 폭풍우 요새"
L["SettingsTBCPhase3"]          = "3단계 — 검은 사원 / 하이잘 산"
L["SettingsTBCPhase4"]          = "4단계 — 태양샘 / 마법사단의 영지"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "표시"
L["SettingsMinimapBtn"]          = "미니맵 버튼 표시"
L["SettingsMinimapBtnDesc"]      = "미니맵 실행 버튼을 표시하거나 숨깁니다."
L["SettingsPersistProfFilter"]     = "전문기술 필터 기억"
L["SettingsPersistProfFilterDesc"] = "접속하거나 다시 로드할 때 선택한 전문기술을 복원합니다."
L["SettingsCooldownsHeader"]= "재사용 대기시간"
L["SettingsMailReadyOnly"]  = "우편: 준비된 재사용 대기시간만 표시"
L["SettingsMailReadyOnlyDesc"] = "재사용 대기시간 패널에서 보급 우편을 작성할 때 재사용 대기시간이 준비된 길드원만 나열합니다."
L["SettingsDevHeader"]      = "개발자"
L["SettingsDebug"]          = "디버그 출력"
L["SettingsDebugDesc"]      = "자세한 디버그 메시지를 채팅창에 표시합니다."
L["SettingsDataHeader"]     = "데이터"
L["SettingsSyncNow"]        = "강제 재동기화"
L["SettingsSyncNowDesc"]    = "즉시 전문기술 데이터를 길드에 전송합니다."
L["SettingsPurgeGuild"]     = "모든 길드 데이터 삭제"
L["SettingsPurgeGuildDesc"] = "이 계정의 모든 길드원에 대한 저장된 전문기술 및 재사용 대기시간 데이터를 삭제합니다. 되돌릴 수 없습니다."
L["SettingsPurgeGuildConfirm"] = "이 계정의 모든 길드 데이터를 삭제하시겠습니까?"
L["SettingsPurgeMine"]      = "내 캐릭터 데이터 삭제"
L["SettingsPurgeMineDesc"]  = "길드 데이터베이스에서 자신의 캐릭터 저장 데이터만 삭제합니다."
L["SettingsPurgeMineConfirm"] = "자신의 전문기술 및 재사용 대기시간 데이터를 삭제하시겠습니까?"
L["SettingsSyncLogHeader"]  = "동기화 기록"
L["SettingsViewLog"]        = "동기화 기록 보기"
L["SettingsViewLogDesc"]    = "최근 동기화 이벤트(최근 200개)의 스크롤 가능한 목록을 엽니다."
L["SettingsClearLog"]       = "동기화 기록 지우기"
L["SettingsClearLogConfirm"]= "모든 동기화 기록 항목을 지우시겠습니까?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog 모듈이 로드되지 않음)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(아직 기록된 동기화 이벤트가 없습니다)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "미니맵 버튼 숨김. |cffda8cff/togpm minimap|r을 사용하여 복원하세요."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "제작자:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00제작 준비 완료:|r %s × %d  (%s × %d 가방 안)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "이 제조법에 대한 제작자 알림 활성화"
L["ShoppingAlertDisable"]              = "이 제조법에 대한 제작자 알림 비활성화"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s 접속 — 제작 가능: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s 접속 (%s의 부캐) — 제작 가능: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "이 재사용 대기시간 준비 알림 활성화"
L["CooldownAlertDisable"]              = "이 재사용 대기시간 준비 알림 비활성화"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r 재사용 대기시간 준비: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "제작자 알림"
L["SettingsCrafterAlert"]              = "제작자 알림 활성화"
L["SettingsCrafterAlertDesc"]          = "쇼핑 목록의 알림 설정된 아이템을 제작할 수 있는 길드원이 접속하면 소리를 재생하고 화면을 깜빡입니다."
L["SettingsCrafterAlertSuppressAV"]    = "소리 및 깜빡임 억제"
L["SettingsCrafterAlertSuppressAVDesc"]    = "오디오 및 화면 깜빡임 효과를 비활성화합니다(채팅 메시지는 여전히 나타남)."
L["SettingsCrafterAlertSuppressLogin"]     = "접속 시 알림 억제"
L["SettingsCrafterAlertSuppressLoginDesc"] = "접속하거나 UI를 다시 로드할 때 초기 접속 알림 폭주 동안 알림을 발동하지 않습니다."
L["SettingsCooldownAlertSuppressProtected"]     = "인스턴스에서 알림 음소거"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "공격대, 던전, 전장, 투기장 또는 시나리오에 있는 동안 재사용 대기시간 준비 알림을 발생시키지 않습니다. 수도는 음소거되지 않습니다 — 스톰윈드에서 잠수 중이라도 변환은 계속 알림이 옵니다. 대기 중인 알림은 인스턴스를 떠나는 즉시 발동됩니다."
L["SettingsCooldownReminderInterval"]      = "재사용 대기시간 준비 알림 재발동"
L["SettingsCooldownReminderIntervalDesc"]  = "재사용 대기시간이 준비된 동안(즉, 실제로 제작할 때까지) 각 활성화된 재사용 대기시간 알림을 N분마다 다시 발동합니다. 0, 비워두기 또는 'off'를 입력하면 준비 주기당 한 번만 발동합니다. 유효 범위: 1–1440분(24시간)."
L["SettingsCooldownReminderInvalid"]       = "0에서 1440 사이의 정수 또는 'off'를 입력하세요."

L["SettingsAHHeader"]                      = "경매장"
L["SettingsAHScanDelay"]                   = "경매장 검색 지연(초)"
L["SettingsAHScanDelayDesc"]               = "경매장 검색 쿼리 사이의 초입니다. 비워두기 / 0 / 'off'는 버전 기본값을 사용합니다(Classic Era 및 Anniversary에서 1.5초; TBC, Wrath, Cata, MoP에서 3.0초 — 해당 서버는 더 엄격하게 제한). 더 빠른 검색을 위해 값을 낮추고, 검색이 멈추면 올리세요. 유효 범위: 0.5–10초."
L["SettingsAHScanDelayInvalid"]            = "0.5에서 10 사이의 숫자 또는 'off'를 입력하세요."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "제조법"
L["TooltipRecipeDesc"]           = "제작 가능한 아이템 또는 주문의 이름입니다."
L["TooltipCraftersTitle"]        = "제작자"
L["TooltipCraftersDesc"]         = "이 제조법을 보유한 길드원입니다. 전체 목록을 보려면 제조법을 클릭하세요."
L["CraftersColHeader"]           = "제작자"
L["TooltipBankTitle"]            = "은행에 요청"
L["TooltipBankDescScroll"]       = "이 제조법 두루마리에 대해 TOGBankClassic 길드 은행원에게 요청을 보냅니다."
L["TooltipBankDescGeneric"]      = "TOGBankClassic 길드 은행원에게 요청을 보냅니다."
L["TooltipAHTitle"]              = "경매장 검색"
L["TooltipAHDescScroll"]         = "이 제조법 두루마리를 경매장 검색에서 엽니다."
L["TooltipAHDescReagent"]        = "이 재료를 경매장 검색에서 엽니다."
L["TooltipSettingsTitle"]        = "설정"
L["TooltipSettingsDesc"]         = "TOG Profession Master 설정 패널을 엽니다(|cffffd700ESC > 옵션 > 애드온 > TOG Profession Master|r). |cffffd700/togpm settings|r 및 미니맵 버튼의 쉬프트+왼쪽 클릭과 동일한 대상입니다."
L["TooltipWhisperRightClick"]    = "귓속말 보내려면 우클릭"
L["TooltipClickTransmutes"]      = "변환 보려면 클릭"
L["TooltipClickDetailsFormat"]   = "%s 보려면 클릭"
L["TooltipClickDetailsFallback"] = "세부 정보"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "재사용 대기시간 보급: %s"
L["MailBodyFormat"]         = "안녕하세요 %s님! 이 재료들을 사용하여 %s을(를) 만들어 주세요. 제작할 시간이 있을 때 %s을(를) 보내주세요. 감사합니다!"
L["MailMsgNoEmptyBag"]      = "분할할 빈 가방 슬롯이 없습니다."
L["MailMsgOpenMailbox"]     = "먼저 우편함을 여세요."
L["MailMsgHasItems"]        = "우편에 이미 첨부된 아이템이 있습니다 — 먼저 보내거나 제거하세요."
L["MailMsgCannotFulfill"]   = "이행할 수 없습니다."
L["MailMsgCouldNotAttach"]  = "아이템을 첨부할 수 없습니다."
L["MailMsgAttachedFormat"]  = "%s에게 %dx %s 첨부됨."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100왼쪽 클릭|r으로 전문기술 탐색기 표시/숨김"
L["MinimapTooltipRightClick"]  = "|cffffd100오른쪽 클릭|r으로 재료 표시/숨김"
L["MinimapTooltipShiftLeft"]   = "|cffffd100쉬프트+왼쪽|r으로 설정 열기"
L["MinimapButtonShown"]        = "미니맵 버튼 표시됨."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- 명령어 이름은 번역되지 않음
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — 명령어:"
L["SlashHelpOpen"]          = "전문기술 탐색기 열기"
L["SlashHelpReagents"]      = "부족한 재료 열기"
L["SlashHelpMinimap"]       = "미니맵 버튼 표시"
L["SlashHelpPurge"]         = "삭제 대화상자 열기"
L["SlashHelpSync"]          = "전체 길드 재동기화 강제"
L["SlashHelpStatus"]        = "동기화/통신 진단 정보 덤프"
L["SlashHelpVersionCheck"]  = "길드의 애드온 버전 확인"
L["SlashHelpDebug"]         = "디버그 출력 전환"
L["SlashHelpHelp"]          = "이 목록 표시"
L["SlashForceSyncSent"]     = "강제 동기화 전송됨."
L["AHScannerOpenAH"]        = "검색하려면 경매장을 여세요."
L["AHOpenFirst"]            = "먼저 경매장을 여세요."
L["AHNoItemsToScan"]        = "현재 보기에 검색할 아이템이 없습니다."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "길드 은행에 요청"
L["BankDialogBanker"]       = "은행원:"
L["BankDialogQty"]          = "수량:"
L["BankDialogSend"]         = "요청 보내기"
L["BankDialogCancel"]       = "취소"

-- ---------------------------------------------------------------------------
-- 삭제 확인 및 기타 명령어 출력
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "모든 길드 데이터가 삭제되었습니다."
L["MsgOwnDataPurged"]        = "캐릭터 데이터가 삭제되었습니다."
L["SlashForceBroadcastSent"] = "강제 브로드캐스트 전송됨."
L["SlashDebugEnabled"]       = "|cff00ff00활성화|r"
L["SlashDebugDisabled"]      = "|cffff4444비활성화|r"
L["SlashDebugToggleFormat"]  = "디버그 출력 %s"

-- ---------------------------------------------------------------------------
-- 전문기술 이름 (공식 Blizzard koKR, 전체 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "연금술"
L["ProfBlacksmithing"]  = "대장기술"
L["ProfCooking"]        = "요리"
L["ProfEnchanting"]     = "마법부여"
L["ProfEngineering"]    = "기계공학"
L["ProfFirstAid"]       = "응급치료"
L["ProfLeatherworking"] = "가죽세공"
L["ProfMining"]         = "채광"
L["ProfTailoring"]      = "재봉술"
L["ProfHerbalism"]      = "약초채집"
L["ProfSkinning"]       = "무두질"
L["ProfJewelcrafting"]  = "보석세공"
L["ProfInscription"]    = "주문각인"
L["ProfFishing"]        = "낚시"
L["ProfSmelting"]       = "제련"
