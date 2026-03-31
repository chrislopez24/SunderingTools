local Meta = dofile("Core/CooldownViewerMeta.lua")

local originalCooldownViewer = C_CooldownViewer

C_CooldownViewer = {
  GetCooldownViewerCooldownInfo = function(cooldownID)
    if cooldownID == 77 then
      return {
        cooldownID = 77,
        spellID = 2139,
        overrideSpellID = 12051,
        linkedSpellIDs = { 999001 },
        charges = true,
        category = 3,
      }
    end
  end,
  GetCooldownViewerCategorySet = function(category)
    if category < 0 or category > 3 then
      error("invalid cooldown viewer category", 0)
    end

    if category == 3 then
      return { 77 }
    end

    return {}
  end,
}

Meta.Reset()

local info = Meta.ResolveSpellMetadata(2139)
assert(info ~= nil, "helper should resolve metadata by base spell id")
assert(info.spellID == 2139, "helper should preserve the base spell id")
assert(info.overrideSpellID == 12051, "helper should preserve the override spell id")
assert(info.hasCharges == true, "helper should expose charges capability")

local linked = Meta.ResolveSpellMetadata(999001)
assert(linked ~= nil, "helper should resolve metadata by linked spell id")
assert(linked.spellID == 2139, "linked spell ids should point back to the canonical spell")

C_CooldownViewer = originalCooldownViewer

print("ok")
