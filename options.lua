-- SwingBarMidnight/options.lua
-- Scrollable options panel (Settings API if available, InterfaceOptions fallback)

local ADDON_NAME, ns = ...
local DB

local _id = 0
local function NextName(prefix) _id = _id + 1; return prefix .. "_" .. _id end

local function Clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function HexToRGB(hex)
  if type(hex) ~= "string" then return 1,1,1 end
  hex = hex:gsub("#","")
  if #hex ~= 6 then return 1,1,1 end
  local r = tonumber(hex:sub(1,2), 16)
  local g = tonumber(hex:sub(3,4), 16)
  local b = tonumber(hex:sub(5,6), 16)
  if not (r and g and b) then return 1,1,1 end
  return r/255, g/255, b/255
end
local function RGBToHex(r,g,b)
  r = Clamp(math.floor((r or 1)*255 + 0.5), 0, 255)
  g = Clamp(math.floor((g or 1)*255 + 0.5), 0, 255)
  b = Clamp(math.floor((b or 1)*255 + 0.5), 0, 255)
  return string.format("#%02X%02X%02X", r,g,b)
end

local panel, scroll, content
local widgets = {}

-- Midnight (12.0+) Settings.OpenToCategory requires a numeric category ID.
-- We store the category object returned by Settings.RegisterCanvasLayoutCategory.
local settingsCategory

