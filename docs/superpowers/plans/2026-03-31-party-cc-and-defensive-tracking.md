# Party CC And Defensive Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secret-safe active CC nameplate tracking, application-time CC cooldown bars, and sync-primary party defensive aura fallback while preserving the current addon UI.

**Architecture:** Introduce dedicated core watcher and resolver layers so active CC, CC cooldowns, and party personals share normalized runtime state instead of embedding detection logic inside UI modules. Keep sync as the primary truth for party personals, use aura-based CC as the live source for nameplates, and use a confidence-gated resolver to start CC cooldown bars at application time.

**Tech Stack:** WoW Lua addon modules, Blizzard aura/chat APIs, existing combat track engine/sync helpers, Lua unit/runtime tests, Python runtime-slice tests.

---

## Non-Negotiable Constraint

Internal logic may be rewritten aggressively, replaced, split, or deleted as needed. The implementation must preserve:

- the current configuration UI structure and usability
- the visible tracker UI patterns already exposed by the addon

Refactoring freedom applies to internals only. User-facing configuration and tracker presentation should remain recognizable unless a small compatibility adjustment is strictly required by the new behavior.

## File Structure

- Create: `Core/PartyCrowdControlAuraWatcher.lua`
  Purpose: Secret-safe watcher that normalizes live CC aura state into apply/update/remove events.
- Create: `Core/PartyCrowdControlResolver.lua`
  Purpose: Resolve spell, owner, cooldown, source, and confidence for CC cooldown state.
- Create: `Core/PartyDefensiveAuraFallback.lua`
  Purpose: Observe party defensive auras and publish fallback defensive cooldown records when sync is missing.
- Create: `Modules/NameplateCrowdControl.lua`
  Purpose: Show active CC on nameplates while the aura exists, without owning cooldown logic.
- Modify: `Modules/CrowdControlTracker.lua`
  Purpose: Consume resolved CC cooldown runtime records instead of owning low-level aura detection policy.
- Modify: `Modules/PartyDefensiveTracker.lua`
  Purpose: Consume sync-primary runtime state plus aura fallback for attached defensive icons.
- Modify: `Core/CombatTrackEngine.lua`
  Purpose: Support normalized promotion/update behavior for mixed source entries if needed by the resolver.
- Modify: `Core/CombatTrackSpellDB.lua`
  Purpose: Expose any CC/defensive metadata needed by resolver and fallback layers.
- Modify: `SunderingTools.toc`
  Purpose: Load new core and module files in a stable order.
- Create: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Create: `tests/core/test_party_crowd_control_resolver.lua`
- Create: `tests/modules/test_nameplate_crowd_control.lua`
- Modify: `tests/modules/test_crowd_control_tracker.lua`
- Modify: `tests/modules/test_party_defensive_tracker.lua`
- Modify: `tests/test_crowd_control_runtime_slice.py`
- Create: `tests/test_nameplate_crowd_control_runtime_slice.py`
- Modify: `tests/test_party_defensive_tracker_runtime_slice.py`

### Task 1: Add A Secret-Safe Party CC Aura Watcher

**Files:**
- Create: `Core/PartyCrowdControlAuraWatcher.lua`
- Modify: `SunderingTools.toc`
- Create: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Create: `tests/test_nameplate_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write the failing test**

```lua
local Watcher = dofile("Core/PartyCrowdControlAuraWatcher.lua")

local events = {}
local watcher = Watcher.New({
  getTime = function() return 100 end,
  isSecretValue = function(value) return value == "__SECRET__" end,
  isCrowdControl = function(spellID) return spellID == 118 end,
})

