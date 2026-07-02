-- TOG Profession Master -- Spanish (Spain) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.
-- esMX (Mexican Spanish) lives in its own file with identical content;
-- divergence can be introduced later if any string needs LATAM phrasing.

local _, addon = ...
local L = addon.NewLocale("esES")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Registro de sincronización"

-- Tab labels
L["TabProfessions"]     = "Profesiones"
L["TabCooldowns"]       = "Reutilizaciones"
L["TabReagents"]        = "Componentes"
L["TabMissingRecipes"]  = "Recetas faltantes"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Buscar recetas…"
L["ViewGuild"]          = "Hermandad"
L["ViewMine"]           = "Mis personajes"
L["AllProfessions"]     = "Todas las profesiones"
L["PanelProfessions"]   = "Profesiones"
L["PanelCharacters"]    = "Personajes"
L["SelectProfession"]   = "Selecciona una profesión"
L["NoDataYet"]          = "|cffaaaaaa(aún no hay datos)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Selecciona una profesión para ver quién la conoce.|r"
L["NoProfMembers"]      = "|cffaaaaaa(ningún miembro de la hermandad con esta profesión)|r"
L["BackToCharacters"]   = "|cff00aaff← Volver a los personajes|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(no hay recetas coincidentes)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Tú"
L["BrowserScanAH"]          = "Escanear SU"
L["BrowserScanAHProgress"]  = "Escaneando %d/%d"
L["BrowserScanAHDesc"]      = "Escanea la subasta en busca de cada componente de tu lista de compras. Las filas cuyos componentes estén actualmente en la SU reciben un botón [SU]; pulsa ese botón para saltar directamente a la búsqueda en la subasta."
L["CooldownsScanAHDesc"]    = "Escanea la subasta en busca de cada componente único en las filas de reutilizaciones visibles. Las filas cuyo componente esté actualmente en la SU reciben un botón [SU] (a la izquierda de [Banco]); pulsa ese botón para saltar a la búsqueda."

-- Skill-tier filter (Browser toolbar)
L["BrowserSkillTier"]       = "Nivel de aptitud"
L["BrowserSkillTierTip"]    = "Filtro de nivel de aptitud"
L["BrowserSkillTierDesc"]   = "Muestra solo las recetas de los niveles de aptitud marcados. Desmarca los niveles inferiores para ocultar sus recetas de la lista. Marca varios niveles; el men\195\186 permanece abierto. Usa Seleccionar todo / Vaciar todo en la parte inferior. Las recetas sin nivel de aptitud conocido siempre permanecen visibles."
L["FilterSelectAll"]        = "Seleccionar todo"
L["FilterClearAll"]         = "Vaciar todo"
L["TierApprentice"]         = "Aprendiz"
L["TierJourneyman"]         = "Oficial"
L["TierExpert"]             = "Experto"
L["TierArtisan"]            = "Artesano"
L["TierMaster"]             = "Maestro"
L["TierGrandMaster"]        = "Gran maestro"
L["TierIllustrious"]        = "Ilustre"
L["TierZenMaster"]          = "Maestro zen"

-- Guild tab
L["TabGuild"]               = "Hermandad"
L["GuildTabChars"]          = "%d personajes registrados"
L["GuildColProfession"]     = "Profesi\195\179n"
L["GuildColProfessionDesc"] = "Cada profesi\195\179n y cu\195\161ntos personajes de la hermandad la tienen. Las subfilas la desglosan por especializaci\195\179n cuando se conoce alguna."
L["GuildColCount"]          = "Personajes"
L["GuildColCountDesc"]      = "N\195\186mero de personajes de la hermandad con la profesi\195\179n (o especializaci\195\179n). Se cuenta a partir de las aptitudes sincronizadas m\195\161s todos los que se sabe que fabrican sus recetas."
L["GuildUnspecialized"]     = "Sin especializaci\195\179n"
L["GuildTabEmpty"]          = "A\195\186n no hay datos de profesiones. Se van rellenando a medida que los miembros de la hermandad que usan el addon sincronizan sus aptitudes."