local function MakeTitle(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
  fs:SetText(text)
  return fs
end

local function MakeCheckbox(parent, label, tooltip)
  local cb = CreateFrame("CheckButton", NextName("SwingBarMidnightCB"), parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  if tooltip then
    cb:SetScript("OnEnter", function(self)
	      if InCombatLockdown and InCombatLockdown() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1,1,1)
      GameTooltip:AddLine(tooltip, 0.9,0.9,0.9, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return cb
end

local function MakeSlider(parent, label, minV, maxV, step, tooltip)
  local s = CreateFrame("Slider", NextName("SwingBarMidnightSL"), parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(260)
  s.Text:SetText(label)
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))
  if tooltip then
    s:SetScript("OnEnter", function(self)
	      if InCombatLockdown and InCombatLockdown() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1,1,1)
      GameTooltip:AddLine(tooltip, 0.9,0.9,0.9, true)
      GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return s
end

local function MakeEditBox(parent, label, width, tooltip)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  l:SetText(label)

  local eb = CreateFrame("EditBox", NextName("SwingBarMidnightEB"), parent, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetSize(width or 120, 20)
  eb:SetTextInsets(6, 6, 0, 0)

  if tooltip then
    eb:SetScript("OnEnter", function(self)
	      if InCombatLockdown and InCombatLockdown() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1,1,1)
      GameTooltip:AddLine(tooltip, 0.9,0.9,0.9, true)
      GameTooltip:Show()
    end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  return l, eb
end


local function MakeDropdown(parent, label, width, tooltip, items, onSelect)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  l:SetText(label)

  local dd = CreateFrame("Frame", NextName("SwingBarMidnightDD"), parent, "UIDropDownMenuTemplate")
  dd._items = items or {}
  dd._selected = nil

  UIDropDownMenu_SetWidth(dd, width or 180)
  UIDropDownMenu_SetText(dd, "")

  if tooltip then
    dd:SetScript("OnEnter", function(self)
      if InCombatLockdown and InCombatLockdown() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1,1,1)
      GameTooltip:AddLine(tooltip, 0.9,0.9,0.9, true)
      GameTooltip:Show()
    end)
    dd:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  UIDropDownMenu_Initialize(dd, function(self, level)
    for _, it in ipairs(dd._items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = it.text
      info.value = it.value
      info.func = function()
        dd._selected = it.value
        UIDropDownMenu_SetSelectedValue(dd, it.value)
        UIDropDownMenu_SetText(dd, it.text)
        if onSelect then onSelect(it.value, it.text) end
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  return l, dd
end

local function GetDropdownValue(dd, default)
  if not dd then return default end
  return dd._selected or default
end

local function SetDropdownToValue(dd, value)
  if not dd then return end
  dd._selected = value
  UIDropDownMenu_SetSelectedValue(dd, value)
  local txt = nil
  if dd._items then
    for _, it in ipairs(dd._items) do
      if it.value == value then txt = it.text break end
    end
  end
  UIDropDownMenu_SetText(dd, txt or "Custom")
end

local function ApplyFromUI()
  if not DB then return end

  DB.enabled = widgets.enabled:GetChecked() and true or false
  DB.showOnlyInCombat = widgets.onlyCombat:GetChecked() and true or false
  DB.locked = widgets.locked:GetChecked() and true or false
  DB.showOffhand = widgets.offhand:GetChecked() and true or false
  DB.text = widgets.text:GetChecked() and true or false
  DB.debug = widgets.debug:GetChecked() and true or false

  DB.width = widgets.width:GetValue()
  DB.height = widgets.height:GetValue()
  DB.scale = widgets.scale:GetValue()
  DB.fontSize = widgets.fontSize:GetValue()

  -- Appearance
  if widgets.barTexPath then DB.barTexture = widgets.barTexPath:GetText() or "" end
  if widgets.bgTexPath then DB.bgTexture = widgets.bgTexPath:GetText() or "" end
  if widgets.fontPath then DB.fontPath = widgets.fontPath:GetText() or "" end
  if widgets.fontFlags then DB.fontFlags = GetDropdownValue(widgets.fontFlags, DB.fontFlags or "OUTLINE") end

  if widgets.textColR then
    local tr = widgets.textColR:GetValue()/255
    local tg = widgets.textColG:GetValue()/255
    local tb = widgets.textColB:GetValue()/255
    DB.textColor = RGBToHex(tr,tg,tb)
  end

  if widgets.bgAlpha then DB.bgAlpha = widgets.bgAlpha:GetValue() end
  if widgets.borderAlpha then DB.borderAlpha = widgets.borderAlpha:GetValue() end

  DB.anchorOnGlow = widgets.anchorGlow:GetChecked() and true or false
  DB.anchorSpellIDs = widgets.anchorIDs:GetText()
  DB.glowFilterFrac = widgets.glowFrac:GetValue()
  DB.suppressWindow = widgets.suppress:GetValue()

	  DB.anchorOnAttackSpell = widgets.attackAnchor:GetChecked() and true or false
	  local atkId = tonumber((widgets.attackSpellId and widgets.attackSpellId:GetText()) or "")
	  if atkId then DB.attackSpellId = atkId end

  DB.anchorOnAura = widgets.anchorAura:GetChecked() and true or false
  DB.auraSpellIDs = widgets.auraIDs:GetText()

  DB.rangeCheck = widgets.rangeCheck:GetChecked() and true or false
  local rsId = tonumber((widgets.rangeSpellId and widgets.rangeSpellId:GetText()) or "")
  if rsId then DB.rangeSpellId = rsId end
  DB.freezeOutOfRange = widgets.freezeOOR:GetChecked() and true or false

  DB.useActionFallback = widgets.useActionFallback:GetChecked() and true or false

  local r = widgets.colR:GetValue()/255
  local g = widgets.colG:GetValue()/255
  local b = widgets.colB:GetValue()/255
  DB.color = RGBToHex(r,g,b)

  if widgets.ohR then
    local orr = widgets.ohR:GetValue()/255
    local org = widgets.ohG:GetValue()/255
    local orb = widgets.ohB:GetValue()/255
    DB.colorOH = RGBToHex(orr,org,orb)
  end

  if widgets.bgR then
    local bgr = widgets.bgR:GetValue()/255
    local bgg = widgets.bgG:GetValue()/255
    local bgb = widgets.bgB:GetValue()/255
    DB.bgColor = RGBToHex(bgr,bgg,bgb)
  end

  if widgets.borderR then
    local brr = widgets.borderR:GetValue()/255
    local brg = widgets.borderG:GetValue()/255
    local brb = widgets.borderB:GetValue()/255
    DB.borderColor = RGBToHex(brr,brg,brb)
  end

  ns.ApplySettings()
end

local function RefreshUI()
  DB = SwingBarMidnightDB
  if not DB then return end

  widgets.enabled:SetChecked(DB.enabled and true or false)
  widgets.onlyCombat:SetChecked(DB.showOnlyInCombat and true or false)
  widgets.locked:SetChecked(DB.locked and true or false)
  widgets.offhand:SetChecked(DB.showOffhand and true or false)
  widgets.text:SetChecked(DB.text and true or false)
  widgets.debug:SetChecked(DB.debug and true or false)

  widgets.width:SetValue(DB.width or 260)
  widgets.height:SetValue(DB.height or 12)
  widgets.scale:SetValue(DB.scale or 1)
  widgets.fontSize:SetValue(DB.fontSize or 10)

  if widgets.barTexPath then widgets.barTexPath:SetText(DB.barTexture or "") end
  if widgets.bgTexPath then widgets.bgTexPath:SetText(DB.bgTexture or "") end
  if widgets.fontPath then widgets.fontPath:SetText(DB.fontPath or "") end
  if widgets.barTexDD then SetDropdownToValue(widgets.barTexDD, DB.barTexture or "") end
  if widgets.bgTexDD then SetDropdownToValue(widgets.bgTexDD, DB.bgTexture or "") end
  if widgets.fontDD then SetDropdownToValue(widgets.fontDD, DB.fontPath or "") end

  if widgets.fontFlags then
    SetDropdownToValue(widgets.fontFlags, DB.fontFlags or "OUTLINE")
  end

  if widgets.textColR then
    local tr,tg,tb = HexToRGB(DB.textColor or "#FFFFFF")
    widgets.textColR:SetValue(math.floor(tr*255+0.5))
    widgets.textColG:SetValue(math.floor(tg*255+0.5))
    widgets.textColB:SetValue(math.floor(tb*255+0.5))
  end

  if widgets.bgAlpha then widgets.bgAlpha:SetValue(DB.bgAlpha or 0.35) end
  if widgets.borderAlpha then widgets.borderAlpha:SetValue(DB.borderAlpha or 0.75) end

  widgets.anchorGlow:SetChecked(DB.anchorOnGlow and true or false)
  widgets.anchorIDs:SetText(DB.anchorSpellIDs or "49020")
  widgets.glowFrac:SetValue(DB.glowFilterFrac or 0.7)
  widgets.suppress:SetValue(DB.suppressWindow or 1.0)

	  widgets.attackAnchor:SetChecked(DB.anchorOnAttackSpell and true or false)
	  widgets.attackSpellId:SetText(tostring(DB.attackSpellId or 6603))

  if widgets.anchorAura then
    widgets.anchorAura:SetChecked(DB.anchorOnAura and true or false)
  end
  if widgets.auraIDs then
    widgets.auraIDs:SetText(DB.auraSpellIDs or "")
  end
  if widgets.rangeCheck then
    widgets.rangeCheck:SetChecked(DB.rangeCheck and true or false)
  end
  if widgets.rangeSpellId then
    widgets.rangeSpellId:SetText(tostring(DB.rangeSpellId or 6603))
  end
  if widgets.freezeOOR then
    widgets.freezeOOR:SetChecked(DB.freezeOutOfRange ~= false)
  end
  widgets.useActionFallback:SetChecked(DB.useActionFallback and true or false)

  local r,g,b = HexToRGB(DB.color or "#66CCFF")
  widgets.colR:SetValue(math.floor(r*255+0.5))
  widgets.colG:SetValue(math.floor(g*255+0.5))
  widgets.colB:SetValue(math.floor(b*255+0.5))

  if widgets.ohR then
    local orr,org,orb = HexToRGB(DB.colorOH or "#FFCC66")
    widgets.ohR:SetValue(math.floor(orr*255+0.5))
    widgets.ohG:SetValue(math.floor(org*255+0.5))
    widgets.ohB:SetValue(math.floor(orb*255+0.5))
  end

  if widgets.bgR then
    local bgr,bgg,bgb = HexToRGB(DB.bgColor or "#000000")
    widgets.bgR:SetValue(math.floor(bgr*255+0.5))
    widgets.bgG:SetValue(math.floor(bgg*255+0.5))
    widgets.bgB:SetValue(math.floor(bgb*255+0.5))
  end

  if widgets.borderR then
    local brr,brg,brb = HexToRGB(DB.borderColor or "#FFFFFF")
    widgets.borderR:SetValue(math.floor(brr*255+0.5))
    widgets.borderG:SetValue(math.floor(brg*255+0.5))
    widgets.borderB:SetValue(math.floor(brb*255+0.5))
  end
end

local function CreatePanel()
  panel = CreateFrame("Frame", "SwingBarMidnightOptionsPanel", UIParent)
  panel.name = "SwingBarMidnight"

  scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  MakeTitle(content, "SwingBarMidnight")

  local y = -50
  local function place(w, x, dy)
    w:SetPoint("TOPLEFT", content, "TOPLEFT", x or 16, y)
    y = y - (dy or 28)
  end

  widgets.enabled = MakeCheckbox(content, "Enable", "Master toggle.")
  place(widgets.enabled)

  widgets.onlyCombat = MakeCheckbox(content, "Show only in combat", "Hides the bar out of combat.")
  place(widgets.onlyCombat)

  widgets.locked = MakeCheckbox(content, "Lock position/size", "Unlock to drag and resize the bar.")
  place(widgets.locked)

  widgets.offhand = MakeCheckbox(content, "Show offhand bar (2 bars)", "If enabled and you dual-wield, draws separate MH/OH bars. Default is one combined bar.")
  place(widgets.offhand, 16, 34)

  widgets.text = MakeCheckbox(content, "Show text", "Shows remaining time (seconds).")
  place(widgets.text)

  widgets.debug = MakeCheckbox(content, "Debug prints", "Prints anchor/suppress debug to chat.")
  place(widgets.debug)

  y = y - 8
  widgets.width = MakeSlider(content, "Width", 120, 900, 1)
  place(widgets.width, 16, 44)

  widgets.height = MakeSlider(content, "Height (per bar)", 8, 60, 1)
  place(widgets.height, 16, 44)

  widgets.scale = MakeSlider(content, "Scale", 0.5, 2.0, 0.01)
  place(widgets.scale, 16, 44)

  widgets.fontSize = MakeSlider(content, "Font size", 8, 18, 1)
  place(widgets.fontSize, 16, 44)

  -- Appearance: textures and font
  y = y - 6
  local apTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  apTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  apTitle:SetText("Textures & font")
  y = y - 24

  local texItems = {
    { text = "Solid (default)", value = "" },
    { text = "UI-StatusBar", value = "Interface\\TARGETINGFRAME\\UI-StatusBar" },
    { text = "Raid-Bar-Hp-Fill", value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { text = "White8x8", value = "Interface\\BUTTONS\\WHITE8X8" },
  }
  local lTexDD, ddTex = MakeDropdown(content, "Fill preset", 180, "Select a preset fill texture. You can also paste a custom path below.", texItems,
    function(val) if widgets.barTexPath then widgets.barTexPath:SetText(val or "") end end)
  lTexDD:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ddTex:SetPoint("LEFT", lTexDD, "RIGHT", -10, -2)
  widgets.barTexDD = ddTex
  y = y - 42

  local lTex, ebTex = MakeEditBox(content, "Fill texture path", 240, "Texture file path. Empty = solid fill. Example: Interface\\\\TARGETINGFRAME\\\\UI-StatusBar")
  lTex:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ebTex:SetPoint("LEFT", lTex, "RIGHT", 12, 0)
  widgets.barTexPath = ebTex
  y = y - 32

  local bgItems = {
    { text = "Solid (default)", value = "" },
    { text = "Tooltip-Background", value = "Interface\\Tooltips\\UI-Tooltip-Background" },
    { text = "White8x8", value = "Interface\\BUTTONS\\WHITE8X8" },
  }
  local lBgDD, ddBg = MakeDropdown(content, "Background preset", 180, "Select a preset background texture. Empty = solid background.", bgItems,
    function(val) if widgets.bgTexPath then widgets.bgTexPath:SetText(val or "") end end)
  lBgDD:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ddBg:SetPoint("LEFT", lBgDD, "RIGHT", -10, -2)
  widgets.bgTexDD = ddBg
  y = y - 42

  local lBg, ebBg = MakeEditBox(content, "Background texture path", 240, "Texture file path. Empty = solid background.")
  lBg:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ebBg:SetPoint("LEFT", lBg, "RIGHT", 12, 0)
  widgets.bgTexPath = ebBg
  y = y - 32

  local fontItems = {
    { text = "Default (STANDARD_TEXT_FONT)", value = "" },
    { text = "FRIZQT__.TTF", value = "Fonts\\FRIZQT__.TTF" },
    { text = "ARIALN.TTF", value = "Fonts\\ARIALN.TTF" },
    { text = "MORPHEUS.TTF", value = "Fonts\\MORPHEUS.ttf" },
    { text = "SKURRI.TTF", value = "Fonts\\skurri.ttf" },
  }
  local lFontDD, ddFont = MakeDropdown(content, "Font preset", 180, "Select a preset font file. You can also paste a custom path below.", fontItems,
    function(val) if widgets.fontPath then widgets.fontPath:SetText(val or "") end end)
  lFontDD:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ddFont:SetPoint("LEFT", lFontDD, "RIGHT", -10, -2)
  widgets.fontDD = ddFont
  y = y - 42

  local lFont, ebFont = MakeEditBox(content, "Font path", 240, "Font file path. Empty = STANDARD_TEXT_FONT.")
  lFont:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ebFont:SetPoint("LEFT", lFont, "RIGHT", 12, 0)
  widgets.fontPath = ebFont
  y = y - 32

  local flagItems = {
    { text = "OUTLINE", value = "OUTLINE" },
    { text = "THICKOUTLINE", value = "THICKOUTLINE" },
    { text = "NONE", value = "NONE" },
    { text = "MONOCHROME", value = "MONOCHROME" },
    { text = "OUTLINE,MONOCHROME", value = "OUTLINE,MONOCHROME" },
    { text = "THICKOUTLINE,MONOCHROME", value = "THICKOUTLINE,MONOCHROME" },
  }
  local lFlags, ddFlags = MakeDropdown(content, "Font flags", 180, "Outline/mono flags for SetFont.", flagItems)
  lFlags:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ddFlags:SetPoint("LEFT", lFlags, "RIGHT", -10, -2)
  widgets.fontFlags = ddFlags
  y = y - 42

  widgets.bgAlpha = MakeSlider(content, "Background alpha", 0.0, 1.0, 0.01, "Opacity of the background.")
  place(widgets.bgAlpha, 16, 44)

  widgets.borderAlpha = MakeSlider(content, "Border alpha", 0.0, 1.0, 0.01, "Opacity of the border.")
  place(widgets.borderAlpha, 16, 44)


  y = y - 6
  local colTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  colTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  colTitle:SetText("Main bar color (RGB)")
  y = y - 24

  widgets.colR = MakeSlider(content, "R", 0, 255, 1)
  place(widgets.colR, 16, 44)
  widgets.colG = MakeSlider(content, "G", 0, 255, 1)
  place(widgets.colG, 16, 44)
  widgets.colB = MakeSlider(content, "B", 0, 255, 1)
  place(widgets.colB, 16, 44)

  y = y - 6
  local ohTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ohTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ohTitle:SetText("Offhand bar color (RGB)")
  y = y - 24

  widgets.ohR = MakeSlider(content, "R", 0, 255, 1)
  place(widgets.ohR, 16, 44)
  widgets.ohG = MakeSlider(content, "G", 0, 255, 1)
  place(widgets.ohG, 16, 44)
  widgets.ohB = MakeSlider(content, "B", 0, 255, 1)
  place(widgets.ohB, 16, 44)

  y = y - 6
  local textTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  textTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  textTitle:SetText("Text color (RGB)")
  y = y - 24

  widgets.textColR = MakeSlider(content, "R", 0, 255, 1)
  place(widgets.textColR, 16, 44)
  widgets.textColG = MakeSlider(content, "G", 0, 255, 1)
  place(widgets.textColG, 16, 44)
  widgets.textColB = MakeSlider(content, "B", 0, 255, 1)
  place(widgets.textColB, 16, 44)

  y = y - 6
  local bgcTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bgcTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  bgcTitle:SetText("Background color (RGB)")
  y = y - 24

  widgets.bgR = MakeSlider(content, "R", 0, 255, 1)
  place(widgets.bgR, 16, 44)
  widgets.bgG = MakeSlider(content, "G", 0, 255, 1)
  place(widgets.bgG, 16, 44)
  widgets.bgB = MakeSlider(content, "B", 0, 255, 1)
  place(widgets.bgB, 16, 44)

  y = y - 6
  local brTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  brTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  brTitle:SetText("Border color (RGB)")
  y = y - 24

  widgets.borderR = MakeSlider(content, "R", 0, 255, 1)
  place(widgets.borderR, 16, 44)
  widgets.borderG = MakeSlider(content, "G", 0, 255, 1)
  place(widgets.borderG, 16, 44)
  widgets.borderB = MakeSlider(content, "B", 0, 255, 1)
  place(widgets.borderB, 16, 44)


  y = y - 6
  local aTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  aTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  aTitle:SetText("Glow anchoring")
  y = y - 24

  widgets.anchorGlow = MakeCheckbox(content, "Anchor phase on SpellActivationOverlay glow", "Uses overlay events as a phase anchor. Filtered to avoid spam.")
  place(widgets.anchorGlow, 16, 34)

  local l1, eb1 = MakeEditBox(content, "Anchor spellIDs (CSV)", 240, "Only these spellIDs will be used for anchoring. Default: 49020 (Obliterate). Example: 49020,438833")
  l1:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  eb1:SetPoint("LEFT", l1, "RIGHT", 12, 0)
  widgets.anchorIDs = eb1
  y = y - 32

  widgets.glowFrac = MakeSlider(content, "Filter: min anchor interval = swing * frac", 0.10, 0.95, 0.01, "Higher = fewer anchors; lower = more sensitive. Default 0.70.")
  place(widgets.glowFrac, 16, 44)

  widgets.suppress = MakeSlider(content, "Suppress anchors after FS/GA/HB/ERW (sec)", 0.0, 2.0, 0.05, "After these casts, the next glow within this window is ignored.")
  place(widgets.suppress, 16, 44)

	  widgets.attackAnchor = MakeCheckbox(content, "Experimental: anchor on cast succeeded (Attack)", "If your client emits UNIT_SPELLCAST_SUCCEEDED for auto-attacks (spellId=6603), this becomes a near-perfect anchor without combat log.")
	  place(widgets.attackAnchor, 16, 34)

	  local lAtk, ebAtk = MakeEditBox(content, "Attack spellID", 80, "Default: 6603. Change only if you know your client uses a different ID.")
	  lAtk:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
	  ebAtk:SetPoint("LEFT", lAtk, "RIGHT", 12, 0)
	  widgets.attackSpellId = ebAtk
	  y = y - 32

  y = y - 6
  local auraTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  auraTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  auraTitle:SetText("Aura anchoring")
  y = y - 24

  widgets.anchorAura = MakeCheckbox(content, "Anchor phase on player aura gain", "Anchors the swing phase when a tracked self-buff appears. Use for autoattack-dependent procs (example FDK Killing Machine: 51124).")
  place(widgets.anchorAura, 16, 34)

  local lAura, ebAura = MakeEditBox(content, "Aura spellIDs (CSV)", 240, "Anchors when any of these auras are gained. Example: 51124,51128")
  lAura:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ebAura:SetPoint("LEFT", lAura, "RIGHT", 12, 0)
  widgets.auraIDs = ebAura
  y = y - 32

  y = y - 6
  local rangeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rangeTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  rangeTitle:SetText("Range gating")
  y = y - 24

  widgets.rangeCheck = MakeCheckbox(content, "Enable range check", "Uses IsSpellInRange/C_Spell.IsSpellInRange to estimate melee range to target.")
  place(widgets.rangeCheck, 16, 34)

  local lRS, ebRS = MakeEditBox(content, "Range check spellID", 80, "Spell used for range checking. Default: 6603 (Attack). If unsupported, range check behaves as 'in range'.")
  lRS:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  ebRS:SetPoint("LEFT", lRS, "RIGHT", 12, 0)
  widgets.rangeSpellId = ebRS
  y = y - 32

  widgets.freezeOOR = MakeCheckbox(content, "Freeze bar when out of range", "When out of range, bars stop advancing (phase is preserved).")
  place(widgets.freezeOOR, 16, 34)

  widgets.useActionFallback = MakeCheckbox(content, "Fallback: suppress via action buttons", "If cast events are unreliable, suppress is triggered when you press watched action slots (spells/macros). Watched slots are rebuilt out of combat.")
  place(widgets.useActionFallback, 16, 34)

  local apply = CreateFrame("Button", NextName("SwingBarMidnightBtn"), content, "UIPanelButtonTemplate")
  apply:SetText("Apply")
  apply:SetSize(90, 22)
  apply:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 6)
  apply:SetScript("OnClick", ApplyFromUI)

  local help = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", apply, "TOPRIGHT", 12, 0)
	  help:SetText("Also: /swingbar options|unlock|lock|reset|toggle|attackanchor|auraanchor|range|freeze")

  y = y - 40
  content:SetHeight(-y + 40)

  panel:SetScript("OnShow", RefreshUI)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "SwingBarMidnight")
    if ok and category then
	      Settings.RegisterAddOnCategory(category)
	      settingsCategory = category
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.OpenOptions()
  if not panel then CreatePanel() end
  if Settings and Settings.OpenToCategory and settingsCategory and settingsCategory.GetID then
    -- Midnight: OpenToCategory expects numeric ID.
    pcall(Settings.OpenToCategory, settingsCategory:GetID())
  elseif Settings and Settings.OpenToCategory then
    -- Legacy fallback (older clients accepted string).
    pcall(Settings.OpenToCategory, "SwingBarMidnight")
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

-- Defer UI creation until needed; avoids unnecessary load/taint risk.
