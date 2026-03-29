-- BloodlustSound
-- Play sound and show icon when bloodlust/heroism is cast

local addon = _G.SunderingTools
if not addon then return end

local db = addon.db and addon.db.BloodlustSound

-- Bloodlust spell IDs
local BloodlustSpells = {
    2825,   -- Bloodlust (Shaman)
    32182,  -- Heroism (Shaman)
    80353,  -- Time Warp (Mage)
    90355,  -- Ancient Hysteria (Hunter - Core Hound)
    160452, -- Netherwinds (Hunter - Nether Ray)
    264667, -- Primal Rage (Hunter - Ferocity)
    390386, -- Fury of the Aspects (Evoker)
}

-- Exhaustion debuff IDs (to verify bloodlust)
local ExhaustionIDs = {
    57723,  -- Exhaustion
    57724,  -- Sated
    80354,  -- Temporal Displacement
    95809,  -- Insanity
    160455, -- Fatigued
    207400, -- Temporal Displacement (different)
    264689, -- Fatigued
    390435, -- Exhaustion (Evoker)
}

-- UI Frame
local frame = nil
local activeTimer = nil
local lastSoundHandle = nil

-- Check if player has exhaustion debuff
local function CheckExhaustion()
    for _, spellID in ipairs(ExhaustionIDs) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura then
            local remaining = aura.expirationTime - GetTime()
            -- If debuff is fresh (within 5 seconds of application)
            if remaining >= 595 then -- 600 - 5 = 595
                return true, aura.expirationTime
            end
        end
    end
    return false, nil
end

-- Stop effect
local function StopEffect()
    if lastSoundHandle then
        StopSound(lastSoundHandle)
        lastSoundHandle = nil
    end
    if activeTimer then
        activeTimer:Cancel()
        activeTimer = nil
    end
    if frame then
        frame:Hide()
    end
end

-- Play effect
local function PlayEffect(expirationTime)
    if not db or not db.enabled then return end

    StopEffect()

    -- Play sound
    if db.soundFile and db.soundFile ~= "" then
        local _, handle = PlaySoundFile(db.soundFile, db.soundChannel or "Master")
        lastSoundHandle = handle
    end

    -- Show icon if not hidden
    if not db.hideIcon and frame then
        frame:Show()

        local now = GetTime()
        local duration = db.duration or 40

        -- If we have expiration time from debuff, use it
        if expirationTime and expirationTime > now then
            duration = expirationTime - now
        end

        -- Set cooldown
        frame.cooldown:SetCooldown(now, duration)

        -- Update timer text
        local timeLeft = duration
        activeTimer = C_Timer.NewTicker(0.1, function()
            timeLeft = timeLeft - 0.1
            if timeLeft <= 0 then
                StopEffect()
            else
                frame.timerText:SetText(math.ceil(timeLeft))
            end
        end)
    end
end

-- Create frame
local function CreateFrame_()
    frame = CreateFrame("Frame", "SunderingToolsBloodlustFrame", UIParent)
    frame:SetSize(db.iconSize, db.iconSize)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)

    -- Background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Icon
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Use bloodlust icon by default
    frame.icon:SetTexture(132313)

    -- Cooldown frame
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    -- Timer text
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timerText:SetPoint("CENTER", 0, 0)
    frame.timerText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    frame.timerText:SetTextColor(1, 1, 0)

    -- Make draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.posX = x
        db.posY = y
    end)

    frame:Hide()
end

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        db = addon.db.BloodlustSound
        if db.enabled then
            CreateFrame_()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget, castGUID, spellID = ...
        -- Check if bloodlust was cast
        for _, id in ipairs(BloodlustSpells) do
            if spellID == id then
                -- Delay slightly to let debuff apply
                C_Timer.After(0.5, function()
                    local hasExhaustion, expiration = CheckExhaustion()
                    if hasExhaustion then
                        PlayEffect(expiration)
                    end
                end)
                break
            end
        end
    elseif event == "UNIT_AURA" then
        local unitTarget = ...
        if unitTarget == "player" then
            -- Check if we got exhaustion debuff
            local hasExhaustion, expiration = CheckExhaustion()
            if hasExhaustion and (not activeTimer or not frame:IsShown()) then
                PlayEffect(expiration)
            end
        end
    end
end)

-- Test command
SLASH_SUNDERINGTOOLS_TEST1 = "/su test"
SlashCmdList["SUNDERINGTOOLS_TEST"] = function()
    if addon.db.BloodlustSound.enabled then
        PlayEffect()
        print("|cff00ff00SunderingTools:|r Bloodlust test triggered!")
    else
        print("|cff00ff00SunderingTools:|r Bloodlust sound is disabled.")
    end
end

-- Expose functions
addon.BloodlustSound = {
    Play = PlayEffect,
    Stop = StopEffect,
}
