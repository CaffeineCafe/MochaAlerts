local addonName, MA = ...

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
local FRAME_W   = 540
local FRAME_H   = 720
local ROW_H     = 36
local ROW_H_TTS = 60   -- taller when TTS selected (room for text override)
local ROW_H_BOTH = 84  -- both TTS voice box and screen-text override box visible
local PAD       = 16

-------------------------------------------------------------------------------
-- Helpers (template-free)
-------------------------------------------------------------------------------
local function MakeButton(parent, width, height, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.18, 0.18, 0.18, 0.95)
    btn.bg = bg

    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.38, 0.34, 0.28, 1)
    btn.border = border

    -- re-layer so bg is on top of border
    bg:SetDrawLayer("BACKGROUND", 1)
    border:SetDrawLayer("BACKGROUND", 0)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label or "")
    text:SetTextColor(0.92, 0.78, 0.58, 1)
    btn.label = text

    btn:SetScript("OnEnter", function() bg:SetColorTexture(0.30, 0.29, 0.26, 1) end)
    btn:SetScript("OnLeave", function() bg:SetColorTexture(0.18, 0.18, 0.18, 0.95) end)

    function btn:SetText(t) text:SetText(t) end
    function btn:GetText() return text:GetText() end

    return btn
end

local function MakeCheckbox(parent, x, y, label, initial, onChange)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(200, 22)
    frame:SetPoint("TOPLEFT", x, y)

    local box = frame:CreateTexture(nil, "ARTWORK")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 0, 0)
    box:SetColorTexture(0.14, 0.14, 0.14, 1)

    local boxBorder = frame:CreateTexture(nil, "BORDER")
    boxBorder:SetSize(20, 20)
    boxBorder:SetPoint("CENTER", box, "CENTER")
    boxBorder:SetColorTexture(0.40, 0.36, 0.30, 1)
    box:SetDrawLayer("ARTWORK", 1)

    local check = frame:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("CENTER", box, "CENTER")
    check:SetColorTexture(0.92, 0.68, 0.22, 1)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    text:SetText(label)

    local checked = initial
    check:SetShown(checked)

    frame:SetScript("OnClick", function()
        checked = not checked
        check:SetShown(checked)
        onChange(checked)
    end)

    return frame
end

-------------------------------------------------------------------------------
-- Config Frame
-------------------------------------------------------------------------------
function MA:ToggleConfig()
    if not self.configFrame then
        self:CreateConfigFrame()
    end
    if self.configFrame:IsShown() then
        self.configFrame:Hide()
    else
        self:RefreshConfig()
        self.configFrame:Show()
    end
end

function MA:ShowURLPopup(url)
    if not self.urlPopup then
        local p = CreateFrame("Frame", "MochaAlertsURLPopup", UIParent)
        p:SetSize(360, 110)
        p:SetFrameStrata("TOOLTIP")
        p:SetClampedToScreen(true)

        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.09, 0.09, 0.09, 0.98)

        local bT = p:CreateTexture(nil,"BORDER"); bT:SetColorTexture(0.38,0.34,0.28,1); bT:SetHeight(1); bT:SetPoint("TOPLEFT"); bT:SetPoint("TOPRIGHT")
        local bB = p:CreateTexture(nil,"BORDER"); bB:SetColorTexture(0.38,0.34,0.28,1); bB:SetHeight(1); bB:SetPoint("BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT")
        local bL = p:CreateTexture(nil,"BORDER"); bL:SetColorTexture(0.38,0.34,0.28,1); bL:SetWidth(1); bL:SetPoint("TOPLEFT"); bL:SetPoint("BOTTOMLEFT")
        local bR = p:CreateTexture(nil,"BORDER"); bR:SetColorTexture(0.38,0.34,0.28,1); bR:SetWidth(1); bR:SetPoint("TOPRIGHT"); bR:SetPoint("BOTTOMRIGHT")

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetTextColor(0.92, 0.68, 0.22)
        title:SetText("Copy Link")

        local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetTextColor(0.70, 0.62, 0.50)
        hint:SetText("Press Ctrl+C to copy")

        local eb = CreateFrame("EditBox", nil, p)
        eb:SetSize(320, 24)
        eb:SetPoint("TOP", hint, "BOTTOM", 0, -8)
        eb:SetAutoFocus(true)
        eb:SetFontObject("GameFontHighlight")
        eb:SetJustifyH("CENTER")
        eb:SetTextInsets(6, 6, 0, 0)
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(0.06, 0.06, 0.06, 1)
        local ebBord = eb:CreateTexture(nil, "BORDER")
        ebBord:SetPoint("TOPLEFT", -1, 1); ebBord:SetPoint("BOTTOMRIGHT", 1, -1)
        ebBord:SetColorTexture(0.42, 0.37, 0.30, 1)
        ebBg:SetDrawLayer("BACKGROUND", 1)
        ebBord:SetDrawLayer("BACKGROUND", 0)
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        eb:SetScript("OnEnterPressed", function() p:Hide() end)
        -- Re-select all text whenever the box gains focus so Ctrl+C works immediately
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnKeyDown", function(self, key)
            -- Block ALL keybinds while this popup is open.
            -- The editbox handles Ctrl+C internally; no propagation needed.
            self:SetPropagateKeyboardInput(false)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.05, function() p:Hide() end)
            end
        end)
        eb:SetScript("OnKeyUp", function(self)
            self:SetPropagateKeyboardInput(false)
        end)
        p.editBox = eb

        local closeBtn = MakeButton(p, 22, 22, "X")
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:SetScript("OnClick", function() p:Hide() end)

        p:SetScript("OnHide", function() eb:ClearFocus() end)
        self.urlPopup = p
    end

    self.urlPopup.editBox:SetText(url)
    self.urlPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    self.urlPopup:Show()
    self.urlPopup.editBox:SetFocus()
    self.urlPopup.editBox:HighlightText()
end

