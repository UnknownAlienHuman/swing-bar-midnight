-- SwingBarMidnight/core.lua
-- Retail 12.1 predicted melee cadence display.
--
-- This addon does not claim actual swing-hit timing without a legal hit event.
-- It renders a deterministic prediction from accessible UnitAttackSpeed values.
-- Phase is seeded on load/equipment changes and can be reset manually.

local ADDON_NAME, ns = ...
ns.VERSION = "0.9.0"
ns.DB_VERSION = 2

SwingBarMidnightDB = type(SwingBarMidnightDB) == "table" and SwingBarMidnightDB or {}
local DB = SwingBarMidnightDB

local DEFAULTS = {
  version = ns.DB_VERSION,
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

  -- False: show the main-hand prediction only.
  -- True: show separate MH/OH predictions when OH exists or its value is inaccessible.
  showOffhand = false,

  bgAlpha = 0.35,
  borderAlpha = 0.75,
  text = true,
  fontSize = 10,
  fontPath = STANDARD_TEXT_FONT,
  fontFlags = "OUTLINE",
  textColor = "#FFFFFF",
  barTexture = "",
  bgTexture = "",
  color = "#66CCFF",
  colorOH = "#FFCC66",
  bgColor = "#000000",
  borderColor = "#FFFFFF",
}

local function CanAccess(value)
  if type(canaccessvalue) == "function" then
    local ok, accessible = pcall(canaccessvalue, value)
    return ok and accessible == true
  end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret ~= true
  end
  return true
end

local function SafeBoolean(value)
  if not CanAccess(value) or type(value) ~= "boolean" then return nil end
  return value
end

local function SafeNumber(value)
  if not CanAccess(value) or type(value) ~= "number" or value ~= value then return nil end
  return value
end

local function SafeString(value)
  if not CanAccess(value) or type(value) ~= "string" then return nil end
  return value
end

local function MergeDefaults(destination, source)
  if type(destination) ~= "table" then destination = {} end
  for key, value in pairs(source) do
    if type(value) == "table" then
      destination[key] = MergeDefaults(destination[key], value)
    elseif type(destination[key]) ~= type(value) then
      destination[key] = value
    end
  end
  return destination
end

local function Clamp(value, fallback, minimum, maximum)
  value = SafeNumber(value)
  if not value then return fallback end
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function SanitizeDB()
  MergeDefaults(DB, DEFAULTS)
  DB.version = ns.DB_VERSION
  DB.enabled = SafeBoolean(DB.enabled) ~= false
  DB.showOnlyInCombat = SafeBoolean(DB.showOnlyInCombat) ~= false
  DB.locked = SafeBoolean(DB.locked) ~= false
  DB.showOffhand = SafeBoolean(DB.showOffhand) == true

  DB.point = SafeString(DB.point) or "CENTER"
  DB.relPoint = SafeString(DB.relPoint) or "CENTER"
  DB.x = Clamp(DB.x, 0, -4000, 4000)
  DB.y = Clamp(DB.y, -180, -4000, 4000)
  DB.width = Clamp(DB.width, 260, 120, 900)
  DB.height = Clamp(DB.height, 12, 8, 60)
  DB.scale = Clamp(DB.scale, 1, 0.60, 3.00)

  DB.bgAlpha = Clamp(DB.bgAlpha, 0.35, 0, 1)
  DB.borderAlpha = Clamp(DB.borderAlpha, 0.75, 0, 1)
  DB.text = SafeBoolean(DB.text) ~= false
  DB.fontSize = math.floor(Clamp(DB.fontSize, 10, 6, 40) + 0.5)
  DB.fontPath = SafeString(DB.fontPath) or STANDARD_TEXT_FONT
  DB.fontFlags = SafeString(DB.fontFlags) or "OUTLINE"
  DB.textColor = SafeString(DB.textColor) or "#FFFFFF"
  DB.barTexture = SafeString(DB.barTexture) or ""
  DB.bgTexture = SafeString(DB.bgTexture) or ""
  DB.color = SafeString(DB.color) or "#66CCFF"
  DB.colorOH = SafeString(DB.colorOH) or "#FFCC66"
  DB.bgColor = SafeString(DB.bgColor) or "#000000"
  DB.borderColor = SafeString(DB.borderColor) or "#FFFFFF"

  -- Retire 0.8.x phase-anchor/range heuristics. They were presentation or
  -- unrelated signals, not proof of an actual main/off-hand swing boundary.
  DB.anchorOnGlow = nil
  DB.anchorSpellIDs = nil
  DB.glowFilterFrac = nil
  DB.suppressWindow = nil
  DB.anchorOnAttackSpell = nil
  DB.attackSpellId = nil
  DB.anchorOnAura = nil
  DB.auraSpellIDs = nil
  DB.rangeCheck = nil
  DB.rangeSpellId = nil
  DB.freezeOutOfRange = nil
  DB.useActionFallback = nil
  DB.debug = nil
