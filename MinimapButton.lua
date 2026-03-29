local addon = _G.SunderingTools
if not addon then return end

function addon:CreateMinimapButton()
  if self.minimapButton then
    self:SetMinimapVisible(self:IsMinimapVisible())
    return self.minimapButton
  end

  local button = CreateFrame("Button", "SunderingToolsMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
  button:RegisterForClicks("LeftButtonUp")

  button.icon = button:CreateTexture(nil, "BACKGROUND")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER", 0, 0)
  button.icon:SetTexture("Interface\\Icons\\Ability_Warrior_PunishingBlow")

  button.border = button:CreateTexture(nil, "OVERLAY")
  button.border:SetSize(54, 54)
  button.border:SetPoint("CENTER", 0, 0)
  button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:SetScript("OnClick", function()
    addon:OpenSettings()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ff00SunderingTools|r")
    GameTooltip:AddLine("Click to open settings")
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  self.minimapButton = button
  self:SetMinimapVisible(self:IsMinimapVisible())
  return button
end
