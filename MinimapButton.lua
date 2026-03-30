local addon = _G.SunderingTools
if not addon then return end

local MINIMAP_LOGO_TEXTURE = "Interface\\AddOns\\SunderingTools\\assets\\icons\\logo-minimap.tga"

local function PositionButton(button, angle)
  local radius = (Minimap:GetWidth() / 2) + 5
  local radians = math.rad(angle or addon:GetMinimapAngle())
  local x = math.cos(radians) * radius
  local y = math.sin(radians) * radius

  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CalculateAngle(dx, dy)
  if math.atan2 then
    return math.deg(math.atan2(dy, dx))
  end

  if dx == 0 then
    return dy >= 0 and 90 or -90
  end

  local angle = math.deg(math.atan(dy / dx))
  if dx < 0 then
    angle = angle + 180
  end

  return angle
end

function addon:CreateMinimapButton()
  if self.minimapButton then
    self.minimapButton:UpdatePosition(self:GetMinimapAngle())
    self:SetMinimapVisible(self:IsMinimapVisible())
    return self.minimapButton
  end

  local button = CreateFrame("Button", "SunderingToolsMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  function button:UpdatePosition(angle)
    PositionButton(self, angle)
  end

  button.icon = button:CreateTexture(nil, "BACKGROUND")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER", 1, 2)
  button.icon:SetTexture(MINIMAP_LOGO_TEXTURE)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  button.border = button:CreateTexture(nil, "OVERLAY")
  button.border:SetSize(52, 52)
  button.border:SetPoint("TOPLEFT")
  button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:SetScript("OnClick", function()
    addon:OpenSettings()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ff00SunderingTools|r")
    GameTooltip:AddLine("Open settings.")
    if addon:IsMinimapUnlocked() then
      GameTooltip:AddLine("Drag to move.", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  button:SetScript("OnDragStart", function(self)
    if not addon:IsMinimapUnlocked() then
      return
    end

    self:SetScript("OnUpdate", function(dragButton)
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      local dx = (cx / scale) - mx
      local dy = (cy / scale) - my
      addon:SetMinimapAngle(CalculateAngle(dx, dy))
      dragButton:UpdatePosition(addon:GetMinimapAngle())
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UpdatePosition(addon:GetMinimapAngle())
  end)

  self.minimapButton = button
  button:UpdatePosition(self:GetMinimapAngle())
  self:SetMinimapVisible(self:IsMinimapVisible())
  return button
end
