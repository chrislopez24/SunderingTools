local addon = _G.SunderingTools
if not addon then return end

local SettingsFrame

local Helpers = {}

local function ClearChildren(frame)
  for _, child in ipairs({ frame:GetChildren() }) do
    child:Hide()
    child:SetParent(nil)
  end
end

local function CreateTextBlock(parent, text, template, width)
  local block = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  block:SetJustifyH("LEFT")
  block:SetJustifyV("TOP")
  block:SetWidth(width or 320)
  block:SetText(text)
  return block
end

local function RenderInfoPanel(panel, title, message)
  local heading = CreateTextBlock(panel, title, "GameFontNormalLarge", 320)
  heading:SetPoint("TOPLEFT", 0, 0)

  local body = CreateTextBlock(panel, message, "GameFontHighlight", 320)
  body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
end

function Helpers:CreateCheckbox(parent, label, checked, onChange)
  local box = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  box.Text:SetText(label)
  box:SetChecked(checked)
  box:SetScript("OnClick", function(self)
    onChange(self:GetChecked())
  end)
  return box
end

function Helpers:CreateButton(parent, label, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(140, 24)
  button:SetText(label)
  button:SetScript("OnClick", onClick)
  return button
end

function Helpers:CreateText(parent, text, template, width)
  return CreateTextBlock(parent, text, template, width)
end

function Helpers:CreateSlider(parent, label, minValue, maxValue, step, value, onChange, width)
  local sliderWidth = width or 320
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(sliderWidth, 56)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", math.max(120, sliderWidth - 80))
  holder.label:SetPoint("TOPLEFT", 0, 0)

  holder.valueText = CreateTextBlock(holder, tostring(value), "GameFontHighlight", 80)
  holder.valueText:SetPoint("TOPRIGHT", 0, 0)
  holder.valueText:SetJustifyH("RIGHT")

  local slider = CreateFrame("Slider", nil, holder, "UISliderTemplate")
  slider:SetPoint("TOPLEFT", 0, -18)
  slider:SetPoint("TOPRIGHT", 0, -18)
  slider:SetHeight(16)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(step or 1)

  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end

  local initializing = true
  slider:SetScript("OnValueChanged", function(self, newValue)
    local steppedValue = math.floor((newValue / (step or 1)) + 0.5) * (step or 1)
    if step == 1 then
      steppedValue = math.floor(steppedValue + 0.5)
    end

    holder.valueText:SetText(tostring(steppedValue))
    if not initializing then
      onChange(steppedValue)
    end
  end)
  slider:SetValue(value)
  initializing = false

  holder.slider = slider
  return holder
end

function Helpers:CreateEditBox(parent, label, width, value, onChange)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width or 320, 52)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", width or 320)
  holder.label:SetPoint("TOPLEFT", 0, 0)

  local input = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  input:SetSize(width or 320, 24)
  input:SetPoint("TOPLEFT", 0, -20)
  input:SetAutoFocus(false)
  input:SetText(value or "")

  local function commit()
    onChange(input:GetText())
  end

  local skipNextFocusCommit = false
  input:SetScript("OnEnterPressed", function(self)
    skipNextFocusCommit = true
    commit()
    self:ClearFocus()
  end)
  input:SetScript("OnEditFocusLost", function()
    if skipNextFocusCommit then
      skipNextFocusCommit = false
      return
    end
    commit()
  end)

  holder.input = input
  return holder
end

