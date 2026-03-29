-- InterruptTracker
-- Track party member interrupt cooldowns - ExWind-style tracking

local addon = _G.SunderingTools
if not addon then return end

local Model = dofile("Modules/InterruptTrackerModel.lua")

local module = {
    key = "InterruptTracker",
    label = "Interrupt Tracker",
    order = 10,
    defaults = {
        enabled = true,
        posX = 0,
        posY = -200,
        maxBars = 5,
        growDirection = "DOWN",
        spacing = 2,
        barWidth = 150,
        barHeight = 24,
        showIcon = true,
        showName = true,
        showTimer = true,
        useClassColor = true,
        useClassColorBar = true,
        fontSize = 14,
        nameFontSize = 14,
        timerFontSize = 14,
        showReadyText = false,
        readyText = "Ready",
    },
}

local db = addon.db and addon.db.InterruptTracker

-- Interrupt spell data by specID
local InterruptData = {
    -- Death Knight
    [250] = { spellID = 47528, cd = 12, role = "TANK" }, -- Mind Freeze
    [251] = { spellID = 47528, cd = 12, role = "DAMAGER" },
    [252] = { spellID = 47528, cd = 12, role = "DAMAGER" },
    -- Demon Hunter
    [577] = { spellID = 183752, cd = 15, role = "DAMAGER" }, -- Disrupt
    [581] = { spellID = 183752, cd = 15, role = "TANK" },
    [1480] = { spellID = 183752, cd = 15, role = "DAMAGER" },
    -- Druid
    [103] = { spellID = 106839, cd = 15, role = "DAMAGER" }, -- Skull Bash
    [104] = { spellID = 106839, cd = 15, role = "TANK" },
    -- Evoker
    [1467] = { spellID = 351338, cd = 20, role = "DAMAGER" }, -- Quell
    [1473] = { spellID = 351338, cd = 18, role = "DAMAGER" },
    -- Hunter
    [253] = { spellID = 147362, cd = 24, role = "DAMAGER" }, -- Counter Shot
    [254] = { spellID = 147362, cd = 24, role = "DAMAGER" },
    [255] = { spellID = 187707, cd = 15, role = "DAMAGER" }, -- Muzzle
    -- Mage
    [62] = { spellID = 2139, cd = 20, role = "DAMAGER" }, -- Counterspell
    [63] = { spellID = 2139, cd = 20, role = "DAMAGER" },
    [64] = { spellID = 2139, cd = 20, role = "DAMAGER" },
    -- Monk
    [268] = { spellID = 116705, cd = 15, role = "TANK" }, -- Spear Hand Strike
    [269] = { spellID = 116705, cd = 15, role = "DAMAGER" },
    -- Paladin
    [66] = { spellID = 96231, cd = 15, role = "TANK" }, -- Rebuke
    [70] = { spellID = 96231, cd = 15, role = "DAMAGER" },
    -- Priest
    [258] = { spellID = 15487, cd = 30, role = "DAMAGER" }, -- Silence
    -- Rogue
    [259] = { spellID = 1766, cd = 15, role = "DAMAGER" }, -- Kick
    [260] = { spellID = 1766, cd = 15, role = "DAMAGER" },
    [261] = { spellID = 1766, cd = 15, role = "DAMAGER" },
    -- Shaman
    [262] = { spellID = 57994, cd = 12, role = "DAMAGER" }, -- Wind Shear
    [263] = { spellID = 57994, cd = 12, role = "DAMAGER" },
    [264] = { spellID = 57994, cd = 30, role = "HEALER" },
    -- Warlock (pet)
    [265] = { spellID = 19647, cd = 24, role = "DAMAGER" }, -- Spell Lock
    [266] = { spellID = 19647, cd = 30, role = "DAMAGER" },
    [267] = { spellID = 19647, cd = 24, role = "DAMAGER" },
    -- Warrior
    [71] = { spellID = 6552, cd = 15, role = "DAMAGER" }, -- Pummel
    [72] = { spellID = 6552, cd = 15, role = "DAMAGER" },
    [73] = { spellID = 6552, cd = 15, role = "TANK" },
}

-- Event tracking system (ExWind-style)
local pendingEvents = {
    casts = {},      -- [unit] = { time = timestamp }
    interrupts = {}, -- [unit] = { time = timestamp }
    auras = {},      -- [unit] = { time = timestamp }
}
local TIME_WINDOW = 0.100 -- 100ms window for matching events
local processingScheduled = false

