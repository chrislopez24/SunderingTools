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
        spacing = 0,
        iconSize = 18,
        barWidth = 175,
        barHeight = 18,
        fontSize = 11,
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

local function UpdateEditLabelVisibility(enabled)
    if not container or not container.editLabel then return end

    if enabled and not HasVisibleBars() then
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
        UpdateEditLabelVisibility(enabled)
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

    local introText = helpers:CreateText(
        panel,
        "OmniCD-style interrupt bars with live preview in Edit Mode.",
        "GameFontHighlight",
        320
    )
    introText:SetPoint("TOPLEFT", 0, 0)

    local enabledBox = helpers:CreateCheckbox(panel, "Enable Interrupt Tracker", moduleDB.enabled, function(value)
        addonRef:SetModuleValue("InterruptTracker", "enabled", value)
    end)
    enabledBox:SetPoint("TOPLEFT", introText, "BOTTOMLEFT", 0, -16)

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

    local iconSizeSlider = helpers:CreateSlider(panel, "Icon Size", 14, 32, 1, moduleDB.iconSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "iconSize", value)
    end, 180)
    iconSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -10)

    local fontSizeSlider = helpers:CreateSlider(panel, "Font Size", 8, 18, 1, moduleDB.fontSize, function(value)
        addonRef:SetModuleValue("InterruptTracker", "fontSize", value)
    end, 180)
    fontSizeSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -10)

    local previewWhenSoloBox = helpers:CreateCheckbox(panel, "Show Preview When Solo", moduleDB.previewWhenSolo, function(value)
        addonRef:SetModuleValue("InterruptTracker", "previewWhenSolo", value)
    end)
    previewWhenSoloBox:SetPoint("TOPLEFT", maxBarsSlider, "TOPRIGHT", 24, -2)

    local helpText = helpers:CreateText(
        panel,
        "Open Edit Mode to move the tracker. Ready bars stay class-colored, and the timer only appears while a kick is recharging.",
        "GameFontHighlight",
        340
    )
    helpText:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -14)
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
        or key == "iconSize"
        or key == "fontSize"
        or key == "previewWhenSolo" then
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

    ConfigureBar(bar)

    bar.icon:SetTexture(C_Spell.GetSpellTexture(data.spellID))
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
    UpdateEditLabelVisibility(addon.db and addon.db.global and addon.db.global.editMode)
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
    bar.cooldown:SetValue(0)

    ReLayout()

    bar:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - data.startTime
        local remaining = cdDuration - elapsed

        if remaining > 0 then
            self.cooldown:SetValue(elapsed / cdDuration)

            local text, displayVal = Model.FormatTimerText(remaining)
            if displayVal ~= self._lastDisplayed then
                self._lastDisplayed = displayVal
                self.cooldownText:SetText(text)
            end

            -- Resort every second while cooling
            local lastUpdate = self._lastSortUpdate or 0
            if elapsed - lastUpdate >= 1.0 then
                self._lastSortUpdate = elapsed
                ReLayout()
            end
        else
            -- Cooldown finished
            self.cooldown:SetValue(1)
            cooldownState[guid] = nil
            self.cooldownText:SetText("")
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