end

SanitizeDB()
ns.DB = DB

local function HexToRGB(value)
  local text = SafeString(value)
  if not text then return 1, 1, 1 end
  text = text:gsub("#", "")
  if #text ~= 6 then return 1, 1, 1 end
  local r = tonumber(text:sub(1, 2), 16)
  local g = tonumber(text:sub(3, 4), 16)
  local b = tonumber(text:sub(5, 6), 16)
  if not (r and g and b) then return 1, 1, 1 end
  return r / 255, g / 255, b / 255
end

local function SafeNow()
  if type(GetTime) ~= "function" then return nil end
  local ok, value = pcall(GetTime)
  return ok and SafeNumber(value) or nil
end

local state = {
  inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true or false,
  mhPeriod = nil,
  ohPeriod = nil,
  mhStatus = "unavailable",
  ohStatus = "unavailable",
  t0MH = 0,
  t0OH = 0,
  pendingApply = false,
  phaseReason = "load seed",
}
ns.state = state
_G.SwingBarMidnightState = state

local function ReadAttackSpeeds()
  if type(UnitAttackSpeed) ~= "function" then
    return nil, nil, "api unavailable", "api unavailable"
  end

  local ok, mhRaw, ohRaw = pcall(UnitAttackSpeed, "player")
  if not ok then return nil, nil, "api error", "api error" end

  local mh
  local mhStatus
  if CanAccess(mhRaw) then
    mh = SafeNumber(mhRaw)
    if mh and mh > 0 then mhStatus = "accessible" else mh, mhStatus = nil, "missing" end
  else
    mhStatus = "inaccessible"
  end

  local oh
  local ohStatus
  if CanAccess(ohRaw) then
    if ohRaw == nil then
      ohStatus = "absent"
    else
      oh = SafeNumber(ohRaw)
      if oh and oh > 0 then ohStatus = "accessible" else oh, ohStatus = nil, "absent" end
    end
  else
    ohStatus = "inaccessible"
  end

  return mh, oh, mhStatus, ohStatus
end

local function PreserveFraction(now, oldPeriod, newPeriod, oldOrigin)
  if not (now and oldPeriod and newPeriod and oldOrigin) then return now or 0 end
  if oldPeriod <= 0 or newPeriod <= 0 then return now end
  local elapsed = now - oldOrigin
  if elapsed < 0 then elapsed = 0 end
  local fraction = (elapsed % oldPeriod) / oldPeriod
  return now - (fraction * newPeriod)
end

