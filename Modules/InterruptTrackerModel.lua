local Model = {}

local rolePriority = {
  TANK = 1,
  HEALER = 2,
  DAMAGER = 3,
}

local function IsReady(bar, now)
  local startTime = bar.startTime or 0
  local cd = bar.cd or 0
  return startTime == 0 or (now - startTime) >= cd
end

local function Remaining(bar, now)
  local startTime = bar.startTime or 0
  local cd = bar.cd or 0
  return cd - (now - startTime)
end

function Model.SortBars(bars, now)
  table.sort(bars, function(a, b)
    local aReady = IsReady(a, now)
    local bReady = IsReady(b, now)

    if aReady ~= bReady then
      return aReady
    end

    if aReady and bReady then
      local aPriority = rolePriority[a.role] or 9
      local bPriority = rolePriority[b.role] or 9
      if aPriority ~= bPriority then
        return aPriority < bPriority
      end
    else
      local aRemaining = Remaining(a, now)
      local bRemaining = Remaining(b, now)
      if aRemaining ~= bRemaining then
        return aRemaining < bRemaining
      end
    end

    return (a.key or a.name or "") < (b.key or b.name or "")
  end)

  return bars
end

function Model.BuildPreviewBars()
  return {
    { key = "tank-ready", name = "TankKick", role = "TANK", text = "Ready", value = 1 },
    { key = "melee", name = "MeleeKick", role = "DAMAGER", text = "7.4", value = 0.45 },
    { key = "ranged", name = "RangedKick", role = "DAMAGER", text = "13", value = 0.2 },
  }
end

return Model