function MA:CreateConfigFrame()
    local f = CreateFrame("Frame", "MochaAlertsConfigFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Escape closes the config; all other keys propagate to C++ bindings.
    -- If an editbox has keyboard focus, let it handle all keys exclusively.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then
            self:SetPropagateKeyboardInput(true)
            return
        end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Background: dark espresso
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.09, 0.09, 0.09, 0.97)

    -- Outer border: warm grey
    local borderT = f:CreateTexture(nil, "BORDER"); borderT:SetColorTexture(0.38,0.34,0.28,1); borderT:SetHeight(2); borderT:SetPoint("TOPLEFT"); borderT:SetPoint("TOPRIGHT")
    local borderB = f:CreateTexture(nil, "BORDER"); borderB:SetColorTexture(0.38,0.34,0.28,1); borderB:SetHeight(2); borderB:SetPoint("BOTTOMLEFT"); borderB:SetPoint("BOTTOMRIGHT")
    local borderL = f:CreateTexture(nil, "BORDER"); borderL:SetColorTexture(0.38,0.34,0.28,1); borderL:SetWidth(2); borderL:SetPoint("TOPLEFT"); borderL:SetPoint("BOTTOMLEFT")
    local borderR = f:CreateTexture(nil, "BORDER"); borderR:SetColorTexture(0.38,0.34,0.28,1); borderR:SetWidth(2); borderR:SetPoint("TOPRIGHT"); borderR:SetPoint("BOTTOMRIGHT")

    -- Header strip background
    local headerBg = f:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 2, -2)
    headerBg:SetPoint("TOPRIGHT", -2, -2)
    headerBg:SetHeight(54)
    headerBg:SetColorTexture(0.14, 0.14, 0.13, 1.0)
    headerBg:SetDrawLayer("BACKGROUND", 1)

    -- Header separator line
    local headerSep = f:CreateTexture(nil, "BORDER")
    headerSep:SetPoint("TOPLEFT", 2, -56)
    headerSep:SetPoint("TOPRIGHT", -2, -56)
    headerSep:SetHeight(1)
    headerSep:SetColorTexture(0.42, 0.37, 0.30, 0.9)

    -- Coffee icon in header
    local headerIcon = f:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(36, 36)
    headerIcon:SetPoint("TOPLEFT", 14, -9)
    headerIcon:SetTexture("Interface\\AddOns\\MochaAlerts\\Media\\Textures\\coffeeAlert.png")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", headerIcon, "RIGHT", 8, 0)
    title:SetText("|cffD4A96AMocha|r|cffEDD9A3Alerts|r")

    -- Close button
    local closeBtn = MakeButton(f, 24, 24, "X")
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- About button (sits left of the close button)
    local aboutBtn = MakeButton(f, 52, 24, "About")
    aboutBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)

    -- About panel (overlays the content area, hidden by default)
    local aboutPanel = CreateFrame("Frame", nil, f)
    aboutPanel:SetPoint("TOPLEFT", 2, -58)
    aboutPanel:SetPoint("BOTTOMRIGHT", -2, 2)
    aboutPanel:SetFrameLevel(f:GetFrameLevel() + 10)
    aboutPanel:EnableMouse(true)  -- block hover/clicks on underlying config widgets

    local apBg = aboutPanel:CreateTexture(nil, "BACKGROUND")
    apBg:SetAllPoints()
    apBg:SetColorTexture(0.09, 0.09, 0.09, 0.99)

    local apBorderT = aboutPanel:CreateTexture(nil,"BORDER"); apBorderT:SetColorTexture(0.38,0.34,0.28,1); apBorderT:SetHeight(1); apBorderT:SetPoint("TOPLEFT"); apBorderT:SetPoint("TOPRIGHT")
    local apBorderB = aboutPanel:CreateTexture(nil,"BORDER"); apBorderB:SetColorTexture(0.38,0.34,0.28,1); apBorderB:SetHeight(1); apBorderB:SetPoint("BOTTOMLEFT"); apBorderB:SetPoint("BOTTOMRIGHT")
    local apBorderL = aboutPanel:CreateTexture(nil,"BORDER"); apBorderL:SetColorTexture(0.38,0.34,0.28,1); apBorderL:SetWidth(1); apBorderL:SetPoint("TOPLEFT"); apBorderL:SetPoint("BOTTOMLEFT")
    local apBorderR = aboutPanel:CreateTexture(nil,"BORDER"); apBorderR:SetColorTexture(0.38,0.34,0.28,1); apBorderR:SetWidth(1); apBorderR:SetPoint("TOPRIGHT"); apBorderR:SetPoint("BOTTOMRIGHT")

    -- Logo icon at the top
    local apIcon = aboutPanel:CreateTexture(nil, "ARTWORK")
    apIcon:SetSize(64, 64)
    apIcon:SetPoint("TOP", 0, -20)
    apIcon:SetTexture("Interface\\AddOns\\MochaAlerts\\Media\\Textures\\coffeeAlert.png")

    local apTitle = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    apTitle:SetPoint("TOP", apIcon, "BOTTOM", 0, -10)
    apTitle:SetText("|cffD4A96AMocha|r|cffEDD9A3Alerts|r")

    local apVersion = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apVersion:SetPoint("TOP", apTitle, "BOTTOM", 0, -4)
    apVersion:SetTextColor(0.65, 0.52, 0.38)
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "1.1.0"
    apVersion:SetText("Version " .. version)

    local apSep = aboutPanel:CreateTexture(nil, "ARTWORK")
    apSep:SetSize(FRAME_W - 80, 1)
    apSep:SetPoint("TOP", apVersion, "BOTTOM", 0, -14)
    apSep:SetColorTexture(0.38, 0.34, 0.28, 0.7)

    local apHowTitle = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apHowTitle:SetPoint("TOP", apSep, "BOTTOM", 0, -14)
    apHowTitle:SetTextColor(0.92, 0.68, 0.22)
    apHowTitle:SetText("Getting Started")

    local apDesc = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apDesc:SetPoint("TOP", apHowTitle, "BOTTOM", 0, -8)
    apDesc:SetWidth(FRAME_W - 80)
    apDesc:SetJustifyH("CENTER")
    apDesc:SetTextColor(0.88, 0.78, 0.62)
    apDesc:SetText("Plays voice alerts and sounds when your tracked\nspells and items come off cooldown and are ready to cast.\nNow with a configurable poll interval for faster alerts.")

    local apHow = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apHow:SetPoint("TOP", apDesc, "BOTTOM", 0, -8)
    apHow:SetWidth(FRAME_W - 80)
    apHow:SetJustifyH("CENTER")
    apHow:SetTextColor(0.80, 0.70, 0.55)
    apHow:SetText("Shift-click spells from your spellbook, or type a\nspell/item name in the Add box below the spell list.\nAdjust the |cffEDD9A3Poll interval|r slider for faster or slower polling.\nUse |cffEDD9A3/malerts|r in chat for slash commands.")

    local apBtnTitle = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apBtnTitle:SetPoint("TOP", apHow, "BOTTOM", 0, -18)
    apBtnTitle:SetTextColor(0.92, 0.68, 0.22)
    apBtnTitle:SetText("Spell Row Buttons")

    local apBtnGuide = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apBtnGuide:SetPoint("TOP", apBtnTitle, "BOTTOM", 0, -8)
    apBtnGuide:SetWidth(FRAME_W - 80)
    apBtnGuide:SetJustifyH("CENTER")
    apBtnGuide:SetTextColor(0.80, 0.70, 0.55)
    apBtnGuide:SetText(
        "|cffEDD9A3[sound dropdown]|r  Choose TTS, no audio, or a sound effect\n" ..
        "|cffEDD9A3[>]|r  Preview the configured alert\n" ..
        "|cffEDD9A3[icon]|r  Toggle the spell icon on the alert frame\n" ..
        "|cffEDD9A3[T]|r  Toggle the alert text label on/off\n" ..
        "|cffEDD9A3[x2]|r  Repeat the alert a second time after 1.5s\n" ..
        "|cffEDD9A3[Tt]|r  Set a custom on-screen text for this alert\n" ..
        "|cffEDD9A3[X]|r  Remove this spell or item from tracking"
    )

    local apAuthorSep = aboutPanel:CreateTexture(nil, "ARTWORK")
    apAuthorSep:SetSize(FRAME_W - 80, 1)
    apAuthorSep:SetPoint("TOP", apBtnGuide, "BOTTOM", 0, -18)
    apAuthorSep:SetColorTexture(0.38, 0.34, 0.28, 0.7)

    local apAuthorTitle = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apAuthorTitle:SetPoint("TOP", apAuthorSep, "BOTTOM", 0, -14)
    apAuthorTitle:SetTextColor(0.92, 0.68, 0.22)
    apAuthorTitle:SetText("About the Author")

    local apAuthor = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apAuthor:SetPoint("TOP", apAuthorTitle, "BOTTOM", 0, -8)
    apAuthor:SetWidth(FRAME_W - 80)
    apAuthor:SetJustifyH("CENTER")
    apAuthor:SetTextColor(0.88, 0.78, 0.62)
    apAuthor:SetText("Thanks for downloading my addon! If you are enjoying it,\nor have questions feel free to stop by my Twitch page:")

    local apTwitchBtn = CreateFrame("Button", nil, aboutPanel)
    apTwitchBtn:SetSize(200, 20)
    apTwitchBtn:SetPoint("TOP", apAuthor, "BOTTOM", 0, -6)

    local apTwitch = apTwitchBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apTwitch:SetAllPoints()
    apTwitch:SetJustifyH("CENTER")
    apTwitch:SetTextColor(0.60, 0.35, 0.90)
    apTwitch:SetText("twitch.tv/caffeinecafe")

    apTwitchBtn:SetScript("OnEnter", function(self)
        apTwitch:SetTextColor(0.75, 0.50, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to open copy dialog", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    apTwitchBtn:SetScript("OnLeave", function()
        apTwitch:SetTextColor(0.60, 0.35, 0.90)
        GameTooltip:Hide()
    end)
    apTwitchBtn:SetScript("OnClick", function()
        MA:ShowURLPopup("twitch.tv/caffeinecafe")
    end)

    local apFooter = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    apFooter:SetPoint("BOTTOM", 0, 20)
    apFooter:SetTextColor(0.45, 0.35, 0.25)
    apFooter:SetText("Click About again to go back  •  /malerts help for all commands")

    aboutPanel:Hide()

    aboutBtn:SetScript("OnClick", function()
        if aboutPanel:IsShown() then
            aboutPanel:Hide()
            aboutBtn.label:SetTextColor(0.92, 0.78, 0.58)
        else
            aboutPanel:Show()
            aboutBtn.label:SetTextColor(0.92, 0.68, 0.22)
        end
    end)

    -- Hide about panel when config closes
    f:HookScript("OnHide", function() aboutPanel:Hide(); aboutBtn.label:SetTextColor(0.92, 0.78, 0.58) end)

    local y = -66

    -- Checkboxes
    MakeCheckbox(f, PAD, y, "Enable alerts", MA.db.enabled, function(v) MA.db.enabled = v end)
    y = y - 24
    MakeCheckbox(f, PAD, y, "Alert during combat", MA.db.alertInCombat, function(v) MA.db.alertInCombat = v end)
    y = y - 24
    MakeCheckbox(f, PAD, y, "Suppress login message", MA.db.quietLogin, function(v) MA.db.quietLogin = v end)

    -- Poll interval (compact, right-aligned next to checkboxes)
    local pollLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pollLabel:SetPoint("TOPLEFT", 230, -76)
    pollLabel:SetTextColor(0.88, 0.78, 0.62)
    pollLabel:SetText("Poll interval:")
    local pollSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    pollSlider:SetPoint("TOPLEFT", 230, -90)
    pollSlider:SetWidth(150)
    pollSlider:SetHeight(12)
    pollSlider:SetScale(1.05)
    pollSlider.Low:SetText("")
    pollSlider.High:SetText("")
    pollSlider:SetMinMaxValues(0.01, 0.40)
    pollSlider:SetValueStep(0.01)
    pollSlider:SetObeyStepOnDrag(true)
    pollSlider:SetValue(MA.db.pollInterval or 0.25)
    local pollValueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pollValueLabel:SetPoint("LEFT", pollSlider, "RIGHT", 10, 0)
    pollValueLabel:SetScale(1.05)
    pollValueLabel:SetText(string.format("%.2fs", pollSlider:GetValue()))
    pollSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 100 + 0.5) / 100
        MA.db.pollInterval = val
        pollValueLabel:SetText(string.format("%.2fs", val))
    end)
    local pollLowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local pollHighLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pollLowLabel:SetScale(1.0)
    pollHighLabel:SetScale(1.0)
    pollLowLabel:SetText("0.01")
    pollHighLabel:SetText("0.40")
    pollLowLabel:SetPoint("TOPLEFT", pollSlider, "BOTTOMLEFT", 0, -1)
    pollHighLabel:SetPoint("TOPRIGHT", pollSlider, "BOTTOMRIGHT", 0, -1)

    y = y - 36

    -- Unlock / Lock & Reset buttons (now above alert scale)
    local unlockBtn = MakeButton(f, 80, 22, "Unlock")
    unlockBtn:SetPoint("TOPLEFT", PAD, y)
    local alertUnlocked = false
    unlockBtn:SetScript("OnClick", function()
        alertUnlocked = not alertUnlocked
        MA:SetAlertUnlocked(alertUnlocked)
        unlockBtn:SetText(alertUnlocked and "Lock" or "Unlock")
    end)
    -- Lock alert when config closes
    f:HookScript("OnHide", function()
        if alertUnlocked then
            alertUnlocked = false
            MA:SetAlertUnlocked(false)
            unlockBtn:SetText("Unlock")
        end
    end)

    local resetBtn = MakeButton(f, 54, 22, "Reset")
    resetBtn:SetPoint("LEFT", unlockBtn, "RIGHT", 4, 0)
    resetBtn:SetScript("OnClick", function()
        MA:ResetAlertPosition()
        if slider then slider:SetValue(100) end
    end)
    y = y - 36

    -- Alert scale label and slider (side by side)
    y = y - 4
    local scaleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", PAD, y)
    scaleLabel:SetText("Alert scale:")
    local slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", scaleLabel, "RIGHT", 20, 0)
    slider:SetWidth((FRAME_W - PAD * 2 - 220 - 60))
    slider:SetHeight(16)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider:SetMinMaxValues(50, 200)
    slider:SetValueStep(10)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue((MA.db.alertScale or 1.0) * 100)
    -- Value label at the end of the slider
    local valueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueLabel:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    valueLabel:SetText(string.format("%d%%", slider:GetValue()))
    slider:SetScript("OnValueChanged", function(self, val)
        local scale = val / 100
        MA:UpdateAlertScale(scale)
        valueLabel:SetText(string.format("%d%%", val))
    end)
    -- Place 50% and 200% labels under the slider, moved up by 2px
    local lowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local highLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lowLabel:SetText("50%")
    highLabel:SetText("200%")
    lowLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    highLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    y = y - 56 -- increase vertical spacing before TTS Voice section

    -- TTS Voice selector
    local voiceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voiceLabel:SetPoint("TOPLEFT", PAD, y)
    voiceLabel:SetText("TTS Voice:")

    local voiceBtn = MakeButton(f, 320, 22, "")
    voiceBtn:SetPoint("LEFT", voiceLabel, "RIGHT", 8, 0)
    local function UpdateVoiceBtnText()
        local voice = MA:GetSelectedVoice()
        voiceBtn:SetText(voice and (voice.name or "Voice " .. (MA.db.ttsVoice or 0)) or "No voices")
    end
    UpdateVoiceBtnText()
    voiceBtn:SetScript("OnClick", function(btn)
        local voices = MA:GetTTSVoices()
        if not voices then return end
        -- Simple cycling through voices
        MA.db.ttsVoice = ((MA.db.ttsVoice or 0) + 1) % #voices
        MA._cachedSelectedVoice = nil  -- invalidate cached voice object
        UpdateVoiceBtnText()
        -- Preview
        MA:TryTTS("Voice selected")
    end)
    y = y - 32

    -- Alert Font selector (FontMagic fonts)
    local fontLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", PAD, y)
    fontLabel:SetText("Alert Font:")

    local fontBtn = MakeButton(f, 320, 22, "")
    fontBtn:SetPoint("LEFT", fontLabel, "RIGHT", 8, 0)
    local function UpdateFontBtnText()
        local currentPath = MA:GetAlertFontPath()
        if currentPath == MA.DEFAULT_FONT then
            fontBtn:SetText("Default (Friz Quadrata)")
        else
            -- find the matching name in FontLib
            local found = false
            for _, entry in ipairs(MA.FontLib) do
                if entry.path == currentPath then
                    fontBtn:SetText(entry.name)
                    found = true
                    break
                end
            end
            if not found then fontBtn:SetText("Custom") end
        end
    end
    UpdateFontBtnText()
    fontBtn:SetScript("OnClick", function(btn) MA:ShowFontDropdown(btn) end)
    MA._fontBtnUpdate = UpdateFontBtnText

    -- Alert Color picker (inline next to font button)
    local colorSwatch = CreateFrame("Button", nil, f)
    colorSwatch:SetSize(22, 22)
    colorSwatch:SetPoint("LEFT", fontBtn, "RIGHT", 8, 0)

    local swatchBg = colorSwatch:CreateTexture(nil, "BACKGROUND")
    swatchBg:SetAllPoints()
    swatchBg:SetColorTexture(0, 0, 0, 1)

    local swatchTex = colorSwatch:CreateTexture(nil, "OVERLAY")
    swatchTex:SetPoint("TOPLEFT", 1, -1)
    swatchTex:SetPoint("BOTTOMRIGHT", -1, 1)
    local sr, sg, sb = MA:GetAlertColor()
    swatchTex:SetColorTexture(sr, sg, sb, 1)

    local swatchBorderT = colorSwatch:CreateTexture(nil,"BORDER"); swatchBorderT:SetColorTexture(0.36,0.33,0.28,1); swatchBorderT:SetHeight(1); swatchBorderT:SetPoint("TOPLEFT",-1,1); swatchBorderT:SetPoint("TOPRIGHT",1,1)
    local swatchBorderB = colorSwatch:CreateTexture(nil,"BORDER"); swatchBorderB:SetColorTexture(0.36,0.33,0.28,1); swatchBorderB:SetHeight(1); swatchBorderB:SetPoint("BOTTOMLEFT",-1,-1); swatchBorderB:SetPoint("BOTTOMRIGHT",1,-1)
    local swatchBorderL = colorSwatch:CreateTexture(nil,"BORDER"); swatchBorderL:SetColorTexture(0.36,0.33,0.28,1); swatchBorderL:SetWidth(1); swatchBorderL:SetPoint("TOPLEFT",-1,1); swatchBorderL:SetPoint("BOTTOMLEFT",-1,-1)
    local swatchBorderR = colorSwatch:CreateTexture(nil,"BORDER"); swatchBorderR:SetColorTexture(0.36,0.33,0.28,1); swatchBorderR:SetWidth(1); swatchBorderR:SetPoint("TOPRIGHT",1,1); swatchBorderR:SetPoint("BOTTOMRIGHT",1,-1)

    colorSwatch:SetScript("OnClick", function()
        local cr, cg, cb = MA:GetAlertColor()
        local function OnColorChanged()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            MA:SetAlertColor(nr, ng, nb)
            swatchTex:SetColorTexture(nr, ng, nb, 1)
        end
        local function OnCancel(prev)
            local pr, pg, pb = prev.r, prev.g, prev.b
            MA:SetAlertColor(pr, pg, pb)
            swatchTex:SetColorTexture(pr, pg, pb, 1)
        end
        local info = {
            r = cr, g = cg, b = cb,
            swatchFunc = OnColorChanged,
            cancelFunc = OnCancel,
            hasOpacity = false,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    y = y - 32

    -- Test button
    local testBtn = MakeButton(f, 100, 24, "Test Alert")
    testBtn:SetPoint("TOPLEFT", PAD, y)
    testBtn:SetScript("OnClick", function() MA:Speak("Spell ready") end)
    y = y - 34

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", PAD, y)
    sep:SetSize(FRAME_W - PAD*2, 1)
    sep:SetColorTexture(0.38, 0.34, 0.28, 0.6)
    y = y - 10

    -- Add spell / item
    local addLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", PAD, y)
    addLabel:SetText("Add spell or item (name, ID, or Shift-Click):")
    y = y - 20

    local editBox = CreateFrame("EditBox", nil, f)
    editBox:SetPoint("TOPLEFT", PAD, y)
    editBox:SetSize(FRAME_W - PAD*2 - 70, 22)
    editBox:SetAutoFocus(false)
    editBox:SetPropagateKeyboardInput(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetTextInsets(4, 4, 0, 0)

    local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
    ebBg:SetAllPoints()
    ebBg:SetColorTexture(0.06, 0.06, 0.06, 0.7)
    local ebBorderT = editBox:CreateTexture(nil,"BORDER"); ebBorderT:SetColorTexture(0.36,0.33,0.28,1); ebBorderT:SetHeight(1); ebBorderT:SetPoint("TOPLEFT",-1,1); ebBorderT:SetPoint("TOPRIGHT",1,1)
    local ebBorderB = editBox:CreateTexture(nil,"BORDER"); ebBorderB:SetColorTexture(0.36,0.33,0.28,1); ebBorderB:SetHeight(1); ebBorderB:SetPoint("BOTTOMLEFT",-1,-1); ebBorderB:SetPoint("BOTTOMRIGHT",1,-1)
    local ebBorderL = editBox:CreateTexture(nil,"BORDER"); ebBorderL:SetColorTexture(0.36,0.33,0.28,1); ebBorderL:SetWidth(1); ebBorderL:SetPoint("TOPLEFT",-1,1); ebBorderL:SetPoint("BOTTOMLEFT",-1,-1)
    local ebBorderR = editBox:CreateTexture(nil,"BORDER"); ebBorderR:SetColorTexture(0.36,0.33,0.28,1); ebBorderR:SetWidth(1); ebBorderR:SetPoint("TOPRIGHT",1,1); ebBorderR:SetPoint("BOTTOMRIGHT",1,-1)

    MA.spellEditBox = editBox

    local addBtn = MakeButton(f, 60, 22, "Add")
    addBtn:SetPoint("LEFT", editBox, "RIGHT", 6, 0)

    -- WoW 12.x spellbook shift-click calls ChatFrameUtil.InsertLink(spellLink),
    -- NOT the old ChatEdit_InsertLink. Hook ChatFrameUtil.InsertLink to capture
    -- spell links when the config frame is open.
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if MA.debugMode then print("|cff00ff00MochaAlerts DBG:|r ChatFrameUtil.InsertLink fired: " .. tostring(text)) end
            if type(text) ~= "string" then return end
            if not text:match("|Hspell:") then return end
            if not (MA.configFrame and MA.configFrame:IsVisible()) then return end
            MA.spellEditBox:SetText(text)
            MA.spellEditBox:SetFocus()
        end)
    end

    -- Fallback: old ChatEdit_InsertLink path (pre-12.x or macros).
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(text)
            if type(text) ~= "string" then return end
            if not text:match("|Hspell:") then return end
            if not (MA.configFrame and MA.configFrame:IsVisible()) then return end
            MA.spellEditBox:SetText(text)
            MA.spellEditBox:SetFocus()
        end)
    end

    -- Items from bags go through HandleModifiedItemClick regardless of chat focus.
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(item)
            if type(item) ~= "string" then return end
            if not (MA.configFrame and MA.configFrame:IsVisible()) then return end
            MA.spellEditBox:SetText(item)
            MA.spellEditBox:SetFocus()
        end)
    end

    local function doAdd()
        local text = strtrim(editBox:GetText())
        if text ~= "" then
            if text:match("|Hitem:") then
                MA:AddItem(text)
            elseif not MA:AddSpell(text, true) then
                MA:AddItem(text)
            end
            editBox:SetText("")
        end
        editBox:ClearFocus()
    end
    addBtn:SetScript("OnClick", doAdd)
    editBox:SetScript("OnEnterPressed", doAdd)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    y = y - 28

    -- Scan trinkets button
    local scanBtn = MakeButton(f, 120, 22, "Scan Trinkets")
    scanBtn:SetPoint("TOPLEFT", PAD, y)
    scanBtn:SetScript("OnClick", function() MA:ScanTrinkets() end)
    y = y - 28

    -- Tracked spells & items header
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", PAD, y)
    hdr:SetText("Tracked Spells & Items:")
    y = y - 18

    -- Scroll area
    local scrollBg = CreateFrame("Frame", nil, f)
    scrollBg:SetPoint("TOPLEFT", PAD, y)
    scrollBg:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local sBg = scrollBg:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints()
    sBg:SetColorTexture(0.05, 0.05, 0.05, 0.6)

    local scrollFrame = CreateFrame("ScrollFrame", nil, scrollBg)
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(FRAME_W - PAD*2 - 12)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = math.max(0, scrollChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ROW_H * 2)))
    end)

    MA.spellListContainer = scrollChild
    MA.spellRows = {}

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", scrollBg, "CENTER")
    emptyText:SetText("No spells or items tracked.\nType /malerts add SpellName")
    MA.emptyText = emptyText

    self.configFrame = f
    f:Hide()
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
function MA:RefreshConfig()
    self:RefreshSpellList()
