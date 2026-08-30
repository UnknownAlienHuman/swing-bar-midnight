local combat = false
local now = 100
local speedMode = "secret"
local SECRET = setmetatable({}, {
  __tostring = function() error("inaccessible speed stringified") end,
  __index = function() error("inaccessible speed indexed") end,
  __lt = function() error("inaccessible speed compared") end,
  __le = function() error("inaccessible speed compared") end,
  __div = function() error("inaccessible speed divided") end,
})
local frames = {}
local registeredEvents = {}
local registeredUnitEvents = {}

local function assertEq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function newRegion(objectType, name, parent)
  local region = {
    objectType = objectType or "Frame",
    name = name,
    parent = parent,
    shown = true,
    width = 260,
    height = 12,
    point = { "CENTER", parent, "CENTER", 0, 0 },
    scripts = {},
  }
  function region:SetBackdrop(value) self.backdrop = value end
  function region:SetBackdropColor(...) self.backdropColor = { ... } end
  function region:SetBackdropBorderColor(...) self.borderColor = { ... } end
  function region:SetAllPoints(value) self.allPoints = value end
  function region:SetPoint(...) self.point = { ... } end
  function region:GetPoint() return unpack(self.point) end
  function region:ClearAllPoints() self.point = {} end
  function region:SetSize(width, height) self.width, self.height = width, height end
  function region:GetSize() return self.width, self.height end
  function region:GetWidth() return self.width end
  function region:GetHeight() return self.height end
  function region:SetWidth(value) self.width = value end
  function region:SetHeight(value) self.height = value end
  function region:SetFrameStrata(value) self.strata = value end
  function region:SetClampedToScreen(value) self.clamped = value end
  function region:SetMovable(value) self.movable = value end
  function region:SetResizable(value) self.resizable = value end
  function region:SetResizeBounds(...) self.resizeBounds = { ... } end
  function region:SetScale(value) self.scale = value end
  function region:EnableMouse(value) self.mouse = value end
  function region:RegisterForDrag(...) self.dragButtons = { ... } end
  function region:SetScript(name, callback) self.scripts[name] = callback end
  function region:SetShown(value) self.shown = value end
  function region:IsShown() return self.shown end
  function region:Show() self.shown = true end
  function region:Hide() self.shown = false end
  function region:StartMoving() self.moving = true end
  function region:StopMovingOrSizing() self.moving = false; self.sizing = false end
  function region:StartSizing(value) self.sizing = value end
  function region:SetTexture(value) self.texture = value end
  function region:SetTexCoord(...) self.texCoord = { ... } end
  function region:SetVertexColor(...) self.vertex = { ... } end
  function region:SetColorTexture(...) self.color = { ... } end
  function region:SetText(value) self.text = value end
  function region:SetFont(...) self.font = { ... }; return true end
  function region:SetTextColor(...) self.textColor = { ... } end
  function region:CreateTexture()
    return newRegion("Texture", nil, self)
  end
  function region:CreateFontString()
    return newRegion("FontString", nil, self)
  end
  function region:RegisterEvent(event)
    registeredEvents[event] = true
  end
  function region:RegisterUnitEvent(event, unit)
    registeredUnitEvents[event] = unit
  end
  frames[#frames + 1] = region
  if name then _G[name] = region end
  return region
end

function canaccessvalue(value) return not rawequal(value, SECRET) end
function issecretvalue(value) return rawequal(value, SECRET) end
function InCombatLockdown() return combat end
function GetTime() return now end
function UnitAttackSpeed()
  if speedMode == "secret" then return SECRET, SECRET end
  if speedMode == "main_only" then return 2.6, nil end
  if speedMode == "dual" then return 2.6, 1.8 end
  return nil, nil
end

STANDARD_TEXT_FONT = "standard"
UIParent = newRegion("Frame", "UIParent")
SlashCmdList = {}
Settings = nil
EventUtil = nil

function CreateFrame(objectType, name, parent)
  return newRegion(objectType, name, parent)
end

local ns = {}
assert(loadfile("core.lua"))("SwingBarMidnight", ns)
local runtime = assert(ns.Runtime)
local state = runtime.GetState()
local mainFrame = assert(runtime.GetFrame())
local barMH = assert(_G.SwingBarMidnightBarMH)
local barOH = assert(_G.SwingBarMidnightBarOH)

assertEq(state.mhPeriod, nil, "secret MH must remain unavailable")
assertEq(state.ohPeriod, nil, "secret OH must remain unavailable")
assertEq(state.mhStatus, "inaccessible", "secret MH status")
assertEq(state.ohStatus, "inaccessible", "secret OH status")
assertEq(registeredEvents.UNIT_AURA, nil, "UNIT_AURA must not be registered")
assertEq(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, nil, "glow event must not be registered")
assertEq(registeredEvents.ACTIONBAR_SLOT_CHANGED, nil, "action bar scan trigger must not be registered")
assertEq(registeredUnitEvents.UNIT_ATTACK_SPEED, "player", "speed event owner")

local eventFrame
local updater
for _, frame in ipairs(frames) do
  if frame.scripts.OnEvent and frame.events == nil then
    -- event ownership is identified by the RegisterEvent side effects below.
  end
  if frame.scripts.OnUpdate then updater = frame end
end
for _, frame in ipairs(frames) do
  if frame.scripts.OnEvent and frame ~= updater then eventFrame = frame end
end
assert(eventFrame, "event frame missing")
assert(updater, "visual updater missing")

speedMode = "main_only"
now = 110
eventFrame.scripts.OnEvent(eventFrame, "UNIT_ATTACK_SPEED", "player")
assertEq(state.mhPeriod, 2.6, "accessible MH period")
assertEq(state.ohPeriod, nil, "absent OH period")
assertEq(state.ohStatus, "absent", "absent OH status")
assertEq(barOH.shown, false, "OH bar should be hidden by default")

SwingBarMidnightDB.showOnlyInCombat = false
SwingBarMidnightDB.text = true
ns.ApplySettings()
updater.scripts.OnUpdate(updater, 0.03)
assert(barMH.text:match("MH predicted"), "MH text must disclose prediction")

SwingBarMidnightDB.showOffhand = true
speedMode = "dual"
now = 120
ns.ApplySettings()
assertEq(state.mhPeriod, 2.6, "dual MH period")
assertEq(state.ohPeriod, 1.8, "dual OH period")
assertEq(barOH.shown, true, "OH bar not shown for accessible dual wield")
assertEq(mainFrame.height, SwingBarMidnightDB.height * 2 + 4, "dual layout height")

local previousOrigin = state.t0MH
now = 125
ns.ResetBarPhase("test reset")
assertEq(state.t0MH, 125, "manual phase reset")
assertEq(state.t0OH, 125, "manual OH phase reset")
assert(previousOrigin ~= state.t0MH, "phase origin did not change")
assertEq(state.phaseReason, "test reset", "phase reason")

local oldWidth = mainFrame.width
SwingBarMidnightDB.width = 500
combat = true
assertEq(ns.ApplySettings(), false, "combat apply must defer")
assertEq(mainFrame.width, oldWidth, "frame width changed in combat")
assertEq(state.pendingApply, true, "pending apply flag")
combat = false
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assertEq(state.pendingApply, false, "pending apply did not clear")
assertEq(mainFrame.width, 500, "deferred width did not apply")

speedMode = "secret"
now = 130
eventFrame.scripts.OnEvent(eventFrame, "UNIT_ATTACK_SPEED", "player")
assertEq(state.mhPeriod, nil, "secret transition reused stale MH speed")
updater.scripts.OnUpdate(updater, 0.03)
assert(barMH.text:match("unavailable"), "unavailable speed must be visible")

print("PASS: inaccessible speeds never receive a fake fallback; MH/OH cadence is explicitly predicted and settings defer in combat")
