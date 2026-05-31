-- TOG Profession Master -- Russian (ruRU) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("ruRU")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — журнал синхронизации"

-- Tab labels
L["TabProfessions"]     = "Профессии"
L["TabCooldowns"]       = "Восстановление"
L["TabReagents"]        = "Реагенты"
L["TabMissingRecipes"]  = "Недостающие рецепты"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Поиск рецептов…"
L["ViewGuild"]          = "Гильдия"
L["ViewMine"]           = "Мои персонажи"
L["AllProfessions"]     = "Все профессии"
L["PanelProfessions"]   = "Профессии"
L["PanelCharacters"]    = "Персонажи"
L["SelectProfession"]   = "Выберите профессию"
L["NoDataYet"]          = "|cffaaaaaa(данных пока нет)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Выберите профессию, чтобы увидеть, кто ею владеет.|r"
L["NoProfMembers"]      = "|cffaaaaaa(нет членов гильдии с этой профессией)|r"
L["BackToCharacters"]   = "|cff00aaff← Назад к персонажам|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(нет подходящих рецептов)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Вы"
L["BrowserScanAH"]          = "Сканировать АД"
L["BrowserScanAHProgress"]  = "Сканирование %d/%d"
L["BrowserScanAHDesc"]      = "Сканирует аукцион в поисках каждого реагента из вашего списка покупок. Строки, реагент которых сейчас на АД, получают кнопку [АД]; нажмите её, чтобы сразу перейти к поиску на аукционе."
L["CooldownsScanAHDesc"]    = "Сканирует аукцион в поисках каждого уникального реагента в видимых строках восстановления. Строки, реагент которых сейчас на АД, получают кнопку [АД] (слева от [Банк]); нажмите её, чтобы сразу перейти к поиску."

-- Recipe detail popup
L["PopupCrafters"]       = "Знают"
L["PopupOnList"]         = "В списке покупок"
L["PopupNotOnList"]      = "Не в списке покупок"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Только готовые"
L["ShowAll"]                = "Все"
L["FilterColProfession"]    = "Профессия"
L["FilterColCooldown"]      = "Восстановление"
L["FilterColView"]          = "Вид"
L["FilterProfessionDesc"]   = "Фильтрует список восстановлений по одной профессии (Алхимия, Портняжное дело и т. д.)."
L["FilterCooldownDesc"]     = "Внутри выбранной профессии фильтрует по одному общему восстановлению (например, Превращение, Лунная ткань)."
L["FilterViewDesc"]         = "Переключает между восстановлениями всех членов гильдии и только ваших персонажей."
L["AllCooldowns"]           = "Все восстановления"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Превращение"
L["FilterAlchResearch"]         = "Исследования алхимии"
L["FilterMooncloth"]            = "Лунная ткань"
L["FilterSpecialtyCloth"]       = "Особая ткань"
L["FilterGlacialBag"]           = "Ледниковая сумка"
L["FilterDreamcloth"]           = "Ткань снов"
L["FilterImperialSilk"]         = "Имперский шёлк"
L["FilterSaltShaker"]           = "Солонка"
L["FilterMagicSphere"]          = "Магическая сфера"
L["FilterShaCrystal"]           = "Кристалл ша"
L["FilterBrilliantGlass"]       = "Сверкающее стекло"
L["FilterIcyPrism"]             = "Ледяная призма"
L["FilterFirePrism"]            = "Огненная призма"
L["FilterJcDaily"]              = "Ежедневная огранка"
L["FilterInscriptionResearch"]  = "Исследования начертания"
L["FilterForgedDocuments"]      = "Поддельные документы"
L["FilterScrollOfWisdom"]       = "Свиток мудрости"
L["FilterTitansteelBar"]        = "Слиток титановой стали"
L["FilterBsIngot"]              = "Плавка"
L["FilterMagnificence"]         = "Великолепие"
L["FilterJards"]                = "Энергия Жарда"
L["ColCharacter"]           = "Персонаж"
L["ColCooldown"]            = "Восстановление"
L["ColReagent"]             = "Реагент"
L["ColTimeLeft"]            = "Осталось"
L["NoCooldownData"]         = "|cffaaaaaa(данных о восстановлении ещё нет — откройте окно профессии)|r"
L["Ready"]                  = "|cff00ff00Готово|r"
L["Transmute"]              = "Превращение"
L["MailBtn"]                = "Почта"
L["MailBtnTooltip"]         = "Отправить посылку с материалами"
L["MailBtnTooltipDesc"]     = "Откройте почтовый ящик, затем нажмите, чтобы вложить реагенты и составить письмо с материалами этому игроку."
L["BankBtn"]                = "[Банк]"
L["CloseBtn"]               = "Закрыть"