-- Local variables
local bars = {}
local activeBars = {} -- [guid] = { bar, unit, name, class, spellID, cd, startTime, specID, role }
local usedBarsList = {} -- Ordered list for layout
local container = nil
local interruptStats = {} -- [guid] = count
local CreateContainer
local UpdatePartyData

-- Get class color
local function GetClassColor(class)
    local colors = {
        ["WARRIOR"] = {0.78, 0.61, 0.43},
        ["PALADIN"] = {0.96, 0.55, 0.73},
        ["HUNTER"] = {0.67, 0.83, 0.45},
        ["ROGUE"] = {1, 0.96, 0.41},
        ["PRIEST"] = {1, 1, 1},
        ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
        ["SHAMAN"] = {0, 0.44, 0.87},
        ["MAGE"] = {0.25, 0.78, 0.92},
        ["WARLOCK"] = {0.53, 0.53, 0.93},
        ["MONK"] = {0, 1, 0.6},
        ["DRUID"] = {1, 0.49, 0.04},
        ["DEMONHUNTER"] = {0.64, 0.19, 0.79},
        ["EVOKER"] = {0.2, 0.58, 0.5},
    }
    return colors[class] or {0.5, 0.5, 0.5}
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

-- Get unit's interrupt data
local function GetUnitInterruptData(unit)
    if not unit then return nil end
    local specID = GetUnitSpecID(unit)

    -- If we have spec data, use it
    if specID and specID > 0 and InterruptData[specID] then
        return InterruptData[specID], specID
    end

    -- Fallback: try to detect by class
    local _, class = UnitClass(unit)
    if class then
        -- Find first matching spec for this class
        for id, data in pairs(InterruptData) do
            -- This is a simplified check - real implementation would need role detection
            return data, id
        end
    end

    return nil, 0
end

local function UpdateAnchorVisuals(enabled)
    local anchor = module.anchor or container
    if not anchor then return end

    anchor:EnableMouse(enabled)
    if anchor.editBackdrop then
        if enabled then
            anchor.editBackdrop:Show()
        else
            anchor.editBackdrop:Hide()
        end
    end

    if anchor.editLabel then
        if enabled then
            anchor.editLabel:Show()
        else
            anchor.editLabel:Hide()
        end
    end

    if enabled then
        anchor:Show()
    end
end

function module:SetEditMode(moduleDB, enabled)
    UpdateAnchorVisuals(enabled)
end

function module:ResetPosition(moduleDB)
    moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.InterruptTracker)
    if not moduleDB then return end

    moduleDB.posX = 0
    moduleDB.posY = -200

    local anchor = self.anchor or container
    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", moduleDB.posX, moduleDB.posY)
    end
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
    local preview = helpers:CreatePreview(panel, Model.BuildPreviewBars(), moduleDB)
    preview:SetPoint("TOPLEFT", 0, 0)

    local enabledBox = helpers:CreateCheckbox(panel, "Enable Interrupt Tracker", moduleDB.enabled, function(value)
        addonRef:SetModuleValue("InterruptTracker", "enabled", value)
    end)
    enabledBox:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -16)

    local editButton = helpers:CreateButton(panel, "Open Edit Mode", function()
        addonRef:SetEditMode(true)
    end)
    editButton:SetPoint("TOPLEFT", enabledBox, "BOTTOMLEFT", 4, -12)

    local resetButton = helpers:CreateButton(panel, "Reset Position", function()
        module:ResetPosition(moduleDB)
    end)
    resetButton:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -8)
end

function module:onConfigChanged(addonRef, moduleDB, key)
    db = moduleDB

    if key == "enabled" then
        if moduleDB.enabled then
            CreateContainer()
            container:Show()
            UpdateAnchorVisuals(addonRef.db.global.editMode)
            UpdatePartyData()
        elseif container then
            container:Hide()
        end
    end
end

-- Create a cooldown bar
local function CreateBar(index)
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetSize(db.barWidth, db.barHeight)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.2)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

    -- Icon
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(db.barHeight, db.barHeight)
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Name text
    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.nameText:SetPoint("LEFT", bar, "LEFT", db.barHeight + 5, 0)
    bar.nameText:SetFont("Fonts\\FRIZQT__.TTF", db.nameFontSize or db.fontSize, "OUTLINE")

    -- Timer text
    bar.timerText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.timerText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.timerText:SetFont("Fonts\\FRIZQT__.TTF", db.timerFontSize or db.fontSize, "OUTLINE")

    bar:Hide()
    return bar
