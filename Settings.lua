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

function Helpers:CreatePreview(parent, previewBars)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(320, 100)

  for index, bar in ipairs(previewBars) do
    local row = CreateFrame("StatusBar", nil, holder)
    row:SetSize(240, 20)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetText(bar.name .. "  " .. bar.text)
  end

  return holder
end

local function CreateSettingsFrame()
  local frame = CreateFrame("Frame", "SunderingToolsSettings", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 420)
  frame:SetPoint("CENTER")
  frame:Hide()

  frame.list = CreateFrame("Frame", nil, frame)
  frame.list:SetPoint("TOPLEFT", 12, -32)
  frame.list:SetSize(160, 360)

  frame.panel = CreateFrame("Frame", nil, frame)
  frame.panel:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 12, 0)
  frame.panel:SetSize(360, 360)

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

    local helpText = CreateTextBlock(content, message, "GameFontHighlight", 320)
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
