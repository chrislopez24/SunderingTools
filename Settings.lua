-- Settings
-- Native-looking settings UI for SunderingTools

local addon = _G.SunderingTools
if not addon then return end

-- Settings frame
local SettingsFrame = nil

-- Create the main settings window
local function CreateSettingsFrame()
    local frame = CreateFrame("Frame", "SunderingToolsSettings", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(450, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    
    -- Title
    frame.TitleBg:SetHeight(30)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -8)
    frame.title:SetText("|cff00ff00SunderingTools|r Settings")
    
    -- Create scroll frame for content
    frame.ScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    
    -- Content frame
    frame.Content = CreateFrame("Frame")
    frame.Content:SetSize(380, 800)
    frame.ScrollFrame:SetScrollChild(frame.Content)
    
    return frame
end

-- Create a section header
local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    header:SetText(text)
    
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -15, 0)
    line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    
    return yOffset - 35
end

-- Create a checkbox
local function CreateCheckbox(parent, label, checked, onClick, yOffset)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    checkbox.Text:SetText(label)
    checkbox:SetChecked(checked)
    checkbox:SetScript("OnClick", function(self)
        onClick(self:GetChecked())
    end)
    return yOffset - 30
end

-- Create a slider
local function CreateSlider(parent, label, value, minVal, maxVal, onValueChanged, yOffset)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    slider:SetWidth(200)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValue(value)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    
    -- Label
    slider.Label = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slider.Label:SetPoint("BOTTOM", slider, "TOP", 0, 5)
    slider.Label:SetText(label)
    
    -- Value text
    slider.ValueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slider.ValueText:SetPoint("TOP", slider, "BOTTOM", 0, -3)
    slider.ValueText:SetText(tostring(value))
    
    slider:SetScript("OnValueChanged", function(self, value)
        self.ValueText:SetText(tostring(math.floor(value)))
        onValueChanged(value)
    end)
    
    return yOffset - 60
end

-- Create a dropdown (simplified button version)
local function CreateDropdown(parent, label, currentValue, options, onSelect, yOffset)
    -- Label
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    labelText:SetText(label)
    
    -- Button
    local button = CreateFrame("Button", nil, parent, "UIMenuButtonStretchTemplate")
    button:SetSize(150, 25)
    button:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -5)
    button:SetText(currentValue)
    
    button:SetScript("OnClick", function(self)
        local menu = {}
        for _, option in ipairs(options) do
            table.insert(menu, {
                text = option,
                func = function()
                    self:SetText(option)
                    onSelect(option)
                end,
                notCheckable = true,
            })
        end
        EasyMenu(menu, CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate"), self, 0, 0, "MENU")
    end)
    
    return yOffset - 60
end

-- Create a button
local function CreateButton(parent, text, onClick, yOffset, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 25)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return yOffset - 35
end

-- Create input field
local function CreateInput(parent, label, value, onChange, yOffset)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    labelText:SetText(label)
    
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(250, 25)
    editBox:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -5)
    editBox:SetAutoFocus(false)
    editBox:SetText(value or "")
    
    editBox:SetScript("OnEnterPressed", function(self)
        onChange(self:GetText())
        self:ClearFocus()
    end)
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    return yOffset - 60
end