local function RecomputeSpeeds(preservePhase)
  local now = SafeNow() or 0
  local oldMH, oldOH = state.mhPeriod, state.ohPeriod
  local oldT0MH, oldT0OH = state.t0MH, state.t0OH
  local mh, oh, mhStatus, ohStatus = ReadAttackSpeeds()

  state.mhPeriod = mh
  state.ohPeriod = oh
  state.mhStatus = mhStatus
  state.ohStatus = ohStatus

  if preservePhase and oldMH and mh then
    state.t0MH = PreserveFraction(now, oldMH, mh, oldT0MH)
  else
    state.t0MH = now
  end

  if preservePhase and oldOH and oh then
    state.t0OH = PreserveFraction(now, oldOH, oh, oldT0OH)
  else
    state.t0OH = now
  end
end

function ns.ResetBarPhase(reason)
  local now = SafeNow() or 0
  state.t0MH = now
  state.t0OH = now
  state.phaseReason = SafeString(reason) or "manual reset"
end

local frame, barMH, barOH

local function CreateBar(parent, name)
  local bar = CreateFrame("Frame", name, parent, "BackdropTemplate")
  bar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })

  local background = bar:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(bar)
  bar.background = background

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("LEFT", bar, "LEFT", 2, 0)
  fill:SetSize(1, 1)
  bar.fill = fill

  local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bar.text = text
  return bar
end

local function ApplyVisual(bar, fillHex)
  local r, g, b = HexToRGB(fillHex)
  if DB.barTexture ~= "" then
    bar.fill:SetTexture(DB.barTexture)
    bar.fill:SetTexCoord(0, 1, 0, 1)
    bar.fill:SetVertexColor(r, g, b, 1)
  else
    bar.fill:SetColorTexture(r, g, b, 1)
  end

  local br, bg, bb = HexToRGB(DB.bgColor)
  if DB.bgTexture ~= "" then
    bar.background:SetTexture(DB.bgTexture)
    bar.background:SetTexCoord(0, 1, 0, 1)
    bar.background:SetVertexColor(br, bg, bb, DB.bgAlpha)
  else
    bar.background:SetColorTexture(br, bg, bb, DB.bgAlpha)
  end

  local rr, rg, rb = HexToRGB(DB.borderColor)
  bar:SetBackdropColor(0, 0, 0, 0)
  bar:SetBackdropBorderColor(rr, rg, rb, DB.borderAlpha)
  bar.text:SetShown(DB.text)

  local flags = DB.fontFlags == "NONE" and "" or DB.fontFlags
  local ok = pcall(bar.text.SetFont, bar.text, DB.fontPath, DB.fontSize, flags)
  if not ok then pcall(bar.text.SetFont, bar.text, STANDARD_TEXT_FONT, DB.fontSize, flags) end
  local tr, tg, tb = HexToRGB(DB.textColor)
  bar.text:SetTextColor(tr, tg, tb, 0.95)
end

local function ShouldShowSecondBar()
  if not DB.showOffhand then return false end
  return state.ohPeriod ~= nil or state.ohStatus == "inaccessible"
end

local function UpdateLayout()
  if not frame then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    state.pendingApply = true
    return false
  end

  state.pendingApply = false
  frame:SetScale(DB.scale)
  local second = ShouldShowSecondBar()
  local gap = 4
  if second then
    frame:SetSize(DB.width, DB.height * 2 + gap)
    barMH:SetSize(DB.width, DB.height)
    barOH:SetSize(DB.width, DB.height)
    barMH:ClearAllPoints()
    barOH:ClearAllPoints()
    barMH:SetPoint("TOP", frame, "TOP", 0, 0)
    barOH:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    barOH:Show()
  else
    frame:SetSize(DB.width, DB.height)
    barMH:SetSize(DB.width, DB.height)
    barMH:ClearAllPoints()
    barMH:SetPoint("CENTER", frame, "CENTER", 0, 0)
    barOH:Hide()
  end

  ApplyVisual(barMH, DB.color)
  ApplyVisual(barOH, DB.colorOH)
  return true
end

local function ApplyPosition()
  if not frame then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    state.pendingApply = true
    return false
  end
  frame:ClearAllPoints()
  frame:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
  return true
end

