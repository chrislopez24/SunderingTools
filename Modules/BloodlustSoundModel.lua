local Model = {}
local CHANNEL_OPTIONS = {
  "Master",
  "SFX",
  "Music",
  "Ambience",
  "Dialog",
}

function Model.NormalizeChannel(channel)
  return channel or "Master"
end

function Model.ResolveDuration(explicitDuration, fallbackDuration)
  return explicitDuration or fallbackDuration
end

function Model.ChannelOptions()
  return CHANNEL_OPTIONS
end

return Model
