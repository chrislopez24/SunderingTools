-- InterruptTracker
-- Track party member interrupt cooldowns - ExWind-style tracking

local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
    _G.SunderingToolsInterruptTrackerModel,
    "SunderingToolsInterruptTrackerModel must load before InterruptTracker.lua"
)
local defaultPosX, defaultPosY = Model.GetDefaultPosition()

local module = {
    key = "InterruptTracker",
    label = "Interrupt Tracker",
    order = 10,
    defaults = {
        enabled = true,
        posX = defaultPosX,
        posY = defaultPosY,
        previewWhenSolo = true,
        maxBars = 5,
        growDirection = "DOWN",
        spacing = 2,
        iconSize = 24,
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
local cooldownState = {} -- [guid] = startTime
local editModePreview = false
local CreateContainer
local EnsureBarPool
local ReLayout
local UpdatePartyData
local UpdateBarVisuals

local function ShouldShowPreview()
    if not db or not db.enabled then
        return false
    end

    if editModePreview then
        return true
    end

    return db.previewWhenSolo and (not IsInGroup() or IsInRaid())
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

    if editModePreview or HasVisibleBars() then
        container:Show()
    else
        container:Hide()
    end
end

local function UsesClassColor(moduleDB)
    if moduleDB.useClassColorBar ~= nil then
        return moduleDB.useClassColorBar
    end

    return moduleDB.useClassColor
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
    local _, class = UnitClass(unit)
    return Model.GetInterruptData(specID, class)
end

local function UpdateAnchorVisuals(enabled)
    local anchor = module.anchor or container
    if not anchor then return end

    anchor:EnableMouse(enabled)
    if anchor.dragHandle then
        anchor.dragHandle:EnableMouse(enabled)
        if enabled then
            anchor.dragHandle:Show()
        else
            anchor.dragHandle:Hide()
        end
    end
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

    moduleDB.posX, moduleDB.posY = Model.GetDefaultPosition()

    local anchor = self.anchor or container
    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", moduleDB.posX, moduleDB.posY)
    end
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
    db = moduleDB

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
    resetButton:SetPoint("TOPLEFT", editButton, "TOPRIGHT", 12, 0)

    local maxBarsSlider = helpers:CreateSlider(panel, "Maximum Bars", 1, 8, 1, moduleDB.maxBars, function(value)
        addonRef:SetModuleValue("InterruptTracker", "maxBars", value)
    end, 180)
    maxBarsSlider:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -20)

    local growDirectionDropdown = helpers:CreateDropdown(
        panel,
        "Grow Direction",
        { "DOWN", "UP" },
        moduleDB.growDirection,
        140,
        function(value)
            addonRef:SetModuleValue("InterruptTracker", "growDirection", value)
        end
    )
    growDirectionDropdown:SetPoint("TOPLEFT", maxBarsSlider, "BOTTOMLEFT", -4, -10)

    local spacingSlider = helpers:CreateSlider(panel, "Bar Spacing", 0, 12, 1, moduleDB.spacing, function(value)
        addonRef:SetModuleValue("InterruptTracker", "spacing", value)
    end, 180)
    spacingSlider:SetPoint("TOPLEFT", growDirectionDropdown, "BOTTOMLEFT", 4, -10)

    local barWidthSlider = helpers:CreateSlider(panel, "Bar Width", 100, 320, 5, moduleDB.barWidth, function(value)
        addonRef:SetModuleValue("InterruptTracker", "barWidth", value)
    end, 180)
    barWidthSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -10)

    local barHeightSlider = helpers:CreateSlider(panel, "Bar Height", 16, 40, 1, moduleDB.barHeight, function(value)
        addonRef:SetModuleValue("InterruptTracker", "barHeight", value)
    end, 180)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -10)

    local readyTextInput = helpers:CreateEditBox(panel, "Ready Text", 180, moduleDB.readyText or "", function(value)
        addonRef:SetModuleValue("InterruptTracker", "readyText", value)
    end)
    readyTextInput:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", -4, -8)

    local showIconBox = helpers:CreateCheckbox(panel, "Show Icon", moduleDB.showIcon, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showIcon", value)
    end)
    showIconBox:SetPoint("TOPLEFT", maxBarsSlider, "TOPRIGHT", 24, -2)

    local showNameBox = helpers:CreateCheckbox(panel, "Show Name", moduleDB.showName, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showName", value)
    end)
    showNameBox:SetPoint("TOPLEFT", showIconBox, "BOTTOMLEFT", 0, -8)

    local useClassColorBox = helpers:CreateCheckbox(panel, "Use Class Color", UsesClassColor(moduleDB), function(value)
        addonRef:SetModuleValue("InterruptTracker", "useClassColorBar", value)
    end)
    useClassColorBox:SetPoint("TOPLEFT", showNameBox, "BOTTOMLEFT", 0, -8)

    local showTimerBox = helpers:CreateCheckbox(panel, "Show Timer", moduleDB.showTimer, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showTimer", value)
    end)
    showTimerBox:SetPoint("TOPLEFT", useClassColorBox, "BOTTOMLEFT", 0, -8)

    local showReadyTextBox = helpers:CreateCheckbox(panel, "Show Ready Text", moduleDB.showReadyText, function(value)
        addonRef:SetModuleValue("InterruptTracker", "showReadyText", value)
    end)
    showReadyTextBox:SetPoint("TOPLEFT", showTimerBox, "BOTTOMLEFT", 0, -8)

    local previewWhenSoloBox = helpers:CreateCheckbox(panel, "Show Preview When Solo", moduleDB.previewWhenSolo, function(value)
        addonRef:SetModuleValue("InterruptTracker", "previewWhenSolo", value)
    end)
    previewWhenSoloBox:SetPoint("TOPLEFT", showReadyTextBox, "BOTTOMLEFT", 0, -8)

    local nameFontSlider = helpers:CreateSlider(panel, "Name Font Size", 8, 24, 1, moduleDB.nameFontSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "nameFontSize", value)
    end, 180)
    nameFontSlider:SetPoint("TOPLEFT", previewWhenSoloBox, "BOTTOMLEFT", 4, -14)

    local timerFontSlider = helpers:CreateSlider(panel, "Timer Font Size", 8, 24, 1, moduleDB.timerFontSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "timerFontSize", value)
    end, 180)
    timerFontSlider:SetPoint("TOPLEFT", nameFontSlider, "BOTTOMLEFT", 0, -10)

    local helpText = helpers:CreateText(
        panel,
        "Open Edit Mode to move the tracker. When solo, Edit Mode forces a preview and this option can keep a preview visible outside groups.",
        "GameFontHighlight",
        320
    )
    helpText:SetPoint("TOPLEFT", timerFontSlider, "BOTTOMLEFT", 0, -12)
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
        local anchor = self.anchor or container
        if anchor then
            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", UIParent, "CENTER", moduleDB.posX, moduleDB.posY)
        end
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
        or key == "showIcon"
        or key == "showName"
        or key == "useClassColorBar"
        or key == "showTimer"
        or key == "nameFontSize"
        or key == "timerFontSize"
        or key == "showReadyText"
        or key == "readyText"
        or key == "previewWhenSolo" then
        if key == "useClassColorBar" then
            moduleDB.useClassColor = moduleDB.useClassColorBar
        end
        CreateContainer()
        UpdatePartyData()
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

