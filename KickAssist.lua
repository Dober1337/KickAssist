local ADDON_NAME = ...

-------------------------------------------------------------------
-- Interrupt-Spell je Klasse (Spell-IDs -> sprachunabhängig)
-------------------------------------------------------------------
local INTERRUPT_SPELLS = {
    WARRIOR     = 6552,   -- Pummel
    ROGUE       = 1766,   -- Kick
    DEATHKNIGHT = 47528,  -- Mind Freeze
    SHAMAN      = 57994,  -- Wind Shear
    MAGE        = 2139,   -- Counterspell
    WARLOCK     = 19647,  -- Spell Lock (Felhunter-Pet) - Standard/Fallback
    HUNTER      = 147362, -- Counter Shot
    MONK        = 116705, -- Spear Hand Strike
    DRUID       = 106839, -- Skull Bash
    PALADIN     = 96231,  -- Rebuke
    DEMONHUNTER = 183752, -- Disrupt
    EVOKER      = 351338, -- Quell
    PRIEST      = 15487,  -- Silence
}

-- Hexer hat je nach Spezialisierung ein anderes Dauer-Pet und damit eine
-- andere Interrupt-Fähigkeit: Dämonologie hat immer den Felwächter (Axtwurf),
-- Verwüstung/Sukkubus nutzen stattdessen den Felsucher (Spell Lock).
local WARLOCK_INTERRUPT_BY_SPEC = {
    [1] = 19647, -- Affliction: Spell Lock (Felsucher)
    [2] = 89766, -- Demonology: Axtwurf (Felwächter)
    [3] = 19647, -- Destruction: Spell Lock (Felsucher)
}

-------------------------------------------------------------------
-- SavedVariables (pro Charakter)
-------------------------------------------------------------------
KickAssistDB = KickAssistDB or {
    myIcon = nil,
    firstRunKick = true,
    firstRunMark = true,
}

local COMM_PREFIX = "KICKASSIST1"
local claimedIcons = {} -- [iconIndex] = "Spielername (kurz)"

-------------------------------------------------------------------
-- Hilfsfunktionen
-------------------------------------------------------------------
local function Print(msg)
    print("|cff00ff88[KickAssist]|r " .. msg)
end

local function IconName(icon)
    return _G["RAID_TARGET_" .. icon] or tostring(icon)
end

local UpdateIconSelectionUI -- weiter unten definiert (GUI-Abschnitt)
local pendingMacroUpdate = false

-- Legt ein Makro an oder aktualisiert es, falls es schon existiert.
-- perCharacter = true -> Makro liegt im Charakter-Makrofenster, nicht global.
local function EnsureMacro(name, iconTexture, body, perCharacter, firstRunFlag)
    local index = GetMacroIndexByName(name)
    local isNew = (index == 0)

    if isNew then
        -- CreateMacro gibt nil zurück, wenn das globale/charakterbezogene
        -- Makro-Limit erreicht ist (36 global / 18 pro Charakter).
        index = CreateMacro(name, iconTexture, body, perCharacter)
        if not index then
            Print("Konnte Makro '" .. name .. "' nicht anlegen (Makro-Limit erreicht?).")
            return
        end
    else
        EditMacro(index, name, iconTexture, body)
    end

    if isNew and KickAssistDB[firstRunFlag] then
        Print("Makro '" .. name .. "' wurde erstellt. Öffne /ka und zieh es einmalig von dort auf deine Aktionsleiste.")
        KickAssistDB[firstRunFlag] = false
    end
end

-------------------------------------------------------------------
-- Teil A: statisches Kick-Makro (immer der eigene Interrupt-Spell)
-------------------------------------------------------------------
local function SetupKickMacro()
    local _, class = UnitClass("player")
    local spellID = INTERRUPT_SPELLS[class]

    if class == "WARLOCK" then
        local specIndex = GetSpecialization()
        spellID = (specIndex and WARLOCK_INTERRUPT_BY_SPEC[specIndex]) or spellID
    end

    if not spellID then
        Print("Für deine Klasse ist kein Interrupt hinterlegt.")
        return
    end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name
    if not spellName then
        Print("Interrupt-Spell (ID " .. spellID .. ") konnte nicht aufgelöst werden - noch nicht gelernt?")
        return
    end

    -- Priorität: Fokus, falls vorhanden und feindlich, sonst aktuelles Ziel.
    local body = "#showtooltip\n/cast [@focus,exists,nodead,harm][harm] " .. spellName

    EnsureMacro("KickAssist_Kick", "INV_Misc_QuestionMark", body, true, "firstRunKick")
end

