local Resolver = {}
Resolver.__index = Resolver

function Resolver.New(deps)
  return setmetatable({
    deps = deps or {},
  }, Resolver)
end

function Resolver:ResolveAppliedCrowdControl(event)
  if type(event) ~= "table" then
    return nil
  end

  local spellID = event.spellID
  if type(spellID) ~= "number" or spellID <= 0 then
    return nil
  end

  local cooldown = (self.deps.getCooldownForSpell and self.deps.getCooldownForSpell(spellID)) or 0
  if type(cooldown) ~= "number" or cooldown <= 0 then
    return nil
  end

  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local ownerUnit = event.ownerUnit or event.sourceUnit
  local source = event.source or "aura"
  local confidence = "medium"

  if source == "aura" and type(event.sourceUnit) == "string" and event.sourceUnit ~= "" then
    confidence = "high"
  end

  return {
    kind = "CC_CD",
    spellID = spellID,
    ownerUnit = ownerUnit,
    targetUnit = event.targetUnit,
    source = source,
    confidence = confidence,
    startTime = now,
    endTime = now + cooldown,
    baseCd = cooldown,
  }
end

_G.SunderingToolsPartyCrowdControlResolver = Resolver

return Resolver
