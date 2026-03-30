local SettingsModel = dofile("Core/SettingsModel.lua")

local sections = SettingsModel.BuildSections({
  { key = "BloodlustSound", label = "Bloodlust Tracker", description = "Sound alerts, icon behavior, and placement.", order = 20 },
  { key = "InterruptTracker", label = "Interrupt Tracker", description = "Track interrupts, sync party data, and adjust layout.", order = 10 },
})

assert(sections[1].key == "General", "general section should always be first")
assert(sections[1].description == "Core addon controls.", "general section should expose concise header copy")
assert(sections[2].key == "InterruptTracker", "modules should be ordered")
assert(sections[2].description == "Track interrupts, sync party data, and adjust layout.", "module descriptions should flow through")
assert(sections[3].key == "BloodlustSound", "second module should follow order")
