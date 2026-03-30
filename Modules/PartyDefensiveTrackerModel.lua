local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before PartyDefensiveTrackerModel.lua"
)

local Model = {}

local function cloneEntry(entry)
  local copy = {}
  for key, value in pairs(entry or {}) do
    copy[key] = value
  end
  return copy
end

function Model.FormatTimerText(remaining)
  return string.format("%.0fs", remaining), math.floor(remaining + 0.5)
end

function Model.GetAvailableSpells(classToken)
  if not classToken then
    return {}
  end

  return SpellDB.GetDefensiveSpellsForClass(classToken)
end

function Model.BuildPreviewIcons(classToken)
  local available = Model.GetAvailableSpells(classToken or "DEATHKNIGHT")
  local preview = {}

  for index, entry in ipairs(available) do
    local icon = cloneEntry(entry)
    icon.key = "party-def-preview-" .. tostring(index)
    icon.kind = "DEF"

    if index == 1 then
      icon.startTime = 0
      icon.previewText = "Ready"
      icon.previewValue = 1
    elseif index == 2 then
      icon.startTime = 72
      icon.previewRemaining = 32
      icon.previewText = "32s"
      icon.previewValue = 0.47
    else
      icon.startTime = 24
      icon.previewRemaining = 14
      icon.previewText = "14s"
      icon.previewValue = 0.84
    end

    preview[#preview + 1] = icon
  end

  return preview
end

function Model.SortIcons(entries, now)
  table.sort(entries, function(a, b)
    local aRemaining = math.max(0, (a.cd or 0) - ((now or 0) - (a.startTime or 0)))
    local bRemaining = math.max(0, (b.cd or 0) - ((now or 0) - (b.startTime or 0)))
    local aReady = (a.startTime or 0) <= 0 or aRemaining <= 0
    local bReady = (b.startTime or 0) <= 0 or bRemaining <= 0

    if aReady ~= bReady then
      return not aReady
    end

    if not aReady and aRemaining ~= bRemaining then
      return aRemaining > bRemaining
    end

    if (a.spellID or 0) ~= (b.spellID or 0) then
      return (a.spellID or 0) > (b.spellID or 0)
    end

    return (a.key or "") < (b.key or "")
  end)

  return entries
end

_G.SunderingToolsPartyDefensiveTrackerModel = Model

return Model