watcher:RegisterCallback(function(event, payload)
  events[#events + 1] = { event = event, payload = payload }
end)

watcher:ProcessAuraSnapshot("nameplate1", {
  {
    auraInstanceID = 9,
    spellId = 118,
    sourceUnit = "party1",
    expirationTime = 108,
  },
})

assert(#events == 1, "cc watcher should emit one apply event")
assert(events[1].event == "CC_APPLIED", "cc watcher should emit apply event")
assert(events[1].payload.unitToken == "nameplate1", "cc watcher should preserve target unit")
assert(events[1].payload.spellID == 118, "cc watcher should preserve usable spell ids")
assert(events[1].payload.remaining == 8, "cc watcher should derive remaining duration from expiration time")

watcher:ProcessAuraSnapshot("nameplate1", {
  {
    auraInstanceID = 10,
    spellId = "__SECRET__",
    sourceUnit = "__SECRET__",
    expirationTime = 104,
  },
})

assert(events[2].payload.spellID == nil, "secret spell ids should not be exposed")
assert(events[2].payload.sourceUnit == nil, "secret source units should not be exposed")
assert(events[2].payload.isCrowdControl == true, "classified crowd control should survive secret identity loss")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rtk test "lua tests/core/test_party_crowd_control_aura_watcher.lua"`
Expected: FAIL because `Core/PartyCrowdControlAuraWatcher.lua` does not exist yet

- [ ] **Step 3: Write minimal implementation**

```lua
local Watcher = {}
Watcher.__index = Watcher

local function copyAura(aura, now, isSecretValue)
  local spellID = aura.spellId
  local sourceUnit = aura.sourceUnit

  if isSecretValue and spellID ~= nil and isSecretValue(spellID) then
    spellID = nil
  end
  if isSecretValue and sourceUnit ~= nil and isSecretValue(sourceUnit) then
    sourceUnit = nil
  end

  local expirationTime = aura.expirationTime or 0
  local remaining = expirationTime > 0 and math.max(0, expirationTime - now) or 0

  return {
    auraInstanceID = aura.auraInstanceID,
    unitToken = aura.unitToken,
    spellID = spellID,
    sourceUnit = sourceUnit,
    remaining = remaining,
    isCrowdControl = aura.isCrowdControl == true,
  }
end

function Watcher.New(deps)
  return setmetatable({
    deps = deps or {},
    callbacks = {},
    activeByUnit = {},
  }, Watcher)
end

function Watcher:RegisterCallback(callback)
  self.callbacks[#self.callbacks + 1] = callback
end

function Watcher:Emit(event, payload)
  for _, callback in ipairs(self.callbacks) do
    callback(event, payload)
  end
end

function Watcher:ProcessAuraSnapshot(unitToken, auras)
  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local isSecretValue = self.deps.isSecretValue
  local isCrowdControl = self.deps.isCrowdControl or function() return false end
  local current = {}

  for _, aura in ipairs(auras or {}) do
    local usableSpellID = aura.spellId
    local classified = usableSpellID ~= nil and isCrowdControl(usableSpellID) or aura.isCrowdControl == true
    if classified and aura.auraInstanceID then
      aura.unitToken = unitToken
      aura.isCrowdControl = true
      current[aura.auraInstanceID] = copyAura(aura, now, isSecretValue)
    end
  end

  self.activeByUnit[unitToken] = self.activeByUnit[unitToken] or {}
  local previous = self.activeByUnit[unitToken]

  for auraInstanceID, payload in pairs(current) do
    if not previous[auraInstanceID] then
      self:Emit("CC_APPLIED", payload)
    else
      self:Emit("CC_UPDATED", payload)
    end
  end

  for auraInstanceID, payload in pairs(previous) do
    if not current[auraInstanceID] then
      self:Emit("CC_REMOVED", payload)
    end
  end

  self.activeByUnit[unitToken] = current
end

_G.SunderingToolsPartyCrowdControlAuraWatcher = Watcher

return Watcher
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk test "lua tests/core/test_party_crowd_control_aura_watcher.lua"`
Expected: PASS

Run: `rtk pytest tests/test_nameplate_crowd_control_runtime_slice.py -q`
Expected: PASS after the runtime-slice test asserts the new core watcher is loaded from the TOC

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyCrowdControlAuraWatcher.lua SunderingTools.toc tests/core/test_party_crowd_control_aura_watcher.lua tests/test_nameplate_crowd_control_runtime_slice.py
rtk git commit -m "feat: add secret-safe party cc aura watcher"
```

### Task 2: Add The CC Resolver And Refactor CrowdControlTracker To Consume It

**Files:**
- Create: `Core/PartyCrowdControlResolver.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Create: `tests/core/test_party_crowd_control_resolver.lua`
- Modify: `tests/modules/test_crowd_control_tracker.lua`
- Modify: `tests/test_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write the failing tests**

```lua
local Resolver = dofile("Core/PartyCrowdControlResolver.lua")

local resolver = Resolver.New({
  getTime = function() return 200 end,
  getCooldownForSpell = function(spellID)
    if spellID == 118 then
      return 30
    end
    return 0
  end,
})

local high = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate1",
  spellID = 118,
  sourceUnit = "party1",
  source = "aura",
})

assert(high ~= nil, "resolver should create a cc cooldown record for a usable aura")
assert(high.source == "aura", "resolver should preserve the source label")
assert(high.confidence == "high", "resolver should mark direct aura attribution high confidence")
assert(high.startTime == 200, "resolver should start cooldowns at application time")
assert(high.endTime == 230, "resolver should derive cooldown end from base cooldown")

local rejected = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate1",
  spellID = nil,
  sourceUnit = nil,
  source = "aura",
})

assert(rejected == nil, "resolver should reject unidentifiable crowd control cooldowns")
```

```lua
-- tests/modules/test_crowd_control_tracker.lua
local source = readfile and readfile("Modules/CrowdControlTracker.lua") or nil
assert(source == nil or source:find("SunderingToolsPartyCrowdControlResolver", 1, true), "crowd control tracker should depend on the resolver")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk test "lua tests/core/test_party_crowd_control_resolver.lua"`
Expected: FAIL because `Core/PartyCrowdControlResolver.lua` does not exist yet

Run: `rtk test "lua tests/modules/test_crowd_control_tracker.lua"`
Expected: FAIL because `CrowdControlTracker.lua` does not reference the resolver yet

- [ ] **Step 3: Write minimal implementation**

```lua
local Resolver = {}
Resolver.__index = Resolver

function Resolver.New(deps)
  return setmetatable({
    deps = deps or {},
  }, Resolver)
end

function Resolver:ResolveAppliedCrowdControl(event)
  if type(event) ~= "table" or type(event.spellID) ~= "number" or event.spellID <= 0 then
    return nil
  end

  local cooldown = (self.deps.getCooldownForSpell and self.deps.getCooldownForSpell(event.spellID)) or 0
  if cooldown <= 0 then
    return nil
  end

  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local confidence = (event.sourceUnit and event.sourceUnit ~= "") and "high" or "medium"

  return {
    kind = "CC_CD",
    spellID = event.spellID,
    ownerUnit = event.sourceUnit,
    targetUnit = event.targetUnit,
    source = event.source or "aura",
    confidence = confidence,
    startTime = now,
    endTime = now + cooldown,
    baseCd = cooldown,
  }
end

_G.SunderingToolsPartyCrowdControlResolver = Resolver

return Resolver
```

```lua
-- Modules/CrowdControlTracker.lua
local Resolver = assert(
  _G.SunderingToolsPartyCrowdControlResolver,
  "SunderingToolsPartyCrowdControlResolver must load before CrowdControlTracker.lua"
)

local resolver = Resolver.New({
  getTime = GetTime,
  getCooldownForSpell = function(spellID)
    local tracked = GetTrackedCrowdControlInfo(spellID)
    return tracked and tracked.cd or 0
  end,
})
```

```lua
-- when an aura application is observed and identified
local resolved = resolver:ResolveAppliedCrowdControl({
  targetUnit = unit,
  spellID = spellID,
  sourceUnit = sourcePartyUnit,
  source = "aura",
})

if resolved then
  local ownerGUID = resolved.ownerUnit and UnitGUID(resolved.ownerUnit)
  if ownerGUID then
    local applied = runtime.engine:ApplySyncState(ownerGUID, resolved.spellID, {
      kind = "CC",
      cd = resolved.baseCd,
      remaining = math.max(0, resolved.endTime - GetTime()),
      observedAt = resolved.startTime,
    })
    if applied then
      applied.source = resolved.source
      applied.startTime = resolved.startTime
      applied.readyAt = resolved.endTime
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk test "lua tests/core/test_party_crowd_control_resolver.lua"`
Expected: PASS

Run: `rtk test "lua tests/modules/test_crowd_control_tracker.lua"`
Expected: PASS

Run: `rtk pytest tests/test_crowd_control_runtime_slice.py -q`
Expected: PASS with updated runtime-slice assertions for watcher/resolver-backed cooldown starts

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyCrowdControlResolver.lua Modules/CrowdControlTracker.lua Core/CombatTrackEngine.lua Core/CombatTrackSpellDB.lua tests/core/test_party_crowd_control_resolver.lua tests/modules/test_crowd_control_tracker.lua tests/test_crowd_control_runtime_slice.py
rtk git commit -m "refactor: resolve cc cooldown bars from normalized aura events"
```

### Task 3: Add Active CC Nameplate Rendering Without Changing Cooldown Logic Ownership

**Files:**
- Create: `Modules/NameplateCrowdControl.lua`
- Modify: `SunderingTools.toc`
- Create: `tests/modules/test_nameplate_crowd_control.lua`
- Create: `tests/test_nameplate_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write the failing tests**

```lua
local modulePath = "Modules/NameplateCrowdControl.lua"
local chunk = loadfile(modulePath)
assert(chunk ~= nil, "nameplate cc module should load")
```

```python
from pathlib import Path

def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")

def test_nameplate_cc_module_is_loaded_from_toc():
    toc = read("SunderingTools.toc")
    assert "Modules\\NameplateCrowdControl.lua" in toc

def test_nameplate_cc_module_depends_on_party_cc_watcher():
    source = read("Modules/NameplateCrowdControl.lua")
    assert "SunderingToolsPartyCrowdControlAuraWatcher" in source
    assert "CC_APPLIED" in source
    assert "CC_REMOVED" in source
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk test "lua tests/modules/test_nameplate_crowd_control.lua"`
Expected: FAIL because the module file does not exist yet

Run: `rtk pytest tests/test_nameplate_crowd_control_runtime_slice.py -q`
Expected: FAIL because the TOC does not load the module yet

- [ ] **Step 3: Write minimal implementation**

```lua
local addon = _G.SunderingTools
if not addon then return end

local Watcher = assert(
  _G.SunderingToolsPartyCrowdControlAuraWatcher,
  "SunderingToolsPartyCrowdControlAuraWatcher must load before NameplateCrowdControl.lua"
)

local module = {
  key = "NameplateCrowdControl",
  label = "Nameplate Crowd Control",
  description = "Show active crowd control on nameplates while the aura exists.",
  order = 26,
  defaults = {
    enabled = true,
  },
}

local runtime = {
  activeByAura = {},
  watcher = Watcher.New({
    getTime = GetTime,
    isSecretValue = _G.issecretvalue,
    isCrowdControl = function(spellID)
      return C_Spell and C_Spell.IsSpellCrowdControl and C_Spell.IsSpellCrowdControl(spellID)
    end,
  }),
}

runtime.watcher:RegisterCallback(function(event, payload)
  if event == "CC_APPLIED" or event == "CC_UPDATED" then
    runtime.activeByAura[payload.auraInstanceID] = payload
  elseif event == "CC_REMOVED" then
    runtime.activeByAura[payload.auraInstanceID] = nil
  end
end)

addon.NameplateCrowdControl = module
addon:RegisterModule(module)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk test "lua tests/modules/test_nameplate_crowd_control.lua"`
Expected: PASS

Run: `rtk pytest tests/test_nameplate_crowd_control_runtime_slice.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Modules/NameplateCrowdControl.lua SunderingTools.toc tests/modules/test_nameplate_crowd_control.lua tests/test_nameplate_crowd_control_runtime_slice.py
rtk git commit -m "feat: add active cc nameplate module"
```

### Task 4: Add Sync-Primary Defensive Aura Fallback For Party Personal Icons

**Files:**
- Create: `Core/PartyDefensiveAuraFallback.lua`
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `tests/modules/test_party_defensive_tracker.lua`
- Modify: `tests/test_party_defensive_tracker_runtime_slice.py`

- [ ] **Step 1: Write the failing tests**

```lua
local Fallback = dofile("Core/PartyDefensiveAuraFallback.lua")
local events = {}
local fallback = Fallback.New({
  getTime = function() return 300 end,
  resolveSpell = function(spellID)
    if spellID == 48707 then
      return { spellID = 48707, kind = "DEF", cd = 60, classToken = "DEATHKNIGHT" }
    end
    return nil
  end,
})

fallback:RegisterCallback(function(payload)
  events[#events + 1] = payload
end)

fallback:ProcessAuraRemoved("party1", {
  spellID = 48707,
  source = "aura",
  startTime = 290,
  endTime = 300,
})

assert(#events == 1, "defensive fallback should emit a cooldown record when a tracked defensive ends")
assert(events[1].spellID == 48707, "defensive fallback should preserve spell id")
assert(events[1].baseCd == 60, "defensive fallback should derive cooldown from spell db")
assert(events[1].startTime == 300, "defensive fallback cooldown should start from aura end time")
assert(events[1].readyAt == 360, "defensive fallback cooldown should extend to cooldown completion")
```

```lua
-- tests/modules/test_party_defensive_tracker.lua
state.db.strictSyncMode = false
state.runtime.partyUsers.Other = {
  key = "Other",
  playerGUID = "other-guid",
  playerName = "Other",
  classToken = "DEATHKNIGHT",
  specID = 250,
  unitToken = "party1",
  spellIDs = {},
}
state.applyDefensiveFallback({
  ownerUnit = "party1",
  spellID = 48707,
  startTime = 300,
  readyAt = 360,
  source = "aura",
})
assert(state.runtime.engine:GetEntry("other-guid:48707") ~= nil, "party defensive tracker should accept fallback state when sync is absent")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk test "lua tests/modules/test_party_defensive_tracker.lua"`
Expected: FAIL because the tracker does not expose or consume aura fallback yet

Run: `rtk pytest tests/test_party_defensive_tracker_runtime_slice.py -q`
Expected: FAIL because the runtime slice does not reference `PartyDefensiveAuraFallback`

- [ ] **Step 3: Write minimal implementation**

```lua
local Fallback = {}
Fallback.__index = Fallback

function Fallback.New(deps)
  return setmetatable({
    deps = deps or {},
    callbacks = {},
  }, Fallback)
end

function Fallback:RegisterCallback(callback)
  self.callbacks[#self.callbacks + 1] = callback
end

function Fallback:Emit(payload)
  for _, callback in ipairs(self.callbacks) do
    callback(payload)
  end
end

function Fallback:ProcessAuraRemoved(ownerUnit, aura)
  local tracked = self.deps.resolveSpell and self.deps.resolveSpell(aura.spellID)
  if not tracked or tracked.kind ~= "DEF" then
    return
  end

  local now = (self.deps.getTime and self.deps.getTime()) or 0
  self:Emit({
    ownerUnit = ownerUnit,
    spellID = tracked.spellID,
    source = "aura",
    startTime = now,
    readyAt = now + tracked.cd,
    baseCd = tracked.cd,
  })
end

_G.SunderingToolsPartyDefensiveAuraFallback = Fallback

return Fallback
```

```lua
-- Modules/PartyDefensiveTracker.lua
local Fallback = assert(
  _G.SunderingToolsPartyDefensiveAuraFallback,
  "SunderingToolsPartyDefensiveAuraFallback must load before PartyDefensiveTracker.lua"
)

runtime.fallback = Fallback.New({
  getTime = GetTime,
  resolveSpell = function(spellID)
    local tracked = SpellDB.ResolveDefensiveSpell(spellID, nil)
    if tracked and tracked.kind == "DEF" then
      return tracked
    end
    return nil
  end,
})

local function ApplyDefensiveFallback(payload)
  local unit = payload and payload.ownerUnit
  if not unit or not UnitExists(unit) then
    return
  end

  local user = runtime.partyUsers[ShortName(UnitName(unit))]
  if not user then
    return
  end

  local runtimeKey = BuildRuntimeKey(user.playerGUID, payload.spellID)
  local existing = runtime.engine:GetEntry(runtimeKey)
  if existing and (existing.source == "self" or existing.source == "sync") then
    return
  end

  local applied = runtime.engine:UpsertEntry({
    key = runtimeKey,
    playerGUID = user.playerGUID,
    playerName = user.playerName,
    classToken = user.classToken,
    unitToken = user.unitToken,
    spellID = payload.spellID,
    source = "aura",
    kind = "DEF",
    startTime = payload.startTime,
    readyAt = payload.readyAt,
    baseCd = payload.baseCd,
    cd = payload.baseCd,
  })

  if applied then
    UpdateAttachments()
  end
end

runtime.fallback:RegisterCallback(ApplyDefensiveFallback)
module.applyDefensiveFallback = ApplyDefensiveFallback
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk test "lua tests/modules/test_party_defensive_tracker.lua"`
Expected: PASS

Run: `rtk pytest tests/test_party_defensive_tracker_runtime_slice.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyDefensiveAuraFallback.lua Modules/PartyDefensiveTracker.lua Core/CombatTrackSpellDB.lua tests/modules/test_party_defensive_tracker.lua tests/test_party_defensive_tracker_runtime_slice.py
rtk git commit -m "feat: add sync-primary defensive aura fallback"
```

### Task 5: Final Regression Verification And Runtime Cleanup

**Files:**
- Modify: any touched tests if required by focused regressions
- Modify: `README.md` only if user-facing behavior description needs updating after implementation

- [ ] **Step 1: Add focused regression assertions**

```python
def test_toc_loads_new_party_cc_files():
    from pathlib import Path
    toc = Path("SunderingTools.toc").read_text(encoding="utf-8")
    assert "Core\\PartyCrowdControlAuraWatcher.lua" in toc
    assert "Core\\PartyCrowdControlResolver.lua" in toc
    assert "Core\\PartyDefensiveAuraFallback.lua" in toc
    assert "Modules\\NameplateCrowdControl.lua" in toc
```

- [ ] **Step 2: Run focused Lua verification**

Run: `rtk summary "lua tests/core/test_party_crowd_control_aura_watcher.lua && lua tests/core/test_party_crowd_control_resolver.lua && lua tests/modules/test_crowd_control_tracker.lua && lua tests/modules/test_nameplate_crowd_control.lua && lua tests/modules/test_party_defensive_tracker.lua"`
Expected: All focused Lua tests pass

- [ ] **Step 3: Run focused Python runtime-slice verification**

Run: `rtk summary "pytest tests/test_crowd_control_runtime_slice.py tests/test_nameplate_crowd_control_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py -q"`
Expected: All focused runtime-slice tests pass

- [ ] **Step 4: Run broader regression verification**

Run: `rtk summary "lua tests/run.lua && pytest tests/test_hybrid_interrupt_cc.py tests/test_interrupt_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py -q"`
Expected: Existing interrupt, hybrid, sync, and defensive raid regressions continue to pass

- [ ] **Step 5: Commit**

```bash
rtk git add README.md SunderingTools.toc tests
rtk git commit -m "test: verify party cc and defensive tracking regressions"
```
