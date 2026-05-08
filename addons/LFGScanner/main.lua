--[[
  LFGScanner.main
  Sklejka: eventy, slash, periodic update, persistence DB.
]]

local A = LFGScanner
local UI = A.UI
local AG = A.Aggregator
local P = A.Parser

-- Kanaly z ktorych bierzemy wiadomosci. Dopasowanie po lowercase substring.
local TRACKED_PATTERNS = {
  "general",
  "global",
  "trade",
  "world",
  "lookingforgroup",
  "lfg",
}

local function channelMatches(channelName)
  if not channelName then return false end
  local lower = channelName:lower()
  for _, pat in ipairs(TRACKED_PATTERNS) do
    if lower:find(pat, 1, true) then return true end
  end
  return false
end

local function ensureDB()
  if type(LFGScannerDB) ~= "table" then LFGScannerDB = {} end
  A.shallowMerge(LFGScannerDB, A.DB_DEFAULTS)
  A.db = LFGScannerDB
end

-- =============================================================
-- Event handler
-- =============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == A.NAME then
      ensureDB()
    end

  elseif event == "PLAYER_LOGIN" then
    ensureDB()
    A.state.login_time = A.now()
    UI.Init()
    UI.Refresh()
    A.print(("v%s loaded. /lfg show|hide|reset|stats"):format(A.VERSION))

  elseif event == "CHAT_MSG_CHANNEL" then
    -- WotLK: msg, author, language, channelString, target, flags, zoneChannelID,
    -- channelIndex, channelBaseName, unused, lineID, guid
    local msg, author, _lang, channelString, _target, _flags, _zone, _ci, channelBaseName = ...
    local nameToCheck = channelBaseName
    if (not nameToCheck or nameToCheck == "") and channelString then
      nameToCheck = channelString:match("^([^-]+)") or channelString
      nameToCheck = (nameToCheck:gsub("%s+$", ""))
    end
    if not channelMatches(nameToCheck) and not channelMatches(channelString) then
      return
    end

    local parsed = P.parse(msg, author)
    AG.ingest(parsed, channelBaseName or channelString or "?", A.now())
    UI.Refresh()
  end
end)

-- =============================================================
-- Periodic tick (lifecycle + UI age refresh)
-- =============================================================

local LIFECYCLE_INTERVAL = 5.0  -- AG.tick: status active/inactive/drop
local UI_REFRESH_INTERVAL = 1.0 -- UI.Refresh: kolumna Age + status alpha
local lifecycle_acc, refresh_acc = 0, 0

frame:SetScript("OnUpdate", function(self, elapsed)
  lifecycle_acc = lifecycle_acc + elapsed
  refresh_acc = refresh_acc + elapsed

  if lifecycle_acc >= LIFECYCLE_INTERVAL then
    lifecycle_acc = 0
    AG.tick(A.now())
  end

  if refresh_acc >= UI_REFRESH_INTERVAL then
    refresh_acc = 0
    if UI.frame and UI.frame:IsShown() then
      UI.Refresh()
    end
  end
end)

-- =============================================================
-- Slash commands
-- =============================================================

SLASH_LFGSCANNER1 = "/lfg"

SlashCmdList["LFGSCANNER"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "show" or msg == "toggle" then
    UI.Toggle()
  elseif msg == "hide" then
    UI.Hide()
  elseif msg == "reset" then
    AG.reset()
    UI.Refresh()
    A.print("Active raids cleared.")
  elseif msg == "stats" then
    A.print(("Tracked raids: %d"):format(AG.count()))
  elseif msg == "resetpos" then
    A.db.ui.point = "CENTER"; A.db.ui.rel_x = 0; A.db.ui.rel_y = 0
    A.db.ui.width = 720; A.db.ui.height = 360
    UI.RestoreLayout()
    A.print("Position reset.")
  else
    A.print("Commands: /lfg show|hide|toggle|reset|stats|resetpos")
  end
end