-- Populate settings content
local function PopulateSettings()
    if not SettingsFrame then return end
    
    local content = SettingsFrame.Content
    local yOffset = -10
    
    -- Clear existing content
    for _, child in ipairs({content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- General Section
    yOffset = CreateSectionHeader(content, "General", yOffset)
    
    yOffset = CreateCheckbox(content, "Show Minimap Icon", not addon.db.global.minimap.hide, function(checked)
        addon.db.global.minimap.hide = not checked
        if addon.minimapIcon then
            if checked then
                addon.minimapIcon:Show("SunderingTools")
            else
                addon.minimapIcon:Hide("SunderingTools")
            end
        end
    end, yOffset)
    
    -- Interrupt Tracker Section
    yOffset = CreateSectionHeader(content, "Interrupt Tracker", yOffset - 10)
    
    yOffset = CreateCheckbox(content, "Enable Interrupt Tracker", addon.db.InterruptTracker.enabled, function(checked)
        addon.db.InterruptTracker.enabled = checked
    end, yOffset)
    
    yOffset = CreateCheckbox(content, "Show Spell Icon", addon.db.InterruptTracker.showIcon, function(checked)
        addon.db.InterruptTracker.showIcon = checked
    end, yOffset)
    
    yOffset = CreateCheckbox(content, "Show Player Name", addon.db.InterruptTracker.showName, function(checked)
        addon.db.InterruptTracker.showName = checked
    end, yOffset)
    
    yOffset = CreateCheckbox(content, "Show Cooldown Timer", addon.db.InterruptTracker.showTimer, function(checked)
        addon.db.InterruptTracker.showTimer = checked
    end, yOffset)
    
    yOffset = CreateCheckbox(content, "Use Class Colors", addon.db.InterruptTracker.useClassColor, function(checked)
        addon.db.InterruptTracker.useClassColor = checked
    end, yOffset)
    
    yOffset = CreateSlider(content, "Max Bars", addon.db.InterruptTracker.maxBars, 1, 5, function(value)
        addon.db.InterruptTracker.maxBars = math.floor(value)
    end, yOffset)
    
    yOffset = CreateSlider(content, "Bar Width", addon.db.InterruptTracker.barWidth, 100, 250, function(value)
        addon.db.InterruptTracker.barWidth = math.floor(value)
    end, yOffset)
    
    yOffset = CreateDropdown(content, "Grow Direction", addon.db.InterruptTracker.growDirection, {"DOWN", "UP"}, function(value)
        addon.db.InterruptTracker.growDirection = value
    end, yOffset)
    
    yOffset = CreateButton(content, "Reset Position", function()
        addon.db.InterruptTracker.posX = 0
        addon.db.InterruptTracker.posY = -200
        print("|cff00ff00SunderingTools:|r Interrupt tracker position reset")
    end, yOffset, 120)
    
    -- Bloodlust Sound Section
    yOffset = CreateSectionHeader(content, "Bloodlust Sound", yOffset - 10)
    
    yOffset = CreateCheckbox(content, "Enable Bloodlust Sound", addon.db.BloodlustSound.enabled, function(checked)
        addon.db.BloodlustSound.enabled = checked
    end, yOffset)
    
    yOffset = CreateCheckbox(content, "Hide Icon", addon.db.BloodlustSound.hideIcon, function(checked)
        addon.db.BloodlustSound.hideIcon = checked
    end, yOffset)
    
    yOffset = CreateSlider(content, "Icon Size", addon.db.BloodlustSound.iconSize, 32, 128, function(value)
        addon.db.BloodlustSound.iconSize = math.floor(value)
    end, yOffset)
    
    yOffset = CreateDropdown(content, "Sound Channel", addon.db.BloodlustSound.soundChannel, {"Master", "SFX", "Ambience", "Music"}, function(value)
        addon.db.BloodlustSound.soundChannel = value
    end, yOffset)
    
    yOffset = CreateInput(content, "Sound File Path", addon.db.BloodlustSound.soundFile, function(text)
        addon.db.BloodlustSound.soundFile = text
    end, yOffset)
    
    yOffset = CreateButton(content, "Test Sound", function()
        if addon.BloodlustSound and addon.BloodlustSound.Play then
            addon.BloodlustSound.Play()
        end
    end, yOffset, 100)
    
    yOffset = CreateButton(content, "Stop Sound", function()
        if addon.BloodlustSound and addon.BloodlustSound.Stop then
            addon.BloodlustSound.Stop()
        end
    end, yOffset - 30, 100)
    
    -- About Section
    yOffset = CreateSectionHeader(content, "About", yOffset - 20)
    
    local aboutText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aboutText:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    aboutText:SetWidth(350)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetText("SunderingTools v1.0.0\nA lightweight addon for tracking interrupts and bloodlust.\n\nCommands:\n/su - Quick menu\n/su config - Open settings\n/su reset - Reset all settings")
    
    -- Adjust content height
    content:SetHeight(math.abs(yOffset) + 100)
end

-- Open settings window
function addon:OpenSettings()
    if not SettingsFrame then
        SettingsFrame = CreateSettingsFrame()
        PopulateSettings()
    end
    
    PopulateSettings() -- Refresh values
    SettingsFrame:Show()
    
    -- Close with ESC
    table.insert(UISpecialFrames, SettingsFrame:GetName())
end

-- Close settings window
function addon:CloseSettings()
    if SettingsFrame then
        SettingsFrame:Hide()
    end
end

-- Toggle settings window
function addon:ToggleSettings()
    if SettingsFrame and SettingsFrame:IsShown() then
        addon:CloseSettings()
    else
        addon:OpenSettings()
    end
end
