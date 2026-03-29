-- SunderingTools
-- Lightweight interrupt tracker and bloodlust sound

local addonName, addon = ...
_G.SunderingTools = addon

-- Default settings
local defaults = {
    global = {
        minimap = {
            hide = false,
        },
    },
    InterruptTracker = {
        enabled = true,
        showIcon = true,
        showName = true,
        showTimer = true,
        iconSize = 24,
        barWidth = 150,
        barHeight = 24,
        spacing = 2,
        maxBars = 5,
        growDirection = "DOWN",
        posX = 0,
        posY = -200,
        fontSize = 14,
        useClassColor = true,
    },
    BloodlustSound = {
        enabled = true,
        hideIcon = false,
        iconSize = 64,
        posX = 0,
        posY = 100,
        soundFile = "Interface\\AddOns\\SunderingTools\\sounds\\bloodlust.ogg",
        soundChannel = "Master",
        duration = 40,
    }
}

-- Initialize database
function addon:InitDB()
    SunderingToolsDB = SunderingToolsDB or {}
    
    -- Initialize global settings
    SunderingToolsDB.global = SunderingToolsDB.global or {}
    for key, value in pairs(defaults.global) do
        if SunderingToolsDB.global[key] == nil then
            SunderingToolsDB.global[key] = value
        end
    end
    
    -- Initialize module settings
    for module, settings in pairs(defaults) do
        if module ~= "global" then
            SunderingToolsDB[module] = SunderingToolsDB[module] or {}
            for key, value in pairs(settings) do
                if SunderingToolsDB[module][key] == nil then
                    SunderingToolsDB[module][key] = value
                end
            end
        end
    end
    
    self.db = SunderingToolsDB
end

-- Initialize minimap icon
function addon:InitMinimapIcon()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)
    
    if not LDB or not LDBIcon then
        -- Fallback: create a simple minimap button if libraries not available
        self:CreateSimpleMinimapButton()
        return
    end
    
    -- Create LDB data object
    local dataObject = LDB:NewDataObject("SunderingTools", {
        type = "launcher",
        text = "SunderingTools",
        icon = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("|cff00ff00SunderingTools|r")
            tooltip:AddLine("Click to open settings")
            tooltip:AddLine(" ")
            tooltip:AddLine("Interrupt Tracker: Track party interrupts")
            tooltip:AddLine("Bloodlust Sound: Alert on bloodlust/heroism")
        end,
        OnClick = function(_, button)
            if button == "LeftButton" then
                addon:OpenSettings()
            elseif button == "RightButton" then
                -- Quick toggle menu
                addon:ShowQuickMenu()
            end
        end,
    })
    
    -- Register with LibDBIcon
    LDBIcon:Register("SunderingTools", dataObject, self.db.global.minimap)
    self.minimapIcon = LDBIcon
end

-- Simple minimap button (fallback)
function addon:CreateSimpleMinimapButton()
    local button = CreateFrame("Button", "SunderingToolsMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    
    -- Icon
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetTexture("Interface\\Icons\\Ability_Warrior_PunishingBlow")
    
    -- Border
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(54, 54)
    button.border:SetPoint("CENTER", 0, 0)
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Highlight
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            addon:OpenSettings()
        elseif button == "RightButton" then
            addon:ShowQuickMenu()
        end
    end)
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ff00SunderingTools|r")
        GameTooltip:AddLine("Left-click: Open settings")
        GameTooltip:AddLine("Right-click: Quick menu")
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Make draggable around minimap
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            local scale = Minimap:GetEffectiveScale()
            xpos = (xpos / scale - xmin - 70) / 1.1
            ypos = (ypos / scale - ymin - 70) / 1.1
            local angle = math.deg(math.atan2(ypos, xpos))
            self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 54 * cos(angle), -54 * sin(angle))
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    
    self.minimapButton = button
end

-- Show quick toggle menu
function addon:ShowQuickMenu()
    local menu = {
        { text = "|cff00ff00SunderingTools|r", isTitle = true, notCheckable = true },
        { text = "Settings", func = function() addon:OpenSettings() end, notCheckable = true },
        { text = " ", notCheckable = true, disabled = true },
        { 
            text = "Interrupt Tracker", 
            checked = function() return addon.db.InterruptTracker.enabled end,
            func = function() 
                addon.db.InterruptTracker.enabled = not addon.db.InterruptTracker.enabled
                -- Reload module
                ReloadUI()
            end,
            keepShownOnClick = true,
        },
        { 
            text = "Bloodlust Sound", 
            checked = function() return addon.db.BloodlustSound.enabled end,
            func = function() 
                addon.db.BloodlustSound.enabled = not addon.db.BloodlustSound.enabled
            end,
            keepShownOnClick = true,
        },
        { text = " ", notCheckable = true, disabled = true },
        { text = "Test Bloodlust", func = function() 
            if addon.BloodlustSound and addon.BloodlustSound.Play then
                addon.BloodlustSound.Play()
            end
        end, notCheckable = true },
        { text = "Interrupt Stats", func = function() 
            if addon.InterruptTracker and addon.InterruptTracker.PrintStats then
                addon.InterruptTracker.PrintStats()
            end
        end, notCheckable = true },
        { text = " ", notCheckable = true, disabled = true },
        { text = "Close", notCheckable = true },
    }
    
    EasyMenu(menu, CreateFrame("Frame", "SunderingToolsQuickMenu", UIParent, "UIDropDownMenuTemplate"), "cursor", 0, 0, "MENU")
end

-- Register slash commands
SLASH_SUNDERINGTOOLS1 = "/su"
SLASH_SUNDERINGTOOLS2 = "/sundering"
SlashCmdList["SUNDERINGTOOLS"] = function(msg)
    if msg == "reset" then
        SunderingToolsDB = nil
        ReloadUI()
    elseif msg == "config" or msg == "settings" then
        addon:OpenSettings()
    else
        addon:ShowQuickMenu()
    end
end

-- Initialize on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    addon:InitDB()
    addon:InitMinimapIcon()
    print("|cff00ff00SunderingTools|r loaded. Type /su for options.")
end)
