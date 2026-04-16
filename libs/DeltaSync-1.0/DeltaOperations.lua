-- DeltaOperations.lua
-- Delta computation and application logic for DeltaSync
-- Extracted and generalized from TOGBankClassic's DeltaComms module
-- 
-- This module handles:
-- - Computing deltas between two data states (array-based and structured)
-- - Applying deltas to current state
-- - Helper functions for indexing, comparison, and field extraction

local MAJOR, MINOR = "DeltaSync-1.0", 1
local lib = LibStub:GetLibrary(MAJOR)

if not lib then
    error("DeltaOperations requires DeltaSync-1.0 to be loaded first")
    return
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Build an index for fast lookups in an array of objects
-- @param array: array of objects to index
-- @param keyFunc: function to generate key from object (optional, uses obj itself as key)
-- @return: table mapping keys to objects
local function BuildIndex(array, keyFunc)
    local index = {}
    if not array then
        return index
    end
    
    for i, obj in ipairs(array) do
        if obj then
            local key = keyFunc and keyFunc(obj, i) or obj
            if key then
                index[key] = obj
            end
        end
    end
    
    return index
end

-- Default key function for objects (uses table reference)
-- Host addons can override this to use custom keys
local function DefaultKeyFunc(obj, index)
    -- Try common ID-like fields first
    if obj.id then
        return tostring(obj.id)
    elseif obj.ID then
        return tostring(obj.ID)
    elseif obj.key then
        return tostring(obj.key)
    elseif obj.name then
        return tostring(obj.name)
    end
    
    -- Fall back to table reference (works but not stable across sessions)
    return tostring(obj)
end

-- Deep comparison of two objects
-- @param obj1: first object
-- @param obj2: second object
-- @param ignoredFields: table of field names to ignore (optional)
-- @return: true if objects are equal, false otherwise
local function ObjectsEqual(obj1, obj2, ignoredFields)
    if obj1 == obj2 then
        return true
    end
    
    if type(obj1) ~= type(obj2) then
        return false
    end
    
    if type(obj1) ~= "table" then
        return obj1 == obj2
    end
    
    ignoredFields = ignoredFields or {}
    
    -- Compare all fields in obj1
    for k, v in pairs(obj1) do
        if not ignoredFields[k] then
            if type(v) == "table" then
                if not ObjectsEqual(v, obj2[k], ignoredFields) then
                    return false
                end
            else
                if v ~= obj2[k] then
                    return false
                end
            end
        end
    end
    
    -- Check for fields present in obj2 but not in obj1
    for k, v in pairs(obj2) do
        if not ignoredFields[k] and obj1[k] == nil then
            return false
        end
    end
    
    return true
end

-- Get changed fields between two objects
-- @param oldObj: original object
-- @param newObj: updated object
-- @param keyFields: array of fields to always include for identification
-- @return: table containing only changed fields plus key fields
local function GetChangedFields(oldObj, newObj, keyFields)
    local changes = {}
    
    -- Always include key fields for identification
    if keyFields then
        for _, field in ipairs(keyFields) do
            if newObj[field] ~= nil then
                changes[field] = newObj[field]
            end
        end
    end
    
    -- Find changed fields
    for field, newValue in pairs(newObj) do
        if oldObj[field] ~= newValue then
            if type(newValue) == "table" then
                -- Deep comparison for tables
                if not ObjectsEqual(oldObj[field], newValue) then
                    changes[field] = newValue
                end
            else
                changes[field] = newValue
            end
        end
    end
    
    return changes
end

-- ============================================================================
-- ARRAY DELTA OPERATIONS
-- ============================================================================

