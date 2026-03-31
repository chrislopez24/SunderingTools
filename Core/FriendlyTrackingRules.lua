local Rules = {}

local SpellDB = _G.SunderingToolsCombatTrackSpellDB

local function ResolveSpecCooldown(value, bySpec, specID)
  if type(specID) == "number" and type(bySpec) == "table" then
    local variant = bySpec[specID]
    if type(variant) == "number" and variant > 0 then
      return variant
    end
  end

  return value
end

function Rules.ResolveDefensive(spellID, specID)
  if not SpellDB or not SpellDB.GetDefensiveSpell then
    return nil
  end

  local entry = SpellDB.GetDefensiveSpell(spellID)
  if not entry then
    return nil
  end

  local resolved = {}
  for key, value in pairs(entry) do
    resolved[key] = value
  end
  resolved.cd = ResolveSpecCooldown(entry.cd, entry.cdBySpec, specID)
  resolved.charges = ResolveSpecCooldown(entry.charges, entry.chargesBySpec, specID)
  return resolved
end

function Rules.MatchDefensive(unitContext, tracked, measuredDuration, evidence)
  if not SpellDB or not SpellDB.GetDefensiveSpellsForClass then
    return nil
  end

  local classToken = unitContext and unitContext.classToken or nil
  if not classToken then
    return nil
  end

  local specID = unitContext and unitContext.specID or nil
  local entries = SpellDB.GetDefensiveSpellsForClass(classToken)
  local fallback = nil

  for _, entry in ipairs(entries or {}) do
    local resolvedCd = ResolveSpecCooldown(entry.cd, entry.cdBySpec, specID)
    if tracked and tracked.AuraTypes and tracked.AuraTypes.EXTERNAL_DEFENSIVE and entry.sourceType == "externalDefensive" then
      if tracked.SpellId and (entry.auraSpellID == tracked.SpellId or entry.spellID == tracked.SpellId) then
        local resolved = {}
        for key, value in pairs(entry) do
          resolved[key] = value
        end
        resolved.cd = resolvedCd
        return resolved
      end
      if not fallback and type(resolvedCd) == "number" and resolvedCd > 0 then
        fallback = entry
      end
    elseif tracked and tracked.AuraTypes and tracked.AuraTypes.BIG_DEFENSIVE and entry.sourceType ~= "externalDefensive" then
      if type(resolvedCd) == "number" and resolvedCd > 0 then
        if tracked.SpellId and (entry.auraSpellID == tracked.SpellId or entry.spellID == tracked.SpellId) then
          local resolved = {}
          for key, value in pairs(entry) do
            resolved[key] = value
          end
          resolved.cd = resolvedCd
          return resolved
        end

        if not fallback and type(measuredDuration) == "number" and measuredDuration > 0 then
          fallback = entry
        end
      end
    end
  end

  if fallback then
    local resolved = {}
    for key, value in pairs(fallback) do
      resolved[key] = value
    end
    resolved.cd = ResolveSpecCooldown(fallback.cd, fallback.cdBySpec, specID)
    return resolved
  end

  return nil
end

function Rules.MatchRaidDefensive(unitContext, tracked, measuredDuration, evidence)
  if not SpellDB or not SpellDB.GetRaidDefensiveSpellsForClass then
    return nil
  end

  local classToken = unitContext and unitContext.classToken or nil
  if not classToken then
    return nil
  end

  local specID = unitContext and unitContext.specID or nil
  local entries = SpellDB.GetRaidDefensiveSpellsForClass(classToken)
  local fallback = nil

  for _, entry in ipairs(entries or {}) do
    local resolvedCd = ResolveSpecCooldown(entry.cd, entry.cdBySpec, specID)
    if tracked.SpellId and (entry.auraSpellID == tracked.SpellId or entry.spellID == tracked.SpellId) then
      local resolved = {}
      for key, value in pairs(entry) do
        resolved[key] = value
      end
      resolved.cd = resolvedCd
      return resolved
    end

    if not fallback and type(resolvedCd) == "number" and resolvedCd > 0 then
      fallback = entry
    end
  end

  if fallback then
    local resolved = {}
    for key, value in pairs(fallback) do
      resolved[key] = value
    end
    resolved.cd = ResolveSpecCooldown(fallback.cd, fallback.cdBySpec, specID)
    return resolved
  end

  return nil
end

function Rules.ResolveInterrupt(spellID, specID, classToken)
  if not SpellDB then
    return nil
  end

  if specID and SpellDB.GetInterruptForSpec then
    local interrupt = SpellDB.GetInterruptForSpec(specID)
    if interrupt and interrupt.spellID == spellID then
      return interrupt
    end
  end

  if classToken and SpellDB.GetInterruptForClass then
    local interrupt = SpellDB.GetInterruptForClass(classToken)
    if interrupt and interrupt.spellID == spellID then
      return interrupt
    end
  end

  return nil
end

_G.SunderingToolsFriendlyTrackingRules = Rules

return Rules