local function ConfigureBar(bar)
    if not bar or not db then return end

    bar:SetSize(db.barWidth, db.barHeight)
    bar.icon:SetSize(db.barHeight, db.barHeight)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

    bar.nameText:ClearAllPoints()
    if db.showIcon then
        bar.nameText:SetPoint("LEFT", bar, "LEFT", db.barHeight + 5, 0)
    else
        bar.nameText:SetPoint("LEFT", bar, "LEFT", 5, 0)
    end
    bar.nameText:SetFont("Fonts\\FRIZQT__.TTF", db.nameFontSize or db.fontSize, "OUTLINE")

    bar.timerText:ClearAllPoints()
    bar.timerText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.timerText:SetFont("Fonts\\FRIZQT__.TTF", db.timerFontSize or db.fontSize, "OUTLINE")
end

local function RefreshContainerGeometry()
    if not container or not db then return end

    local totalHeight = (db.maxBars * db.barHeight) + (math.max(0, db.maxBars - 1) * db.spacing)
    container:SetSize(db.barWidth, math.max(db.barHeight, totalHeight))
end

local function EnsureBarPool()
    if not container or not db then return end

    for index = 1, db.maxBars do
        if not bars[index] then
            bars[index] = CreateBar(index)
        end
        ConfigureBar(bars[index])
    end

    for index = db.maxBars + 1, #bars do
        if bars[index] then
            bars[index]:Hide()
        end
    end

    RefreshContainerGeometry()
end