-- Compute delta between two arrays of objects
-- @param oldArray: original array
-- @param newArray: updated array
-- @param options: table with optional fields:
--   - keyFunc: function(obj, index) to generate unique key for object
--   - equalFunc: function(obj1, obj2) to compare objects for equality
--   - keyFields: array of fields to include in modified entries for identification
-- @return: delta table with added, modified, removed arrays
function lib:ComputeArrayDelta(oldArray, newArray, options)
    local delta = {
        added = {},
        modified = {},
        removed = {}
    }
    
    oldArray = oldArray or {}
    newArray = newArray or {}
    options = options or {}
    
    local keyFunc = options.keyFunc or DefaultKeyFunc
    local equalFunc = options.equalFunc or ObjectsEqual
    local keyFields = options.keyFields or {}
    
    -- Build index for old array
    local oldByKey = BuildIndex(oldArray, keyFunc)
    
    -- Track which old entries have been matched (prevents duplicate matching)
    local matchedOld = {}
    
    -- Find added and modified items
    for i, newObj in ipairs(newArray) do
        if newObj then
            local key = keyFunc(newObj, i)
            local oldObj = oldByKey[key]
            
            if not oldObj then
                -- Object was added
                table.insert(delta.added, newObj)
                self:Debug("DELTA", "COMPUTE", "Added object: %s", tostring(key))
            elseif not equalFunc(oldObj, newObj) then
                -- Object was modified
                local changes = GetChangedFields(oldObj, newObj, keyFields)
                table.insert(delta.modified, changes)
                self:Debug("DELTA", "COMPUTE", "Modified object: %s", tostring(key))
            end
            
            -- Mark as processed
            matchedOld[key] = true
        end
    end
    
    -- Find removed items (anything in old but not matched in new)
    for key, oldObj in pairs(oldByKey) do
        if not matchedOld[key] then
            -- Extract key fields for identification in removal
            local removedEntry = {}
            if keyFields then
                for _, field in ipairs(keyFields) do
                    if oldObj[field] ~= nil then
                        removedEntry[field] = oldObj[field]
                    end
                end
            end
            -- If no key fields extracted, use the whole object
            if next(removedEntry) == nil then
                removedEntry = oldObj
            end
            table.insert(delta.removed, removedEntry)
            self:Debug("DELTA", "COMPUTE", "Removed object: %s", tostring(key))
        end
    end
    
    self:Debug("DELTA", "COMPUTE", "Array delta: +%d ~%d -%d", 
        #delta.added, #delta.modified, #delta.removed)
    
    return delta
end

-- Apply array delta to current array
-- @param currentArray: array to modify (modified in place)
-- @param delta: delta table with added, modified, removed arrays
-- @param options: table with optional fields:
--   - keyFunc: function(obj, index) to generate unique key for object
--   - mergeFunc: function(existingObj, changes) to merge changes into existing object
-- @return: true if successful, false + error message if failed
function lib:ApplyArrayDelta(currentArray, delta, options)
    if not currentArray or not delta then
        return false, "Invalid array or delta"
    end
    
    options = options or {}
    local keyFunc = options.keyFunc or DefaultKeyFunc
    local mergeFunc = options.mergeFunc or function(existing, changes)
        for k, v in pairs(changes) do
            existing[k] = v
        end
    end
    
    -- Build index for current array
    local currentByKey = BuildIndex(currentArray, keyFunc)
    
    -- Process in order: removed → modified → added
    -- This prevents index issues when array is rebuilt
    
    -- STEP 1: Remove items
    if delta.removed then
        for _, removedObj in ipairs(delta.removed) do
            local key = keyFunc(removedObj)
            -- Find and remove from array
            for i = #currentArray, 1, -1 do
                local obj = currentArray[i]
                if obj and keyFunc(obj, i) == key then
                    table.remove(currentArray, i)
                    currentByKey[key] = nil
                    self:Debug("DELTA", "APPLY", "Removed object: %s", tostring(key))
                    break
                end
            end
        end
    end
    
    -- STEP 2: Modify existing items
    if delta.modified then
        for _, changes in ipairs(delta.modified) do
            local key = keyFunc(changes)
            local existingObj = currentByKey[key]
            
            if existingObj then
                -- Apply changes to existing object
                mergeFunc(existingObj, changes)
                self:Debug("DELTA", "APPLY", "Modified object: %s", tostring(key))
            else
                -- Object doesn't exist (shouldn't happen), add as new
                table.insert(currentArray, changes)
                currentByKey[key] = changes
                self:Debug("DELTA", "APPLY", "Modified object not found, added as new: %s", 
                    tostring(key))
            end
        end
    end
    
    -- STEP 3: Add new items
    if delta.added then
        for _, newObj in ipairs(delta.added) do
            local key = keyFunc(newObj)
            local existingObj = currentByKey[key]
            
            if existingObj then
                -- Object already exists, update it (merge)
                mergeFunc(existingObj, newObj)
                self:Debug("DELTA", "APPLY", "Added object already exists, updated: %s", 
                    tostring(key))
            else
                -- Add new object
                table.insert(currentArray, newObj)
                currentByKey[key] = newObj
                self:Debug("DELTA", "APPLY", "Added new object: %s", tostring(key))
            end
        end
    end
    
    self:Debug("DELTA", "APPLY", "Applied array delta: array now has %d items", #currentArray)
    return true
end

-- ============================================================================
-- STRUCTURED DELTA OPERATIONS
-- ============================================================================

-- Compute delta between two structured data objects
-- @param oldData: original data structure
-- @param newData: updated data structure
-- @param metadata: optional metadata to include in delta (version, timestamp, etc.)
-- @param options: table with optional fields:
--   - arrayFields: table of field names that contain arrays (will use ComputeArrayDelta)
--   - scalarFields: table of field names that are scalar values (direct comparison)
--   - arrayOptions: table mapping array field names to options for ComputeArrayDelta
-- @return: delta structure with type="delta" and changes field
function lib:ComputeStructuredDelta(oldData, newData, metadata, options)
    if not newData then
        return nil, "newData is required"
    end
    
    oldData = oldData or {}
    metadata = metadata or {}
    options = options or {}
    
    local delta = {
        type = "delta",
        version = metadata.version or 0,
        timestamp = metadata.timestamp or 0,
        hash = metadata.hash or 0,
        changes = {}
    }
    
    -- Process scalar fields (direct value comparison)
    if options.scalarFields then
        for _, field in ipairs(options.scalarFields) do
            if newData[field] ~= oldData[field] then
                delta.changes[field] = newData[field]
                self:Debug("DELTA", "COMPUTE", "Scalar field '%s' changed: %s → %s",
                    field, tostring(oldData[field]), tostring(newData[field]))
            end
        end
    end
    
    -- Process array fields (compute array deltas)
    if options.arrayFields then
        for _, field in ipairs(options.arrayFields) do
            local oldArray = oldData[field] or {}
            local newArray = newData[field] or {}
            local arrayOptions = options.arrayOptions and options.arrayOptions[field] or {}
            
            local arrayDelta = self:ComputeArrayDelta(oldArray, newArray, arrayOptions)
            
            -- Only include if there are changes
            if #arrayDelta.added > 0 or #arrayDelta.modified > 0 or #arrayDelta.removed > 0 then
                delta.changes[field] = arrayDelta
                self:Debug("DELTA", "COMPUTE", "Array field '%s' changed: +%d ~%d -%d",
                    field, #arrayDelta.added, #arrayDelta.modified, #arrayDelta.removed)
            end
        end
    end
    
    -- Process nested objects (recursive delta computation)
    for field, newValue in pairs(newData) do
        if type(newValue) == "table" and
           (not options.arrayFields or not self:TableContains(options.arrayFields, field)) and
           (not options.scalarFields or not self:TableContains(options.scalarFields, field)) then
            
            local oldValue = oldData[field]
            if not ObjectsEqual(oldValue, newValue) then
                delta.changes[field] = newValue
                self:Debug("DELTA", "COMPUTE", "Nested field '%s' changed", field)
            end
        end
    end
    
    self:Debug("DELTA", "COMPUTE", "Structured delta computed: %d field(s) changed",
        self:TableCount(delta.changes))
    
    return delta
end

-- Apply structured delta to current data
-- @param currentData: data structure to modify (modified in place)
-- @param delta: delta structure with changes field
-- @param options: table with optional fields:
--   - arrayFields: table of field names that contain arrays
--   - arrayOptions: table mapping array field names to options for ApplyArrayDelta
-- @return: true if successful, false + error message if failed
function lib:ApplyStructuredDelta(currentData, delta, options)
    if not currentData or not delta or not delta.changes then
        return false, "Invalid data or delta structure"
    end
    
    options = options or {}
    local success = true
    local errors = {}
    
    -- Apply changes
    for field, change in pairs(delta.changes) do
        -- Check if this is an array field
        local isArrayField = options.arrayFields and self:TableContains(options.arrayFields, field)
        
        if isArrayField and type(change) == "table" and (change.added or change.modified or change.removed) then
            -- This is an array delta, apply it
            if not currentData[field] then
                currentData[field] = {}
            end
            
            local arrayOptions = options.arrayOptions and options.arrayOptions[field] or {}
            local ok, err = self:ApplyArrayDelta(currentData[field], change, arrayOptions)
            
            if not ok then
                success = false
                table.insert(errors, string.format("Failed to apply delta to array field '%s': %s", 
                    field, err))
                self:Debug("DELTA", "APPLY", "ERROR: Failed to apply array delta to '%s': %s",
                    field, err)
            else
                self:Debug("DELTA", "APPLY", "Applied array delta to field '%s'", field)
            end
        else
            -- Scalar or nested object change, apply directly
            currentData[field] = change
            self:Debug("DELTA", "APPLY", "Applied change to field '%s'", field)
        end
    end
    
    if not success then
        return false, table.concat(errors, "; ")
    end
    
    self:Debug("DELTA", "APPLY", "Structured delta applied successfully")
    return true
end

-- ============================================================================
-- DELTA VALIDATION
-- ============================================================================

-- Validate delta structure
-- @param delta: delta to validate
-- @return: true if valid, false + error message if invalid
function lib:ValidateDelta(delta)
    if not delta or type(delta) ~= "table" then
        return false, "delta is not a table"
    end
    
    if delta.type ~= "delta" then
        return false, "invalid delta type (expected 'delta')"
    end
    
    if not delta.changes or type(delta.changes) ~= "table" then
        return false, "missing or invalid changes field"
    end
    
    -- Validate version and timestamp if present
    if delta.version and type(delta.version) ~= "number" then
        return false, "invalid version (must be number)"
    end
    
    if delta.timestamp and type(delta.timestamp) ~= "number" then
        return false, "invalid timestamp (must be number)"
    end
    
    if delta.hash and type(delta.hash) ~= "number" then
        return false, "invalid hash (must be number)"
    end
    
    -- Validate array deltas in changes
    for field, change in pairs(delta.changes) do
        if type(change) == "table" and (change.added or change.modified or change.removed) then
            -- This looks like an array delta, validate it
            if change.added and type(change.added) ~= "table" then
                return false, string.format("invalid added array in field '%s'", field)
            end
            if change.modified and type(change.modified) ~= "table" then
                return false, string.format("invalid modified array in field '%s'", field)
            end
            if change.removed and type(change.removed) ~= "table" then
                return false, string.format("invalid removed array in field '%s'", field)
            end
        end
    end
    
    return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if a table contains a value
-- @param tbl: table to search
-- @param value: value to find
-- @return: true if found, false otherwise
function lib:TableContains(tbl, value)
    if not tbl then
        return false
    end
    
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    
    return false
end

-- Count the number of entries in a table
-- @param tbl: table to count
-- @return: number of entries
function lib:TableCount(tbl)
    if not tbl then
        return 0
    end
    
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    
    return count
end

-- Get delta statistics
-- @param delta: delta structure to analyze
-- @return: table with statistics (added, modified, removed, totalChanges)
function lib:GetDeltaStats(delta)
    if not delta or not delta.changes then
        return {
            added = 0,
            modified = 0,
            removed = 0,
            totalChanges = 0,
            fields = 0
        }
    end
    
    local stats = {
        added = 0,
        modified = 0,
        removed = 0,
        totalChanges = 0,
        fields = 0
    }
    
    for field, change in pairs(delta.changes) do
        stats.fields = stats.fields + 1
        
        if type(change) == "table" then
            if change.added then
                stats.added = stats.added + #change.added
            end
            if change.modified then
                stats.modified = stats.modified + #change.modified
            end
            if change.removed then
                stats.removed = stats.removed + #change.removed
            end
        else
            stats.modified = stats.modified + 1
        end
    end
    
    stats.totalChanges = stats.added + stats.modified + stats.removed
    
    return stats
end
