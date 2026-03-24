local addonName, MA = ...

-- Constants
local ALERT_THROTTLE = 0.5
local TTS_COALESCE_WINDOW = 0.15  -- collect simultaneous TTS for this long before speaking once
local POLL_INTERVAL = 0.3  -- safety-net poll; events are the primary mechanism

-- Defaults
local defaults = {
    enabled = true,
    alertInCombat = true,
    showVisual = true,
    alertScale = 1.0,
    alertPos = nil,  -- { point, relPoint, x, y }
    ttsVoice = 0,   -- 0-based index into C_VoiceChat.GetTtsVoices() (0 = first voice)
}

-- Per-character defaults
local charDefaults = {
    trackedSpells = {},
    trackedItems = {},
}

MA.usableState = {}        -- [spellID] = true/false (normalized boolean)
MA.usableFalseAt = {}     -- [spellID] = GetTime() when spell last transitioned to false
MA.spellCastSeen = {}     -- [spellID] = true when a real cast was observed this session
MA.itemCastSeen = {}      -- [itemID]  = true when a real item use was observed this session
MA.resourceReady = {}     -- [spellID] = true/false/nil for custom resource threshold
MA.lastAlertTime = {}
MA.lastSpellAlert = {}    -- [spellID] = GetTime() per-spell alert cooldown
MA.alertPool = {}         -- [1..4] pool of alert frames; slot 1 = draggable anchor
MA.ttsQueue = {}          -- TTS texts queued for coalesced speak
MA.ttsFlushPending = false -- whether a C_Timer flush is already scheduled
MA._activeSpellCache = {} -- [baseID]  = activeID for known tracked spells; rebuilt by BuildOverrideMap
MA.lastSpellCheckTime = 0 -- GetTime() of last event-driven spell check (throttle)
MA.lastItemCheckTime = 0  -- GetTime() of last event-driven item check (throttle)
MA._displayTextOpen = {}  -- [rowKey] = true when the display-text edit box is open in the config UI
MA.initialized = false
MA.elapsed = 0
MA.debugMode = false

-------------------------------------------------------------------------------
-- Minimap Button (no library required)
-------------------------------------------------------------------------------

--[[
    CreateMinimapButton
    Creates a Blizzard-style minimap button for MochaAlerts, using a custom icon and proper layering.
    - Uses Blizzard's border, background, and highlight textures.
    - Icon is round-cropped and centered.
    - Button is draggable and remembers its position as an angle around the minimap.
    - Left-click toggles the config UI.
]]
local function CreateMinimapButton()
    if MA.MinimapButton then return end

    local BUTTON_SIZE = 32
    local ICON_SIZE = 18
    local BORDER_SIZE = 50
    local BG_SIZE = 24
    local HIGHLIGHT_SIZE = 32
    local MINIMAP_RADIUS = 100

    local function UpdateMinimapPos(btn)
        local angle = (MochaAlertsCharDB and MochaAlertsCharDB.minimapAngle) or 215
        local rad = math.rad(angle)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * MINIMAP_RADIUS, math.sin(rad) * MINIMAP_RADIUS)
    end

    local button = CreateFrame("Button", "MochaAlertsMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    -- Background (Blizzard style)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467) -- "Interface\\Minimap\\UI-Minimap-Background"
    background:SetSize(BG_SIZE, BG_SIZE)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.background = background

    -- Icon (custom, round crop)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\MochaAlerts\\Media\\Textures\\coffeeAlert.tga")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    button.icon = icon

    -- Border (Blizzard style)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430) -- "Interface\\Minimap\\MiniMap-TrackingBorder"
    border:SetSize(BORDER_SIZE, BORDER_SIZE)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.border = border

    -- Highlight (Blizzard style)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(136477) -- "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
    highlight:SetSize(HIGHLIGHT_SIZE, HIGHLIGHT_SIZE)
    highlight:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetHighlightTexture(highlight)

    -- Drag to move around minimap (angle-locked, no free movement)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local scale = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local mx, my = Minimap:GetCenter()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            MochaAlertsCharDB = MochaAlertsCharDB or {}
            MochaAlertsCharDB.minimapAngle = angle
            UpdateMinimapPos(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateMinimapPos(self)
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("MochaAlerts", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open settings.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Left-click to open config UI
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            if MA.ToggleConfig then
                MA:ToggleConfig()
            else
                print("MochaAlerts: Config UI not found.")
            end
        end
    end)

    MA.MinimapButton = button
    UpdateMinimapPos(button)
end

-- Create the minimap button after PLAYER_LOGIN
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    CreateMinimapButton()
end)

-- Cooldown frame tracking (combat-safe for CD-based spells like Disrupt)
MA.cdFrames = {}        -- [spellID] = Cooldown frame widget
MA.cdPending = {}       -- [spellID] = GetTime() when OnCooldownDone fired
MA.cdCastAt = {}        -- [spellID] = GetTime() when spell was cast (for post-cast bounce guard)
MA.gcdEndTime = 0       -- GetTime() when GCD last completed
MA.gcdFrame = nil       -- Cooldown frame for GCD

-- Lockout suppression: abilities like Roll/Chi Torpedo/Lighter Than Air briefly
-- make everything unusable during movement, causing mass false alerts when the
-- lockout ends. We detect this by checking UNIT_SPELLCAST_SUCCEEDED against a
-- dynamically-built set of lockout spell IDs (base + current overrides).
MA.lockoutUntil = 0     -- GetTime() until which usability alerts are suppressed
MA.lockoutSet = {}      -- [spellID] = duration (seconds) for all known lockout spells

-- Lockout spell IDs with their suppression durations.
-- Values are seconds to suppress alerts after the spell fires.
local LOCKOUT_BASE_SPELLS = {
    [109132] = 1.5,   -- Roll
    [115008] = 2.0,   -- Chi Torpedo (longer dash)
    [119381] = 1.5,   -- Leg Sweep
    [467455] = 5.5,   -- Lighter Than Air float (5s buff + buffer)
}

-- Lighter Than Air: buff that extends the lockout while active
local LTA_SPELL_IDS = { 449582, 467455 }  -- talent aura + float spell

-- Item tracking (trinkets & potions)
MA.itemUsableState = {}     -- [itemID] = true/false
MA.itemLastAlert = {}       -- [itemID] = GetTime()
MA.itemCdFrames = {}        -- [itemID] = Cooldown frame widget
MA.itemCdPending = {}       -- [itemID] = GetTime() when OnCooldownDone fired
MA.itemSpellMap = {}        -- [itemID] = spellID resolved from GetItemSpell
MA.itemSpellReverse = {}    -- [spellID] = itemID reverse lookup for cast detection