-- Recipe detail popup
L["PopupCrafters"]       = "Conocida por"
L["PopupOnList"]         = "En la lista de compras"
L["PopupNotOnList"]      = "No está en la lista"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Sólo listas"
L["ShowAll"]                = "Todas"
L["FilterColProfession"]    = "Profesión"
L["FilterColCooldown"]      = "Reutilización"
L["FilterColView"]          = "Vista"
L["FilterProfessionDesc"]   = "Filtra la lista de reutilizaciones por una sola profesión (Alquimia, Sastrería, etc.)."
L["FilterCooldownDesc"]     = "Dentro de la profesión seleccionada, filtra por una sola reutilización compartida (p. ej. Transmutación, Tela lunar)."
L["FilterViewDesc"]         = "Alterna entre las reutilizaciones de todos los miembros de la hermandad y solo las de tus personajes."
L["AllCooldowns"]           = "Todas las reutilizaciones"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Transmutación"
L["FilterAlchResearch"]         = "Investigación de Alquimia"
L["FilterMooncloth"]            = "Tela lunar"
L["FilterSpecialtyCloth"]       = "Tela especial"
L["FilterGlacialBag"]           = "Bolsa glacial"
L["FilterDreamcloth"]           = "Tela onírica"
L["FilterImperialSilk"]         = "Seda imperial"
L["FilterSaltShaker"]           = "Salero"
L["FilterMagicSphere"]          = "Esfera mágica"
L["FilterShaCrystal"]           = "Cristal de Sha"
L["FilterBrilliantGlass"]       = "Cristal brillante"
L["FilterIcyPrism"]             = "Prisma helado"
L["FilterFirePrism"]            = "Prisma de fuego"
L["FilterJcDaily"]              = "Corte diario de Joyería"
L["FilterInscriptionResearch"]  = "Investigación de Inscripción"
L["FilterForgedDocuments"]      = "Documentos falsificados"
L["FilterScrollOfWisdom"]       = "Pergamino de sabiduría"
L["FilterTitansteelBar"]        = "Barra de acero de titán"
L["FilterBsIngot"]              = "Fundición"
L["FilterMagnificence"]         = "Magnificencia"
L["FilterJards"]                = "Energía de Jard"
L["ColCharacter"]           = "Personaje"
L["ColCooldown"]            = "Reutilización"
L["ColReagent"]             = "Componente"
L["ColTimeLeft"]            = "Tiempo restante"
L["NoCooldownData"]         = "|cffaaaaaa(aún no hay datos de reutilización — abre una ventana de profesión)|r"
L["Ready"]                  = "|cff00ff00Lista|r"
L["Transmute"]              = "Transmutación"
L["MailBtn"]                = "Correo"
L["MailBtnTooltip"]         = "Enviar correo de suministros"
L["MailBtnTooltipDesc"]     = "Abre un buzón y luego pulsa para adjuntar componentes y redactar un correo de suministros a este jugador."
L["BankBtn"]                = "[Banco]"
L["CloseBtn"]               = "Cerrar"

