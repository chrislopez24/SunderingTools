local Registry = {}
Registry.__index = Registry

function Registry.New()
    return setmetatable({ modules = {} }, Registry)
end

function Registry:Register(moduleDef)
    assert(type(moduleDef) == "table" and moduleDef.key, "moduleDef.key is required")
    self.modules[moduleDef.key] = moduleDef
end

function Registry:List()
    local list = {}

    for _, moduleDef in pairs(self.modules) do
        list[#list + 1] = moduleDef
    end

    table.sort(list, function(a, b)
        local aOrder = a.order or 1000
        local bOrder = b.order or 1000

        if aOrder == bOrder then
            return a.key < b.key
        end

        return aOrder < bOrder
    end)

    return list
end

_G.SunderingToolsRegistry = Registry

return Registry
