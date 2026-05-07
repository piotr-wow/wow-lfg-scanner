--[[
  LFGScanner.Aggregator
  Trzyma stan aktywnych raidow. Zbiera parsed messages, dedupuje,
  obsluguje lifecycle (active < 5min, inactive < 10min, drop).
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner
A.Aggregator = A.Aggregator or {}
local AG = A.Aggregator

-- =============================================================
-- Pomocnicze
-- =============================================================

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepcopy(v) end
  return out
end

local function setHas(set, key)
  return set[key] ~= nil and set[key] ~= false
end

-- =============================================================
-- API
-- =============================================================

-- Wstaw / zaktualizuj raid na podstawie wyniku parsera.
-- parsed: tabela z LFGScanner.Parser.parse(...)
-- channel: nazwa kanalu na ktorym wyladowala wiadomosc
-- t: epoch
function AG.ingest(parsed, channel, t)
  if not parsed or parsed.class ~= "LFM_RAID" then return nil end

  local msg_key = parsed.msg_normalized
  if not msg_key or msg_key == "" then return nil end

  -- 1. Multi-officer / repost: identyczna wiadomosc -> ten sam raid.
  local id = A.state.by_msg[msg_key]
  if id and A.state.raids[id] then
    return AG.update(A.state.raids[id], parsed, channel, t)
  end

  -- 2. Ten sam autor + ten sam raid (np. tresc ewoluuje gdy zapelniaja sie role)
  --    -> ten sam raid, mergujemy.
  if parsed.author and parsed.raid and parsed.raid ~= "?" then
    local ar_key = parsed.author .. "|" .. parsed.raid
    local ar_id = A.state.by_author_raid[ar_key]
    if ar_id and A.state.raids[ar_id] then
      return AG.update(A.state.raids[ar_id], parsed, channel, t)
    end
  end

  -- 3. Nowy raid.
  return AG.create(msg_key, parsed, channel, t)
end

function AG.create(key, parsed, channel, t)
  local id = key  -- jak narazie id = znormalizowana wiadomosc, prosto
  local raid = {
    id = id,
    raid = parsed.raid,
    size = parsed.size,
    difficulty = parsed.difficulty,
    progress = { current = parsed.progress_cur, max = parsed.progress_max, fresh = parsed.fresh },
    gs_min = parsed.gs_min,
    gs_strict = parsed.gs_strict,
    role_needs = deepcopy(parsed.role_needs or {}),
    reserves_raw = parsed.reserves_raw,
    reserves_tokens = deepcopy(parsed.reserves_tokens or {}),
    ach_req = deepcopy(parsed.ach_req or {}),
    current_in_group = parsed.current,
    max_in_group = parsed.max,
    posters = {},
    primary_poster = parsed.author,
    actual_leader = parsed.actual_leader,
    channels = {},
    first_seen = t,
    last_seen = t,
    posts_count = 1,
    raw_message = parsed.raw_message,
    classified_as = parsed.class,
    status = "active",
  }
  if parsed.author then raid.posters[parsed.author] = true end
  if channel then raid.channels[channel] = true end

  A.state.raids[id] = raid
  A.state.by_msg[key] = id
  if parsed.author and parsed.raid and parsed.raid ~= "?" then
    A.state.by_author_raid[parsed.author .. "|" .. parsed.raid] = id
  end
  return raid
end

function AG.update(raid, parsed, channel, t)
  raid.last_seen = t
  raid.posts_count = (raid.posts_count or 0) + 1
  if parsed.author then raid.posters[parsed.author] = true end
  if channel then raid.channels[channel] = true end

  -- Zarejestruj nowy msg_normalized i (author|raid) do tego samego raida,
  -- zeby nastepne wpisy z taka sama trescia / od tego autora trafialy tu.
  if parsed.msg_normalized and parsed.msg_normalized ~= "" then
    A.state.by_msg[parsed.msg_normalized] = raid.id
  end
  if parsed.author and parsed.raid and parsed.raid ~= "?" then
    A.state.by_author_raid[parsed.author .. "|" .. parsed.raid] = raid.id
  end

  -- Aktualizuj zmienialne pola (ktos moze zmienic GS/role/current/max w kolejnym wpisie).
  if parsed.current then raid.current_in_group = parsed.current end
  if parsed.max then raid.max_in_group = parsed.max end
  if parsed.role_needs then raid.role_needs = deepcopy(parsed.role_needs) end
  if parsed.gs_min then raid.gs_min = parsed.gs_min end
  if parsed.reserves_raw then
    raid.reserves_raw = parsed.reserves_raw
    raid.reserves_tokens = deepcopy(parsed.reserves_tokens or {})
  end
  if parsed.ach_req then raid.ach_req = deepcopy(parsed.ach_req) end
  if parsed.actual_leader and not raid.actual_leader then
    raid.actual_leader = parsed.actual_leader
  end
  if parsed.raw_message then raid.raw_message = parsed.raw_message end
  raid.status = "active"
  return raid
end

-- Lifecycle tick. Wywolywany co kilka sekund.
function AG.tick(now)
  local removed = {}
  local active_max = A.LIFECYCLE.ACTIVE_MAX_AGE
  local inactive_max = A.LIFECYCLE.INACTIVE_MAX_AGE

  for id, raid in pairs(A.state.raids) do
    local age = now - (raid.last_seen or now)
    if age > inactive_max then
      A.state.raids[id] = nil
      -- Wyczysc wszystkie indeksy wskazujace na ten id
      for k, v in pairs(A.state.by_msg) do
        if v == id then A.state.by_msg[k] = nil end
      end
      for k, v in pairs(A.state.by_author_raid) do
        if v == id then A.state.by_author_raid[k] = nil end
      end
      table.insert(removed, id)
    elseif age > active_max then
      raid.status = "inactive"
    else
      raid.status = "active"
    end
  end
  return removed
end

-- Pobierz liste do UI - posortowana po last_seen DESC, wedlug filtrow.
function AG.list(filters)
  filters = filters or {}
  local out = {}
  for _, raid in pairs(A.state.raids) do
    if not (filters.hide_inactive and raid.status == "inactive") then
      table.insert(out, raid)
    end
  end
  table.sort(out, function(a, b)
    if a.status ~= b.status then
      return a.status == "active"  -- active na gorze
    end
    return (a.last_seen or 0) > (b.last_seen or 0)
  end)
  return out
end

function AG.reset()
  A.state.raids = {}
  A.state.by_msg = {}
  A.state.by_author_raid = {}
end

function AG.count()
  local n = 0
  for _ in pairs(A.state.raids) do n = n + 1 end
  return n
end
