--[[
  LFGScanner - core / namespace.
  Initializes the addon's global table and shared utilities.
  Other modules (parser, aggregator, ui, main) attach themselves as fields.
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner

A.NAME = "LFGScanner"
A.VERSION = "0.2.0"

A.LIFECYCLE = {
  ACTIVE_MAX_AGE = 2 * 60,    -- silence > 2 min -> row greys out (inactive)
  INACTIVE_MAX_AGE = 5 * 60,  -- silence > 5 min -> row drops from the list
}

-- runtime cache (not persisted)
A.state = {
  raids = {},            -- aggregator: id -> ActiveRaid
  by_msg = {},           -- msg_normalized -> id (multi-officer dedup)
  by_author_raid = {},   -- "author|raid" -> id (dedup of the same author's evolving LFM)
  login_time = 0,        -- set on PLAYER_LOGIN
}

-- SavedVariables defaults
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
  -- Snapshot of A.state taken at PLAYER_LOGOUT, restored at PLAYER_LOGIN
  -- (and immediately pruned by AG.tick, so anything older than INACTIVE_MAX_AGE
  -- drops on its own).
  persisted = {
    saved_at = 0,
    raids = {},
    by_msg = {},
    by_author_raid = {},
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
