-- DeltaSync Library
-- Author: ianplamondon
-- Version: 1.0.0
-- A standalone, embeddable Lua library for efficient data synchronization using delta compression

local MAJOR, MINOR = "DeltaSync-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then
    return -- Already loaded
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Communication channel types
-- VERSION, DATA, QUERY, RESPONSE, DELTA: core sync channels (5 prefixes)
-- OFFER, HANDSHAKE: P2P session negotiation channels (2 prefixes, 7 total)
local CHANNEL_TYPES = {
    VERSION   = "v",  -- Version/hash-list broadcast to guild
    DATA      = "d",  -- Full data sync
    QUERY     = "q",  -- State summary (requester → provider, triggers delta computation)
    RESPONSE  = "r",  -- Query response / no-change notification
    DELTA     = "x",  -- Delta sync
    OFFER     = "o",  -- Hash-offer (peer → broadcaster) or hash-list-broadcast (GUILD)
    HANDSHAKE = "h",  -- P2P handshake: sync-request / sync-accept / sync-busy
}

-- Wire format for checksum-wrapped messages:
--   <AceSerializer payload> \030 <checksum> \031END
-- \030 = ASCII Record Separator (not emitted by AceSerializer)
-- \031END = stop-marker confirming message was fully delivered (not truncated)
local CHECKSUM_SEPARATOR = "\030"
local STOP_MARKER        = "\031END"

-- Default channel configuration
-- Host addons can override these during Initialize()
local DEFAULT_CHANNEL_CONFIG = {
    VERSION = {
        distribution = "GUILD",
        priority = "NORMAL",
        channel = nil,
    },
    DATA = {
        distribution = "GUILD",
        priority = "BULK",
        channel = nil,
    },
    QUERY = {
        distribution = "WHISPER",
        priority = "NORMAL",
        channel = nil,
    },
    RESPONSE = {
        distribution = "WHISPER",
        priority = "NORMAL",
        channel = nil,
    },
    DELTA = {
        distribution = "WHISPER",
        priority = "NORMAL",
        channel = nil,
    },
    -- P2P negotiation channels
    OFFER = {
        distribution = "WHISPER",  -- whisper by default; BroadcastItemHashes overrides to GUILD
        priority = "NORMAL",
        channel = nil,
    },
    HANDSHAKE = {
        distribution = "WHISPER",
        priority = "NORMAL",
        channel = nil,
    },
}

-- Valid distribution types
local VALID_DISTRIBUTIONS = {
    GUILD = true,
    RAID = true,
    PARTY = true,
    WHISPER = true,
    CHANNEL = true,
}

-- Valid priority levels (AceComm/ChatThrottleLib)
local VALID_PRIORITIES = {
    ALERT = true,   -- Highest priority, bypasses throttling
    NORMAL = true,  -- Standard priority
    BULK = true,    -- Lowest priority, background tasks
}

-- Maximum prefix length enforced by WoW
local MAX_PREFIX_LENGTH = 16

-- Debug categories for filtering
local DEBUG_CATEGORY = {
    INIT = "INIT",           -- Library initialization
    HASH = "HASH",           -- Hash computation
    COMMS = "COMMS",         -- Communication layer
    DELTA = "DELTA",         -- Delta operations
    VALIDATE = "VALIDATE",   -- Validation/sanitization
    SERIALIZE = "SERIALIZE", -- Serialization layer
}

-- Debug sub-tags for fine-grained filtering
-- nil entry in host SV = tag is ALLOWED by default (opt-out model)
local DEBUG_TAGS = {
    COMMS = {
        SEND = "message sends",
        RECEIVE = "message receives",
        HANDLER = "handler invocations",
        REGISTER = "channel registration",
    },
    DELTA = {
        COMPUTE = "delta computation",
        APPLY = "delta application",
        VALIDATE = "delta validation",
    },
    HASH = {
        ARRAY = "array hash computation",
        STRUCTURED = "structured hash computation",
    },
}

-- ============================================================================
-- PRIVATE FUNCTIONS
-- ============================================================================

-- Generate a shortened addon name for prefix generation
-- Creates a 6-character prefix from the addon name
-- @param addonName: full addon name
-- @return: 6-character prefix
local function GenerateShortName(addonName)
    if not addonName or addonName == "" then
        return "dltsyn"  -- Default: "dltsyn" (deltasync shortened)
    end
    
    -- Lowercase and remove spaces/special chars
    local cleaned = string.lower(addonName)
    cleaned = string.gsub(cleaned, "[^a-z0-9]", "")
    
    -- Always truncate to exactly 6 characters
    if #cleaned > 6 then
        cleaned = string.sub(cleaned, 1, 6)
    elseif #cleaned < 6 then
        -- Pad with 'x' if too short (rare case)
        while #cleaned < 6 do
            cleaned = cleaned .. "x"
        end
    end
    
    return cleaned
end

-- Validate channel configuration
-- @param channelConfig: table of channel configurations
-- @return: true if valid, or nil + error message
local function ValidateChannelConfig(channelConfig)
    if not channelConfig then
        return true -- nil config is valid, will use defaults
    end
    
    if type(channelConfig) ~= "table" then
        return nil, "Channel configuration must be a table"
    end
    
    for channelName, config in pairs(channelConfig) do
        -- Validate channel name
        if not CHANNEL_TYPES[channelName] then
            return nil, string.format("Unknown channel type: %s", channelName)
        end
        
        -- Validate config structure
        if type(config) ~= "table" then
            return nil, string.format("Channel %s config must be a table", channelName)
        end
        
        -- Validate distribution
        if config.distribution then
            if not VALID_DISTRIBUTIONS[config.distribution] then
                return nil, string.format("Channel %s: Invalid distribution '%s'", channelName, config.distribution)
            end
            
            -- CHANNEL distribution requires channel name
            if config.distribution == "CHANNEL" and not config.channel then
                return nil, string.format("Channel %s: CHANNEL distribution requires 'channel' parameter", channelName)
            end
        end
        
        -- Validate priority
        if config.priority then
            if not VALID_PRIORITIES[config.priority] then
                return nil, string.format("Channel %s: Invalid priority '%s' (must be ALERT, NORMAL, or BULK)", channelName, config.priority)
            end
        end
    end
    
    return true