-- Indicador de bonificación de especialización de profesión
L["SpecBonusGuaranteedDouble"]  = "Producción 2x garantizada"
L["SpecBonusProcChance"]        = "Probabilidad de producción extra"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Lista de compras"
L["SectionMissingReagents"] = "Componentes faltantes"
L["SectionReagentWatch"]    = "Vigilancia de componentes"
L["ShoppingListEmpty"]      = "|cffaaaaaa(vacía — pulsa una fila de receta en la pestaña Profesiones para añadir objetos a tu lista de compras)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(la lista de compras está vacía o todos los componentes están en las bolsas)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(no se vigila ningún objeto — introduce un ID de objeto o enlace arriba)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(módulo ReagentWatch no cargado)|r"
L["WatchInputLabel"]        = "ID de objeto o enlace"
L["WatchBtn"]               = "Vigilar"
L["WatchedItemsHeading"]    = "Objetos vigilados"
L["ColHave"]                = "Tienes"
L["ColNeed"]                = "Necesita"
L["ColShort"]               = "Falta"
L["ColItem"]                = "Objeto"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personaje|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Profesión|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Buscar recetas…|r"
L["MissingIncludeTrainer"]      = "Incluir sólo de entrenador"
L["MissingIncludeTrainerDesc"]  = "Incluye recetas que solo pueden aprenderse de un entrenador (sin pergamino en la SU)."
L["MissingScanAH"]              = "Escanear SU"
L["MissingScanAHProgress"]      = "Escaneando %d/%d (pulsa para cancelar)"
L["MissingScanAHDesc"]          = "Abre la subasta y luego pulsa para escanearla en busca de cada pergamino de receta de la lista visible. Las filas con subastas activas reciben un botón [SU]; pulsa ese botón para saltar a la búsqueda."
L["MissingNoCharacters"]        = "|cffaaaaaa(aún no hay personajes con datos de profesión — abre una ventana de profesión)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(este personaje aún no tiene profesiones registradas — abre una ventana de profesión)|r"
L["MissingNoneFound"]           = "|cff00ff00Se han aprendido todas las recetas conocidas de esta profesión.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Elige una profesión para ver qué falta.|r"
L["MissingNoData"]              = "|cffff8888(no hay datos de recetas disponibles para esta profesión)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Receta"
L["MissingColSkill"]            = "Aptitud"
L["MissingColSource"]           = "Fuentes"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Vigilar este pergamino de receta"
L["MissingAddToWatchDesc"]      = "Añade el pergamino de receta a tu lista de Vigilancia de componentes para verlo en cuanto caiga en tus bolsas."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Ya en Vigilancia — pulsa para dejar de vigilar"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Receta faltante"
L["MissingCountPlural"]         = "Recetas faltantes"
L["MissingTruncatedHint"]       = "(mostrando las primeras %d — escribe en el cuadro de búsqueda para reducir la lista)"
L["MissingCharTooltipTitle"]    = "Filtro de personaje"
L["MissingCharTooltipDesc"]     = "Elige para cuál de tus personajes ver las recetas faltantes. Por defecto, el personaje con sesión iniciada."
L["MissingProfTooltipTitle"]    = "Filtro de profesión"
L["MissingProfTooltipDesc"]     = "Elige una profesión para ver los pergaminos que este personaje todavía no ha aprendido."
L["MissingSearchTooltipTitle"]  = "Buscar recetas"
L["MissingSearchTooltipDesc"]   = "Escribe para filtrar por nombre la lista de recetas faltantes."
L["MissingHdrCountTitle"]       = "Recetas faltantes"
L["MissingHdrCountDesc"]        = "Recetas que el personaje seleccionado aún no ha aprendido pero que se pueden obtener en esta versión del juego. El número refleja el filtro actual (profesión, búsqueda, conmutador de entrenador)."
L["MissingHdrSkillTitle"]       = "Nivel de aptitud"
L["MissingHdrSkillDesc"]        = "El nivel de aptitud de profesión necesario para aprender esta receta. Las filas en gris indican que el personaje aún no tiene el nivel suficiente."
L["MissingHdrSourceTitle"]      = "Fuentes"
L["MissingHdrSourceDesc"]       = "Cómo obtener esta receta — entrenador, botín, vendedor, misión o fabricada. Pasa el ratón sobre el texto de fuente de una fila para ver el PNJ / criatura / paso concreto."
L["MissingRowTooltipShift"]     = "Mayús-clic para enlazar en el chat."
L["MissingSrcVendor"]           = "Vendedor"
L["MissingSrcDrop"]             = "Botín"
L["MissingSrcQuest"]            = "Misión"
L["MissingSrcCrafted"]          = "Fabricada"
L["MissingSrcFishing"]          = "Pesca"
L["MissingSrcContainer"]        = "Contenedor"
L["MissingSrcTrainer"]          = "Entrenador"
L["MissingSrcOther"]            = "Otros"
L["MissingSrcUnknown"]          = "Desconocida"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Información sobre objetos"
L["SettingsTooltipShowCrafters"]    = "Mostrar artesanos de la hermandad en la información de objetos"
L["SettingsTooltipShowCraftersDesc"]= "Añade una línea [TOGPM] que lista a todos los compañeros de hermandad que pueden fabricar el objeto que tienes encima. En blanco si están conectados, en gris si no. Los objetos vinculados al recoger se omiten (no se pueden intercambiar de todos modos)."
L["SettingsTooltipShowIds"]         = "Mostrar ID de objeto / ID de hechizo en la información"
L["SettingsTooltipShowIdsDesc"]     = "Añade una línea [TOGPM] con el ID de objeto y (si se conoce) el ID de hechizo de la receta. Útil sobre todo para diagnosticar iconos incorrectos o recetas faltantes — pega los IDs en Wowhead para verificar la coincidencia."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Fase de TBC Aniversario"
L["SettingsTBCPhase"]           = "Fase de contenido actual"
L["SettingsTBCPhaseDesc"]       = "Oculta las Recetas faltantes que provienen de fases posteriores a la fase actual de Aniversario. Aumenta este valor cada vez que Blizzard avance de fase. (Las recetas ya accesibles en la fase activa siguen visibles.)"
L["SettingsTBCPhase1"]          = "Fase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Fase 2 — Caverna Fangoscura / Ojo de la Tormenta"
L["SettingsTBCPhase3"]          = "Fase 3 — Templo Oscuro / Monte Hyjal"
L["SettingsTBCPhase4"]          = "Fase 4 — Pozo del Sol / Terraza de los Magistrados"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Pantalla"
L["SettingsMinimapBtn"]          = "Mostrar botón de minimapa"
L["SettingsMinimapBtnDesc"]      = "Muestra u oculta el botón lanzador en el minimapa."
L["SettingsPersistProfFilter"]     = "Recordar filtro de profesión"
L["SettingsPersistProfFilterDesc"] = "Restaura la profesión seleccionada al iniciar sesión o recargar."
L["SettingsSyncHeader"]     = "Sincronización"
L["SettingsGuildMode"]      = "Modo de sincronización solo por hermandad (servidores privados)"
L["SettingsGuildModeDesc"]  = "Para servidores privados o emulados (p. ej. Whitemane) que no entregan los mensajes de addon por susurros, lo que impide que los miembros de la hermandad reciban los datos de profesión de los demás. Cuando está ACTIVADO, todo el tráfico de sincronización se enruta por el canal de hermandad. Actívalo solo si la sincronización de hermandad no funciona en tu servidor. |cffffd100Todos en la hermandad deberían activarlo|r — solo funciona entre miembros que lo tengan activado ambos. El uso compartido entre hermandades se desactiva automáticamente mientras esto está activado. Se aplica a todos los personajes de este reino. (Oculto si tu versión instalada de DeltaSync no lo admite.)"
L["SettingsCooldownsHeader"]= "Reutilizaciones"
L["SettingsMailReadyOnly"]  = "Correo: mostrar solo reutilizaciones listas"
L["SettingsMailReadyOnlyDesc"] = "Al redactar correo de suministros desde el panel de reutilizaciones, lista solo a los miembros cuya reutilización esté lista."
L["SettingsDevHeader"]      = "Desarrollador"
L["SettingsDebug"]          = "Salida de depuración"
L["SettingsDebugDesc"]      = "Imprime mensajes de depuración detallados en el chat."
L["SettingsDataHeader"]     = "Datos"
L["SettingsSyncNow"]        = "Forzar resincronización"
L["SettingsSyncNowDesc"]    = "Difunde inmediatamente tus datos de profesión a la hermandad."
L["SettingsPurgeGuild"]     = "Purgar todos los datos de hermandad"
L["SettingsPurgeGuildDesc"] = "Elimina todos los datos de profesión y reutilización almacenados para cada miembro de la hermandad de esta cuenta. No se puede deshacer."
L["SettingsPurgeGuildConfirm"] = "¿Eliminar TODOS los datos de hermandad de esta cuenta?"
L["SettingsPurgeMine"]      = "Purgar mis datos de personaje"
L["SettingsPurgeMineDesc"]  = "Elimina solo los datos almacenados de tu propio personaje de la base de datos de hermandad."
L["SettingsPurgeMineConfirm"] = "¿Eliminar tus datos de profesión y reutilización?"
L["SettingsSyncLogHeader"]  = "Registro de sincronización"
L["SettingsViewLog"]        = "Ver registro de sincronización"
L["SettingsViewLogDesc"]    = "Abre una lista desplazable de eventos recientes de sincronización (últimos 200)."
L["SettingsClearLog"]       = "Vaciar registro de sincronización"
L["SettingsClearLogConfirm"]= "¿Vaciar todas las entradas del registro de sincronización?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(módulo SyncLog no cargado)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(aún no se han registrado eventos de sincronización)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Botón de minimapa oculto. Usa |cffda8cff/togpm minimap|r para restaurarlo."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Fabricado por:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Listo para fabricar:|r %s × %d  (%s × %d en bolsas)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Activar alerta de artesano para esta receta"
L["ShoppingAlertDisable"]              = "Desactivar alerta de artesano para esta receta"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s está conectado — puede fabricar: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s está conectado (alter de %s) — puede fabricar: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Activar alerta de listo para esta reutilización"
L["CooldownAlertDisable"]              = "Desactivar alerta de listo para esta reutilización"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Reutilización lista: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Alertas de artesano"
L["SettingsCrafterAlert"]              = "Activar alertas de artesano"
L["SettingsCrafterAlertDesc"]          = "Reproduce un sonido y hace parpadear la pantalla cuando un miembro de la hermandad que puede fabricar un objeto alertado de la lista de compras se conecta."
L["SettingsCrafterAlertSuppressAudio"]     = "Suprimir sonido de alerta"
L["SettingsCrafterAlertSuppressAudioDesc"] = "Desactiva el sonido cuando un artesano se conecta (el parpadeo de pantalla y el mensaje de chat siguen apareciendo)."
L["SettingsCrafterAlertSuppressVisual"]    = "Suprimir alerta visual"
L["SettingsCrafterAlertSuppressVisualDesc"] = "Desactiva la alerta visual en pantalla (parpadeo de pantalla, banner, etc.) cuando un artesano se conecta (el sonido y el mensaje de chat siguen apareciendo)."
L["AlertCrafterOnlineBanner"]              = "Artesano de hermandad conectado"
L["SettingsCrafterAlertSound"]             = "Sonido de alerta"
L["SettingsCrafterAlertSoundDesc"]         = "Qué sonido se reproduce cuando un artesano al que puedes llegar se conecta. Al seleccionar uno se muestra una vista previa. No tiene efecto mientras el sonido de alerta esté suprimido arriba."
L["SettingsCrafterAlertVisual"]            = "Efecto visual de alerta"
L["SettingsCrafterAlertVisualDesc"]        = "Qué efecto en pantalla se dispara cuando un artesano se conecta: un destello a pantalla completa en el tono que elijas, o un parpadeo en la barra de tareas para cuando estés en otra ventana. Al seleccionar uno se muestra una vista previa. No tiene efecto mientras el parpadeo de pantalla esté suprimido arriba."
L["SettingsCrafterAlertSuppressLogin"]     = "Suprimir alertas al iniciar sesión"
L["SettingsCrafterAlertSuppressLoginDesc"] = "No dispares alertas durante la ráfaga inicial de notificaciones de conexión al iniciar sesión o recargar."
L["SettingsCooldownAlertSuppressProtected"]     = "Silenciar alertas en instancias"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "No emitas ni imprimas alertas de reutilización lista mientras estés en una banda, mazmorra, campo de batalla, arena o escenario. Las capitales NO se silencian — tu transmutación seguirá sonando mientras estés ausente en Ventormenta. Las alertas pendientes se disparan en cuanto salgas de la instancia."
L["SettingsCooldownReminderInterval"]      = "Recordatorio de reutilización lista"
L["SettingsCooldownReminderIntervalDesc"]  = "Vuelve a disparar cada alerta de reutilización armada cada N minutos mientras la reutilización siga lista (es decir, hasta que realmente la uses). Introduce 0, vacío o 'off' para disparar solo una vez por ciclo de listo. Rango válido: 1–1440 minutos (24 horas)."
L["SettingsCooldownReminderInvalid"]       = "Introduce un número entero de 0 a 1440, u 'off'."

