local Model = {}
local CHANNEL_OPTIONS = {
  "Master",
  "SFX",
  "Music",
  "Ambience",
  "Dialog",
}
local VALID_CHANNELS = {}

for _, channel in ipairs(CHANNEL_OPTIONS) do
  VALID_CHANNELS[channel] = true
end

function Model.NormalizeChannel(channel)
  if type(channel) ~= "string" then
    return "Master"
  end

  channel = channel:match("^%s*(.-)%s*$")
  if channel == "" then
    return "Master"
  end

  if VALID_CHANNELS[channel] then
    return channel
  end

  return "Master"
end

function Model.ResolveDuration(explicitDuration, fallbackDuration)
  return explicitDuration or fallbackDuration
end

function Model.ChannelOptions()
  return CHANNEL_OPTIONS
end

return Model
