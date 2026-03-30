local addon = _G.SunderingTools
if not addon then return end

local SettingsFrame

local Helpers = {}
Helpers.ScrollWidth = 600
Helpers.SectionWidth = 560
Helpers.WideControlWidth = 420
Helpers.ColumnWidth = 216
Helpers.ActionButtonWidth = 136
Helpers.ColumnGap = 18
Helpers.RowGap = 10
Helpers.SectionColumnWidth = 266
Helpers.SectionColumnGap = 28
local ADDON_VERSION =
  (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addon.name or "SunderingTools", "Version"))
  or GetAddOnMetadata(addon.name or "SunderingTools", "Version")
  or "@project-version@"

local Theme = {
  windowBg = { 0.06, 0.06, 0.07, 0.95 },
  windowBorder = { 1, 1, 1, 0.15 },
  headerBg = { 0.10, 0.10, 0.12, 0.95 },
  sidebarBg = { 0.09, 0.09, 0.10, 0.95 },
  contentBg = { 0.08, 0.08, 0.09, 0.95 },
  sectionBg = { 0.09, 0.09, 0.10, 0.92 },
  sectionHeaderBg = { 0.10, 0.10, 0.12, 0.95 },
  buttonBg = { 0.08, 0.10, 0.12, 0.98 },
  buttonBorder = { 0.15, 0.56, 0.64, 0.90 },
  buttonHighlight = { 0.11, 0.16, 0.19, 1.0 },
  selectedBg = { 0.09, 0.84, 0.95, 0.16 },
  selectedText = { 0.42, 0.92, 1.0 },
  idleText = { 0.92, 0.92, 0.92 },
  divider = { 1, 1, 1, 0.07 },
  accent = { 0.09, 0.84, 0.95, 1.0 },
  hintText = { 0.76, 0.76, 0.78 },
}

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
  block:SetText(text or "")
  return block
end

local function ApplySolidBackdrop(frame, color, edgeColor)
  if not frame or not frame.SetBackdrop then
    return
  end

  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = edgeColor and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
    tile = true,
    tileSize = 8,
    edgeSize = edgeColor and 12 or 0,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  frame:SetBackdropColor(unpack(color))
  if edgeColor then
    frame:SetBackdropBorderColor(unpack(edgeColor))
  end
end

local function CreateDivider(parent, topLeft, topRight)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(unpack(Theme.divider))
  line:SetPoint(unpack(topLeft))
  line:SetPoint(unpack(topRight))
  line:SetHeight(1)
  return line
end

local function UpdateNavState(navButtons, selectedKey)
  for _, buttonInfo in ipairs(navButtons or {}) do
    local isSelected = buttonInfo.key == selectedKey
    buttonInfo.button.selected = isSelected

    if buttonInfo.button.bg then
      buttonInfo.button.bg:SetAlpha(isSelected and 0.18 or 0.0)
    end

    if buttonInfo.button.text then
      if isSelected then
        buttonInfo.button.text:SetTextColor(unpack(Theme.selectedText))
      else
        buttonInfo.button.text:SetTextColor(unpack(Theme.idleText))
      end
    end
  end
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
  button:SetSize(152, 24)
  button:SetText(label)
  if onClick then
    button:SetScript("OnClick", onClick)
  end
  return button
end

function Helpers:CreateText(parent, text, template, width)
  return CreateTextBlock(parent, text, template, width)
end

function Helpers:CreateSectionHint(parent, text, width)
  local hint = CreateTextBlock(parent, text, "GameFontHighlightSmall", width or (self.SectionWidth - 40))
  hint:SetTextColor(unpack(Theme.hintText))
  return hint
end

function Helpers:CreateDividerLabel(parent, text, anchor, offsetY)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(self.SectionWidth, 22)

  if anchor then
    holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -18)
  else
    holder:SetPoint("TOPLEFT", 0, offsetY or 0)
  end

  holder.label = CreateTextBlock(holder, text or "", "GameFontHighlight", self.SectionWidth - 84)
  holder.label:SetPoint("TOPLEFT", 0, 0)

  holder.line = holder:CreateTexture(nil, "ARTWORK")
  holder.line:SetColorTexture(unpack(Theme.divider))
  holder.line:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -4)
  holder.line:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -18)
  holder.line:SetHeight(1)

  return holder