L["SettingsAHHeader"]                      = "Casa de subastas"
L["SettingsAHScanDelay"]                   = "Retraso del escaneo de SU (segundos)"
L["SettingsAHScanDelayDesc"]               = "Segundos entre consultas de escaneo de la SU. Vacío / 0 / 'off' usa el valor por defecto de la versión (1.5s en Classic Era y Aniversario; 3.0s en TBC, Wrath, Cata, MoP — esos servidores limitan más). Reduce el valor para escaneos más rápidos, auméntalo si los escaneos se quedan atascados. Rango válido: 0.5–10 segundos."
L["SettingsAHScanDelayInvalid"]            = "Introduce un número de 0.5 a 10, u 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Receta"
L["TooltipRecipeDesc"]           = "El nombre del objeto fabricable o del hechizo."
L["TooltipCraftersTitle"]        = "Artesanos"
L["TooltipCraftersDesc"]         = "Miembros de la hermandad que conocen esta receta. Pulsa una receta para la lista completa."
L["CraftersColHeader"]           = "Artesanos"
L["TooltipBankTitle"]            = "Solicitar al banco"
L["TooltipBankDescScroll"]       = "Envía una solicitud a un banquero de hermandad TOGBankClassic para este pergamino de receta."
L["TooltipBankDescGeneric"]      = "Envía una solicitud a un banquero de hermandad TOGBankClassic."
L["TooltipAHTitle"]              = "Buscar en la subasta"
L["TooltipAHDescScroll"]         = "Abre este pergamino de receta en la búsqueda de la SU."
L["TooltipAHDescReagent"]        = "Abre este componente en la búsqueda de la SU."
L["TooltipSettingsTitle"]        = "Ajustes"
L["TooltipSettingsDesc"]         = "Abre el panel de ajustes de TOG Profession Master (|cffffd700ESC > Opciones > AddOns > TOG Profession Master|r). Mismo destino que |cffffd700/togpm settings|r y Mayús+clic izquierdo en el botón del minimapa."
L["TooltipWhisperRightClick"]    = "Clic derecho para susurrar"
L["TooltipClickTransmutes"]      = "Pulsa para ver las transmutaciones"
L["TooltipClickDetailsFormat"]   = "Pulsa para ver %s"
L["TooltipClickDetailsFallback"] = "detalles"

