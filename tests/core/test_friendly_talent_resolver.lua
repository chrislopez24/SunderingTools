local Resolver = dofile("Core/FriendlyTalentResolver.lua")

local resolver = Resolver.New()
resolver:SetUnitSpec("Party", 257)
assert(resolver:GetUnitSpec("Party") == 257, "talent resolver should preserve remote unit specs")

local context = resolver:ResolveContext({
  unit = "party1",
  classToken = "PRIEST",
})
assert(context.unit == "party1" and context.classToken == "PRIEST", "talent resolver should preserve context payloads")

print("ok")