-------------------------------------------------------------------------------
-- Sound Library
-------------------------------------------------------------------------------
MA.SoundLib = {
    -- Warning & Alert Sounds
    { key = "RaidWarning",      name = "Raid Warning",         id = 8960  },
    { key = "BossEmote",        name = "Boss Emote",           id = 8457  },
    { key = "BossWhisper",      name = "Boss Whisper",         id = 8458  },
    { key = "ReadyCheck",       name = "Ready Check",          id = 8959  },
    { key = "PVPWarning",       name = "PVP Warning",          id = 8332  },
    { key = "PVPFlagTaken",     name = "PVP Flag Taken",       id = 8046  },
    { key = "AlarmClock",       name = "Alarm Clock",          id = 12889 },
    -- Completion Sounds
    { key = "LevelUp",          name = "Level Up",             id = 11466 },
    { key = "QuestComplete",    name = "Quest Complete",       id = 618   },
    { key = "ObjectiveComplete",name = "Objective Complete",   id = 43505 },
    -- Notification Sounds
    { key = "MapPing",          name = "Map Ping",             id = 6674  },
    { key = "FriendJoin",       name = "Friend Login",         id = 3332  },
    { key = "BNetToast",        name = "BNet Notification",    id = 23404 },
    { key = "GroupInvite",      name = "Group Invite",         id = 888   },
    { key = "InviteDeclined",   name = "Invite Declined",      id = 839   },
    { key = "PVPQueueReady",    name = "PVP Queue Ready",      id = 37881 },
    -- Interface Sounds
    { key = "AuctionOpen",      name = "Auction Open",         id = 5274  },
    { key = "AuctionClose",     name = "Auction Close",        id = 5275  },
    { key = "CharacterInfo",    name = "Character Sheet",      id = 12867 },
    { key = "LootCoin",         name = "Loot Coin",            id = 120   },
    { key = "SpellFizzle",      name = "Spell Fizzle",         id = 170   },
    -- WeakAuras Custom Sounds (file-based)
    { key = "WA_AcousticGuitar",    name = "WA: Acoustic Guitar",      file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\AcousticGuitar.ogg" },
    { key = "WA_Adds",              name = "WA: Adds",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Adds.ogg" },
    { key = "WA_AirHorn",           name = "WA: Air Horn",             file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\AirHorn.ogg" },
    { key = "WA_Applause",          name = "WA: Applause",             file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Applause.ogg" },
    { key = "WA_BananaPeelSlip",    name = "WA: Banana Peel Slip",     file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\BananaPeelSlip.ogg" },
    { key = "WA_BatmanPunch",       name = "WA: Batman Punch",         file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\BatmanPunch.ogg" },
    { key = "WA_BikeHorn",          name = "WA: Bike Horn",            file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\BikeHorn.ogg" },
    { key = "WA_Blast",             name = "WA: Blast",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Blast.ogg" },
    { key = "WA_Bleat",             name = "WA: Bleat",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Bleat.ogg" },
    { key = "WA_Boss",              name = "WA: Boss",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Boss.ogg" },
    { key = "WA_BoxingArena",       name = "WA: Boxing Arena",         file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\BoxingArenaSound.ogg" },
    { key = "WA_Brass",             name = "WA: Brass",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Brass.mp3" },
    { key = "WA_CartoonBaritone",   name = "WA: Cartoon Baritone",     file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\CartoonVoiceBaritone.ogg" },
    { key = "WA_CartoonWalking",    name = "WA: Cartoon Walking",      file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\CartoonWalking.ogg" },
    { key = "WA_CatMeow",           name = "WA: Cat Meow",             file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\CatMeow2.ogg" },
    { key = "WA_ChickenAlarm",      name = "WA: Chicken Alarm",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\ChickenAlarm.ogg" },
    { key = "WA_Circle",            name = "WA: Circle",               file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Circle.ogg" },
    { key = "WA_CowMooing",         name = "WA: Cow Mooing",           file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\CowMooing.ogg" },
    { key = "WA_Cross",             name = "WA: Cross",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Cross.ogg" },
    { key = "WA_Diamond",           name = "WA: Diamond",              file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Diamond.ogg" },
    { key = "WA_DontRelease",       name = "WA: Don't Release",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\DontRelease.ogg" },
    { key = "WA_DoubleWhoosh",      name = "WA: Double Whoosh",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\DoubleWhoosh.ogg" },
    { key = "WA_Drums",             name = "WA: Drums",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Drums.ogg" },
    { key = "WA_Empowered",         name = "WA: Empowered",            file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Empowered.ogg" },
    { key = "WA_ErrorBeep",         name = "WA: Error Beep",           file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\ErrorBeep.ogg" },
    { key = "WA_Focus",             name = "WA: Focus",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Focus.ogg" },
    { key = "WA_Glass",             name = "WA: Glass",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Glass.mp3" },
    { key = "WA_GoatBleating",      name = "WA: Goat Bleating",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\GoatBleating.ogg" },
    { key = "WA_Heartbeat",         name = "WA: Heartbeat",            file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\HeartbeatSingle.ogg" },
    { key = "WA_Idiot",             name = "WA: Idiot",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Idiot.ogg" },
    { key = "WA_KittenMeow",        name = "WA: Kitten Meow",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\KittenMeow.ogg" },
    { key = "WA_Left",              name = "WA: Left",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Left.ogg" },
    { key = "WA_Moon",              name = "WA: Moon",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Moon.ogg" },
    { key = "WA_Next",              name = "WA: Next",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Next.ogg" },
    { key = "WA_OhNo",              name = "WA: Oh No",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\OhNo.ogg" },
    { key = "WA_Portal",            name = "WA: Portal",               file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Portal.ogg" },
    { key = "WA_Protected",         name = "WA: Protected",            file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Protected.ogg" },
    { key = "WA_Release",           name = "WA: Release",              file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Release.ogg" },
    { key = "WA_Right",             name = "WA: Right",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Right.ogg" },
    { key = "WA_RingingPhone",      name = "WA: Ringing Phone",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\RingingPhone.ogg" },
    { key = "WA_RoaringLion",       name = "WA: Roaring Lion",         file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\RoaringLion.ogg" },
    { key = "WA_RobotBlip",         name = "WA: Robot Blip",           file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\RobotBlip.ogg" },
    { key = "WA_RoosterCalls",      name = "WA: Rooster Calls",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\RoosterChickenCalls.ogg" },
    { key = "WA_RunAway",           name = "WA: Run Away",             file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\RunAway.ogg" },
    { key = "WA_SharpPunch",        name = "WA: Sharp Punch",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\SharpPunch.ogg" },
    { key = "WA_SheepBleat",        name = "WA: Sheep Bleat",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\SheepBleat.ogg" },
    { key = "WA_Shotgun",           name = "WA: Shotgun",              file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Shotgun.ogg" },
    { key = "WA_Skull",             name = "WA: Skull",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Skull.ogg" },
    { key = "WA_Spread",            name = "WA: Spread",               file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Spread.ogg" },
    { key = "WA_Square",            name = "WA: Square",               file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Square.ogg" },
    { key = "WA_SqueakyToy",        name = "WA: Squeaky Toy",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\SqueakyToyShort.ogg" },
    { key = "WA_SquishFart",        name = "WA: Squish Fart",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\SquishFart.ogg" },
    { key = "WA_Stack",             name = "WA: Stack",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Stack.ogg" },
    { key = "WA_Star",              name = "WA: Star",                 file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Star.ogg" },
    { key = "WA_Switch",            name = "WA: Switch",               file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Switch.ogg" },
    { key = "WA_SynthChord",        name = "WA: Synth Chord",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\SynthChord.ogg" },
    { key = "WA_TadaFanfare",       name = "WA: Tada Fanfare",         file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\TadaFanfare.ogg" },
    { key = "WA_Taunt",             name = "WA: Taunt",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Taunt.ogg" },
    { key = "WA_TempleBell",        name = "WA: Temple Bell",          file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\TempleBellHuge.ogg" },
    { key = "WA_Torch",             name = "WA: Torch",                file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Torch.ogg" },
    { key = "WA_Triangle",          name = "WA: Triangle",             file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Triangle.ogg" },
    { key = "WA_WarningSiren",      name = "WA: Warning Siren",        file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\WarningSiren.ogg" },
    { key = "WA_WaterDrop",         name = "WA: Water Drop",           file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\WaterDrop.ogg" },
    { key = "WA_Xylophone",         name = "WA: Xylophone",            file = "Interface\\AddOns\\MochaAlerts\\Media\\Sounds\\Xylophone.ogg" },
}

MA.SoundByKey = {}
for _, entry in ipairs(MA.SoundLib) do
    if entry.file then
        MA.SoundByKey[entry.key] = { file = entry.file }
    else
        MA.SoundByKey[entry.key] = { id = entry.id }
    end
end

function MA:PlaySoundByKey(key)
    local info = self.SoundByKey[key or "RaidWarning"] or self.SoundByKey["RaidWarning"]
    local ok, willPlay
    if info.file then
        ok, willPlay = pcall(PlaySoundFile, info.file, "Master")
    else
        ok, willPlay = pcall(PlaySound, info.id, "Master")
    end
    if self.debugMode then
        local desc = info.file or tostring(info.id)
        print("|cff00ff00MochaAlerts DBG:|r PlaySound " .. tostring(key) .. " (" .. desc .. ") -> " .. tostring(ok and willPlay))
    end
end

function MA:GetSpellSound(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.sound then
        return data.sound
    end
    return "RaidWarning"
end

function MA:SetSpellSound(spellID, soundKey)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then
        data = { sound = soundKey, mode = "sound" }
    else
        data.sound = soundKey
        data.mode = "sound"
    end
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetSpellMode(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.mode then
        return data.mode
    end
    return "tts"
end

function MA:SetSpellMode(spellID, mode)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then
        data = { mode = mode, sound = "RaidWarning" }
    else
        data.mode = mode
    end
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetSpellTTSText(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.ttsText and data.ttsText ~= "" then
        return data.ttsText
    end
    return nil  -- nil means use default "SpellName ready"
end

function MA:SetSpellTTSText(spellID, text)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then
        data = { mode = "tts", sound = "RaidWarning" }
    end
    data.ttsText = (text and text ~= "") and text or nil
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetSpellDisplayText(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.displayText and data.displayText ~= "" then
        return data.displayText
    end
    return nil  -- nil means use the default "SpellName ready"
end

function MA:SetSpellDisplayText(spellID, text)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then
        data = { mode = "tts", sound = "RaidWarning" }
    end
    data.displayText = (text and text ~= "") and text or nil
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetSpellResourceMin(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.resourceMin then
        return data.resourceMin
    end
    return nil
end

-------------------------------------------------------------------------------
-- Item Helpers (trinkets & potions — mirrors spell helpers for trackedItems)
-------------------------------------------------------------------------------
function MA:GetItemMode(itemID)
    local data = self.charDb.trackedItems[itemID]
    return (type(data) == "table" and data.mode) or "tts"
end

function MA:SetItemMode(itemID, mode)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = mode, sound = "RaidWarning" } end
    data.mode = mode
    self.charDb.trackedItems[itemID] = data
end

function MA:GetItemSound(itemID)
    local data = self.charDb.trackedItems[itemID]
    return (type(data) == "table" and data.sound) or "RaidWarning"
end

function MA:SetItemSound(itemID, soundKey)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "sound", sound = soundKey } end
    data.sound = soundKey
    data.mode = "sound"
    self.charDb.trackedItems[itemID] = data
end

function MA:GetItemTTSText(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" or not data.ttsText or data.ttsText == "" then return nil end
    -- Ignore the old auto-set default for health pot groups so the editbox
    -- always shows the grey placeholder until the user types something.
    if data.isHealthPotGroup and data.ttsText == "Health Pot" then return nil end
    return data.ttsText
end

-- Centralised display name for tracked items.  Honours all group types.
function MA:GetItemDisplayName(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) == "table" then
        if data.isHealthPotGroup then return "Health Pot" end
        if data.isPotionGroup and data.displayName then return data.displayName end
    end
    return GetItemInfo(itemID) or "Item"
end

function MA:SetItemTTSText(itemID, text)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.ttsText = (text and text ~= "") and text or nil
    self.charDb.trackedItems[itemID] = data
end

function MA:GetItemDisplayText(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" or not data.displayText or data.displayText == "" then return nil end
    return data.displayText  -- nil means use the default "ItemName ready"
end

function MA:SetItemDisplayText(itemID, text)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.displayText = (text and text ~= "") and text or nil
    self.charDb.trackedItems[itemID] = data
end

function MA:GetSpellShowIcon(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.showIcon == false then return false end
    return true  -- default on
end

function MA:SetSpellShowIcon(spellID, val)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.showIcon = val and true or false
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetItemShowIcon(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) == "table" and data.showIcon == false then return false end
    return true  -- default on
end

function MA:SetItemShowIcon(itemID, val)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.showIcon = val and true or false
    self.charDb.trackedItems[itemID] = data
end

function MA:GetSpellShowText(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.showText == false then return false end
    return true  -- default on
end

function MA:SetSpellShowText(spellID, val)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.showText = val and true or false
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetItemShowText(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) == "table" and data.showText == false then return false end
    return true  -- default on
end

function MA:SetItemShowText(itemID, val)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.showText = val and true or false
    self.charDb.trackedItems[itemID] = data
end

function MA:GetSpellDoubleAlert(spellID)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) == "table" and data.doubleAlert == true then return true end
    return false  -- always default off
end

function MA:SetSpellDoubleAlert(spellID, val)
    local data = self.charDb.trackedSpells[spellID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.doubleAlert = val and true or false
    self.charDb.trackedSpells[spellID] = data
end

function MA:GetItemDoubleAlert(itemID)
    local data = self.charDb.trackedItems[itemID]
    if type(data) == "table" and data.doubleAlert == true then return true end
    return false  -- always default off
end

function MA:SetItemDoubleAlert(itemID, val)
    local data = self.charDb.trackedItems[itemID]
    if type(data) ~= "table" then data = { mode = "tts", sound = "RaidWarning" } end
    data.doubleAlert = val and true or false
    self.charDb.trackedItems[itemID] = data
end

-------------------------------------------------------------------------------
-- Visual Alert (safe custom frame — never touches protected UIErrorsFrame)
-------------------------------------------------------------------------------
-- Visual Alert -- stacking pool (up to 4 simultaneous alerts).
-- Slot 1 is the draggable anchor at the saved position.
-- Slots 2-4 stack upward above slot 1, each 10% smaller than the slot below it.
-------------------------------------------------------------------------------
local ALERT_POOL_SIZE  = 4
local ALERT_SCALE_STEP = 0.10   -- each higher slot is this much smaller

function MA:CreateAlertFrame()
    if self.alertPool[1] then return end

    local GROW_DUR    = 0.25
    local HOLD_DUR    = 1.5
    local FADE_DUR    = 0.8
    local START_SCALE = 0.5

    for i = 1, ALERT_POOL_SIZE do
        local f = CreateFrame("Frame", i == 1 and "MochaAlertsAlertFrame" or nil, UIParent)
        f:SetSize(500, 90)
        f:SetFrameStrata("HIGH")
        f:SetClampedToScreen(true)
        f:EnableMouse(false)

        local baseScale = (self.db and self.db.alertScale) or 1.0
        f.targetScale = baseScale * ((1 - ALERT_SCALE_STEP) ^ (i - 1))
        f:SetScale(f.targetScale)
        f.slotIndex = i

        if i == 1 then
            -- Slot 1: use saved position and allow dragging (unlocked via config)
            local pos = self.db and self.db.alertPos
            if pos then
                f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
            else
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local point, _, relPoint, x, y = self:GetPoint()
                MA.db.alertPos = { point, relPoint, x, y }
            end)
        else
            -- Slots 2-4: anchored above the slot below; follow slot 1 when it moves
            f:SetPoint("BOTTOM", self.alertPool[i - 1], "TOP", 0, 8)
        end

        local icon = f:CreateTexture(nil, "OVERLAY")
        icon:SetSize(40, 40)
        icon:SetPoint("BOTTOM", f, "CENTER", 0, 2)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()
        f.icon = icon

        local text = f:CreateFontString(nil, "OVERLAY")
        text:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
        text:SetPoint("TOP", f, "CENTER", 0, -2)
        f.text = text

        f.animPhase   = nil
        f.animElapsed = 0

        f:SetScript("OnUpdate", function(self, dt)
            if not self.animPhase then return end
            self.animElapsed = self.animElapsed + dt
            local tScale = self.targetScale or ((MA.db and MA.db.alertScale) or 1.0)

            if self.animPhase == "grow" then
                local t    = math.min(self.animElapsed / GROW_DUR, 1.0)
                local ease = 1 - (1 - t) * (1 - t)
                local s    = START_SCALE + (1 - START_SCALE) * ease
                self:SetScale(tScale * s)
                self:SetAlpha(0.3 + 0.7 * ease)
                if t >= 1.0 then
                    self.animPhase   = "hold"
                    self.animElapsed = 0
                    self:SetScale(tScale)
                    self:SetAlpha(1)
                end
            elseif self.animPhase == "hold" then
                if self.animElapsed >= HOLD_DUR then
                    self.animPhase   = "fade"
                    self.animElapsed = 0
                end
            elseif self.animPhase == "fade" then
                local t    = math.min(self.animElapsed / FADE_DUR, 1.0)
                local ease = t * t
                self:SetAlpha(1 - ease)
                self:SetScale(tScale)
                if t >= 1.0 then
                    self.animPhase = nil
                    self:Hide()
                    self:SetScale(tScale)
                end
            end
        end)

        f:Hide()
        self.alertPool[i] = f
    end

    self.alertFrame = self.alertPool[1]  -- backward-compat for unlock/scale/reset
end

function MA:ShowAlertText(msg, spellID, itemID)
    self:CreateAlertFrame()

    -- Pick the lowest-indexed free slot so stacking is as low as possible
    local f, slotIdx
    for i = 1, ALERT_POOL_SIZE do
        if not self.alertPool[i].animPhase then
            f, slotIdx = self.alertPool[i], i
            break
        end
    end
    if not f then
        -- All slots busy: steal the one furthest along its animation
        slotIdx = 1; f = self.alertPool[1]
        local bestScore = -math.huge
        for i = 1, ALERT_POOL_SIZE do
            local p = self.alertPool[i]
            local score = (p.animPhase == "fade" and 100 or p.animPhase == "hold" and 50 or 0) + (p.animElapsed or 0)
            if score > bestScore then bestScore = score; f = p; slotIdx = i end
        end
    end

    -- Scale: slot 1 = full base scale; each slot above is 10% smaller
    local baseScale = (self.db and self.db.alertScale) or 1.0
    f.targetScale = baseScale * ((1 - ALERT_SCALE_STEP) ^ (slotIdx - 1))

    -- Check per-spell/item text visibility
    local showText = true
    if spellID then
        showText = self:GetSpellShowText(spellID)
    elseif itemID then
        showText = self:GetItemShowText(itemID)
    end
    if showText then
        f.text:SetText(msg)
        f.text:Show()
    else
        f.text:SetText("")
        f.text:Hide()
    end

    -- Show spell/item icon if enabled per-spell/item
    local showIcon = false
    if spellID then
        showIcon = self:GetSpellShowIcon(spellID)
    elseif itemID then
        showIcon = self:GetItemShowIcon(itemID)
    end
    local iconTexture = nil
    if showIcon and spellID then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            iconTexture = info.iconID
        end
    end
    if showIcon and itemID and not iconTexture then
        iconTexture = C_Item.GetItemIconByID(itemID)
    end

    if showIcon and iconTexture then
        f.icon:SetTexture(iconTexture)
        f.icon:Show()
        f.icon:ClearAllPoints()
        if showText then
            f.icon:SetPoint("BOTTOM", f, "CENTER", 0, 2)
            f.text:ClearAllPoints()
            f.text:SetPoint("TOP", f, "CENTER", 0, -2)
        else
            f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
        end
    else
        f.icon:Hide()
        if showText then
            f.text:ClearAllPoints()
            f.text:SetPoint("TOP", f, "CENTER", 0, 12)
        end
    end

    -- Don't show frame if both text and icon are hidden
    if not showText and not (showIcon and iconTexture) then return end

    -- Start grow animation
    f:SetScale(f.targetScale * 0.5)
    f:SetAlpha(0.3)
    f.animPhase   = "grow"
    f.animElapsed = 0
    f:Show()
end

-- Toggle alert frame dragging (unlock/lock)
function MA:SetAlertUnlocked(unlocked)
    self:CreateAlertFrame()
    local f = self.alertFrame
    if unlocked then
        f:EnableMouse(true)
        f.text:SetText("|cffff9900Drag to move|r")
        f.text:Show()
        f.icon:SetTexture(134400)
        f.icon:Show()
        f.animPhase = nil
        f:SetAlpha(0.8)
        f:Show()
    else
        f:EnableMouse(false)
        f.animPhase = nil
        f:Hide()
    end
end

function MA:UpdateAlertScale(scale)
    self.db.alertScale = scale
    for i, f in ipairs(self.alertPool) do
        local ts = scale * ((1 - ALERT_SCALE_STEP) ^ (i - 1))
        f.targetScale = ts
        if not f.animPhase then
            f:SetScale(ts)
        end
    end
end

function MA:ResetAlertPosition()
    self.db.alertPos = nil
    if self.alertFrame then
        self.alertFrame:ClearAllPoints()
        self.alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

-------------------------------------------------------------------------------
-- TTS (Text-to-Speech)
-------------------------------------------------------------------------------
function MA:GetTTSVoices()
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and voices and #voices > 0 then return voices end
    end
    return nil
end

function MA:GetSelectedVoice()
    local voices = self:GetTTSVoices()
    if not voices then return nil end
    local idx = (self.db.ttsVoice or 0) + 1  -- saved as 0-based, Lua tables are 1-based
    return voices[idx] or voices[1]
end

function MA:TryTTS(text)
    -- Method 1: TextToSpeech_Speak with the actual voice OBJECT (not ID)
    if TextToSpeech_Speak then
        local voice = self:GetSelectedVoice()
        if voice then
            local ok, err = pcall(TextToSpeech_Speak, text, voice)
            if self.debugMode then
                print("|cff00ff00MochaAlerts DBG:|r TTS Method1 (TextToSpeech_Speak + voiceObj): ok=" .. tostring(ok) .. " err=" .. tostring(err))
            end
            if ok then return true end
        end
    end

    -- Method 2: Direct C_VoiceChat.SpeakText with voice object's voiceID
    if C_VoiceChat and C_VoiceChat.SpeakText then
        local voice = self:GetSelectedVoice()
        local vid = voice and voice.voiceID or 0
        -- Enum.VoiceTtsDestination: LocalPlayback=0, QueuedLocalPlayback=1, RemoteTransmission=2
        local ok, err = pcall(C_VoiceChat.SpeakText, vid, text, 0, 0, 100)
        if self.debugMode then
            print("|cff00ff00MochaAlerts DBG:|r TTS Method2 (SpeakText vid=" .. vid .. "): ok=" .. tostring(ok) .. " err=" .. tostring(err))
        end
        if ok then return true end
    end

    return false
end

function MA:DiagnoseTTS()
    print("|cff00ff00MochaAlerts TTS Diagnostic (v2):|r")

    -- Voice objects from GetTtsVoices
    local voices = self:GetTTSVoices()
    if voices then
        print("  Voices (" .. #voices .. "):")
        for i, v in ipairs(voices) do
            print("    [" .. i .. "] type=" .. type(v))
            if type(v) == "table" then
                for k, val in pairs(v) do
                    print("      ." .. tostring(k) .. " = " .. tostring(val) .. " (" .. type(val) .. ")")
                end
            end
        end
    else
        print("  Voices: NONE")
    end

    -- VoiceTtsDestination enum
    if Enum and Enum.VoiceTtsDestination then
        print("  VoiceTtsDestination enum:")
        for k, v in pairs(Enum.VoiceTtsDestination) do
            print("    " .. tostring(k) .. " = " .. tostring(v))
        end
    end

    -- TTS Settings state
    if C_TTSSettings then
        print("  C_TTSSettings:")
        for _, fn in ipairs({"GetSpeechRate", "GetSpeechVolume"}) do
            if C_TTSSettings[fn] then
                local ok, val = pcall(C_TTSSettings[fn])
                print("    ." .. fn .. "() = " .. tostring(val) .. " (ok=" .. tostring(ok) .. ")")
            end
        end
        -- Check if playback settings are configured
        if C_TTSSettings.GetSetting then
            print("    Settings dump:")
            for _, key in ipairs({"ttsPlaybackRate", "ttsPlaybackVolume", "playbackEnabled", "ttsEnabled", "speechRate", "speechVolume"}) do
                local ok, val = pcall(C_TTSSettings.GetSetting, key)
                if ok and val ~= nil then
                    print("      '" .. key .. "' = " .. tostring(val))
                end
            end
        end
        -- GetVoiceOptionID with proper voiceType
        if C_TTSSettings.GetVoiceOptionID then
            for vt = 0, 1 do
                local ok, val = pcall(C_TTSSettings.GetVoiceOptionID, vt)
                print("    GetVoiceOptionID(" .. vt .. ") ok=" .. tostring(ok) .. " val=" .. tostring(val))
            end
        end
    end

    -- Method 1: TextToSpeech_Speak with voice OBJECT
    print("  --- Method 1: TextToSpeech_Speak(text, voiceObject) ---")
    if TextToSpeech_Speak and voices then
        for i, voice in ipairs(voices) do
            C_Timer.After(1.5 * (i - 1), function()
                local msg = "Testing voice " .. i
                local ok, err = pcall(TextToSpeech_Speak, msg, voice)
                print("    voice[" .. i .. "] ok=" .. tostring(ok) .. " err=" .. tostring(err))
                print("    >>> Did you hear: '" .. msg .. "'?")
            end)
        end
    else
        print("    TextToSpeech_Speak or voices not available")
    end

    -- Method 2: C_VoiceChat.SpeakText with each destination (delayed to not overlap)
    local offset = voices and (#voices * 1.5) or 0
    if C_VoiceChat and C_VoiceChat.SpeakText and voices then
        print("  --- Method 2: C_VoiceChat.SpeakText (delayed " .. offset .. "s) ---")
        local destNames = {}
        if Enum and Enum.VoiceTtsDestination then
            for k, v in pairs(Enum.VoiceTtsDestination) do
                destNames[v] = k
            end
        end
        local attempt = 0
        for i, voice in ipairs(voices) do
            for dest = 0, 3 do
                attempt = attempt + 1
                C_Timer.After(offset + 1.5 * attempt, function()
                    local msg = "Voice " .. (voice.voiceID or i) .. " destination " .. dest
                    local ok, err = pcall(C_VoiceChat.SpeakText, voice.voiceID or (i - 1), msg, dest, 0, 100)
                    print("    vid=" .. tostring(voice.voiceID) .. " dest=" .. dest .. " (" .. (destNames[dest] or "?") .. ") ok=" .. tostring(ok) .. " err=" .. tostring(err))
                end)
            end
        end
    end

    -- Method 3: TextToSpeechFrame methods
    print("  --- Method 3: TextToSpeechFrame methods ---")
    if TextToSpeechFrame then
        print("    TextToSpeechFrame exists. Methods:")
        for k, v in pairs(TextToSpeechFrame) do
            if type(v) == "function" then
                print("      :" .. tostring(k) .. "()")
            end
        end
        -- Try AddMessage with a voice object
        if voices and voices[1] then
            if TextToSpeechFrame.AddMessage then
                local ok, err = pcall(TextToSpeechFrame.AddMessage, TextToSpeechFrame, "Test from AddMessage", voices[1])
                print("    AddMessage(text, voiceObj): ok=" .. tostring(ok) .. " err=" .. tostring(err))
            end
            if TextToSpeechFrame.Speak then
                local ok, err = pcall(TextToSpeechFrame.Speak, TextToSpeechFrame, "Test from Frame Speak", voices[1])
                print("    Frame:Speak(text, voiceObj): ok=" .. tostring(ok) .. " err=" .. tostring(err))
            end
        end
    else
        print("    TextToSpeechFrame: NOT found")
    end

    print("  Diagnostic complete. Listen for spoken text over the next ~" .. math.ceil(offset + 20) .. " seconds.")
end

-------------------------------------------------------------------------------
-- TTS Coalescing Queue
-- Collecting all simultaneous TTS requests into one speech act avoids the
-- engine queuing them sequentially, which causes the second spell name to be
-- delayed until the first finishes speaking.
-------------------------------------------------------------------------------
function MA:_QueueTTS(text)
    tinsert(self.ttsQueue, text)
    if not self.ttsFlushPending then
        self.ttsFlushPending = true
        C_Timer.After(TTS_COALESCE_WINDOW, function()
            MA:_FlushTTSQueue()
        end)
    end
end

function MA:_FlushTTSQueue()
    self.ttsFlushPending = false
    if #self.ttsQueue == 0 then return end
    local combined = table.concat(self.ttsQueue, ", ")
    wipe(self.ttsQueue)
    if self.debugMode then
        print("|cff00ff00MochaAlerts DBG:|r TTS flush: '" .. combined .. "'")
    end
    if not self:TryTTS(combined) then
        self:PlaySoundByKey("RaidWarning")
    end
end

-------------------------------------------------------------------------------
-- Alert Dispatch
-------------------------------------------------------------------------------
function MA:Speak(text, spellID)
    if not self.db or not self.db.enabled then
        if self.debugMode then print("|cffff0000MochaAlerts DBG:|r Blocked - disabled") end
        return
    end
    if not self.db.alertInCombat and InCombatLockdown() then
        if self.debugMode then print("|cffff0000MochaAlerts DBG:|r Blocked - combat setting off") end
        return
    end

    local now = GetTime()
    -- Unified throttle for all alerts
    if self.lastAlertTime[text] and (now - self.lastAlertTime[text]) < ALERT_THROTTLE then
        if self.debugMode then print("|cffff8800MochaAlerts DBG:|r Throttled alert for '" .. text .. "'") end
        return
    end
    self.lastAlertTime[text] = now

    if self.debugMode then
        print("|cff00ff00MochaAlerts DBG:|r >>> " .. text)
    end

    -- Per-spell mode: TTS, sound, or none
    local mode = spellID and self:GetSpellMode(spellID) or "tts"
    if mode == "tts" then
        -- Queue for coalescing: if another spell ready in the same burst,
        -- they'll be combined into one TTS call ("Void Ray, Darkness")
        local ttsText = spellID and self:GetSpellTTSText(spellID) or nil
        self:_QueueTTS(ttsText or text)
    elseif mode ~= "none" then
        local soundKey = spellID and self:GetSpellSound(spellID) or "RaidWarning"
        self:PlaySoundByKey(soundKey)
    end

    -- Visual feedback (custom frame is safe during combat)
    if self.db.showVisual then
        local visText = (spellID and self:GetSpellDisplayText(spellID)) or text
        self:ShowAlertText("|cff00ff00" .. visText .. "|r", spellID, nil)
    end

    -- Double-alert: schedule a second fire after 1.5s when x2 is enabled
    if spellID and self:GetSpellDoubleAlert(spellID) then
        C_Timer.After(1.5, function() MA:_SpeakRaw(text, spellID) end)
    end
end

-- Raw spell alert -- bypasses throttle, used only for x2 repeat
function MA:_SpeakRaw(text, spellID)
    if not self.db or not self.db.enabled then return end
    if not self.db.alertInCombat and InCombatLockdown() then return end
    self.lastAlertTime[text] = GetTime()
    local mode = spellID and self:GetSpellMode(spellID) or "tts"
    if mode == "tts" then
        local ttsText = spellID and self:GetSpellTTSText(spellID) or nil
        self:_QueueTTS(ttsText or text)
    elseif mode ~= "none" then
        self:PlaySoundByKey(spellID and self:GetSpellSound(spellID) or "RaidWarning")
    end
    if self.db.showVisual then
        local visText = (spellID and self:GetSpellDisplayText(spellID)) or text
        self:ShowAlertText("|cff00ff00" .. visText .. "|r", spellID, nil)
    end
end

-------------------------------------------------------------------------------
-- Alert Dispatch for Items
-------------------------------------------------------------------------------
function MA:SpeakItem(text, itemID)
    if not self.db or not self.db.enabled then return end
    if not self.db.alertInCombat and InCombatLockdown() then return end

    local now = GetTime()
    if self.lastAlertTime[text] and (now - self.lastAlertTime[text]) < ALERT_THROTTLE then
        if self.debugMode then print("|cffff8800MochaAlerts DBG:|r Throttled item alert for '" .. text .. "'") end
        return
    end
    self.lastAlertTime[text] = now

    if self.debugMode then print("|cff00ff00MochaAlerts DBG:|r >>> " .. text) end

    local mode = self:GetItemMode(itemID)
    if mode == "tts" then
        local ttsText = self:GetItemTTSText(itemID)
        self:_QueueTTS(ttsText or text)
    elseif mode ~= "none" then
        self:PlaySoundByKey(self:GetItemSound(itemID))
    end

    if self.db.showVisual then
        local visText = (itemID and self:GetItemDisplayText(itemID)) or text
        self:ShowAlertText("|cff00ff00" .. visText .. "|r", nil, itemID)
    end

    -- Double-alert: schedule a second fire after 1.5s when x2 is enabled
    if itemID and self:GetItemDoubleAlert(itemID) then
        C_Timer.After(1.5, function() MA:_SpeakItemRaw(text, itemID) end)
    end
end

-- Raw item alert — bypasses throttle, used only for x2 repeat
function MA:_SpeakItemRaw(text, itemID)
    if not self.db or not self.db.enabled then return end
    if not self.db.alertInCombat and InCombatLockdown() then return end
    self.lastAlertTime[text] = GetTime()
    local mode = self:GetItemMode(itemID)
    if mode == "tts" then
        self:_QueueTTS(self:GetItemTTSText(itemID) or text)
    elseif mode ~= "none" then
        self:PlaySoundByKey(self:GetItemSound(itemID))
    end
    if self.db.showVisual then
        local visText = (itemID and self:GetItemDisplayText(itemID)) or text
        self:ShowAlertText("|cff00ff00" .. visText .. "|r", nil, itemID)
    end
end

-------------------------------------------------------------------------------
-- Spell Override Mapping
-- During Meta, spells get new IDs (e.g., Chaos Strike -> Annihilation).
-- We track base IDs but query/detect using the current override.
-------------------------------------------------------------------------------
function MA:GetActiveSpellID(baseSpellID)
    -- C_Spell.GetOverrideSpell returns the current active version
    if C_Spell.GetOverrideSpell then
        local override = C_Spell.GetOverrideSpell(baseSpellID)
        if override and override ~= baseSpellID then
            return override
        end
    end
    -- Fallback: FindSpellOverrideByID (older API, may still exist)
    if FindSpellOverrideByID then
        local override = FindSpellOverrideByID(baseSpellID)
        if override and override ~= baseSpellID then
            return override
        end
    end
    return baseSpellID
end

-- Build reverse map: overrideID -> baseSpellID for incoming cast events
-- Also detects override changes (e.g., Void Meta) and re-snapshots usability
-- so the mode change doesn't trigger a false "ready" alert.
function MA:BuildOverrideMap()
    self._overrideToBase = {}
    self._lastActiveID = self._lastActiveID or {}
    wipe(self._activeSpellCache)
    local anyOverrideChanged = false
    for baseID in pairs(self.charDb.trackedSpells) do
        local activeID = self:GetActiveSpellID(baseID)
        self._overrideToBase[activeID] = baseID
        self._overrideToBase[baseID] = baseID

        -- If the active spell ID changed (override gained/lost), re-snapshot
        -- usability and cancel the stale CD frame to prevent double alerts.
        local prevActiveID = self._lastActiveID[baseID]
        if prevActiveID and prevActiveID ~= activeID and self.usableState[baseID] ~= nil then
            anyOverrideChanged = true
            -- Cancel the old CD frame so it doesn't fire OnCooldownDone for
            -- a cooldown that was reset by the form entry (Void Meta, etc.).
            local f = self.cdFrames[baseID]
            if f then f:SetCooldown(0, 0) end
            self.cdPending[baseID] = nil
            self.cdCastAt[baseID] = nil
            local rawUsable = C_Spell.IsSpellUsable(activeID)
            local newUsable = (rawUsable == true) and true or false
            if not newUsable then
                -- New override is NOT ready: stamp false so CheckUsability can
                -- detect the eventual false->true when it comes off CD.
                self.usableState[baseID] = false
                self.usableFalseAt[baseID] = GetTime()
            else
                -- New override is IMMEDIATELY ready (e.g. Void Ray on Void Meta entry).
                -- The old spell's CD context is gone, so clear the two guards that
                -- would otherwise delay or suppress the alert:
                --   usableFalseAt: was stamped when the OLD spell was cast; clearing it
                --     bypasses the instant-flip guard (now - falseAt < 1.5s).
                --   spellCastSeen: may have been consumed when the old spell last alerted;
                --     re-arming it lets CheckUsability past the no-cast-seen gate.
                self.usableFalseAt[baseID] = nil
                self.spellCastSeen[baseID] = true
            end
            if self.debugMode then
                local name = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseID) or tostring(baseID)
                print("|cffff8800MochaAlerts DBG:|r Override changed for " .. name .. " [" .. baseID .. "]: " .. tostring(prevActiveID) .. " -> " .. tostring(activeID) .. ", newUsable=" .. tostring(newUsable) .. " (usableState left=" .. tostring(self.usableState[baseID]) .. ")")
            end
        end
        self._lastActiveID[baseID] = activeID
        -- Cache for CheckCooldowns: avoids GetActiveSpellID + IsPlayerSpell*2 per check.
        if IsPlayerSpell(baseID) or IsPlayerSpell(activeID) then
            self._activeSpellCache[baseID] = activeID
        end
    end
    -- If any override changed (form entry/exit), re-snapshot ALL tracked spells.
    -- This prevents adjacent cooldown resets (e.g. Darkness) from firing false
    -- alerts when Void Meta resets multiple spells simultaneously.
    -- Only stamp false; spells that are now ready keep their existing false state
    -- so CheckCooldowns can detect the false->true transition and alert.
    if anyOverrideChanged then
        for baseID in pairs(self.charDb.trackedSpells) do
            if self.usableState[baseID] ~= nil then
                local activeID = self:GetActiveSpellID(baseID)
                local rawUsable = C_Spell.IsSpellUsable(activeID)
                if not ((rawUsable == true) and true or false) then
                    self.usableState[baseID] = false
                    self.usableFalseAt[baseID] = GetTime()
                end
                -- Spells that are now usable: leave usableState unchanged so
                -- CheckCooldowns sees the false->true and fires the alert.
            end
        end
    end
    return anyOverrideChanged
end

function MA:GetBaseSpellID(castSpellID)
    if self._overrideToBase and self._overrideToBase[castSpellID] then
        return self._overrideToBase[castSpellID]
    end
    -- Direct match
    if self.charDb.trackedSpells[castSpellID] then
        return castSpellID
    end
    return nil
end

-------------------------------------------------------------------------------
-- Lockout Set — dynamically built at login/talent change so talent overrides
-- (e.g., Lighter Than Air replacing Roll) are captured automatically.
-------------------------------------------------------------------------------
function MA:BuildLockoutSet()
    self.lockoutSet = {}
    for baseID, dur in pairs(LOCKOUT_BASE_SPELLS) do
        self.lockoutSet[baseID] = dur
        -- Add the current override (talent replacement) — use the LONGER duration
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, baseID)
        if ok and overrideID and overrideID ~= baseID then
            local existing = self.lockoutSet[overrideID] or 0
            if dur > existing then
                self.lockoutSet[overrideID] = dur
            end
        end
        if FindSpellOverrideByID then
            local ok2, overrideID2 = pcall(FindSpellOverrideByID, baseID)
            if ok2 and overrideID2 and overrideID2 ~= baseID then
                local existing = self.lockoutSet[overrideID2] or 0
                if dur > existing then
                    self.lockoutSet[overrideID2] = dur
                end
            end
        end
    end
    -- Ensure explicitly listed spells always use their own duration (not an override's)
    for baseID, dur in pairs(LOCKOUT_BASE_SPELLS) do
        self.lockoutSet[baseID] = dur
    end
    if self.debugMode then
        local parts = {}
        for id, dur in pairs(self.lockoutSet) do parts[#parts+1] = tostring(id) .. "(" .. dur .. "s)" end
        print("|cffff8800MochaAlerts DBG:|r Lockout set: " .. table.concat(parts, ", "))
    end
end

function MA:HasLTABuff()
    local ok, result = pcall(function()
        for _, auraID in ipairs(LTA_SPELL_IDS) do
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(auraID)
                if aura then return true end
            end
            local name = C_Spell.GetSpellName(auraID)
            if name then
                local aura = AuraUtil.FindAuraByName(name, "player", "HELPFUL")
                if aura then return true end
            end
        end
        return false
    end)
    if ok then return result end
    return false  -- assume no LTA if check fails in combat
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function MA:IsOnRealCooldown(spellID)
    local activeID = self:GetActiveSpellID(spellID)
    local cooldownInfo = C_Spell.GetSpellCooldown(activeID)
    if not cooldownInfo then return false end

    local ok, result = pcall(function()
        if cooldownInfo.duration == 0 then return false end
        -- Compare against the global cooldown (spell 61304)
        local gcdInfo = C_Spell.GetSpellCooldown(61304)
        if gcdInfo and gcdInfo.duration > 0
           and cooldownInfo.startTime == gcdInfo.startTime
           and cooldownInfo.duration == gcdInfo.duration then
            return false -- just the GCD, not a real cooldown
        end
        return true
    end)

    if ok then return result end
    return nil -- secret values in combat, can't determine
end

-------------------------------------------------------------------------------
-- Cooldown Frame Tracking (combat-safe)
-- SetCooldown() accepts secret values. OnCooldownDone fires when the C++ timer
-- completes. We defer alerts by one frame so we can compare against GCD.
-------------------------------------------------------------------------------
function MA:GetCDFrame(spellID)
    if self.cdFrames[spellID] then return self.cdFrames[spellID] end
    local f = CreateFrame("Cooldown", nil, UIParent)
    f:SetSize(1, 1)
    f:SetAlpha(0)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:Show()
    local sid = spellID
    f:SetScript("OnCooldownDone", function()
        local now = GetTime()
        MA.cdPending[sid] = now
        -- If spell was cast and this CD frame fired well after (>2s),
        -- this is a real CD end, not just a GCD. Force usableState to
        -- false so CheckUsability detects the false->true transition.
        -- Handles spells where IsSpellUsable stays true during real CD
        -- (e.g., Void Ray in Meta/Voidform).
        local castAt = MA.cdCastAt[sid]
        if castAt and (now - castAt) > 2.0 then
            MA.usableState[sid] = false
            MA.cdCastAt[sid] = nil
        end
        -- CD frame fired = real cooldown ended this session; mark as cast-seen
        -- so CheckUsability can alert even if zone wiped the original OnSpellCast.
        -- Only re-arm when usableState is still false; if CheckUsability already fired
        -- an alert and updated state to true, don't re-arm (prevents double-alert).
        if MA.usableState[sid] == false then
            MA.spellCastSeen[sid] = true
        end
        pcall(MA.CheckUsability, MA, sid)
        if MA.debugMode then
            local name = C_Spell.GetSpellName(sid) or tostring(sid)
            print("|cff88ffffMochaAlerts DBG:|r OnCooldownDone: " .. name .. " at " .. string.format("%.2f", GetTime()))
        end
    end)
    self.cdFrames[spellID] = f
    return f
end

function MA:EnsureGCDFrame()
    if self.gcdFrame then return end
    local f = CreateFrame("Cooldown", nil, UIParent)
    f:SetSize(1, 1)
    f:SetAlpha(0)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:Show()
    f:SetScript("OnCooldownDone", function()
        MA.gcdEndTime = GetTime()
        if MA.debugMode then
            print("|cff88ffffMochaAlerts DBG:|r GCD done at " .. string.format("%.2f", GetTime()))
        end
        -- Immediately process any spells whose real CD expired during this GCD
        -- so they alert the moment the GCD ends rather than waiting for the next poll.
        pcall(MA.ProcessPendingCDs, MA)
    end)
    self.gcdFrame = f
end

-- Called from OnUpdate to process deferred CD completions
function MA:ProcessPendingCDs()
    for spellID, doneTime in pairs(self.cdPending) do
        -- GCD filter: suppress only when the CD and GCD ended within ~100ms of each
        -- other, which means the CD was GCD-only (no real cooldown of its own).
        -- A real CD that expired DURING an active GCD has doneTime meaningfully
        -- earlier than gcdEndTime — allow it through so it alerts immediately
        -- once ProcessPendingCDs is called from EnsureGCDFrame's OnCooldownDone.
        if math.abs(doneTime - self.gcdEndTime) < 0.1 then
            -- Ended simultaneously with GCD — this was a GCD-only cooldown, skip
        else
            -- Real cooldown ended — fire alert (with per-spell throttle)
            local now = GetTime()
            local lastAlert = self.lastSpellAlert[spellID] or 0
            if (now - lastAlert) >= ALERT_THROTTLE then
                self.lastSpellAlert[spellID] = now
                local activeID = self._activeSpellCache[spellID] or self:GetActiveSpellID(spellID)
                local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(spellID)
                if spellName and self.charDb.trackedSpells[spellID] then
                    if self.debugMode then
                        print("|cff00ff00MochaAlerts DBG:|r CD done: " .. spellName .. " (doneAt=" .. string.format("%.2f", doneTime) .. " gcdAt=" .. string.format("%.2f", self.gcdEndTime) .. ")")
                    end
                    self:Speak(spellName .. " ready", spellID)
                end
            end
        end
        self.cdPending[spellID] = nil
    end
end

-- Called when UNIT_SPELLCAST_SUCCEEDED fires for a tracked spell
function MA:OnSpellCast(castSpellID)
    -- Map the cast spell ID back to the tracked base spell ID
    local baseID = self:GetBaseSpellID(castSpellID)
    if not baseID then return end

    if self.debugMode then
        local name = C_Spell.GetSpellName(castSpellID) or tostring(castSpellID)
        local baseName = C_Spell.GetSpellName(baseID) or tostring(baseID)
        print("|cff88ffffMochaAlerts DBG:|r CAST: " .. name .. " [" .. castSpellID .. "] (base: " .. baseName .. " [" .. baseID .. "])")
    end

    -- Force usableState to false on cast so any immediate bounce
    -- (IsSpellUsable returning true during real CD) doesn't bypass detection
    self.usableState[baseID] = false
    -- Mark that we observed a real cast this session so CheckUsability
    -- knows the upcoming false->true is a genuine CD expiry, not a
    -- zone-change / rez / form-reset that externally reset the cooldown.
    self.spellCastSeen[baseID] = true

    -- Record cast time for the post-cast bounce guard in CheckUsability
    -- (IsSpellUsable can momentarily return true before the CD is applied).
    self.cdCastAt[baseID] = GetTime()

    -- Set up spell CD frame using the CAST spell ID (SetCooldown accepts secret values)
    local info = C_Spell.GetSpellCooldown(castSpellID)
    if info then
        local f = self:GetCDFrame(baseID)
        f:SetCooldown(info.startTime, info.duration)
    end

    -- Set up GCD frame for comparison
    self:EnsureGCDFrame()
    local gcdInfo = C_Spell.GetSpellCooldown(61304)
    if gcdInfo then
        self.gcdFrame:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
    end
end

-- Re-sync CD frames for recently-cast spells only (cdCastAt set).
-- These are the frames that may have received secret values in OnSpellCast and
-- need the real duration once SPELL_UPDATE_COOLDOWN delivers it.
function MA:ReSyncCDFrames()
    for baseID in pairs(self.cdCastAt) do
        if self.charDb.trackedSpells[baseID] then
            local activeID = self._activeSpellCache[baseID] or self:GetActiveSpellID(baseID)
            local info = C_Spell.GetSpellCooldown(activeID)
            if info then
                local f = self.cdFrames[baseID]
                if f then f:SetCooldown(info.startTime, info.duration) end
            end
        end
    end
    -- Always re-sync the GCD frame (needed for ProcessPendingCDs GCD comparison).
    if self.gcdFrame then
        local gcdInfo = C_Spell.GetSpellCooldown(61304)
        if gcdInfo then
            self.gcdFrame:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
        end
    end
end

-------------------------------------------------------------------------------
-- Cooldown Tracking
-------------------------------------------------------------------------------
function MA:CheckCooldowns()
    -- _activeSpellCache is built by BuildOverrideMap; avoids per-call API overhead.
    for baseSpellID, activeID in pairs(self._activeSpellCache) do
        self:CheckUsability(baseSpellID, activeID)
        pcall(self.CheckResource, self, baseSpellID)
    end
    self:ProcessPendingCDs()
end

-------------------------------------------------------------------------------
-- Usability Tracking (primary mechanism — works in AND out of combat)
-- C_Spell.IsSpellUsable returns false when: on cooldown, not enough resource,
-- not enough charges, missing proc, etc. Returns true when castable.
-- This is the ONLY combat-safe detection since it avoids secret number comparisons.
-------------------------------------------------------------------------------
function MA:CheckUsability(baseSpellID, activeID)
    activeID = activeID or self:GetActiveSpellID(baseSpellID)
    -- Query usability on the ACTIVE (possibly overridden) spell ID
    local rawUsable = C_Spell.IsSpellUsable(activeID)
    local isUsable = (rawUsable == true) and true or false

    local wasUsable = self.usableState[baseSpellID]

    if self.debugMode and wasUsable ~= isUsable then
        local name = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
        print("|cffaa88ffMochaAlerts DBG:|r [" .. baseSpellID .. "/" .. activeID .. "] " .. name .. " usable: " .. tostring(wasUsable) .. " -> " .. tostring(isUsable))
    end

    -- Alert on not-usable -> usable transition
    if isUsable and wasUsable == false then
        -- Primary gate: only alert if we observed a real cast (or CD frame
        -- expiry) this session.  Zone changes, rezes, and form-resets can all
        -- flip a spell from not-usable -> usable without any cast occurring;
        -- spellCastSeen is wiped by InitCooldownStates so those transitions
        -- are transparently suppressed regardless of how long they take.
        if not self.spellCastSeen[baseSpellID] then
            if self.debugMode then
                local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
                print("|cffff8800MochaAlerts DBG:|r Suppressed no-cast-seen alert for " .. name)
            end
            self.usableState[baseSpellID] = isUsable
            return
        end
        -- Consume the cast-seen flag; cleared here so a second external reset
        -- after a real cast doesn't sneak through.
        self.spellCastSeen[baseSpellID] = nil
        -- Secondary guard: instant flip (< 1.5s) catches Void Meta resetting a
        -- spell that was JUST cast (so spellCastSeen was set) within the same GCD.
        local now = GetTime()
        local falseAt = self.usableFalseAt[baseSpellID] or 0
        if (now - falseAt) < 1.5 then
            if self.debugMode then
                local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
                print("|cffff8800MochaAlerts DBG:|r Suppressed instant-flip alert for " .. name .. " (false for " .. string.format("%.2f", now - falseAt) .. "s)")
            end
            self.usableState[baseSpellID] = isUsable
            return
        end
        local castAt = self.cdCastAt[baseSpellID]
        if castAt and (now - castAt) < 2.0 then
            self.usableState[baseSpellID] = isUsable
            return
        end
        -- Skip if inside lockout suppression window (Roll, Chi Torpedo, etc.)
        -- Extend lockout if Lighter Than Air buff is still active
        local hasLTA = self:HasLTABuff()
        if now < self.lockoutUntil or hasLTA then
            if self.debugMode then
                print("|cffff8800MochaAlerts DBG:|r Suppressed alert (lockout=" .. string.format("%.1f", self.lockoutUntil - now) .. "s remaining, LTA=" .. tostring(hasLTA) .. ")")
            end
            if hasLTA then
                -- Extend lockout to cover full LTA float; never shorten
                local newUntil = now + 6.0
                if newUntil > self.lockoutUntil then
                    self.lockoutUntil = newUntil
                end
            end
            -- Don't alert, but DO update state so the transition is consumed
            self.usableState[baseSpellID] = isUsable
            return
        end
        local lastAlert = self.lastSpellAlert[baseSpellID] or 0
        if (now - lastAlert) >= ALERT_THROTTLE then
            self.lastSpellAlert[baseSpellID] = now
            self.cdPending[baseSpellID] = nil  -- prevent ProcessPendingCDs double-fire
            -- Use the active (override) spell name so transforms like Void Meta -> Collapsing Star
            -- alert with the spell name the player currently sees on their action bar.
            local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID)
            if spellName then
                self:Speak(spellName .. " ready", baseSpellID)
            end
        end
    end

    -- Record when this spell transitions to not-usable so the min-false-duration
    -- check above can filter form-reset flips.
    if not isUsable and wasUsable ~= false then
        self.usableFalseAt[baseSpellID] = GetTime()
    end
    self.usableState[baseSpellID] = isUsable
end

-------------------------------------------------------------------------------
-- Resource Check — custom threshold (e.g., alert at 100 Fury, not spell cost)
-- Only works out of combat; UnitPower comparisons fail with secret values.
-- In combat, CheckUsability alerts at the spell's actual resource cost instead.
-------------------------------------------------------------------------------
function MA:CheckResource(spellID)
    local resMin = self:GetSpellResourceMin(spellID)
    if not resMin then
        self.resourceReady[spellID] = nil
        return
    end

    -- Skip in combat — number comparisons throw secret value errors
    if InCombatLockdown() then return end

    local powerType = UnitPowerType("player")
    local power = UnitPower("player", powerType)
    local offCD = self:IsOnRealCooldown(spellID)
    if offCD == nil then offCD = false end
    local isReady = (not offCD) and (power >= resMin)
    local wasReady = self.resourceReady[spellID]

    -- Alert on false -> true transition (nil = init, skip)
    if isReady and wasReady == false then
        local now = GetTime()
        local lastAlert = self.lastSpellAlert[spellID] or 0
        if (now - lastAlert) >= ALERT_THROTTLE then
            self.lastSpellAlert[spellID] = now
            local activeID = self._activeSpellCache[spellID] or self:GetActiveSpellID(spellID)
            local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(spellID)
            if spellName then
                self:Speak(spellName .. " ready", spellID)
            end
        end
    end

    self.resourceReady[spellID] = isReady
end

-------------------------------------------------------------------------------
-- Item Cooldown Tracking (trinkets & potions)
-- Items have their OWN cooldown tracked via C_Container.GetItemCooldown /
-- GetItemCooldown, NOT via C_Spell.GetSpellCooldown on the associated spell.
-- C_Spell APIs return GCD figures, not the real item cooldown.
-------------------------------------------------------------------------------
function MA:ResolveItemSpells()
    wipe(self.itemSpellMap)
    wipe(self.itemSpellReverse)
    for itemID, data in pairs(self.charDb.trackedItems) do
        local spellName, spellID = GetItemSpell(itemID)
        if spellID then
            self.itemSpellMap[itemID] = spellID
            self.itemSpellReverse[spellID] = itemID
        end
        -- For group types, map all member spell IDs to the representative so
        -- OnItemCast fires regardless of which specific variant the player uses.
        if type(data) == "table" and data.members then
            for memberID in pairs(data.members) do
                local _, memberSpellID = GetItemSpell(memberID)
                if memberSpellID then
                    self.itemSpellReverse[memberSpellID] = itemID
                end
            end
        end
    end
end

-- Get the real item cooldown (startTime, duration) using the item API
function MA:GetRealItemCooldown(itemID)
    -- C_Container.GetItemCooldown (modern) or GetItemCooldown (legacy)
    local getCD = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    if not getCD then return nil, nil end
    local ok, startTime, duration, enable = pcall(getCD, itemID)
    if ok and startTime and duration then
        return startTime, duration
    end
    return nil, nil
end

function MA:IsItemOnRealCooldown(itemID)
    local startTime, duration = self:GetRealItemCooldown(itemID)
    if not startTime or not duration then
        -- No CD data: if the item isn't in bags it was consumed (e.g. Healthstone).
        -- Returning nil tells CheckItemUsability to skip the transition check so
        -- consuming an item doesn't immediately fire a "ready" alert.
        if GetItemCount(itemID) == 0 then return nil end
        return false
    end
    local ok, result = pcall(function()
        if duration == 0 then return false end
        -- Filter GCD (≤1.5s)
        if duration <= 1.5 then return false end
        return true
    end)
    if ok then return result end
    return nil  -- secret values in combat
end

function MA:GetItemCDFrame(itemID)
    if self.itemCdFrames[itemID] then return self.itemCdFrames[itemID] end
    local f = CreateFrame("Cooldown", nil, UIParent)
    f:SetSize(1, 1)
    f:SetAlpha(0)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:Show()
    local iid = itemID
    f:SetScript("OnCooldownDone", function()
        MA.itemCdPending[iid] = GetTime()
        -- Only re-arm itemCastSeen if CheckItemUsability hasn't already consumed
        -- it and fired an alert (i.e. item is still marked as on-CD).  If the
        -- usability path already ran, re-setting this would cause ProcessItemPendingCDs
        -- to fire a duplicate alert ~2 seconds later.
        if MA.itemUsableState[iid] == false then
            MA.itemCastSeen[iid] = true
        end
        if MA.debugMode then
            local name = GetItemInfo(iid) or tostring(iid)
            print("|cff88ffffMochaAlerts DBG:|r Item OnCooldownDone: " .. name)
        end
    end)
    self.itemCdFrames[itemID] = f
    return f
end

function MA:OnItemCast(castSpellID)
    local itemID = self.itemSpellReverse[castSpellID]
    if not itemID or not self.charDb.trackedItems[itemID] then return end

    if self.debugMode then
        local name = GetItemInfo(itemID) or tostring(itemID)
        print("|cff88ffffMochaAlerts DBG:|r ITEM CAST: " .. name .. " [" .. itemID .. "] via spell " .. castSpellID)
    end

    -- Use ITEM cooldown API, not spell cooldown
    local startTime, duration = self:GetRealItemCooldown(itemID)
    if startTime and duration then
        local f = self:GetItemCDFrame(itemID)
        f:SetCooldown(startTime, duration)
        if self.debugMode then
            print("|cff88ffffMochaAlerts DBG:|r Item CD set: start=" .. string.format("%.1f", startTime) .. " dur=" .. string.format("%.1f", duration))
        end
    end

    -- Mark as not-usable immediately so we don't alert until CD ends
    self.itemUsableState[itemID] = false
    -- Record that a real use was observed so CheckItemUsability knows the
    -- upcoming false->true is a genuine CD expiry, not a rez/zone reset.
    self.itemCastSeen[itemID] = true

    self:EnsureGCDFrame()
    local gcdInfo = C_Spell.GetSpellCooldown(61304)
    if gcdInfo then
        self.gcdFrame:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
    end
end

function MA:ProcessItemPendingCDs()
    for itemID, doneTime in pairs(self.itemCdPending) do
        -- Items use the same tight GCD filter as spells: only suppress when the
        -- CD and GCD ended within ~100ms of each other.
        if math.abs(doneTime - self.gcdEndTime) < 0.1 then
            -- GCD, skip
        else
            local now = GetTime()
            local lastAlert = self.itemLastAlert[itemID] or 0
            if (now - lastAlert) >= 2.0 then
                self.itemLastAlert[itemID] = now
                if self.charDb.trackedItems[itemID] then
                    -- Gate: only fire if a real use was seen (catches rez/zone
                    -- resets that bypass CheckItemUsability's gate via the CD frame).
                    if self.itemCastSeen[itemID] then
                        self.itemCastSeen[itemID] = nil
                        self:SpeakItem(self:GetItemDisplayName(itemID) .. " ready", itemID)
                    elseif self.debugMode then
                        local name = GetItemInfo(itemID) or tostring(itemID)
                        print("|cffff8800MochaAlerts DBG:|r Suppressed no-cast-seen pending CD for " .. name)
                    end
                end
            end
        end
        self.itemCdPending[itemID] = nil
    end
end

function MA:CheckItemUsability(itemID)
    -- Check actual item cooldown, not spell usability
    local onCD = self:IsItemOnRealCooldown(itemID)
    -- onCD: true = on cooldown, false = ready, nil = can't determine (secret)
    if onCD == nil then
        -- In combat with secret values, can't determine — skip transition check
        return
    end

    local isUsable = not onCD
    local wasUsable = self.itemUsableState[itemID]

    if self.debugMode and wasUsable ~= isUsable then
        local name = GetItemInfo(itemID) or tostring(itemID)
        local startTime, duration = self:GetRealItemCooldown(itemID)
        print("|cffaa88ffMochaAlerts DBG:|r Item [" .. itemID .. "] " .. name .. " usable: " .. tostring(wasUsable) .. " -> " .. tostring(isUsable) .. " (CD start=" .. tostring(startTime) .. " dur=" .. tostring(duration) .. ")")
    end

    if isUsable and wasUsable == false then
        -- Only alert if a real use was observed this session; rez/zone resets
        -- flip the state without any cast and must not trigger an alert.
        if not self.itemCastSeen[itemID] then
            if self.debugMode then
                local name = GetItemInfo(itemID) or tostring(itemID)
                print("|cffff8800MochaAlerts DBG:|r Suppressed no-cast-seen item alert for " .. name)
            end
            self.itemUsableState[itemID] = isUsable
            return
        end
        self.itemCastSeen[itemID] = nil  -- consume
        local now = GetTime()
        if now < self.lockoutUntil or self:HasLTABuff() then
            if self:HasLTABuff() then
                local newUntil = now + 6.0
                if newUntil > self.lockoutUntil then
                    self.lockoutUntil = newUntil
                end
            end
            self.itemUsableState[itemID] = isUsable
            return
        end
        local lastAlert = self.itemLastAlert[itemID] or 0
        if (now - lastAlert) >= ALERT_THROTTLE then
            self.itemLastAlert[itemID] = now
            self.itemCdPending[itemID] = nil  -- prevent ProcessItemPendingCDs double-fire
            self:SpeakItem(self:GetItemDisplayName(itemID) .. " ready", itemID)
        end
    end

    self.itemUsableState[itemID] = isUsable
end

function MA:CheckItemCooldowns()
    for itemID in pairs(self.charDb.trackedItems) do
        self:CheckItemUsability(itemID)
    end
    self:ProcessItemPendingCDs()
end

function MA:ReSyncItemCDFrames()
    for itemID, f in pairs(self.itemCdFrames) do
        if self.charDb.trackedItems[itemID] then
            local startTime, duration = self:GetRealItemCooldown(itemID)
            if startTime and duration then
                f:SetCooldown(startTime, duration)
            end
        end
    end
end

function MA:InitItemStates()
    wipe(self.itemUsableState)
    wipe(self.itemLastAlert)
    wipe(self.itemCastSeen)
    for itemID in pairs(self.charDb.trackedItems) do
        local onCD = self:IsItemOnRealCooldown(itemID)
        if onCD ~= nil then
            self.itemUsableState[itemID] = not onCD
        else
            self.itemUsableState[itemID] = true  -- assume ready at init
        end
    end
end

function MA:InitCooldownStates()
    wipe(self.usableState)
    wipe(self.usableFalseAt)
    wipe(self.spellCastSeen)
    wipe(self.cdCastAt)
    wipe(self.resourceReady)
    wipe(self.lastSpellAlert)

    for spellID in pairs(self.charDb.trackedSpells) do
        local activeID = self:GetActiveSpellID(spellID)
        if IsPlayerSpell(spellID) or IsPlayerSpell(activeID) then
            -- Normalize to real Lua boolean, query on active ID
            local rawUsable = C_Spell.IsSpellUsable(activeID)
            self.usableState[spellID] = (rawUsable == true) and true or false
            -- Stamp false-at so any immediate post-init transition (e.g. a port
            -- resetting a cooldown) is caught by the min-false-duration gate.
            if self.usableState[spellID] == false then
                self.usableFalseAt[spellID] = GetTime()
                -- Spell was on CD at init: pre-arm so its first expiry alerts.
                -- (spellCastSeen stays nil for spells that start true, which
                --  blocks false "ready" alerts caused by rez/port state resets.)
                self.spellCastSeen[spellID] = true
            end
            -- Init resource state: nil = unknown, first check won't alert
            local resMin = self:GetSpellResourceMin(spellID)
            if resMin then
                self.resourceReady[spellID] = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Spell Management
-------------------------------------------------------------------------------
function MA:AddSpell(input, silent)
    if not input or input == "" then return false end

    -- Parse spell links (shift-click from spellbook)
    local linkID = input:match("|Hspell:(%d+)")
    if linkID then
        input = tonumber(linkID)
    end

    -- Try via C_Spell.GetSpellInfo (accepts name or ID)
    local spellInfo = C_Spell.GetSpellInfo(input)
    if spellInfo and spellInfo.spellID then
        self.charDb.trackedSpells[spellInfo.spellID] = { mode = "tts", sound = "RaidWarning" }
        self.usableState[spellInfo.spellID] = nil
        print("|cff00ff00MochaAlerts:|r Added " .. spellInfo.name .. " (ID: " .. spellInfo.spellID .. ")")
        self:InitSingleSpell(spellInfo.spellID)
        if self.configFrame and self.configFrame:IsShown() then
            self:RefreshSpellList()
        end
        return true
    end

    -- Try as raw number
    local numID = tonumber(input)
    if numID then
        local name = C_Spell.GetSpellName(numID)
        if name then
            self.charDb.trackedSpells[numID] = { mode = "tts", sound = "RaidWarning" }
            self.usableState[numID] = nil
            print("|cff00ff00MochaAlerts:|r Added " .. name .. " (ID: " .. numID .. ")")
            self:InitSingleSpell(numID)
            if self.configFrame and self.configFrame:IsShown() then
                self:RefreshSpellList()
            end
            return true
        end
    end

    if not silent then
        print("|cffff0000MochaAlerts:|r Spell not found: " .. tostring(input))
    end
    return false
end

function MA:InitSingleSpell(spellID)
    if not IsPlayerSpell(spellID) then return end
    local activeID = self:GetActiveSpellID(spellID)
    self._activeSpellCache[spellID] = activeID
    local rawUsable = C_Spell.IsSpellUsable(activeID)
    self.usableState[spellID] = (rawUsable == true) and true or false
end

function MA:RemoveSpell(spellID)
    local spellName = C_Spell.GetSpellName(spellID) or tostring(spellID)
    self.charDb.trackedSpells[spellID] = nil
    self._activeSpellCache[spellID] = nil
    self.usableState[spellID] = nil
    self.usableFalseAt[spellID] = nil
    self.spellCastSeen[spellID] = nil
    self.resourceReady[spellID] = nil
    self.lastSpellAlert[spellID] = nil
    self.cdPending[spellID] = nil
    self.cdCastAt[spellID] = nil
    if self.cdFrames[spellID] then
        self.cdFrames[spellID]:SetCooldown(0, 0)
        self.cdFrames[spellID] = nil
    end
    print("|cff00ff00MochaAlerts:|r Removed " .. spellName)
    if self.configFrame and self.configFrame:IsShown() then
        self:RefreshSpellList()
    end
end

-------------------------------------------------------------------------------
-- Item Management (trinkets & potions)
-------------------------------------------------------------------------------

-- Detect health potions: Consumable (class 0) > Potion (subclass 1) whose
-- use-spell name contains "heal" (covers all English health pot variants).
function MA:IsHealthPotion(itemID)
    if type(itemID) ~= "number" then return false end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)
    if not classID or classID ~= 0 or subClassID ~= 1 then return false end
    local spellName = GetItemSpell(itemID)
    return spellName ~= nil and spellName:lower():find("heal") ~= nil
end

-- Non-health combat potion: class 0 / subclass 1, use-spell doesn't contain "heal".
function MA:IsPotion(itemID)
    if type(itemID) ~= "number" then return false end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)
    return classID == 0 and subClassID == 1 and not self:IsHealthPotion(itemID)
end

-- Find an existing isPotionGroup entry whose displayName matches the given name.
function MA:FindPotionGroupByDisplayName(name)
    for itemID, data in pairs(self.charDb.trackedItems) do
        if type(data) == "table" and data.isPotionGroup and data.displayName == name then
            return itemID
        end
    end
    return nil
end

-- Add a health potion to (or create) the shared Health Potion group.
-- All health pots map to one alert entry so the player is never spammed.
function MA:AddHealthPotGroup(numID, itemName, spellName, spellID, silent)
    -- If this itemID is already tracked as a standalone item, migrate it first.
    local existing = self.charDb.trackedItems[numID]
    if existing and not (type(existing) == "table" and existing.isHealthPotGroup) then
        self:RemoveItem(numID)
    end

    -- Find an existing health pot group representative.
    local repID = nil
    for id, data in pairs(self.charDb.trackedItems) do
        if type(data) == "table" and data.isHealthPotGroup then
            repID = id
            break
        end
    end

    if repID then
        -- Already have a group; add this potion as a member.
        local data = self.charDb.trackedItems[repID]
        data.members = data.members or {}
        if data.members[numID] then
            if not silent then
                print("|cff00ff00MochaAlerts:|r Health potions already tracked as a group.")
            end
            return true
        end
        data.members[numID] = true
        -- Map this member's spell so OnItemCast attributes it to the group.
        if spellID then
            self.itemSpellReverse[spellID] = repID
        end
        if not silent then
            print("|cff00ff00MochaAlerts:|r Health Potion group: added " .. itemName .. ".")
        end
    else
        -- First health pot added; create the group using this itemID as rep.
        self.charDb.trackedItems[numID] = {
            mode             = "tts",
            sound            = "RaidWarning",
            ttsText          = "Health Pot",
            showIcon         = true,
            showText         = true,
            isHealthPotGroup = true,
            members          = { [numID] = true },
        }
        self.itemSpellMap[numID] = spellID
        self.itemSpellReverse[spellID] = numID
        local rawUsable = C_Spell.IsSpellUsable(spellID)
        self.itemUsableState[numID] = (rawUsable == true) and true or false
        if not silent then
            print("|cff00ff00MochaAlerts:|r Health Potion group created. TTS: \"Health Pot\" -- link any health potion to add it to this group.")
        end
    end
    if self.configFrame and self.configFrame:IsShown() then
        self:RefreshSpellList()
    end
    return true
end

-- Add a potion to a named group so a "Fleeting X" variant and its base "X"
-- share one alert entry.  displayName is the stripped base name.
function MA:AddPotionGroup(numID, itemName, displayName, spellName, spellID, silent)
    -- If already tracked as a standalone, drop it so it can join the group.
    local existing = self.charDb.trackedItems[numID]
    if existing and not (type(existing) == "table" and existing.isPotionGroup) then
        self:RemoveItem(numID)
    end

    -- Reject if already a member of any potion group.
    for id, data in pairs(self.charDb.trackedItems) do
        if type(data) == "table" and data.isPotionGroup and data.members and data.members[numID] then
            if not silent then
                print("|cff00ff00MochaAlerts:|r " .. itemName .. " is already in the " .. (data.displayName or "potion") .. " group.")
            end
            return true
        end
    end

    -- Find a group already keyed to this displayName.
    local repID = self:FindPotionGroupByDisplayName(displayName)
    if repID then
        -- Add as a new member of the existing group.
        local data = self.charDb.trackedItems[repID]
        data.members[numID] = true
        if spellID then self.itemSpellReverse[spellID] = repID end
        if not silent then
            print("|cff00ff00MochaAlerts:|r " .. displayName .. " group: added " .. itemName .. ".")
        end
    else
        -- No group yet.  Check if the base item is already tracked standalone
        -- and, if so, promote it to a group in-place, preserving its settings.
        local baseRepID = nil
        for id, d in pairs(self.charDb.trackedItems) do
            if not (type(d) == "table" and (d.isPotionGroup or d.isHealthPotGroup)) then
                if GetItemInfo(id) == displayName then
                    baseRepID = id
                    break
                end
            end
        end

        if baseRepID then
            local old = self.charDb.trackedItems[baseRepID]
            self.charDb.trackedItems[baseRepID] = {
                mode          = (type(old) == "table" and old.mode)  or "tts",
                sound         = (type(old) == "table" and old.sound) or "RaidWarning",
                ttsText       = type(old) == "table" and old.ttsText or nil,
                showIcon      = not (type(old) == "table" and old.showIcon == false),
                showText      = not (type(old) == "table" and old.showText == false),
                isPotionGroup = true,
                displayName   = displayName,
                members       = { [baseRepID] = true, [numID] = true },
            }
            -- itemSpellMap / itemUsableState for baseRepID already exist.
            if spellID then self.itemSpellReverse[spellID] = baseRepID end
            if not silent then
                print("|cff00ff00MochaAlerts:|r " .. displayName .. " group created -- merged " .. itemName .. " with existing entry.")
            end
        else
            -- Brand-new group; numID becomes the representative.
            self.charDb.trackedItems[numID] = {
                mode          = "tts",
                sound         = "RaidWarning",
                showIcon      = true,
                showText      = true,
                isPotionGroup = true,
                displayName   = displayName,
                members       = { [numID] = true },
            }
            self.itemSpellMap[numID] = spellID
            if spellID then self.itemSpellReverse[spellID] = numID end
            local rawUsable = C_Spell.IsSpellUsable(spellID)
            self.itemUsableState[numID] = (rawUsable == true) and true or false
            if not silent then
                print("|cff00ff00MochaAlerts:|r " .. displayName .. " group created from " .. itemName .. ". Link the base potion to merge it.")
            end
        end
    end

    if self.configFrame and self.configFrame:IsShown() then
        self:RefreshSpellList()
    end
    return true
end

function MA:AddItem(input, silent)
    if not input or input == "" then return false end

    -- Parse item links (shift-click from inventory)
    local linkID = input:match("|Hitem:(%d+)")
    if linkID then input = tonumber(linkID) end

    local numID = tonumber(input)
    if not numID then
        -- Try by name (only works for cached items in bags/equipped)
        local itemName, itemLink = GetItemInfo(input)
        if itemLink then
            numID = tonumber(itemLink:match("item:(%d+)"))
        end
    end

    if not numID then
        if not silent then print("|cffff0000MochaAlerts:|r Item not found: " .. tostring(input)) end
        return false
    end

    local itemName = GetItemInfo(numID)
    if not itemName then
        if not silent then print("|cffff0000MochaAlerts:|r Item not found (ID: " .. numID .. ")") end
        return false
    end

    local spellName, spellID = GetItemSpell(numID)
    if not spellID then
        if not silent then print("|cffff0000MochaAlerts:|r " .. itemName .. " has no use effect to track.") end
        return false
    end

    -- Health potions go into a shared group so the player gets one alert
    -- regardless of how many different health pot types they track.
    if self:IsHealthPotion(numID) then
        return self:AddHealthPotGroup(numID, itemName, spellName, spellID, silent)
    end

    -- Fleeting potions (cauldron variant) group with their base potion name.
    -- Base potions also merge into an existing fleeting group if one exists.
    if self:IsPotion(numID) then
        local baseName = itemName:match("^Fleeting (.+)$")
        if baseName then
            return self:AddPotionGroup(numID, itemName, baseName, spellName, spellID, silent)
        end
        local groupID = self:FindPotionGroupByDisplayName(itemName)
        if groupID then
            return self:AddPotionGroup(numID, itemName, itemName, spellName, spellID, silent)
        end
    end

    if self.charDb.trackedItems[numID] then
        if not silent then print("|cffff0000MochaAlerts:|r Already tracking: " .. itemName) end
        return false
    end

    self.charDb.trackedItems[numID] = { mode = "tts", sound = "RaidWarning" }
    self.itemSpellMap[numID] = spellID
    self.itemSpellReverse[spellID] = numID

    local rawUsable = C_Spell.IsSpellUsable(spellID)
    self.itemUsableState[numID] = (rawUsable == true) and true or false

    print("|cff00ff00MochaAlerts:|r Added item: " .. itemName .. " (ID: " .. numID .. ", Spell: " .. (spellName or "?") .. ")")
    if self.configFrame and self.configFrame:IsShown() then
        self:RefreshSpellList()
    end
    return true
end

function MA:RemoveItem(itemID)
    local data = self.charDb.trackedItems[itemID]
    -- Clear all member spell reverse-mappings for any group type.
    if type(data) == "table" and data.members then
        for memberID in pairs(data.members) do
            local _, memberSpellID = GetItemSpell(memberID)
            if memberSpellID then
                self.itemSpellReverse[memberSpellID] = nil
            end
        end
    end
    local itemName
    if type(data) == "table" and data.isHealthPotGroup then
        itemName = "Health Potion group"
    elseif type(data) == "table" and data.isPotionGroup and data.displayName then
        itemName = data.displayName .. " group"
    else
        itemName = GetItemInfo(itemID) or tostring(itemID)
    end
    local spellID = self.itemSpellMap[itemID]

    self.charDb.trackedItems[itemID] = nil
    self.itemUsableState[itemID] = nil
    self.itemLastAlert[itemID] = nil
    self.itemCdPending[itemID] = nil
    self.itemSpellMap[itemID] = nil
    if spellID then self.itemSpellReverse[spellID] = nil end
    if self.itemCdFrames[itemID] then
        self.itemCdFrames[itemID]:SetCooldown(0, 0)
        self.itemCdFrames[itemID] = nil
    end

    print("|cff00ff00MochaAlerts:|r Removed item: " .. itemName)
    if self.configFrame and self.configFrame:IsShown() then
        self:RefreshSpellList()
    end
end

function MA:ScanTrinkets()
    local added = 0
    for _, slot in ipairs({13, 14}) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local spellName, spellID = GetItemSpell(itemID)
            if spellID and not self.charDb.trackedItems[itemID] then
                if self:AddItem(tostring(itemID)) then
                    added = added + 1
                end
            end
        end
    end
    if added == 0 then
        print("|cff00ff00MochaAlerts:|r No new trinkets with use effects found.")
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
MA.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_USABLE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_POWER_FREQUENT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            MochaAlertsDB = MochaAlertsDB or {}
            MA.db = MochaAlertsDB
            for k, v in pairs(defaults) do
                if MA.db[k] == nil then
                    MA.db[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
            -- Remove any stale keys not in defaults (e.g. ttsVolume)
            MA.db.ttsVolume = nil
            -- Per-character DB
            MochaAlertsCharDB = MochaAlertsCharDB or {}
            MA.charDb = MochaAlertsCharDB
            for k, v in pairs(charDefaults) do
                if MA.charDb[k] == nil then
                    MA.charDb[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
            -- Migrate old formats (on charDb now)
            if MA.charDb.trackedSpells then
                for spellID, val in pairs(MA.charDb.trackedSpells) do
                    if val == true then
                        MA.charDb.trackedSpells[spellID] = { mode = "tts", sound = "RaidWarning" }
                    elseif type(val) == "table" and not val.mode then
                        val.mode = "tts"  -- existing spells default to TTS
                    end
                end
            end
            -- Migrate trackedSpells from account DB to per-character DB
            if MochaAlertsDB.trackedSpells and next(MochaAlertsDB.trackedSpells) then
                for spellID, data in pairs(MochaAlertsDB.trackedSpells) do
                    if not MA.charDb.trackedSpells[spellID] then
                        MA.charDb.trackedSpells[spellID] = data
                    end
                end
                MochaAlertsDB.trackedSpells = nil  -- remove from account DB
            end
            -- Migrate trackedItems from account DB to per-character DB
            if MA.db.trackedItems and next(MA.db.trackedItems) then
                for itemID, data in pairs(MA.db.trackedItems) do
                    if not MA.charDb.trackedItems[itemID] then
                        MA.charDb.trackedItems[itemID] = data
                    end
                end
                MA.db.trackedItems = nil  -- remove from account DB
            end
            -- Remove legacy auto-set ttsText from health pot groups so the
            -- editbox shows the grey placeholder instead of white "Health Pot".
            if MA.charDb.trackedItems then
                for _, data in pairs(MA.charDb.trackedItems) do
                    if type(data) == "table" and data.isHealthPotGroup
                        and data.ttsText == "Health Pot"
                    then
                        data.ttsText = nil
                    end
                end
            end
            frame:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_LOGIN" then
        MA:BuildOverrideMap()
        MA:BuildLockoutSet()
        MA:ResolveItemSpells()
        MA:InitCooldownStates()
        MA:InitItemStates()
        MA.initialized = true
        -- Periodic polling: safety net for transitions that events may miss.
        -- Throttle tables are shared with event handlers so polling only fires
        -- when events have been quiet (avoids redundant work in combat).
        frame:SetScript("OnUpdate", function(_, dt)
            MA.elapsed = MA.elapsed + dt
            if MA.elapsed >= POLL_INTERVAL then
                MA.elapsed = 0
                if MA.initialized and MA.db then
                    local now = GetTime()
                    if (now - MA.lastSpellCheckTime) >= POLL_INTERVAL then
                        MA.lastSpellCheckTime = now
                        pcall(MA.CheckCooldowns, MA)
                    end
                    if (now - MA.lastItemCheckTime) >= POLL_INTERVAL then
                        MA.lastItemCheckTime = now
                        pcall(MA.CheckItemCooldowns, MA)
                    end
                end
            end
        end)
        print("|cff00ff00MochaAlerts|r v1.0.0 loaded. Type |cff88bbff/malerts|r to configure.")

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        if MA.initialized and MA.db then
            -- Rebuild override map on usability changes so form-entry re-snapshots
            -- happen before CheckCooldowns compares states.
            if event == "SPELL_UPDATE_USABLE" then
                MA:BuildOverrideMap()
            end
            -- Re-sync CD frames for recently-cast spells (cheap -- only cdCastAt set).
            pcall(MA.ReSyncCDFrames, MA)
            -- Throttle the full spell check to avoid redundant loops on rapid events.
            local now = GetTime()
            if (now - MA.lastSpellCheckTime) >= 0.1 then
                MA.lastSpellCheckTime = now
                pcall(MA.CheckCooldowns, MA)
            end
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        if MA.initialized and MA.db then
            pcall(MA.ReSyncItemCDFrames, MA)
            local now = GetTime()
            if (now - MA.lastItemCheckTime) >= 0.1 then
                MA.lastItemCheckTime = now
                pcall(MA.CheckItemCooldowns, MA)
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local a1, a2, a3 = ...
        local unit = a1
        local spellID
        -- In Midnight retail: (unitTarget, castGUID, spellID)
        if type(a3) == "number" then
            spellID = a3
        elseif type(a2) == "number" then
            spellID = a2
        end
        if MA.debugMode then
            print("|cff88ffffMochaAlerts DBG:|r SPELLCAST_SUCCEEDED args: a1=" .. tostring(a1) .. " a2=" .. tostring(a2) .. " a3=" .. tostring(a3) .. " -> spellID=" .. tostring(spellID))
        end
        if unit == "player" and MA.initialized and MA.db and spellID then
            -- Check if this is a lockout spell (Roll, Chi Torpedo, Lighter Than Air, etc.)
            if MA.lockoutSet[spellID] then
                local duration = MA.lockoutSet[spellID]
                local newUntil = GetTime() + duration
                -- Only extend, never shorten (Chi Torpedo fires first, then LTA may extend)
                if newUntil > MA.lockoutUntil then
                    MA.lockoutUntil = newUntil
                end
                if MA.debugMode then
                    local name = C_Spell.GetSpellName(spellID) or tostring(spellID)
                    print("|cffff8800MochaAlerts DBG:|r Lockout triggered by " .. name .. " [" .. spellID .. "], suppressing for " .. duration .. "s")
                end
                -- Snapshot current states so transitions during lockout are consumed
                for baseSpellID in pairs(MA.charDb.trackedSpells) do
                    local activeID = MA:GetActiveSpellID(baseSpellID)
                    if IsPlayerSpell(baseSpellID) or IsPlayerSpell(activeID) then
                        local rawUsable = C_Spell.IsSpellUsable(activeID)
                        MA.usableState[baseSpellID] = (rawUsable == true) and true or false
                    end
                end
                for itemID in pairs(MA.charDb.trackedItems) do
                    local onCD = MA:IsItemOnRealCooldown(itemID)
                    if onCD ~= nil then
                        MA.itemUsableState[itemID] = not onCD
                    end
                end
            end
            MA:OnSpellCast(spellID)
            MA:OnItemCast(spellID)
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and MA.initialized and MA.db then
            local overrideChanged = MA:BuildOverrideMap()
            local now = GetTime()
            -- Always check immediately on an override change (e.g. Void Meta entry)
            -- so spells that just became ready don't wait for the throttle window.
            if overrideChanged or (now - MA.lastSpellCheckTime) >= 0.1 then
                MA.lastSpellCheckTime = now
                pcall(MA.CheckCooldowns, MA)
            end
        end

    elseif event == "UNIT_POWER_FREQUENT" then
        -- Only relevant out of combat: CheckResource already no-ops in combat.
        local unit = ...
        if unit == "player" and MA.initialized and MA.db and not InCombatLockdown() then
            pcall(MA.CheckCooldowns, MA)
        end


    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        if MA.initialized and MA.db then
            MA:BuildOverrideMap()
            MA:BuildLockoutSet()
            if not InCombatLockdown() then
                MA:ResolveItemSpells()
                MA:InitCooldownStates()
                MA:InitItemStates()
            end
        end

    -- Prevent alerts on zone changes: reset state but do not trigger alerts
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if MA.initialized and MA.db then
            MA:InitCooldownStates()
            MA:InitItemStates()
            -- Do NOT call CheckCooldowns/CheckItemCooldowns here (would trigger alerts)
            if MA.debugMode then
                print("|cff00ff00MochaAlerts DBG:|r State reset on zone change (", event, ")")
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- Slash Commands
-------------------------------------------------------------------------------
SLASH_MochaAlerts1 = "/MochaAlerts"
SLASH_MochaAlerts2 = "/malerts"

SlashCmdList["MochaAlerts"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    if not cmd then cmd = msg end
    cmd = strtrim(cmd):lower()

    if cmd == "add" and rest and strtrim(rest) ~= "" then
        local val = strtrim(rest)
        if val:match("|Hitem:") then
            MA:AddItem(val)
        elseif not MA:AddSpell(val, true) then
            MA:AddItem(val)
        end

    elseif (cmd == "remove" or cmd == "rm" or cmd == "del") and rest and strtrim(rest) ~= "" then
        rest = strtrim(rest)
        local id = tonumber(rest)
        if id then
            if MA.charDb.trackedItems[id] then
                MA:RemoveItem(id)
            else
                MA:RemoveSpell(id)
            end
        else
            -- Search spells by name
            for spellID in pairs(MA.charDb.trackedSpells) do
                local name = C_Spell.GetSpellName(spellID)
                if name and name:lower() == rest:lower() then
                    MA:RemoveSpell(spellID)
                    return
                end
            end
            -- Search items by name
            for itemID in pairs(MA.charDb.trackedItems) do
                local name = GetItemInfo(itemID)
                if name and name:lower() == rest:lower() then
                    MA:RemoveItem(itemID)
                    return
                end
            end
            print("|cffff0000MochaAlerts:|r Not tracking: " .. rest)
        end

    elseif cmd == "list" or cmd == "ls" then
        print("|cff00ff00MochaAlerts|r tracked spells:")
        local count = 0
        for spellID in pairs(MA.charDb.trackedSpells) do
            local name = C_Spell.GetSpellName(spellID) or "Unknown"
            local known = IsPlayerSpell(spellID)
            local tag = known
                and "|cff00ff00[Known]|r"
                or  "|cff888888[Not on this character]|r"
            local onCD = known and MA:IsOnRealCooldown(spellID)
            local cdTag = onCD and " |cffff8800[On CD]|r" or " |cff88ff88[Ready]|r"
            local usable = MA.usableState[spellID]
            print("  " .. name .. " (ID: " .. spellID .. ") " .. tag .. cdTag .. " usable=" .. tostring(usable))
            count = count + 1
        end
        for itemID in pairs(MA.charDb.trackedItems) do
            local name = GetItemInfo(itemID) or "Unknown Item"
            local spellID = MA.itemSpellMap[itemID]
            local usable = spellID and C_Spell.IsSpellUsable(spellID)
            local cdTag = usable and " |cff88ff88[Ready]|r" or " |cffff8800[On CD]|r"
            print("  |cff00ccff[Item]|r " .. name .. " (ID: " .. itemID .. ")" .. cdTag)
            count = count + 1
        end
        if count == 0 then
            print("  (none) — Use |cff88bbff/malerts add SpellName|r to start tracking.")
        end

    elseif cmd == "scanitems" or cmd == "scantrinkets" then
        MA:ScanTrinkets()

    elseif cmd == "toggle" then
        MA.db.enabled = not MA.db.enabled
        print("|cff00ff00MochaAlerts:|r " .. (MA.db.enabled and "Enabled" or "Disabled"))

    elseif cmd == "on" then
        MA.db.enabled = true
        print("|cff00ff00MochaAlerts:|r Enabled")

    elseif cmd == "off" then
        MA.db.enabled = false
        print("|cff00ff00MochaAlerts:|r Disabled")

    elseif cmd == "test" then
        if rest and strtrim(rest) ~= "" then
            local input = strtrim(rest)
            local testID = tonumber(input)
            if not testID then
                local info = C_Spell.GetSpellInfo(input)
                if info then testID = info.spellID end
            end
            if testID then
                local name = C_Spell.GetSpellName(testID) or "?"
                local known = IsPlayerSpell(testID)
                local onCD = MA:IsOnRealCooldown(testID)
                local usable = C_Spell.IsSpellUsable(testID)
                print("|cff00ff00MochaAlerts:|r Test " .. name .. " [" .. testID .. "]:")
                print("  known=" .. tostring(known) .. " onCD=" .. tostring(onCD) .. " usable=" .. tostring(usable))
                MA:Speak(name .. " ready", testID)
            else
                print("|cffff0000MochaAlerts:|r Spell not found: " .. input)
            end
        else
            MA:Speak("Spell ready")
        end
        print("|cff00ff00MochaAlerts:|r Test alert sent.")

    elseif cmd == "tts" then
        if MA.debugMode then
            MA:DiagnoseTTS()
        else
            print("|cffff8800MochaAlerts:|r TTS diagnostic only available in debug mode (/malerts debug)")
        end

    elseif cmd == "voice" then
        local voices = MA:GetTTSVoices()
        if not voices then
            print("|cffff0000MochaAlerts:|r No TTS voices available.")
            return
        end
        if rest and strtrim(rest) ~= "" then
            local idx = tonumber(strtrim(rest))
            if idx and idx >= 0 and idx < #voices then
                MA.db.ttsVoice = idx
                local v = voices[idx + 1]
                print("|cff00ff00MochaAlerts:|r TTS voice set to: " .. (v.name or tostring(idx)))
            else
                print("|cffff0000MochaAlerts:|r Invalid voice index. Use 0-" .. (#voices - 1))
            end
        else
            print("|cff00ff00MochaAlerts:|r TTS voices:")
            for i, v in ipairs(voices) do
                local marker = ((i - 1) == (MA.db.ttsVoice or 0)) and " |cff88ff88<< selected|r" or ""
                print("  [" .. (i - 1) .. "] " .. (v.name or "Voice " .. (i - 1)) .. marker)
            end
            print("  Use |cff88bbff/malerts voice 0|r to select a voice.")
        end

    elseif cmd == "power" then
        local powerType, powerToken = UnitPowerType("player")
        local power = UnitPower("player", powerType)
        local powerMax = UnitPowerMax("player", powerType)
        print("|cff00ff00MochaAlerts|r Power diagnostic:")
        print("  Power type: " .. tostring(powerType) .. " (" .. tostring(powerToken) .. ")")
        print("  Current: " .. tostring(power) .. " / " .. tostring(powerMax))
        local foundAny = false
        for spellID in pairs(MA.charDb.trackedSpells) do
            local resMin = MA:GetSpellResourceMin(spellID)
            if resMin then
                foundAny = true
                local name = C_Spell.GetSpellName(spellID) or "Unknown"
                local known = IsPlayerSpell(spellID)
                local offCD = not MA:IsOnRealCooldown(spellID)
                local rState = MA.resourceReady[spellID]
                local meetsReq = power >= resMin
                print("  [" .. spellID .. "] " .. name .. ": min=" .. resMin .. " known=" .. tostring(known) .. " offCD=" .. tostring(offCD) .. " meets=" .. tostring(meetsReq) .. " state=" .. tostring(rState))
            end
        end
        if not foundAny then
            print("  No spells have a resource threshold set.")
        end

    elseif cmd == "debug" then
        MA.debugMode = not MA.debugMode
        print("|cff00ff00MochaAlerts:|r Debug mode: " .. (MA.debugMode and "ON" or "OFF"))
        if MA.debugMode then
            MA:InitCooldownStates()
            print("|cff00ff00MochaAlerts DBG:|r Tracked spells (states reinitialized):")
            for spellID in pairs(MA.charDb.trackedSpells) do
                local name = C_Spell.GetSpellName(spellID) or "Unknown"
                local known = IsPlayerSpell(spellID)
                local usable = C_Spell.IsSpellUsable(spellID)
                local onCD = MA:IsOnRealCooldown(spellID)
                local usState = MA.usableState[spellID]
                print("  " .. name .. " [" .. spellID .. "] known=" .. tostring(known) .. " usable=" .. tostring(usable) .. " onCD=" .. tostring(onCD) .. " state=" .. tostring(usState))
            end
        end

    elseif cmd == "reset" then
        MochaAlertsDB = CopyTable(defaults)
        MA.db = MochaAlertsDB
        MA:InitCooldownStates()
        print("|cff00ff00MochaAlerts:|r Settings reset to defaults.")
        if MA.configFrame and MA.configFrame:IsShown() then
            MA.configFrame:Hide()
        end

    elseif cmd == "" or cmd == "config" or cmd == "options" then
        local ok, err = pcall(MA.ToggleConfig, MA)
        if not ok then
            print("|cffff0000MochaAlerts ERROR:|r " .. tostring(err))
        end

    else
        MA:PrintHelp()
    end
end

function MA:PrintHelp()
    print("|cff00ff00MochaAlerts|r commands:")
    print("  |cff88bbff/malerts|r — Open config panel")
    print("  |cff88bbff/malerts add [name or ID]|r — Track a spell or item")
    print("  |cff88bbff/malerts remove [name or ID]|r — Untrack a spell or item")
    print("  |cff88bbff/malerts list|r — Show tracked spells and items")
    print("  |cff88bbff/malerts scantrinkets|r — Auto-add equipped trinkets")
    print("  |cff88bbff/malerts scanitems|r   — Alias for scantrinkets")
    print("  |cff88bbff/malerts toggle|r — Enable / disable alerts")
    print("  |cff88bbff/malerts test|r — Play a test voice alert")
    print("  |cff88bbff/malerts tts|r — Run TTS diagnostic")
    print("  |cff88bbff/malerts voice|r — List / select TTS voice")
    print("  |cff88bbff/malerts power|r — Show power/resource diagnostic")
    print("  |cff88bbff/malerts debug|r — Toggle debug output")
    print("  |cff88bbff/malerts reset|r — Reset all settings")
end