end

function Helpers:CreateDarkButton(parent, label, width, onClick)
  local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  button:SetSize(width or self.ActionButtonWidth, 22)
  ApplySolidBackdrop(button, Theme.buttonBg, Theme.buttonBorder)
  button:RegisterForClicks("LeftButtonUp")

  button.Accent = button:CreateTexture(nil, "ARTWORK")
  button.Accent:SetPoint("TOPLEFT", 4, -4)
  button.Accent:SetPoint("TOPRIGHT", -4, -4)
  button.Accent:SetHeight(1)
  button.Accent:SetColorTexture(unpack(Theme.accent))
  button.Accent:SetAlpha(0.75)

  button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.Label:SetPoint("CENTER", 0, 0)
  button.Label:SetText(label or "")
  button.Label:SetTextColor(unpack(Theme.idleText))

  function button:SetText(text)
    self.Label:SetText(text or "")
  end

  button:SetScript("OnMouseDown", function(self)
    self.Label:SetPoint("CENTER", 0, -1)
    self:SetBackdropColor(0.09, 0.13, 0.16, 1)
    self.Accent:SetAlpha(1)
  end)
  button:SetScript("OnMouseUp", function(self)
    self.Label:SetPoint("CENTER", 0, 0)
    if self:IsMouseOver() then
      self:SetBackdropColor(unpack(Theme.buttonHighlight))
      self.Accent:SetAlpha(1)
    else
      self:SetBackdropColor(unpack(Theme.buttonBg))
      self.Accent:SetAlpha(0.75)
    end
  end)
  button:SetScript("OnEnter", function(self)
    self:SetBackdropColor(unpack(Theme.buttonHighlight))
    self.Accent:SetAlpha(1)
  end)
  button:SetScript("OnLeave", function(self)
    self:SetBackdropColor(unpack(Theme.buttonBg))
    self.Accent:SetAlpha(0.75)
  end)
  button:SetScript("OnDisable", function(self)
    self:SetAlpha(0.45)
    self.Accent:SetAlpha(0.45)
  end)
  button:SetScript("OnEnable", function(self)
    self:SetAlpha(1)
    self:SetBackdropColor(unpack(Theme.buttonBg))
    self.Accent:SetAlpha(0.75)
  end)

  if onClick then
    button:SetScript("OnClick", onClick)
  end

  return button
end

function Helpers:CreateActionButton(parent, label, onClick, width)
  return self:CreateDarkButton(parent, label, width or self.ActionButtonWidth, onClick)
end

function Helpers:CreateInlineCheckbox(parent, label, checked, onChange)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(self.ColumnWidth, 24)

  holder.checkbox = CreateFrame("CheckButton", nil, holder, "InterfaceOptionsCheckButtonTemplate")
  holder.checkbox:SetPoint("LEFT", 0, 0)
  holder.checkbox:SetSize(24, 24)
  holder.checkbox:SetHitRectInsets(0, 0, 0, 0)
  holder.checkbox.Text:SetText(label)
  holder.checkbox.Text:ClearAllPoints()
  holder.checkbox.Text:SetPoint("LEFT", holder.checkbox, "RIGHT", 2, 0)
  holder.checkbox.Text:SetWidth(self.ColumnWidth - 26)
  holder.checkbox.Text:SetJustifyH("LEFT")
  holder.checkbox.Text:SetTextColor(unpack(Theme.idleText))
  holder.checkbox:SetChecked(checked)
  holder.checkbox:SetScript("OnClick", function(self)
    onChange(self:GetChecked())
  end)

  return holder
end

function Helpers:PlaceRow(anchor, left, right, offsetY, gap)
  if not anchor or not left then
    return
  end

  left:ClearAllPoints()
  left:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -12)

  if right then
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", gap or self.ColumnGap, 0)
  end
end

function Helpers:CreateSectionColumns(parent, anchor, offsetY, leftWidth, rightWidth, gap)
  local left = CreateFrame("Frame", nil, parent)
  left:SetSize(leftWidth or self.SectionColumnWidth, 1)

  if anchor then
    left:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -24)
  else
    left:SetPoint("TOPLEFT", 0, offsetY or 0)
  end

  local right = CreateFrame("Frame", nil, parent)
  right:SetSize(rightWidth or self.SectionColumnWidth, 1)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", gap or self.SectionColumnGap, 0)

  return left, right
