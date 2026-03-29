local Model = dofile("Modules/BloodlustSoundModel.lua")

assert(Model.NormalizeChannel(nil) == "Master", "default channel should be Master")
assert(Model.NormalizeChannel("SFX") == "SFX", "explicit channel should be preserved")
assert(Model.ResolveDuration(nil, 40) == 40, "fallback duration should use config value")
assert(Model.ResolveDuration(25, 40) == 25, "aura duration should override fallback")