-- Update bar visuals
local function UpdateBarVisuals(bar, data)
    if not bar or not data then return end

    ConfigureBar(bar)
    bar:SetValue(data.previewValue or 1)

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
        if UsesClassColor(db) and data.class then
            local color = Model.GetClassColor(data.class)
            bar.nameText:SetTextColor(unpack(color))
        else
            bar.nameText:SetTextColor(1, 1, 1)
        end
        bar.nameText:Show()
    else
        bar.nameText:Hide()
    end

    if db.showTimer then
        if data.previewText then
            bar.timerText:SetText(data.previewText)
        else
            bar.timerText:SetText(db.showReadyText and (db.readyText or "Ready") or "")
        end
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

    EnsureBarPool()
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

    for index = #usedBarsList + 1, #bars do
        if bars[index] then
            bars[index]:Hide()
        end
    end

    UpdateContainerVisibility()
end

-- Create main container
function CreateContainer()
    if container then
        EnsureBarPool()
        RefreshContainerGeometry()
        return
    end

    container = CreateFrame("Frame", "SunderingToolsInterruptTracker", UIParent)
    container:SetSize(db.barWidth, db.barHeight * db.maxBars)
    container:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    container:SetMovable(true)
    container:EnableMouse(false)
    container:RegisterForDrag("LeftButton")

    container.dragHandle = CreateFrame("Frame", nil, container)
    container.dragHandle:SetAllPoints()
    container.dragHandle:SetFrameStrata("HIGH")
    container.dragHandle:EnableMouse(false)
    container.dragHandle:RegisterForDrag("LeftButton")
    container.dragHandle:SetScript("OnDragStart", function()
        container:StartMoving()
    end)
    container.dragHandle:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        local _, _, _, x, y = container:GetPoint()
        db.posX = x
        db.posY = y
    end)
    container.dragHandle:Hide()

    container.editBackdrop = container:CreateTexture(nil, "BACKGROUND")
    container.editBackdrop:SetAllPoints()
    container.editBackdrop:SetColorTexture(0.1, 0.5, 0.9, 0.18)
    container.editBackdrop:Hide()

    container.editLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.editLabel:SetPoint("CENTER")
    container.editLabel:SetText("Interrupt Tracker")
    container.editLabel:Hide()

    EnsureBarPool()

    module.anchor = container
    UpdateAnchorVisuals(addon.db and addon.db.global and addon.db.global.editMode)
end

local function ResetActiveBars()
    for _, data in pairs(activeBars) do
        if data.bar then
            data.bar:SetScript("OnUpdate", nil)
            data.bar._lastDisplayed = nil
            data.bar._lastSortUpdate = nil
            data.bar:Hide()
        end
    end

    wipe(activeBars)
    wipe(usedBarsList)
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
            bar = bar,
            unit = entry.unit,
            name = entry.name,
            class = entry.class,
            role = entry.role,
            spellID = entry.spellID,
            cd = entry.cd,
            specID = entry.specID,
            startTime = entry.startTime or 0,
            previewText = entry.previewText,
            previewValue = entry.previewValue,
        }

        activeBars[barData.key] = barData
        UpdateBarVisuals(bar, barData)
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

    if not IsInGroup() or IsInRaid() then
        ResetActiveBars()
        ReLayout()
        return
    end

    local units = {"player"}
    for i = 1, 4 do
        table.insert(units, "party" .. i)
    end

    local entries = {}
    for _, unit in ipairs(units) do
        if UnitExists(unit) and #entries < db.maxBars then
            local guid = UnitGUID(unit)
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            local interrupt, specID = GetUnitInterruptData(unit)

            if interrupt and guid then
                entries[#entries + 1] = {
                    key = guid,
                    unit = unit,
                    name = name,
                    class = class,
                    role = interrupt.role,
                    spellID = interrupt.spellID,
                    cd = interrupt.cd,
                    specID = specID,
                    startTime = cooldownState[guid] or 0,
                }
            end
        end
    end

    PopulateBars(entries)
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
    cooldownState[guid] = data.startTime
    bar:SetValue(0)

    ReLayout()

    bar:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - data.startTime
        local remaining = cdDuration - elapsed

        if remaining > 0 then
            self:SetValue(elapsed / cdDuration)

            if db.showTimer then
                local text, displayVal = Model.FormatTimerText(remaining)
                if displayVal ~= self._lastDisplayed then
                    self._lastDisplayed = displayVal
                    self.timerText:SetText(text)
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
            cooldownState[guid] = nil
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