end

function Helpers:CreateLabeledEditBox(parent, label, width, value, onChange)
  local inputWidth = width or self.WideControlWidth
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(inputWidth + 12, 46)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", inputWidth)
  holder.label:SetPoint("TOPLEFT", 0, 0)

  local editBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  editBox:SetAutoFocus(false)
  editBox:SetSize(inputWidth, 20)
  editBox:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 6, -6)
  editBox:SetText(value or "")
  editBox:SetCursorPosition(0)

  local committedValue = value or ""
  local function Commit(self)
    committedValue = self:GetText() or ""
    onChange(committedValue)
  end

  editBox:SetScript("OnEnterPressed", function(self)
    Commit(self)
    self:ClearFocus()
  end)
  editBox:SetScript("OnEscapePressed", function(self)
    self:SetText(committedValue)
    self:ClearFocus()
  end)
  editBox:SetScript("OnEditFocusLost", function(self)
    Commit(self)
  end)

  holder.editBox = editBox
  return holder
end

function Helpers:CreateLabeledSlider(parent, label, minValue, maxValue, step, value, onChange, width)
  local sliderWidth = width or self.ColumnWidth
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(sliderWidth, 50)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", math.max(120, sliderWidth - 80))
  holder.label:SetPoint("TOPLEFT", 0, 0)

  holder.valueText = CreateTextBlock(holder, tostring(value), "GameFontHighlight", 80)
  holder.valueText:SetPoint("TOPRIGHT", 0, 0)
  holder.valueText:SetJustifyH("RIGHT")

  local slider = CreateFrame("Slider", nil, holder, "UISliderTemplate")
  slider:SetPoint("TOPLEFT", 0, -16)
  slider:SetPoint("TOPRIGHT", 0, -16)
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

function Helpers:CreateLabeledDropdown(parent, label, options, selectedValue, width, onChange)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize((width or (self.ColumnWidth - 28)) + 32, 58)

  holder.label = CreateTextBlock(holder, label, "GameFontHighlight", width or (self.ColumnWidth - 28))
  holder.label:SetPoint("TOPLEFT", 0, 0)

  local dropdown = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
  dropdown:SetPoint("TOPLEFT", -12, -18)
  dropdown.value = selectedValue

  local function GetOptionText(option)
    if type(option) == "table" then
      return option.label or option.text or option.value
    end

    return option
  end

  local function GetOptionValue(option)
    if type(option) == "table" then
      return option.value
    end

    return option
  end

  UIDropDownMenu_SetWidth(dropdown, width or 180)
  UIDropDownMenu_Initialize(dropdown, function()
    for _, option in ipairs(options) do
      local optionText = GetOptionText(option)
      local optionValue = GetOptionValue(option)
      local info = UIDropDownMenu_CreateInfo()
      info.text = optionText
      info.value = optionValue
      info.checked = optionValue == dropdown.value
      info.func = function()
        dropdown.value = optionValue
        UIDropDownMenu_SetSelectedValue(dropdown, optionValue)
        UIDropDownMenu_SetText(dropdown, optionText)
        onChange(optionValue)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetSelectedValue(dropdown, selectedValue)

  for _, option in ipairs(options or {}) do
    if GetOptionValue(option) == selectedValue then
      UIDropDownMenu_SetText(dropdown, GetOptionText(option))
      break
    end
  end

  holder.dropdown = dropdown
  return holder
end

function Helpers:CreateCheckbox(parent, label, checked, onChange)
  return self:CreateInlineCheckbox(parent, label, checked, onChange)
end

function Helpers:CreateButton(parent, label, onClick)
  return self:CreateActionButton(parent, label, onClick)
end

function Helpers:CreateEditBox(parent, label, width, value, onChange)
  return self:CreateLabeledEditBox(parent, label, width, value, onChange)
end

function Helpers:CreateSlider(parent, label, minValue, maxValue, step, value, onChange, width)
  return self:CreateLabeledSlider(parent, label, minValue, maxValue, step, value, onChange, width)
end

function Helpers:CreateDropdown(parent, label, options, selectedValue, width, onChange)
  return self:CreateLabeledDropdown(parent, label, options, selectedValue, width, onChange)
end

local function GetGlobalEditModeLabel(addonRef)
  if addonRef.db and addonRef.db.global and addonRef.db.global.editMode then
    return "Lock All Trackers"
  end

  return "Open Edit Mode"
end

local function GetMinimapDragLabel(addonRef)
  if addonRef:IsMinimapUnlocked() then
    return "Lock Minimap Drag"
  end

  return "Unlock Minimap Drag"
end

local function GetEditModeStatusText(addonRef)
  if not addonRef.db or not addonRef.db.global or not addonRef.db.global.editMode then
    return nil
  end

  local active = addonRef.db.global.activeEditModule
  if active == "ALL" then
    return "Interrupt Tracker, Crowd Control Tracker, and Bloodlust Tracker can be moved now."
  end

  local moduleDef = addonRef.modules and addonRef.modules[active]
  if moduleDef and moduleDef.label then
    return moduleDef.label .. " can be moved now."
  end

  return "A tracker can be moved now."
end

local function UpdateEditModeBanner(frame)
  if not frame or not frame.editStatus or not frame.editStatusText then
    return
  end

  local statusText = GetEditModeStatusText(addon)
  frame.scrollFrame:ClearAllPoints()

  if statusText then
    frame.editStatusText:SetText(statusText)
    frame.editStatus:Show()
    frame.scrollFrame:SetPoint("TOPLEFT", frame.editStatus, "BOTTOMLEFT", 0, -12)
  else
    frame.editStatus:Hide()
    frame.scrollFrame:SetPoint("TOPLEFT", frame.sectionBody, "BOTTOMLEFT", 0, -14)
  end

  frame.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 0)
