-- TOG Profession Master -- Portuguese (Brazil) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("ptBR")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Registro de sincronização"

-- Tab labels
L["TabProfessions"]     = "Profissões"
L["TabCooldowns"]       = "Tempos de recarga"
L["TabReagents"]        = "Reagentes"
L["TabMissingRecipes"]  = "Receitas faltantes"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Buscar receitas…"
L["ViewGuild"]          = "Guilda"
L["ViewMine"]           = "Meus personagens"
L["AllProfessions"]     = "Todas as profissões"
L["PanelProfessions"]   = "Profissões"
L["PanelCharacters"]    = "Personagens"
L["SelectProfession"]   = "Selecione uma profissão"
L["NoDataYet"]          = "|cffaaaaaa(ainda sem dados)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Selecione uma profissão para ver quem a conhece.|r"
L["NoProfMembers"]      = "|cffaaaaaa(nenhum membro da guilda com esta profissão)|r"
L["BackToCharacters"]   = "|cff00aaff← Voltar aos personagens|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(nenhuma receita correspondente)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Você"
L["BrowserScanAH"]          = "Escanear LE"
L["BrowserScanAHProgress"]  = "Escaneando %d/%d"
L["BrowserScanAHDesc"]      = "Escaneia a casa de leilões em busca de cada reagente da sua lista de compras. Linhas cujos reagentes estão atualmente na LE recebem um botão [LE]; clique para saltar direto à busca no leilão."
L["CooldownsScanAHDesc"]    = "Escaneia a casa de leilões em busca de cada reagente único nas linhas de recarga visíveis. Linhas cujos reagentes estão na LE recebem um botão [LE] (à esquerda de [Banco]); clique para saltar à busca."

-- Skill-tier filter (Browser toolbar)
L["BrowserSkillTier"]      = "N\195\173vel de per\195\173cia"
L["BrowserSkillTierTip"]   = "Filtro de n\195\173vel de per\195\173cia"
L["BrowserSkillTierDesc"]  = "Mostra apenas as receitas dos n\195\173veis de per\195\173cia marcados. Desmarque n\195\173veis inferiores para ocultar suas receitas da lista. Marque v\195\161rios n\195\173veis; o menu permanece aberto. Use Selecionar tudo / Limpar tudo na parte inferior. Receitas sem n\195\173vel de habilidade conhecido permanecem sempre vis\195\173veis."
L["FilterSelectAll"]       = "Selecionar tudo"
L["FilterClearAll"]        = "Limpar tudo"
L["TierApprentice"]        = "Aprendiz"
L["TierJourneyman"]        = "Oficial"
L["TierExpert"]            = "Perito"
L["TierArtisan"]           = "Artes\195\163o"
L["TierMaster"]            = "Mestre"
L["TierGrandMaster"]       = "Gr\195\163o-Mestre"
L["TierIllustrious"]       = "Ilustre"
L["TierZenMaster"]         = "Mestre Zen"

-- Guild tab
L["TabGuild"]               = "Guilda"
L["GuildTabChars"]          = "%d personagens rastreados"
L["GuildColProfession"]     = "Profiss\195\163o"
L["GuildColProfessionDesc"] = "Cada profiss\195\163o e quantos personagens da guilda a possuem. As sublinhas a detalham por especializa\195\167\195\163o quando alguma \195\169 conhecida."
L["GuildColCount"]          = "Personagens"
L["GuildColCountDesc"]      = "N\195\186mero de personagens da guilda com a profiss\195\163o (ou especializa\195\167\195\163o). Contado a partir das habilidades sincronizadas mais todos que se sabe que fabricam suas receitas."
L["GuildUnspecialized"]     = "Sem especializa\195\167\195\163o"
L["GuildTabEmpty"]          = "Ainda sem dados de profiss\195\163o. Preenche-se \195\160 medida que os companheiros de guilda que usam o addon sincronizam suas habilidades."

