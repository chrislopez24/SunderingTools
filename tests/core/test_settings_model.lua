local SettingsModel = dofile("Core/SettingsModel.lua")

local sections = SettingsModel.BuildSections({
  { key = "BloodlustSound", label = "Bloodlust Sound", order = 20 },
  { key = "InterruptTracker", label = "Interrupt Tracker", order = 10 },
})

assert(sections[1].key == "General", "general section should always be first")
assert(sections[2].key == "InterruptTracker", "modules should be ordered")
assert(sections[3].key == "BloodlustSound", "second module should follow order")