end

-- Update bar visuals
local function UpdateBarVisuals(bar, data)
    if not bar or not data then return end

    -- Update icon
    if db.showIcon then
        bar.icon:SetTexture(C_Spell.GetSpellTexture(data.spellID))
        bar.icon:Show()
    else
        bar.icon:Hide()
    end

    -- Update name
    if db.showName then
        bar.nameText:SetText(data.name or "")
        if (db.useClassColorBar or db.useClassColor) and data.class then
            local color = GetClassColor(data.class)
            bar.nameText:SetTextColor(unpack(color))
        else
            bar.nameText:SetTextColor(1, 1, 1)
        end
        bar.nameText:Show()
    else
        bar.nameText:Hide()
    end

    if db.showTimer then
        bar.timerText:SetText(db.showReadyText and (db.readyText or "Ready") or "")
        bar.timerText:Show()
    else
        bar.timerText:Hide()
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
local function ReLayout()
    if not container then return end

    SortBars()

    local spacing = db.spacing
    local growUp = (db.growDirection == "UP")
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

            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)
            bar:Show()
        end
    end
end

-- Create main container
function CreateContainer()
    if container then return end

    container = CreateFrame("Frame", "SunderingToolsInterruptTracker", UIParent)
    container:SetSize(db.barWidth, db.barHeight * db.maxBars)
    container:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    container:SetMovable(true)
    container:EnableMouse(false)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", container.StartMoving)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.posX = x
        db.posY = y
    end)

    container.editBackdrop = container:CreateTexture(nil, "BACKGROUND")
    container.editBackdrop:SetAllPoints()
    container.editBackdrop:SetColorTexture(0.1, 0.5, 0.9, 0.18)
    container.editBackdrop:Hide()

    container.editLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.editLabel:SetPoint("CENTER")
    container.editLabel:SetText("Interrupt Tracker")
    container.editLabel:Hide()

    -- Create bars pool
    for i = 1, db.maxBars do
        bars[i] = CreateBar(i)
    end

    module.anchor = container
    UpdateAnchorVisuals(addon.db and addon.db.global and addon.db.global.editMode)
end

-- Update party data
function UpdatePartyData()
    if not container then return end

    -- Hide existing bars
    for _, data in pairs(activeBars) do
        if data.bar then
            data.bar:Hide()
        end
    end
    wipe(activeBars)
    wipe(usedBarsList)

    if not IsInGroup() or IsInRaid() then
        ReLayout()
        return
    end

    local units = {"player"}
    for i = 1, 4 do
        table.insert(units, "party" .. i)
    end

    local barIndex = 1
    for _, unit in ipairs(units) do
        if UnitExists(unit) and barIndex <= db.maxBars then
            local guid = UnitGUID(unit)
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            local interrupt, specID = GetUnitInterruptData(unit)

            if interrupt and guid and barIndex <= #bars then
                local bar = bars[barIndex]

                activeBars[guid] = {
                    key = guid,
                    bar = bar,
                    unit = unit,
                    name = name,
                    class = class,
                    role = interrupt.role,
                    spellID = interrupt.spellID,
                    cd = interrupt.cd,
                    specID = specID,
                    startTime = 0,
                }

                UpdateBarVisuals(bar, activeBars[guid])
                barIndex = barIndex + 1
            end
        end
    end

    ReLayout()
end

-- Trigger cooldown
local function TriggerCooldown(unit)
    local guid = UnitGUID(unit)
    if not guid or not activeBars[guid] then return end

    local data = activeBars[guid]
    local bar = data.bar
    local cdDuration = data.cd

    -- Record stat
    interruptStats[guid] = (interruptStats[guid] or 0) + 1

    -- Start cooldown
    data.startTime = GetTime()
    bar:SetValue(0)

    ReLayout()

    bar:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - data.startTime
        local remaining = cdDuration - elapsed

        if remaining > 0 then
            self:SetValue(elapsed / cdDuration)

            if db.showTimer then
                -- Show integer when > 6s, decimal when <= 6s
                if remaining > 6 then
                    local displayVal = math.floor(remaining)
                    if displayVal ~= self._lastDisplayed then
                        self._lastDisplayed = displayVal
                        self.timerText:SetText(string.format("%d", displayVal))
                    end
                else
                    local displayVal = math.floor(remaining * 10)
                    if displayVal ~= self._lastDisplayed then
                        self._lastDisplayed = displayVal
                        self.timerText:SetText(string.format("%.1f", remaining))
                    end
                end
            end

            -- Resort every second while cooling
            local lastUpdate = self._lastSortUpdate or 0
            if elapsed - lastUpdate >= 1.0 then
                self._lastSortUpdate = elapsed
                ReLayout()
            end
        else
            -- Cooldown finished
            self:SetValue(1)
            if db.showTimer then
                if db.showReadyText then
                    self.timerText:SetText(db.readyText or "Ready")
                else
                    self.timerText:SetText("")
                end
            end
            self._lastDisplayed = nil
            self:SetScript("OnUpdate", nil)
            ReLayout()
        end
    end)