-- Recipe detail popup
L["PopupCrafters"]       = "Conhecida por"
L["PopupOnList"]         = "Na lista de compras"
L["PopupNotOnList"]      = "Não está na lista"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Só prontos"
L["ShowAll"]                = "Todos"
L["FilterColProfession"]    = "Profissão"
L["FilterColCooldown"]      = "Recarga"
L["FilterColView"]          = "Visão"
L["FilterProfessionDesc"]   = "Filtra a lista de recargas por uma única profissão (Alquimia, Alfaiataria, etc.)."
L["FilterCooldownDesc"]     = "Dentro da profissão selecionada, filtra por uma única recarga compartilhada (ex.: Transmutação, Tecido Lunar)."
L["FilterViewDesc"]         = "Alterna entre as recargas de todos os membros da guilda e apenas seus personagens."
L["AllCooldowns"]           = "Todas as recargas"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Transmutação"
L["FilterAlchResearch"]         = "Pesquisa de Alquimia"
L["FilterMooncloth"]            = "Tecido Lunar"
L["FilterSpecialtyCloth"]       = "Tecido Especial"
L["FilterGlacialBag"]           = "Bolsa Glacial"
L["FilterDreamcloth"]           = "Tecido Onírico"
L["FilterImperialSilk"]         = "Seda Imperial"
L["FilterSaltShaker"]           = "Saleiro"
L["FilterMagicSphere"]          = "Esfera Mágica"
L["FilterShaCrystal"]           = "Cristal Sha"
L["FilterBrilliantGlass"]       = "Vidro Brilhante"
L["FilterIcyPrism"]             = "Prisma Gélido"
L["FilterFirePrism"]            = "Prisma de Fogo"
L["FilterJcDaily"]              = "Corte Diário de Joalharia"
L["FilterInscriptionResearch"]  = "Pesquisa de Escrituração"
L["FilterForgedDocuments"]      = "Documentos Falsificados"
L["FilterScrollOfWisdom"]       = "Pergaminho da Sabedoria"
L["FilterTitansteelBar"]        = "Barra de Aço Titânico"
L["FilterBsIngot"]              = "Fundição"
L["FilterMagnificence"]         = "Magnificência"
L["FilterJards"]                = "Energia de Jard"
L["ColCharacter"]           = "Personagem"
L["ColCooldown"]            = "Recarga"
L["ColReagent"]             = "Reagente"
L["ColTimeLeft"]            = "Tempo restante"
L["NoCooldownData"]         = "|cffaaaaaa(ainda sem dados de recarga — abra uma janela de profissão)|r"
L["Ready"]                  = "|cff00ff00Pronto|r"
L["Transmute"]              = "Transmutação"
L["MailBtn"]                = "Correio"
L["MailBtnTooltip"]         = "Enviar correio de suprimentos"
L["MailBtnTooltipDesc"]     = "Abra uma caixa de correio, depois clique para anexar reagentes e compor um correio de suprimentos para este jogador."
L["BankBtn"]                = "[Banco]"
L["CloseBtn"]               = "Fechar"