-------------------------------------------------------------------
-- Teil B: dynamisches Markier-Makro (dein zugewiesenes Symbol)
-------------------------------------------------------------------
local function SetupMarkMacro()
    if not KickAssistDB.myIcon then return end

    -- Markiert aktuell anvisiertes Ziel und setzt es gleich als Fokus.
    local body = "#showtooltip\n/tm " .. KickAssistDB.myIcon .. "\n/focus"

    local iconPath = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. KickAssistDB.myIcon
    local iconFileID = GetFileIDFromPath(iconPath) or "INV_Misc_QuestionMark"

    EnsureMacro("KickAssist_Mark", iconFileID, body, true, "firstRunMark")
end

-- Makros dürfen laut WoW-API nie während des Kampfes erstellt/verändert
-- werden - das würde sonst mit "der Blizzard-UI vorbehalten" geblockt.
local function UpdateMacrosSafely()
    if InCombatLockdown() then
        if not pendingMacroUpdate then
            pendingMacroUpdate = true
            Print("Du bist im Kampf - Makro wird aktualisiert, sobald der Kampf endet.")
        end
        return
    end

    SetupKickMacro()
    if KickAssistDB.myIcon then
        SetupMarkMacro()
    end
    pendingMacroUpdate = false
end

-------------------------------------------------------------------
-- Gruppen-Sync
-------------------------------------------------------------------
local function GetGroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function BroadcastIconClaim(icon)
    local channel = GetGroupChannel()
    if not channel then return end
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, "CLAIM:" .. icon, channel)
end

local function BroadcastIconRelease(icon)
    local channel = GetGroupChannel()
    if not channel then return end
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, "RELEASE:" .. icon, channel)
end

local function AnnounceInChat(icon)
    local channel = GetGroupChannel()
    if not channel then return end
    SendChatMessage("{rt" .. icon .. "} Ich kicke " .. IconName(icon), channel)
end

-- Baut aus der aktuellen Gruppe eine Menge bekannter (kurzer) Spielernamen.
-- Wird genutzt, um verwaiste Symbol-Zuordnungen (Spieler hat Gruppe verlassen) zu entfernen.
local function GetGroupMemberNames()
    local present = {}
    present[UnitName("player")] = true
    if IsInRaid() then
        for i = 1, 40 do
            if UnitExists("raid" .. i) then
                present[Ambiguate(UnitName("raid" .. i), "short")] = true
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                present[Ambiguate(UnitName("party" .. i), "short")] = true
            end
        end
    end
    return present
end

-------------------------------------------------------------------
-- Öffentliche Funktionen: eigenes Symbol setzen / freigeben
-------------------------------------------------------------------
local function SetMyIcon(icon)
    if icon < 1 or icon > 6 then
        Print("Nur Symbole 1-6 (Stern bis Quadrat) sind erlaubt - Kreuz und Totenkopf bleiben frei.")
        return
    end

    local existingOwner = claimedIcons[icon]
    local myName = UnitName("player")
    if existingOwner and existingOwner ~= myName then
        Print("Achtung: " .. IconName(icon) .. " ist laut Sync bereits von " .. existingOwner .. " gewählt. Trotzdem gesetzt - sprecht euch ab.")
    end

    -- Falls du vorher ein anderes Symbol hattest, dieses freigeben.
    if KickAssistDB.myIcon and KickAssistDB.myIcon ~= icon then
        local oldIcon = KickAssistDB.myIcon
        if claimedIcons[oldIcon] == myName then
            claimedIcons[oldIcon] = nil
        end
        BroadcastIconRelease(oldIcon)
    end

    KickAssistDB.myIcon = icon
    claimedIcons[icon] = myName

    UpdateMacrosSafely()
    BroadcastIconClaim(icon)
    AnnounceInChat(icon)

    if UpdateIconSelectionUI then
        UpdateIconSelectionUI()
    end

    Print("Dein Symbol: " .. IconName(icon) .. ". Nutze das Makro 'KickAssist_Mark', um dein aktuelles Ziel damit zu markieren.")
end

local function ClearMyIcon()
    if not KickAssistDB.myIcon then
        Print("Du hast aktuell kein Symbol gewählt.")
        return
    end

    local icon = KickAssistDB.myIcon
    local myName = UnitName("player")

    if claimedIcons[icon] == myName then
        claimedIcons[icon] = nil
    end
    BroadcastIconRelease(icon)

    KickAssistDB.myIcon = nil

    if UpdateIconSelectionUI then
        UpdateIconSelectionUI()
    end

    Print(IconName(icon) .. " wieder freigegeben. Hinweis: 'KickAssist_Mark' zeigt bis zur nächsten Wahl noch auf das alte Symbol.")