end

-- Merge channel configuration with defaults
-- @param userConfig: user-provided configuration (may be partial)
-- @return: complete configuration with defaults filled in
local function MergeChannelConfig(userConfig)
    local merged = {}
    
    -- Start with defaults
    for channelName, defaultConfig in pairs(DEFAULT_CHANNEL_CONFIG) do
        merged[channelName] = {
            distribution = defaultConfig.distribution,
            priority = defaultConfig.priority,
            channel = defaultConfig.channel,
        }
    end
    
    -- Override with user config
    if userConfig then
        for channelName, userChannelConfig in pairs(userConfig) do
            if merged[channelName] then
                if userChannelConfig.distribution then
                    merged[channelName].distribution = userChannelConfig.distribution
                end
                if userChannelConfig.priority then
                    merged[channelName].priority = userChannelConfig.priority
                end
                if userChannelConfig.channel then
                    merged[channelName].channel = userChannelConfig.channel
                end
            end
        end
    end
    
    return merged
end

-- Generate all communication prefixes for an addon
-- @param addonName: full addon name
-- @return: table of prefixes { version="...", data="...", etc. }
local function GeneratePrefixes(addonName)
    local shortName = GenerateShortName(addonName)
    local prefixes = {}
    
    for channelName, suffix in pairs(CHANNEL_TYPES) do
        local prefix = shortName .. "-" .. suffix
        if #prefix > MAX_PREFIX_LENGTH then
            -- Should never happen with our truncation, but safety check
            prefix = string.sub(prefix, 1, MAX_PREFIX_LENGTH)
        end
        prefixes[channelName] = prefix
    end
    
    return prefixes
end

-- Compute a simple but effective checksum/hash of a string
-- Uses multiplicative hashing with prime number (31) for good distribution
-- Returns: numeric hash value (0 to 2147483647)
local function ComputeChecksum(str)
    if not str or type(str) ~= "string" then
        return 0
    end
    
    local sum = 0
    local len = #str
    for i = 1, len do
        local byte = string.byte(str, i)
        sum = (sum * 31 + byte) % 2147483647
    end
    -- Include length to detect truncation
    sum = (sum * 31 + len) % 2147483647
    
    return sum
end

-- Serialize a Lua value to a string for hashing
-- Handles tables, strings, numbers, booleans, nil
-- Returns: string representation
local function SerializeForHash(value, seen)
    seen = seen or {}
    local valueType = type(value)
    
    if valueType == "nil" then
        return "nil"
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        return tostring(value)
    elseif valueType == "string" then
        return value
    elseif valueType == "table" then
        -- Detect circular references
        if seen[value] then
            return "circular"
        end
        seen[value] = true
        
        -- Collect and sort keys for consistent ordering
        local keys = {}
        for k in pairs(value) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then
                return ta < tb
            end
            return tostring(a) < tostring(b)
        end)
        
        -- Build serialized representation
        local parts = {}
        for _, k in ipairs(keys) do
            local keyStr = SerializeForHash(k, seen)
            local valStr = SerializeForHash(value[k], seen)
            table.insert(parts, keyStr .. "=" .. valStr)
        end
        
        return "{" .. table.concat(parts, ",") .. "}"
    else
        -- Unsupported type (function, userdata, thread)
        return "unsupported:" .. valueType
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Initialize the library with configuration options
-- @param config: table with optional fields:
--   - namespace: string, unique identifier for your addon (REQUIRED)
--   - debug: table with debug configuration:
--       - enabled: boolean, enable debug logging (default: false)
--       - addonName: string, name for debug tab (default: namespace)
--       - savedVariables: table, reference to host addon's SV table (REQUIRED for persistence)
--       - categories: table, initial category states (optional, uses SV if available)
--   - hashStrategy: string, "deep" or "shallow" (default: "deep")
--   - onVersionReceived: function(sender, version, hash), called when version broadcast received
--   - onDataRequest: function(sender, baseline), called when data request received
--   - onDataReceived: function(sender, data), called when full data or delta received
--   - onOfferReceived: function(sender, data), raw OFFER message received (P2P inspection hook)
function lib:Initialize(config)
    config = config or {}
    
    if not config.namespace then
        error("DeltaSync:Initialize() requires 'namespace' parameter (your addon name)")
    end
    
    self.namespace = config.namespace
    
    -- Validate and merge channel configuration
    local valid, err = ValidateChannelConfig(config.channels)
    if not valid then
        error("DeltaSync: Invalid channel configuration: " .. err)
    end
    self.channelConfig = MergeChannelConfig(config.channels)
    
    -- Initialize debug system
    local debugConfig = config.debug or {}
    self.debugEnabled = debugConfig.enabled or false
    self.debugAddonName = debugConfig.addonName or self.namespace
    self.debugSV = debugConfig.savedVariables
    
    -- Initialize debug storage in host SV if not exists
    if self.debugEnabled and self.debugSV then
        if not self.debugSV.deltaSyncDebug then
            self.debugSV.deltaSyncDebug = {
                categories = {},
                tags = {},
            }
        end
        
        -- Apply initial category states if provided
        if debugConfig.categories then
            for category, enabled in pairs(debugConfig.categories) do
                self.debugSV.deltaSyncDebug.categories[category] = enabled
            end
        end
    end
    
    -- Initialize debug frame and buffer
    self.debugFrame = nil
    self.debugMessageBuffer = {}
    self.maxBufferSize = 1000
    
    self.hashStrategy = config.hashStrategy or "deep"
    self.callbacks = {
        onVersionReceived  = config.onVersionReceived,
        onDataRequest      = config.onDataRequest,
        onDataReceived     = config.onDataReceived,
        -- P2P callbacks
        onOfferReceived    = config.onOfferReceived,   -- (sender, data) raw OFFER message received
    }
    
    -- Generate and store communication prefixes
    self.prefixes = GeneratePrefixes(self.namespace)
    
    -- Initialize state storage
    self.localState = {
        version = 0,
        hash = 0,
        data = nil,
    }
    
    -- Peer state tracking
    self.peerStates = {} -- [sender] = { version, hash, lastSeen }
    
    -- Store player name for self-ignore (GuildCache provides canonical Name-Realm form)
    self.playerName     = UnitName and UnitName("player") or ""
    self.playerFullName = lib:GetNormalizedPlayer()

    -- Register communication channels
    self:RegisterCommChannels()
    
    -- Create debug chat frame if enabled
    if self.debugEnabled then
        self:CreateDebugTab()
        self:Debug("INIT", "Initialized DeltaSync for %s", self.namespace)
        self:Debug("INIT", "Prefixes: v=%s, d=%s, q=%s, r=%s, x=%s", 
            self.prefixes.VERSION,
            self.prefixes.DATA,
            self.prefixes.QUERY,
            self.prefixes.RESPONSE,
            self.prefixes.DELTA)
        
        -- Log channel configuration
        for channelName, config in pairs(self.channelConfig) do
            self:Debug("INIT", "Channel %s: distribution=%s, priority=%s%s",
                channelName,
                config.distribution,
                config.priority,
                config.channel and (", channel=" .. config.channel) or "")
        end
    end
