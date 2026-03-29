local Model = dofile("Modules/BloodlustSoundModel.lua")

assert(Model.NormalizeChannel(nil) == "Master", "default channel should be Master")
assert(Model.NormalizeChannel("SFX") == "SFX", "explicit channel should be preserved")
assert(Model.NormalizeChannel("") == "Master", "empty channel should fall back to Master")
assert(Model.NormalizeChannel("   ") == "Master", "whitespace channel should fall back to Master")
assert(Model.NormalizeChannel("Invalid") == "Master", "unknown channel should fall back to Master")
assert(Model.ResolveDuration(nil, 40) == 40, "fallback duration should use config value")
assert(Model.ResolveDuration(25, 40) == 25, "aura duration should override fallback")

local channels = Model.ChannelOptions()
assert(channels[1] == "Master", "channel options should start with Master")
assert(channels[2] == "SFX", "channel options should include SFX")
assert(channels[#channels] == "Dialog", "channel options should include Dialog")
