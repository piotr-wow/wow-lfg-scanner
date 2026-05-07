--[[
  LFGScannerLogger
  Zapisuje wpisy z wybranych kanalow chatu do SavedVariables (LFGScannerLoggerDB).
  Cel: zebrac realne dane LFM z /global i /general (Dalaran) do analizy off-line,
  zanim zbudujemy wlasciwy parser raidow.
]]

local ADDON_NAME = "LFGScannerLogger"

-- Wzorce nazw kanalow ktore logujemy. Porownanie po lowercase, dopasowanie czesciowe,
-- wiec "General - Dalaran" dopasuje "general", a customowy "Global" dopasuje "global".
local TRACKED_PATTERNS = {
  "general",
  "global",
  "trade",
  "world",
  "lookingforgroup",
  "lfg",
}

-- Maks. liczba wpisow trzymanych w DB (zeby plik nie urosl bez konca).
local MAX_ENTRIES = 50000

local frame = CreateFrame("Frame")

local function ensureDB()
  if type(LFGScannerLoggerDB) ~= "table" then
    LFGScannerLoggerDB = {}
  end
  if type(LFGScannerLoggerDB.entries) ~= "table" then
    LFGScannerLoggerDB.entries = {}
  end
  if type(LFGScannerLoggerDB.sessions) ~= "table" then
    LFGScannerLoggerDB.sessions = {}
  end
  if type(LFGScannerLoggerDB.meta) ~= "table" then
    LFGScannerLoggerDB.meta = { version = 1 }
  end
end

local function channelMatches(channelName)
  if not channelName then return false end
  local lower = channelName:lower()
  for _, pat in ipairs(TRACKED_PATTERNS) do
    if lower:find(pat, 1, true) then
      return true
    end
  end
  return false
end

local function nowEpoch()
  -- time() zwraca uniksowy timestamp (sekundy). date("%H:%M:%S") czytelnie.
  return time()
end

local function startSession()
  local realm = GetRealmName() or "?"
  local player = UnitName("player") or "?"
  local zone = GetRealZoneText() or ""
  local session = {
    started_at = nowEpoch(),
    realm = realm,
    player = player,
    zone_at_login = zone,
    client_locale = GetLocale(),
  }
  table.insert(LFGScannerLoggerDB.sessions, session)
  LFGScannerLoggerDB.current_session_index = #LFGScannerLoggerDB.sessions
  return session
end

local function pruneIfNeeded()
  local entries = LFGScannerLoggerDB.entries
  local n = #entries
  if n <= MAX_ENTRIES then return end
  local toRemove = n - MAX_ENTRIES
  -- Usun najstarsze (z poczatku tablicy).
  for i = 1, n do
    entries[i] = entries[i + toRemove]
  end
end

local function logEntry(msg, author, channelString, channelBaseName, channelIndex, zoneChannelID, guid)
  ensureDB()
  local entry = {
    t = nowEpoch(),                         -- epoch seconds
    s = LFGScannerLoggerDB.current_session_index, -- session index
    a = author,                             -- "Player-Realm" lub "Player"
    c = channelBaseName or channelString,   -- np. "General" / "global"
    cs = channelString,                     -- pelna nazwa np. "General - Dalaran"
    ci = channelIndex,                      -- numer kanalu w UI
    z = GetRealZoneText() or "",            -- biezaca strefa gracza
    m = msg,                                -- tresc
    g = guid,                               -- GUID nadawcy (jak dostepny)
  }
  table.insert(LFGScannerLoggerDB.entries, entry)
  pruneIfNeeded()
end

local function onChatMsgChannel(...)
  -- WotLK 3.3.5a sygnatura:
  -- msg, author, language, channelString, target, flags, zoneChannelID,
  -- channelIndex, channelBaseName, unused, lineID, guid
  local msg, author, _language, channelString, _target, _flags, zoneChannelID,
        channelIndex, channelBaseName, _unused, _lineID, guid = ...

  local nameToCheck = channelBaseName
  if not nameToCheck or nameToCheck == "" then
    -- fallback: spróbuj wyciagnac z channelString przed " - "
    if channelString then
      local base = channelString:match("^([^-]+)")
      if base then nameToCheck = base:gsub("%s+$", "") end
    end
  end

  if not channelMatches(nameToCheck) and not channelMatches(channelString) then
    return
  end

  logEntry(msg, author, channelString, nameToCheck, channelIndex, zoneChannelID, guid)
end

local function printStats()
  ensureDB()
  local entries = LFGScannerLoggerDB.entries
  local total = #entries
  local perChannel = {}
  for i = 1, total do
    local c = entries[i].c or "?"
    perChannel[c] = (perChannel[c] or 0) + 1
  end
  DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[LFGLog]|r Total entries: %d"):format(total))
  for c, n in pairs(perChannel) do
    DEFAULT_CHAT_FRAME:AddMessage(("  %s: %d"):format(c, n))
  end
  if total > 0 then
    local last = entries[total]
    DEFAULT_CHAT_FRAME:AddMessage(("  Last: [%s] %s: %s"):format(
      date("%H:%M:%S", last.t), tostring(last.a), tostring(last.m):sub(1, 60)))
  end
end

local function clearDB()
  LFGScannerLoggerDB.entries = {}
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[LFGLog]|r Entries cleared.")
end

SLASH_LFGLOG1 = "/lfglog"
SlashCmdList["LFGLOG"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "clear" then
    clearDB()
  elseif msg == "stats" or msg == "" then
    printStats()
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[LFGLog]|r commands: /lfglog stats | /lfglog clear")
  end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON_NAME then
      ensureDB()
    end
  elseif event == "PLAYER_LOGIN" then
    ensureDB()
    startSession()
    DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[LFGLog]|r Logging active. Tracked: %s. Use /lfglog."):format(
      table.concat(TRACKED_PATTERNS, ", ")))
  elseif event == "CHAT_MSG_CHANNEL" then
    onChatMsgChannel(...)
  end
end)