end

-- Register all communication channels with AceComm
-- Embeds AceComm-3.0 and AceCommQueue-1.0 directly into the lib object so that:
--   1. lib:RegisterComm() / lib:SendCommMessage() are available.
--   2. AceCommQueue wraps SendCommMessage to prevent CTL chunk interleaving
--      (the root cause of CRC errors when messages of different priorities share a prefix).
-- Falls back to raw WoW API when AceComm is unavailable.
function lib:RegisterCommChannels()
    -- Step 0: Embed AceSerialization-3.0 so lib:Serialize() / lib:Deserialize() are available.
    local AceSer = LibStub and LibStub:GetLibrary("AceSerialization-3.0", true)
    if AceSer and not lib.__AceSer_embedded then
        AceSer:Embed(lib)
        lib.__AceSer_embedded = true
    end

    local AceComm = LibStub and LibStub:GetLibrary("AceComm-3.0", true)

    if AceComm then
        -- Step 1: Embed AceComm into lib so it gets its own RegisterComm/SendCommMessage.
        -- Guard against double-embedding across LibStub upgrades.
        if not lib.__AceComm_embedded then
            AceComm:Embed(lib)
            lib.__AceComm_embedded = true
        end

        -- Step 2: Capture the AceComm-backed SendCommMessage BEFORE the queue wraps it,
        -- so we can insert a debug-logging shim in between (mirrors TOGBankClassic pattern).
        local aceCommSend = lib.SendCommMessage
        lib.SendCommMessage = function(commObj, prefix, text, dist, target, prio, callbackFn, callbackArg)
            local bytes = text and #text or 0
            local dest  = (target and target ~= "") and (dist .. "/" .. target) or (dist or "GUILD")
            lib:Debug("COMMS", "SEND", "< %s to %s (%d bytes) [%s]", prefix, dest, bytes, prio or "NORMAL")
            return aceCommSend(commObj, prefix, text, dist, target, prio, callbackFn, callbackArg)
        end

        -- Step 3: Embed AceCommQueue AFTER the shim so the queue wraps the complete chain.
        local ACQ = LibStub and LibStub:GetLibrary("AceCommQueue-1.0", true)
        if ACQ then
            ACQ:Embed(lib)
            self:Debug("COMMS", "REGISTER", "AceCommQueue-1.0 embedded — chunk-interleave CRC errors prevented")
        else
            self:Debug("COMMS", "REGISTER", "AceCommQueue-1.0 not found — large multi-priority sends may CRC-error")
        end

        -- Step 4: Register comm handlers using lib's own RegisterComm.
        for channelName, prefix in pairs(self.prefixes) do
            local handlerName = "OnComm_" .. channelName
            lib:RegisterComm(prefix, function(p, message, distribution, sender)
                lib[handlerName](lib, p, message, distribution, sender)
            end)
            self:Debug("COMMS", "REGISTER", "Registered AceComm channel: %s", prefix)
        end

        self.useAceComm     = true
        self.useAceCommQueue = ACQ ~= nil
    else
        -- Fall back to raw WoW API
        local API            = C_ChatInfo or {}
        local RegisterPrefix = API.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix

        if RegisterPrefix then
            for _, prefix in pairs(self.prefixes) do
                RegisterPrefix(prefix)
                self:Debug("COMMS", "REGISTER", "Registered addon message prefix: %s", prefix)
            end
        else
            error("DeltaSync: No communication API available (neither AceComm-3.0 nor C_ChatInfo)")
        end

        -- Register event handler for incoming messages
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
            self:OnAddonMessage(prefix, message, distribution, sender)
        end)
        self.commFrame = frame

        self.useAceComm      = false
        self.useAceCommQueue = false
    end

    self.commsRegistered = true
end

-- Get the current channel configuration
-- @param channelType: specific channel (optional, returns all if nil)
-- @return: channel config table or full config
function lib:GetChannelConfig(channelType)
    if channelType then
        return self.channelConfig[channelType]
    end
    return self.channelConfig
end

-- Update channel configuration at runtime (not recommended)
-- @param channelType: channel to update
-- @param config: new configuration { distribution, priority, channel }
-- @return: true if successful, or nil + error message
function lib:SetChannelConfig(channelType, config)
    if not CHANNEL_TYPES[channelType] then
        return nil, "Unknown channel type: " .. channelType
    end
    
    -- Validate the configuration
    local tempConfig = { [channelType] = config }
    local valid, err = ValidateChannelConfig(tempConfig)
    if not valid then
        return nil, err
    end
    
    -- Update configuration
    if not self.channelConfig[channelType] then
        self.channelConfig[channelType] = {}
    end
    
    if config.distribution then
        self.channelConfig[channelType].distribution = config.distribution
    end
    if config.priority then
        self.channelConfig[channelType].priority = config.priority
    end
    if config.channel ~= nil then
        self.channelConfig[channelType].channel = config.channel
    end
    
    self:Debug("COMMS", "Updated %s channel config: dist=%s, priority=%s%s",
        channelType,
        self.channelConfig[channelType].distribution,
        self.channelConfig[channelType].priority,
        self.channelConfig[channelType].channel and (", channel=" .. self.channelConfig[channelType].channel) or "")
    
    return true