-- Indicador de bônus de especialização de profissão
L["SpecBonusGuaranteedDouble"]  = "Produção 2x garantida"
L["SpecBonusProcChance"]        = "Chance de produção extra"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Lista de compras"
L["SectionMissingReagents"] = "Reagentes faltantes"
L["SectionReagentWatch"]    = "Vigilância de reagentes"
L["ShoppingListEmpty"]      = "|cffaaaaaa(vazia — clique em uma linha de receita na aba Profissões para adicionar itens à lista de compras)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(a lista de compras está vazia ou todos os reagentes estão nas mochilas)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(nenhum item vigiado — digite um ID de item ou link acima)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(módulo ReagentWatch não carregado)|r"
L["WatchInputLabel"]        = "ID de item ou link"
L["WatchBtn"]               = "Vigiar"
L["WatchedItemsHeading"]    = "Itens vigiados"
L["ColHave"]                = "Possui"
L["ColNeed"]                = "Precisa"
L["ColShort"]               = "Falta"
L["ColItem"]                = "Item"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personagem|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Profissão|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Buscar receitas…|r"
L["MissingIncludeTrainer"]      = "Incluir apenas de treinador"
L["MissingIncludeTrainerDesc"]  = "Inclui receitas que só podem ser aprendidas com um treinador (sem pergaminho na LE)."
L["MissingScanAH"]              = "Escanear LE"
L["MissingScanAHProgress"]      = "Escaneando %d/%d (clique para cancelar)"
L["MissingScanAHDesc"]          = "Abra a casa de leilões, depois clique para escaneá-la em busca de cada pergaminho de receita da lista visível. Linhas com leilões ativos recebem um botão [LE]; clique para saltar à busca."
L["MissingNoCharacters"]        = "|cffaaaaaa(ainda sem personagens com dados de profissão — abra uma janela de profissão)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(este personagem ainda não tem profissões registradas — abra uma janela de profissão)|r"
L["MissingNoneFound"]           = "|cff00ff00Todas as receitas conhecidas desta profissão foram aprendidas.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Escolha uma profissão para ver o que falta.|r"
L["MissingNoData"]              = "|cffff8888(sem dados de receita disponíveis para esta profissão)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Receita"
L["MissingColSkill"]            = "Habilidade"
L["MissingColSource"]           = "Fontes"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Vigiar este pergaminho de receita"
L["MissingAddToWatchDesc"]      = "Adiciona o pergaminho de receita à sua lista de Vigilância de reagentes para vê-lo assim que cair nas suas mochilas."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Já em Vigilância — clique para parar de vigiar"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Receita faltante"
L["MissingCountPlural"]         = "Receitas faltantes"
L["MissingTruncatedHint"]       = "(mostrando as primeiras %d — digite na caixa de busca para reduzir a lista)"
L["MissingCharTooltipTitle"]    = "Filtro de personagem"
L["MissingCharTooltipDesc"]     = "Escolha para qual dos seus personagens ver as receitas faltantes. Por padrão, o personagem atualmente conectado."
L["MissingProfTooltipTitle"]    = "Filtro de profissão"
L["MissingProfTooltipDesc"]     = "Escolha uma profissão para ver os pergaminhos que este personagem ainda não aprendeu."
L["MissingSearchTooltipTitle"]  = "Buscar receitas"
L["MissingSearchTooltipDesc"]   = "Digite para filtrar por nome a lista de receitas faltantes."
L["MissingHdrCountTitle"]       = "Receitas faltantes"
L["MissingHdrCountDesc"]        = "Receitas que o personagem selecionado ainda não aprendeu mas que podem ser obtidas nesta versão do jogo. O número reflete o filtro atual (profissão, busca, interruptor de treinador)."
L["MissingHdrSkillTitle"]       = "Nível de habilidade"
L["MissingHdrSkillDesc"]        = "O nível de habilidade da profissão necessário para aprender esta receita. Linhas em cinza indicam que o personagem ainda não tem nível suficiente."
L["MissingHdrSourceTitle"]      = "Fontes"
L["MissingHdrSourceDesc"]       = "Como obter esta receita — treinador, drop, vendedor, missão ou fabricada. Passe o mouse sobre o texto de fonte de uma linha para ver o NPC / criatura / passo específico."
L["MissingRowTooltipShift"]     = "Shift-clique para vincular no chat."
L["MissingSrcVendor"]           = "Vendedor"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Missão"
L["MissingSrcCrafted"]          = "Fabricada"
L["MissingSrcFishing"]          = "Pesca"
L["MissingSrcContainer"]        = "Contêiner"
L["MissingSrcTrainer"]          = "Treinador"
L["MissingSrcOther"]            = "Outros"
L["MissingSrcUnknown"]          = "Desconhecida"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Dica de item"
L["SettingsTooltipShowCrafters"]    = "Mostrar artesãos da guilda nas dicas de itens"
L["SettingsTooltipShowCraftersDesc"]= "Adiciona uma linha [TOGPM] listando cada companheiro de guilda que pode fabricar o item sob o cursor. Online em branco, offline em cinza. Itens vinculados ao pegar são ignorados (não negociáveis de qualquer forma)."
L["SettingsTooltipShowIds"]         = "Mostrar ID de item / ID de feitiço nas dicas"
L["SettingsTooltipShowIdsDesc"]     = "Adiciona uma linha [TOGPM] com o ID de item e (se conhecido) o ID de feitiço da receita. Útil principalmente para diagnosticar ícones errados ou receitas faltantes — cole os IDs no Wowhead para verificar a correspondência."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Fase de TBC Anniversary"
L["SettingsTBCPhase"]           = "Fase de conteúdo atual"
L["SettingsTBCPhaseDesc"]       = "Oculta as Receitas faltantes vindas de fases posteriores à fase atual de Anniversary. Aumente o valor cada vez que a Blizzard avançar a fase. (Receitas já acessíveis na fase ativa permanecem visíveis.)"
L["SettingsTBCPhase1"]          = "Fase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Fase 2 — Caverna do Santuário da Serpente / Fortaleza Tempestade"
L["SettingsTBCPhase3"]          = "Fase 3 — Templo Negro / Monte Hyjal"
L["SettingsTBCPhase4"]          = "Fase 4 — Poço do Sol / Terraço dos Magistros"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Exibição"
L["SettingsMinimapBtn"]          = "Mostrar botão do minimapa"
L["SettingsMinimapBtnDesc"]      = "Mostra ou oculta o botão de inicialização no minimapa."
L["SettingsPersistProfFilter"]     = "Lembrar filtro de profissão"
L["SettingsPersistProfFilterDesc"] = "Restaura a profissão selecionada ao entrar ou recarregar."
L["SettingsSyncHeader"]     = "Sincronização"
L["SettingsGuildMode"]      = "Modo de sincronização apenas por guilda (servidores privados)"
L["SettingsGuildModeDesc"]  = "Para servidores privados ou emulados (ex.: Whitemane) que não entregam mensagens de addon por sussurros, o que impede os membros da guilda de receberem os dados de profissão uns dos outros. Quando LIGADO, todo o tráfego de sincronização é roteado pelo canal da guilda. Ative isto apenas se a sincronização de guilda não estiver funcionando no seu servidor. |cffffd100Todos na guilda devem ativá-lo|r — só funciona entre membros que estejam ambos com ele ativado. O compartilhamento entre guildas é desativado automaticamente enquanto isto estiver ligado. Aplica-se a todos os personagens deste reino. (Oculto se a sua versão instalada do DeltaSync não tiver suporte.)"
L["SettingsCooldownsHeader"]= "Recargas"
L["SettingsMailReadyOnly"]  = "Correio: mostrar apenas recargas prontas"
L["SettingsMailReadyOnlyDesc"] = "Ao compor correio de suprimentos no painel de recargas, lista apenas membros cuja recarga esteja pronta."
L["SettingsDevHeader"]      = "Desenvolvedor"
L["SettingsDebug"]          = "Saída de depuração"
L["SettingsDebugDesc"]      = "Imprime mensagens detalhadas de depuração no chat."
L["SettingsDataHeader"]     = "Dados"
L["SettingsSyncNow"]        = "Forçar ressincronização"
L["SettingsSyncNowDesc"]    = "Transmite imediatamente seus dados de profissão para a guilda."
L["SettingsPurgeGuild"]     = "Limpar todos os dados de guilda"
L["SettingsPurgeGuildDesc"] = "Remove todos os dados de profissão e recarga armazenados para cada membro da guilda nesta conta. Não pode ser desfeito."
L["SettingsPurgeGuildConfirm"] = "Excluir TODOS os dados de guilda desta conta?"
L["SettingsPurgeMine"]      = "Limpar dados do meu personagem"
L["SettingsPurgeMineDesc"]  = "Remove apenas os dados armazenados do seu personagem do banco de dados da guilda."
L["SettingsPurgeMineConfirm"] = "Excluir seus dados de profissão e recarga?"
L["SettingsSyncLogHeader"]  = "Registro de sincronização"
L["SettingsViewLog"]        = "Ver registro de sincronização"
L["SettingsViewLogDesc"]    = "Abre uma lista rolável de eventos recentes de sincronização (últimos 200)."
L["SettingsClearLog"]       = "Limpar registro de sincronização"
L["SettingsClearLogConfirm"]= "Limpar todas as entradas do registro de sincronização?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(módulo SyncLog não carregado)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(ainda sem eventos de sincronização registrados)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Botão do minimapa oculto. Use |cffda8cff/togpm minimap|r para restaurar."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Fabricado por:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Pronto para fabricar:|r %s × %d  (%s × %d nas mochilas)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Ativar alerta de artesão para esta receita"
L["ShoppingAlertDisable"]              = "Desativar alerta de artesão para esta receita"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s está online — pode fabricar: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s está online (alt de %s) — pode fabricar: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Ativar alerta de pronto para esta recarga"
L["CooldownAlertDisable"]              = "Desativar alerta de pronto para esta recarga"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Recarga pronta: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Alertas de artesão"
L["SettingsCrafterAlert"]              = "Ativar alertas de artesão"
L["SettingsCrafterAlertDesc"]          = "Toca um som e faz a tela piscar quando um membro da guilda que pode fabricar um item da lista de compras com alerta entra online."
L["SettingsCrafterAlertSuppressAudio"]     = "Suprimir som do alerta"
L["SettingsCrafterAlertSuppressAudioDesc"] = "Desativa o som quando um artesão fica online (o flash da tela e a mensagem no chat continuam aparecendo)."
L["SettingsCrafterAlertSuppressVisual"]    = "Suprimir alerta visual"
L["SettingsCrafterAlertSuppressVisualDesc"] = "Desativa o alerta visual na tela (flash da tela, banner, etc.) quando um artesão fica online (o som e a mensagem no chat continuam aparecendo)."
L["AlertCrafterOnlineBanner"]              = "Artesão da guilda online"
L["SettingsCrafterAlertSound"]             = "Som do alerta"
L["SettingsCrafterAlertSoundDesc"]         = "Qual som toca quando um artesão que você pode alcançar fica online. Selecionar um faz uma prévia. Não tem efeito enquanto o som do alerta estiver suprimido acima."
L["SettingsCrafterAlertVisual"]            = "Efeito visual do alerta"
L["SettingsCrafterAlertVisualDesc"]        = "Qual efeito na tela dispara quando um artesão fica online — um flash em tela cheia na cor que você escolher, ou um piscar na barra de tarefas para quando você estiver em outra janela. Selecionar um faz uma prévia. Não tem efeito enquanto o flash da tela estiver suprimido acima."
L["SettingsCrafterAlertSuppressLogin"]     = "Suprimir alertas no login"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Não disparar alertas durante a rajada inicial de notificações de conexão no login ou recarga da UI."
L["SettingsCooldownAlertSuppressProtected"]     = "Silenciar alertas em instâncias"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Não emite nem imprime alertas de recarga pronta enquanto você estiver em uma raide, masmorra, campo de batalha, arena ou cenário. As capitais NÃO são silenciadas — sua transmutação continuará pingando enquanto você estiver AFK em Stormwind. Alertas pendentes disparam assim que você sair da instância."
L["SettingsCooldownReminderInterval"]      = "Lembrete de recarga pronta"
L["SettingsCooldownReminderIntervalDesc"]  = "Redispara cada alerta de recarga armado a cada N minutos enquanto a recarga continuar pronta (ou seja, até você realmente fabricar). Digite 0, vazio ou 'off' para disparar apenas uma vez por ciclo de pronto. Faixa válida: 1–1440 minutos (24 horas)."
L["SettingsCooldownReminderInvalid"]       = "Digite um número inteiro de 0 a 1440, ou 'off'."

