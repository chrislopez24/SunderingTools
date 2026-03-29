local Model = {}

function Model.NormalizeChannel(channel)
  return channel or "Master"
end

function Model.ResolveDuration(explicitDuration, fallbackDuration)
  return explicitDuration or fallbackDuration
end

return Model