end

-- Send a message on a specific channel
-- @param channelType: one of CHANNEL_TYPES keys (VERSION, DATA, QUERY, etc.)
-- @param message: serialized message string
-- @param distribution: "GUILD", "RAID", "PARTY", "WHISPER", "CHANNEL" (optional, uses config if nil)
-- @param target: target player name (for WHISPER only) or channel name (for CHANNEL)
-- @param priority: "ALERT", "NORMAL", "BULK" (optional, uses config if nil)
function lib:SendMessage(channelType, message, distribution, target, priority)
    local prefix = self.prefixes[channelType]
    if not prefix then
        self:Debug("ERROR: Unknown channel type: %s", channelType)
        return false
    end

    -- Use configured distribution/priority if not explicitly provided
    local channelConfig = self.channelConfig[channelType]
    distribution = distribution or (channelConfig and channelConfig.distribution) or "GUILD"
    priority     = priority     or (channelConfig and channelConfig.priority)     or "NORMAL"

    -- For CHANNEL distribution, use configured channel name if target not provided
    if distribution == "CHANNEL" and not target and channelConfig then
        target = channelConfig.channel
    end

    if distribution == "CHANNEL" and not target then
        self:Debug("COMMS", "ERROR: CHANNEL distribution requires target channel name")
        return false
    end

    -- Online guard for whispers: skip only if the roster confirms the target is a known
    -- guild member who is currently offline.  Targets not in the roster (cross-realm,
    -- non-guild use cases) are allowed through so the library stays generic.
    if distribution == "WHISPER" and target then
        local normTarget = lib:NormalizeName(target)
        local entry      = normTarget and lib.guildRoster and lib.guildRoster[normTarget]
        if entry and not entry.isOnline then
            self:Debug("COMMS", "SKIP", "Skipping whisper to offline member: %s", target)
            return false
        end
    end

    if self.useAceComm then
        -- Use lib:SendCommMessage (AceComm-embedded, wrapped by AceCommQueue if present).
        if distribution == "CHANNEL" then
            local channelNum = GetChannelName(target)
            if not channelNum or channelNum == 0 then
                self:Debug("COMMS", "ERROR: Channel '%s' not found or not joined", tostring(target))
                return false
            end
            lib:SendCommMessage(prefix, message, distribution, tostring(channelNum), priority)
        else
            lib:SendCommMessage(prefix, message, distribution, target, priority)
        end
    else
        -- Raw WoW API fallback (no priority support, no queue)
        local API     = C_ChatInfo or {}
        local SendMsg = API.SendAddonMessage or SendAddonMessage
        if not SendMsg then
            self:Debug("COMMS", "ERROR: Cannot send message - no API available")
            return false
        end
        if distribution == "CHANNEL" then
            local channelNum = GetChannelName(target)
            if not channelNum or channelNum == 0 then
                self:Debug("COMMS", "ERROR: Channel '%s' not found or not joined", tostring(target))
                return false
            end
            SendMsg(prefix, message, distribution, channelNum)
        else
            SendMsg(prefix, message, distribution, target)
        end
    end

    return true
end

-- ============================================================================
-- MESSAGE HANDLERS
-- ============================================================================

-- Handle raw addon messages (non-AceComm fallback)
function lib:OnAddonMessage(prefix, message, distribution, sender)
    -- Route to appropriate handler based on prefix
    for channelName, channelPrefix in pairs(self.prefixes) do
        if prefix == channelPrefix then
            local handlerName = "OnComm_" .. channelName
            if self[handlerName] then
                self[handlerName](self, prefix, message, distribution, sender)
            end
            return
        end
    end
end

-- Handle VERSION channel messages (version broadcasts)
function lib:OnComm_VERSION(prefix, message, distribution, sender)
    -- Ignore own messages
    if sender == self.playerName or sender == self.playerFullName then
        return
    end

    self:Debug("COMMS", "RECEIVE", "Received VERSION from %s", sender)

    -- Deserialize checksum-wrapped payload (SerializeWithChecksum format).
    -- Falls back gracefully to the old plain "version|hash" wire format for pre-CRC peers.
    local version, hash
    local ok, data = self:DeserializeWithChecksum(message)
    if ok and type(data) == "table" then
        version = tonumber(data.version)
        hash    = tonumber(data.hash)
    else
        -- Old-format fallback: plain "version|hash" string
        local vs, hs = string.match(message, "^(%d+)|(%d+)$")
        version = vs and tonumber(vs)
        hash    = hs and tonumber(hs)
    end

    if not version or not hash then
        self:Debug("COMMS", "ERROR: Invalid VERSION message from %s", sender)
        return
    end

    -- Update peer state
    self.peerStates[sender] = {
        version  = version,
        hash     = hash,
        lastSeen = GetServerTime(),
    }

    -- Notify host addon
    if self.callbacks.onVersionReceived then
        self.callbacks.onVersionReceived(sender, version, hash)
    end
end

-- Handle QUERY channel messages (data requests)
function lib:OnComm_QUERY(prefix, message, distribution, sender)
    -- Ignore own messages
    if sender == self.playerName or sender == self.playerFullName then
        return
    end
    
    self:Debug("COMMS", "RECEIVE", "Received QUERY from %s", sender)
    
    -- Parse baseline information from query
    -- Format: "hash|version|keys"
    local baseline = self:DeserializeBaseline(message)
    
    -- Notify host addon to handle the request
    if self.callbacks.onDataRequest then
        self.callbacks.onDataRequest(sender, baseline)
    end
end