L["SettingsAHHeader"]                      = "Casa de leilões"
L["SettingsAHScanDelay"]                   = "Atraso de escaneamento da LE (segundos)"
L["SettingsAHScanDelayDesc"]               = "Segundos entre requisições de escaneamento da LE. Vazio / 0 / 'off' usa o valor padrão da versão (1.5s em Classic Era e Anniversary; 3.0s em TBC, Wrath, Cata, MoP — esses servidores limitam mais). Diminua o valor para escaneamentos mais rápidos, aumente se travarem. Faixa válida: 0.5–10 segundos."
L["SettingsAHScanDelayInvalid"]            = "Digite um número de 0.5 a 10, ou 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Receita"
L["TooltipRecipeDesc"]           = "O nome do item fabricável ou do feitiço."
L["TooltipCraftersTitle"]        = "Artesãos"
L["TooltipCraftersDesc"]         = "Membros da guilda que conhecem esta receita. Clique em uma receita para ver a lista completa."
L["CraftersColHeader"]           = "Artesãos"
L["TooltipBankTitle"]            = "Solicitar do banco"
L["TooltipBankDescScroll"]       = "Envia uma solicitação a um banqueiro da guilda TOGBankClassic para este pergaminho de receita."
L["TooltipBankDescGeneric"]      = "Envia uma solicitação a um banqueiro da guilda TOGBankClassic."
L["TooltipAHTitle"]              = "Buscar na casa de leilões"
L["TooltipAHDescScroll"]         = "Abre este pergaminho de receita na busca da LE."
L["TooltipAHDescReagent"]        = "Abre este reagente na busca da LE."
L["TooltipSettingsTitle"]        = "Configurações"
L["TooltipSettingsDesc"]         = "Abre o painel de configurações do TOG Profession Master (|cffffd700ESC > Opções > AddOns > TOG Profession Master|r). Mesmo destino de |cffffd700/togpm settings|r e Shift+clique esquerdo no botão do minimapa."
L["TooltipWhisperRightClick"]    = "Clique direito para sussurrar"
L["TooltipClickTransmutes"]      = "Clique para ver as transmutações"
L["TooltipClickDetailsFormat"]   = "Clique para ver %s"
L["TooltipClickDetailsFallback"] = "detalhes"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Suprimentos de recarga: %s"
L["MailBodyFormat"]         = "Olá %s! Use estes materiais para fazer %s. Mande-me o %s quando tiver tempo de fabricar. Obrigado!"
L["MailMsgNoEmptyBag"]      = "Sem espaço vazio na mochila para dividir."
L["MailMsgOpenMailbox"]     = "Abra uma caixa de correio primeiro."
L["MailMsgHasItems"]        = "O correio já tem itens anexados — envie ou remova-os primeiro."
L["MailMsgCannotFulfill"]   = "Não é possível completar."
L["MailMsgCouldNotAttach"]  = "Não foi possível anexar os itens."
L["MailMsgAttachedFormat"]  = "Anexados %dx %s para %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Clique esquerdo|r para mostrar/ocultar o navegador de profissões"
L["MinimapTooltipRightClick"]  = "|cffffd100Clique direito|r para mostrar/ocultar reagentes"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+esquerdo|r abre as configurações"
L["MinimapButtonShown"]        = "Botão do minimapa mostrado."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- nomes dos comandos não são traduzidos
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — comandos:"
L["SlashHelpOpen"]          = "abre o navegador de profissões"
L["SlashHelpReagents"]      = "abre os reagentes faltantes"
L["SlashHelpMinimap"]       = "mostrar botão do minimapa"
L["SlashHelpPurge"]         = "abre o diálogo de limpeza"
L["SlashHelpSync"]          = "força uma ressincronização completa da guilda"
L["SlashHelpStatus"]        = "imprime informações de diagnóstico sync/comm"
L["SlashHelpVersionCheck"]  = "verifica versões do addon na guilda"
L["SlashHelpDebug"]         = "alterna saída de depuração"
L["SlashHelpHelp"]          = "mostra esta lista"
L["SlashForceSyncSent"]     = "Sincronização forçada enviada."
L["AHScannerOpenAH"]        = "Abra a casa de leilões para buscar."
L["AHOpenFirst"]            = "Abra a casa de leilões primeiro."
L["AHNoItemsToScan"]        = "Sem itens para escanear na visão atual."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Solicitação ao banco da guilda"
L["BankDialogBanker"]       = "Banqueiro:"
L["BankDialogQty"]          = "Qtd:"
L["BankDialogSend"]         = "Enviar solicitação"
L["BankDialogCancel"]       = "Cancelar"

