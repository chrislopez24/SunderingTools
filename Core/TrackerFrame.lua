local TrackerFrame = _G.SunderingToolsTrackerFrame or {}

function TrackerFrame.CreateContainerShell(name, labelText, onDragStart, onDragStop)
  local frame = CreateFrame("Frame", name, UIParent)
  frame:SetMovable(true)
  frame:EnableMouse(false)
  frame:RegisterForDrag("LeftButton")

  frame.dragHandle = CreateFrame("Frame", nil, frame)
  frame.dragHandle:SetAllPoints()
  frame.dragHandle:SetFrameStrata("HIGH")
  frame.dragHandle:EnableMouse(false)
  frame.dragHandle:RegisterForDrag("LeftButton")
  frame.dragHandle:SetScript("OnDragStart", onDragStart)
  frame.dragHandle:SetScript("OnDragStop", onDragStop)
  frame.dragHandle:Hide()

  frame.editBackdrop = frame:CreateTexture(nil, "BACKGROUND")
  frame.editBackdrop:SetAllPoints()
  frame.editBackdrop:SetColorTexture(0.05, 0.42, 0.46, 0.18)
  frame.editBackdrop:Hide()

  frame.editBorderTop = frame:CreateTexture(nil, "OVERLAY")
  frame.editBorderTop:SetPoint("TOPLEFT", 0, 0)
  frame.editBorderTop:SetPoint("TOPRIGHT", 0, 0)
  frame.editBorderTop:SetHeight(1)
  frame.editBorderTop:SetColorTexture(0.08, 0.82, 0.86, 0.85)
  frame.editBorderTop:Hide()

  frame.editBorderBottom = frame:CreateTexture(nil, "OVERLAY")
  frame.editBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
  frame.editBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
  frame.editBorderBottom:SetHeight(1)
  frame.editBorderBottom:SetColorTexture(0.08, 0.82, 0.86, 0.85)
  frame.editBorderBottom:Hide()

  frame.editLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.editLabel:SetPoint("TOP", 0, -8)
  frame.editLabel:SetTextColor(0.08, 0.82, 0.86)
  frame.editLabel:SetText(labelText or "")
  frame.editLabel:Hide()

  return frame
end

function TrackerFrame.UpdateEditModeVisuals(frame, enabled, updateLabelVisibility)
  if not frame then
    return
  end

  frame:EnableMouse(enabled)

  if frame.dragHandle then
    frame.dragHandle:EnableMouse(enabled)
    if enabled then
      frame.dragHandle:Show()
    else
      frame.dragHandle:Hide()
    end
  end

  if frame.editBackdrop then
    if enabled then
      frame.editBackdrop:Show()
    else
      frame.editBackdrop:Hide()
    end
  end

  if frame.editBorderTop and frame.editBorderBottom then
    if enabled then
      frame.editBorderTop:Show()
      frame.editBorderBottom:Show()
    else
      frame.editBorderTop:Hide()
      frame.editBorderBottom:Hide()
    end
  end

  if type(updateLabelVisibility) == "function" then
    updateLabelVisibility(enabled)
  end

  if enabled then
    frame:Show()
  end
end

_G.SunderingToolsTrackerFrame = TrackerFrame

return TrackerFrame
