local SettingsModel = _G.SunderingToolsSettingsModel or {}

function SettingsModel.BuildSections(modules)
  local sections = {
    { key = "General", label = "General", kind = "general" },
  }

  local orderedModules = {}
  for index, moduleDef in ipairs(modules or {}) do
    orderedModules[index] = moduleDef
  end

  table.sort(orderedModules, function(a, b)
    local aOrder = a and a.order or 1000
    local bOrder = b and b.order or 1000

    if aOrder == bOrder then
      return (a.key or "") < (b.key or "")
    end

    return aOrder < bOrder
  end)

  for _, moduleDef in ipairs(orderedModules) do
    sections[#sections + 1] = {
      key = moduleDef.key,
      label = moduleDef.label,
      kind = "module",
    }
  end

  return sections
end

_G.SunderingToolsSettingsModel = SettingsModel

return SettingsModel