function Helpers:CreateDropdown(parent, label, options, selectedValue, width, onChange)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize((width or 180) + 32, 52)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", width or 180)
  holder.label:SetPoint("TOPLEFT", 0, 0)

  local dropdown = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
  dropdown:SetPoint("TOPLEFT", -16, -14)
  dropdown.value = selectedValue

  UIDropDownMenu_SetWidth(dropdown, width or 180)
  UIDropDownMenu_Initialize(dropdown, function(self, _)
    for _, option in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = option
      info.value = option
      info.checked = option == dropdown.value
      info.func = function()
        dropdown.value = option
        UIDropDownMenu_SetSelectedValue(dropdown, option)
        UIDropDownMenu_SetText(dropdown, option)
        onChange(option)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetSelectedValue(dropdown, selectedValue)
  UIDropDownMenu_SetText(dropdown, selectedValue)

  holder.dropdown = dropdown
  return holder
end

function Helpers:CreatePreview(parent, previewBars, db)
  local barWidth = (db and db.barWidth) or 240
  local barHeight = (db and db.barHeight) or 20
  local spacing = (db and db.spacing) or 4
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(barWidth, math.max(0, (#previewBars * (barHeight + spacing)) - spacing))

  for index, bar in ipairs(previewBars) do
    local row = CreateFrame("StatusBar", nil, holder)
    row:SetSize(barWidth, barHeight)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * (barHeight + spacing)))
    row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row:SetStatusBarColor(0.2, 0.8, 0.2)
    row:SetMinMaxValues(0, 1)
    row:SetValue(bar.value or 1)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.7)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", 8, 0)
    row.nameText:SetText(bar.name or "")

    row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.timerText:SetPoint("RIGHT", -8, 0)
    row.timerText:SetText(bar.text or "")
  end

  return holder
end

local function CreateSettingsFrame()
  local frame = CreateFrame("Frame", "SunderingToolsSettings", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 560)
  frame:SetPoint("CENTER")
  frame:Hide()

  frame.list = CreateFrame("Frame", nil, frame)
  frame.list:SetPoint("TOPLEFT", 12, -32)
  frame.list:SetSize(160, 500)

  frame.panel = CreateFrame("Frame", nil, frame)
  frame.panel:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 12, 0)
  frame.panel:SetSize(420, 500)

  return frame
end

function addon:RenderSection(sectionKey, panel, helpers)
  ClearChildren(panel)
  local content = CreateFrame("Frame", nil, panel)
  content:SetAllPoints()

  if sectionKey == "General" then
    local minimapBox = helpers:CreateCheckbox(content, "Show Minimap Button", addon:IsMinimapVisible(), function(checked)
      addon:SetMinimapVisible(checked)
    end)
    minimapBox:SetPoint("TOPLEFT", 0, 0)

    local button = helpers:CreateButton(content, "Open Edit Mode", function()
      addon:SetEditMode(true)
    end)
    button:SetPoint("TOPLEFT", minimapBox, "BOTTOMLEFT", 4, -12)

    local message = "Edit mode support is not available in this shell yet."
    if addon:CanOpenEditMode() then
      message = "Edit mode is available for supported modules."
    else
      button:Disable()
    end

    local resetAllButton = helpers:CreateButton(content, "Reset All Settings", function()
      addon:ResetAllSettings()
    end)
    resetAllButton:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, 0)

    local helpText = CreateTextBlock(
      content,
      message .. "\n\n/su opens settings.\n/su config opens settings directly.\n/su reset reloads with defaults.",
      "GameFontHighlight",
      380
    )
    helpText:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)
    return
  end

  local moduleDef = self.modules[sectionKey]
  if moduleDef and moduleDef.buildSettings then
    moduleDef:buildSettings(content, helpers, self, self.db.modules[sectionKey])
    if #({ content:GetChildren() }) > 0 or #({ content:GetRegions() }) > 0 then
      return
    end
  end

  RenderInfoPanel(
    content,
    (moduleDef and moduleDef.label) or sectionKey,
    "Settings for this module will be added in a later task."
  )
end

function addon:OpenSettings()
  SettingsFrame = SettingsFrame or CreateSettingsFrame()
  ClearChildren(SettingsFrame.list)
  SettingsFrame:Show()

  local sections = self:GetSettingsSections()
  for index, section in ipairs(sections) do
    local nav = Helpers:CreateButton(SettingsFrame.list, section.label, function()
      addon:RenderSection(section.key, SettingsFrame.panel, Helpers)
    end)
    nav:SetPoint("TOPLEFT", 0, -((index - 1) * 28))
  end

  addon:RenderSection(sections[1].key, SettingsFrame.panel, Helpers)

  if not tContains(UISpecialFrames, SettingsFrame:GetName()) then
    table.insert(UISpecialFrames, SettingsFrame:GetName())
  end
end

function addon:CloseSettings()
  if SettingsFrame then
    SettingsFrame:Hide()
  end
end

function addon:ToggleSettings()
  if SettingsFrame and SettingsFrame:IsShown() then
    addon:CloseSettings()
  else
    addon:OpenSettings()
  end
end