end

local function CreateNavButton(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(30)
  button:SetPoint("LEFT", 8, 0)
  button:SetPoint("RIGHT", -8, 0)
  button:RegisterForClicks("LeftButtonUp")

  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(unpack(Theme.selectedBg))
  button.bg:SetAlpha(0.0)

  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  button.text:SetPoint("LEFT", 10, 0)
  button.text:SetPoint("RIGHT", -10, 0)
  button.text:SetJustifyH("LEFT")
  button.text:SetText(text)
  button.text:SetTextColor(unpack(Theme.idleText))

  if onClick then
    button:SetScript("OnClick", onClick)
  end

  return button
end

local function CreateSettingsFrame()
  local frame = CreateFrame("Frame", "SunderingToolsSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(920, 560)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  ApplySolidBackdrop(frame, Theme.windowBg, Theme.windowBorder)
  frame:Hide()
  frame:SetScript("OnHide", function()
    if addon.db and addon.db.global and addon.db.global.editMode then
      addon:SetEditMode(false)
    end
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  frame.headerBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.headerBar:SetPoint("TOPLEFT", 10, -10)
  frame.headerBar:SetPoint("TOPRIGHT", -10, -10)
  frame.headerBar:SetHeight(40)
  ApplySolidBackdrop(frame.headerBar, Theme.headerBg)

  frame.headerTitle = CreateTextBlock(frame.headerBar, "SunderingTools", "GameFontNormalLarge", 220)
  frame.headerTitle:SetPoint("LEFT", 12, 0)

  frame.headerByline = CreateTextBlock(frame.headerBar, "|cffbbbbbbby Krich|r", "GameFontHighlightSmall", 90)
  frame.headerByline:SetPoint("LEFT", frame.headerTitle, "RIGHT", 8, -2)

  frame.headerMeta = CreateTextBlock(frame.headerBar, "", "GameFontHighlightSmall", 320)
  frame.headerMeta:SetPoint("LEFT", frame.headerByline, "RIGHT", 12, -2)
  frame.headerMeta:SetText("")

  frame:SetMovable(true)
  frame.headerBar:EnableMouse(true)
  frame.headerBar:RegisterForDrag("LeftButton")
  frame.headerBar:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  frame.headerBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  frame.sidebar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.sidebar:SetPoint("TOPLEFT", 10, -56)
  frame.sidebar:SetPoint("BOTTOMLEFT", 10, 10)
  frame.sidebar:SetWidth(192)
  ApplySolidBackdrop(frame.sidebar, Theme.sidebarBg)

  frame.contentPane = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.contentPane:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 10, 0)
  frame.contentPane:SetPoint("BOTTOMRIGHT", -10, 10)
  ApplySolidBackdrop(frame.contentPane, Theme.contentBg)

  frame.headerDivider = CreateDivider(frame, { "TOPLEFT", 10, -56 }, { "TOPRIGHT", -10, -56 })

  frame.sectionTitle = CreateTextBlock(frame.contentPane, "", "GameFontNormalLarge", Helpers.SectionWidth)
  frame.sectionTitle:SetPoint("TOPLEFT", 16, -16)

  frame.sectionBody = CreateTextBlock(frame.contentPane, "", "GameFontHighlight", Helpers.SectionWidth)
  frame.sectionBody:SetPoint("TOPLEFT", frame.sectionTitle, "BOTTOMLEFT", 0, -8)

  frame.editStatus = CreateFrame("Frame", nil, frame.contentPane, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.editStatus:SetPoint("TOPLEFT", frame.sectionBody, "BOTTOMLEFT", 0, -12)
  frame.editStatus:SetSize(Helpers.SectionWidth, 44)
  ApplySolidBackdrop(frame.editStatus, { 0.10, 0.10, 0.12, 0.95 })
  frame.editStatus:Hide()

  frame.editStatusTitle = CreateTextBlock(frame.editStatus, "Edit Mode Active", "GameFontNormal", Helpers.SectionWidth - 84)
  frame.editStatusTitle:SetPoint("TOPLEFT", 12, -8)

  frame.editStatusText = CreateTextBlock(frame.editStatus, "", "GameFontHighlightSmall", Helpers.SectionWidth - 40)
  frame.editStatusText:SetPoint("TOPLEFT", frame.editStatusTitle, "BOTTOMLEFT", 0, -4)

  frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame.contentPane, "UIPanelScrollFrameTemplate")
  frame.scrollFrame:SetPoint("TOPLEFT", frame.sectionBody, "BOTTOMLEFT", 0, -14)
  frame.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 0)

  frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
  frame.scrollChild:SetSize(600, 1)
  frame.scrollFrame:SetScrollChild(frame.scrollChild)

  frame.navButtons = {}
  return frame
end

function addon:RenderSection(sectionKey, panel, helpers)
  ClearChildren(panel)
  local content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT", 0, 0)
  content:SetSize(helpers.ScrollWidth, 1)

  if sectionKey == "General" then
    local minimapTitle = helpers:CreateDividerLabel(content, "Minimap", nil, 0)
    local minimapBody = helpers:CreateSectionHint(content, "Launcher visibility and drag state.", 520)
    minimapBody:SetPoint("TOPLEFT", minimapTitle, "BOTTOMLEFT", 0, -8)

    local minimapBox = helpers:CreateInlineCheckbox(content, "Show Minimap Icon", addon:IsMinimapVisible(), function(checked)
      addon:SetMinimapVisible(checked)
    end)
    minimapBox:SetPoint("TOPLEFT", minimapBody, "BOTTOMLEFT", 0, -12)

    local unlockButton = helpers:CreateActionButton(content, GetMinimapDragLabel(addon), function(self)
      addon:SetMinimapUnlocked(not addon:IsMinimapUnlocked())
      self:SetText(GetMinimapDragLabel(addon))
    end, 148)

    local resetMinimapButton = helpers:CreateActionButton(content, "Reset Minimap Position", function()
      addon:ResetMinimapPosition()
    end, 170)
    helpers:PlaceRow(minimapBox, unlockButton, resetMinimapButton, -12, 12)

    local minimapHint = helpers:CreateSectionHint(content, "Unlock to drag the icon around the minimap.", 420)
    minimapHint:SetPoint("TOPLEFT", unlockButton, "BOTTOMLEFT", 0, -12)

    local editTitle = helpers:CreateDividerLabel(content, "Edit Mode", minimapHint, -22)
    local editBody = helpers:CreateSectionHint(content, "Move supported trackers without leaving the game.", 520)
    editBody:SetPoint("TOPLEFT", editTitle, "BOTTOMLEFT", 0, -8)

    local button = helpers:CreateActionButton(content, GetGlobalEditModeLabel(addon))
    button:SetScript("OnClick", function(self)
      addon:SetEditMode(not addon.db.global.editMode)
      self:SetText(GetGlobalEditModeLabel(addon))
      addon:RefreshSettings()
    end)
    button:SetPoint("TOPLEFT", editBody, "BOTTOMLEFT", 0, -12)

    local message = "Edit mode is available for supported trackers."
    if not addon:CanOpenEditMode() then
      message = "Edit mode is not available for the current tracker setup."
      button:Disable()
    end

    local helpText = helpers:CreateSectionHint(content, message, 420)
    helpText:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)

    local systemTitle = helpers:CreateDividerLabel(content, "System", helpText, -22)
    local systemBody = helpers:CreateSectionHint(content, "Global addon actions and diagnostics.", 520)
    systemBody:SetPoint("TOPLEFT", systemTitle, "BOTTOMLEFT", 0, -8)

    local debugModeBox = helpers:CreateInlineCheckbox(content, "Debug Mode", addon:IsDebugEnabled(), function(checked)
      addon:SetDebugEnabled(checked)
    end)
    debugModeBox:SetPoint("TOPLEFT", systemBody, "BOTTOMLEFT", 0, -12)

    local debugHint = helpers:CreateSectionHint(content, "Print lightweight event traces to chat while enabled.", 420)
    debugHint:SetPoint("TOPLEFT", debugModeBox, "BOTTOMLEFT", 0, -10)

    local resetAllButton = helpers:CreateActionButton(content, "Reset All Settings", function()
      addon:ResetAllSettings()
    end)
    resetAllButton:SetPoint("TOPLEFT", debugHint, "BOTTOMLEFT", 0, -12)

    content:SetHeight(372)
    return
  end

  local moduleDef = self.modules[sectionKey]
  if moduleDef and moduleDef.buildSettings then
    moduleDef:buildSettings(content, helpers, self, self.db.modules[sectionKey])
    content:SetHeight(760)
    return
  end

  local title = CreateTextBlock(content, (moduleDef and moduleDef.label) or sectionKey, "GameFontNormalLarge", 360)
  title:SetPoint("TOPLEFT", 0, 0)
  local body = CreateTextBlock(content, "Settings for this module are not available yet.", "GameFontHighlight", 360)
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  content:SetHeight(200)
end

