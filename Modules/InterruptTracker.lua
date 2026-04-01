-- InterruptTracker
-- Track party member interrupt cooldowns - ExWind-style tracking

local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
    _G.SunderingToolsInterruptTrackerModel,
    "SunderingToolsInterruptTrackerModel must load before InterruptTracker.lua"
)
local SpellDB = assert(
    _G.SunderingToolsCombatTrackSpellDB,
    "SunderingToolsCombatTrackSpellDB must load before InterruptTracker.lua"
)
local CooldownViewerMeta = assert(
    _G.SunderingToolsCooldownViewerMeta,
    "SunderingToolsCooldownViewerMeta must load before InterruptTracker.lua"
)
local Sync = assert(
    _G.SunderingToolsCombatTrackSync,
    "SunderingToolsCombatTrackSync must load before InterruptTracker.lua"
)
local Engine = assert(
    _G.SunderingToolsCombatTrackEngine,
    "SunderingToolsCombatTrackEngine must load before InterruptTracker.lua"
)
local FramePositioning = assert(
    _G.SunderingToolsFramePositioning,
    "SunderingToolsFramePositioning must load before InterruptTracker.lua"
)
local TrackerFrame = assert(
    _G.SunderingToolsTrackerFrame,
    "SunderingToolsTrackerFrame must load before InterruptTracker.lua"
)
local TrackerSettings = assert(
    _G.SunderingToolsTrackerSettings,
    "SunderingToolsTrackerSettings must load before InterruptTracker.lua"
)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local defaultPosX, defaultPosY = Model.GetDefaultPosition()
local HEADER_LABEL = "Interrupts"
local HEADER_TEXTURE = "Interface\\Icons\\Ability_Kick"
local READY_SOUND_DEFAULT = "Interface\\AddOns\\SunderingTools\\sounds\\ready.mp3"
local READY_SOUND_ALT = "Interface\\AddOns\\SunderingTools\\sounds\\ready2.mp3"
local READY_SOUND_OPTIONS = {
    { label = "SunderingTools: Ready 1", value = READY_SOUND_DEFAULT },
    { label = "SunderingTools: Ready 2", value = READY_SOUND_ALT },
}
local READY_SOUND_CHANNELS = {
    "Master",
    "SFX",
    "Music",
    "Ambience",
    "Dialog",
}
local READY_SOUND_VALID_CHANNELS = {}

for _, channel in ipairs(READY_SOUND_CHANNELS) do
    READY_SOUND_VALID_CHANNELS[channel] = true
end

local module = {
    key = "InterruptTracker",
    label = "Interrupt Tracker",
    description = "Track interrupts, sync party data, and adjust layout.",
    order = 10,
    defaults = TrackerSettings.CreateBarDefaults(defaultPosX, defaultPosY, {
        readySoundEnabled = false,
        readySoundPath = READY_SOUND_DEFAULT,
        readySoundChannel = "Master",
    }),
}

local db = addon.db and addon.db.InterruptTracker

-- Local variables
local bars = {}
local activeBars = {} -- [guid] = { bar, unit, name, class, spellID, cd, startTime, specID, role }
local usedBarsList = {} -- Ordered list for layout
local container = nil
local interruptStats = {} -- [guid] = count
local cooldownState = {} -- [guid] = startTime
local trackerTicker = nil
local spellTextureCache = {}
local editModePreview = false
local CreateContainer
local EnsureBarPool
local ConfigureBarPool
local ReLayout
local UpdatePartyData
local UpdateBarVisuals
local StartCooldownTicker
local RegisterPartyWatchers
local RegisterEnemyWatchers

local runtime = {
    engine = Engine.New(),
    partyWatchFrames = {},
    partyPetWatchFrames = {},
    nameplateWatchFrames = {},
    activeEnemyChannels = {},
    lastSelfInterruptTime = 0,
    lastHelloAt = 0,
    lastHelloReplyAt = {},
    lastCorrName = nil,
    lastCorrTime = 0,
    partyUsers = {},
    partyManifests = {},
    noInterruptPlayers = {},
    recentPartyCasts = {},
    lastSelfStateSyncAt = 0,
}
local CHANNEL_MIN_DURATION = 1.0

local function GetCachedSpellTexture(spellID)
    if not spellID then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    if not spellTextureCache[spellID] then
        spellTextureCache[spellID] =
            (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            or (GetSpellTexture and GetSpellTexture(spellID))
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    return spellTextureCache[spellID]
end

local function ShouldShowPreview()
    if not db or not db.enabled then
        return false
    end

    if editModePreview then
        return true
    end

    return db.previewWhenSolo and not IsInGroup() and not IsInRaid() and not next(runtime.partyUsers)
end

local function IsCurrentInstanceAllowed()
    return TrackerSettings.IsBarContextAllowed(db)
end

local function ShouldHideForCombat()
    return db and db.hideOutOfCombat and not editModePreview and not InCombatLockdown()
end

local function HasVisibleBars()
    return next(activeBars) ~= nil
end

local function UpdateContainerVisibility()
    if not container or not db then return end

    if not db.enabled then
        container:Hide()
        return
    end

    if not editModePreview and not ShouldShowPreview() then
        if not IsCurrentInstanceAllowed() or ShouldHideForCombat() then
            container:Hide()
            return
        end
    end

    if editModePreview or ShouldShowPreview() or HasVisibleBars() then
        container:Show()
    else
        container:Hide()
    end
end

local function UpdateEditLabelVisibility(enabled)
    if not container or not container.editLabel then return end

    if enabled then
        container.editLabel:Show()
    else
        container.editLabel:Hide()
    end
end

local function UsesClassColor(moduleDB)
    return moduleDB.useClassColor ~= false
end

local function BlendColor(color, darkness, alpha)
    local r = (color[1] * (1 - darkness)) + (0.08 * darkness)
    local g = (color[2] * (1 - darkness)) + (0.08 * darkness)
    local b = (color[3] * (1 - darkness)) + (0.08 * darkness)
    return r, g, b, alpha or 1
end

local function GetIconOffset()
    return math.min(db.iconSize, db.barHeight) + 2
end

local function GetHeaderHeight()
    if not db or db.showHeader == false then
        return 0
    end

    return 18
end

local function NormalizeReadySoundChannel(channel)
    if type(channel) ~= "string" then
        return "Master"
    end

    channel = channel:match("^%s*(.-)%s*$")
    if channel == "" then
        return "Master"
    end

    if READY_SOUND_VALID_CHANNELS[channel] then
        return channel
    end

    return "Master"
end

local function BuildReadySoundOptions()
    local options = {}
    local seenValues = {}

    for _, option in ipairs(READY_SOUND_OPTIONS) do
        options[#options + 1] = option
        seenValues[option.value] = true
    end

    local sharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
    if sharedMedia and sharedMedia.HashTable then
        local soundTable = sharedMedia:HashTable("sound")
        local orderedLabels = {}

        for label in pairs(soundTable or {}) do
            orderedLabels[#orderedLabels + 1] = label
        end

        table.sort(orderedLabels)

        for _, label in ipairs(orderedLabels) do
            local soundPath = soundTable[label]
            if type(soundPath) == "string" and soundPath ~= "" and not seenValues[soundPath] then
                options[#options + 1] = {
                    label = label,
                    value = soundPath,
                }
                seenValues[soundPath] = true
            end
        end
    end

    return options
end

local function PlayReadySound(soundPath, channel)
    if type(soundPath) ~= "string" or soundPath == "" then
        return
    end

    PlaySoundFile(soundPath, NormalizeReadySoundChannel(channel))
end

function module:GetReadySoundOptions()
    return BuildReadySoundOptions()
end

local function RefreshHeaderLayout()
    if not container or not container.header or not db then
        return
    end

    local headerHeight = GetHeaderHeight()
    if headerHeight <= 0 then
        container.header:Hide()
        return
    end

    local headerWidth = math.max(96, math.min(db.barWidth, 132))
    container.header:ClearAllPoints()
    container.header:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 4)
    container.header:SetSize(headerWidth, headerHeight)

    container.header.bg:SetAllPoints()
    container.header.bg:SetColorTexture(0.14, 0.12, 0.24, 0.88)

    container.header.borderTop:SetPoint("TOPLEFT", container.header, "TOPLEFT", 0, 0)
    container.header.borderTop:SetPoint("TOPRIGHT", container.header, "TOPRIGHT", 0, 0)
    container.header.borderTop:SetHeight(1)
    container.header.borderTop:SetColorTexture(0.35, 0.31, 0.52, 0.9)

    container.header.borderBottom:SetPoint("BOTTOMLEFT", container.header, "BOTTOMLEFT", 0, 0)
    container.header.borderBottom:SetPoint("BOTTOMRIGHT", container.header, "BOTTOMRIGHT", 0, 0)
    container.header.borderBottom:SetHeight(1)
    container.header.borderBottom:SetColorTexture(0, 0, 0, 0.9)

    container.header.icon:SetSize(headerHeight - 4, headerHeight - 4)
    container.header.icon:SetPoint("LEFT", container.header, "LEFT", 2, 0)
    container.header.icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(6552)) or HEADER_TEXTURE)

    container.header.title:ClearAllPoints()
    container.header.title:SetPoint("LEFT", container.header.icon, "RIGHT", 4, 0)
    container.header.title:SetPoint("RIGHT", container.header, "RIGHT", -6, 0)
    container.header.title:SetText(HEADER_LABEL)
    container.header.title:SetTextColor(1.0, 0.84, 0.22)
    container.header.title:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, db.fontSize), "OUTLINE")

    container.header:Show()
