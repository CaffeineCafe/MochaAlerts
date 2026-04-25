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
local SIDE_PANEL_W = 280  -- right-side customization panel width

-------------------------------------------------------------------------------
-- Helpers (template-free)
-------------------------------------------------------------------------------
local function MakeButton(parent, width, height, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")

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

local function MakeCheckbox(parent, x, y, label, initial, onChange, width, fontObj)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(width or 200, 22)
    frame:SetPoint("TOPLEFT", x, y)
    frame:RegisterForClicks("LeftButtonUp")

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

    local text = frame:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    text:SetText(label)

    local checked = initial
    check:SetShown(checked)

    frame:SetScript("OnClick", function()
        checked = not checked
        check:SetShown(checked)
        onChange(checked)
    end)

    function frame:SetChecked(value)
        checked = value and true or false
        check:SetShown(checked)
    end

    function frame:GetChecked()
        return checked
    end

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

function MA:ShowIconPicker(anchor, id, isItem)
    if not self.iconPicker then
        local p = CreateFrame("Frame", "MochaAlertsIconPicker", UIParent)
        p:SetSize(340, 270)
        p:SetFrameStrata("TOOLTIP")
        p:SetClampedToScreen(true)
        p:EnableMouse(true)

        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.09, 0.09, 0.09, 0.98)

        local bT = p:CreateTexture(nil,"BORDER"); bT:SetColorTexture(0.38,0.34,0.28,1); bT:SetHeight(1); bT:SetPoint("TOPLEFT"); bT:SetPoint("TOPRIGHT")
        local bB = p:CreateTexture(nil,"BORDER"); bB:SetColorTexture(0.38,0.34,0.28,1); bB:SetHeight(1); bB:SetPoint("BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT")
        local bL = p:CreateTexture(nil,"BORDER"); bL:SetColorTexture(0.38,0.34,0.28,1); bL:SetWidth(1); bL:SetPoint("TOPLEFT"); bL:SetPoint("BOTTOMLEFT")
        local bR = p:CreateTexture(nil,"BORDER"); bR:SetColorTexture(0.38,0.34,0.28,1); bR:SetWidth(1); bR:SetPoint("TOPRIGHT"); bR:SetPoint("BOTTOMRIGHT")

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Custom Icon")

        local preview = p:CreateTexture(nil, "ARTWORK")
        preview:SetSize(32, 32)
        preview:SetPoint("TOPLEFT", 12, -32)
        preview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        p.preview = preview

        local sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("LEFT", preview, "RIGHT", 10, 10)
        sub:SetText("Click an icon below to select")

        local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", preview, "RIGHT", 10, -10)
        hint:SetText("Includes tracked + macro icon pools")

        local search = CreateFrame("EditBox", nil, p)
        search:SetSize(186, 20)
        search:SetPoint("TOPRIGHT", -12, -48)
        search:SetAutoFocus(false)
        search:SetMaxLetters(24)
        search:SetFontObject("GameFontHighlightSmall")
        search:SetTextInsets(5, 5, 0, 0)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        local sBg = search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0.06, 0.06, 0.06, 1)
        local sBd = search:CreateTexture(nil, "BORDER")
        sBd:SetPoint("TOPLEFT", -1, 1)
        sBd:SetPoint("BOTTOMRIGHT", 1, -1)
        sBd:SetColorTexture(0.42, 0.37, 0.30, 1)
        search.bg = sBg
        search.bd = sBd
        p.searchBox = search

        local searchPh = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        searchPh:SetPoint("LEFT", 6, 0)
        searchPh:SetText("Filter (name or id)")
        p.searchPlaceholder = searchPh

        local grid = CreateFrame("Frame", nil, p)
        grid:SetPoint("TOPLEFT", 12, -74)
        grid:SetSize(316, 150)
        p.grid = grid

        p.iconButtons = {}
        local BTN = 32
        local GAP = 6
        local COLS = 8
        local MAX_BTNS = 32

        for i = 1, MAX_BTNS do
            local btn = CreateFrame("Button", nil, grid)
            btn:SetSize(BTN, BTN)
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)
            btn:SetPoint("TOPLEFT", col * (BTN + GAP), -(row * (BTN + GAP)))

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.12, 1)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", -2, 2)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            btn.iconTex = tex

            local border = btn:CreateTexture(nil, "BORDER")
            border:SetPoint("TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", 1, -1)
            border:SetColorTexture(0.38, 0.34, 0.28, 1)
            btn.border = border

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

            btn:SetScript("OnClick", function(self)
                if p.isItem then
                    MA:SetItemCustomIcon(p.targetID, self.iconValue)
                else
                    MA:SetSpellCustomIcon(p.targetID, self.iconValue)
                end
                p:Hide()
                MA:RefreshSpellList()
            end)

            p.iconButtons[i] = btn
        end

        local clearBtn = MakeButton(p, 60, 22, "Clear")
        clearBtn:SetPoint("BOTTOMLEFT", 12, 10)
        local prevBtn = MakeButton(p, 26, 22, "<")
        prevBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
        local pageLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pageLabel:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
        pageLabel:SetText("1 / 1")
        local nextBtn = MakeButton(p, 26, 22, ">")
        nextBtn:SetPoint("LEFT", pageLabel, "RIGHT", 8, 0)
        local cancelBtn = MakeButton(p, 60, 22, "Cancel")
        cancelBtn:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)

        p.clearBtn = clearBtn
        p.prevBtn = prevBtn
        p.nextBtn = nextBtn
        p.pageLabel = pageLabel
        p.cancelBtn = cancelBtn
        p.iconCandidates = {}
        p.filteredCandidates = {}
        p.iconPage = 1
        p.filterQuery = ""

        p.RebuildFilteredIcons = function()
            local q = strlower(strtrim(p.filterQuery or ""))
            wipe(p.filteredCandidates)
            if q == "" then
                for i = 1, #p.iconCandidates do
                    p.filteredCandidates[#p.filteredCandidates + 1] = p.iconCandidates[i]
                end
                return
            end

            for i = 1, #p.iconCandidates do
                local tex = p.iconCandidates[i]
                local idStr = tostring(tex)
                local nameStr = strlower(p.iconNames and p.iconNames[tex] or "")
                if strfind(strlower(idStr), q, 1, true) or (nameStr ~= "" and strfind(nameStr, q, 1, true)) then
                    p.filteredCandidates[#p.filteredCandidates + 1] = tex
                end
            end
        end

        p.RenderIconPage = function()
            local total = #p.filteredCandidates
            local perPage = #p.iconButtons
            local maxPage = math.max(1, math.ceil(total / perPage))
            if p.iconPage < 1 then p.iconPage = 1 end
            if p.iconPage > maxPage then p.iconPage = maxPage end

            local startIdx = (p.iconPage - 1) * perPage + 1
            for i, btn in ipairs(p.iconButtons) do
                local tex = p.filteredCandidates[startIdx + i - 1]
                if tex then
                    btn.iconValue = tex
                    btn.iconTex:SetTexture(tex)
                    if p.currentIcon and tex == p.currentIcon then
                        btn.border:SetColorTexture(0.92, 0.68, 0.22, 1)
                    else
                        btn.border:SetColorTexture(0.38, 0.34, 0.28, 1)
                    end
                    btn:Show()
                else
                    btn:Hide()
                end
            end

            p.pageLabel:SetText(tostring(p.iconPage) .. " / " .. tostring(maxPage))

            local prevColor = (p.iconPage > 1) and 0.92 or 0.45
            local nextColor = (p.iconPage < maxPage) and 0.92 or 0.45
            p.prevBtn.label:SetTextColor(prevColor, prevColor, prevColor)
            p.nextBtn.label:SetTextColor(nextColor, nextColor, nextColor)
        end

        clearBtn:SetScript("OnClick", function()
            if p.isItem then
                MA:SetItemCustomIcon(p.targetID, nil)
            else
                MA:SetSpellCustomIcon(p.targetID, nil)
            end
            p:Hide()
            MA:RefreshSpellList()
        end)

        prevBtn:SetScript("OnClick", function()
            p.iconPage = p.iconPage - 1
            p.RenderIconPage()
        end)

        nextBtn:SetScript("OnClick", function()
            p.iconPage = p.iconPage + 1
            p.RenderIconPage()
        end)

        cancelBtn:SetScript("OnClick", function() p:Hide() end)

        p:SetScript("OnMouseWheel", function(_, delta)
            if delta > 0 then
                p.iconPage = p.iconPage - 1
            else
                p.iconPage = p.iconPage + 1
            end
            p.RenderIconPage()
        end)
        p:EnableMouseWheel(true)

        search:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                p.filterQuery = self:GetText() or ""
                if p.searchPlaceholder then
                    if strtrim(self:GetText() or "") == "" then p.searchPlaceholder:Show() else p.searchPlaceholder:Hide() end
                end
                p.iconPage = 1
                p.RebuildFilteredIcons()
                p.RenderIconPage()
            end
        end)
        search:SetScript("OnEditFocusGained", function()
            if p.searchPlaceholder then p.searchPlaceholder:Hide() end
        end)
        search:SetScript("OnEditFocusLost", function(self)
            if p.searchPlaceholder and strtrim(self:GetText() or "") == "" then p.searchPlaceholder:Show() end
        end)
        self.iconPicker = p
    end

    local p = self.iconPicker
    p.targetID = id
    p.isItem = isItem and true or false

    local current = isItem and self:GetItemCustomIcon(id) or self:GetSpellCustomIcon(id)
    p.currentIcon = current
    local fallback = isItem and (C_Item.GetItemIconByID(id) or 134400) or (C_Spell.GetSpellTexture(id) or 134400)
    p.preview:SetTexture(current or fallback)

    local candidates, seen, iconNames = {}, {}, {}
    local function AddIcon(tex)
        if not tex or tex == 0 or seen[tex] then return end
        seen[tex] = true
        candidates[#candidates + 1] = tex
    end

    local function AddNamedIcon(tex, name)
        if not tex or tex == 0 then return end
        AddIcon(tex)
        if name and name ~= "" then
            iconNames[tex] = name
        end
    end

    AddIcon(current)
    AddIcon(fallback)
    AddIcon(134400) -- question mark
    AddIcon(136243) -- ability icon
    AddIcon(1322720) -- generic chest
    AddIcon(134414) -- gear icon

    for spellID in pairs(self.charDb.trackedSpells or {}) do
        local spName = C_Spell.GetSpellName(spellID)
        AddNamedIcon(self:GetSpellCustomIcon(spellID), spName)
        AddNamedIcon(C_Spell.GetSpellTexture(spellID), spName)
    end
    for itemID in pairs(self.charDb.trackedItems or {}) do
        local itName = GetItemInfo(itemID)
        AddNamedIcon(self:GetItemCustomIcon(itemID), itName)
        AddNamedIcon(C_Item.GetItemIconByID(itemID), itName)
    end

    -- Pull the game's macro icon pools so users can pick from a much larger set.
    local function AddMacroPool(fetchFn)
        if not fetchFn then return end
        local pool = {}
        local ok = pcall(fetchFn, pool)
        if ok and pool then
            for i = 1, #pool do
                AddIcon(pool[i])
            end
        end
    end
    AddMacroPool(GetLooseMacroIcons)
    AddMacroPool(GetLooseMacroItemIcons)
    AddMacroPool(GetMacroIcons)
    AddMacroPool(GetMacroItemIcons)

    p.iconCandidates = candidates
    p.iconNames = iconNames
    p.filterQuery = ""
    p.searchBox:SetText("")
    if p.searchPlaceholder then p.searchPlaceholder:Show() end
    p.RebuildFilteredIcons()
    p.iconPage = 1
    p.RenderIconPage()

    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    p:Show()
end

function MA:ShowIconPickerInPanel(id, isItem)
    local p = self.sidePanel
    if not p then return end

    local current = isItem and self:GetItemCustomIcon(id) or self:GetSpellCustomIcon(id)
    p.currentIcon = current
    local fallback = isItem and (C_Item.GetItemIconByID(id) or 134400) or (C_Spell.GetSpellTexture(id) or 134400)

    local candidates, seen, iconNames = {}, {}, {}
    local function AddIcon(tex)
        if not tex or tex == 0 or seen[tex] then return end
        seen[tex] = true
        candidates[#candidates + 1] = tex
    end

    local function AddNamedIcon(tex, name)
        if not tex or tex == 0 then return end
        AddIcon(tex)
        if name and name ~= "" then
            iconNames[tex] = name
        end
    end

    AddIcon(current)
    AddIcon(fallback)
    AddIcon(134400) -- question mark
    AddIcon(136243) -- ability icon
    AddIcon(1322720) -- generic chest
    AddIcon(134414) -- gear icon

    for spellID in pairs(self.charDb.trackedSpells or {}) do
        local spName = C_Spell.GetSpellName(spellID)
        AddNamedIcon(self:GetSpellCustomIcon(spellID), spName)
        AddNamedIcon(C_Spell.GetSpellTexture(spellID), spName)
    end
    for itemID in pairs(self.charDb.trackedItems or {}) do
        local itName = GetItemInfo(itemID)
        AddNamedIcon(self:GetItemCustomIcon(itemID), itName)
        AddNamedIcon(C_Item.GetItemIconByID(itemID), itName)
    end

    -- Pull the game's macro icon pools
    local function AddMacroPool(fetchFn)
        if not fetchFn then return end
        local pool = {}
        local ok = pcall(fetchFn, pool)
        if ok and pool then
            for i = 1, #pool do
                AddIcon(pool[i])
            end
        end
    end
    AddMacroPool(GetLooseMacroIcons)
    AddMacroPool(GetLooseMacroItemIcons)
    AddMacroPool(GetMacroIcons)
    AddMacroPool(GetMacroItemIcons)

    p.iconCandidates = candidates
    p.iconNames = iconNames
    p.filterQuery = ""
    p.searchBox:SetText("")
    p.RebuildFilteredIcons()
    p.iconPage = 1
    p.RenderIconPage()
end

function MA:CreateConfigFrame()
    local f = CreateFrame("Frame", "MochaAlertsConfigFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    local cfgPos = self.db and self.db.configPos
    if cfgPos then
        f:SetPoint(cfgPos[1], UIParent, cfgPos[2], cfgPos[3], cfgPos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        MA.db.configPos = { point, relPoint, x, y }
    end)

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
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "unknown"
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
    apDesc:SetText("Plays voice alerts and sounds when your tracked\nspells and items come off cooldown and are ready to cast.\nVersion 1.3.2 improves context filtering reliability\nand TTS stability on 12.0.5.")

    local apHow = aboutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    apHow:SetPoint("TOP", apDesc, "BOTTOM", 0, -8)
    apHow:SetWidth(FRAME_W - 80)
    apHow:SetJustifyH("CENTER")
    apHow:SetTextColor(0.80, 0.70, 0.55)
    apHow:SetText("Shift-click spells from your spellbook, or type a\nspell/item name in the Add box below the spell list.\nClick a tracked alert's icon to open the flyout panel,\nthen use |cffEDD9A3Switch To Unlinked|r and |cffEDD9A3Unlock & Drag|r\nfor separate screen-based icon and text placement.")

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
        "|cffEDD9A3[X]|r  Remove this spell or item from tracking\n\n" ..
        "|cffEDD9A3[click alert icon]|r  Open the v1.3.2 customization flyout\n" ..
        "|cffEDD9A3[Switch To Unlinked]|r  Separate icon and text placement\n" ..
        "|cffEDD9A3[Unlock & Drag]|r  Open dimmed screen placement mode"
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
        if voice then
            voiceBtn:SetText(voice.name or ("Voice " .. tostring((MA.db.ttsVoice or 0) + 1)))
        else
            voiceBtn:SetText("No TTS voices detected")
        end
    end
    UpdateVoiceBtnText()
    voiceBtn:SetScript("OnClick", function(btn)
        MA:ShowVoiceDropdown(btn)
    end)
    MA._voiceBtnUpdate = UpdateVoiceBtnText
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
    testBtn:SetScript("OnClick", function() MA:Speak("Spell ready", nil, 134400) end)
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

    -------------------------------------------------------------------------------
    -- Right-side customization panel (SEPARATE FLOATING FRAME - fly-out drawer)
    -------------------------------------------------------------------------------
    local sidePanel = CreateFrame("Frame", "MochaAlertsSidePanel", UIParent)
    sidePanel:SetSize(SIDE_PANEL_W, FRAME_H + 130)
    sidePanel:SetFrameStrata("DIALOG")
    sidePanel:SetToplevel(true)
    sidePanel:SetClampedToScreen(true)
    sidePanel:EnableMouse(true)
    
    local spBg = sidePanel:CreateTexture(nil, "BACKGROUND")
    spBg:SetAllPoints()
    spBg:SetColorTexture(0.12, 0.12, 0.11, 0.95)
    
    local spBorder = sidePanel:CreateTexture(nil, "BORDER")
    spBorder:SetPoint("TOPLEFT", -1, 1)
    spBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    spBorder:SetColorTexture(0.38, 0.34, 0.28, 1)
    spBg:SetDrawLayer("BACKGROUND", 1)
    spBorder:SetDrawLayer("BACKGROUND", 0)
    
    -- Title
    local spTitle = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spTitle:SetPoint("TOPLEFT", 8, -8)
    spTitle:SetTextColor(0.92, 0.68, 0.22)
    spTitle:SetText("Customize")
    
    -- Close button
    local spCloseBtn = MakeButton(sidePanel, 18, 18, "X")
    spCloseBtn:SetPoint("TOPRIGHT", -4, -4)
    spCloseBtn:SetScript("OnClick", function() 
        sidePanel:Hide()
    end)
    
    -- Separator line
    local spSep1 = sidePanel:CreateTexture(nil, "ARTWORK")
    spSep1:SetSize(SIDE_PANEL_W - 16, 1)
    spSep1:SetPoint("TOPLEFT", 8, -26)
    spSep1:SetColorTexture(0.38, 0.34, 0.28, 0.6)
    
    -- Item name display
    -- Icon + name header (matches tracked spell row style)
    local spItemIconFrame = sidePanel:CreateTexture(nil, "ARTWORK")
    spItemIconFrame:SetSize(26, 26)
    spItemIconFrame:SetPoint("TOPLEFT", 8, -28)
    spItemIconFrame:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    spItemIconFrame:SetTexture(134400)
    sidePanel.itemIcon = spItemIconFrame

    local spItemName = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spItemName:SetPoint("TOPLEFT", 40, -32)
    spItemName:SetJustifyH("LEFT")
    spItemName:SetWidth(SIDE_PANEL_W - 48)
    spItemName:SetWordWrap(false)
    spItemName:SetText("(No spell selected)")
    sidePanel.itemName = spItemName

    -- Fire In: content filter (directly below name)
    local spContextLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spContextLabel:SetPoint("TOPLEFT", 8, -58)
    spContextLabel:SetTextColor(0.92, 0.68, 0.22)
    spContextLabel:SetText("Fire In:")

    local function SetSidePanelContext(key, enabled)
        if not sidePanel.currentSpellID then return end
        if sidePanel.isItem then
            MA:SetItemContextEnabled(sidePanel.currentSpellID, key, enabled)
        else
            MA:SetSpellContextEnabled(sidePanel.currentSpellID, key, enabled)
        end
    end

    local spPvpCheck = MakeCheckbox(sidePanel, 8, -76, "PvP", false, function(v)
        SetSidePanelContext("pvp", v)
    end, 110, "GameFontHighlight")
    local spFiveManCheck = MakeCheckbox(sidePanel, 136, -76, "5-Man", false, function(v)
        SetSidePanelContext("fiveMan", v)
    end, 110, "GameFontHighlight")
    local spRaidCheck = MakeCheckbox(sidePanel, 8, -98, "Raid", false, function(v)
        SetSidePanelContext("raid", v)
    end, 110, "GameFontHighlight")
    local spMythicRaidCheck = MakeCheckbox(sidePanel, 136, -98, "Mythic Raid", false, function(v)
        SetSidePanelContext("mythicRaid", v)
    end, 130, "GameFontHighlight")

    sidePanel.contextLabel = spContextLabel
    sidePanel.contextChecks = {
        pvp = spPvpCheck,
        fiveMan = spFiveManCheck,
        raid = spRaidCheck,
        mythicRaid = spMythicRaidCheck,
    }

    -- Position Settings (below Fire In)
    local spLinkLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spLinkLabel:SetPoint("TOPLEFT", 8, -126)
    spLinkLabel:SetTextColor(0.88, 0.78, 0.62)
    spLinkLabel:SetText("Position Settings:")
    
    local spLinkStateLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spLinkStateLabel:SetPoint("TOPLEFT", 8, -146)
    spLinkStateLabel:SetTextColor(0.88, 0.78, 0.62)
    spLinkStateLabel:SetText("Current Mode:")

    local spLinkStateValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spLinkStateValue:SetPoint("LEFT", spLinkStateLabel, "RIGHT", 8, 0)
    spLinkStateValue:SetTextColor(0.92, 0.68, 0.22)
    spLinkStateValue:SetText("Linked")
    sidePanel.linkStateValue = spLinkStateValue

    local spLinkActionBtn = MakeButton(sidePanel, SIDE_PANEL_W - 16, 20, "Switch To Unlinked")
    spLinkActionBtn:SetPoint("TOPLEFT", 8, -164)
    spLinkActionBtn:SetFrameLevel(sidePanel:GetFrameLevel() + 20)
    spLinkActionBtn:SetScript("OnClick", function()
        if not sidePanel.currentSpellID then return end

        local isItem = sidePanel.isItem
        local linked = isItem and MA:GetItemIconTextLinked(sidePanel.currentSpellID) or MA:GetSpellIconTextLinked(sidePanel.currentSpellID)
        local newLinked = not linked

        if isItem then
            MA:SetItemIconTextLinked(sidePanel.currentSpellID, newLinked)
        else
            MA:SetSpellIconTextLinked(sidePanel.currentSpellID, newLinked)
        end

        sidePanel.RefreshControls()
    end)
    sidePanel.linkActionBtn = spLinkActionBtn
    
    -- Unlock button (only enabled when unlinked)
    local spUnlockBtn = MakeButton(sidePanel, 120, 18, "Unlock & Drag")
    spUnlockBtn:SetPoint("TOPLEFT", 8, -194)
    spUnlockBtn:SetFrameLevel(sidePanel:GetFrameLevel() + 20)
    spUnlockBtn:SetScript("OnClick", function()
        if sidePanel.currentSpellID then
            local ok, err = pcall(MA.ShowDragPreview, MA, sidePanel.currentSpellID, sidePanel.isItem)
            if not ok then
                print("|cffff0000MochaAlerts Error:|r " .. tostring(err))
            elseif MA.positioningModeFrame then
                MA.positioningModeFrame:SetAlpha(1)
                MA.positioningModeFrame:Show()
                MA.positioningModeFrame:Raise()
            end
        end
    end)
    sidePanel.unlockBtn = spUnlockBtn
    spUnlockBtn:Hide()  -- Hidden by default, shown in RefreshControls when unlinked
    
    -- Icon controls (shown when unlinked)
    local spIconLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spIconLabel:SetPoint("TOPLEFT", 8, -218)
    spIconLabel:SetTextColor(0.92, 0.68, 0.22)
    spIconLabel:SetText("Icon:")
    sidePanel.iconLabel = spIconLabel
    
    -- Icon offset X
    local spIconXLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconXLabel:SetPoint("TOPLEFT", 8, -236)
    spIconXLabel:SetTextColor(0.88, 0.78, 0.62)
    spIconXLabel:SetText("X Offset:")
    local spIconXValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconXValue:SetPoint("LEFT", spIconXLabel, "RIGHT", 50, 0)
    spIconXValue:SetTextColor(0.88, 0.78, 0.62)
    spIconXValue:SetText("0")
    sidePanel.iconXValue = spIconXValue
    
    local spIconXSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spIconXSlider:SetPoint("TOPLEFT", 8, -248)
    spIconXSlider:SetWidth(SIDE_PANEL_W - 24)
    spIconXSlider:SetHeight(10)
    spIconXSlider.Low:SetText("")
    spIconXSlider.High:SetText("")
    spIconXSlider:SetMinMaxValues(-2000, 2000)
    spIconXSlider:SetValueStep(1)
    spIconXSlider:SetObeyStepOnDrag(true)
    spIconXSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        spIconXValue:SetText(tostring(val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemIconOffsetX(sidePanel.currentSpellID, val)
            else
                MA:SetSpellIconOffsetX(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spIconXSlider:GetThumbTexture() then
        spIconXSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.iconXSlider = spIconXSlider
    
    -- Icon offset Y
    local spIconYLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconYLabel:SetPoint("TOPLEFT", 8, -272)
    spIconYLabel:SetTextColor(0.88, 0.78, 0.62)
    spIconYLabel:SetText("Y Offset:")
    local spIconYValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconYValue:SetPoint("LEFT", spIconYLabel, "RIGHT", 50, 0)
    spIconYValue:SetTextColor(0.88, 0.78, 0.62)
    spIconYValue:SetText("0")
    sidePanel.iconYValue = spIconYValue
    
    local spIconYSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spIconYSlider:SetPoint("TOPLEFT", 8, -284)
    spIconYSlider:SetWidth(SIDE_PANEL_W - 24)
    spIconYSlider:SetHeight(10)
    spIconYSlider.Low:SetText("")
    spIconYSlider.High:SetText("")
    spIconYSlider:SetMinMaxValues(-2000, 2000)
    spIconYSlider:SetValueStep(1)
    spIconYSlider:SetObeyStepOnDrag(true)
    spIconYSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        spIconYValue:SetText(tostring(val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemIconOffsetY(sidePanel.currentSpellID, val)
            else
                MA:SetSpellIconOffsetY(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spIconYSlider:GetThumbTexture() then
        spIconYSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.iconYSlider = spIconYSlider
    
    -- Icon scale
    local spIconScaleLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconScaleLabel:SetPoint("TOPLEFT", 8, -308)
    spIconScaleLabel:SetTextColor(0.88, 0.78, 0.62)
    spIconScaleLabel:SetText("Scale:")
    local spIconScaleValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spIconScaleValue:SetPoint("LEFT", spIconScaleLabel, "RIGHT", 50, 0)
    spIconScaleValue:SetTextColor(0.88, 0.78, 0.62)
    spIconScaleValue:SetText("1.0")
    sidePanel.iconScaleValue = spIconScaleValue
    
    local spIconScaleSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spIconScaleSlider:SetPoint("TOPLEFT", 8, -320)
    spIconScaleSlider:SetWidth(SIDE_PANEL_W - 24)
    spIconScaleSlider:SetHeight(10)
    spIconScaleSlider.Low:SetText("")
    spIconScaleSlider.High:SetText("")
    spIconScaleSlider:SetMinMaxValues(0.5, 2.0)
    spIconScaleSlider:SetValueStep(0.1)
    spIconScaleSlider:SetObeyStepOnDrag(true)
    spIconScaleSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 10) / 10
        spIconScaleValue:SetText(string.format("%.1f", val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemIconScale(sidePanel.currentSpellID, val)
            else
                MA:SetSpellIconScale(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spIconScaleSlider:GetThumbTexture() then
        spIconScaleSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.iconScaleSlider = spIconScaleSlider
    
    -- Separator
    local spSep2 = sidePanel:CreateTexture(nil, "ARTWORK")
    spSep2:SetSize(SIDE_PANEL_W - 16, 1)
    spSep2:SetPoint("TOPLEFT", 8, -338)
    spSep2:SetColorTexture(0.38, 0.34, 0.28, 0.4)
    
    -- Text controls
    local spTextLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spTextLabel:SetPoint("TOPLEFT", 8, -348)
    spTextLabel:SetTextColor(0.92, 0.68, 0.22)
    spTextLabel:SetText("Text:")
    sidePanel.textLabel = spTextLabel
    
    -- Text offset X
    local spTextXLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextXLabel:SetPoint("TOPLEFT", 8, -366)
    spTextXLabel:SetTextColor(0.88, 0.78, 0.62)
    spTextXLabel:SetText("X Offset:")
    local spTextXValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextXValue:SetPoint("LEFT", spTextXLabel, "RIGHT", 50, 0)
    spTextXValue:SetTextColor(0.88, 0.78, 0.62)
    spTextXValue:SetText("0")
    sidePanel.textXValue = spTextXValue
    
    local spTextXSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spTextXSlider:SetPoint("TOPLEFT", 8, -378)
    spTextXSlider:SetWidth(SIDE_PANEL_W - 24)
    spTextXSlider:SetHeight(10)
    spTextXSlider.Low:SetText("")
    spTextXSlider.High:SetText("")
    spTextXSlider:SetMinMaxValues(-2000, 2000)
    spTextXSlider:SetValueStep(1)
    spTextXSlider:SetObeyStepOnDrag(true)
    spTextXSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        spTextXValue:SetText(tostring(val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemTextOffsetX(sidePanel.currentSpellID, val)
            else
                MA:SetSpellTextOffsetX(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spTextXSlider:GetThumbTexture() then
        spTextXSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.textXSlider = spTextXSlider
    
    -- Text offset Y
    local spTextYLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextYLabel:SetPoint("TOPLEFT", 8, -402)
    spTextYLabel:SetTextColor(0.88, 0.78, 0.62)
    spTextYLabel:SetText("Y Offset:")
    local spTextYValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextYValue:SetPoint("LEFT", spTextYLabel, "RIGHT", 50, 0)
    spTextYValue:SetTextColor(0.88, 0.78, 0.62)
    spTextYValue:SetText("0")
    sidePanel.textYValue = spTextYValue
    
    local spTextYSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spTextYSlider:SetPoint("TOPLEFT", 8, -414)
    spTextYSlider:SetWidth(SIDE_PANEL_W - 24)
    spTextYSlider:SetHeight(10)
    spTextYSlider.Low:SetText("")
    spTextYSlider.High:SetText("")
    spTextYSlider:SetMinMaxValues(-2000, 2000)
    spTextYSlider:SetValueStep(1)
    spTextYSlider:SetObeyStepOnDrag(true)
    spTextYSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val)
        spTextYValue:SetText(tostring(val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemTextOffsetY(sidePanel.currentSpellID, val)
            else
                MA:SetSpellTextOffsetY(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spTextYSlider:GetThumbTexture() then
        spTextYSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.textYSlider = spTextYSlider
    
    -- Text scale
    local spTextScaleLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextScaleLabel:SetPoint("TOPLEFT", 8, -438)
    spTextScaleLabel:SetTextColor(0.88, 0.78, 0.62)
    spTextScaleLabel:SetText("Scale:")
    local spTextScaleValue = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spTextScaleValue:SetPoint("LEFT", spTextScaleLabel, "RIGHT", 50, 0)
    spTextScaleValue:SetTextColor(0.88, 0.78, 0.62)
    spTextScaleValue:SetText("1.0")
    sidePanel.textScaleValue = spTextScaleValue
    
    local spTextScaleSlider = CreateFrame("Slider", nil, sidePanel, "OptionsSliderTemplate")
    spTextScaleSlider:SetPoint("TOPLEFT", 8, -450)
    spTextScaleSlider:SetWidth(SIDE_PANEL_W - 24)
    spTextScaleSlider:SetHeight(10)
    spTextScaleSlider.Low:SetText("")
    spTextScaleSlider.High:SetText("")
    spTextScaleSlider:SetMinMaxValues(0.5, 2.0)
    spTextScaleSlider:SetValueStep(0.1)
    spTextScaleSlider:SetObeyStepOnDrag(true)
    spTextScaleSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 10) / 10
        spTextScaleValue:SetText(string.format("%.1f", val))
        if sidePanel.currentSpellID then
            if sidePanel.isItem then
                MA:SetItemTextScale(sidePanel.currentSpellID, val)
            else
                MA:SetSpellTextScale(sidePanel.currentSpellID, val)
            end
        end
    end)
    if spTextScaleSlider:GetThumbTexture() then
        spTextScaleSlider:GetThumbTexture():SetVertexColor(0.92, 0.68, 0.22)
    end
    sidePanel.textScaleSlider = spTextScaleSlider
    
    -- Separator
    local spSep3 = sidePanel:CreateTexture(nil, "ARTWORK")
    spSep3:SetSize(SIDE_PANEL_W - 16, 1)
    spSep3:SetPoint("TOPLEFT", 8, -468)
    spSep3:SetColorTexture(0.38, 0.34, 0.28, 0.4)
    
    -- Icon picker section
    local spPickerLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spPickerLabel:SetPoint("TOPLEFT", 8, -480)
    spPickerLabel:SetTextColor(0.92, 0.68, 0.22)
    spPickerLabel:SetText("Icon Picker:")
    sidePanel.pickerLabel = spPickerLabel
    
    -- Search box for icons
    local spSearch = CreateFrame("EditBox", nil, sidePanel)
    spSearch:SetSize(SIDE_PANEL_W - 20, 18)
    spSearch:SetPoint("TOPLEFT", 10, -498)
    spSearch:SetAutoFocus(false)
    spSearch:SetMaxLetters(24)
    spSearch:SetFontObject("GameFontHighlightSmall")
    spSearch:SetTextInsets(4, 4, 0, 0)
    local spSearchBg = spSearch:CreateTexture(nil, "BACKGROUND")
    spSearchBg:SetAllPoints()
    spSearchBg:SetColorTexture(0.06, 0.06, 0.06, 0.8)
    local spSearchBd = spSearch:CreateTexture(nil, "BORDER")
    spSearchBd:SetPoint("TOPLEFT", -1, 1)
    spSearchBd:SetPoint("BOTTOMRIGHT", 1, -1)
    spSearchBd:SetColorTexture(0.36, 0.33, 0.28, 1)
    spSearch.bg = spSearchBg
    spSearch.bd = spSearchBd
    spSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    spSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sidePanel.searchBox = spSearch
    
    -- Icon grid (expanded, 6 buttons across)
    local spGrid = CreateFrame("Frame", nil, sidePanel)
    spGrid:SetPoint("TOPLEFT", 10, -524)
    spGrid:SetSize(SIDE_PANEL_W - 20, 220)  -- More space for 6x6 grid
    sidePanel.grid = spGrid
    
    sidePanel.iconButtons = {}
    sidePanel.filteredCandidates = {}
    sidePanel.iconCandidates = {}
    sidePanel.iconPage = 1
    sidePanel.filterQuery = ""
    
    local BTN = 32  -- Bigger buttons
    local GAP = 6
    local COLS = 6  -- More columns
    local MAX_BTNS = 36  -- 6 rows x 6 cols for side panel
    
    for i = 1, MAX_BTNS do
        local btn = CreateFrame("Button", nil, spGrid)
        btn:SetSize(BTN, BTN)
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        btn:SetPoint("TOPLEFT", col * (BTN + GAP), -(row * (BTN + GAP)))
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 1)
        
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.iconTex = tex
        
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.38, 0.34, 0.28, 1)
        btn.border = border
        
        btn:SetScript("OnClick", function(self)
            if sidePanel.currentSpellID then
                if sidePanel.isItem then
                    MA:SetItemCustomIcon(sidePanel.currentSpellID, self.iconValue)
                else
                    MA:SetSpellCustomIcon(sidePanel.currentSpellID, self.iconValue)
                end
                MA:RefreshSpellList()
            end
        end)
        
        sidePanel.iconButtons[i] = btn
    end
    
    -- Pagination controls
    local spPrevBtn = MakeButton(sidePanel, 20, 18, "<")
    spPrevBtn:SetPoint("TOPLEFT", 10, -756)
    local spPageLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spPageLabel:SetPoint("LEFT", spPrevBtn, "RIGHT", 6, 0)
    spPageLabel:SetText("1/1")
    local spNextBtn = MakeButton(sidePanel, 20, 18, ">")
    spNextBtn:SetPoint("LEFT", spPageLabel, "RIGHT", 6, 0)
    
    sidePanel.prevBtn = spPrevBtn
    sidePanel.nextBtn = spNextBtn
    sidePanel.pageLabel = spPageLabel
    
    -- Icon picker functions
    function sidePanel.RebuildFilteredIcons()
        local q = strlower(strtrim(sidePanel.filterQuery or ""))
        wipe(sidePanel.filteredCandidates)
        if q == "" then
            for i = 1, #sidePanel.iconCandidates do
                sidePanel.filteredCandidates[#sidePanel.filteredCandidates + 1] = sidePanel.iconCandidates[i]
            end
            return
        end
        
        for i = 1, #sidePanel.iconCandidates do
            local tex = sidePanel.iconCandidates[i]
            local idStr = tostring(tex)
            local nameStr = strlower(sidePanel.iconNames and sidePanel.iconNames[tex] or "")
            if strfind(strlower(idStr), q, 1, true) or (nameStr ~= "" and strfind(nameStr, q, 1, true)) then
                sidePanel.filteredCandidates[#sidePanel.filteredCandidates + 1] = tex
            end
        end
    end
    
    function sidePanel.RenderIconPage()
        local total = #sidePanel.filteredCandidates
        local perPage = #sidePanel.iconButtons
        local maxPage = math.max(1, math.ceil(total / perPage))
        if sidePanel.iconPage < 1 then sidePanel.iconPage = 1 end
        if sidePanel.iconPage > maxPage then sidePanel.iconPage = maxPage end
        
        local startIdx = (sidePanel.iconPage - 1) * perPage + 1
        for i, btn in ipairs(sidePanel.iconButtons) do
            local tex = sidePanel.filteredCandidates[startIdx + i - 1]
            if tex then
                btn.iconValue = tex
                btn.iconTex:SetTexture(tex)
                if sidePanel.currentIcon and tex == sidePanel.currentIcon then
                    btn.border:SetColorTexture(0.92, 0.68, 0.22, 1)
                else
                    btn.border:SetColorTexture(0.38, 0.34, 0.28, 1)
                end
                btn:Show()
            else
                btn:Hide()
            end
        end
        
        spPageLabel:SetText(tostring(sidePanel.iconPage) .. " / " .. tostring(maxPage))
        
        local prevColor = (sidePanel.iconPage > 1) and 0.92 or 0.45
        local nextColor = (sidePanel.iconPage < maxPage) and 0.92 or 0.45
        spPrevBtn.label:SetTextColor(prevColor, prevColor, prevColor)
        spNextBtn.label:SetTextColor(nextColor, nextColor, nextColor)
    end
    
    spPrevBtn:SetScript("OnClick", function()
        sidePanel.iconPage = sidePanel.iconPage - 1
        sidePanel.RenderIconPage()
    end)
    
    spNextBtn:SetScript("OnClick", function()
        sidePanel.iconPage = sidePanel.iconPage + 1
        sidePanel.RenderIconPage()
    end)
    
    spSearch:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            sidePanel.filterQuery = self:GetText() or ""
            sidePanel.iconPage = 1
            sidePanel.RebuildFilteredIcons()
            sidePanel.RenderIconPage()
        end
    end)
    
    spGrid:EnableMouseWheel(true)
    spGrid:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then
            sidePanel.iconPage = sidePanel.iconPage - 1
        else
            sidePanel.iconPage = sidePanel.iconPage + 1
        end
        sidePanel.RenderIconPage()
    end)
    
    sidePanel.iconButtons_frame = spGrid  -- Reference for showing/hiding
    
    -- Help text
    local spHelpText = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spHelpText:SetPoint("TOPLEFT", 8, -778)
    spHelpText:SetWidth(SIDE_PANEL_W - 16)
    spHelpText:SetJustifyH("LEFT")
    spHelpText:SetWordWrap(true)
    spHelpText:SetTextColor(0.65, 0.52, 0.38)
    spHelpText:SetText("Use sliders to customize icon/text position and scale. Context filters are optional: if no boxes are checked, the alert still fires everywhere. Unlock & Drag lets you place them anywhere on screen, separate from the base alert anchor.")
    sidePanel.helpText = spHelpText


    -- Function to refresh controls
    function sidePanel.RefreshControls()
        local spellID = sidePanel.currentSpellID
        local isItem = sidePanel.isItem
        if not spellID then return end

        sidePanel.contextChecks.pvp:SetChecked(isItem and MA:GetItemContextEnabled(spellID, "pvp") or MA:GetSpellContextEnabled(spellID, "pvp"))
        sidePanel.contextChecks.fiveMan:SetChecked(isItem and MA:GetItemContextEnabled(spellID, "fiveMan") or MA:GetSpellContextEnabled(spellID, "fiveMan"))
        sidePanel.contextChecks.raid:SetChecked(isItem and MA:GetItemContextEnabled(spellID, "raid") or MA:GetSpellContextEnabled(spellID, "raid"))
        sidePanel.contextChecks.mythicRaid:SetChecked(isItem and MA:GetItemContextEnabled(spellID, "mythicRaid") or MA:GetSpellContextEnabled(spellID, "mythicRaid"))
        
        local linked = isItem and MA:GetItemIconTextLinked(spellID) or MA:GetSpellIconTextLinked(spellID)
        sidePanel.linkStateValue:SetText(linked and "Linked" or "Unlinked")
        sidePanel.linkActionBtn:SetText(linked and "Switch To Unlinked" or "Switch To Linked")
        
        -- Show unlock button only when unlinked (for spells only, not items for now)
        if linked or isItem then
            sidePanel.unlockBtn:Hide()
        else
            sidePanel.unlockBtn:Show()
        end
        
        -- Only show positioning controls when icon/text are unlinked.
        spIconLabel:SetShown(not linked)
        spIconXLabel:SetShown(not linked)
        spIconXValue:SetShown(not linked)
        spIconXSlider:SetShown(not linked)
        spIconYLabel:SetShown(not linked)
        spIconYValue:SetShown(not linked)
        spIconYSlider:SetShown(not linked)
        spIconScaleLabel:SetShown(not linked)
        spIconScaleValue:SetShown(not linked)
        spIconScaleSlider:SetShown(not linked)
        spSep2:SetShown(not linked)
        spTextLabel:SetShown(not linked)
        spTextXLabel:SetShown(not linked)
        spTextXValue:SetShown(not linked)
        spTextXSlider:SetShown(not linked)
        spTextYLabel:SetShown(not linked)
        spTextYValue:SetShown(not linked)
        spTextYSlider:SetShown(not linked)
        spTextScaleLabel:SetShown(not linked)
        spTextScaleValue:SetShown(not linked)
        spTextScaleSlider:SetShown(not linked)
        spSep3:SetShown(not linked)
        
        -- Update slider values
        local iconX = isItem and MA:GetItemIconOffsetX(spellID) or MA:GetSpellIconOffsetX(spellID)
        local iconY = isItem and MA:GetItemIconOffsetY(spellID) or MA:GetSpellIconOffsetY(spellID)
        local iconScale = isItem and MA:GetItemIconScale(spellID) or MA:GetSpellIconScale(spellID)
        local textX = isItem and MA:GetItemTextOffsetX(spellID) or MA:GetSpellTextOffsetX(spellID)
        local textY = isItem and MA:GetItemTextOffsetY(spellID) or MA:GetSpellTextOffsetY(spellID)
        local textScale = isItem and MA:GetItemTextScale(spellID) or MA:GetSpellTextScale(spellID)
        
        spIconXSlider:SetValue(iconX)
        spIconYSlider:SetValue(iconY)
        spIconScaleSlider:SetValue(iconScale)
        spTextXSlider:SetValue(textX)
        spTextYSlider:SetValue(textY)
        spTextScaleSlider:SetValue(textScale)

        -- Reposition icon picker and resize panel based on linked state
        if linked then
            -- Compact: move picker up just below the position-settings buttons
            sidePanel.pickerLabel:ClearAllPoints()
            sidePanel.pickerLabel:SetPoint("TOPLEFT", 8, -200)
            sidePanel.searchBox:ClearAllPoints()
            sidePanel.searchBox:SetPoint("TOPLEFT", 10, -218)
            sidePanel.grid:ClearAllPoints()
            sidePanel.grid:SetPoint("TOPLEFT", 10, -244)
            sidePanel.prevBtn:ClearAllPoints()
            sidePanel.prevBtn:SetPoint("TOPLEFT", 10, -476)
            sidePanel.helpText:ClearAllPoints()
            sidePanel.helpText:SetPoint("TOPLEFT", 8, -500)
            sidePanel.helpText:SetWidth(SIDE_PANEL_W - 16)
            sidePanel:SetHeight(562)
        else
            -- Full: restore original positions
            sidePanel.pickerLabel:ClearAllPoints()
            sidePanel.pickerLabel:SetPoint("TOPLEFT", 8, -480)
            sidePanel.searchBox:ClearAllPoints()
            sidePanel.searchBox:SetPoint("TOPLEFT", 10, -498)
            sidePanel.grid:ClearAllPoints()
            sidePanel.grid:SetPoint("TOPLEFT", 10, -524)
            sidePanel.prevBtn:ClearAllPoints()
            sidePanel.prevBtn:SetPoint("TOPLEFT", 10, -756)
            sidePanel.helpText:ClearAllPoints()
            sidePanel.helpText:SetPoint("TOPLEFT", 8, -778)
            sidePanel.helpText:SetWidth(SIDE_PANEL_W - 16)
            sidePanel:SetHeight(FRAME_H + 130)
        end
    end
    
    sidePanel:Hide()
    MA.sidePanel = sidePanel

    -- Hide side panel when config frame hides
    f:HookScript("OnHide", function() sidePanel:Hide() end)

    self.configFrame = f
    f:Hide()
end

-------------------------------------------------------------------------------
-- Voice Dropdown (installed TTS voices)
-------------------------------------------------------------------------------
function MA:ShowVoiceDropdown(anchor)
    local voices = self:GetTTSVoices(true)
    if not voices or #voices == 0 then
        if self._voiceBtnUpdate then self._voiceBtnUpdate() end
        return
    end

    if not self.voiceDropdown then
        local ROW_H = 20
        local PAD = 4
        local WIDTH = 320
        local MAX_VIS = 320
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
        dd.scroll = scroll
        dd.content = content
        dd.buttons = {}
        dd.rowHeight = ROW_H
        dd.pad = PAD
        dd.width = WIDTH
        dd.maxVisible = MAX_VIS
        dd.contentWidth = CONTENT_W

        self.voiceDropdown = dd
    end

    local dd = self.voiceDropdown

    -- Rebuild entries each open to reflect currently available voices.
    for _, btn in ipairs(dd.buttons) do
        btn:Hide()
    end
    wipe(dd.buttons)

    for i, voice in ipairs(voices) do
        local btn = CreateFrame("Button", nil, dd.content)
        btn:SetSize(dd.contentWidth, dd.rowHeight)
        btn:SetPoint("TOPLEFT", 0, -((i - 1) * dd.rowHeight))

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.55, 0.50, 0.40, 0.25)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 4, 0)
        label:SetPoint("RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetText((voice.name and voice.name ~= "") and voice.name or ("Voice " .. tostring(i)))

        btn.voiceIndex = i - 1 -- DB stores 0-based index
        btn.label = label
        dd.buttons[#dd.buttons + 1] = btn
    end

    local contentHeight = #voices * dd.rowHeight
    dd.content:SetHeight(math.max(1, contentHeight))
    dd:SetSize(dd.width, math.min(contentHeight + 2 * dd.pad, dd.maxVisible))

    local selected = self.db.ttsVoice or 0
    if selected < 0 or selected >= #voices then
        selected = 0
        self.db.ttsVoice = 0
    end

    for _, btn in ipairs(dd.buttons) do
        btn:SetScript("OnClick", function()
            self.db.ttsVoice = btn.voiceIndex
            self._cachedSelectedVoice = nil
            dd:Hide()
            if self._voiceBtnUpdate then self._voiceBtnUpdate() end
            self:TryTTS("Voice selected")
        end)

        if btn.voiceIndex == selected then
            btn.label:SetTextColor(0.92, 0.68, 0.22)
        else
            btn.label:SetTextColor(0.88, 0.80, 0.68)
        end
    end

    if dd.scroll and dd.scroll.SetVerticalScroll then
        dd.scroll:SetVerticalScroll(0)
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

    -- Right-click hotspot for custom icon picker
    local iconClick = CreateFrame("Button", nil, row)
    iconClick:SetSize(24, 24)
    iconClick:SetPoint("TOPLEFT", 4, -6)
    iconClick:RegisterForClicks("LeftButtonUp")
    iconClick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to customize positioning, scaling & icon")
        GameTooltip:Show()
    end)
    iconClick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.iconClick = iconClick

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
            local customIcon = MA:GetItemCustomIcon(sid)
            row.icon:SetTexture(customIcon or itemTexture or 134400)
            row.nameText:SetText("|cffEDD9A3" .. entry.name .. "|r")
            row.nameText:SetTextColor(1, 1, 1)
        else
            local customIcon = MA:GetSpellCustomIcon(sid)
            row.icon:SetTexture(customIcon or C_Spell.GetSpellTexture(sid) or 134400)
            row.nameText:SetText(entry.name)
            row.nameText:SetTextColor(IsPlayerSpell(sid) and 1 or 0.5, IsPlayerSpell(sid) and 1 or 0.5, IsPlayerSpell(sid) and 1 or 0.5)
        end

        row.iconClick:SetScript("OnClick", function(_, btn)
            -- Show side panel for positioning/scaling/icon controls
            MA.sidePanel.currentSpellID = sid
            MA.sidePanel.isItem = isItem
            local name = isItem and (entry.name or "Item") or (entry.name or "Spell")
            MA.sidePanel.itemName:SetText(name)
            local iconTex
            if isItem then
                iconTex = MA:GetItemCustomIcon(sid) or C_Item.GetItemIconByID(sid) or 134400
            else
                iconTex = MA:GetSpellCustomIcon(sid) or C_Spell.GetSpellTexture(sid) or 134400
            end
            MA.sidePanel.itemIcon:SetTexture(iconTex)
            MA.sidePanel.RefreshControls()
            MA.sidePanel:ClearAllPoints()
            MA.sidePanel:SetPoint("TOPLEFT", MA.configFrame, "TOPRIGHT", 4, 0)
            MA.sidePanel:SetFrameLevel(MA.configFrame:GetFrameLevel() + 20)
            MA.sidePanel:Raise()
            MA.sidePanel:Show()
            MA:ShowIconPickerInPanel(sid, isItem)
        end)

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
        local iconTex
        if isItem then
            iconTex = MA:GetItemCustomIcon(sid) or (select(10, GetItemInfo(sid)) or 134400)
        else
            iconTex = MA:GetSpellCustomIcon(sid) or (C_Spell.GetSpellTexture(sid) or 134400)
        end
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
