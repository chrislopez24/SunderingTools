local Meta = {}

local bySpellID = {}
local loaded = false
local FALLBACK_CATEGORY_IDS = { 0, 1, 2, 3 }

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

local function listCategoryIDs()
  local enum = Enum and Enum.CooldownViewerCategory
  if type(enum) ~= "table" then
    return FALLBACK_CATEGORY_IDS
  end

  local categoryIDs = {}
  local seen = {}
  for _, value in pairs(enum) do
    if type(value) == "number" and not seen[value] then
      seen[value] = true
      categoryIDs[#categoryIDs + 1] = value
    end
  end

  if #categoryIDs == 0 then
    return FALLBACK_CATEGORY_IDS
  end

  table.sort(categoryIDs)
  return categoryIDs
end

local function ensureLoaded()
  if loaded then
    return
  end

  loaded = true

  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
    return
  end

  for _, category in ipairs(listCategoryIDs()) do
    local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if ok then
      for _, cooldownID in ipairs(cooldownIDs or {}) do
      indexCooldownInfo(C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID))
      end
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
