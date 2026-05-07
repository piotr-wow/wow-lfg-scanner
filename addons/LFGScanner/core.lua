--[[
  LFGScanner - core / namespace.
  Inicjalizuje globalna tablice addonu i wspolne utilsy.
  Pozostale moduly (parser, aggregator, ui, main) doczepiaja sie jako pola.
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner

A.NAME = "LFGScanner"
A.VERSION = "0.1.0"

A.LIFECYCLE = {
  ACTIVE_MAX_AGE = 2 * 60,    -- ponad 2 min ciszy -> wiersz szarzeje (inactive)
  INACTIVE_MAX_AGE = 5 * 60,  -- ponad 5 min ciszy -> wiersz znika z listy
}

-- runtime cache (nie persystowany)
A.state = {
  raids = {},            -- aggregator: id -> ActiveRaid
  by_msg = {},           -- msg_normalized -> id (dedup multi-officer)
  by_author_raid = {},   -- "author|raid" -> id (dedup tego samego autora ewoluujacego LFM)
  login_time = 0,        -- ustawiane w PLAYER_LOGIN
}

-- defaulty SavedVariables
A.DB_DEFAULTS = {
  meta = { version = 1 },
  ui = {
    point = "CENTER", rel_x = 0, rel_y = 0, width = 820, height = 360, shown = true,
    selected_tab = "ALL",
  },
  filters = {
    show_inactive = true,
    hide_boost = true,
    blacklist_authors = {},
  },
}

function A.print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[LFG]|r " .. tostring(msg))
end

function A.shallowMerge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      A.shallowMerge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

function A.now()
  return time()
end

function A.formatAge(seconds)
  if seconds < 60 then return string.format("0:%02d", seconds) end
  local m = math.floor(seconds / 60)
  local s = seconds % 60
  return string.format("%d:%02d", m, s)
end

function A.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