-- ---------------------------------------------------------------------------
-- Mail composer (correo de suministros desde la pestaña Reutilizaciones)
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Suministros de reutilización: %s"
L["MailBodyFormat"]         = "¡Hola %s! Por favor usa estos materiales para hacer %s. Mándame el %s cuando tengas tiempo de fabricarlo. ¡Gracias!"
L["MailMsgNoEmptyBag"]      = "No hay hueco vacío en la bolsa para dividir."
L["MailMsgOpenMailbox"]     = "Abre primero un buzón."
L["MailMsgHasItems"]        = "El correo ya tiene objetos adjuntos — envíalos o quítalos primero."
L["MailMsgCannotFulfill"]   = "No se puede completar."
L["MailMsgCouldNotAttach"]  = "No se pudieron adjuntar los objetos."
L["MailMsgAttachedFormat"]  = "Adjuntados %dx %s para %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Clic izquierdo|r para mostrar/ocultar el navegador de profesiones"
L["MinimapTooltipRightClick"]  = "|cffffd100Clic derecho|r para mostrar/ocultar los componentes"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Mayús+izquierdo|r abre los ajustes"
L["MinimapButtonShown"]        = "Botón de minimapa mostrado."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- los nombres de comando no se traducen
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — comandos:"
L["SlashHelpOpen"]          = "abrir navegador de profesiones"
L["SlashHelpReagents"]      = "abrir componentes faltantes"
L["SlashHelpMinimap"]       = "mostrar botón de minimapa"
L["SlashHelpPurge"]         = "abrir diálogo de purga"
L["SlashHelpSync"]          = "forzar resincronización completa de la hermandad"
L["SlashHelpStatus"]        = "volcar información de diagnóstico de sync/comm"
L["SlashHelpVersionCheck"]  = "comprobar versiones del addon en la hermandad"
L["SlashHelpDebug"]         = "alternar salida de depuración"
L["SlashHelpHelp"]          = "mostrar esta lista"
L["SlashForceSyncSent"]     = "Sincronización forzada enviada."
L["AHScannerOpenAH"]        = "Abre la subasta para buscar."
L["AHOpenFirst"]            = "Abre primero la subasta."
L["AHNoItemsToScan"]        = "No hay objetos que escanear en la vista actual."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Solicitar al banco de hermandad"
L["BankDialogBanker"]       = "Banquero:"
L["BankDialogQty"]          = "Cant.:"
L["BankDialogSend"]         = "Enviar solicitud"
L["BankDialogCancel"]       = "Cancelar"

