local Resolver = {}
Resolver.__index = Resolver

local function copyTable(source)
  local copy = {}
  for key, value in pairs(source or {}) do
    copy[key] = value
  end
  return copy
end

function Resolver.New(deps)
  deps = deps or {}
  return setmetatable({
    deps = deps,
    localSpecID = nil,
    byPlayerName = {},
  }, Resolver)
end

function Resolver:Reset()
  self.localSpecID = nil
  self.byPlayerName = {}
end

function Resolver:GetLocalSpecID()
  if self.localSpecID then
    return self.localSpecID
  end

  if GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local specID = GetSpecializationInfo(specIndex)
      if type(specID) == "number" and specID > 0 then
        self.localSpecID = specID
        return specID
      end
    end
  end

  return nil
end

function Resolver:SetUnitSpec(playerName, specID)
  if type(playerName) ~= "string" or playerName == "" then
    return
  end

  self.byPlayerName[playerName] = self.byPlayerName[playerName] or {}
  self.byPlayerName[playerName].specID = specID
end

function Resolver:GetUnitSpec(playerName)
  local entry = type(playerName) == "string" and self.byPlayerName[playerName] or nil
  return entry and entry.specID or nil
end

function Resolver:ResolveContext(unitContext)
  return copyTable(unitContext)
end

_G.SunderingToolsFriendlyTalentResolver = Resolver

return Resolver