local function SetLocked(locked)
  DB.locked = locked == true
  if not frame then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    state.pendingApply = true
    return
  end
  frame:EnableMouse(not DB.locked)
  frame:SetMovable(not DB.locked)
  if DB.locked then
    frame:RegisterForDrag()
  else
    frame:RegisterForDrag("LeftButton")
  end
  frame.resizer:SetShown(not DB.locked)
  frame.moverOverlay:SetShown(not DB.locked)
end

local function SavePosition()
  if not frame or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  point = SafeString(point)
  relativePoint = SafeString(relativePoint)
  x = SafeNumber(x)
  y = SafeNumber(y)
  if not point or not relativePoint or not x or not y then return end
  DB.point, DB.relPoint = point, relativePoint
  DB.x, DB.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local function CreateMainFrame()
  frame = CreateFrame("Frame", "SwingBarMidnightFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(120, 8, 900, 120)

  barMH = CreateBar(frame, "SwingBarMidnightBarMH")
  barOH = CreateBar(frame, "SwingBarMidnightBarOH")

  local overlay = frame:CreateTexture(nil, "OVERLAY")
  overlay:SetAllPoints(frame)
  overlay:SetColorTexture(1, 1, 1, 0.06)
  frame.moverOverlay = overlay

  frame:SetScript("OnDragStart", function(self)
    if DB.locked or InCombatLockdown() then return end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)

  local resizer = CreateFrame("Button", nil, frame)
  frame.resizer = resizer
  resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  resizer:SetSize(14, 14)
  resizer:RegisterForDrag("LeftButton")
  resizer:SetScript("OnDragStart", function()
    if DB.locked or InCombatLockdown() then return end
    frame:StartSizing("BOTTOMRIGHT")
  end)
  resizer:SetScript("OnDragStop", function()
    if InCombatLockdown() then return end
    frame:StopMovingOrSizing()
    local width, height = frame:GetSize()
    width = SafeNumber(width)
    height = SafeNumber(height)
    if not width or not height then return end
    DB.width = Clamp(width, DB.width, 120, 900)
    if ShouldShowSecondBar() then height = (height - 4) / 2 end
    DB.height = Clamp(height, DB.height, 8, 60)
    UpdateLayout()
  end)
  local resizeTexture = resizer:CreateTexture(nil, "OVERLAY")
  resizeTexture:SetAllPoints(resizer)
  resizeTexture:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")

  ApplyPosition()
  UpdateLayout()
  SetLocked(DB.locked)
end

local function SetProgress(bar, progress)
  if not bar then return end
  progress = SafeNumber(progress)
  if not progress then progress = 0 end
  if progress < 0 then progress = 0 elseif progress > 1 then progress = 1 end
  local width = SafeNumber(bar:GetWidth()) or 1
  local height = SafeNumber(bar:GetHeight()) or 1
  width = math.max(1, width - 4)
  height = math.max(1, height - 4)
  bar.fill:SetWidth(width * progress)
  bar.fill:SetHeight(height)
end

local function UpdatePredictedBar(bar, label, period, origin, status, now)
  if not bar then return end
  if not period or period <= 0 or not now then
    SetProgress(bar, 0)
    if DB.text then bar.text:SetText(label .. " — " .. (status or "unavailable")) end
    return
  end

  local elapsed = now - origin
  if elapsed < 0 then elapsed = 0 end
  local phase = elapsed % period
  local remaining = period - phase
  SetProgress(bar, phase / period)
  if DB.text then bar.text:SetText(string.format("%s predicted %.2f", label, remaining)) end
end

local function ShouldShow()
  if not DB.enabled then return false end
  if DB.showOnlyInCombat and not state.inCombat then return false end
  return true
end

local updater = CreateFrame("Frame")
local accumulator = 0
updater:SetScript("OnUpdate", function(_, elapsed)
  if not frame then return end
  if not ShouldShow() then
    frame:Hide()
    return
  end
  frame:Show()

  local elapsedNumber = SafeNumber(elapsed)
  if not elapsedNumber then return end
  accumulator = accumulator + elapsedNumber
  if accumulator < 0.02 then return end
  accumulator = 0

  local now = SafeNow()
  UpdatePredictedBar(barMH, "MH", state.mhPeriod, state.t0MH, state.mhStatus, now)
  if ShouldShowSecondBar() then
    UpdatePredictedBar(barOH, "OH", state.ohPeriod, state.t0OH, state.ohStatus, now)
  end
end)

CreateMainFrame()
RecomputeSpeeds(false)
ns.ResetBarPhase("load seed")
UpdateLayout()

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    state.inCombat = true
    if DB.showOnlyInCombat and DB.enabled then frame:Show() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    state.inCombat = false
    if state.pendingApply then ns.ApplySettings() end
    if DB.showOnlyInCombat then frame:Hide() end
  elseif event == "UNIT_ATTACK_SPEED" or event == "PLAYER_EQUIPMENT_CHANGED" then
    local oldSecond = ShouldShowSecondBar()
    RecomputeSpeeds(true)
    if oldSecond ~= ShouldShowSecondBar() then UpdateLayout() end
  end
end)

