local Config = {}

local function CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

function Config.MergeDefaults(db, defaults)
    return CopyDefaults(db or {}, defaults or {})
end

_G.SunderingToolsConfig = Config

return Config
