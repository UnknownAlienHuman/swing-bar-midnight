-- SwingBarMidnight/options.lua
-- Current Blizzard Settings registration for the predicted-cadence runtime.

local ADDON_NAME, ns = ...
local DB = ns.DB
local registered = false
local categoryID

local function Apply()
  if type(ns.ApplySettings) == "function" then ns.ApplySettings() end
end

local function RegisterSettings()
  if registered or not Settings or not Settings.RegisterVerticalLayoutCategory then return false end
  registered = true

  local category = Settings.RegisterVerticalLayoutCategory("SwingBarMidnight")
  categoryID = category:GetID()

  local function Checkbox(variable, key, label, defaultValue, tooltip)
    local setting = Settings.RegisterAddOnSetting(
      category,
      variable,
      key,
      DB,
      Settings.VarType.Boolean,
      label,
      defaultValue
    )
    setting:SetValueChangedCallback(Apply)
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
  end

  local function Slider(variable, key, label, defaultValue, minimum, maximum, step, tooltip)
    local setting = Settings.RegisterAddOnSetting(
      category,
      variable,
      key,
      DB,
      Settings.VarType.Number,
      label,
      defaultValue
    )
    setting:SetValueChangedCallback(Apply)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    Settings.CreateSlider(category, setting, options, tooltip)
    return setting
  end

  Checkbox(
    "SWING_BAR_MIDNIGHT_ENABLED",
    "enabled",
    "Enabled",
    true,
    "Show the predicted melee cadence bar."
  )
  Checkbox(
    "SWING_BAR_MIDNIGHT_COMBAT_ONLY",
    "showOnlyInCombat",
    "Show only in combat",
    true,
    "Hide the bar outside combat."
  )
  Checkbox(
    "SWING_BAR_MIDNIGHT_LOCKED",
    "locked",
    "Locked",
    true,
    "Disable drag and resize controls."
  )
  Checkbox(
    "SWING_BAR_MIDNIGHT_OFFHAND",
    "showOffhand",
    "Show separate off-hand prediction",
    false,
    "Show independent MH and OH predictions. The addon does not claim the real hand offset."
  )
  Checkbox(
    "SWING_BAR_MIDNIGHT_TEXT",
    "text",
    "Show remaining-time text",
    true,
    "Label values as predicted rather than actual swing-hit timestamps."
  )

  Slider("SWING_BAR_MIDNIGHT_WIDTH", "width", "Width", 260, 120, 900, 1, "Bar width in UI units.")
  Slider("SWING_BAR_MIDNIGHT_HEIGHT", "height", "Per-hand height", 12, 8, 60, 1, "Height of each MH/OH bar.")
  Slider("SWING_BAR_MIDNIGHT_SCALE", "scale", "Scale", 1, 0.60, 3.00, 0.05, "Scale the complete frame.")
  Slider("SWING_BAR_MIDNIGHT_FONT_SIZE", "fontSize", "Font size", 10, 6, 40, 1, "Remaining-time label size.")
  Slider("SWING_BAR_MIDNIGHT_BG_ALPHA", "bgAlpha", "Background alpha", 0.35, 0, 1, 0.05, "Background opacity.")
  Slider("SWING_BAR_MIDNIGHT_BORDER_ALPHA", "borderAlpha", "Border alpha", 0.75, 0, 1, 0.05, "Border opacity.")

  Settings.RegisterAddOnCategory(category)
  return true
end

function ns.OpenOptions()
  if not registered then RegisterSettings() end
  if Settings and categoryID then Settings.OpenToCategory(categoryID) end
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
  EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, RegisterSettings)
else
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:SetScript("OnEvent", function(self)
    if RegisterSettings() then self:UnregisterAllEvents() end
  end)
end
