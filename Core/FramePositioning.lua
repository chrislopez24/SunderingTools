local FramePositioning = _G.SunderingToolsFramePositioning or {}

function FramePositioning.ApplySavedPosition(frame, moduleDB, defaultX, defaultY)
  if not frame or not moduleDB then
    return
  end

  frame:ClearAllPoints()

  if moduleDB.positionMode == "ABSOLUTE_TOPLEFT"
    and type(moduleDB.posX) == "number"
    and type(moduleDB.posY) == "number"
    and moduleDB.posY > 0 then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", moduleDB.posX, moduleDB.posY)
    return
  end

  if type(moduleDB.posX) == "number" and type(moduleDB.posY) == "number" then
    frame:SetPoint("CENTER", UIParent, "CENTER", moduleDB.posX, moduleDB.posY)
    return
  end

  frame:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, defaultY or 0)
end

function FramePositioning.SaveAbsolutePosition(frame, moduleDB)
  if not frame or not moduleDB then
    return
  end

  local left = frame.GetLeft and frame:GetLeft()
  local top = frame.GetTop and frame:GetTop()
  if not left or not top then
    return
  end

  moduleDB.posX = left
  moduleDB.posY = top
  moduleDB.positionMode = "ABSOLUTE_TOPLEFT"
end

function FramePositioning.ResetToDefault(frame, moduleDB, defaultX, defaultY)
  if not moduleDB then
    return
  end

  moduleDB.posX = defaultX or 0
  moduleDB.posY = defaultY or 0
  moduleDB.positionMode = "CENTER_OFFSET"

  if frame then
    FramePositioning.ApplySavedPosition(frame, moduleDB, defaultX, defaultY)
  end
end

_G.SunderingToolsFramePositioning = FramePositioning

return FramePositioning