-- ---------------------------------------------------------------------------
-- Confirmaciones de purga y otras salidas de comando
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Todos los datos de hermandad purgados."
L["MsgOwnDataPurged"]        = "Tus datos de personaje purgados."
L["SlashForceBroadcastSent"] = "Difusión forzada enviada."
L["SlashDebugEnabled"]       = "|cff00ff00activada|r"
L["SlashDebugDisabled"]      = "|cffff4444desactivada|r"
L["SlashDebugToggleFormat"]  = "Salida de depuración %s"

-- ---------------------------------------------------------------------------
-- Nombres de profesiones (oficial Blizzard esES, los 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alquimia"
L["ProfBlacksmithing"]  = "Herrería"
L["ProfCooking"]        = "Cocina"
L["ProfEnchanting"]     = "Encantamiento"
L["ProfEngineering"]    = "Ingeniería"
L["ProfFirstAid"]       = "Primeros auxilios"
L["ProfLeatherworking"] = "Peletería"
L["ProfMining"]         = "Minería"
L["ProfTailoring"]      = "Sastrería"
L["ProfHerbalism"]      = "Herboristería"
L["ProfSkinning"]       = "Desuello"
L["ProfJewelcrafting"]  = "Joyería"
L["ProfInscription"]    = "Inscripción"
L["ProfFishing"]        = "Pesca"
L["ProfSmelting"]       = "Fundición"

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
