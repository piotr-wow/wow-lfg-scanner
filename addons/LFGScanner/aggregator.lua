--[[
  LFGScanner.Aggregator
  Holds the active-raid state. Ingests parsed messages, deduplicates them,
  drives the lifecycle (active < 2min, inactive < 5min, drop).
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner
A.Aggregator = A.Aggregator or {}
local AG = A.Aggregator

-- =============================================================
-- Helpers
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

-- Insert / update a raid given the parser output.
-- parsed: table from LFGScanner.Parser.parse(...)
-- channel: name of the channel the message arrived on
-- t: epoch
function AG.ingest(parsed, channel, t)
  if not parsed or parsed.class ~= "LFM_RAID" then return nil end

  local msg_key = parsed.msg_normalized
  if not msg_key or msg_key == "" then return nil end

  -- 1. Multi-officer / repost: identical message -> same raid.
  local id = A.state.by_msg[msg_key]
  if id and A.state.raids[id] then
    return AG.update(A.state.raids[id], parsed, channel, t)
  end

  -- 2. Same author + same raid (e.g. body evolves as roles fill in)
  --    -> same raid, merge.
  if parsed.author and parsed.raid and parsed.raid ~= "?" then
    local ar_key = parsed.author .. "|" .. parsed.raid
    local ar_id = A.state.by_author_raid[ar_key]
    if ar_id and A.state.raids[ar_id] then
      return AG.update(A.state.raids[ar_id], parsed, channel, t)
    end
  end

  -- 3. New raid.
  return AG.create(msg_key, parsed, channel, t)
end

function AG.create(key, parsed, channel, t)
  local id = key  -- for now id = normalized message, kept simple
  local raid = {
    id = id,
    raid = parsed.raid,
    size = parsed.size,
    difficulty = parsed.difficulty,
    progress = { current = parsed.progress_cur, max = parsed.progress_max },
    gs_min = parsed.gs_min,
    gs_strict = parsed.gs_strict,
    role_needs = deepcopy(parsed.role_needs or {}),
    reserves_raw = parsed.reserves_raw,
    reserves_tokens = deepcopy(parsed.reserves_tokens or {}),
    ach_req = deepcopy(parsed.ach_req or {}),
    discord_status = parsed.discord_status or "unknown",
    current_in_group = parsed.current,
    max_in_group = parsed.max,
    posters = {},
    primary_poster = parsed.author,
    at_boss = parsed.at_boss,
    at_boss_num = parsed.at_boss_num,
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

  -- Register the new msg_normalized and (author|raid) against this same raid,
  -- so subsequent entries with that body / from that author land here.
  if parsed.msg_normalized and parsed.msg_normalized ~= "" then
    A.state.by_msg[parsed.msg_normalized] = raid.id
  end
  if parsed.author and parsed.raid and parsed.raid ~= "?" then
    A.state.by_author_raid[parsed.author .. "|" .. parsed.raid] = raid.id
  end

  -- Update mutable fields (someone may change GS/role/current/max in a later post).
  if parsed.current then raid.current_in_group = parsed.current end
  if parsed.max then raid.max_in_group = parsed.max end
  if parsed.role_needs then raid.role_needs = deepcopy(parsed.role_needs) end
  if parsed.gs_min then raid.gs_min = parsed.gs_min end
  if parsed.reserves_raw then
    raid.reserves_raw = parsed.reserves_raw
    raid.reserves_tokens = deepcopy(parsed.reserves_tokens or {})
  end
  if parsed.ach_req then raid.ach_req = deepcopy(parsed.ach_req) end
  if parsed.discord_status and parsed.discord_status ~= "unknown" then
    -- Update only if we have a new concrete value (req or not_req).
    -- "unknown" in a new entry must not overwrite a prior known state.
    raid.discord_status = parsed.discord_status
  elseif raid.discord_status == nil then
    raid.discord_status = parsed.discord_status or "unknown"
  end
  if parsed.at_boss then
    raid.at_boss = parsed.at_boss
    raid.at_boss_num = parsed.at_boss_num
  end
  if parsed.raw_message then raid.raw_message = parsed.raw_message end
  raid.status = "active"
  return raid
end

-- Lifecycle tick. Called every few seconds.
function AG.tick(now)
  local removed = {}
  local active_max = A.LIFECYCLE.ACTIVE_MAX_AGE
  local inactive_max = A.LIFECYCLE.INACTIVE_MAX_AGE

  for id, raid in pairs(A.state.raids) do
    local age = now - (raid.last_seen or now)
    if age > inactive_max then
      A.state.raids[id] = nil
      -- Clear every index pointing at this id
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

-- Build the UI list - sorted stably by `first_seen` ASC.
-- We do not sort by `last_seen` because then every repost of the same posting
-- would bump the raid to the top and shift every other row down - the user
-- loses their target under the cursor. `first_seen` is stable for the entire
-- life of the raid, so the position doesn't change on updates. New raids land
-- at the bottom; nothing existing slides upward.
function AG.list(filters)
  filters = filters or {}
  local out = {}
  for _, raid in pairs(A.state.raids) do
    if not (filters.hide_inactive and raid.status == "inactive") then
      table.insert(out, raid)
    end
  end
  table.sort(out, function(a, b)
    local fa, fb = a.first_seen or 0, b.first_seen or 0
    if fa ~= fb then return fa < fb end
    return (a.id or "") < (b.id or "")  -- tie-break: stable on id
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

-- Pull a previously-saved snapshot back into A.state, then run a tick to drop
-- anything that has aged out while we were away. Returns the number of raids
-- still alive after pruning.
function AG.hydrate(saved, now)
  if type(saved) ~= "table" then return 0 end
  if type(saved.raids) ~= "table" then return 0 end

  for id, raid in pairs(saved.raids) do
    if type(raid) == "table" and raid.id then
      A.state.raids[id] = raid
    end
  end
  if type(saved.by_msg) == "table" then
    for k, v in pairs(saved.by_msg) do
      if A.state.raids[v] then A.state.by_msg[k] = v end
    end
  end
  if type(saved.by_author_raid) == "table" then
    for k, v in pairs(saved.by_author_raid) do
      if A.state.raids[v] then A.state.by_author_raid[k] = v end
    end
  end

  AG.tick(now or A.now())
  return AG.count()
end
