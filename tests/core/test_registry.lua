local Config = dofile("Core/Config.lua")
local Registry = dofile("Core/Registry.lua")

local defaults = {
  global = { minimap = { hide = false } },
  modules = {
    InterruptTracker = { enabled = true, maxBars = 5 },
  },
}

local db = Config.MergeDefaults({ modules = { InterruptTracker = {} } }, defaults)
assert(db.global.minimap.hide == false, "global defaults should merge")
assert(db.modules.InterruptTracker.enabled == true, "module defaults should merge")
assert(db.modules.InterruptTracker.maxBars == 5, "missing module keys should merge")

local registry = Registry.New()
registry:Register({ key = "BloodlustSound", order = 20, label = "Bloodlust Tracker" })
registry:Register({ key = "InterruptTracker", order = 10, label = "Interrupt Tracker" })

local ordered = registry:List()
assert(ordered[1].key == "InterruptTracker", "modules should sort by order")
assert(ordered[2].key == "BloodlustSound", "modules should preserve registration payload")
