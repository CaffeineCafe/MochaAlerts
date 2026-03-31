local addonName, MA = ...

-- Upvalue hot-path globals (avoids global table lookups on every poll tick)
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsPlayerSpell = IsPlayerSpell
local C_Spell = C_Spell
local C_Timer = C_Timer
local pairs = pairs
local ipairs = ipairs
local type = type
local wipe = wipe
local pcall = pcall
local tinsert = tinsert
local tconcat = table.concat

-- Constants
local ALERT_THROTTLE = 0.3
local TTS_COALESCE_WINDOW = 0.05  -- brief window to catch truly simultaneous alerts before speaking
local DEFAULT_POLL_INTERVAL = 0.25 -- fallback before DB loads; overridden by db.pollInterval

-- Defaults
local defaults = {
    enabled = true,
    alertInCombat = true,
    showVisual = true,
    alertScale = 1.0,
    alertPos = nil,  -- { point, relPoint, x, y }
    ttsVoice = 0,   -- 0-based index into C_VoiceChat.GetTtsVoices() (0 = first voice)
    pollInterval = 0.25, -- safety-net poll interval in seconds (0.01–0.40)
    alertFont = nil, -- nil = default Friz Quadrata; otherwise a FontMagic font path
    alertColor = {r = 0, g = 1, b = 0}, -- visual alert text color (default green)
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
MA.usableLiesDuringCD = {} -- [spellID] = true for spells where IsSpellUsable returns true during real CD (e.g. interrupt lockout)
MA.chargeCount = {}       -- [baseSpellID] = last known currentCharges (only for spells with maxCharges > 1)
MA._chargeTimers = {}     -- [baseSpellID] = C_Timer handle for per-charge recovery detection
MA._chargeRechargeDur = {} -- [baseSpellID] = per-charge recharge duration in seconds (cached at init, out of combat)
MA._chargedSpells = {}    -- [baseSpellID] = maxCharges, cached at init (out of combat) so we never need secret-value APIs at runtime
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

-- NOTE: In WoW 12.0.1+, neither SetCooldown() nor SetCooldownFromDurationObject()
-- accept the Lua table from C_Spell.GetSpellCooldown (secret value restrictions).
-- Spell readiness is detected by polling the non-secret isActive boolean.
-- Charged spell recovery uses C_Timer with cached recharge durations.
-- Item CD frames still work because GetItemCooldown returns non-secret values.


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
-- Font Library (sourced from FontMagic addon)
-------------------------------------------------------------------------------
MA.FontLib = {}  -- { { name = "Display Name", path = "Interface\\...\\file.ttf", category = "Popular" }, ... }
MA.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

do
    local FM_PATH = "Interface\\AddOns\\FontMagic\\"
    -- Mirror FontMagic's category→folder mapping
    local FM_GROUPS = {
        { category = "Popular",          folder = "Popular" },
        { category = "Clean & Readable", folder = "Easy-to-Read" },
        { category = "Bold & Impact",    folder = "BoldImpact" },
        { category = "Fantasy & RP",     folder = "Fun" },
        { category = "Sci-Fi & Tech",    folder = "Future" },
        { category = "Random",           folder = "Random" },
    }
    -- Font files per folder (must match FontMagic's shipped files)
    local FM_FONTS = {
        ["Popular"] = {
            "Pepsi.ttf", "bignoodletitling.ttf", "Expressway.ttf", "Bangers.ttf", "PTSansNarrow-Bold.ttf", "Roboto Condensed Bold.ttf",
            "NotoSans_Condensed-Bold.ttf", "Roboto-Bold.ttf", "AlteHaasGroteskBold.ttf", "CalibriBold.ttf", "Orbitron.ttf", "Prototype.ttf",
            "914Solid.ttf", "Halo.ttf", "Proxima Nova Condensed Bold.ttf", "Comfortaa-Bold.ttf", "Andika-Bold.ttf", "lemon-milk.ttf",
            "Good Brush.ttf", "KG HAPPY.ttf",
        },
        ["Easy-to-Read"] = {
            "BauhausRegular.ttf", "Butterpop.ttf", "Diogenes.ttf", "Junegull.ttf", "Pantalone.ttf", "Resoft.ttf",
            "Retro Amour.ttf", "SF-Pro.ttf", "Solange.ttf", "Takeaway.ttf",
        },
        ["BoldImpact"] = {
            "airstrikebold.ttf", "Blazed.ttf", "DieDieDie.ttf", "graff.ttf", "Green Fuz.otf", "Love Craft.ttf",
            "modernwarfare.ttf", "Showpop.ttf", "Skratchpunk.ttf", "Skullphabet.ttf", "Trashco.ttf", "Whiplash.ttf",
        },
        ["Fun"] = {
            "Acadian.ttf", "akash.ttf", "Caesar.ttf", "ComicRunes.ttf", "crygords.ttf", "Deltarune.ttf",
            "Elven.ttf", "Gunung.ttf", "Guroes.ttf", "HarryP.ttf", "Hobbit.ttf", "Kting.ttf",
            "leviathans.ttf", "MystikOrbs.ttf", "Odinson.ttf", "ParryHotter.ttf", "Pau.ttf", "Pokemon.ttf",
            "Runic.ttf", "Runy.ttf", "Ruritania.ttf", "Spongebob.ttf", "Starborn.ttf", "Starshines.ttf",
            "The Centurion .ttf", "Vampire Wars.ttf", "VTKS.ttf", "WaltographUI.ttf", "Wasser.ttf", "Wickedmouse.ttf",
            "WKnight.ttf", "Zombie.ttf",
        },
        ["Future"] = {
            "04b.ttf", "albra.TTF", "Audiowide.ttf", "continuum.ttf", "dalek.ttf", "digital-7.ttf",
            "Digital.ttf", "Exocet.ttf", "Galaxyone.ttf", "Minecrafter.Reg.ttf", "pf_tempesta_seven.ttf", "Price.ttf",
            "RaceSpace.ttf", "RushDriver.ttf", "space age.ttf", "Terminator.ttf",
        },
        ["Random"] = {
            "accidentalpres.ttf", "animeace.ttf", "Barriecito.ttf", "baskethammer.ttf", "ChopSic.ttf", "college.ttf",
            "Disko.ttf", "Dmagic.ttf", "edgyh.ttf", "edkies.ttf", "FastHand.ttf", "figtoen.ttf",
            "font2.ttf", "Fraks.ttf", "Ginko.ttf", "Homespun.ttf", "IKARRG.TTF", "JJSTS.TTF",
            "KOMIKAX_.ttf", "Ktingw.ttf", "Melted.ttf", "Midorima.ttf", "Munsteria.ttf", "Rebuffed.TTF",
            "Shiruken.ttf", "shog.ttf", "Starcine.ttf", "Stentiga.ttf", "tsuchigumo.ttf", "WhoAsksSatan.ttf",
        },
    }
    -- Strip extension and normalize display name (mirrors FontMagic's __fmShortenFontLabel)
    local function StripFontName(fname)
        local s = fname:gsub("%.[Tt][Tt][Ff]$", ""):gsub("%.[Oo][Tt][Ff]$", "")
        s = s:gsub("[_%-]+", " ")
        s = s:gsub("(%l)(%u)", "%1 %2")
        s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return s
    end
    for _, group in ipairs(FM_GROUPS) do
        local files = FM_FONTS[group.folder]
        if files then
            for _, fname in ipairs(files) do
                local path = FM_PATH .. group.folder .. "\\" .. fname
                tinsert(MA.FontLib, {
                    name = StripFontName(fname),
                    path = path,
                    category = group.category,
                })
            end
        end
    end
end

function MA:GetAlertFontPath()
    return (self.db and self.db.alertFont) or self.DEFAULT_FONT
end

function MA:GetAlertColor()
    local c = self.db and self.db.alertColor
    if c then return c.r, c.g, c.b end
    return 0, 1, 0
end

function MA:SetAlertColor(r, g, b)
    self.db.alertColor = {r = r, g = g, b = b}
end

function MA:GetAlertColorHex()
    local r, g, b = self:GetAlertColor()
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function MA:SetAlertFont(path)
    self.db.alertFont = (path ~= self.DEFAULT_FONT) and path or nil
    local fontPath = path or self.DEFAULT_FONT
    -- Update all existing alert frames
    for _, f in ipairs(self.alertPool) do
        if f.text then
            f.text:SetFont(fontPath, 24, "OUTLINE")
        end
    end
end

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
        text:SetFont(self:GetAlertFontPath(), 24, "OUTLINE")
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
    if self._cachedVoices then return self._cachedVoices end
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and voices and #voices > 0 then
            self._cachedVoices = voices
            return voices
        end
    end
    return nil
end

function MA:GetSelectedVoice()
    if self._cachedSelectedVoice then return self._cachedSelectedVoice end
    local voices = self:GetTTSVoices()
    if not voices then return nil end
    local idx = (self.db.ttsVoice or 0) + 1
    local voice = voices[idx] or voices[1]
    self._cachedSelectedVoice = voice
    return voice
end

function MA:TryTTS(text)
    local voice = self:GetSelectedVoice()
    -- Method 1: TextToSpeech_Speak with the actual voice OBJECT (not ID)
    if TextToSpeech_Speak and voice then
        local ok, err = pcall(TextToSpeech_Speak, text, voice)
        if self.debugMode then
            print("|cff00ff00MochaAlerts DBG:|r TTS Method1 (TextToSpeech_Speak + voiceObj): ok=" .. tostring(ok) .. " err=" .. tostring(err))
        end
        if ok then return true end
    end

    -- Method 2: Direct C_VoiceChat.SpeakText with voice object's voiceID
    if C_VoiceChat and C_VoiceChat.SpeakText then
        local vid = voice and voice.voiceID or 0
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
-- The FIRST alert in a burst is spoken immediately (zero latency).  If a
-- second alert arrives within TTS_COALESCE_WINDOW of that first one, the
-- engine is stopped and both are re-spoken as a combined string.  This avoids
-- the old 50ms delay on every single alert while still coalescing true
-- simultaneous bursts ("Void Ray, Collapsing Star").
-------------------------------------------------------------------------------
function MA:_QueueTTS(text)
    tinsert(self.ttsQueue, text)
    if not self.ttsFlushPending then
        -- First alert in this burst: speak it NOW (zero latency).
        -- Also start a short coalesce window — if a second alert arrives
        -- before the timer fires, we stop the first speech and re-speak
        -- the combined string.
        self.ttsFlushPending = true
        self:_FlushTTSQueue(true)  -- true = immediate flush (keep window open)
        C_Timer.After(TTS_COALESCE_WINDOW, function()
            if #MA.ttsQueue > 0 then
                -- More alerts arrived during the window; re-speak combined.
                MA:_FlushTTSQueue(false)
            else
                MA.ttsFlushPending = false
            end
        end)
    else
        -- A second (or third) alert arrived while the coalesce window is open.
        -- Stop the in-progress single speech so the timer re-speaks combined.
        if C_VoiceChat and C_VoiceChat.StopSpeakingText then
            pcall(C_VoiceChat.StopSpeakingText)
        end
    end
end

function MA:_FlushTTSQueue(keepWindow)
    if not keepWindow then
        self.ttsFlushPending = false
    end
    if #self.ttsQueue == 0 then return end
    local combined = tconcat(self.ttsQueue, ", ")
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

    -- Per-spell mode and custom TTS text (single table lookup)
    local data = spellID and self.charDb.trackedSpells[spellID]
    local mode = (type(data) == "table" and data.mode) or "tts"
    if mode == "tts" then
        local ttsText = (type(data) == "table" and data.ttsText ~= "" and data.ttsText) or nil
        self:_QueueTTS(ttsText or text)
    elseif mode ~= "none" then
        local soundKey = (type(data) == "table" and data.sound) or "RaidWarning"
        self:PlaySoundByKey(soundKey)
    end

    -- Visual feedback (custom frame is safe during combat)
    if self.db.showVisual then
        local visText = (type(data) == "table" and data.displayText ~= "" and data.displayText) or text
        self:ShowAlertText(self:GetAlertColorHex() .. visText .. "|r", spellID, nil)
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
    local data = spellID and self.charDb.trackedSpells[spellID]
    local mode = (type(data) == "table" and data.mode) or "tts"
    if mode == "tts" then
        local ttsText = (type(data) == "table" and data.ttsText ~= "" and data.ttsText) or nil
        self:_QueueTTS(ttsText or text)
    elseif mode ~= "none" then
        self:PlaySoundByKey((type(data) == "table" and data.sound) or "RaidWarning")
    end
    if self.db.showVisual then
        local visText = (type(data) == "table" and data.displayText ~= "" and data.displayText) or text
        self:ShowAlertText(self:GetAlertColorHex() .. visText .. "|r", spellID, nil)
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
        local visText = self:GetItemDisplayText(itemID) or text
        self:ShowAlertText(self:GetAlertColorHex() .. visText .. "|r", nil, itemID)
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
        self:ShowAlertText(self:GetAlertColorHex() .. visText .. "|r", nil, itemID)
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
        -- readiness so the mode change doesn't trigger a false alert.
        local prevActiveID = self._lastActiveID[baseID]
        if prevActiveID and prevActiveID ~= activeID and self.usableState[baseID] ~= nil then
            anyOverrideChanged = true
            -- Evaluate readiness for the NEW override using the same
            -- logic as CheckUsability.
            local rawUsable = C_Spell.IsSpellUsable(activeID)
            local cdInfo = C_Spell.GetSpellCooldown(activeID)
            local cdActive = cdInfo and cdInfo.isActive
            local newReady
            if self.usableLiesDuringCD[baseID] then
                if not (rawUsable == true) then
                    newReady = false
                elseif not cdActive then
                    newReady = true
                else
                    -- isUsable + cdActive: could be GCD or real lockout.
                    -- Preserve current state.
                    local prev = self.usableState[baseID]
                    newReady = (prev == nil) and false or prev
                end
            else
                newReady = (rawUsable == true)
            end
            if not newReady then
                -- New override is NOT ready (on CD or not usable).
                self.usableState[baseID] = false
                if activeID == baseID then
                    -- Form EXIT, not ready: spell is off-CD but resource-gated
                    -- (e.g. not enough Fury).  Clear usableFalseAt so the
                    -- bounce guard doesn't eat the alert when resource ticks up.
                    self.usableFalseAt[baseID] = nil
                    self.spellCastSeen[baseID] = true
                else
                    -- Form ENTRY, on real CD: stamp false time to guard against
                    -- any instant-flip inside the new form.
                    self.usableFalseAt[baseID] = GetTime()
                end
            else
                -- New override is IMMEDIATELY ready.
                if activeID == baseID then
                    -- Form EXIT: the override was lost and the base version is
                    -- already ready (CD finished while in form, e.g. Void Ray
                    -- ready when Void Meta ends).  Force false so CheckUsability
                    -- sees the false->true transition and fires the alert.
                    self.usableState[baseID] = false
                    self.usableFalseAt[baseID] = nil
                    self.spellCastSeen[baseID] = true
                else
                    -- Form ENTRY: a new override was gained and it is immediately
                    -- ready (e.g. Void Meta reset Void Ray/Collapsing Star's CD).
                    -- Leave usableState as-is: if false, CheckUsability will alert
                    -- (Meta reset your CD — you want to know).  If already true,
                    -- no spurious alert fires.
                    self.usableFalseAt[baseID] = nil
                    self.spellCastSeen[baseID] = true
                end
            end
            if self.debugMode then
                local name = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseID) or tostring(baseID)
                print("|cffff8800MochaAlerts DBG:|r Override changed for " .. name .. " [" .. baseID .. "]: "
                    .. tostring(prevActiveID) .. " -> " .. tostring(activeID)
                    .. ", newReady=" .. tostring(newReady)
                    .. " (usableState=" .. tostring(self.usableState[baseID]) .. ")")
            end
        end
        self._lastActiveID[baseID] = activeID
        -- Cache for CheckCooldowns: avoids GetActiveSpellID + IsPlayerSpell*2 per check.
        if IsPlayerSpell(baseID) or IsPlayerSpell(activeID) then
            self._activeSpellCache[baseID] = activeID
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
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return false end
    for _, auraID in ipairs(LTA_SPELL_IDS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(auraID) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
function MA:IsOnRealCooldown(spellID)
    local activeID = self:GetActiveSpellID(spellID)
    local cooldownInfo = C_Spell.GetSpellCooldown(activeID)
    if not cooldownInfo then return false end
    -- 12.0.1+: isActive is non-secret and true when a real CD is displayed.
    return cooldownInfo.isActive == true
end

---------------------------------------------------------------------------
-- Timer-based per-charge recovery detection.
-- CooldownFrame + SetCooldown/SetCooldownFromDurationObject can't work
-- because spell startTime/duration are secret in combat.  Instead we cache
-- the per-charge recharge duration at init (out of combat) and use
-- C_Timer.NewTimer after each cast to schedule recovery callbacks.
---------------------------------------------------------------------------
function MA:ArmChargeWatch(baseSpellID, forceNew)
    -- If a timer is already running and we're not forcing a new one, leave it.
    if self._chargeTimers[baseSpellID] and not forceNew then
        if self.debugMode then
            local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
            print("|cffaa88ffMochaAlerts DBG:|r ArmChargeWatch: " .. name .. " timer already running, skipping")
        end
        return
    end

    -- Cancel any stale timer.
    if self._chargeTimers[baseSpellID] then
        self._chargeTimers[baseSpellID]:Cancel()
        self._chargeTimers[baseSpellID] = nil
    end

    local rechargeDur = self._chargeRechargeDur[baseSpellID]
    if not rechargeDur or rechargeDur <= 0 then
        if self.debugMode then
            local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
            print("|cffff8800MochaAlerts DBG:|r ArmChargeWatch: " .. name .. " no cached recharge duration, skipping")
        end
        return
    end

    -- Out of combat we can calculate the exact remaining time.
    local remaining = rechargeDur
    if not InCombatLockdown() then
        local activeID = self._activeSpellCache[baseSpellID] or self:GetActiveSpellID(baseSpellID)
        local chargeInfo = C_Spell.GetSpellCharges(activeID)
        if not chargeInfo then chargeInfo = C_Spell.GetSpellCharges(baseSpellID) end
        if chargeInfo and chargeInfo.cooldownStartTime and chargeInfo.cooldownDuration
           and chargeInfo.cooldownDuration > 0 then
            remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
        end
    end

    if remaining <= 0.05 then return end  -- already recovered

    self._chargeTimers[baseSpellID] = C_Timer.NewTimer(remaining, function()
        self._chargeTimers[baseSpellID] = nil
        MA:OnChargeRecovered(baseSpellID)
    end)

    if self.debugMode then
        local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
        print("|cffaa88ffMochaAlerts DBG:|r Armed charge timer for " .. name .. " (" .. string.format("%.1f", remaining) .. "s)")
    end
end

function MA:OnChargeRecovered(baseSpellID)
    if not self.spellCastSeen[baseSpellID] then return end

    local maxCharges = self._chargedSpells[baseSpellID]
    if not maxCharges then return end

    local prev = self.chargeCount[baseSpellID] or 0
    local newCount = prev + 1
    if newCount > maxCharges then newCount = maxCharges end
    self.chargeCount[baseSpellID] = newCount
    self.usableState[baseSpellID] = newCount > 0

    -- Alert
    local now = GetTime()
    local lastAlert = self.lastSpellAlert[baseSpellID] or 0
    if (now - lastAlert) >= ALERT_THROTTLE then
        self.lastSpellAlert[baseSpellID] = now
        local activeID = self._activeSpellCache[baseSpellID] or self:GetActiveSpellID(baseSpellID)
        local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID)
        if spellName then
            if self.debugMode then
                print("|cffaa88ffMochaAlerts DBG:|r Charge recovered (timer): " .. spellName .. " (" .. prev .. " -> " .. newCount .. "/" .. maxCharges .. ")")
            end
            self:Speak(spellName .. " ready", baseSpellID)
        end
    end

    -- If still recharging, re-arm for the next charge recovery (full duration).
    if newCount < maxCharges then
        self:ArmChargeWatch(baseSpellID, true)  -- force new timer
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

    -- Determine if this spell has multiple charges.
    -- GetSpellCharges/GetSpellCooldown return secret proxies in combat that
    -- break comparisons, so we use the _chargedSpells cache (seeded at init).
    local maxCh = self._chargedSpells[baseID]

    -- Runtime fallback: if not cached, check cdInfo.maxCharges (non-secret,
    -- accurate when the spell is on CD).
    if not maxCh then
        local cdInfo = C_Spell.GetSpellCooldown(baseID)
        if cdInfo and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
            maxCh = cdInfo.maxCharges
            self._chargedSpells[baseID] = maxCh
            if self.debugMode then
                local name = C_Spell.GetSpellName(baseID) or tostring(baseID)
                print("|cff88ffffMochaAlerts DBG:|r Runtime detected " .. name .. " as charged (" .. maxCh .. " max) from OnSpellCast")
            end
        end
    end

    if maxCh then
        -- Charged spell: decrement our internal counter.
        -- currentCharges is secret in combat, so we use chargeCount instead.
        -- Out of combat OnSpellCast fires before the charge is deducted,
        -- so we use our counter which was last synced by CheckUsability.
        local prev = self.chargeCount[baseID] or maxCh
        local afterCast = prev - 1
        if afterCast < 0 then afterCast = 0 end
        self.chargeCount[baseID] = afterCast
        self.spellCastSeen[baseID] = true
        if afterCast < 1 then
            -- All charges spent — spell truly becomes not-ready.
            self.usableState[baseID] = false
            self.usableFalseAt[baseID] = GetTime()
        end
        if self.debugMode then
            print("|cff88ffffMochaAlerts DBG:|r Charged spell cast: " .. afterCast .. "/" .. maxCh .. " charges remain")
        end
        -- Start a charge recovery timer.
        -- Only force a new timer when we were at max charges (new recharge cycle).
        -- Otherwise let the existing timer run for the current recharge.
        local wasAtMax = (prev == maxCh)
        if wasAtMax or not self._chargeTimers[baseID] then
            self:ArmChargeWatch(baseID, true)  -- force new timer
        end
    else
        -- Non-charged spell: force usableState to false on cast so the
        -- false->true transition in CheckUsability fires when the CD expires.
        self.usableState[baseID] = false
        self.usableFalseAt[baseID] = GetTime()
        self.spellCastSeen[baseID] = true
    end
end

-------------------------------------------------------------------------------
-- Cooldown Tracking
-------------------------------------------------------------------------------

-- GetSpellCooldown().maxCharges is unreliable for some charged spells (reports 0).
-- GetSpellCharges() is the authoritative source.
local function GetSpellMaxCharges(spellID)
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        return chargeInfo.maxCharges
    end
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    return cdInfo and cdInfo.maxCharges or 0
end

function MA:CheckCooldowns()
    for baseSpellID, activeID in pairs(self._activeSpellCache) do
        self:CheckUsability(baseSpellID, activeID)
    end
    -- Resource thresholds only work out of combat (UnitPower returns secret values).
    -- Skipping this loop in combat avoids per-spell function call overhead.
    if not InCombatLockdown() then
        for baseSpellID in pairs(self._activeSpellCache) do
            self:CheckResource(baseSpellID)
        end
    end
end

-------------------------------------------------------------------------------
-- Usability Tracking (primary mechanism — works in AND out of combat)
--
-- WoW 12.0.1+: C_Spell.GetSpellCooldown now returns a non-secret "isActive"
-- boolean that reliably indicates whether a cooldown is being rendered.
-- Combined with C_Spell.IsSpellUsable (also non-secret), we can definitively
-- determine spell readiness without CD frames or secret-value tricks.
-- Most spells:  ready = IsSpellUsable(id)
--   (GCD is irrelevant — alerts fire the instant the real CD expires.)
-- Interrupt-like spells (auto-detected):  usable=true even during lockout,
--   so when isUsable+cdActive we preserve the prior state (could be GCD).
--   OnSpellCast forces usableState=false for real casts.
-------------------------------------------------------------------------------
function MA:CheckUsability(baseSpellID, activeID)
    activeID = activeID or self:GetActiveSpellID(baseSpellID)

    -- Query usability on the ACTIVE (possibly overridden) spell ID
    local rawUsable = C_Spell.IsSpellUsable(activeID)
    local isUsable = (rawUsable == true) and true or false

    -- Query the non-secret isActive boolean from cooldown info (12.0.1+)
    -- isActive is true when a cooldown should be displayed:
    --   regular CD: isEnabled and startTime > 0 and duration > 0
    --   charge CD:  maxCharges > 1 and currentCharges < maxCharges and start > 0 and dur > 0
    local cdInfo = C_Spell.GetSpellCooldown(activeID)
    local cdActive = cdInfo and cdInfo.isActive

    -- Check if this is a charged spell from our init-time cache.
    -- GetSpellCharges returns secret proxies in combat; the cache is reliable.
    local maxCharges = self._chargedSpells[baseSpellID] or 0

    -- Runtime fallback: cdInfo.maxCharges (non-secret in 12.0.1+) is accurate
    -- when the spell is actively on CD.  Some charged spells report maxCharges=0
    -- when fully charged (off CD), so init may miss them.  Detect them here.
    if maxCharges <= 1 and cdInfo and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
        maxCharges = cdInfo.maxCharges
        self._chargedSpells[baseSpellID] = maxCharges
        -- Also un-flag usableLiesDuringCD if it was incorrectly set.
        self.usableLiesDuringCD[baseSpellID] = nil
        if self.debugMode then
            local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
            print("|cffaa88ffMochaAlerts DBG:|r Runtime detected " .. name .. " as charged (" .. maxCharges .. " max)")
        end
    end

    -- Auto-detect spells where IsSpellUsable lies during a real CD (e.g.
    -- interrupt lockout: usable=true while cdActive=true after a confirmed cast).
    -- Charged spells (maxCharges>1) are excluded: usable+cdActive is normal for them.
    if isUsable and cdActive and self.spellCastSeen[baseSpellID]
       and not self.usableLiesDuringCD[baseSpellID]
       and maxCharges <= 1 then
        self.usableLiesDuringCD[baseSpellID] = true
        if self.debugMode then
            local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
            print("|cffaa88ffMochaAlerts DBG:|r Auto-flagged " .. name .. " as usable-lies-during-CD")
        end
    end

    ---------------------------------------------------------------------------
    -- Charged spell handling: alert on charge RECOVERY, not on use.
    -- In combat: C_Timer (armed in OnSpellCast) fires after the cached
    --   per-charge recharge duration.
    -- Out of combat: we sync from the real currentCharges value.
    ---------------------------------------------------------------------------
    if maxCharges > 1 then
        local prevCount = self.chargeCount[baseSpellID]

        -- Out of combat: sync from the real value (currentCharges is readable).
        if not InCombatLockdown() then
            local chargeInfo = C_Spell.GetSpellCharges(activeID)
            if not chargeInfo then chargeInfo = C_Spell.GetSpellCharges(baseSpellID) end
            if chargeInfo and chargeInfo.currentCharges then
                local cur = chargeInfo.currentCharges
                -- Keep recharge duration cached for in-combat timers (haste may change).
                if chargeInfo.cooldownDuration and chargeInfo.cooldownDuration > 0 then
                    self._chargeRechargeDur[baseSpellID] = chargeInfo.cooldownDuration
                end
                -- Detect recovery: count went UP since last check
                if prevCount and cur > prevCount and self.spellCastSeen[baseSpellID] then
                    local now = GetTime()
                    local lastAlert = self.lastSpellAlert[baseSpellID] or 0
                    if (now - lastAlert) >= ALERT_THROTTLE then
                        self.lastSpellAlert[baseSpellID] = now
                        local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID)
                        if spellName then
                            if self.debugMode then
                                print("|cffaa88ffMochaAlerts DBG:|r Charge recovered: " .. spellName .. " (" .. prevCount .. " -> " .. cur .. "/" .. maxCharges .. ")")
                            end
                            self:Speak(spellName .. " ready", baseSpellID)
                        end
                    end
                end
                self.chargeCount[baseSpellID] = cur
                self.usableState[baseSpellID] = isUsable and cur > 0
            end
        end
        -- In combat: C_Timer handles recovery detection (see ArmChargeWatch).
        -- Just keep usableState in sync with our counter.
        if self.chargeCount[baseSpellID] and self.chargeCount[baseSpellID] > 0 then
            self.usableState[baseSpellID] = true
        end
        return  -- charged spells fully handled; skip normal path
    end

    -- Readiness: for most spells, IsSpellUsable alone is sufficient and lets
    -- alerts fire mid-GCD.
    -- Interrupt-like spells (usableLiesDuringCD): IsSpellUsable returns true
    -- even during a real lockout CD.  When isUsable+cdActive, it could be
    -- just GCD from another spell — preserve the current state.  OnSpellCast
    -- already forces usableState=false for real casts.
    local isReady
    if self.usableLiesDuringCD[baseSpellID] then
        if not isUsable then
            isReady = false
        elseif not cdActive then
            isReady = true
        else
            -- isUsable + cdActive: could be GCD or real lockout.
            -- Preserve current state; OnSpellCast handles the lockout transition.
            local prev = self.usableState[baseSpellID]
            isReady = (prev == nil) and false or prev
        end
    else
        isReady = isUsable
    end
    local wasReady = self.usableState[baseSpellID]

    if self.debugMode and wasReady ~= isReady then
        local name = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
        print("|cffaa88ffMochaAlerts DBG:|r [" .. baseSpellID .. "/" .. activeID .. "] " .. name
            .. " ready: " .. tostring(wasReady) .. " -> " .. tostring(isReady)
            .. " (usable=" .. tostring(isUsable) .. ", cdActive=" .. tostring(cdActive) .. ")")
    end

    -- Alert on not-ready -> ready transition
    if isReady and wasReady == false then
        -- Primary gate: only alert if we observed a real cast this session.
        -- Zone changes, rezes, and form-resets can flip a spell from
        -- not-ready -> ready without any cast; spellCastSeen is wiped by
        -- InitCooldownStates so those transitions are suppressed.
        if not self.spellCastSeen[baseSpellID] then
            if self.debugMode then
                local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
                print("|cffff8800MochaAlerts DBG:|r Suppressed no-cast-seen alert for " .. name)
            end
            self.usableState[baseSpellID] = isReady
            return
        end

        local now = GetTime()

        -- Post-cast bounce guard: right after a cast, APIs can briefly
        -- report usable=true / cdActive=false before the CD is fully applied.
        local falseAt = self.usableFalseAt[baseSpellID]
        if falseAt and (now - falseAt) < 0.1 then
            if self.debugMode then
                local name = C_Spell.GetSpellName(baseSpellID) or tostring(baseSpellID)
                print("|cffff8800MochaAlerts DBG:|r Suppressed bounce for " .. name
                    .. " (not-ready for " .. string.format("%.2f", now - falseAt) .. "s)")
            end
            -- Don't update state — wait for a real transition
            return
        end

        -- Consume the cast-seen flag; cleared so a second external reset
        -- after a real cast doesn't sneak through.
        self.spellCastSeen[baseSpellID] = nil

        -- Skip if inside lockout suppression window (Roll, Chi Torpedo, etc.)
        local hasLTA = self:HasLTABuff()
        if now < self.lockoutUntil or hasLTA then
            if self.debugMode then
                print("|cffff8800MochaAlerts DBG:|r Suppressed alert (lockout=" .. string.format("%.1f", self.lockoutUntil - now) .. "s remaining, LTA=" .. tostring(hasLTA) .. ")")
            end
            if hasLTA then
                local newUntil = now + 6.0
                if newUntil > self.lockoutUntil then
                    self.lockoutUntil = newUntil
                end
            end
            self.usableState[baseSpellID] = isReady
            return
        end

        local lastAlert = self.lastSpellAlert[baseSpellID] or 0
        if (now - lastAlert) >= ALERT_THROTTLE then
            self.lastSpellAlert[baseSpellID] = now
            -- Use the active (override) spell name so transforms like
            -- Void Meta -> Collapsing Star alert with the visible name.
            local spellName = C_Spell.GetSpellName(activeID) or C_Spell.GetSpellName(baseSpellID)
            if spellName then
                self:Speak(spellName .. " ready", baseSpellID)
            end
        end
    end

    -- Record when this spell transitions to not-ready so the bounce guard
    -- can filter brief post-cast API bounces.
    if not isReady and wasReady ~= false then
        self.usableFalseAt[baseSpellID] = GetTime()
    end
    self.usableState[baseSpellID] = isReady
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
    if duration == 0 then return false end
    -- Filter GCD (≤1.5s)
    if duration <= 1.5 then return false end
    return true
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

end

function MA:ProcessItemPendingCDs()
    for itemID, doneTime in pairs(self.itemCdPending) do
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
    wipe(self.resourceReady)
    wipe(self.lastSpellAlert)
    wipe(self.usableLiesDuringCD)
    wipe(self.chargeCount)
    -- Cancel any running charge recovery timers.
    for id, timer in pairs(self._chargeTimers) do
        timer:Cancel()
    end
    wipe(self._chargeTimers)
    -- Do NOT wipe _chargedSpells or _chargeRechargeDur: once detected (at login, out of combat),
    -- the charged status is permanent for the session.  In-combat reinits
    -- (e.g. /ma debug) would fail to re-detect because GetSpellCharges
    -- returns secret proxy values that break comparisons.

    for spellID in pairs(self.charDb.trackedSpells) do
        local activeID = self:GetActiveSpellID(spellID)
        if IsPlayerSpell(spellID) or IsPlayerSpell(activeID) then
            local rawUsable = C_Spell.IsSpellUsable(activeID)
            local cdInfo = C_Spell.GetSpellCooldown(activeID)
            local cdActive = cdInfo and cdInfo.isActive
            -- Use cached charged-spell info first (reliable), fall back to API
            -- only when not cached (works out of combat, fails in combat).
            local maxCharges = self._chargedSpells[spellID]
            if not maxCharges then
                maxCharges = GetSpellMaxCharges(activeID)
                if maxCharges <= 1 then maxCharges = GetSpellMaxCharges(spellID) end
                if maxCharges > 1 then
                    self._chargedSpells[spellID] = maxCharges
                end
            end

            -- Auto-detect interrupt-like spells at init: usable=true while
            -- cdActive=true (e.g. Disrupt during lockout).  Exclude charged
            -- spells where that combination is normal.
            if rawUsable and cdActive and (not maxCharges or maxCharges <= 1) then
                self.usableLiesDuringCD[spellID] = true
            end

            -- Readiness: GCD is never accounted for.
            local isReady
            if maxCharges and maxCharges > 1 then
                -- Charged spell: seed the internal counter.
                -- Out of combat: read real currentCharges.
                -- In combat: infer from IsSpellUsable (true = at least 1 charge).
                local cur
                if not InCombatLockdown() then
                    local chargeInfo = C_Spell.GetSpellCharges(activeID)
                    if not chargeInfo then chargeInfo = C_Spell.GetSpellCharges(spellID) end
                    cur = chargeInfo and chargeInfo.currentCharges or 0
                    -- Cache per-charge recharge duration for in-combat timers.
                    if chargeInfo and chargeInfo.cooldownDuration and chargeInfo.cooldownDuration > 0 then
                        self._chargeRechargeDur[spellID] = chargeInfo.cooldownDuration
                    end
                else
                    -- In combat: best we can do is assume max if usable+!cdActive,
                    -- 1 if usable+cdActive, 0 if not usable.
                    if rawUsable and not cdActive then
                        cur = maxCharges
                    elseif rawUsable then
                        cur = 1  -- at least 1, recharging others
                    else
                        cur = 0
                    end
                end
                self.chargeCount[spellID] = cur
                isReady = (rawUsable == true) and cur > 0
                -- If charges are recharging at init, arm a recovery timer.
                if cdActive then
                    self:ArmChargeWatch(spellID, true)
                end
            elseif self.usableLiesDuringCD[spellID] then
                -- At init, no previous state exists; default to not-ready
                -- when cdActive (could be real lockout or GCD — safe to assume CD).
                isReady = (rawUsable == true) and not cdActive
            else
                isReady = (rawUsable == true)
            end
            self.usableState[spellID] = isReady
            -- Stamp false-at so any immediate post-init transition (e.g. a port
            -- resetting a cooldown) is caught by the bounce guard.
            if not isReady then
                self.usableFalseAt[spellID] = GetTime()
                -- Spell was not ready at init: pre-arm so its first expiry alerts.
                -- (spellCastSeen stays nil for spells that start ready, which
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
            local poll = (MA.db and MA.db.pollInterval) or DEFAULT_POLL_INTERVAL
            if MA.elapsed >= poll then
                MA.elapsed = 0
                if MA.initialized and MA.db then
                    local now = GetTime()
                    if (now - MA.lastSpellCheckTime) >= poll then
                        MA.lastSpellCheckTime = now
                        pcall(MA.CheckCooldowns, MA)
                    end
                    if (now - MA.lastItemCheckTime) >= poll then
                        MA.lastItemCheckTime = now
                        pcall(MA.CheckItemCooldowns, MA)
                    end
                end
            end
        end)
        print("|cff00ff00MochaAlerts|r v1.2.0 loaded. Type |cff88bbff/malerts|r to configure.")

        -- Register in the in-game Addon settings list
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local panel = CreateFrame("Frame")
            panel.name = "MochaAlerts"

            -- Header background
            local hBg = panel:CreateTexture(nil, "BACKGROUND")
            hBg:SetPoint("TOPLEFT", 0, 0)
            hBg:SetPoint("TOPRIGHT", 0, 0)
            hBg:SetHeight(54)
            hBg:SetColorTexture(0.14, 0.14, 0.13, 1.0)
            hBg:SetDrawLayer("BACKGROUND", 1)

            -- Header separator
            local hSep = panel:CreateTexture(nil, "BORDER")
            hSep:SetPoint("TOPLEFT", 0, -54)
            hSep:SetPoint("TOPRIGHT", 0, -54)
            hSep:SetHeight(1)
            hSep:SetColorTexture(0.42, 0.37, 0.30, 0.9)

            -- Coffee icon
            local hIcon = panel:CreateTexture(nil, "ARTWORK")
            hIcon:SetSize(36, 36)
            hIcon:SetPoint("TOPLEFT", 14, -9)
            hIcon:SetTexture("Interface\\AddOns\\MochaAlerts\\Media\\Textures\\coffeeAlert.png")

            -- Title
            local hTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            hTitle:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
            hTitle:SetText("|cffD4A96AMocha|r|cffEDD9A3Alerts|r")

            -- "Open Settings" button
            local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            openBtn:SetSize(160, 28)
            openBtn:SetPoint("TOPLEFT", 14, -70)
            openBtn:SetText("Open MochaAlerts")
            openBtn:SetScript("OnClick", function() MA:ToggleConfig() end)

            -- Version text
            local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            ver:SetPoint("LEFT", openBtn, "RIGHT", 12, 0)
            ver:SetTextColor(0.65, 0.52, 0.38)
            local versionStr = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "1.2.0"
            ver:SetText("v" .. versionStr)

            local category = Settings.RegisterCanvasLayoutCategory(panel, "MochaAlerts")
            category.ID = "MochaAlerts"
            Settings.RegisterAddOnCategory(category)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        if MA.initialized and MA.db then
            -- Rebuild override map on usability changes so form-entry re-snapshots
            -- happen before CheckCooldowns compares states.
            local overrideChanged = false
            if event == "SPELL_UPDATE_USABLE" then
                overrideChanged = MA:BuildOverrideMap()
            end
            -- Throttle the full spell check to avoid redundant loops on rapid events.
            -- Always bypass the throttle when an override changed (e.g. Void Meta exit)
            -- so CheckCooldowns runs immediately even if UNIT_AURA was throttled.
            local now = GetTime()
            if overrideChanged or (now - MA.lastSpellCheckTime) >= 0.05 then
                MA.lastSpellCheckTime = now
                pcall(MA.CheckCooldowns, MA)
            end
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        if MA.initialized and MA.db then
            pcall(MA.ReSyncItemCDFrames, MA)
            local now = GetTime()
            if (now - MA.lastItemCheckTime) >= 0.05 then
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
            if overrideChanged or (now - MA.lastSpellCheckTime) >= 0.05 then
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

    -- Prevent alerts after loading screens (instances, portals, login).
    -- ZONE_CHANGED and ZONE_CHANGED_NEW_AREA are NOT reset here because they
    -- fire constantly while flying between subzones/zones, causing false alerts
    -- (spells are briefly not-usable during flight → InitCooldownStates arms
    -- spellCastSeen → transition fires when API settles).
    elseif event == "PLAYER_ENTERING_WORLD" then
        if MA.initialized and MA.db then
            MA:InitCooldownStates()
            MA:InitItemStates()
            if MA.debugMode then
                print("|cff00ff00MochaAlerts DBG:|r State reset on", event)
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
                MA._cachedSelectedVoice = nil  -- invalidate so GetSelectedVoice picks up the change
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
                local liesFlag = MA.usableLiesDuringCD[spellID] and true or false
                local chargedMax = MA._chargedSpells[spellID]
                local chargeCt = MA.chargeCount[spellID]
                local chargeStr = chargedMax and (" charges=" .. tostring(chargeCt) .. "/" .. tostring(chargedMax)) or ""
                print("  " .. name .. " [" .. spellID .. "] known=" .. tostring(known) .. " usable=" .. tostring(usable) .. " onCD=" .. tostring(onCD) .. " state=" .. tostring(usState) .. " cdGate=" .. tostring(liesFlag) .. chargeStr)
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
