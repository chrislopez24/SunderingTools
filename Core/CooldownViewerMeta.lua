local Meta = {}

local MAX_CATEGORY_ID = 64
local bySpellID = {}
local loaded = false

local function wipeTable(target)
  for key in pairs(target) do
    target[key] = nil
  end
end

local function indexCooldownInfo(cooldownInfo)
  if type(cooldownInfo) ~= "table" then
    return
  end

  local spellID = cooldownInfo.spellID
  if type(spellID) ~= "number" or spellID <= 0 then
    return
  end

  local record = {
    cooldownID = cooldownInfo.cooldownID,
    spellID = spellID,
    overrideSpellID = cooldownInfo.overrideSpellID,
    linkedSpellIDs = cooldownInfo.linkedSpellIDs or {},
    hasCharges = cooldownInfo.charges == true,
    category = cooldownInfo.category,
  }

  bySpellID[spellID] = record

  if type(record.overrideSpellID) == "number" and record.overrideSpellID > 0 then
    bySpellID[record.overrideSpellID] = record
  end

  for _, linkedSpellID in ipairs(record.linkedSpellIDs) do
    if type(linkedSpellID) == "number" and linkedSpellID > 0 then
      bySpellID[linkedSpellID] = record
    end
  end
end

local function ensureLoaded()
  if loaded then
    return
  end

  loaded = true

  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
    return
  end

  for category = 0, MAX_CATEGORY_ID do
    for _, cooldownID in ipairs(C_CooldownViewer.GetCooldownViewerCategorySet(category, true) or {}) do
      indexCooldownInfo(C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID))
    end
  end
end

function Meta.Reset()
  loaded = false
  wipeTable(bySpellID)
end

function Meta.ResolveSpellMetadata(spellID)
  ensureLoaded()
  return bySpellID[spellID]
end

_G.SunderingToolsCooldownViewerMeta = Meta

return Meta