-- Handle RESPONSE channel messages (query responses)
function lib:OnComm_RESPONSE(prefix, message, distribution, sender)
    -- Ignore own messages
    if sender == self.playerName or sender == self.playerFullName then
        return
    end
    
    self:Debug("COMMS", "RECEIVE", "Received RESPONSE from %s (%d bytes)", sender, #message)
    
    -- Deserialize data
    local data = self:DeserializeData(message)
    
    if not data then
        self:Debug("COMMS", "ERROR: Failed to deserialize RESPONSE from %s", sender)
        return
    end
    
    -- Notify host addon
    if self.callbacks.onDataReceived then
        self.callbacks.onDataReceived(sender, data)
    end
end

-- Handle DATA channel messages (full sync)
function lib:OnComm_DATA(prefix, message, distribution, sender)
    -- Ignore own messages
    if sender == self.playerName or sender == self.playerFullName then
        return
    end
    
    self:Debug("COMMS", "RECEIVE", "Received DATA from %s (%d bytes)", sender, #message)
    
    -- Same as RESPONSE - full data sync
    local data = self:DeserializeData(message)
    
    if not data then
        self:Debug("COMMS", "ERROR: Failed to deserialize DATA from %s", sender)
        return
    end
    
    -- Notify host addon
    if self.callbacks.onDataReceived then
        self.callbacks.onDataReceived(sender, data)
    end
end

-- Handle DELTA channel messages (delta sync)
function lib:OnComm_DELTA(prefix, message, distribution, sender)
    -- Ignore own messages
    if sender == self.playerName or sender == self.playerFullName then
        return
    end

    self:Debug("COMMS", "RECEIVE", "Received DELTA from %s (%d bytes)", sender, #message)

    -- Deserialize delta
    local delta = self:DeserializeData(message)

    if not delta then
        self:Debug("DELTA", "ERROR: Failed to deserialize DELTA from %s", sender)
        return
    end

    -- Validate delta structure
    local valid, err = self:ValidateDelta(delta)
    if not valid then
        self:Debug("DELTA", "VALIDATE", "Invalid DELTA from %s: %s", sender, err)
        return
    end

    -- Notify host addon (they will apply it)
    if self.callbacks.onDataReceived then
        self.callbacks.onDataReceived(sender, delta)
    end
end

-- Handle OFFER channel messages (hash-list broadcast OR hash-offer whisper)
-- GUILD distribution: peer is broadcasting their item hashes; if we have newer
--   data for any listed item we send a hash-offer whisper back.
-- WHISPER distribution: peer is offering data for specific items; P2PSession
--   records the offer during the collect window.
function lib:OnComm_OFFER(prefix, message, distribution, sender)
    if sender == self.playerName or sender == self.playerFullName then
        return
    end

    self:Debug("COMMS", "RECEIVE", "Received OFFER from %s (%s, %d bytes)", sender, distribution, #message)

    local ok, data = self:DeserializeWithChecksum(message)
    if not ok or type(data) ~= "table" then
        self:Debug("COMMS", "ERROR: Invalid OFFER from %s: %s", sender, tostring(data))
        return
    end

    if self.p2p then
        if data.type == "hash-list" then
            -- Peer broadcast their hashes; let P2PSession decide whether to offer data.
            self.p2p:OnHashListReceived(sender, data.items)
        elseif data.type == "hash-offer" then
            -- Peer is offering data; record during collect window.
            self.p2p:OnOffer(sender, data.items)
        end
    end

    -- Also fire the generic callback so host addons can inspect raw peer hashes.
    if self.callbacks.onOfferReceived then
        self.callbacks.onOfferReceived(sender, data)
    end
end

-- Handle HANDSHAKE channel messages (P2P session negotiation)
-- All three subtypes travel on the same whisper prefix:
--   sync-request  (requester → provider): "please send me data for itemKey"
--   sync-accept   (provider → requester): "OK, data incoming"
--   sync-busy     (provider → requester): "at capacity, try another peer"
function lib:OnComm_HANDSHAKE(prefix, message, distribution, sender)
    if sender == self.playerName or sender == self.playerFullName then
        return
    end

    self:Debug("COMMS", "RECEIVE", "Received HANDSHAKE from %s (%d bytes)", sender, #message)

    local ok, data = self:DeserializeWithChecksum(message)
    if not ok or type(data) ~= "table" then
        self:Debug("COMMS", "ERROR: Invalid HANDSHAKE from %s: %s", sender, tostring(data))
        return
    end

    if self.p2p then
        if data.type == "sync-request" then
            self.p2p:HandleSyncRequest(data.sessionId, sender, data.itemKey)
        elseif data.type == "sync-accept" then
            self.p2p:OnSyncAccept(data.sessionId, sender)
        elseif data.type == "sync-busy" then
            self.p2p:OnSyncBusy(data.sessionId, sender)
        end
    end
end

-- ============================================================================
-- HIGH-LEVEL API
-- ============================================================================

-- Broadcast your current version and hash to the network
-- @param version: numeric version number
-- @param hash: numeric content hash
-- @param distribution: "GUILD", "RAID", "PARTY", "CHANNEL" (optional, uses config if nil)
-- @param priority: "ALERT", "NORMAL", "BULK" (optional, uses config if nil)
function lib:BroadcastVersion(version, hash, distribution, priority)
    local message = self:SerializeWithChecksum({ type = "version", version = version, hash = hash })
    if not message then return false end
    return self:SendMessage("VERSION", message, distribution, nil, priority)
end

-- Request data from a peer
-- @param target: player name
-- @param baseline: your current baseline { version, hash, keys }
-- @param priority: "ALERT", "NORMAL", "BULK" (optional, uses config if nil)
function lib:RequestData(target, baseline, priority)
    local message = self:SerializeBaseline(baseline)
    return self:SendMessage("QUERY", message, "WHISPER", target, priority)
end

-- Send data to a peer in response to a request
-- @param target: player name
-- @param data: data structure or delta to send
-- @param isDelta: boolean, true if sending delta instead of full data
-- @param priority: "ALERT", "NORMAL", "BULK" (optional, uses config if nil)
function lib:SendData(target, data, isDelta, priority)
    local channelType = isDelta and "DELTA" or "RESPONSE"
    local message = self:SerializeData(data)
    return self:SendMessage(channelType, message, "WHISPER", target, priority)
end

-- Broadcast full data to the network (not recommended for large data)
-- @param data: data structure to broadcast
-- @param distribution: "GUILD", "RAID", "PARTY", "CHANNEL" (optional, uses config if nil)
-- @param priority: "ALERT", "NORMAL", "BULK" (optional, uses config if nil)
function lib:BroadcastData(data, distribution, priority)
    local message = self:SerializeData(data)
    return self:SendMessage("DATA", message, distribution, nil, priority)
end

-- ── P2P API ──────────────────────────────────────────────────────────────────

-- Broadcast item hashes to the guild, then open the P2P collect window.
-- Peers who have newer data for any listed item will whisper back a hash-offer.
-- @param items     {itemKey → {hash, updatedAt}} — the caller's known item hashes
-- @param priority  "BULK" recommended (large broadcast, not time-critical)
function lib:BroadcastItemHashes(items, priority)
    local message = self:SerializeWithChecksum({ type = "hash-list", items = items })
    if not message then
        self:Debug("COMMS", "ERROR: BroadcastItemHashes — serialization failed")
        return false
    end
    local ok = self:SendMessage("OFFER", message, "GUILD", nil, priority or "BULK")
    if ok and self.p2p then
        self.p2p:BeginCollectWindow(items)
    end
    return ok
end

-- Whisper a hash-offer to a peer who just broadcast their hash-list.
-- Only sends items where our updatedAt is strictly greater than the peer's.
-- @param target    player name (the broadcaster)
-- @param items     {itemKey → {hash, updatedAt}} — items we can supply
-- @param priority  "NORMAL" (default)
function lib:SendHashOffer(target, items, priority)
    local message = self:SerializeWithChecksum({ type = "hash-offer", items = items })
    if not message then return false end
    return self:SendMessage("OFFER", message, "WHISPER", target, priority or "NORMAL")
end

-- Send a P2P handshake message (internal; used by P2PSession).
-- @param target    player name
-- @param payload   table with { type, sessionId, ... }
-- @param priority  "NORMAL" (default)
function lib:SendHandshake(target, payload, priority)
    local message = self:SerializeWithChecksum(payload)
    if not message then return false end
    return self:SendMessage("HANDSHAKE", message, "WHISPER", target, priority or "NORMAL")
end

-- ============================================================================
-- SERIALIZATION HELPERS
-- ============================================================================

-- Serialize baseline information for transmission.
-- Uses the same checksum-wrapped AceSer format as all other channels.
-- @param baseline  { hash, version, keys }
-- @return  wire-format string, or nil on failure
function lib:SerializeBaseline(baseline)
    local payload = {
        hash    = (baseline and baseline.hash)    or 0,
        version = (baseline and baseline.version) or 0,
        keys    = (baseline and baseline.keys)    or {},
    }
    return self:SerializeWithChecksum(payload)
end

-- Deserialize baseline information received on the QUERY channel.
-- @param message  wire-format string from SerializeBaseline
-- @return  { hash, version, keys } or nil on integrity failure
function lib:DeserializeBaseline(message)
    local ok, payload = self:DeserializeWithChecksum(message)
    if not ok or type(payload) ~= "table" then
        return nil
    end
    return {
        hash    = payload.hash    or 0,
        version = payload.version or 0,
        keys    = payload.keys    or {},
    }
end

-- Serialize data for transmission
-- Uses checksum-wrapped format for integrity verification
function lib:SerializeData(data)
    return self:SerializeWithChecksum(data)
end

-- Deserialize data from transmission
-- Verifies checksum integrity; returns nil on failure
function lib:DeserializeData(message)
    local ok, result = self:DeserializeWithChecksum(message)
    if not ok then
        return nil
    end
    return result
end

-- ============================================================================
-- CRC / CHECKSUM FRAMEWORK
-- ============================================================================
-- Wire format:  <BuiltinSerialized payload> \030 <checksum> \031END
--
-- Two independent integrity checks run on receive:
--   1. Stop-marker check (O(k)):  was the message fully delivered (not truncated)?
--   2. CRC check (O(N)):          was the message content uncorrupted?
--
-- When both checks disagree (stop present but CRC fails) the message experienced
-- genuine bit-corruption rather than truncation — the O(N) CRC cannot be dropped.

--- Serialize a value and append checksum + stop-marker.
-- @param data  any Lua value
-- @return      wire-format string, or nil on serialization failure
function lib:SerializeWithChecksum(data)
    local serialized = self:Serialize(data)
    if not serialized then
        return nil
    end
    local checksum = ComputeChecksum(serialized)
    self:Debug("SERIALIZE", "SEND bytes=%d checksum=%d", #serialized, checksum)
    return serialized .. CHECKSUM_SEPARATOR .. tostring(checksum) .. STOP_MARKER
end

--- Deserialize a checksum-wrapped message and verify integrity.
-- Falls back gracefully to raw deserialize for pre-CRC (old-format) messages.
-- @param message  wire-format string from the network
-- @param ctx      optional {sender, prefix, distribution} for diagnostics
-- @return         true + value  on success
--                 false + errmsg on structural failure
function lib:DeserializeWithChecksum(message, ctx)
    if not message or type(message) ~= "string" then
        return false, "invalid message"
    end

    -- === Stop-marker check (O(k)) ===
    local stopMarkerLen = #STOP_MARKER
    local stopPresent   = (string.sub(message, -stopMarkerLen) == STOP_MARKER)
    local body          = stopPresent and string.sub(message, 1, #message - stopMarkerLen) or message

    -- === CRC check (O(N)): locate checksum separator from the end ===
    local sepPos  = nil
    local sepByte = string.byte(CHECKSUM_SEPARATOR)
    for i = #body, 1, -1 do
        if string.byte(body, i) == sepByte then
            sepPos = i
            break
        end
    end

    if not sepPos then
        -- Old-format message (no checksum) — fall back gracefully.
        return self:Deserialize(message)
    end

    local serialized       = string.sub(body, 1, sepPos - 1)
    local checksumStr      = string.sub(body, sepPos + 1)
    local expectedChecksum = tonumber(checksumStr)

    if not expectedChecksum then
        return false, "invalid checksum format"
    end

    local actualChecksum = ComputeChecksum(serialized)
    local crcValid       = (actualChecksum == expectedChecksum)

    -- Log disagreement: stop present but CRC fails = genuine corruption
    if stopPresent and not crcValid then
        local sender = ctx and ctx.sender or "?"
        local pfx    = ctx and ctx.prefix or "?"
        self:Debug("COMMS", string.format(
            "INTEGRITY-MISMATCH stop=PASS crc=FAIL from=%s prefix=%s bytes=%d expected=%d got=%d",
            sender, pfx, #message, expectedChecksum, actualChecksum))
        -- Best-effort: decode the corrupt payload to log its type field.
        local _ok, _decoded = self:Deserialize(serialized)
        local msgType = _ok and (type(_decoded) == "table" and _decoded.type) or "unknown"
        self:Debug("COMMS", "INTEGRITY-MISMATCH PAYLOAD-TYPE '%s'", tostring(msgType))
    end

    if not crcValid then
        return false, string.format("CRC mismatch: expected %d, got %d", expectedChecksum, actualChecksum)
    end

    return self:Deserialize(serialized)
end

-- ============================================================================
-- HASH FUNCTIONS
-- ============================================================================

-- Compute a content hash of any Lua table/value
-- This detects actual content changes, not just timestamp updates
-- @param data: any Lua value (table, string, number, etc.)
-- @return: numeric hash (0 to 2147483647)
function lib:ComputeHash(data)
    if not data then
        return 0
    end
    
    -- Serialize the data structure to a string
    local serialized = SerializeForHash(data)
    
    -- Compute checksum of serialized representation
    return ComputeChecksum(serialized)
end

-- Compute hash for a simple array of items with ID and Count fields
-- This is optimized for common inventory-like structures
-- @param items: array of tables with ID and Count fields
-- @return: numeric hash
function lib:ComputeArrayHash(items)
    if not items or type(items) ~= "table" then
        return 0
    end
    
    -- Build sorted representation for consistent hashing
    local sorted = {}
    for _, item in ipairs(items) do
        if item and item.ID then
            table.insert(sorted, string.format("%d:%d", item.ID, item.Count or 0))
        end
    end
    table.sort(sorted)
    
    local combined = table.concat(sorted, ",")
    return ComputeChecksum(combined)
end

-- Compute hash for a structured data object with named sections
-- @param sections: table where keys are section names and values are arrays
--   Example: { bank = {...}, bags = {...}, mail = {...}, money = 1000 }
-- @return: numeric hash
function lib:ComputeStructuredHash(sections)
    if not sections or type(sections) ~= "table" then
        return 0
    end
    
    local parts = {}
    
    -- Process each section in sorted order for consistency
    local sortedKeys = {}
    for key in pairs(sections) do
        table.insert(sortedKeys, key)
    end
    table.sort(sortedKeys)
    
    for _, key in ipairs(sortedKeys) do
        local value = sections[key]
        local valueType = type(value)
        
        if valueType == "number" then
            -- Simple numeric value
            table.insert(parts, key .. ":" .. tostring(value))
        elseif valueType == "table" then
            -- Array of items - hash them
            local arrayHash = self:ComputeArrayHash(value)
            table.insert(parts, key .. ":" .. tostring(arrayHash))
        end
    end
    
    local combined = table.concat(parts, "|")
    return ComputeChecksum(combined)
end

-- Get the protocol version
-- @return: string version number
function lib:GetProtocolVersion()
    return "1.0.0"
end

-- ============================================================================
-- DEBUG SYSTEM
-- ============================================================================

-- Check if a debug category is enabled
function lib:IsCategoryEnabled(category)
    if not self.debugEnabled or not self.debugSV then
        return false
    end
    
    local debugData = self.debugSV.deltaSyncDebug
    if not debugData or not debugData.categories then
        return false
    end
    
    return debugData.categories[category] == true
end

-- Enable/disable a debug category
function lib:SetCategoryEnabled(category, enabled)
    if not self.debugSV then
        return
    end
    
    if not self.debugSV.deltaSyncDebug then
        self.debugSV.deltaSyncDebug = { categories = {}, tags = {} }
    end
    
    self.debugSV.deltaSyncDebug.categories[category] = enabled
end

-- Check if a debug tag is enabled (opt-out model: nil = enabled)
function lib:IsTagEnabled(category, tag)
    if not self.debugEnabled or not self.debugSV then
        return true
    end
    
    local debugData = self.debugSV.deltaSyncDebug
    if not debugData or not debugData.tags then
        return true
    end
    
    local catTags = debugData.tags[category]
    if not catTags then
        return true  -- No per-tag settings for this category
    end
    
    if catTags[tag] == nil then
        return true  -- Unknown/new tag → show by default
    end
    
    return catTags[tag] == true
end

-- Enable/disable a debug tag
function lib:SetTagEnabled(category, tag, enabled)
    if not self.debugSV then
        return
    end
    
    if not self.debugSV.deltaSyncDebug then
        self.debugSV.deltaSyncDebug = { categories = {}, tags = {} }
    end
    
    local debugData = self.debugSV.deltaSyncDebug
    if not debugData.tags[category] then
        debugData.tags[category] = {}
    end
    
    debugData.tags[category][tag] = enabled
end

-- Get or create debug chat frame
function lib:GetDebugFrame()
    if self.debugFrame then
        return self.debugFrame
    end
    
    -- Search for existing frame by name
    local tabName = self.debugAddonName .. " Debug"
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.name == tabName then
            self.debugFrame = frame
            return frame
        end
    end
    
    return nil
end

-- Create dedicated debug chat tab
function lib:CreateDebugTab()
    if self.debugFrame then
        return  -- Already created
    end
    
    local tabName = self.debugAddonName .. " Debug"
    
    -- Check if tab already exists
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.name == tabName then
            self.debugFrame = frame
            return
        end
    end
    
    -- Find first available chat frame slot
    local frameIndex = nil
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame and not frame:IsShown() and frame.name == "" then
            frameIndex = i
            break
        end
    end
    
    if not frameIndex then
        -- No available slots, use default chat
        return
    end
    
    local frame = _G["ChatFrame" .. frameIndex]
    if not frame then
        return
    end
    
    -- Configure the frame
    FCF_SetWindowName(frame, tabName)
    FCF_DockFrame(frame)
    frame:Show()
    
    self.debugFrame = frame
    
    -- Hook OnShow to redraw messages when tab becomes visible
    frame:HookScript("OnShow", function()
        self:RedrawDebugMessages()
    end)
end

-- Remove debug chat tab
function lib:RemoveDebugTab()
    local frame = self:GetDebugFrame()
    if not frame then
        return
    end
    
    -- Clear the frame
    FCF_Close(frame)
    self.debugFrame = nil
end

-- Store debug message in buffer
function lib:BufferDebugMessage(message)
    table.insert(self.debugMessageBuffer, message)
    
    -- Simple circular buffer: remove oldest if we exceed max
    while #self.debugMessageBuffer > self.maxBufferSize do
        table.remove(self.debugMessageBuffer, 1)
    end
end

-- Redraw all buffered debug messages
function lib:RedrawDebugMessages()
    local frame = self:GetDebugFrame()
    if not frame then
        return
    end
    
    -- Clear and redraw
    frame:Clear()
    for _, message in ipairs(self.debugMessageBuffer) do
        frame:AddMessage(message)
    end
end

-- Debug logging with category and optional tag support
-- Usage:
--   Debug("CATEGORY", "TAG", "message %s", arg)  -- [CATEGORY.TAG] prefix
--   Debug("CATEGORY", "message %s", arg)         -- [CATEGORY] prefix
--   Debug("message %s", arg)                     -- Simple debug (no category)
-- @param fmt: category string or format string
-- @param ...: tag + format + args, or format + args, or just args
function lib:Debug(fmt, ...)
    if not self.debugEnabled then
        return
    end
    
    local prefix = nil
    local actualFmt = nil
    local args = nil
    
    -- Check if first arg is a known category
    if type(fmt) == "string" and DEBUG_CATEGORY[fmt] then
        local category = fmt
        
        -- Check if category is enabled
        if not self:IsCategoryEnabled(category) then
            return
        end
        
        local firstArg = select(1, ...)
        
        -- Check if second arg is a known tag for this category
        if type(firstArg) == "string" 
                and DEBUG_TAGS
                and DEBUG_TAGS[category]
                and DEBUG_TAGS[category][firstArg] ~= nil then
            local tag = firstArg
            
            -- Check if tag is enabled
            if not self:IsTagEnabled(category, tag) then
                return
            end
            
            prefix = string.format("|cff888888[%s.%s]|r", category, tag)
            actualFmt = select(2, ...)
            args = {select(3, ...)}
        else
            -- No tag, just category
            prefix = string.format("|cff888888[%s]|r", category)
            actualFmt = firstArg
            args = {select(2, ...)}
        end
    else
        -- No category, simple debug message
        prefix = string.format("|cff888888[%s]|r", self.namespace)
        actualFmt = fmt
        args = {...}
    end
    
    -- Format the message
    local message
    if actualFmt and #args > 0 then
        message = string.format("%s %s", prefix, string.format(actualFmt, unpack(args)))
    elseif actualFmt then
        message = string.format("%s %s", prefix, actualFmt)
    else
        message = prefix
    end
    
    -- Store in buffer
    self:BufferDebugMessage(message)
    
    -- Output to debug frame if available
    local debugFrame = self:GetDebugFrame()
    if debugFrame then
        debugFrame:AddMessage(message)
    else
        -- Fall back to default chat
        print(message)
    end
end

-- ============================================================================
-- CONVENIENCE API (wraps DeltaOperations.lua)
-- ============================================================================

-- Compute delta between old and new data structures
-- @param oldData: previous data state
-- @param newData: current data state
-- @param metadata: optional { version, timestamp, hash }
-- @param options: optional delta options (see ComputeStructuredDelta)
-- @return: delta structure ready for transmission
function lib:ComputeDelta(oldData, newData, metadata, options)
    return self:ComputeStructuredDelta(oldData, newData, metadata, options)
end

-- Apply a received delta to current data
-- @param currentData: your current data state
-- @param delta: delta received from peer
-- @param options: optional apply options (see ApplyStructuredDelta)
-- @return: true if successful, false + error message if failed
function lib:ApplyDelta(currentData, delta, options)
    return self:ApplyStructuredDelta(currentData, delta, options)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Get information about auto-generated prefixes for an addon name
-- Useful for debugging and documentation
-- @param addonName: full addon name
-- @return: table with prefix information
function lib:GetPrefixInfo(addonName)
    addonName = addonName or self.namespace
    local shortName = GenerateShortName(addonName)
    local prefixes = GeneratePrefixes(addonName)
    
    return {
        addonName = addonName,
        shortName = shortName,
        prefixes = prefixes,
        maxLength = MAX_PREFIX_LENGTH,
        usage = {},
    }
end

-- Check if a specific prefix would conflict with existing prefixes
-- @param prefix: prefix to check
-- @return: boolean (true if available, false if conflict)
function lib:IsPrefixAvailable(prefix)
    if not prefix or #prefix > MAX_PREFIX_LENGTH then
        return false
    end
    
    -- Check against our registered prefixes
    for _, registeredPrefix in pairs(self.prefixes or {}) do
        if registeredPrefix == prefix then
            return false
        end
    end
    
    return true
end

-- Get current peer states (for debugging)
-- @return: table of peer states
function lib:GetPeerStates()
    return self.peerStates or {}
end

-- Get communication statistics
-- @return: table with stats
function lib:GetCommStats()
    return {
        registered    = self.commsRegistered  or false,
        prefixes      = self.prefixes         or {},
        peerCount     = self.peerStates       and #self.peerStates or 0,
        useAceComm    = self.useAceComm      or false,
        useAceCommQueue = self.useAceCommQueue or false,
        p2pEnabled    = self.p2p             ~= nil,
    }
end