function addon:OpenSettings()
  SettingsFrame = SettingsFrame or CreateSettingsFrame()
  ClearChildren(SettingsFrame.sidebar)
  wipe(SettingsFrame.navButtons)
  SettingsFrame:Show()

  local sections = self:GetSettingsSections()
  local function selectSection(section)
    SettingsFrame.selectedSection = section.key
    SettingsFrame.sectionTitle:SetText(section.label)
    SettingsFrame.sectionBody:SetText(section.description or "")
    UpdateEditModeBanner(SettingsFrame)
    SettingsFrame.scrollFrame:SetVerticalScroll(0)
    addon:RenderSection(section.key, SettingsFrame.scrollChild, Helpers)
    UpdateNavState(SettingsFrame.navButtons, section.key)
  end
  SettingsFrame.selectSection = selectSection

  for index, section in ipairs(sections) do
    local nav = CreateNavButton(SettingsFrame.sidebar, section.label, function()
      selectSection(section)
    end)
    nav:SetPoint("TOPLEFT", 0, -14 - ((index - 1) * 34))
    SettingsFrame.navButtons[#SettingsFrame.navButtons + 1] = {
      key = section.key,
      button = nav,
    }
  end

  selectSection(sections[1])

  if not tContains(UISpecialFrames, SettingsFrame:GetName()) then
    table.insert(UISpecialFrames, SettingsFrame:GetName())
  end
end

function addon:RefreshSettings()
  if not SettingsFrame or not SettingsFrame:IsShown() then
    return
  end

  local selectedKey = SettingsFrame.selectedSection or "General"
  local sections = self:GetSettingsSections()
  for _, section in ipairs(sections) do
    if section.key == selectedKey then
      SettingsFrame.selectSection(section)
      return
    end
  end
end

function addon:CloseSettings()
  if SettingsFrame then
    addon:SetEditMode(false)
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