end

-------------------------------------------------------------------
-- Grafische Symbolauswahl (Alternative zu /ka <Zahl>)
-------------------------------------------------------------------
local iconButtons = {}
local selectorFrame

local function BuildRosterText()
    local lines = {}
    for icon = 1, 6 do
        local owner = claimedIcons[icon]
        if owner then
            table.insert(lines, IconName(icon) .. ": " .. owner)
        end
    end
    if #lines == 0 then
        return "Noch niemand hat ein Symbol gewählt."
    end
    return table.concat(lines, "\n")
end

local function CreateSelectorFrame()
    if selectorFrame then return selectorFrame end

    local f = CreateFrame("Frame", "KickAssistSelectorFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(248, 240)
    local pos = KickAssistDB.framePos or {"CENTER", "CENTER", 0, 150}
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        KickAssistDB.framePos = {point, relPoint, x, y}
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -5)
    f.title:SetText("KickAssist - dein Symbol")

    local size, spacing = 32, 6
    local totalWidth = (size * 6) + (spacing * 5)
    local startX = (f:GetWidth() - totalWidth) / 2

    for i = 1, 6 do
        local btn = CreateFrame("Button", "KickAssistIconButton" .. i, f)
        btn:SetSize(size, size)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", startX + (i - 1) * (size + spacing), -42)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i))
        btn.icon = tex

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.25)

        local checkmark = btn:CreateTexture(nil, "OVERLAY")
        checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkmark:SetSize(18, 18)
        checkmark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -4)
        checkmark:Hide()
        btn.checkmark = checkmark

        btn:SetScript("OnClick", function() SetMyIcon(i) end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local owner = claimedIcons[i]
            if KickAssistDB.myIcon == i then
                GameTooltip:SetText(IconName(i) .. " (dein Symbol)")
            elseif owner then
                GameTooltip:SetText(IconName(i) .. " (vergeben: " .. owner .. ")")
            else
                GameTooltip:SetText(IconName(i) .. " (frei)")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        iconButtons[i] = btn
    end

    -- Freigeben-Button
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(110, 20)
    clearBtn:SetPoint("TOP", f, "TOP", 0, -80)
    clearBtn:SetText("Symbol freigeben")
    clearBtn:SetScript("OnClick", ClearMyIcon)
    f.clearButton = clearBtn

    -- Roster-Anzeige
    local rosterTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rosterTitle:SetPoint("TOP", clearBtn, "BOTTOM", 0, -8)
    rosterTitle:SetText("Aktuelle Zuteilung:")

    local rosterText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterText:SetPoint("TOP", rosterTitle, "BOTTOM", 0, -4)
    rosterText:SetWidth(220)
    rosterText:SetJustifyH("CENTER")
    rosterText:SetText(BuildRosterText())
    f.rosterText = rosterText

    -- Trennlinie/Hinweis + Drag-Icons
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", rosterText, "BOTTOM", 0, -12)
    hint:SetWidth(230)
    hint:SetText("Makros direkt auf die Leiste ziehen:")

    local function CreateDraggableMacroIcon(xOffset, macroName, label)
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(36, 36)
        btn:SetPoint("TOP", hint, "BOTTOM", xOffset, -8)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        btn.icon = tex

        local btnHighlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btnHighlight:SetAllPoints()
        btnHighlight:SetColorTexture(1, 1, 1, 0.25)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        text:SetText(label)

        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function()
            if InCombatLockdown() then
                Print("Makros können im Kampf nicht auf die Leiste gezogen werden.")
                return
            end
            local index = GetMacroIndexByName(macroName)
            if index and index > 0 then
                PickupMacro(index)
            else
                Print("Makro '" .. macroName .. "' existiert noch nicht.")
            end
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(macroName)
            GameTooltip:AddLine("Anklicken, halten, auf Aktionsleiste ziehen.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn.Refresh = function()
            local index = GetMacroIndexByName(macroName)
            if index and index > 0 then
                local _, iconTexture = GetMacroInfo(index)
                tex:SetTexture(iconTexture)
                tex:SetDesaturated(false)
            else
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tex:SetDesaturated(true)
            end
        end
        btn.Refresh()

        return btn
    end

    f.kickDragButton = CreateDraggableMacroIcon(-40, "KickAssist_Kick", "Kick")
    f.markDragButton = CreateDraggableMacroIcon(40, "KickAssist_Mark", "Mark")

    selectorFrame = f
    UpdateIconSelectionUI()
    return f
end

UpdateIconSelectionUI = function()
    local myName = UnitName("player")

    for icon, btn in pairs(iconButtons) do
        local owner = claimedIcons[icon]

        if KickAssistDB.myIcon == icon then
            btn.checkmark:Show()
            btn:Enable()
            btn.icon:SetDesaturated(false)
        elseif owner and owner ~= myName then
            btn.checkmark:Hide()
            btn:Disable()
            btn.icon:SetDesaturated(true)
        else
            btn.checkmark:Hide()
            btn:Enable()
            btn.icon:SetDesaturated(false)
        end
    end

    if selectorFrame then
        if selectorFrame.rosterText then
            selectorFrame.rosterText:SetText(BuildRosterText())
        end
        if selectorFrame.kickDragButton then selectorFrame.kickDragButton.Refresh() end
        if selectorFrame.markDragButton then selectorFrame.markDragButton.Refresh() end
    end
end

local function ToggleSelectorFrame()
    local f = CreateSelectorFrame()
    if f:IsShown() then
        f:Hide()
    else
        UpdateIconSelectionUI()
        f:Show()
    end
end

-------------------------------------------------------------------
-- Minimap-Icon
-------------------------------------------------------------------
local minimapButton

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    local angle = math.rad(KickAssistDB.minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        radius * math.cos(angle), radius * math.sin(angle))
end

local function CreateMinimapButton()
    if minimapButton then return minimapButton end

    local btn = CreateFrame("Button", "KickAssistMinimapButton", UIParent)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"))
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(31, 31)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            KickAssistDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            UpdateMinimapButtonPosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function()
        ToggleSelectorFrame()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("KickAssist")
        GameTooltip:AddLine("Klicken zum Öffnen. Ziehen zum Verschieben.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapButton = btn
    UpdateMinimapButtonPosition()
    btn:SetShown(not KickAssistDB.minimapHidden)
    return btn
end

-------------------------------------------------------------------
-- Events
-------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
            CreateMinimapButton()
            UpdateMacrosSafely()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMacrosSafely()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingMacroUpdate then
            UpdateMacrosSafely()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then
            UpdateMacrosSafely()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        local present = GetGroupMemberNames()
        for icon, owner in pairs(claimedIcons) do
            if not present[owner] then
                claimedIcons[icon] = nil
            end
        end

        if KickAssistDB.myIcon then
            BroadcastIconClaim(KickAssistDB.myIcon)
        end

        if UpdateIconSelectionUI then
            UpdateIconSelectionUI()
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= COMM_PREFIX then return end

        local senderShort = Ambiguate(sender, "short")
        if senderShort == UnitName("player") then return end

        local claimIcon = msg:match("^CLAIM:(%d)$")
        local releaseIcon = msg:match("^RELEASE:(%d)$")

        if claimIcon then
            local icon = tonumber(claimIcon)
            local existingOwner = claimedIcons[icon]
            if existingOwner and existingOwner ~= senderShort and icon == KickAssistDB.myIcon then
                Print("Achtung: " .. senderShort .. " hat ebenfalls " .. IconName(icon) .. " gewählt - sprecht euch ab.")
            end
            claimedIcons[icon] = senderShort
            if UpdateIconSelectionUI then UpdateIconSelectionUI() end

        elseif releaseIcon then
            local icon = tonumber(releaseIcon)
            if claimedIcons[icon] == senderShort then
                claimedIcons[icon] = nil
                if UpdateIconSelectionUI then UpdateIconSelectionUI() end
            end
        end
    end
end)

-------------------------------------------------------------------
-- Slash-Befehl
-------------------------------------------------------------------
SLASH_KICKASSIST1 = "/kickassist"
SLASH_KICKASSIST2 = "/ka"
SlashCmdList["KICKASSIST"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        ToggleSelectorFrame()
        return
    end

    if msg == "clear" then
        ClearMyIcon()
        return
    end

    if msg == "minimap" then
        KickAssistDB.minimapHidden = not KickAssistDB.minimapHidden
        if minimapButton then
            minimapButton:SetShown(not KickAssistDB.minimapHidden)
        end
        Print(KickAssistDB.minimapHidden and "Minimap-Icon ausgeblendet." or "Minimap-Icon eingeblendet.")
        return
    end

    local icon = tonumber(msg)
    if icon then
        SetMyIcon(icon)
    else
        Print("Nutzung: /ka  (öffnet Auswahlfenster)  |  /ka <1-6>  |  /ka clear  |  /ka minimap")
        Print("1=Stern  2=Kreis  3=Diamant  4=Dreieck  5=Mond  6=Quadrat")
    end
end
