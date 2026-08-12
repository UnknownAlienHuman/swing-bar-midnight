-- SwingBarMidnight/core.lua
-- Midnight-safe: no combat log parsing. Optional player-aura anchoring for self procs (safe fields only).
-- Base timer: deterministic from attack speed. Optional phase anchoring from SpellActivationOverlay glow.
-- Anchor suppression: ignore anchors shortly after specific casts (FS/GA/HB/ERW), with cast event + UseAction fallback.

local ADDON_NAME, ns = ...
ns.VERSION = "0.8.1"


-- SavedVariables
SwingBarMidnightDB = SwingBarMidnightDB or {}
local DB = SwingBarMidnightDB

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local defaults = {
  enabled = true,
  showOnlyInCombat = true,
  locked = true,

  point = "CENTER",
  relPoint = "CENTER",
  x = 0,
  y = -180,
  width = 260,
  height = 12,
  scale = 1,

  -- If false: 1 combined bar (recommended for modern dual-wield normalization).
  -- If true: two bars (MH/OH) when dual-wielding.
  showOffhand = false,

  -- Visual
  bgAlpha = 0.35,
  borderAlpha = 0.75,
  text = true,
  fontSize = 10,
  fontPath = STANDARD_TEXT_FONT,
  fontFlags = "OUTLINE",
  textColor = "#FFFFFF",
  barTexture = "", -- empty => solid fill
  bgTexture = "",  -- empty => solid background

  -- Colors in hex (#RRGGBB)
  color = "#66CCFF",
  colorOH = "#FFCC66",
  bgColor = "#000000",
  borderColor = "#FFFFFF",

  -- Anchoring (glow)
  anchorOnGlow = true,
  anchorSpellIDs = "49020", -- Obliterate
  glowFilterFrac = 0.70,    -- min accepted anchor interval = swingPeriod * frac (debounce)
  suppressWindow = 1.00,    -- seconds after certain casts to ignore anchors
  -- Experimental: if the client emits UNIT_SPELLCAST_SUCCEEDED for auto-attacks
  -- (spellId=6603), this provides a near-perfect anchor without combat log.
  anchorOnAttackSpell = false,
  attackSpellId = 6603,

  -- Optional: anchor phase on player aura gain (self buffs).
  -- Intended for autoattack-dependent procs (e.g. FDK Killing Machine).
  -- We only use presence checks by spellID; we never compare secret fields.
  anchorOnAura = false,
  auraSpellIDs = "",

  -- Optional: range gating (freeze bar when target is out of range).
  rangeCheck = false,
  rangeSpellId = 6603,
  freezeOutOfRange = true,

  -- Fallback for suppress (button/macro usage)
  useActionFallback = true,

  debug = false,
}

CopyDefaults(DB, defaults)
ns.DB = DB

local function Clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function HexToRGB(hex)
  if type(hex) ~= "string" then return 1, 1, 1 end
  hex = hex:gsub("#","")
  if #hex ~= 6 then return 1,1,1 end
  local r = tonumber(hex:sub(1,2), 16)
  local g = tonumber(hex:sub(3,4), 16)
  local b = tonumber(hex:sub(5,6), 16)
  if not (r and g and b) then return 1,1,1 end
  return r/255, g/255, b/255
end

local function ParseSpellIDList(csv)
  local t = {}
  if type(csv) ~= "string" then return t end
  for token in csv:gmatch("[^,%s]+") do
    local n = tonumber(token)
    if n then t[n] = true end
  end
  return t
end


-- Aura presence checks (player-only, safe fields) ----------------------------

local FindAuraBySpellId = (AuraUtil and (AuraUtil.FindAuraBySpellId or AuraUtil.FindAuraBySpellID))

local function AuraPresentBySpellId(spellId)
  if not FindAuraBySpellId then return false end
  if type(spellId) ~= "number" or spellId <= 0 then return false end
  -- Return value (name) may be secret; we only use its presence as a boolean.
  return FindAuraBySpellId(spellId, "player", "HELPFUL") and true or false
end

local function DebugPrint(...)
  if not DB.debug then return end
  print("|cff66ccffSwingBarMidnight|r", ...)
end

-- Speeds helpers ------------------------------------------------------------

-- Returns mhSpeed, ohSpeed (ohSpeed=0 if none).
local function GetAttackSpeeds()
  local mh, oh
  if type(GetSwingSpeeds) == "function" then
    mh, oh = GetSwingSpeeds()
  end
  mh, oh = mh or 0, oh or 0
  if mh <= 0 then
    local u1, u2 = UnitAttackSpeed("player")
    mh, oh = u1 or 0, u2 or 0
  end
  if mh <= 0 then mh = 2.0 end
  if not oh or oh <= 0 then oh = 0 end
  return mh, oh
end

local function HasOffhandWeapon(mh, oh)
  return (type(oh) == "number" and oh > 0) and true or false
end

-- Forward declaration.
-- NOTE: Several helper functions (e.g. GetPeriods) reference `state`.
-- In Lua, if `local state` is declared *after* those functions, they will
-- capture the *global* `state` instead (nil), causing runtime errors.
local state

-- State (init early so helpers never see nil)
state = {
  inCombat = InCombatLockdown() and true or false,
  lastAnchor = 0,
  suppressUntil = 0,
  hasOffhand = false,
  mhSpeed = 0,
  ohSpeed = 0,
  periodMH = 0,
  periodOH = 0,
  periodCombined = 0,
  anchorSpellSet = ParseSpellIDList(DB.anchorSpellIDs or "49020"),
  overlayActive = {}, -- spellId -> bool (rising edge detector)
  overlayCount = 0,   -- for debugger (optional)
  auraSpellSet = ParseSpellIDList(DB.auraSpellIDs or ""),
  auraActive = {},  -- spellId -> bool
  lastAuraScan = 0,

  inRange = true,
  rangeLastCheck = 0,
  paused = false,
  pauseAt = 0,
}
ns.state = state

-- Cache speeds/periods so the OnUpdate loop never calls UnitAttackSpeed.
local function RecomputeSpeedsAndPeriods()
  local mh, oh = GetAttackSpeeds()
  state.mhSpeed = mh
  state.ohSpeed = oh
  state.hasOffhand = HasOffhandWeapon(mh, oh)

  state.periodMH = mh
  state.periodOH = state.hasOffhand and oh or 0

  -- Period model:
  --  - 1 weapon: mhSpeed
  --  - 2 weapons combined stream: mean interval ~= 1 / (1/mh + 1/oh)
  if state.hasOffhand then
    local rate = (1.0 / mh) + (1.0 / oh)
    if rate > 0 then
      state.periodCombined = (1.0 / rate)
    else
      state.periodCombined = mh
    end
  else
    state.periodCombined = mh
  end
end

RecomputeSpeedsAndPeriods()

-- Period selection (cheap; uses cached values)
local function GetPeriods()
  if DB.showOffhand and state.hasOffhand then
    return state.periodMH, state.periodOH
  end
  return state.periodCombined, 0
end

-- Expose for debugger
_G.SwingBarMidnightState = state
_G.SwingBarMidnight_InternalState = state

-- UI -------------------------------------------------------------------------

local frame, barMH, barOH

local function CreateBar(parent, name)
  local fr = CreateFrame("Frame", name, parent, "BackdropTemplate")
  fr:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  fr:SetBackdropColor(0,0,0,1)
  fr:SetBackdropBorderColor(1,1,1,1)

  local bg = fr:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(fr)
  bg:SetColorTexture(0,0,0,1)
  fr._bg = bg

  local fill = fr:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("LEFT", fr, "LEFT", 2, 0)
  fill:SetSize(1, 1)
  fill:SetColorTexture(1,1,1,1)
  fr._fill = fill

  local txt = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  txt:SetPoint("CENTER", fr, "CENTER", 0, 0)
  txt:SetText("")
  fr._txt = txt

  return fr
end

local function ApplyVisual(fr, hexFill)
  local r,g,b = HexToRGB(hexFill)

  -- Fill texture (optional)
  local tex = DB.barTexture
  if type(tex) == "string" and tex ~= "" then
    fr._fill:SetTexture(tex)
    fr._fill:SetTexCoord(0, 1, 0, 1)
    fr._fill:SetVertexColor(r,g,b,1)
  else
    fr._fill:SetColorTexture(r,g,b,1)
  end

  -- Background
  local br,bg,bb = HexToRGB(DB.bgColor)
  local btex = DB.bgTexture
  local ba = DB.bgAlpha or 0.35
  if type(btex) == "string" and btex ~= "" then
    fr._bg:SetTexture(btex)
    fr._bg:SetTexCoord(0, 1, 0, 1)
    fr._bg:SetVertexColor(br,bg,bb,ba)
  else
    fr._bg:SetColorTexture(br,bg,bb,ba)
  end

  -- Border
  local rr,rg,rb = HexToRGB(DB.borderColor)
  fr:SetBackdropBorderColor(rr,rg,rb, DB.borderAlpha or 0.75)

  -- Text
  fr._txt:SetShown(DB.text and true or false)

  local fontPath = (type(DB.fontPath) == "string" and DB.fontPath ~= "") and DB.fontPath or STANDARD_TEXT_FONT
  local flags = (type(DB.fontFlags) == "string" and DB.fontFlags) or "OUTLINE"
  if flags == "NONE" then flags = "" end

  local ok = pcall(fr._txt.SetFont, fr._txt, fontPath, DB.fontSize or 10, flags)
  if not ok then
    -- Fallback to default font path if a custom file is missing.
    pcall(fr._txt.SetFont, fr._txt, STANDARD_TEXT_FONT, DB.fontSize or 10, flags)
  end

  local tr,tg,tb = HexToRGB(DB.textColor or "#FFFFFF")
  fr._txt:SetTextColor(tr,tg,tb,0.9)
end

local function UpdateLayout()
  if not frame then return end
  frame:SetScale(DB.scale or 1)

  local w = DB.width or 260
  local h = DB.height or 12

  -- Two bars only make sense when an actual offhand weapon is present.
  local showTwo = (DB.showOffhand and state.hasOffhand) and true or false

  if showTwo then
    local gap = 4
    frame:SetSize(w, (h*2) + gap)
    barMH:SetSize(w, h)
    barOH:SetSize(w, h)
    barMH:ClearAllPoints()
    barOH:ClearAllPoints()
    barMH:SetPoint("TOP", frame, "TOP", 0, 0)
    barOH:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    barOH:Show()
  else
    frame:SetSize(w, h)
    barMH:SetSize(w, h)
    barMH:ClearAllPoints()
    barMH:SetPoint("CENTER", frame, "CENTER", 0, 0)
    barOH:Hide()
  end

  ApplyVisual(barMH, DB.color or "#66CCFF")
  ApplyVisual(barOH, DB.colorOH or "#FFCC66")
end

local function SavePosition()
  local p, _, rp, x, y = frame:GetPoint(1)
  DB.point, DB.relPoint, DB.x, DB.y = p, rp, x, y
end

local function ApplyPosition()
  frame:ClearAllPoints()
  frame:SetPoint(DB.point or "CENTER", UIParent, DB.relPoint or "CENTER", DB.x or 0, DB.y or -180)
end

local function SetLocked(lock)
  DB.locked = lock and true or false
  frame:EnableMouse(not DB.locked)
  frame:SetMovable(not DB.locked)
  if not DB.locked then
    frame:RegisterForDrag("LeftButton")
  else
    frame:RegisterForDrag()
  end
  frame._resizer:SetShown(not DB.locked)
  frame._moverOverlay:SetShown(not DB.locked)
end

local function CreateMainFrame()
  frame = CreateFrame("Frame", "SwingBarMidnightFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetSize(DB.width or 260, DB.height or 12)

  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(120, 8, 900, 120)

  barMH = CreateBar(frame, "SwingBarMidnightBarMH")
  barOH = CreateBar(frame, "SwingBarMidnightBarOH")

  local moverOverlay = frame:CreateTexture(nil, "OVERLAY")
  moverOverlay:SetAllPoints(frame)
  moverOverlay:SetColorTexture(1,1,1,0.06)
  frame._moverOverlay = moverOverlay

  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if DB.locked then return end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    if DB.locked then return end
    self:StopMovingOrSizing()
    SavePosition()
  end)

  local resizer = CreateFrame("Button", nil, frame)
  resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  resizer:SetSize(14, 14)
  resizer:EnableMouse(true)
  resizer:RegisterForDrag("LeftButton")
  resizer:SetScript("OnDragStart", function()
    if DB.locked then return end
    frame:StartSizing("BOTTOMRIGHT")
  end)
  resizer:SetScript("OnDragStop", function()
    if DB.locked then return end
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    local showTwo = (DB.showOffhand and state.hasOffhand) and true or false
    if showTwo then
      local gap = 4
      local per = (h - gap) / 2
      DB.height = Clamp(per, 8, 60)
      DB.width = Clamp(w, 120, 900)
    else
      DB.width = Clamp(w, 120, 900)
      DB.height = Clamp(h, 8, 60)
    end
    UpdateLayout()
  end)
  local rt = resizer:CreateTexture(nil, "OVERLAY")
  rt:SetAllPoints(resizer)
  rt:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
  frame._resizer = resizer

  UpdateLayout()
  ApplyPosition()
  SetLocked(DB.locked)

  if not DB.enabled then
    frame:Hide()
  end
end

CreateMainFrame()

-- Swing phase + display ------------------------------------------------------

-- Separate phase origins for MH/OH.
-- In single-bar mode we only use t0MH.
local t0MH = GetTime()
local t0OH = t0MH

local function SetProgress(fr, p)
  p = Clamp(p or 0, 0, 1)
  local w = (fr:GetWidth() or 1) - 4
  if w < 1 then w = 1 end
  fr._fill:SetWidth(w * p)
  fr._fill:SetHeight((fr:GetHeight() or 1) - 4)
end

local function UpdateText(fr, label, remaining)
  if not DB.text then return end
  fr._txt:SetText(string.format("%s %.2f", label, remaining))
end

local function ShouldShow()
  if not DB.enabled then return false end
  if DB.showOnlyInCombat and not state.inCombat then return false end
  return true
end

local function DualBarsActive()
  return (DB.showOffhand and state.hasOffhand) and true or false
end

-- Debounce period used for accepting anchors. In dual-bar mode an anchor can be
-- caused by either hand, so we use the faster hand as the upper bound.
local function GetDebouncePeriod()
  local mhP, ohP = GetPeriods()
  mhP = (type(mhP) == "number" and mhP > 0) and mhP or 2.0

  if DualBarsActive() and type(ohP) == "number" and ohP > 0 then
    return math.min(mhP, ohP)
  end
  return mhP
end

local function PhaseDistance(now, t0, period)
  if type(period) ~= "number" or period <= 0 then return math.huge, 0 end
  if type(t0) ~= "number" then t0 = now end
  local dt = now - t0
  if dt < 0 then dt = 0 end
  local phase = dt % period
  local d = phase
  local d2 = period - phase
  if d2 < d then d = d2 end
  return d, phase
end

local function AnchorNow(reason)
  local now = GetTime()

  if DualBarsActive() then
    -- Snap the hand whose predicted boundary is closer to "now".
    local mhP, ohP = GetPeriods()
    local dMH = PhaseDistance(now, t0MH, mhP)
    local dOH = PhaseDistance(now, t0OH, ohP)
    if dOH < dMH then
      t0OH = now
      DebugPrint("ANCHOR", reason or "?", "hand=OH")
    else
      t0MH = now
      DebugPrint("ANCHOR", reason or "?", "hand=MH")
    end
  else
    t0MH = now
    DebugPrint("ANCHOR", reason or "?")
  end

  state.lastAnchor = now
  state.inRange = true
  if state.paused then SetPaused(false) end
end

local function CanAcceptAnchor()
  local now = GetTime()
  if state.paused then
    return false, 'paused'
  end
  if now < (state.suppressUntil or 0) then
    return false, "suppressed"
  end

  local period = GetDebouncePeriod()
  local minInt = (DB.glowFilterFrac or 0.7) * period
  if (now - (state.lastAnchor or 0)) < minInt then
    return false, "debounce"
  end
  return true, "ok"
end

local function OnGlowShow(spellId)
  if not DB.anchorOnGlow then return end
  if not state.anchorSpellSet[spellId] then return end

  -- rising edge only
  if state.overlayActive[spellId] then return end
  state.overlayActive[spellId] = true

  local ok, why = CanAcceptAnchor()
  if not ok then
    DebugPrint("GLOW_SHOW ignored", spellId, why)
    return
  end
  AnchorNow("glow:" .. tostring(spellId))
end

local function OnGlowHide(spellId)
  if not state.anchorSpellSet[spellId] then return end
  state.overlayActive[spellId] = false
end


-- Player aura anchoring -----------------------------------------------------

local function BaselineTrackedAuras()
  if not state.auraSpellSet or not next(state.auraSpellSet) then return end
  for spellId in pairs(state.auraSpellSet) do
    state.auraActive[spellId] = AuraPresentBySpellId(spellId)
  end
  state.lastAuraScan = GetTime()
end

local function ScanPlayerAuras(reason)
  if not DB.anchorOnAura then return end
  if not state.auraSpellSet or not next(state.auraSpellSet) then return end

  local now = GetTime()
  -- UNIT_AURA can be spammy; throttle.
  if (now - (state.lastAuraScan or 0)) < 0.05 then return end
  state.lastAuraScan = now

  for spellId in pairs(state.auraSpellSet) do
    local present = AuraPresentBySpellId(spellId)
    local prev = state.auraActive[spellId] and true or false

    if present and not prev then
      local ok, why = CanAcceptAnchor()
      if ok then
        AnchorNow((reason or 'aura') .. ':' .. tostring(spellId))
      else
        DebugPrint('AURA_GAIN ignored', spellId, why)
      end
    end

    state.auraActive[spellId] = present
  end
end

-- Suppress anchors after casts that can proc KM without melee swing
local SUPPRESS_CAST_SPELLS = {
  [49143]  = true, -- Frost Strike
  [194913] = true, -- Glacial Advance
  [49184]  = true, -- Howling Blast
  [47568]  = true, -- Empower Rune Weapon
}

local function SuppressNow(reason, payload)
  local untilT = GetTime() + (DB.suppressWindow or 1.0)
  state.suppressUntil = untilT
  DebugPrint("SUPPRESS", reason, payload or "", "until", untilT)
end

local function OnSpellcastSucceeded(unit, _, spellId)
  if unit ~= "player" then return end

  if spellId and SUPPRESS_CAST_SPELLS[spellId] then
    SuppressNow("cast", spellId)
    return
  end

  -- Experimental: some clients may emit 6603 (Attack) here for auto-attacks.
  if DB.anchorOnAttackSpell and type(spellId) == "number" and spellId == (DB.attackSpellId or 6603) then
    local ok, why = CanAcceptAnchor()
    if ok then
      AnchorNow("cast:" .. tostring(spellId))
    else
      DebugPrint("CAST_OK ignored", spellId, why)
    end
  end
end

-- Range gating (freeze out of range) ----------------------------------------

local function GetSpellInRange(spellId, unit)
  if type(spellId) ~= "number" or spellId <= 0 then return nil end

  if C_Spell and C_Spell.IsSpellInRange then
    -- Returns true/false/nil (Midnight-safe).
    return C_Spell.IsSpellInRange(spellId, unit)
  end

  if IsSpellInRange and GetSpellInfo then
    local name = GetSpellInfo(spellId)
    if not name then return nil end
    local r = IsSpellInRange(name, unit)
    if r == 1 then return true end
    if r == 0 then return false end
    return nil
  end

  return nil
end

local function UpdateRangeState(now, force)
  if not DB.rangeCheck then
    state.inRange = true
    state.rangeLastCheck = now
    return
  end

  if not force and (now - (state.rangeLastCheck or 0)) < 0.10 then
    return
  end
  state.rangeLastCheck = now

  if not UnitExists("target") or not UnitCanAttack("player", "target") then
    state.inRange = true
    return
  end

  local sid = tonumber(DB.rangeSpellId) or 0
  local r = GetSpellInRange(sid, "target")
  -- Treat nil as in-range (avoid false positives when API can't evaluate the spell).
  state.inRange = (r == false) and false or true
end

local function SetPaused(paused)
  paused = paused and true or false
  if paused == (state.paused and true or false) then return end

  if paused then
    state.paused = true
    state.pauseAt = GetTime()
  else
    local now = GetTime()
    local delta = now - (state.pauseAt or now)
    if delta > 0 then
      -- Keep swing phase continuous by shifting origins forward.
      t0MH = t0MH + delta
      t0OH = t0OH + delta
    end
    state.paused = false
    state.pauseAt = 0
  end
end

-- UseAction fallback: build watched action slots out of combat, then suppress when those slots are used.
local watchedSlots = {} -- slot -> true

local function ResolveMacroSpellId(macroIndex)
  if type(macroIndex) ~= "number" then return nil end
  local s = GetMacroSpell(macroIndex)
  if type(s) == "number" then return s end
  if type(s) == "string" and C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(s)
    if info and type(info.spellID) == "number" then return info.spellID end
  end
  return nil
end

local function BuildWatchedSlots()
  if InCombatLockdown() then return end
  if not DB.useActionFallback then return end
  for k in pairs(watchedSlots) do watchedSlots[k] = nil end

  for slot = 1, 180 do
    local t, id = GetActionInfo(slot)
    if t == "spell" and type(id) == "number" and SUPPRESS_CAST_SPELLS[id] then
      watchedSlots[slot] = true
    elseif t == "macro" and type(id) == "number" then
      local spellId = ResolveMacroSpellId(id)
      if type(spellId) == "number" and SUPPRESS_CAST_SPELLS[spellId] then
        watchedSlots[slot] = true
      end
    end
  end

  if DB.debug then
    local c=0; for _ in pairs(watchedSlots) do c=c+1 end
    DebugPrint("watchedSlots rebuilt:", c)
  end
end

if DB.useActionFallback then
  hooksecurefunc("UseAction", function(slot)
    if slot and watchedSlots[slot] then
      SuppressNow("useaction", slot)
    end
  end)
end

-- Update loop
local updater = CreateFrame("Frame")
local acc = 0
updater:SetScript("OnUpdate", function(_, elapsed)
  if not frame then return end

  if not ShouldShow() then
    if frame:IsShown() then frame:Hide() end
    return
  end
  if not frame:IsShown() then frame:Show() end

  acc = acc + elapsed
  if acc < 0.016 then return end
  acc = 0

  local nowReal = GetTime()

  -- Range gating (optional)
  UpdateRangeState(nowReal, false)
  if DB.rangeCheck and DB.freezeOutOfRange and (state.inRange == false) then
    SetPaused(true)
  else
    SetPaused(false)
  end

  local now = state.paused and (state.pauseAt or nowReal) or nowReal
  local mhPeriod, ohPeriod = GetPeriods()

  local showTwo = DualBarsActive()

  -- If weapon configuration changed without firing equipment events, keep the
  -- frame layout in sync.
  if frame._showTwo ~= showTwo then
    frame._showTwo = showTwo
    UpdateLayout()
  end

  if not showTwo then
    local period = (type(mhPeriod) == "number" and mhPeriod > 0) and mhPeriod or 2.0
    local dt = now - t0MH
    local rem = period - (dt % period)
    SetProgress(barMH, (dt % period) / period)
    UpdateText(barMH, "Swing", rem)
  else
    local periodMH = (type(mhPeriod) == "number" and mhPeriod > 0) and mhPeriod or 2.0
    local periodOH = (type(ohPeriod) == "number" and ohPeriod > 0) and ohPeriod or periodMH

    local dtMH = now - t0MH
    local dtOH = now - t0OH

    local rem1 = periodMH - (dtMH % periodMH)
    SetProgress(barMH, (dtMH % periodMH) / periodMH)
    UpdateText(barMH, "MH", rem1)

    local rem2 = periodOH - (dtOH % periodOH)
    SetProgress(barOH, (dtOH % periodOH) / periodOH)
    UpdateText(barOH, "OH", rem2)
  end
end)

-- Events (registered only when allowed) --------------------------------------

local ev = CreateFrame("Frame")

local function OnRegenDisabled()
  state.inCombat = true
  if DB.showOnlyInCombat then frame:Show() end
end

local function OnRegenEnabled()
  state.inCombat = false
  if DB.showOnlyInCombat then frame:Hide() end
  BuildWatchedSlots()
end

local function OnAttackSpeedChanged()
  local oldHasOH = state.hasOffhand and true or false
  local oldMH = state.periodMH
  local oldOH = state.periodOH
  local oldCombined = state.periodCombined

  RecomputeSpeedsAndPeriods()

  -- Preserve visual phase when haste/speed changes to avoid large jumps.
  local function RescalePhase(oldP, newP, t0)
    if type(oldP) ~= "number" or oldP <= 0 then return t0 end
    if type(newP) ~= "number" or newP <= 0 then return t0 end
    local now = GetTime()
    local dt = now - (t0 or now)
    if dt < 0 then dt = 0 end
    local frac = (dt % oldP) / oldP
    return now - (frac * newP)
  end

  local nowHasOH = state.hasOffhand and true or false

  if DB.showOffhand and nowHasOH then
    -- Dual bars: rescale each hand independently.
    t0MH = RescalePhase(oldMH, state.periodMH, t0MH)
    if oldHasOH then
      t0OH = RescalePhase(oldOH, state.periodOH, t0OH)
    else
      -- If an offhand weapon appears, initialize its phase to match MH.
      t0OH = t0MH
    end
  else
    -- Single bar: rescale the combined stream.
    t0MH = RescalePhase(oldCombined, state.periodCombined, t0MH)
    if nowHasOH and not oldHasOH then
      t0OH = t0MH
    end
  end

  -- Layout depends on whether an offhand weapon exists.
  if oldHasOH ~= nowHasOH then
    UpdateLayout()
  end

  DebugPrint("SPEED", state.mhSpeed or 0, state.ohSpeed or 0, "hasOH", nowHasOH and 1 or 0)
end

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    OnRegenDisabled()
  elseif event == "PLAYER_REGEN_ENABLED" then
    OnRegenEnabled()
  elseif event == "UNIT_ATTACK_SPEED" then
    local unit = ...
    if unit == "player" then OnAttackSpeedChanged() end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    OnAttackSpeedChanged()
  elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" then
    BuildWatchedSlots()
  elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
    local spellId = ...
    if type(spellId) == "number" then OnGlowShow(spellId) end
  elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" or event == "SPELL_ACTIVATION_OVERLAY_HIDE" then
    local spellId = ...
    if type(spellId) == "number" then OnGlowHide(spellId) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnSpellcastSucceeded(...)
  elseif event == "UNIT_AURA" then
    local unit = ...
    if unit == "player" then
      ScanPlayerAuras("UNIT_AURA")
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    -- Force immediate range reevaluation on target switch.
    UpdateRangeState(GetTime(), true)
    if DB.rangeCheck and DB.freezeOutOfRange and (state.inRange == false) then
      SetPaused(true)
    else
      SetPaused(false)
    end
  end
end)

local function RegisterEventsNow()
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:RegisterEvent("UNIT_ATTACK_SPEED")
  ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
  ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
  ev:RegisterEvent("PLAYER_TARGET_CHANGED")
  ev:RegisterEvent("UNIT_AURA")
  ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  ev:RegisterEvent("UPDATE_MACROS")
  DebugPrint("events registered")
end

-- Midnight: RegisterEvent can be forbidden if addon is loaded in combat (/reload in combat). Defer to out of combat.
if not InCombatLockdown() then
  RegisterEventsNow()
  BuildWatchedSlots()
else
  local defer = CreateFrame("Frame")
  defer:SetScript("OnUpdate", function(self)
    if not InCombatLockdown() then
      self:SetScript("OnUpdate", nil)
      RegisterEventsNow()
      BuildWatchedSlots()
    end
  end)
end

-- Options API ----------------------------------------------------------------

function ns.ApplySettings()
  state.anchorSpellSet = ParseSpellIDList(DB.anchorSpellIDs or "49020")
  state.auraSpellSet = ParseSpellIDList(DB.auraSpellIDs or "")
  BaselineTrackedAuras()

  -- Reset range pause on settings changes.
  state.inRange = true
  if state.paused then SetPaused(false) end

  -- Refresh cached weapon speeds/periods so layout respects actual offhand presence.
  RecomputeSpeedsAndPeriods()

  UpdateLayout()
  ApplyPosition()
  SetLocked(DB.locked)
  if not ShouldShow() then frame:Hide() else frame:Show() end
end

function ns.ResetBarPhase()
  local now = GetTime()
  t0MH = now
  t0OH = now
  state.lastAnchor = now
  state.inRange = true
  if state.paused then SetPaused(false) end
  DebugPrint("RESET_PHASE")
end

-- Slash ----------------------------------------------------------------------

SLASH_SWINGBARMIDNIGHT1 = "/swingbar"
SlashCmdList["SWINGBARMIDNIGHT"] = function(msg)
  msg = (msg or ""):lower()
  if msg == "unlock" then
    SetLocked(false); ns.ApplySettings(); print("SwingBarMidnight: unlocked")
  elseif msg == "lock" then
    SetLocked(true); ns.ApplySettings(); print("SwingBarMidnight: locked")
  elseif msg == "reset" then
    DB.point, DB.relPoint, DB.x, DB.y = "CENTER", "CENTER", 0, -180
    DB.width, DB.height, DB.scale = 260, 12, 1
    ns.ResetBarPhase()
    ns.ApplySettings()
    print("SwingBarMidnight: reset")
  elseif msg == "toggle" then
    DB.enabled = not DB.enabled
    ns.ApplySettings()
    print("SwingBarMidnight:", DB.enabled and "enabled" or "disabled")
  elseif msg == "version" or msg == "ver" then
    print("SwingBarMidnight v" .. tostring(ns.VERSION or "?"))
  elseif msg == "attackanchor" then
    DB.anchorOnAttackSpell = not DB.anchorOnAttackSpell
    ns.ApplySettings()
    print("SwingBarMidnight: attack anchor", DB.anchorOnAttackSpell and "ON" or "OFF")
  elseif msg == "auraanchor" then
    DB.anchorOnAura = not DB.anchorOnAura
    ns.ApplySettings()
    print("SwingBarMidnight: aura anchor", DB.anchorOnAura and "ON" or "OFF")
  elseif msg == "range" then
    DB.rangeCheck = not DB.rangeCheck
    ns.ApplySettings()
    print("SwingBarMidnight: range check", DB.rangeCheck and "ON" or "OFF")
  elseif msg == "freeze" then
    DB.freezeOutOfRange = not DB.freezeOutOfRange
    ns.ApplySettings()
    print("SwingBarMidnight: freeze OOR", DB.freezeOutOfRange and "ON" or "OFF")
  elseif msg == "options" or msg == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  else
    print("SwingBarMidnight commands:")
    print("  /swingbar options | unlock | lock | reset | toggle | attackanchor | auraanchor | range | freeze | version")
  end
end

-- Initial visibility
if DB.showOnlyInCombat and not state.inCombat then frame:Hide() end
if not DB.enabled then frame:Hide() end

-- Load banner (helps confirm correct installed version)
print("SwingBarMidnight v" .. tostring(ns.VERSION or "?"))