end

-------------------------------------------------------------------------------
-- Spell Row
-------------------------------------------------------------------------------
function MA:GetOrCreateRow(index)
    if self.spellRows[index] then return self.spellRows[index] end

    local container = self.spellListContainer
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(container:GetWidth() or (FRAME_W - PAD*2 - 12), ROW_H)
    row:SetPoint("TOPLEFT", 0, 0)  -- repositioned with correct offset in RefreshSpellList

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.55, 0.50, 0.42, 0.08)

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 4, -6)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    -- Name
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetJustifyH("LEFT")
    name:SetWidth(140)
    name:SetWordWrap(false)
    row.nameText = name

    -- Sound/TTS selector button (dropdown trigger)
    local soundBtn = CreateFrame("Button", nil, row)
    soundBtn:SetSize(110, 20)
    soundBtn:SetPoint("LEFT", name, "RIGHT", 4, 0)
    local sBg = soundBtn:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints()
    sBg:SetColorTexture(0.18, 0.17, 0.16, 1)
    local sBord = soundBtn:CreateTexture(nil, "BORDER")
    sBord:SetPoint("TOPLEFT", -1, 1)
    sBord:SetPoint("BOTTOMRIGHT", 1, -1)
    sBord:SetColorTexture(0.38, 0.34, 0.28, 1)
    sBg:SetDrawLayer("BACKGROUND", 1)
    sBord:SetDrawLayer("BACKGROUND", 0)

    local soundLabel = soundBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soundLabel:SetPoint("LEFT", 4, 0)
    soundLabel:SetPoint("RIGHT", -14, 0)
    soundLabel:SetJustifyH("LEFT")
    soundLabel:SetWordWrap(false)
    row.soundLabel = soundLabel

    local arrow = soundBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -2, 0)
    arrow:SetText("v")
    row.soundBtn = soundBtn

    -- Preview button
    local previewBtn = MakeButton(row, 20, 20, ">")
    previewBtn:SetPoint("LEFT", soundBtn, "RIGHT", 2, 0)
    row.previewBtn = previewBtn

    -- Icon toggle button (per-spell icon on/off)
    local iconBtn = MakeButton(row, 22, 22, "")
    iconBtn:SetPoint("LEFT", previewBtn, "RIGHT", 2, 0)
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Toggle spell icon on alert")
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local iconBtnIcon = iconBtn:CreateTexture(nil, "OVERLAY")
    iconBtnIcon:SetSize(16, 16)
    iconBtnIcon:SetPoint("CENTER")
    iconBtnIcon:SetTexture(134400)  -- placeholder, updated in refresh
    iconBtnIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconBtn = iconBtn
    row.iconBtnIcon = iconBtnIcon

    -- Text toggle button (per-spell text on/off)
    local textBtn = MakeButton(row, 22, 22, "T")
    textBtn:SetPoint("LEFT", iconBtn, "RIGHT", 2, 0)
    textBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Toggle alert text display")
        GameTooltip:Show()
    end)
    textBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.textBtn = textBtn

    -- Double-alert toggle button (x2 repeat after 1.5s)
    local x2Btn = MakeButton(row, 26, 22, "x2")
    x2Btn:SetPoint("LEFT", textBtn, "RIGHT", 2, 0)
    x2Btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Double alert: repeat the alert 1.5s after it fires")
        GameTooltip:Show()
    end)
    x2Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.x2Btn = x2Btn

    -- Custom screen-text button: toggles the on-screen text override edit box
    local customTextBtn = MakeButton(row, 28, 22, "Tt")
    customTextBtn:SetPoint("LEFT", x2Btn, "RIGHT", 2, 0)
    customTextBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Set custom on-screen alert text")
        GameTooltip:Show()
    end)
    customTextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.customTextBtn = customTextBtn

    -- Remove button
    local removeBtn = MakeButton(row, 22, 22, "X")
    removeBtn:SetPoint("TOPRIGHT", -4, -7)
    row.removeBtn = removeBtn

    -- TTS text override edit box (shown only when mode == "tts")
    local ttsEdit = CreateFrame("EditBox", nil, row)
    ttsEdit:SetSize(row:GetWidth() - 38, 18)
    ttsEdit:SetPoint("BOTTOMLEFT", 34, 2)
    ttsEdit:SetAutoFocus(false)
    ttsEdit:SetPropagateKeyboardInput(false)
    ttsEdit:SetFontObject("GameFontHighlightSmall")
    ttsEdit:SetTextInsets(4, 4, 0, 0)
    ttsEdit:SetMaxLetters(100)

    local teBg = ttsEdit:CreateTexture(nil, "BACKGROUND")
    teBg:SetAllPoints()
    teBg:SetColorTexture(0.06, 0.06, 0.06, 0.6)
    local teBord = ttsEdit:CreateTexture(nil, "BORDER")
    teBord:SetPoint("TOPLEFT", -1, 1)
    teBord:SetPoint("BOTTOMRIGHT", 1, -1)
    teBord:SetColorTexture(0.36, 0.33, 0.28, 1)
    teBg:SetDrawLayer("BACKGROUND", 1)
    teBord:SetDrawLayer("BACKGROUND", 0)

    ttsEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ttsEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.ttsEdit = ttsEdit
    ttsEdit:Hide()

    -- On-screen display text override edit box (shown when custom text button is toggled)
    local displayEdit = CreateFrame("EditBox", nil, row)
    displayEdit:SetSize(row:GetWidth() - 38, 18)
    displayEdit:SetPoint("BOTTOMLEFT", 34, 2)
    displayEdit:SetAutoFocus(false)
    displayEdit:SetPropagateKeyboardInput(false)
    displayEdit:SetFontObject("GameFontHighlightSmall")
    displayEdit:SetTextInsets(4, 4, 0, 0)
    displayEdit:SetMaxLetters(100)

    local deBg = displayEdit:CreateTexture(nil, "BACKGROUND")
    deBg:SetAllPoints()
    deBg:SetColorTexture(0.06, 0.06, 0.06, 0.6)
    local deBord = displayEdit:CreateTexture(nil, "BORDER")
    deBord:SetPoint("TOPLEFT", -1, 1)
    deBord:SetPoint("BOTTOMRIGHT", 1, -1)
    deBord:SetColorTexture(0.30, 0.45, 0.30, 1)  -- green tint to distinguish from TTS box
    deBg:SetDrawLayer("BACKGROUND", 1)
    deBord:SetDrawLayer("BACKGROUND", 0)

    displayEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    displayEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.displayEdit = displayEdit
    displayEdit:Hide()

    self.spellRows[index] = row
    return row