end

-- Get unit's spec ID (placeholder - would need LibGroupInSpecT for real implementation)
local function GetUnitSpecID(unit)
    if unit == "player" then
        return GetSpecializationInfo(GetSpecialization() or 1) or 0
    end
    -- For party members, we'd need a library like LibGroupInSpecT
    -- For now, return 0 and rely on role detection
    return 0
end

local function AfterDelay(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

local function ResolveUnitRole(unit)
    if unit == "player" and GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, _, _, _, role = GetSpecializationInfo(specIndex)
            if role and role ~= "" then
                return role
            end
        end
    end

    return UnitGroupRolesAssigned(unit)
end

local function GetUnitInterruptData(unit)
    if not unit or not UnitExists(unit) then
        return nil, 0, "MISSING_UNIT"
    end

    local specID = GetUnitSpecID(unit)
    local _, classToken = UnitClass(unit)
    local role = ResolveUnitRole(unit)
    local powerType = UnitPowerType and UnitPowerType(unit) or nil
    return SpellDB.ResolveAutoInterruptByContext(specID, classToken, role, powerType)
end

local function GetRuntimeUnits()
    local units = {"player"}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
                units[#units + 1] = "raid" .. i
            end
        end
        return units
    end

    for i = 1, 4 do
        units[#units + 1] = "party" .. i
    end

    return units
end

local function BuildRuntimeUnitsForDisplay()
    local units = {"player"}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
                units[#units + 1] = "raid" .. i
            end
        end
        return units
    end

    if IsInGroup() then
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end

    return units
end

local function ShortName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        local short = Ambiguate(name, "short")
        if short and short ~= "" then
            return short
        end
    end

    return string.match(name, "^([^%-]+)") or name
end

local function GetUnitBySender(sender)
    if not sender or sender == "" then
        return nil
    end

    local senderShort = ShortName(sender)
    for _, unit in ipairs(GetRuntimeUnits()) do
        if UnitExists(unit) then
            local unitName = UnitName(unit)
            if unitName == sender or ShortName(unitName) == senderShort then
                return unit
            end
        end
    end

    return nil
end

local function BuildSpellSet(spellIDs)
    local spellSet = {}
    for _, spellID in ipairs(spellIDs or {}) do
        spellSet[spellID] = true
    end
    return spellSet
end

local function GetManifestForUser(shortName)
    if not shortName or shortName == "" then
        return nil
    end

    local manifest = runtime.partyManifests[shortName]
    if not manifest then
        manifest = {
            spells = {},
            received = false,
        }
        runtime.partyManifests[shortName] = manifest
    end

    return manifest
end

local function HasAuthoritativeManifest(shortName)
    local manifest = shortName and runtime.partyManifests[shortName] or nil
    return manifest ~= nil and manifest.received == true
end

local function HasManifestSpell(shortName, spellID)
    local manifest = shortName and runtime.partyManifests[shortName] or nil
    return manifest ~= nil and manifest.spells ~= nil and manifest.spells[spellID] == true
end

local function GetManifestSpellID(shortName)
    local manifest = shortName and runtime.partyManifests[shortName] or nil
    if not manifest or type(manifest.spellList) ~= "table" then
        return nil
    end

    return manifest.spellList[1]
end

local function RegisterInterruptManifest(shortName, spellIDs)
    local manifest = GetManifestForUser(shortName)
    if not manifest then
        return nil
    end

    manifest.spellList = {}
    for _, spellID in ipairs(spellIDs or {}) do
        local trackedSpell = SpellDB.GetTrackedSpell(spellID)
        if trackedSpell and trackedSpell.kind == "INT" then
            manifest.spellList[#manifest.spellList + 1] = spellID
        end
    end

    manifest.spells = BuildSpellSet(manifest.spellList)
    manifest.received = true
    return manifest
end

local function GetLocalInterruptManifest()
    local interruptEntry = select(1, GetUnitInterruptData("player"))
    if not interruptEntry or not interruptEntry.spellID then
        return {}
    end

    local metadata = CooldownViewerMeta.ResolveSpellMetadata(interruptEntry.spellID)
    local manifestSpellID = (metadata and metadata.spellID) or interruptEntry.spellID
    return { manifestSpellID }
end

local function GetEntryRemaining(entry, now)
    if type(entry) ~= "table" then
        return 0
    end

    now = now or GetTime()
    local readyAt = entry.readyAt or 0
    if type(readyAt) ~= "number" or readyAt <= 0 then
        return 0
    end

    return math.max(0, readyAt - now)
end

local function FindGroupUnitByShortName(shortName)
    if not shortName then
        return nil
    end

    for _, unit in ipairs(GetRuntimeUnits()) do
        if UnitExists(unit) and ShortName(UnitName(unit)) == shortName then
            return unit
        end
    end

    return nil
end

local function GetEntryCooldown(entry)
    if type(entry) ~= "table" then
        return 0
    end

    return entry.baseCd or entry.cd or 0
end

local function ResolveLocalMetadataSpellID(spellID)
    local metadata = CooldownViewerMeta.ResolveSpellMetadata(spellID)
    if metadata and type(metadata.spellID) == "number" and metadata.spellID > 0 then
        return metadata.spellID
    end

    return spellID
end

local function BuildEntryKey(guid, spellID)
    if not guid or not spellID then
        return nil
    end

    return tostring(guid) .. ":" .. tostring(spellID)
end

local function RemovePartyUser(shortName)
    if not shortName then
        return
    end

    local existing = runtime.partyUsers[shortName]
    runtime.partyUsers[shortName] = nil
    runtime.partyManifests[shortName] = nil

    if existing and existing.guid and existing.spellID then
        runtime.engine:RemoveEntry(BuildEntryKey(existing.guid, existing.spellID))
    end
end

local function RegisterRuntimeInterrupt(unit, spellID, cooldownOverride, options)
    options = options or {}
    if not unit or not UnitExists(unit) then
        return nil
    end

    local guid = UnitGUID(unit)
    local fullName = UnitName(unit)
    local shortName = ShortName(fullName)
    local _, classToken = UnitClass(unit)
    if not guid or not classToken or not shortName then
        return nil
    end

    local resolvedSpellID = spellID and SpellDB.ResolveTrackedSpellID(spellID) or nil
    local trackedSpell = resolvedSpellID and SpellDB.GetTrackedSpell(resolvedSpellID) or nil
    if trackedSpell and trackedSpell.kind ~= "INT" then
        return nil
    end

    local resolvedInterrupt, resolvedSpecID, suppressReason = GetUnitInterruptData(unit)
    if suppressReason == "HEALER_SUPPRESSED" and not trackedSpell then
        runtime.noInterruptPlayers[shortName] = true
        RemovePartyUser(shortName)
        return nil
    end

    runtime.noInterruptPlayers[shortName] = nil

    resolvedSpellID = resolvedSpellID or (resolvedInterrupt and resolvedInterrupt.spellID)
    if not resolvedSpellID then
        return nil
    end

    local resolvedSource = options.source or (options.auto and "auto" or "sync")
    local role = ResolveUnitRole(unit)
    local cooldown = cooldownOverride
        or (resolvedInterrupt and resolvedInterrupt.spellID == resolvedSpellID and resolvedInterrupt.cd)
        or (trackedSpell and trackedSpell.cd)
        or 0
    local startTime = options.startTime or 0
    local readyAt = options.readyAt
    if readyAt == nil and startTime > 0 and cooldown > 0 then
        readyAt = startTime + cooldown
    end
    local spellInfo = SpellDB.GetTrackedSpell(resolvedSpellID) or resolvedInterrupt or {}
    local user = runtime.partyUsers[shortName] or {}

    user.guid = guid
    user.unitToken = unit
    user.name = shortName
    user.class = classToken
    user.role = role
    user.spellID = resolvedSpellID
    user.spellName = spellInfo.name or user.spellName or shortName
    user.baseCd = cooldown
    user.specID = resolvedSpecID or user.specID or 0
    user._auto = options.auto == true
    if readyAt ~= nil then
        user.cdEnd = readyAt
    else
        user.cdEnd = user.cdEnd or 0
    end

    runtime.partyUsers[shortName] = user

    local runtimeEntry = runtime.engine:UpsertEntry({
        key = BuildEntryKey(guid, resolvedSpellID),
        playerGUID = guid,
        playerName = shortName,
        classToken = classToken,
        unitToken = unit,
        spellID = resolvedSpellID,
        kind = "INT",
        role = role,
        specID = resolvedSpecID or 0,
        baseCd = cooldown,
        cd = cooldown,
        source = resolvedSource,
        startTime = startTime,
        readyAt = readyAt,
    })

    return runtimeEntry
end

local function RefreshRuntimePartyRegistration()
    RegisterRuntimeInterrupt("player", nil, nil, {
        auto = false,
        source = "self",
    })

    if not IsInGroup() or IsInRaid() then
        return
    end

    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            RegisterRuntimeInterrupt(unit, nil, nil, {
                auto = true,
                source = "auto",
            })
        end
    end
end

local function UpdateEngineEntryTiming(runtimeKey, source, startTime, readyAt)
    if not runtimeKey then
        return
    end

    runtime.engine:UpsertEntry({
        key = runtimeKey,
        source = source,
        startTime = startTime,
        readyAt = readyAt,
    })
end

local function BuildRuntimeBarEntries()
    local entries = {}
    local now = GetTime()

    for _, unit in ipairs(BuildRuntimeUnitsForDisplay()) do
        if UnitExists(unit) then
            local shortName = ShortName(UnitName(unit))
            local guid = UnitGUID(unit)
            local user = shortName and runtime.partyUsers[shortName] or nil

            if user and guid then
                local startTime = 0
                if (user.cdEnd or 0) > now and (user.baseCd or 0) > 0 then
                    startTime = user.cdEnd - user.baseCd
                end

                if startTime <= 0 then
                    startTime = cooldownState[guid] or 0
                end

                local ready = startTime <= 0 or (user.cdEnd or 0) <= now
                if not (ready and db.showReady == false) then
                    entries[#entries + 1] = {
                        key = guid,
                        runtimeKey = BuildEntryKey(guid, user.spellID),
                        unit = unit,
                        partyName = shortName,
                        name = user.name or shortName,
                        class = user.class,
                        role = user.role,
                        spellID = user.spellID,
                        cd = user.baseCd,
                        specID = user.specID,
                        startTime = startTime,
                        source = user._auto and "auto" or "sync",
                    }
                end
            end
        end
    end

    return entries
end

local function RecordInterruptStat(guid)
    if guid then
        interruptStats[guid] = (interruptStats[guid] or 0) + 1
    end
end

local function ApplyRuntimeCooldownEntry(entry, countInterrupt)
    if type(entry) ~= "table" or not entry.playerGUID then
        return
    end

    local guid = entry.playerGUID
    local shortName = ShortName(entry.playerName)
    local startTime = entry.startTime or GetTime()
    local cooldown = GetEntryCooldown(entry)
    local readyAt = entry.readyAt
    if readyAt == nil and cooldown > 0 then
        readyAt = startTime + cooldown
    end

    if shortName and runtime.partyUsers[shortName] then
        local user = runtime.partyUsers[shortName]
        user.guid = guid
        user.spellID = entry.spellID or user.spellID
        user.baseCd = cooldown > 0 and cooldown or user.baseCd
        user.class = entry.classToken or user.class
        user.role = entry.role or user.role
        user.specID = entry.specID or user.specID
        user._auto = entry.source == "auto"
        user.cdEnd = readyAt or 0
    end

    cooldownState[guid] = startTime
    UpdateEngineEntryTiming(entry.key, entry.source, startTime, readyAt)

    if countInterrupt then
        RecordInterruptStat(guid)
    end

    local data = activeBars[guid]
    if not data then
        UpdatePartyData()
        data = activeBars[guid]
    end

    if not data then
        return
    end

    data.runtimeKey = entry.key
    data.spellID = entry.spellID or data.spellID
    data.cd = cooldown > 0 and cooldown or data.cd
    data.startTime = startTime
    data.source = entry.source or data.source
    data.role = entry.role or data.role
    data.class = entry.classToken or data.class
    data.name = entry.playerName or data.name

    local bar = data.bar
    bar._trackerData = data
    bar.cooldown:SetValue(0)
    UpdateBarVisuals(bar, data)
    StartCooldownTicker(bar, data)
    ReLayout()
end

local SendCurrentSelfState

local function SendInterruptManifest()
    if not db or not db.enabled or not IsInGroup() then
        return
    end

    Sync.Send("INT_MANIFEST", {
        spells = GetLocalInterruptManifest(),
    })
end

local function AnnouncePresence()
    if not db or not db.enabled or not IsInGroup() then
        return
    end

    local _, classToken = UnitClass("player")
    local specID = GetUnitSpecID("player")
    runtime.lastHelloAt = GetTime()
    Sync.Send("HELLO", {
        classToken = classToken or "UNKNOWN",
        specID = specID,
    })
    SendInterruptManifest()
    SendCurrentSelfState()
end

SendCurrentSelfState = function()
    if not db or not db.enabled or not IsInGroup() then
        return
    end

    local playerGUID = UnitGUID("player")
    if not playerGUID then
        return
    end

    local sentState = false
    for _, entry in ipairs(runtime.engine:GetEntriesByKind("INT")) do
        if entry.playerGUID == playerGUID then
            local remaining = GetEntryRemaining(entry)
            if remaining > 0 then
                Sync.Send("INT", {
                    spellID = entry.spellID,
                    cd = entry.baseCd or entry.cd or 0,
                    remaining = remaining,
                })
                sentState = true
            end
        end
    end

    if sentState then
        runtime.lastSelfStateSyncAt = GetTime()
    end
end

local function MaybeBroadcastSelfState()
    if not db or not db.enabled or not IsInGroup() then
        return
    end

    local now = GetTime()
    if runtime.lastSelfStateSyncAt > 0 and (now - runtime.lastSelfStateSyncAt) < 4.5 then
        return
    end

    SendCurrentSelfState()
end

local function ReplyToHello(senderShort)
    if not db or not db.enabled or not IsInGroup() then
        return
    end

    local now = GetTime()
    if senderShort and senderShort ~= "" then
        local lastReplyAt = runtime.lastHelloReplyAt[senderShort] or 0
        if (now - lastReplyAt) < 5 then
            return
        end
        runtime.lastHelloReplyAt[senderShort] = now
    end

    SendInterruptManifest()
    SendCurrentSelfState()
end

local function HandleSyncHelloMessage(payload, sender)
    if not db or not db.enabled then
        return
    end

    local unit = GetUnitBySender(sender)
    if not unit or unit == "player" then
        return
    end

    local classToken = payload.classToken
    if not classToken or classToken == "" then
        _, classToken = UnitClass(unit)
    end

    local senderShort = ShortName(sender)
    if senderShort and senderShort ~= "" then
        GetManifestForUser(senderShort)
    end

    RegisterRuntimeInterrupt(unit, nil, nil, {
        auto = false,
        source = "auto",
    })

    ReplyToHello(senderShort)
end

local function HandleSyncInterruptManifestMessage(payload, sender)
    if not db or not db.enabled then
        return
    end

    local unit = GetUnitBySender(sender)
    if not unit or unit == "player" then
        return
    end

    local shortName = ShortName(sender)
    if not shortName or shortName == "" then
        return
    end

    local existing = runtime.partyUsers[shortName]
    local manifest = RegisterInterruptManifest(shortName, payload and payload.spells or {})
    local manifestSpellID = manifest and manifest.spellList and manifest.spellList[1] or nil
    if existing and existing.guid and existing.spellID and existing.spellID ~= manifestSpellID then
        runtime.engine:RemoveEntry(BuildEntryKey(existing.guid, existing.spellID))
    end
    if manifestSpellID then
        RegisterRuntimeInterrupt(unit, manifestSpellID, nil, {
            auto = false,
            source = "sync",
        })
    else
        RemovePartyUser(shortName)
    end
end

local function HandleEnemyInterrupted()
    local now = GetTime()
    local selfDelta = runtime.lastSelfInterruptTime > 0 and (now - runtime.lastSelfInterruptTime) or 999
    local sawRecentInterruptCandidate = selfDelta < 1.5

    for name, observedAt in pairs(runtime.recentPartyCasts) do
        local delta = now - observedAt
        if delta <= 1.5 then
            sawRecentInterruptCandidate = true
        end
        if delta > 0.5 then
            runtime.recentPartyCasts[name] = nil
        end
    end

    local applied = runtime.engine:ResolveInterruptWindow(now, {
        windowSize = 0.5,
        selfObservedAt = runtime.lastSelfInterruptTime > 0 and runtime.lastSelfInterruptTime or nil,
        selfWinsTies = true,
        consumeSuppressed = true,
    })

    if applied then
        local resolvedName = applied.playerName or ShortName(UnitName(applied.unitToken))
        if resolvedName and resolvedName ~= "" then
            runtime.recentPartyCasts[resolvedName] = nil
        end

        if runtime.lastCorrName == resolvedName and (now - runtime.lastCorrTime) < 0.2 then
            return
        end

        runtime.lastCorrName = resolvedName
        runtime.lastCorrTime = now

        if resolvedName and resolvedName ~= "" then
            addon:DebugLog("int", "corr", resolvedName, "delta", string.format("%.3f", now - (applied.startTime or now)))
        end

        ApplyRuntimeCooldownEntry(applied, true)
    elseif selfDelta < 1.5 then
        if runtime.lastCorrName == "self" and (now - runtime.lastCorrTime) < 0.2 then
            return
        end

        runtime.lastCorrName = "self"
        runtime.lastCorrTime = now
        addon:DebugLog("int", "corr", "self", "delta", string.format("%.3f", selfDelta))
        runtime.lastSelfInterruptTime = 0
        UpdatePartyData()
    elseif sawRecentInterruptCandidate then
        addon:DebugLog("int", "corr", "miss")
    end
end

local function CanAcceptSyncedInterruptSpell(senderShort, unit, spellID)
    if not unit or type(spellID) ~= "number" or spellID <= 0 then
        return false
    end

    local resolvedSpellID = SpellDB.ResolveTrackedSpellID(spellID)
    if HasAuthoritativeManifest(senderShort) then
        return HasManifestSpell(senderShort, resolvedSpellID)
    end

    local existingUser = senderShort and runtime.partyUsers[senderShort] or nil
    if existingUser and type(existingUser.spellID) == "number" and existingUser.spellID > 0 then
        return SpellDB.ResolveTrackedSpellID(existingUser.spellID) == resolvedSpellID
    end

    local resolvedInterrupt = GetUnitInterruptData(unit)
    if not resolvedInterrupt or type(resolvedInterrupt.spellID) ~= "number" or resolvedInterrupt.spellID <= 0 then
        return false
    end

    return SpellDB.ResolveTrackedSpellID(resolvedInterrupt.spellID) == resolvedSpellID
end

local function ShouldApplyIncomingInterruptSync(unit, spellID, readyAt)
    if not unit or type(spellID) ~= "number" or spellID <= 0 then
        return false
    end

    if type(readyAt) ~= "number" or readyAt <= 0 then
        return false
    end

    local guid = UnitGUID(unit)
    if not guid then
        return false
    end

    local currentEntry = runtime.engine:GetEntry(BuildEntryKey(guid, SpellDB.ResolveTrackedSpellID(spellID)))
    if not currentEntry then
        return true
    end

    local currentReadyAt = tonumber(currentEntry.readyAt) or 0
    if currentReadyAt <= 0 then
        return true
    end

    return readyAt > (currentReadyAt + 0.05)
end

local function BuildEnemyChannelKey(unit)
    if not unit or unit == "" then
        return nil
    end

    local guid = UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        return guid
    end

    return unit
end

local function HandleEnemyChannelStart(unit)
    local key = BuildEnemyChannelKey(unit)
    if not key then
        return
    end

    runtime.activeEnemyChannels[key] = GetTime()
end

local function HandleEnemyChannelStop(unit)
    local key = BuildEnemyChannelKey(unit)
    if not key then
        return
    end

    local startedAt = runtime.activeEnemyChannels[key]
    runtime.activeEnemyChannels[key] = nil
    if startedAt and (GetTime() - startedAt) < CHANNEL_MIN_DURATION then
        HandleEnemyInterrupted()
    end
end

local function CanRecordWatcherTimestamp(ownerUnit)
    if not ownerUnit or not UnitExists(ownerUnit) or not UnitIsPlayer(ownerUnit) then
        return false
    end

    local shortName = ShortName(UnitName(ownerUnit))
    if not shortName or shortName == "" or runtime.noInterruptPlayers[shortName] then
        return false
    end

    local info = runtime.partyUsers[shortName]
    local kickOnCooldown = info and info.cdEnd and (info.cdEnd > GetTime() + 0.5)
    if kickOnCooldown then
        return false
    end

    if info then
        return true
    end

    local resolvedInterrupt = GetUnitInterruptData(ownerUnit)
    return resolvedInterrupt ~= nil
end

local function HandlePartyWatcher(ownerUnit)
    if not db or not db.enabled or not ownerUnit or not UnitExists(ownerUnit) then
        return
    end

    if not CanRecordWatcherTimestamp(ownerUnit) then
        return
    end

    local observedAt = GetTime()
    local shortName = ShortName(UnitName(ownerUnit))
    if shortName and shortName ~= "" then
        runtime.recentPartyCasts[shortName] = observedAt
        runtime.engine:RecordPartyCast(ownerUnit, observedAt)
        addon:DebugLog("int", "party cast", shortName)
    end
end

local function HandleSyncInterruptMessage(message, sender)
    if not db or not db.enabled then
        return
    end

    local unit = GetUnitBySender(sender)
    if not unit or unit == "player" then
        return
    end

    local messageType, payload = Sync.Decode(message)
    if messageType == "HELLO" then
        HandleSyncHelloMessage(payload, sender)
        return
    end

    if messageType == "INT_MANIFEST" then
        HandleSyncInterruptManifestMessage(payload, sender)
        return
    end

    if messageType ~= "INT" then
        return
    end

    local spellID = payload.spellID or 0
    local cooldown = payload.cd or 0
    if spellID <= 0 or cooldown <= 0 then
        return
    end

    spellID = SpellDB.ResolveTrackedSpellID(spellID)

    local senderShort = ShortName(sender)
    if not CanAcceptSyncedInterruptSpell(senderShort, unit, spellID) then
        addon:DebugLog("int", "ignore sync", senderShort or "?", spellID, "identity mismatch")
        return
    end

    local now = GetTime()
    local remaining = payload.remaining
    if type(remaining) ~= "number" or remaining < 0 then
        remaining = cooldown
    end

    local readyAt = remaining > 0 and (now + remaining) or 0
    local startTime = 0
    if readyAt > 0 and cooldown > 0 then
        startTime = readyAt - cooldown
    end

    if not ShouldApplyIncomingInterruptSync(unit, spellID, readyAt) then
        addon:DebugLog("int", "ignore sync", senderShort or "?", spellID, "stale readyAt")
        return
    end

    local registered = RegisterRuntimeInterrupt(unit, spellID, cooldown, {
        auto = false,
        source = "sync",
        startTime = startTime,
        readyAt = readyAt,
    })
    if not registered then
        return
    end

    local applied = runtime.engine:ApplySyncState(UnitGUID(unit), spellID, {
        kind = "INT",
        cd = cooldown,
        remaining = remaining,
        observedAt = now,
    })
    if applied then
        applied.playerName = ShortName(UnitName(unit))
        applied.classToken = select(2, UnitClass(unit))
        applied.unitToken = unit
        ApplyRuntimeCooldownEntry(applied, false)
    end
end

local function UpdateAnchorVisuals(enabled)
    local anchor = module.anchor or container
    TrackerFrame.UpdateEditModeVisuals(anchor, enabled, UpdateEditLabelVisibility)
end

function module:SetEditMode(enabled)
    editModePreview = enabled and true or false
    if db and db.enabled then
        CreateContainer()
        UpdatePartyData()
    end
    UpdateAnchorVisuals(enabled)
end

function module:ResetPosition(moduleDB)
    moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.InterruptTracker)
    if not moduleDB then return end

    FramePositioning.ResetToDefault(self.anchor or container, moduleDB, defaultPosX, defaultPosY)
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
    db = moduleDB

    local function GetEditButtonLabel()
        if addonRef.db.global.editMode and (
            addonRef.db.global.activeEditModule == "InterruptTracker"
            or addonRef.db.global.activeEditModule == "ALL"
        ) then
            return "Lock Tracker"
        end

        return "Open Edit Mode"
    end

    local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
    local stateBody = helpers:CreateSectionHint(panel, "Enable the tracker and place it where you want it.", 520)
    stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

    local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Interrupt Tracker", moduleDB.enabled, function(value)
        addonRef:SetModuleValue("InterruptTracker", "enabled", value)
    end)
    enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

    local editButton = helpers:CreateActionButton(panel, GetEditButtonLabel(), function(self)
        local isActive = addonRef.db.global.editMode and (
            addonRef.db.global.activeEditModule == "InterruptTracker"
            or addonRef.db.global.activeEditModule == "ALL"
        )
        addonRef:SetEditMode(not isActive, isActive and nil or "InterruptTracker")
        self:SetText(GetEditButtonLabel())
        addonRef:RefreshSettings()
    end)

    local resetButton = helpers:CreateActionButton(panel, "Reset Position", function()
        module:ResetPosition(moduleDB)
    end)
    helpers:PlaceRow(enabledBox, editButton, resetButton, -12, 12)

    local stateHint = helpers:CreateSectionHint(panel, "Edit mode lets you move this tracker.", 420)
    stateHint:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -12)

    local behaviorColumn, layoutColumn = helpers:CreateSectionColumns(panel, stateHint, -24)

    local behaviorLabel = helpers:CreateDividerLabel(behaviorColumn, "Behavior", nil, 0)
    local behaviorBody = helpers:CreateSectionHint(behaviorColumn, "Preview, visibility, and ready sound options.", 250)
    behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

    local showReadyBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Ready Bars", moduleDB.showReady ~= false, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showReady", value)
    end)
    showReadyBox:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

    local hideOutOfCombatBox = helpers:CreateInlineCheckbox(behaviorColumn, "Hide Out of Combat", moduleDB.hideOutOfCombat, function(value)
        addonRef:SetModuleValue("InterruptTracker", "hideOutOfCombat", value)
    end)
    hideOutOfCombatBox:SetPoint("TOPLEFT", showReadyBox, "BOTTOMLEFT", 0, -8)

    local tooltipBox = helpers:CreateInlineCheckbox(behaviorColumn, "Tooltip on Hover", moduleDB.tooltipOnHover ~= false, function(value)
        addonRef:SetModuleValue("InterruptTracker", "tooltipOnHover", value)
    end)
    tooltipBox:SetPoint("TOPLEFT", hideOutOfCombatBox, "BOTTOMLEFT", 0, -8)

    local showInDungeonBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in Dungeons", moduleDB.showInDungeon ~= false, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showInDungeon", value)
    end)
    showInDungeonBox:SetPoint("TOPLEFT", tooltipBox, "BOTTOMLEFT", 0, -8)

    local showInWorldBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in World", moduleDB.showInWorld ~= false, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showInWorld", value)
    end)
    showInWorldBox:SetPoint("TOPLEFT", showInDungeonBox, "BOTTOMLEFT", 0, -8)

    local behaviorHint = helpers:CreateSectionHint(
        behaviorColumn,
        "SunderingTools handles sync and fallback automatically while keeping the visible model small.",
        250
    )
    behaviorHint:SetPoint("TOPLEFT", showInWorldBox, "BOTTOMLEFT", 0, -12)

    local readySoundBox = helpers:CreateInlineCheckbox(behaviorColumn, "Play Ready Sound", moduleDB.readySoundEnabled, function(value)
        addonRef:SetModuleValue("InterruptTracker", "readySoundEnabled", value)
    end)
    readySoundBox:SetPoint("TOPLEFT", behaviorHint, "BOTTOMLEFT", 0, -14)

    local readySoundDropdown = helpers:CreateLabeledDropdown(
        behaviorColumn,
        "Ready Sound",
        module:GetReadySoundOptions(),
        moduleDB.readySoundPath,
        210,
        function(value)
            addonRef:SetModuleValue("InterruptTracker", "readySoundPath", value)
        end
    )
    readySoundDropdown:SetPoint("TOPLEFT", readySoundBox, "BOTTOMLEFT", 0, -10)

    local readySoundChannelDropdown = helpers:CreateLabeledDropdown(
        behaviorColumn,
        "Sound Channel",
        READY_SOUND_CHANNELS,
        NormalizeReadySoundChannel(moduleDB.readySoundChannel),
        210,
        function(value)
            addonRef:SetModuleValue("InterruptTracker", "readySoundChannel", value)
        end
    )
    readySoundChannelDropdown:SetPoint("TOPLEFT", readySoundDropdown, "BOTTOMLEFT", 0, -10)

    local layoutLabel = helpers:CreateDividerLabel(layoutColumn, "Layout", nil, 0)
    local layoutBody = helpers:CreateSectionHint(layoutColumn, "Adjust size, spacing, and growth.", 250)
    layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

    local showHeaderBox = helpers:CreateInlineCheckbox(layoutColumn, "Show Header", moduleDB.showHeader ~= false, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showHeader", value)
    end)
    showHeaderBox:SetPoint("TOPLEFT", layoutBody, "BOTTOMLEFT", 0, -12)

    local growDirectionDropdown = helpers:CreateLabeledDropdown(
        layoutColumn,
        "Grow Direction",
        { "DOWN", "UP" },
        moduleDB.growDirection,
        210,
        function(value)
            addonRef:SetModuleValue("InterruptTracker", "growDirection", value)
        end
    )
    growDirectionDropdown:SetPoint("TOPLEFT", showHeaderBox, "BOTTOMLEFT", 0, -10)

    local maxBarsSlider = helpers:CreateLabeledSlider(layoutColumn, "Maximum Bars", 1, 8, 1, moduleDB.maxBars, function(value)
        addonRef:SetModuleValue("InterruptTracker", "maxBars", value)
    end, 250)
    maxBarsSlider:SetPoint("TOPLEFT", growDirectionDropdown, "BOTTOMLEFT", 0, -10)

    local spacingSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Spacing", 0, 12, 1, moduleDB.spacing, function(value)
        addonRef:SetModuleValue("InterruptTracker", "spacing", value)
    end, 250)
    spacingSlider:SetPoint("TOPLEFT", maxBarsSlider, "BOTTOMLEFT", 0, -10)

    local barWidthSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Width", 100, 320, 5, moduleDB.barWidth, function(value)
        addonRef:SetModuleValue("InterruptTracker", "barWidth", value)
    end, 250)
    barWidthSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -10)

    local barHeightSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Height", 16, 40, 1, moduleDB.barHeight, function(value)
        addonRef:SetModuleValue("InterruptTracker", "barHeight", value)
    end, 250)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -10)

    local iconSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Size", 14, 32, 1, moduleDB.iconSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "iconSize", value)
    end, 250)
    iconSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -10)

    local fontSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Font Size", 8, 18, 1, moduleDB.fontSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "fontSize", value)
    end, 250)
    fontSizeSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -10)