function ns.ApplySettings()
  SanitizeDB()
  if InCombatLockdown() then
    state.pendingApply = true
    return false
  end
  state.pendingApply = false
  RecomputeSpeeds(true)
  ApplyPosition()
  UpdateLayout()
  SetLocked(DB.locked)
  frame:SetShown(ShouldShow())
  return true
end

function ns.GetPredictionState()
  return {
    mhPeriod = state.mhPeriod,
    ohPeriod = state.ohPeriod,
    mhStatus = state.mhStatus,
    ohStatus = state.ohStatus,
    phaseReason = state.phaseReason,
  }
end

SLASH_SWINGBARMIDNIGHT1 = "/swingbar"
SlashCmdList.SWINGBARMIDNIGHT = function(message)
  message = SafeString(message) or ""
  message = message:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if message == "unlock" then
    SetLocked(false)
  elseif message == "lock" then
    SetLocked(true)
  elseif message == "reset" then
    DB.point, DB.relPoint, DB.x, DB.y = "CENTER", "CENTER", 0, -180
    DB.width, DB.height, DB.scale = 260, 12, 1
    ns.ResetBarPhase("full reset")
    ns.ApplySettings()
  elseif message == "resetphase" or message == "phase" then
    ns.ResetBarPhase("manual reset")
  elseif message == "toggle" then
    DB.enabled = not DB.enabled
    ns.ApplySettings()
  elseif message == "options" or message == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif message == "status" then
    local prediction = ns.GetPredictionState()
    print(string.format(
      "SwingBarMidnight: MH=%s (%s), OH=%s (%s), phase=%s; prediction only",
      prediction.mhPeriod and string.format("%.3f", prediction.mhPeriod) or "unavailable",
      prediction.mhStatus,
      prediction.ohPeriod and string.format("%.3f", prediction.ohPeriod) or "unavailable",
      prediction.ohStatus,
      prediction.phaseReason
    ))
  elseif message == "version" or message == "ver" then
    print("SwingBarMidnight v" .. ns.VERSION)
  else
    print("SwingBarMidnight: /swingbar options|unlock|lock|reset|resetphase|toggle|status|version")
  end
end

if DB.showOnlyInCombat and not state.inCombat then frame:Hide() end
if not DB.enabled then frame:Hide() end

ns.Runtime = {
  CanAccess = CanAccess,
  SafeNumber = SafeNumber,
  ReadAttackSpeeds = ReadAttackSpeeds,
  RecomputeSpeeds = RecomputeSpeeds,
  PreserveFraction = PreserveFraction,
  GetState = function() return state end,
  GetFrame = function() return frame end,
}