-- Индикатор бонуса специализации профессии
L["SpecBonusGuaranteedDouble"]  = "Гарантированный двойной выход"
L["SpecBonusProcChance"]        = "Шанс на дополнительный выход"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Список покупок"
L["SectionMissingReagents"] = "Недостающие реагенты"
L["SectionReagentWatch"]    = "Отслеживание реагентов"
L["ShoppingListEmpty"]      = "|cffaaaaaa(пусто — нажмите строку рецепта на вкладке Профессии, чтобы добавить предмет в список покупок)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(список покупок пуст или все реагенты есть в сумках)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(нет отслеживаемых предметов — введите ID предмета или ссылку выше)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(модуль ReagentWatch не загружен)|r"
L["WatchInputLabel"]        = "ID предмета или ссылка"
L["WatchBtn"]               = "Отслеживать"
L["WatchedItemsHeading"]    = "Отслеживаемые предметы"
L["ColHave"]                = "Есть"
L["ColNeed"]                = "Нужно"
L["ColShort"]               = "Не хватает"
L["ColItem"]                = "Предмет"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Персонаж|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Профессия|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Поиск рецептов…|r"
L["MissingIncludeTrainer"]      = "Только у учителя"
L["MissingIncludeTrainerDesc"]  = "Включает рецепты, которые можно выучить только у учителя профессии (без свитка на АД)."
L["MissingScanAH"]              = "Сканировать АД"
L["MissingScanAHProgress"]      = "Сканирование %d/%d (нажмите, чтобы отменить)"
L["MissingScanAHDesc"]          = "Откройте аукцион, затем нажмите, чтобы просканировать его на каждый свиток рецепта из видимого списка. Строки со свитками, выставленными на продажу, получают кнопку [АД]; нажмите её, чтобы перейти к поиску."
L["MissingNoCharacters"]        = "|cffaaaaaa(нет персонажей с данными профессий — откройте окно профессии)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(у этого персонажа пока нет отслеживаемых профессий — откройте окно профессии)|r"
L["MissingNoneFound"]           = "|cff00ff00Все известные рецепты этой профессии выучены.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Выберите профессию, чтобы увидеть, чего не хватает.|r"
L["MissingNoData"]              = "|cffff8888(нет данных о рецептах для этой профессии)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Рецепт"
L["MissingColSkill"]            = "Навык"
L["MissingColSource"]           = "Источники"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Отслеживать этот свиток рецепта"
L["MissingAddToWatchDesc"]      = "Добавляет свиток рецепта в список Отслеживания реагентов, чтобы вы увидели его сразу, как только он попадёт в сумки."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Уже отслеживается — нажмите, чтобы прекратить"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Недостающий рецепт"
L["MissingCountPlural"]         = "Недостающих рецептов"
L["MissingTruncatedHint"]       = "(показаны первые %d — введите текст в поле поиска, чтобы сузить список)"
L["MissingCharTooltipTitle"]    = "Фильтр по персонажу"
L["MissingCharTooltipDesc"]     = "Выберите, для какого из ваших персонажей показывать недостающие рецепты. По умолчанию — текущий персонаж."
L["MissingProfTooltipTitle"]    = "Фильтр по профессии"
L["MissingProfTooltipDesc"]     = "Выберите профессию, чтобы увидеть свитки, которые этот персонаж ещё не выучил."
L["MissingSearchTooltipTitle"]  = "Поиск рецептов"
L["MissingSearchTooltipDesc"]   = "Введите текст, чтобы отфильтровать список недостающих рецептов по имени."
L["MissingHdrCountTitle"]       = "Недостающие рецепты"
L["MissingHdrCountDesc"]        = "Рецепты, которые выбранный персонаж ещё не выучил, но которые доступны в этой версии игры. Число отражает текущий фильтр (профессия, поиск, переключатель учителя)."
L["MissingHdrSkillTitle"]       = "Уровень навыка"
L["MissingHdrSkillDesc"]        = "Требуемый уровень профессии для изучения этого рецепта. Затенённые строки означают, что у персонажа недостаточно навыка."
L["MissingHdrSourceTitle"]      = "Источники"
L["MissingHdrSourceDesc"]       = "Как получить этот рецепт — учитель, добыча, торговец, задание или ремесло. Наведите на текст источника в строке, чтобы увидеть конкретного NPC / монстра / шаг."
L["MissingRowTooltipShift"]     = "Shift-клик — вставить ссылку в чат."
L["MissingSrcVendor"]           = "Торговец"
L["MissingSrcDrop"]             = "Добыча"
L["MissingSrcQuest"]            = "Задание"
L["MissingSrcCrafted"]          = "Ремесло"
L["MissingSrcFishing"]          = "Рыбная ловля"
L["MissingSrcContainer"]        = "Контейнер"
L["MissingSrcTrainer"]          = "Учитель"
L["MissingSrcOther"]            = "Прочее"
L["MissingSrcUnknown"]          = "Неизвестно"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Подсказка предмета"
L["SettingsTooltipShowCrafters"]    = "Показывать ремесленников гильдии в подсказках предметов"
L["SettingsTooltipShowCraftersDesc"]= "Добавляет строку [TOGPM] со списком всех товарищей по гильдии, способных изготовить предмет, над которым вы навели курсор. Онлайн — белым, оффлайн — серым. Предметы, привязывающиеся при получении, пропускаются (их всё равно нельзя обменять)."
L["SettingsTooltipShowIds"]         = "Показывать ID предмета / заклинания в подсказках"
L["SettingsTooltipShowIdsDesc"]     = "Добавляет строку [TOGPM] с ID предмета и (если известен) ID заклинания рецепта. Особенно полезно для диагностики неправильных иконок или отсутствующих рецептов — вставьте ID в Wowhead, чтобы проверить соответствие."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Фаза TBC Anniversary"
L["SettingsTBCPhase"]           = "Текущая фаза контента"
L["SettingsTBCPhaseDesc"]       = "Скрывает Недостающие рецепты из фаз более поздних, чем текущая фаза Anniversary. Увеличивайте значение каждый раз, когда Blizzard продвигает фазу. (Рецепты, уже доступные на текущей фазе, остаются видимыми.)"
L["SettingsTBCPhase1"]          = "Фаза 1 — Каражан / Груул / Магтеридон"
L["SettingsTBCPhase2"]          = "Фаза 2 — Змеиное святилище / Крепость Бурь"
L["SettingsTBCPhase3"]          = "Фаза 3 — Чёрный храм / Хиджал"
L["SettingsTBCPhase4"]          = "Фаза 4 — Источник Солнца / Терраса Магистров"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Отображение"
L["SettingsMinimapBtn"]          = "Показывать кнопку на миникарте"
L["SettingsMinimapBtnDesc"]      = "Показывает или скрывает кнопку запуска на миникарте."
L["SettingsPersistProfFilter"]     = "Запоминать фильтр профессии"
L["SettingsPersistProfFilterDesc"] = "Восстанавливает выбранную профессию при входе или перезагрузке интерфейса."
L["SettingsCooldownsHeader"]= "Восстановления"
L["SettingsMailReadyOnly"]  = "Почта: только готовые восстановления"
L["SettingsMailReadyOnlyDesc"] = "При составлении письма с материалами из панели восстановлений показывать только тех членов гильдии, чьё восстановление готово."
L["SettingsDevHeader"]      = "Разработка"
L["SettingsDebug"]          = "Отладочный вывод"
L["SettingsDebugDesc"]      = "Выводит подробные отладочные сообщения в окно чата."
L["SettingsDataHeader"]     = "Данные"
L["SettingsSyncNow"]        = "Принудительная синхронизация"
L["SettingsSyncNowDesc"]    = "Немедленно отправляет ваши данные профессий гильдии."
L["SettingsPurgeGuild"]     = "Очистить все данные гильдии"
L["SettingsPurgeGuildDesc"] = "Удаляет все сохранённые данные профессий и восстановлений для каждого члена гильдии в этом аккаунте. Невозможно отменить."
L["SettingsPurgeGuildConfirm"] = "Удалить ВСЕ данные гильдии для этого аккаунта?"
L["SettingsPurgeMine"]      = "Очистить данные моего персонажа"
L["SettingsPurgeMineDesc"]  = "Удаляет только сохранённые данные вашего персонажа из базы данных гильдии."
L["SettingsPurgeMineConfirm"] = "Удалить ваши данные профессий и восстановлений?"
L["SettingsSyncLogHeader"]  = "Журнал синхронизации"
L["SettingsViewLog"]        = "Просмотр журнала синхронизации"
L["SettingsViewLogDesc"]    = "Открывает прокручиваемый список недавних событий синхронизации (последние 200)."
L["SettingsClearLog"]       = "Очистить журнал синхронизации"
L["SettingsClearLogConfirm"]= "Очистить все записи журнала синхронизации?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(модуль SyncLog не загружен)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(пока нет записанных событий синхронизации)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Кнопка миникарты скрыта. Используйте |cffda8cff/togpm minimap|r для восстановления."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Изготавливают:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Готово к изготовлению:|r %s × %d  (%s × %d в сумках)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Включить оповещение о ремесленнике для этого рецепта"
L["ShoppingAlertDisable"]              = "Отключить оповещение о ремесленнике для этого рецепта"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s в сети — может изготовить: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s в сети (альт %s) — может изготовить: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Включить оповещение о готовности для этого восстановления"
L["CooldownAlertDisable"]              = "Отключить оповещение о готовности для этого восстановления"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Восстановление готово: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Оповещения о ремесленниках"
L["SettingsCrafterAlert"]              = "Включить оповещения о ремесленниках"
L["SettingsCrafterAlertDesc"]          = "Проигрывает звук и заставляет экран мигать, когда член гильдии, способный изготовить отслеживаемый предмет из списка покупок, заходит в игру."
L["SettingsCrafterAlertSuppressAV"]    = "Подавлять звук и мигание"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Отключает звуковые эффекты и мигание экрана (сообщение в чате остаётся)."
L["SettingsCrafterAlertSuppressLogin"]     = "Подавлять оповещения при входе"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Не запускает оповещения во время начального всплеска уведомлений о входе при логине или перезагрузке интерфейса."
L["SettingsCooldownAlertSuppressProtected"]     = "Заглушать оповещения в подземельях"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Не подаёт звук и не выводит оповещения о готовности восстановлений, пока вы находитесь в рейде, подземелье, поле боя, арене или сценарии. Столицы НЕ заглушаются — ваше превращение всё равно пингует, пока вы стоите АФК в Штормграде. Отложенные оповещения сработают, как только вы покинете подземелье."
L["SettingsCooldownReminderInterval"]      = "Напоминание о готовности восстановления"
L["SettingsCooldownReminderIntervalDesc"]  = "Повторно запускает каждое включённое оповещение о восстановлении каждые N минут, пока восстановление остаётся готовым (то есть пока вы реально не изготовите). Введите 0, пусто или 'off', чтобы срабатывало только один раз за цикл готовности. Допустимый диапазон: 1–1440 минут (24 часа)."
L["SettingsCooldownReminderInvalid"]       = "Введите целое число от 0 до 1440 или 'off'."