end

-------------------------------------------------------------------------------
-- Spell List
-------------------------------------------------------------------------------
function MA:RefreshSpellList()
    if not self.spellListContainer then return end

    for _, row in ipairs(self.spellRows) do row:Hide() end

    local sorted = {}
    for spellID in pairs(self.charDb.trackedSpells) do
        local name = C_Spell.GetSpellName(spellID) or "Unknown"
        tinsert(sorted, { id = spellID, name = name, isItem = false })
    end
    if self.charDb and self.charDb.trackedItems then
        for itemID in pairs(self.charDb.trackedItems) do
            local data = self.charDb.trackedItems[itemID]
            local isHPG = type(data) == "table" and data.isHealthPotGroup == true
            local isPG  = type(data) == "table" and data.isPotionGroup == true
            local name
            if isHPG then
                name = "Health Potion"
            elseif isPG then
                name = data.displayName or "Potion"
            else
                name = GetItemInfo(itemID) or "Unknown Item"
            end
            tinsert(sorted, { id = itemID, name = name, isItem = true, isHealthPotGroup = isHPG, isPotionGroup = isPG })
        end
    end
    table.sort(sorted, function(a, b)
        if a.isItem ~= b.isItem then return not a.isItem end  -- spells first
        return a.name < b.name
    end)

    for i, entry in ipairs(sorted) do
        local row = self:GetOrCreateRow(i)
        local sid = entry.id
        local isItem = entry.isItem

        local mode
        if isItem then
            mode = MA:GetItemMode(sid)
        else
            mode = MA:GetSpellMode(sid)
        end

        -- Determine display-text edit box visibility
        local rowKey = isItem and ("i" .. sid) or ("s" .. sid)
        local hasDisplayText = isItem and MA:GetItemDisplayText(sid) or MA:GetSpellDisplayText(sid)
        local showDisplayEdit = (MA._displayTextOpen[rowKey] == true) or (hasDisplayText ~= nil)

        -- Row height depends on how many extra edit boxes are visible
        local showTTSEdit = (mode == "tts")
        local rowH
        if showTTSEdit and showDisplayEdit then
            rowH = ROW_H_BOTH
        elseif showTTSEdit or showDisplayEdit then
            rowH = ROW_H_TTS
        else
            rowH = ROW_H
        end
        row:SetHeight(rowH)

        if isItem then
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(sid)
            row.icon:SetTexture(itemTexture or 134400)
            row.nameText:SetText("|cffEDD9A3" .. entry.name .. "|r")
            row.nameText:SetTextColor(1, 1, 1)
        else
            row.icon:SetTexture(C_Spell.GetSpellTexture(sid) or 134400)
            row.nameText:SetText(entry.name)
            row.nameText:SetTextColor(IsPlayerSpell(sid) and 1 or 0.5, IsPlayerSpell(sid) and 1 or 0.5, IsPlayerSpell(sid) and 1 or 0.5)
        end

        local displayName
        if mode == "tts" then
            displayName = "|cffEDD9A3TTS|r"
        elseif mode == "none" then
            displayName = "|cff888888None|r"
        else
            local currentKey = isItem and MA:GetItemSound(sid) or MA:GetSpellSound(sid)
            displayName = currentKey
            for _, sndEntry in ipairs(MA.SoundLib) do
                if sndEntry.key == currentKey then displayName = sndEntry.name; break end
            end
        end
        row.soundLabel:SetText(displayName)

        row.soundBtn:SetScript("OnClick", function(btn) MA:ShowSoundDropdown(btn, sid, isItem) end)
        row.previewBtn:SetScript("OnClick", function()
            MA._previewCount = (MA._previewCount or 0)
            if MA._previewCount >= 3 then return end
            MA._previewCount = MA._previewCount + 1
            local nm = isItem and MA:GetItemDisplayName(sid) or (C_Spell.GetSpellName(sid) or "Spell")
            local text = nm .. " ready"
            if isItem then
                MA:_SpeakItemRaw(text, sid)
            else
                MA:_SpeakRaw(text, sid)
            end
            C_Timer.After(2.0, function() MA._previewCount = math.max(0, (MA._previewCount or 1) - 1) end)
        end)
        row.removeBtn:SetScript("OnClick", function()
            if isItem then MA:RemoveItem(sid) else MA:RemoveSpell(sid) end
        end)

        -- Per-spell icon toggle
        local showIcon
        if isItem then showIcon = MA:GetItemShowIcon(sid) else showIcon = MA:GetSpellShowIcon(sid) end
        local iconTex = isItem and (select(10, GetItemInfo(sid)) or 134400) or (C_Spell.GetSpellTexture(sid) or 134400)
        row.iconBtnIcon:SetTexture(iconTex)
        row.iconBtnIcon:SetDesaturated(not showIcon)
        row.iconBtnIcon:SetAlpha(showIcon and 1.0 or 0.3)
        row.iconBtn:SetScript("OnClick", function()
            if isItem then
                MA:SetItemShowIcon(sid, not MA:GetItemShowIcon(sid))
            else
                MA:SetSpellShowIcon(sid, not MA:GetSpellShowIcon(sid))
            end
            MA:RefreshSpellList()
        end)

        -- Per-spell text toggle
        local showText
        if isItem then showText = MA:GetItemShowText(sid) else showText = MA:GetSpellShowText(sid) end
        if showText then
            row.textBtn.label:SetTextColor(1, 1, 1)
        else
            row.textBtn.label:SetTextColor(0.3, 0.3, 0.3)
        end
        row.textBtn:SetScript("OnClick", function()
            if isItem then
                MA:SetItemShowText(sid, not MA:GetItemShowText(sid))
            else
                MA:SetSpellShowText(sid, not MA:GetSpellShowText(sid))
            end
            MA:RefreshSpellList()
        end)

        -- Per-spell double-alert (x2) toggle
        local doubleAlert
        if isItem then doubleAlert = MA:GetItemDoubleAlert(sid) else doubleAlert = MA:GetSpellDoubleAlert(sid) end
        if doubleAlert then
            row.x2Btn.label:SetTextColor(0.92, 0.68, 0.22)  -- amber when active
        else
            row.x2Btn.label:SetTextColor(0.3, 0.3, 0.3)  -- dim when off
        end
        row.x2Btn:SetScript("OnClick", function()
            if isItem then
                MA:SetItemDoubleAlert(sid, not MA:GetItemDoubleAlert(sid))
            else
                MA:SetSpellDoubleAlert(sid, not MA:GetSpellDoubleAlert(sid))
            end
            MA:RefreshSpellList()
        end)

        -- Custom screen-text toggle button
        if hasDisplayText then
            row.customTextBtn.label:SetTextColor(0.92, 0.68, 0.22)  -- amber when override is active
        else
            row.customTextBtn.label:SetTextColor(0.3, 0.3, 0.3)  -- dim when no override
        end
        row.customTextBtn:SetScript("OnClick", function()
            if showDisplayEdit then
                -- Collapse: clear saved override and hide box
                MA._displayTextOpen[rowKey] = false
                if isItem then MA:SetItemDisplayText(sid, "") else MA:SetSpellDisplayText(sid, "") end
            else
                MA._displayTextOpen[rowKey] = true
            end
            MA:RefreshSpellList()
        end)

        -- TTS text override (voice text)
        if showTTSEdit then
            -- Position: higher slot when display edit is also shown
            row.ttsEdit:ClearAllPoints()
            if showDisplayEdit then
                row.ttsEdit:SetPoint("BOTTOMLEFT", 34, 26)
            else
                row.ttsEdit:SetPoint("BOTTOMLEFT", 34, 2)
            end

            local custom = isItem and MA:GetItemTTSText(sid) or MA:GetSpellTTSText(sid)
            row.ttsEdit:SetText(custom or "")
            row.ttsEdit:SetScript("OnTextChanged", function(self, userInput)
                if userInput then
                    if isItem then
                        MA:SetItemTTSText(sid, strtrim(self:GetText()))
                    else
                        MA:SetSpellTTSText(sid, strtrim(self:GetText()))
                    end
                end
            end)
            -- Placeholder text
            if not row.ttsPlaceholder then
                local ph = row.ttsEdit:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                ph:SetPoint("LEFT", 5, 0)
                row.ttsPlaceholder = ph
            end
            row.ttsPlaceholder:SetText("TTS: " .. (entry.isHealthPotGroup and "Health Pot Ready" or (entry.name .. " ready")))
            row.ttsEdit:SetScript("OnEditFocusGained", function() row.ttsPlaceholder:Hide() end)
            row.ttsEdit:SetScript("OnEditFocusLost", function(self)
                if strtrim(self:GetText()) == "" then row.ttsPlaceholder:Show() end
            end)
            if (custom or "") == "" then row.ttsPlaceholder:Show() else row.ttsPlaceholder:Hide() end
            row.ttsEdit:Show()
        else
            row.ttsEdit:Hide()
            if row.ttsPlaceholder then row.ttsPlaceholder:Hide() end
        end

        -- On-screen display text override
        if showDisplayEdit then
            row.displayEdit:ClearAllPoints()
            row.displayEdit:SetPoint("BOTTOMLEFT", 34, 2)

            local customDisplay = isItem and MA:GetItemDisplayText(sid) or MA:GetSpellDisplayText(sid)
            row.displayEdit:SetText(customDisplay or "")
            row.displayEdit:SetScript("OnTextChanged", function(self, userInput)
                if userInput then
                    local t = strtrim(self:GetText())
                    if isItem then MA:SetItemDisplayText(sid, t) else MA:SetSpellDisplayText(sid, t) end
                    -- Update button color immediately
                    if t ~= "" then
                        row.customTextBtn.label:SetTextColor(0.92, 0.68, 0.22)
                    else
                        row.customTextBtn.label:SetTextColor(0.3, 0.3, 0.3)
                    end
                end
            end)
            -- Placeholder text
            if not row.displayPlaceholder then
                local ph = row.displayEdit:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                ph:SetPoint("LEFT", 5, 0)
                row.displayPlaceholder = ph
            end
            row.displayPlaceholder:SetText(entry.isHealthPotGroup and "Health Pot Ready" or (entry.name .. " ready"))
            row.displayEdit:SetScript("OnEditFocusGained", function() row.displayPlaceholder:Hide() end)
            row.displayEdit:SetScript("OnEditFocusLost", function(self)
                if strtrim(self:GetText()) == "" then row.displayPlaceholder:Show() end
            end)
            if (customDisplay or "") == "" then row.displayPlaceholder:Show() else row.displayPlaceholder:Hide() end
            row.displayEdit:Show()
        else
            row.displayEdit:Hide()
            if row.displayPlaceholder then row.displayPlaceholder:Hide() end
        end

        row:Show()
    end

    -- Position rows with variable heights
    local totalH = 0
    for i = 1, #sorted do
        local row = self.spellRows[i]
        if row and row:IsShown() then
            row:SetPoint("TOPLEFT", 0, -totalH)
            totalH = totalH + row:GetHeight()
        end
    end

    self.spellListContainer:SetHeight(math.max(1, totalH))
    if self.emptyText then self.emptyText:SetShown(#sorted == 0) end
end

-------------------------------------------------------------------------------
-- Sound / TTS Dropdown
-------------------------------------------------------------------------------
function MA:ShowSoundDropdown(anchor, id, isItem)
    if not self.soundDropdown then
        local ROW_H = 20
        local PAD = 4
        local WIDTH = 190
        local MAX_VIS = 400
        local CONTENT_W = WIDTH - 2 * PAD

        local dd = CreateFrame("Frame", nil, UIParent)
        dd:SetFrameStrata("TOOLTIP")
        dd:SetClampedToScreen(true)
        dd:EnableMouse(true)

        local ddBg = dd:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.10, 0.10, 0.10, 0.97)

        local ddBT = dd:CreateTexture(nil,"BORDER"); ddBT:SetColorTexture(0.38,0.34,0.28,1); ddBT:SetHeight(1); ddBT:SetPoint("TOPLEFT"); ddBT:SetPoint("TOPRIGHT")
        local ddBB = dd:CreateTexture(nil,"BORDER"); ddBB:SetColorTexture(0.38,0.34,0.28,1); ddBB:SetHeight(1); ddBB:SetPoint("BOTTOMLEFT"); ddBB:SetPoint("BOTTOMRIGHT")
        local ddBL = dd:CreateTexture(nil,"BORDER"); ddBL:SetColorTexture(0.38,0.34,0.28,1); ddBL:SetWidth(1); ddBL:SetPoint("TOPLEFT"); ddBL:SetPoint("BOTTOMLEFT")
        local ddBR = dd:CreateTexture(nil,"BORDER"); ddBR:SetColorTexture(0.38,0.34,0.28,1); ddBR:SetWidth(1); ddBR:SetPoint("TOPRIGHT"); ddBR:SetPoint("BOTTOMRIGHT")

        -- Scroll frame for long sound list
        local scroll = CreateFrame("ScrollFrame", nil, dd)
        scroll:SetPoint("TOPLEFT", PAD, -PAD)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local mx = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(cur - delta * 60, mx)))
        end)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(CONTENT_W)
        scroll:SetScrollChild(content)

        dd:Hide()
        dd.buttons = {}

        -- First entry: TTS
        local ttsBtn = CreateFrame("Button", nil, content)
        ttsBtn:SetSize(CONTENT_W, ROW_H)
        ttsBtn:SetPoint("TOPLEFT", 0, 0)

        local ttsHl = ttsBtn:CreateTexture(nil, "HIGHLIGHT")
        ttsHl:SetAllPoints()
        ttsHl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

        local ttsLabel = ttsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ttsLabel:SetPoint("LEFT", 4, 0)
        ttsLabel:SetText("|cffEDD9A3TTS (Text-to-Speech)|r")
        ttsBtn.label = ttsLabel
        ttsBtn.isTTS = true
        dd.buttons[1] = ttsBtn

        -- Second entry: None (no audio)
        local noneBtn = CreateFrame("Button", nil, content)
        noneBtn:SetSize(CONTENT_W, ROW_H)
        noneBtn:SetPoint("TOPLEFT", 0, -ROW_H)

        local noneHl = noneBtn:CreateTexture(nil, "HIGHLIGHT")
        noneHl:SetAllPoints()
        noneHl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

        local noneLabel = noneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noneLabel:SetPoint("LEFT", 4, 0)
        noneLabel:SetText("None (visual only)")
        noneBtn.label = noneLabel
        noneBtn.isNone = true
        dd.buttons[2] = noneBtn

        -- Separator line
        local sepLine = content:CreateTexture(nil, "ARTWORK")
        sepLine:SetHeight(1)
        sepLine:SetPoint("TOPLEFT", 0, -(2 * ROW_H + 2))
        sepLine:SetPoint("TOPRIGHT", 0, -(2 * ROW_H + 2))
        sepLine:SetColorTexture(0.36, 0.33, 0.28, 0.6)

        local sepOfs = 2 * ROW_H + 5  -- space taken by TTS + None rows + separator
        local extraSepOfs = 0   -- extra offset for WA category separator

        -- Sound entries
        for i, entry in ipairs(MA.SoundLib) do
            -- Add separator before first WeakAuras sound
            if entry.file and extraSepOfs == 0 then
                local waSep = content:CreateTexture(nil, "ARTWORK")
                waSep:SetHeight(1)
                local waSepY = -(sepOfs + (i - 1) * ROW_H + extraSepOfs + 2)
                waSep:SetPoint("TOPLEFT", 0, waSepY)
                waSep:SetPoint("TOPRIGHT", 0, waSepY)
                waSep:SetColorTexture(0.36, 0.33, 0.28, 0.6)

                local waLabel = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                waLabel:SetPoint("TOPLEFT", 4, waSepY - 2)
                waLabel:SetText("|cff8B6F50WeakAuras Sounds|r")
                extraSepOfs = 18  -- separator + label height
            end

            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(CONTENT_W, ROW_H)
            btn:SetPoint("TOPLEFT", 0, -(sepOfs + (i - 1) * ROW_H + extraSepOfs))

            local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
            bhl:SetAllPoints()
            bhl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 4, 0)
            label:SetPoint("RIGHT", -22, 0)
            label:SetJustifyH("LEFT")
            label:SetText(entry.name)
            btn.label = label

            local playBtn = CreateFrame("Button", nil, btn)
            playBtn:SetSize(16, 16)
            playBtn:SetPoint("RIGHT", -2, 0)
            local playBg = playBtn:CreateTexture(nil, "ARTWORK")
            playBg:SetAllPoints()
            playBg:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            local playTxt = playBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            playTxt:SetPoint("CENTER")
            playTxt:SetText(">")
            playBtn:SetScript("OnClick", function()
                MA:PlaySoundByKey(entry.key)
            end)

            btn.entry = entry
            btn.isTTS = false
            dd.buttons[i + 2] = btn
        end

        local contentHeight = sepOfs + #MA.SoundLib * ROW_H + extraSepOfs
        content:SetHeight(contentHeight)
        local visHeight = math.min(contentHeight + 2 * PAD, MAX_VIS)
        dd:SetSize(WIDTH, visHeight)

        self.soundDropdown = dd
    end

    local dd = self.soundDropdown
    local currentMode = isItem and MA:GetItemMode(id) or MA:GetSpellMode(id)
    local currentSound = isItem and MA:GetItemSound(id) or MA:GetSpellSound(id)

    -- Reset scroll to top
    local scroll = dd:GetChildren()
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end

    for _, btn in ipairs(dd.buttons) do
        if btn.isNone then
            btn:SetScript("OnClick", function()
                if isItem then MA:SetItemMode(id, "none") else MA:SetSpellMode(id, "none") end
                dd:Hide()
                MA:RefreshSpellList()
            end)
            if currentMode == "none" then
                btn.label:SetTextColor(0.92, 0.68, 0.22)
                btn.label:SetText("|cffD4A96ANone (visual only)|r")
            else
                btn.label:SetTextColor(0.88, 0.80, 0.68)
                btn.label:SetText("None (visual only)")
            end
        elseif btn.isTTS then
            btn:SetScript("OnClick", function()
                if isItem then MA:SetItemMode(id, "tts") else MA:SetSpellMode(id, "tts") end
                dd:Hide()
                MA:RefreshSpellList()
            end)
            if currentMode == "tts" then
                btn.label:SetTextColor(0.92, 0.68, 0.22)
                btn.label:SetText("|cffD4A96ATTS (Text-to-Speech)|r")
            else
                btn.label:SetTextColor(0.88, 0.80, 0.68)
                btn.label:SetText("TTS (Text-to-Speech)")
            end
        else
            btn:SetScript("OnClick", function()
                if isItem then
                    MA:SetItemSound(id, btn.entry.key)
                else
                    MA:SetSpellSound(id, btn.entry.key)
                end
                MA:PlaySoundByKey(btn.entry.key)
                dd:Hide()
                MA:RefreshSpellList()
            end)
            if currentMode == "sound" and btn.entry.key == currentSound then
                btn.label:SetTextColor(0.92, 0.68, 0.22)
            else
                btn.label:SetTextColor(0.88, 0.80, 0.68)
            end
        end
    end

    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    dd:Show()

    dd:SetScript("OnUpdate", function()
        if not dd:IsMouseOver() and not anchor:IsMouseOver() then
            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                dd:Hide()
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Font Dropdown (FontMagic fonts)
-------------------------------------------------------------------------------
function MA:ShowFontDropdown(anchor)
    if not self.fontDropdown then
        local ROW_H = 20
        local PAD = 4
        local WIDTH = 220
        local MAX_VIS = 420
        local CONTENT_W = WIDTH - 2 * PAD

        local dd = CreateFrame("Frame", nil, UIParent)
        dd:SetFrameStrata("TOOLTIP")
        dd:SetClampedToScreen(true)
        dd:EnableMouse(true)

        local ddBg = dd:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.10, 0.10, 0.10, 0.97)

        local ddBT = dd:CreateTexture(nil,"BORDER"); ddBT:SetColorTexture(0.38,0.34,0.28,1); ddBT:SetHeight(1); ddBT:SetPoint("TOPLEFT"); ddBT:SetPoint("TOPRIGHT")
        local ddBB = dd:CreateTexture(nil,"BORDER"); ddBB:SetColorTexture(0.38,0.34,0.28,1); ddBB:SetHeight(1); ddBB:SetPoint("BOTTOMLEFT"); ddBB:SetPoint("BOTTOMRIGHT")
        local ddBL = dd:CreateTexture(nil,"BORDER"); ddBL:SetColorTexture(0.38,0.34,0.28,1); ddBL:SetWidth(1); ddBL:SetPoint("TOPLEFT"); ddBL:SetPoint("BOTTOMLEFT")
        local ddBR = dd:CreateTexture(nil,"BORDER"); ddBR:SetColorTexture(0.38,0.34,0.28,1); ddBR:SetWidth(1); ddBR:SetPoint("TOPRIGHT"); ddBR:SetPoint("BOTTOMRIGHT")

        local scroll = CreateFrame("ScrollFrame", nil, dd)
        scroll:SetPoint("TOPLEFT", PAD, -PAD)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local mx = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(cur - delta * 60, mx)))
        end)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(CONTENT_W)
        scroll:SetScrollChild(content)

        dd:Hide()
        dd.buttons = {}
        dd.catLabels = {}

        -- "Default" entry
        local defBtn = CreateFrame("Button", nil, content)
        defBtn:SetSize(CONTENT_W, ROW_H)
        defBtn:SetPoint("TOPLEFT", 0, 0)
        local defHl = defBtn:CreateTexture(nil, "HIGHLIGHT")
        defHl:SetAllPoints()
        defHl:SetColorTexture(0.55, 0.50, 0.40, 0.25)
        local defLabel = defBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        defLabel:SetPoint("LEFT", 4, 0)
        defLabel:SetText("Default (Friz Quadrata)")
        defBtn.label = defLabel
        defBtn.fontPath = MA.DEFAULT_FONT
        dd.buttons[1] = defBtn

        local yOfs = ROW_H + 2  -- after default + small gap

        -- Build categorized font entries
        local lastCat = nil
        for idx, entry in ipairs(MA.FontLib) do
            -- Category header
            if entry.category ~= lastCat then
                lastCat = entry.category
                local catSep = content:CreateTexture(nil, "ARTWORK")
                catSep:SetHeight(1)
                catSep:SetPoint("TOPLEFT", 0, -yOfs)
                catSep:SetPoint("TOPRIGHT", 0, -yOfs)
                catSep:SetColorTexture(0.36, 0.33, 0.28, 0.6)
                yOfs = yOfs + 3

                local catLabel = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                catLabel:SetPoint("TOPLEFT", 4, -yOfs)
                catLabel:SetText("|cff8B6F50" .. entry.category .. "|r")
                yOfs = yOfs + 14
            end

            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(CONTENT_W, ROW_H)
            btn:SetPoint("TOPLEFT", 0, -yOfs)

            local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
            bhl:SetAllPoints()
            bhl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 4, 0)
            label:SetPoint("RIGHT", -4, 0)
            label:SetJustifyH("LEFT")
            label:SetText(entry.name)
            btn.label = label
            btn.fontPath = entry.path

            dd.buttons[#dd.buttons + 1] = btn
            yOfs = yOfs + ROW_H
        end

        content:SetHeight(yOfs)
        dd:SetSize(WIDTH, math.min(yOfs + 2 * PAD, MAX_VIS))

        self.fontDropdown = dd
    end

    local dd = self.fontDropdown
    local currentPath = self:GetAlertFontPath()

    -- Reset scroll
    local scroll = dd:GetChildren()
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end

    for _, btn in ipairs(dd.buttons) do
        btn:SetScript("OnClick", function()
            MA:SetAlertFont(btn.fontPath)
            dd:Hide()
            if MA._fontBtnUpdate then MA._fontBtnUpdate() end
        end)
        if btn.fontPath == currentPath then
            btn.label:SetTextColor(0.92, 0.68, 0.22)
        else
            btn.label:SetTextColor(0.88, 0.80, 0.68)
        end
    end

    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    dd:Show()

    dd:SetScript("OnUpdate", function()
        if not dd:IsMouseOver() and not anchor:IsMouseOver() then
            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                dd:Hide()
            end
        end
    end)
end