end

function module:onConfigChanged(addonRef, moduleDB, key)
    db = moduleDB

    if key == "enabled" then
        if moduleDB.enabled then
            CreateContainer()
            UpdateAnchorVisuals(addonRef.db.global.editMode)
            UpdatePartyData()
        elseif container then
            container:Hide()
        end
        return
    end

    if key == "posX" or key == "posY" then
        FramePositioning.ApplySavedPosition(self.anchor or container, moduleDB, defaultPosX, defaultPosY)
        return
    end

    if not moduleDB.enabled then
        return
    end

    if key == "maxBars" then
        CreateContainer()
        UpdatePartyData()
        return
    end

    if key == "growDirection"
        or key == "spacing"
        or key == "barWidth"
        or key == "barHeight"
        or key == "iconSize"
        or key == "fontSize"
        or key == "showHeader"
        or key == "previewWhenSolo"
        or key == "showInDungeon"
        or key == "showInWorld"
        or key == "hideOutOfCombat"
        or key == "showReady"
        or key == "tooltipOnHover"
        or key == "readySoundEnabled"
        or key == "readySoundPath"
        or key == "readySoundChannel" then
        CreateContainer()
        UpdatePartyData()
    end
end

-- Create a cooldown bar
local function CreateBar(index)
    local bar = CreateFrame("Frame", nil, container)
    bar:SetSize(db.barWidth, db.barHeight)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.iconBorder = bar:CreateTexture(nil, "BORDER")
    bar.iconBorder:SetColorTexture(0, 0, 0, 1)

    bar.borderTop = bar:CreateTexture(nil, "BORDER")
    bar.borderBottom = bar:CreateTexture(nil, "BORDER")
    bar.borderRight = bar:CreateTexture(nil, "BORDER")
    bar.separator = bar:CreateTexture(nil, "BORDER")

    bar.cooldown = CreateFrame("StatusBar", nil, bar)
    bar.cooldown:SetMinMaxValues(0, 1)
    bar.cooldown:SetValue(0)
    bar.cooldown:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.cooldown.bg = bar.cooldown:CreateTexture(nil, "BACKGROUND")
    bar.cooldown.bg:SetAllPoints()
    bar.cooldown.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.nameText:SetJustifyH("LEFT")
    bar.nameText:SetJustifyV("MIDDLE")

    bar.cooldownNameText = bar.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.cooldownNameText:SetJustifyH("LEFT")
    bar.cooldownNameText:SetJustifyV("MIDDLE")

    bar.cooldownText = bar.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.cooldownText:SetJustifyH("RIGHT")
    bar.cooldownText:SetJustifyV("MIDDLE")
    bar.timerText = bar.cooldownText

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if not db or db.tooltipOnHover == false then return end
        local data = self._trackerData
        if not data then return end

        local trackedSpell = SpellDB.GetTrackedSpell(data.spellID)
        local now = GetTime()
        local ready = data.startTime == 0 or (now - data.startTime) >= (data.cd or 0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(data.partyName or data.name or "Unknown", 1, 1, 1)
        if trackedSpell and trackedSpell.name then
            GameTooltip:AddLine(trackedSpell.name, 1, 1, 1)
        end
        if ready then
            GameTooltip:AddLine("Status: Ready", 0.2, 0.95, 0.3)
        else
            local remaining = math.max(0, (data.cd or 0) - (now - data.startTime))
            GameTooltip:AddLine(string.format("Cooldown: %.0fs", remaining), 0.95, 0.6, 0.15)
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar:Hide()
    return bar
end

local function ConfigureBar(bar)
    if not bar or not db then return end

    local borderSize = 1
    local iconSize = math.min(db.iconSize, db.barHeight)
    local statusLeft = iconSize + 3

    bar:SetSize(db.barWidth, db.barHeight)
    bar.icon:SetSize(iconSize, iconSize)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

    bar.iconBorder:ClearAllPoints()
    bar.iconBorder:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 0, 0)
    bar.iconBorder:SetPoint("BOTTOMLEFT", bar.icon, "BOTTOMRIGHT", 0, 0)
    bar.iconBorder:SetWidth(borderSize)

    bar.bg:ClearAllPoints()
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, 0)
    bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    bar.borderTop:ClearAllPoints()
    bar.borderTop:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, 0)
    bar.borderTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar.borderTop:SetHeight(borderSize)
    bar.borderTop:SetColorTexture(0, 0, 0, 1)

    bar.borderBottom:ClearAllPoints()
    bar.borderBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", statusLeft, 0)
    bar.borderBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.borderBottom:SetHeight(borderSize)
    bar.borderBottom:SetColorTexture(0, 0, 0, 1)

    bar.borderRight:ClearAllPoints()
    bar.borderRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -borderSize)
    bar.borderRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, borderSize)
    bar.borderRight:SetWidth(borderSize)
    bar.borderRight:SetColorTexture(0, 0, 0, 1)

    bar.separator:ClearAllPoints()
    bar.separator:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, borderSize)
    bar.separator:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", statusLeft, -borderSize)
    bar.separator:SetWidth(borderSize)
    bar.separator:SetColorTexture(0, 0, 0, 1)

    bar.cooldown:ClearAllPoints()
    bar.cooldown:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, -borderSize)
    bar.cooldown:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
    bar.cooldown.bg:SetColorTexture(0.14, 0.14, 0.16, 0.85)

    bar.nameText:ClearAllPoints()
    bar.nameText:SetPoint("LEFT", bar, "LEFT", statusLeft + 5, 0)
    bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.nameText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
    bar.nameText:SetShadowOffset(1, -1)

    bar.cooldownNameText:ClearAllPoints()
    bar.cooldownNameText:SetPoint("LEFT", bar.cooldown, "LEFT", 5, 0)
    bar.cooldownNameText:SetPoint("RIGHT", bar.cooldownText, "LEFT", -5, 0)
    bar.cooldownNameText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
    bar.cooldownNameText:SetShadowOffset(1, -1)

    bar.cooldownText:ClearAllPoints()
    bar.cooldownText:SetPoint("RIGHT", bar.cooldown, "RIGHT", -5, 0)
    bar.cooldownText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
    bar.cooldownText:SetShadowOffset(1, -1)