-- ---------------------------------------------------------------------------
-- Confirmações de limpeza e outras saídas de comandos
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Todos os dados da guilda removidos."
L["MsgOwnDataPurged"]        = "Dados do seu personagem removidos."
L["SlashForceBroadcastSent"] = "Transmissão forçada enviada."
L["SlashDebugEnabled"]       = "|cff00ff00ativada|r"
L["SlashDebugDisabled"]      = "|cffff4444desativada|r"
L["SlashDebugToggleFormat"]  = "Saída de depuração %s"

-- ---------------------------------------------------------------------------
-- Nomes das profissões (oficial Blizzard ptBR, todas 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alquimia"
L["ProfBlacksmithing"]  = "Ferraria"
L["ProfCooking"]        = "Culinária"
L["ProfEnchanting"]     = "Encantamento"
L["ProfEngineering"]    = "Engenharia"
L["ProfFirstAid"]       = "Primeiros Socorros"
L["ProfLeatherworking"] = "Couraria"
L["ProfMining"]         = "Mineração"
L["ProfTailoring"]      = "Alfaiataria"
L["ProfHerbalism"]      = "Herborismo"
L["ProfSkinning"]       = "Esfolamento"
L["ProfJewelcrafting"]  = "Joalheria"
L["ProfInscription"]    = "Escrituração"
L["ProfFishing"]        = "Pesca"
L["ProfSmelting"]       = "Fundição"

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