end

-- Process pending events (ExWind-style matching)
local function ProcessPendingEvents()
    processingScheduled = false

    local currentTime = GetTime()

    -- Clean old aura records (> 50ms)
    for unit, data in pairs(pendingEvents.auras) do
        if currentTime - data.time > 0.05 then
            pendingEvents.auras[unit] = nil
        end
    end

    -- Check 1: Must have exactly one interrupt (multiple = CC)
    local interruptCount = 0
    local targetUnit = nil
    for unit, _ in pairs(pendingEvents.interrupts) do
        interruptCount = interruptCount + 1
        targetUnit = unit
    end

    if interruptCount == 0 then
        wipe(pendingEvents.interrupts)
        wipe(pendingEvents.casts)
        wipe(pendingEvents.auras)
        return
    end

    -- Multiple interrupts = crowd control, ignore
    if interruptCount > 1 then
        wipe(pendingEvents.interrupts)
        wipe(pendingEvents.casts)
        wipe(pendingEvents.auras)
        return
    end

    -- Check 2: Look for aura changes on the interrupted target (CC detection)
    local interruptTime = pendingEvents.interrupts[targetUnit].time

    if pendingEvents.auras[targetUnit] then
        local auraTime = pendingEvents.auras[targetUnit].time
        local auraDiff = math.abs(interruptTime - auraTime)

        -- If aura changed within 30ms of interrupt, it's probably a CC
        if auraDiff <= 0.030 then
            wipe(pendingEvents.interrupts)
            wipe(pendingEvents.casts)
            wipe(pendingEvents.auras)
            return
        end
    end

    -- Check 3: Find the caster with closest timing
    local caster = nil
    local bestMatch = nil
    local bestTimeDiff = math.huge

    for unit, data in pairs(pendingEvents.casts) do
        local timeDiff = math.abs(interruptTime - data.time)

        if timeDiff <= TIME_WINDOW and timeDiff < bestTimeDiff then
            bestMatch = unit
            bestTimeDiff = timeDiff
        end
    end

    caster = bestMatch

    if caster then
        TriggerCooldown(caster)
    end

    -- Clear event cache
    wipe(pendingEvents.interrupts)
    wipe(pendingEvents.casts)
    wipe(pendingEvents.auras)
end

-- Schedule event processing
local function ScheduleProcessing()
    if processingScheduled then return end
    processingScheduled = true
    C_Timer.After(0.03, ProcessPendingEvents)
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        db = addon.db.InterruptTracker
        if db.enabled then
            CreateContainer()
            UpdatePartyData()
            container:Show()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if db and db.enabled then
            UpdatePartyData()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not db or not db.enabled then return end

        local unit, castGUID, spellID = ...

        -- Only track player and party
        if not (unit == "player" or string.find(unit, "party")) then return end

        -- For player: direct detection by spellID
        if unit == "player" then
            local interruptData = GetUnitInterruptData("player")
            if interruptData and interruptData.spellID == spellID then
                TriggerCooldown("player")
            end
            return
        end

        -- For party: record cast event for time-window matching
        pendingEvents.casts[unit] = { time = GetTime() }
        ScheduleProcessing()

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not db or not db.enabled then return end

        local unit = ...
        -- Only track nameplate units (enemy casts)
        if not string.find(unit, "nameplate") then return end

        pendingEvents.interrupts[unit] = { time = GetTime() }
        ScheduleProcessing()

    elseif event == "UNIT_AURA" then
        if not db or not db.enabled then return end

        local unit = ...
        -- Only track nameplate units
        if not string.find(unit, "nameplate") then return end

        pendingEvents.auras[unit] = { time = GetTime() }
        ScheduleProcessing()
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