L["SettingsAHHeader"]                      = "Аукцион"
L["SettingsAHScanDelay"]                   = "Задержка сканирования АД (секунды)"
L["SettingsAHScanDelayDesc"]               = "Секунды между запросами сканирования АД. Пусто / 0 / 'off' использует значение по умолчанию для версии (1.5с на Classic Era и Anniversary; 3.0с на TBC, Wrath, Cata, MoP — там серверы строже). Уменьшите для более быстрого сканирования, увеличьте, если сканирование зависает. Допустимый диапазон: 0.5–10 секунд."
L["SettingsAHScanDelayInvalid"]            = "Введите число от 0.5 до 10 или 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Рецепт"
L["TooltipRecipeDesc"]           = "Название изготавливаемого предмета или заклинания."
L["TooltipCraftersTitle"]        = "Ремесленники"
L["TooltipCraftersDesc"]         = "Члены гильдии, знающие этот рецепт. Нажмите рецепт для полного списка."
L["CraftersColHeader"]           = "Ремесленники"
L["TooltipBankTitle"]            = "Запросить из банка"
L["TooltipBankDescScroll"]       = "Отправляет запрос банкиру гильдии TOGBankClassic на этот свиток рецепта."
L["TooltipBankDescGeneric"]      = "Отправляет запрос банкиру гильдии TOGBankClassic."
L["TooltipAHTitle"]              = "Поиск на аукционе"
L["TooltipAHDescScroll"]         = "Открывает этот свиток рецепта в поиске АД."
L["TooltipAHDescReagent"]        = "Открывает этот реагент в поиске АД."
L["TooltipSettingsTitle"]        = "Настройки"
L["TooltipSettingsDesc"]         = "Открывает панель настроек TOG Profession Master (|cffffd700ESC > Настройки > Аддоны > TOG Profession Master|r). Та же цель, что и |cffffd700/togpm settings|r и Shift+левый щелчок по кнопке миникарты."
L["TooltipWhisperRightClick"]    = "Правый щелчок — шёпот"
L["TooltipClickTransmutes"]      = "Нажмите, чтобы увидеть превращения"
L["TooltipClickDetailsFormat"]   = "Нажмите, чтобы увидеть %s"
L["TooltipClickDetailsFallback"] = "подробности"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Материалы для восстановления: %s"
L["MailBodyFormat"]         = "Привет, %s! Используй эти материалы, чтобы сделать %s. Пришли мне %s, когда будет время на изготовление. Спасибо!"
L["MailMsgNoEmptyBag"]      = "Нет пустого слота сумки для разделения."
L["MailMsgOpenMailbox"]     = "Сначала откройте почтовый ящик."
L["MailMsgHasItems"]        = "К письму уже прикреплены предметы — отправьте или удалите их сначала."
L["MailMsgCannotFulfill"]   = "Невозможно выполнить."
L["MailMsgCouldNotAttach"]  = "Не удалось прикрепить предметы."
L["MailMsgAttachedFormat"]  = "Прикреплено %dx %s для %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Левый щелчок|r — открыть/закрыть обозреватель профессий"
L["MinimapTooltipRightClick"]  = "|cffffd100Правый щелчок|r — открыть/закрыть реагенты"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+левый|r — открыть настройки"
L["MinimapButtonShown"]        = "Кнопка миникарты показана."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- имена команд не переводятся
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — команды:"
L["SlashHelpOpen"]          = "открыть обозреватель профессий"
L["SlashHelpReagents"]      = "открыть недостающие реагенты"
L["SlashHelpMinimap"]       = "показать кнопку миникарты"
L["SlashHelpPurge"]         = "открыть диалог очистки"
L["SlashHelpSync"]          = "принудительная полная синхронизация гильдии"
L["SlashHelpStatus"]        = "вывести диагностику sync/comm"
L["SlashHelpVersionCheck"]  = "проверить версии аддона у гильдии"
L["SlashHelpDebug"]         = "переключить отладочный вывод"
L["SlashHelpHelp"]          = "показать этот список"
L["SlashForceSyncSent"]     = "Принудительная синхронизация отправлена."
L["AHScannerOpenAH"]        = "Откройте аукцион для поиска."
L["AHOpenFirst"]            = "Сначала откройте аукцион."
L["AHNoItemsToScan"]        = "В текущем виде нет предметов для сканирования."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Запрос из банка гильдии"
L["BankDialogBanker"]       = "Банкир:"
L["BankDialogQty"]          = "Кол-во:"
L["BankDialogSend"]         = "Отправить запрос"
L["BankDialogCancel"]       = "Отмена"