end

local function RefreshContainerGeometry()
    if not container or not db then return end

    local visibleCount = math.max(1, math.min(db.maxBars, #usedBarsList))
    local totalHeight = (visibleCount * db.barHeight) + (math.max(0, visibleCount - 1) * db.spacing)
    container:SetSize(db.barWidth, math.max(db.barHeight, totalHeight))
    RefreshHeaderLayout()
end

local function EnsureBarPool()
    if not container or not db then return end

    for index = 1, db.maxBars do
        if not bars[index] then
            bars[index] = CreateBar(index)
        end
    end

    for index = db.maxBars + 1, #bars do
        if bars[index] then
            bars[index]:Hide()
        end
    end
end

ConfigureBarPool = function()
    if not container or not db then return end

    EnsureBarPool()
    for index = 1, db.maxBars do
        if bars[index] then
            ConfigureBar(bars[index])
        end
    end

    RefreshContainerGeometry()
end

-- Update bar visuals
UpdateBarVisuals = function(bar, data)
    if not bar or not data then return end

    local now = GetTime()
    local isReady = data.startTime == 0 or (now - data.startTime) >= (data.cd or 0)
    local remaining = math.max(0, (data.cd or 0) - (now - data.startTime))
    local progress = 0
    local classColor
    local textOffset = GetIconOffset() + 5
    local readyTextColor = { 1.0, 0.84, 0.22 }
    local activeTextColor = { 1.0, 0.94, 0.74 }

    if UsesClassColor(db) and data.class then
        classColor = Model.GetClassColor(data.class)
    else
        classColor = { 0.45, 0.45, 0.45 }
    end

    if not isReady and (data.cd or 0) > 0 then
        progress = math.max(0, math.min(1, 1 - (remaining / data.cd)))
    end

    bar.icon:SetTexture(GetCachedSpellTexture(data.spellID))
    bar.icon:Show()
    bar.nameText:SetText(data.name or "")
    bar.cooldownNameText:SetText(data.name or "")

    if isReady then
        bar.bg:Show()
        bar.cooldown:Hide()
        bar.bg:SetVertexColor(BlendColor(classColor, 0.18, 0.95))
        bar.nameText:SetTextColor(readyTextColor[1], readyTextColor[2], readyTextColor[3])
        bar.nameText:Show()
        bar.cooldownNameText:Hide()
        bar.nameText:ClearAllPoints()
        bar.nameText:SetPoint("LEFT", bar, "LEFT", textOffset, 0)
        bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.cooldownText:SetText("")
        bar.cooldownText:Hide()
    else
        bar.bg:Hide()
        bar.cooldown:Show()
        bar.cooldown:SetStatusBarColor(BlendColor(classColor, 0.14, 1))
        bar.cooldown:SetValue(data.previewValue or progress)
        bar.nameText:Hide()
        bar.cooldownNameText:SetTextColor(activeTextColor[1], activeTextColor[2], activeTextColor[3])
        bar.cooldownNameText:Show()

        local timerText = data.previewText
        if not timerText then
            timerText = Model.FormatTimerText(remaining)
        end
        if type(timerText) == "table" then
            timerText = timerText[1]
        end
        bar.cooldownText:SetText(timerText or "")
        bar.cooldownText:SetTextColor(activeTextColor[1], activeTextColor[2], activeTextColor[3])
        bar.cooldownText:Show()
    end
end

-- Sort bars: ready bars first, cooling bars by remaining time
local function SortBars()
    local sortList = {}
    for _, data in pairs(activeBars) do
        table.insert(sortList, data)
    end

    Model.SortBars(sortList, GetTime())

    wipe(usedBarsList)
    for _, data in ipairs(sortList) do
        table.insert(usedBarsList, data)
    end
end

-- Layout bars
ReLayout = function()
    if not container then return end

    EnsureBarPool()
    SortBars()
    RefreshContainerGeometry()

    local spacing = db.spacing
    local growUp = (db.growDirection == "UP")
    local growKey = string.format("%s:%d:%d", db.growDirection or "DOWN", db.barHeight or 0, spacing or 0)
    local maxLimit = db.maxBars

    for i, data in ipairs(usedBarsList) do
        if i > maxLimit then
            data.bar:Hide()
        else
            local bar = data.bar
            local yOffset = (i - 1) * (db.barHeight + spacing)
            if growUp then
                yOffset = -yOffset
            end

            if bar._lastLayoutIndex ~= i or bar._lastGrowKey ~= growKey then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)
                bar._lastLayoutIndex = i
                bar._lastGrowKey = growKey
            end
            bar:Show()
        end
    end

    for index = #usedBarsList + 1, #bars do
        if bars[index] then
            bars[index]:Hide()
        end
    end

    UpdateContainerVisibility()
    UpdateEditLabelVisibility(addon.db and addon.db.global and addon.db.global.editMode)
end

-- Create main container
function CreateContainer()
    if container then
        FramePositioning.ApplySavedPosition(container, db, defaultPosX, defaultPosY)
        ConfigureBarPool()
        return
    end

    container = TrackerFrame.CreateContainerShell(
        "SunderingToolsInterruptTracker",
        "Interrupt Tracker",
        function()
            container:StartMoving()
        end,
        function()
            container:StopMovingOrSizing()
            FramePositioning.SaveAbsolutePosition(container, db)
        end
    )
    container.header = CreateFrame("Frame", nil, container)
    container.header.bg = container.header:CreateTexture(nil, "BACKGROUND")
    container.header.borderTop = container.header:CreateTexture(nil, "BORDER")
    container.header.borderBottom = container.header:CreateTexture(nil, "BORDER")
    container.header.icon = container.header:CreateTexture(nil, "ARTWORK")
    container.header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    container.header.title = container.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.header.title:SetJustifyH("CENTER")
    container.header.title:SetJustifyV("MIDDLE")
    container:SetSize(db.barWidth, db.barHeight * db.maxBars)
    FramePositioning.ApplySavedPosition(container, db, defaultPosX, defaultPosY)

    ConfigureBarPool()
    RefreshHeaderLayout()

    module.anchor = container
    UpdateAnchorVisuals(addon.db and addon.db.global and addon.db.global.editMode)
end

local function ResetActiveBars()
    if trackerTicker then
        trackerTicker:Cancel()
        trackerTicker = nil
    end

    for _, data in pairs(activeBars) do
        if data.bar then
            data.bar._trackerData = nil
            data.bar._lastDisplayed = nil
            data.bar:Hide()
        end
    end

    wipe(activeBars)
    wipe(usedBarsList)
end

local HandleCooldownReady

local function RefreshActiveCooldownBars()
    local anyCooling = false
    local needsLayout = false
    local needsRefresh = false

    for _, data in pairs(activeBars) do
        local bar = data.bar
        if bar and (data.startTime or 0) > 0 and (data.cd or 0) > 0 then
            local liveElapsed = GetTime() - data.startTime
            local liveRemaining = data.cd - liveElapsed

            if liveRemaining > 0 then
                anyCooling = true
                bar.cooldown:SetValue(liveElapsed / data.cd)

                local text, displayVal = Model.FormatTimerText(liveRemaining)
                if displayVal ~= bar._lastDisplayed then
                    bar._lastDisplayed = displayVal
                    bar.cooldownText:SetText(text)
                end
            else
                if HandleCooldownReady and HandleCooldownReady(data, bar) then
                    needsLayout = true
                else
                    needsRefresh = true
                end
            end
        end
    end

    if needsRefresh then
        UpdatePartyData()
        return
    end

    if needsLayout then
        ReLayout()
    end

    if anyCooling then
        MaybeBroadcastSelfState()
    end

    if not anyCooling and trackerTicker then
        trackerTicker:Cancel()
        trackerTicker = nil
    end
end

local function StartTrackerTicker()
    if trackerTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end

    trackerTicker = C_Timer.NewTicker(1, function()
        RefreshActiveCooldownBars()
    end)
end

StartCooldownTicker = function(bar, data)
    if not bar or not data then return end

    local startTime = data.startTime or 0
    local cdDuration = data.cd or 0
    local elapsed = GetTime() - startTime
    local remaining = cdDuration - elapsed

    bar._lastDisplayed = nil

    if startTime <= 0 or cdDuration <= 0 or remaining <= 0 then
        data.startTime = 0
        cooldownState[data.key] = nil
        if data.partyName and runtime.partyUsers[data.partyName] then
            runtime.partyUsers[data.partyName].cdEnd = 0
        end
        UpdateEngineEntryTiming(data.runtimeKey, data.source, 0, 0)
        UpdateBarVisuals(bar, data)
        return
    end

    bar.cooldown:SetValue(math.max(0, math.min(1, elapsed / cdDuration)))
    local text, displayVal = Model.FormatTimerText(remaining)
    bar._lastDisplayed = displayVal
    UpdateBarVisuals(bar, data)
    bar.cooldownText:SetText(text)
    StartTrackerTicker()
end

HandleCooldownReady = function(data, bar)
    if not data or not bar then
        return false
    end

    bar.cooldown:SetValue(1)
    data.startTime = 0
    cooldownState[data.key] = nil
    if data.partyName and runtime.partyUsers[data.partyName] then
        runtime.partyUsers[data.partyName].cdEnd = 0
    end
    UpdateEngineEntryTiming(data.runtimeKey, data.source, 0, 0)
    if data.unit == "player" and db.readySoundEnabled then
        if not editModePreview then
            PlayReadySound(db.readySoundPath, db.readySoundChannel)
        end
    end
    if db.showReady == false then
        bar._lastDisplayed = nil
        return false
    end

    bar.cooldownText:SetText("")
    bar._lastDisplayed = nil
    UpdateBarVisuals(bar, data)
    return true
end

local function ShouldDisplaySoloSelfBar()
    if IsInGroup() or IsInRaid() then
        return false
    end

    local playerName = ShortName(UnitName("player"))
    return playerName and runtime.partyUsers[playerName] ~= nil
end

local function PruneRuntimeRoster()
    local currentNames = {}
    local currentGuids = {}
    local playerName = ShortName(UnitName("player"))
    local playerGUID = UnitGUID("player")

    if playerName and playerName ~= "" then
        currentNames[playerName] = true
    end
    if playerGUID then
        currentGuids[playerGUID] = true
    end

    if IsInGroup() then
        for _, unit in ipairs(GetRuntimeUnits()) do
            if UnitExists(unit) then
                local name = ShortName(UnitName(unit))
                local guid = UnitGUID(unit)
                if name and name ~= "" then
                    currentNames[name] = true
                end
                if guid then
                    currentGuids[guid] = true
                end
            end
        end
    end

    for name in pairs(runtime.partyUsers) do
        if not currentNames[name] then
            runtime.partyUsers[name] = nil
        end
    end

    for name in pairs(runtime.noInterruptPlayers) do
        if not currentNames[name] then
            runtime.noInterruptPlayers[name] = nil
        end
    end

    for name in pairs(runtime.partyManifests) do
        if not currentNames[name] then
            runtime.partyManifests[name] = nil
        end
    end

    for name in pairs(runtime.recentPartyCasts) do
        if not currentNames[name] then
            runtime.recentPartyCasts[name] = nil
        end
    end

    for name in pairs(runtime.lastHelloReplyAt) do
        if not currentNames[name] then
            runtime.lastHelloReplyAt[name] = nil
        end
    end

    for _, entry in ipairs(runtime.engine:GetEntriesByKind("INT")) do
        if not currentGuids[entry.playerGUID] then
            runtime.engine:RemoveEntry(entry.key)
        end
    end
end

local function BuildPreviewBars()
    local previewBars = {}
    local now = GetTime()

    for _, previewData in ipairs(Model.BuildPreviewBars()) do
        local startTime = 0
        if (previewData.previewRemaining or 0) > 0 and (previewData.cd or 0) > 0 then
            startTime = now - (previewData.cd - previewData.previewRemaining)
        end

        previewBars[#previewBars + 1] = {
            key = previewData.key,
            name = previewData.name,
            class = previewData.class,
            role = previewData.role,
            spellID = previewData.spellID,
            cd = previewData.cd or 0,
            startTime = startTime,
            previewText = previewData.previewText,
            previewValue = previewData.previewValue,
        }
    end

    return previewBars
end

local function PopulateBars(entries)
    ResetActiveBars()

    local barIndex = 1
    for _, entry in ipairs(entries) do
        if barIndex > db.maxBars or barIndex > #bars then
            break
        end

        local bar = bars[barIndex]
        local barData = {
            key = entry.key,
            runtimeKey = entry.runtimeKey,
            bar = bar,
            unit = entry.unit,
            partyName = entry.partyName,
            name = entry.name,
            class = entry.class,
            role = entry.role,
            spellID = entry.spellID,
            cd = entry.cd,
            specID = entry.specID,
            startTime = entry.startTime or 0,
            previewText = entry.previewText,
            previewValue = entry.previewValue,
            source = entry.source,
        }

        activeBars[barData.key] = barData
        bar._trackerData = barData
        bar._lastDisplayed = nil
        UpdateBarVisuals(bar, barData)
        if (barData.startTime or 0) > 0 then
            StartCooldownTicker(bar, barData)
        end
        barIndex = barIndex + 1
    end

    ReLayout()
end

-- Update party data
function UpdatePartyData()
    if not container then return end

    EnsureBarPool()

    if ShouldShowPreview() then
        PopulateBars(BuildPreviewBars())
        return
    end

    if not IsCurrentInstanceAllowed() or ShouldHideForCombat() then
        ResetActiveBars()
        ReLayout()
        return
    end

    if not IsInGroup() and not ShouldDisplaySoloSelfBar() then
        ResetActiveBars()
        ReLayout()
        return
    end

    PopulateBars(BuildRuntimeBarEntries())
end

-- Trigger cooldown
local function TriggerCooldown(unit)
    local runtimeEntry = RegisterRuntimeInterrupt(unit, nil, nil, {
        auto = unit ~= "player",
        source = unit == "player" and "self" or "auto",
    })
    if not runtimeEntry then
        return
    end

    local cooldown = GetEntryCooldown(runtimeEntry)
    if cooldown <= 0 then
        return
    end

    local guid = UnitGUID(unit)
    if not guid then
        return
    end

    local now = GetTime()
    local applied = runtime.engine:ApplyCorrelatedCast(guid, runtimeEntry.spellID, now, now + cooldown)
    if applied then
        ApplyRuntimeCooldownEntry(applied, true)
    end
end

for i = 1, 4 do
    runtime.partyWatchFrames[i] = CreateFrame("Frame")
    runtime.partyPetWatchFrames[i] = CreateFrame("Frame")
end

RegisterPartyWatchers = function()
    for i = 1, 4 do
        local unit = "party" .. i
        local petUnit = "partypet" .. i
        local ownerUnit = unit

        runtime.partyWatchFrames[i]:UnregisterAllEvents()
        runtime.partyPetWatchFrames[i]:UnregisterAllEvents()

        if UnitExists(unit) then
            runtime.partyWatchFrames[i]:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
            runtime.partyWatchFrames[i]:SetScript("OnEvent", function()
                HandlePartyWatcher(unit)
            end)
        end

        if UnitExists(petUnit) then
            runtime.partyPetWatchFrames[i]:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", petUnit)
            runtime.partyPetWatchFrames[i]:SetScript("OnEvent", function()
                HandlePartyWatcher(ownerUnit)
            end)
        end
    end
end

local enemyWatcherFrame = CreateFrame("Frame")

RegisterEnemyWatchers = function()
    enemyWatcherFrame:RegisterUnitEvent(
        "UNIT_SPELLCAST_INTERRUPTED",
        "target", "focus",
        "boss1", "boss2", "boss3", "boss4", "boss5"
    )
    enemyWatcherFrame:RegisterUnitEvent(
        "UNIT_SPELLCAST_CHANNEL_START",
        "target", "focus",
        "boss1", "boss2", "boss3", "boss4", "boss5"
    )
    enemyWatcherFrame:RegisterUnitEvent(
        "UNIT_SPELLCAST_CHANNEL_STOP",
        "target", "focus",
        "boss1", "boss2", "boss3", "boss4", "boss5"
    )
    enemyWatcherFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            runtime.activeEnemyChannels[BuildEnemyChannelKey(unit)] = nil
            HandleEnemyInterrupted()
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            HandleEnemyChannelStart(unit)
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            HandleEnemyChannelStop(unit)
        end
    end)

    for i = 1, 40 do
        local npUnit = "nameplate" .. i
        if not runtime.nameplateWatchFrames[npUnit] then
            runtime.nameplateWatchFrames[npUnit] = CreateFrame("Frame")
        end

        runtime.nameplateWatchFrames[npUnit]:UnregisterAllEvents()
        runtime.nameplateWatchFrames[npUnit]:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", npUnit)
        runtime.nameplateWatchFrames[npUnit]:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", npUnit)
        runtime.nameplateWatchFrames[npUnit]:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", npUnit)
        runtime.nameplateWatchFrames[npUnit]:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_SPELLCAST_INTERRUPTED" then
                runtime.activeEnemyChannels[BuildEnemyChannelKey(unit or npUnit)] = nil
                HandleEnemyInterrupted()
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                HandleEnemyChannelStart(unit or npUnit)
            elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                HandleEnemyChannelStop(unit or npUnit)
            end
        end)
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        db = addon.db and addon.db.InterruptTracker
        Sync.RegisterPrefix()
        RegisterEnemyWatchers()

        if db and db.enabled then
            CreateContainer()
            UpdatePartyData()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(runtime.partyUsers)
        wipe(runtime.partyManifests)
        wipe(runtime.noInterruptPlayers)
        wipe(runtime.recentPartyCasts)
        wipe(runtime.activeEnemyChannels)
        wipe(cooldownState)
        runtime.engine:Reset()
        runtime.lastSelfInterruptTime = 0
        runtime.lastCorrName = nil
        runtime.lastCorrTime = 0
        runtime.lastHelloAt = 0
        wipe(runtime.lastHelloReplyAt)
        runtime.lastSelfStateSyncAt = 0
        addon:DebugLog("int", "reset runtime", "PLAYER_ENTERING_WORLD")

        AfterDelay(0.3, function()
            RegisterRuntimeInterrupt("player", nil, nil, {
                auto = false,
                source = "self",
            })
            if db and db.enabled then
                UpdatePartyData()
            end
        end)
        AfterDelay(0.5, function()
            RegisterPartyWatchers()
            RefreshRuntimePartyRegistration()
        end)
        AfterDelay(1.5, function()
            if IsInGroup() then
                AnnouncePresence()
            end
        end)

    elseif event == "CHALLENGE_MODE_START" then
        wipe(runtime.partyManifests)
        wipe(runtime.recentPartyCasts)
        wipe(runtime.activeEnemyChannels)
        wipe(cooldownState)
        runtime.engine:Reset()
        runtime.lastHelloAt = 0
        wipe(runtime.lastHelloReplyAt)
        runtime.lastSelfStateSyncAt = 0
        addon:DebugLog("int", "reset runtime", "CHALLENGE_MODE_START")
        AfterDelay(0.5, function()
            RegisterPartyWatchers()
            RefreshRuntimePartyRegistration()
        end)
        AfterDelay(1.0, function()
            if IsInGroup() then
                AnnouncePresence()
            end
        end)
        AfterDelay(4.0, function()
            if IsInGroup() then
                AnnouncePresence()
            end
        end)

    elseif event == "GROUP_ROSTER_UPDATE" then
        addon:DebugLog("int", "group roster update")
        PruneRuntimeRoster()
        RegisterPartyWatchers()
        RefreshRuntimePartyRegistration()
        RegisterRuntimeInterrupt("player", nil, nil, {
            auto = false,
            source = "self",
        })
        AfterDelay(1.5, function()
            if IsInGroup() then
                AnnouncePresence()
            end
        end)

        if db and db.enabled then
            UpdatePartyData()
        end

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if db and db.enabled then
            UpdatePartyData()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not db or not db.enabled then return end

        local unit, _, spellID = ...
        if unit ~= "player" then return end
        if type(spellID) ~= "number" then return end
        local canonicalSpellID = SpellDB.ResolveTrackedSpellID(ResolveLocalMetadataSpellID(spellID))
        local trackedSelfSpell = SpellDB.GetTrackedSpell(canonicalSpellID)

        local function ApplySelfInterrupt(registeredEntry)
            if not registeredEntry or registeredEntry.spellID ~= canonicalSpellID then
                return false
            end

            local now = GetTime()
            local cooldown = GetEntryCooldown(registeredEntry)
            local applied = runtime.engine:ApplySelfCast(UnitGUID("player"), canonicalSpellID, now, now + cooldown)
            runtime.lastSelfInterruptTime = now
            if applied then
                applied.playerName = ShortName(UnitName("player"))
                applied.classToken = select(2, UnitClass("player"))
                applied.unitToken = "player"
                applied.role = registeredEntry.role or ResolveUnitRole("player")
                applied.specID = registeredEntry.specID or 0
                applied.baseCd = cooldown
                applied.cd = cooldown
                ApplyRuntimeCooldownEntry(applied, true)
                addon:DebugLog("int", "self cast", canonicalSpellID, "cd", cooldown)
                if IsInGroup() then
                    addon:DebugLog("int", "send sync", canonicalSpellID, "cd", cooldown, "remaining", cooldown)
                    Sync.Send("INT", {
                        spellID = canonicalSpellID,
                        cd = cooldown,
                        remaining = cooldown,
                    })
                    runtime.lastSelfStateSyncAt = now
                end
            end

            return true
        end

        local interruptEntry = RegisterRuntimeInterrupt("player", nil, nil, {
            auto = false,
            source = "self",
        })
        if not ApplySelfInterrupt(interruptEntry) and trackedSelfSpell and trackedSelfSpell.kind == "INT" then
            local exactEntry = RegisterRuntimeInterrupt("player", canonicalSpellID, nil, {
                auto = false,
                source = "self",
            })
            ApplySelfInterrupt(exactEntry)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix ~= Sync.GetPrefix() then
            return
        end

        local messageType = Sync.Decode(message)
        if messageType == "HELLO" or messageType == "INT" then
            addon:DebugLog("int", "recv sync", sender or "?", message or "")
        end

        HandleSyncInterruptMessage(message, sender)
    end
end)

-- Print interrupt stats
local function PrintInterruptStats()
    print("|cffff00ff========== Interrupt Stats ==========|r")

    if not next(interruptStats) then
        print("|cffaaaaaa(No data)|r")
        return
    end

    local sorted = {}
    for guid, count in pairs(interruptStats) do
        table.insert(sorted, { guid = guid, count = count })
    end

    table.sort(sorted, function(a, b) return a.count > b.count end)

    for _, data in ipairs(sorted) do
        local name = activeBars[data.guid] and activeBars[data.guid].name or "Unknown"
        print(string.format("|cffffffff%s|r: |cff00ff00%d|r interrupts", name, data.count))
    end
end

-- Test command
SLASH_SUNDERINGTOOLS_INT1 = "/su interrupts"
SlashCmdList["SUNDERINGTOOLS_INT"] = function()
    PrintInterruptStats()
end

module.UpdateParty = UpdatePartyData
module.TriggerCD = function(unit) TriggerCooldown(unit) end
module.PrintStats = PrintInterruptStats

addon.InterruptTracker = module
addon:RegisterModule(module)