-- ---------------------------------------------------------------------------
-- Подтверждения очистки и прочий вывод команд
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Все данные гильдии очищены."
L["MsgOwnDataPurged"]        = "Данные вашего персонажа очищены."
L["SlashForceBroadcastSent"] = "Принудительная рассылка отправлена."
L["SlashDebugEnabled"]       = "|cff00ff00включён|r"
L["SlashDebugDisabled"]      = "|cffff4444отключён|r"
L["SlashDebugToggleFormat"]  = "Отладочный вывод %s"

-- ---------------------------------------------------------------------------
-- Названия профессий (официальный Blizzard ruRU, все 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Алхимия"
L["ProfBlacksmithing"]  = "Кузнечное дело"
L["ProfCooking"]        = "Кулинария"
L["ProfEnchanting"]     = "Наложение чар"
L["ProfEngineering"]    = "Инженерное дело"
L["ProfFirstAid"]       = "Первая помощь"
L["ProfLeatherworking"] = "Кожевничество"
L["ProfMining"]         = "Горное дело"
L["ProfTailoring"]      = "Портняжное дело"
L["ProfHerbalism"]      = "Травничество"
L["ProfSkinning"]       = "Снятие шкур"
L["ProfJewelcrafting"]  = "Ювелирное дело"
L["ProfInscription"]    = "Начертание"
L["ProfFishing"]        = "Рыбная ловля"
L["ProfSmelting"]       = "Плавка"

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
