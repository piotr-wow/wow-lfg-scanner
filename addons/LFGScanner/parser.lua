--[[
  LFGScanner.Parser
  Pure classification + field-extraction logic for chat messages.
  Heuristics documented in docs/PARSING.md.
  Designed to be testable without WoW APIs (uses only string/table/math).
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner
A.Parser = A.Parser or {}
local P = A.Parser

-- =============================================================
-- Dictionaries
-- =============================================================

-- Raid patterns. Order matters: longer / more specific first.
-- { lua_pattern, normalized_name, size, default_difficulty }
P.RAID_PATTERNS = {
  -- ICC reverse-order ("10man ICC", "25 ICC") - must come before bare icc patterns
  { "10%s*man%s*icc",    "ICC10",   10, "NM" },
  { "25%s*man%s*icc",    "ICC25",   25, "NM" },
  { "10%s+icc",          "ICC10",   10, "NM" },
  { "25%s+icc",          "ICC25",   25, "NM" },
  -- ICC (most common)
  { "icc%s*25%s*hc",     "ICC25HC", 25, "HC" },
  { "icc%-25%-hc",       "ICC25HC", 25, "HC" },
  { "icc25hc",           "ICC25HC", 25, "HC" },
  { "icc%s*25%s*nm",     "ICC25",   25, "NM" },
  { "icc%s*25",          "ICC25",   25, "NM" },
  { "icc25",             "ICC25",   25, "NM" },
  { "icc%s*10%s*hc",     "ICC10HC", 10, "HC" },
  { "icc%s*10%s*nm",     "ICC10",   10, "NM" },
  { "icc%s*10",          "ICC10",   10, "NM" },
  { "icc10",             "ICC10",   10, "NM" },
  { "icc%s*flex",        "ICC10",   10, "NM" },
  -- TOGC (before TOC so it doesn't match "toc")
  { "togc%s*25",         "TOGC25",  25, "HC" },
  { "togc%s*10",         "TOGC10",  10, "HC" },
  { "togc25",            "TOGC25",  25, "HC" },
  { "togc",              "TOGC25",  25, "HC" },
  -- TOC
  { "toc%s*25%s*hc",     "TOC25HC", 25, "HC" },
  { "toc%s*25%s*nm",     "TOC25",   25, "NM" },
  { "toc%s*25",          "TOC25",   25, "NM" },
  { "toc%s*10%s*hc",     "TOC10HC", 10, "HC" },
  { "toc%s*10",          "TOC10",   10, "NM" },
  { "toc25",             "TOC25",   25, "NM" },
  { "toc10",             "TOC10",   10, "NM" },
  -- RS
  { "rs%s*25%s*hc",      "RS25HC",  25, "HC" },
  { "rs%s*25%s*nm",      "RS25",    25, "NM" },
  { "rs25%s*nm",         "RS25",    25, "NM" },
  { "rs25hc",            "RS25HC",  25, "HC" },
  { "rs25",              "RS25",    25, "NM" },
  { "rs%s*25",           "RS25",    25, "NM" },
  { "rs%s*10%s*hc",      "RS10HC",  10, "HC" },
  { "rs%s*10",           "RS10",    10, "NM" },
  { "rs10",              "RS10",    10, "NM" },
  -- VOA
  { "voa%s*25",          "VOA25",   25, "NM" },
  { "voa%s*10",          "VOA10",   10, "NM" },
  { "voa25",             "VOA25",   25, "NM" },
  { "voa10",             "VOA10",   10, "NM" },
  { "voa",               "VOA25",   25, "NM" },
  -- Others
  { "ulduar%s*10",       "ULDUAR10", 10, "NM" },
  { "ulduar%s*25",       "ULDUAR",  25, "NM" },
  { "ulduar",            "ULDUAR",  25, "NM" },
  { "naxx",              "NAXX",    25, "NM" },
  { "os%s*25",           "OS25",    25, "NM" },
  { "os%s*10",           "OS10",    10, "NM" },
  { "lod",               "LOD",     25, "HC" },
  { "bane",              "BANE",    25, "HC" },
}

-- Role tokens (plain strings, exact match per word).
P.ROLE_TOKENS = {
  TANK   = { "tank", "tanks", "mt", "ot", "prot", "bdk", "bear", "ppal", "pwar" },
  HEAL   = { "heal", "heals", "healer", "healers", "hpala", "disco", "discp", "holy", "hpriest", "rsham", "hdruid", "hpal" },
  MELEE  = { "melee", "mdps", "fwar", "ret", "rogue", "rogues", "rog", "enha", "fdk", "kit", "feral" },
  RANGED = { "ranged", "rdps", "boomy", "hunter", "hunters", "hunt", "mage", "mages", "sp", "spriest", "demo", "affli", "ele", "lock", "locks", "warlock" },
  DPS    = { "dps", "dd" },
}

-- Negative signals against LFM_RAID. If any matches, classifier won't pick LFM.
P.NEGATIVE_PATTERNS = {
  "wts%s", "^wts", " wtb ", "^wtb",
  "selling%s", "^selling",
  " boost ", "^boost", "boosting%s+guild",
  "%scarry%s",
  "gdkp",
  "recruiting",
  "regrutira",
  "rekrutuje",
  "looking%s+for%s+raiders",
  "looking%s+for%s+active",
}

-- Positive signals for LFM_RAID.
P.POSITIVE_PATTERNS = {
  "^lfm[%s%-#]", "^#lfm", "%slfm[%s%-]", "^lfm$",
  "^#%d",                           -- "#2 ICC25 8/12HC ...", "#2LFM TOC ..."
  "^lf%s",                          -- "LF tank", "LF healer"
  "%(%d+/%d+%)",                    -- (21/25)
  "/w%s+me", "pst%s+me", "pst%s+for", "whisper%s+me",
  "last%s+spot", "last%s+%d+%s+spot",
  "fresh%s+%d+/", "fresh%s+run",
  "need%s+%d", "need%s+all", "%sneed%s",
}

-- =============================================================
-- Helpers
-- =============================================================

function P.stripWoWLinks(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  -- |H...|h[Name]|h -> [Name]
  s = s:gsub("|H[^|]+|h(%[[^%]]+%])|h", "%1")
  return s
end

function P.normalize(s)
  s = P.stripWoWLinks(s or "")
  s = s:lower()
  s = s:gsub("[%[%]%(%)%-%_%*%!%?%.%,%:%;]", " ")
  s = s:gsub("%s+", " ")
  s = (s:gsub("^%s+", ""):gsub("%s+$", ""))
  s = s:gsub("^#%d+%s*", "")
  s = s:gsub("%s+%d+%s*/%s*%d+%s*$", "")
  return s:sub(1, 100)
end

-- =============================================================
-- Language filter (we accept English only)
-- =============================================================

-- Language tags that mark non-English content.
P.NON_EN_LANG_TAGS = {
  "%[ru%]", "%[rus%]", "%[de%]", "%[ger%]", "%[fr%]", "%[fra%]",
  "%[es%]", "%[esp%]", "%[br%]", "%[pt%]", "%[pl%]",
  "%[balkan%]", "%[sr%]", "%[srb%]", "%[bs%]", "%[hr%]",
  "%[bg%]", "%[ge%]", "%[gr%]", "%[it%]", "%[tr%]", "%[cn%]",
}

-- Words characteristic of non-English content.
P.NON_EN_KEYWORDS = {
  -- DE
  "wir%s+sind", "wöchent", "deutsch", "raiden", "mitspielern",
  "individuell", "miteinander", "freundlich", "gilde",
  -- Balkan/SR/HR/BS
  "regrutira", "regrutiranje", "igrace", "igraci", "aktivne",
  "potrebni", "koristimo", "dopunili", "dobrodosli", "raidu",
  "balkan", "srpsk", "bosansk", "hrvatsk", "discord%s*je",
  -- PL
  "rekrutuje", "rekrutacja", "szukamy",
  -- RU/CYR translit (characteristic fragments)
  "pyc[ck][ko]", "rycc?ko", "rycc?ka", "npurJI", "npuhuM",
  "ko[Mm]aH", "ack[Oo]B", "rocyga", "umpok",
}

function P.hasNonAsciiBytes(s, threshold)
  threshold = threshold or 5
  local count = 0
  for i = 1, #s do
    if s:byte(i) > 127 then
      count = count + 1
      if count >= threshold then return true end
    end
  end
  return false
end

function P.looksLikeTranslitWord(word)
  -- Cyrillic-as-ASCII looks like:
  -- - a digit between letters in a word: "u9eT", "g9eT", "p9gbI"
  -- - lowercase then uppercase in a >=5 char word: "ruJI", "npurJI", "onblmHblx"
  --
  -- We no longer use the "[A-Z][A-Z][A-Z] mixed with non-letters" rule - it
  -- false-flagged typical LFM tokens: ICC25HC, RS25HC, (B+P+SFS, RES),
  -- GS+SPEC, B+O+P. The result was real LFMs being classified as NON_ENGLISH.
  if word:len() < 4 then return false end
  if word:match("[A-Za-z]%d[A-Za-z]") then return true end
  if word:len() >= 5 and word:match("[a-z][A-Z]") then return true end
  return false
end

function P.isEnglishOnly(raw)
  if not raw or raw == "" then return true end
  local low = raw:lower()

  -- 1. Language tags at start / in header
  for _, tag in ipairs(P.NON_EN_LANG_TAGS) do
    if low:find(tag) then return false end
  end

  -- 2. UTF-8 bytes outside ASCII (Cyrillic, Polish/German/Balkan diacritics)
  if P.hasNonAsciiBytes(raw, 5) then return false end

  -- 3. Marker words for non-English languages
  for _, kw in ipairs(P.NON_EN_KEYWORDS) do
    if low:find(kw) then return false end
  end

  -- 4. Cyrillic-as-ASCII heuristic (translit)
  local translit_count = 0
  for word in raw:gmatch("%S+") do
    if P.looksLikeTranslitWord(word) then
      translit_count = translit_count + 1
      if translit_count >= 3 then return false end
    end
  end

  return true
end

-- =============================================================
-- Classification
-- =============================================================

function P.isItemSell(low, raw)
  local has_item_link = raw:find("|Hitem:") and true or false
  local has_g_stack = low:find("g/stack") and true or false
  if has_g_stack then return true end
  if has_item_link and (low:find("selling") or low:find("wts") or low:find("cod%s")) then
    return true
  end
  if low:match("^selling%s+potions") then return true end
  return false
end

function P.isBoostSell(low)
  if low:match("^wts%s") or low:match("%swts%s") then
    if low:find("boost") or low:find("lod") or low:find("bane") or low:find("rs%s*25") or low:find("togc") then
      return true
    end
    return true
  end
  if low:find("boosting%s+guild") then return true end
  if low:find("boost%s+service") then return true end
  if low:find("dm%s+for%s+details") and low:find("boost") then return true end
  return false
end

function P.isGuildRecruit(low, raw)
  -- Prefix < ... > / > ... < / << ... >> at the start - almost always a guild/boost,
  -- unless we have strong LFM_RAID signals (LFM + (N/M) + Need + raid).
  local prefix_bracket = raw:match("^%s*[<>]") and true or false
  if prefix_bracket then
    local strong_lfm = (
      (low:find("^<.->%s*lfm") or low:find("^>.-<%s*lfm") or low:find("%s+lfm%s")) and
      low:find("%(%d+/%d+%)") and
      (low:find("need%s") or low:find("need,") or low:find("need:") or low:find("^need"))
    ) and true or false
    if not strong_lfm then return true end
  end

  if low:find("recruiting") then return true end  -- "guild recruiting", "<X> recruiting", etc.
  if low:find("recruit%s") then return true end
  if low:find("regrutira") then return true end
  if low:find("rekrutuje") then return true end
  if low:find("looking%s+for%s+raiders") then return true end
  if low:find("looking%s+for%s+active") then return true end
  if low:find("looking%s+for%s+experienced") then return true end
  if low:find("wir%s+sind") and (low:find("gilde") or low:find("raiden")) then return true end
  return false
end

function P.isAchievementRun(low, raw)
  local has_ach_link = raw:find("|Hachievement:") and true or false
  if has_ach_link then
    -- An LFM with (N/M) and a raid name wins - that's still LFM_RAID, the
    -- achievement is a requirement.
    if low:find("%(%d+/%d+%)") then return false end
    if low:find("^lfm") or low:find("%slfm%s") then return false end
    if low:find("^#%d") or low:find("#%d+lfm") then return false end
    return true
  end
  return false
end

function P.findRaid(low)
  for _, entry in ipairs(P.RAID_PATTERNS) do
    if low:find(entry[1]) then
      return entry[2], entry[3], entry[4]
    end
  end
  return nil, nil, nil
end

function P.classify(raw)
  local low = (raw or ""):lower()

  -- Language filter: only English passes into further classification.
  if not P.isEnglishOnly(raw) then return "NON_ENGLISH" end

  if P.isItemSell(low, raw)      then return "ITEM_SELL"       end
  if P.isBoostSell(low)          then return "BOOST_SELL"      end
  if P.isGuildRecruit(low, raw)  then return "GUILD_RECRUIT"   end
  if P.isAchievementRun(low, raw) then return "ACHIEVEMENT_RUN" end

  for _, pat in ipairs(P.NEGATIVE_PATTERNS) do
    if low:find(pat) then return "OTHER" end
  end

  local positive = 0
  for _, pat in ipairs(P.POSITIVE_PATTERNS) do
    if low:find(pat) then positive = positive + 1; break end
  end
  -- Second pass - count EXTRA positives beyond the main LFM trigger.
  if low:find("/w%s+me") or low:find("pst%s+me") then positive = positive + 1 end
  if low:find("%(%d+/%d+%)") then positive = positive + 1 end
  if low:find("need%s+%d") or low:find("need%s+all") or low:find("%sneed%s") then positive = positive + 1 end

  local raid_name = P.findRaid(low)
  if raid_name then positive = positive + 1 end

  if positive >= 2 and raid_name then
    return "LFM_RAID"
  end
  return "OTHER"
end

-- =============================================================
-- Field extraction
-- =============================================================

function P.extractGS(low)
  -- 6.1KK / 6,1KK
  local a, b = low:match("(%d)[%.,](%d)%s*kk")
  if a then return tonumber(a) * 1000 + tonumber(b) * 100, false end

  -- min gs 5.4 / min. 6.2k / Min GS 5.4
  a, b = low:match("min%.?%s*gs%s*(%d)[%.,]?(%d?)")
  if a then return tonumber(a) * 1000 + (tonumber(b) or 0) * 100, false end
  a, b = low:match("min%.?%s+(%d)[%.,]?(%d?)%s*k")
  if a then return tonumber(a) * 1000 + (tonumber(b) or 0) * 100, false end

  -- gs 5.5 / GS 5.8
  a, b = low:match("gs%s+(%d)[%.,]?(%d?)")
  if a then return tonumber(a) * 1000 + (tonumber(b) or 0) * 100, true end

  -- 6.2+ / 6,2+ / 6.2k+ / 5.8K+
  a, b = low:match("(%d)[%.,](%d)%s*k?%+")
  if a then return tonumber(a) * 1000 + tonumber(b) * 100, false end

  -- 5800+ gs / 5800gs
  local k = low:match("(%d%d%d%d)%s*%+?%s*gs")
  if k then return tonumber(k), false end

  -- "all +6,2+achiv" - pattern from the data
  a, b = low:match("all%s*%+?(%d)[%.,](%d)")
  if a then return tonumber(a) * 1000 + tonumber(b) * 100, false end

  return nil, nil
end

function P.extractCurrentMax(low)
  -- Best is (N/M) at the end
  local n, m
  for nn, mm in low:gmatch("%((%d+)/(%d+)%)") do
    nn, mm = tonumber(nn), tonumber(mm)
    if mm == 10 or mm == 25 then n, m = nn, mm end
  end
  if n then return n, m end

  -- Without parens at the end
  local nn, mm = low:match("(%d+)/(%d+)%s*$")
  if nn then
    nn, mm = tonumber(nn), tonumber(mm)
    if mm == 10 or mm == 25 then return nn, mm end
  end
  return nil, nil
end

function P.extractProgress(low)
  -- Boss progress: M in {12, 5, 4, 6} (WotLK raids)
  for n, m in low:gmatch("(%d+)/(%d+)") do
    n, m = tonumber(n), tonumber(m)
    if m == 12 or m == 5 or m == 4 or m == 6 then
      return n, m
    end
  end
  return nil, nil
end

function P.tokenizeReserves(block)
  local tokens = {}
  local cleaned = block:gsub("[Rr][Ee][Ss][Ss]?", " ")
  cleaned = cleaned:gsub("[Oo][Nn][Ll][Yy]", " ")
  cleaned = cleaned:gsub("[Ff][Oo][Rr]%s+[Ss][Ee][Ll][Ll]", " ")
  for tok in cleaned:gmatch("[%w]+") do
    if tok:len() <= 5 then
      table.insert(tokens, tok:upper())
    end
  end
  return tokens
end

function P.extractReserves(raw)
  -- Each parenthesized block containing "res"
  for block in raw:gmatch("%((.-)%)") do
    if block:lower():find("res") then
      return "(" .. block .. ")", P.tokenizeReserves(block)
    end
  end
  return nil, nil
end

function P.extractAchReq(raw, low)
  local link_name = raw:match("|Hachievement:[^|]+|h(%[[^%]]+%])|h")
  local has_link = link_name and true or false
  local has_word = (low:find("achiv") or low:find("achi%s") or low:find("achi$") or low:find("achievement")) and true or false
  return {
    required = has_link or has_word,
    link = link_name,
  }
end

function P.classifyRoleToken(word)
  for role, tokens in pairs(P.ROLE_TOKENS) do
    for _, t in ipairs(tokens) do
      if word == t then return role end
    end
  end
  return nil
end

function P.extractRoles(low)
  local result = { TANK = 0, HEAL = 0, MELEE = 0, RANGED = 0, DPS = 0, all = false }

  if low:find("need%s+all") or low:find("need.+all") then
    result.all = true
  end

  -- Position of the word "need" - accept any following character (comma, colon, space).
  local need_pos = low:find("need")
  if not need_pos then
    need_pos = low:find("lfm") or low:find("^lf%s")
  end
  if not need_pos then return result end

  local seg = low:sub(need_pos, need_pos + 250)

  for n, word in seg:gmatch("(%d+)%s+(%a+)") do
    local cnt = tonumber(n)
    if cnt and cnt >= 1 and cnt <= 9 then
      local role = P.classifyRoleToken(word)
      if role then
        result[role] = result[role] + cnt
      end
    end
  end

  return result
end

-- Boss aliases used in '@<boss>' tokens. Map alias -> { short_name, boss_num }.
-- '@<boss>' in an LFM means "raid is currently AT this boss" (looking for a
-- replacement to continue), NOT a leader's nickname. The token also collides
-- with class/spec mentions (@unholy, @sp, @cat, @rshamy, @disc) and status
-- markers (@fresh) - those are intentionally absent from this map and are
-- ignored.
P.BOSS_ALIASES = {
  -- ICC (12 bosses, in order)
  ["mar"]         = { "MAR",    1 },
  ["lm"]          = { "MAR",    1 },
  ["marrowgar"]   = { "MAR",    1 },
  ["ldw"]         = { "LDW",    2 },
  ["lady"]        = { "LDW",    2 },
  ["deathwhisper"]= { "LDW",    2 },
  ["gs"]          = { "GS",     3 },
  ["gsh"]         = { "GS",     3 },
  ["gunship"]     = { "GS",     3 },
  ["dbs"]         = { "DBS",    4 },
  ["saur"]        = { "DBS",    4 },
  ["saurfang"]    = { "DBS",    4 },
  ["fc"]          = { "FC",     5 },
  ["fest"]        = { "FC",     5 },
  ["fester"]      = { "FC",     5 },
  ["festergut"]   = { "FC",     5 },
  ["rot"]         = { "ROT",    6 },
  ["rotface"]     = { "ROT",    6 },
  ["pp"]          = { "PP",     7 },
  ["prof"]        = { "PP",     7 },
  ["putricide"]   = { "PP",     7 },
  ["plage"]       = { "PP",     7 },     -- Plagueworks wing -> last boss in wing
  ["bp"]          = { "BPC",    8 },
  ["bpc"]         = { "BPC",    8 },
  ["bprinces"]    = { "BPC",    8 },
  ["princes"]     = { "BPC",    8 },
  ["blood"]       = { "BPC",    8 },     -- ambiguous, but 'Blood Council' is more common usage
  ["bq"]          = { "BQL",    9 },
  ["bql"]         = { "BQL",    9 },
  ["queen"]       = { "BQL",    9 },
  ["bqueen"]      = { "BQL",    9 },
  ["bqhc"]        = { "BQL",    9 },
  ["lanathel"]    = { "BQL",    9 },
  ["vdw"]         = { "VDW",   10 },
  ["val"]         = { "VDW",   10 },
  ["vali"]        = { "VDW",   10 },
  ["dbw"]         = { "VDW",   10 },
  ["valithria"]   = { "VDW",   10 },
  ["dreamwalker"] = { "VDW",   10 },
  ["sin"]         = { "SIN",   11 },
  ["sind"]        = { "SIN",   11 },
  ["sindy"]       = { "SIN",   11 },
  ["syndra"]      = { "SIN",   11 },
  ["sindra"]      = { "SIN",   11 },
  ["sindragosa"]  = { "SIN",   11 },
  ["lk"]          = { "LK",    12 },
  ["lich"]        = { "LK",    12 },
  ["lichking"]    = { "LK",    12 },
  -- RS (1 boss)
  ["halion"]      = { "HALION", 1 },
  ["hallion"]     = { "HALION", 1 },
}

function P.extractAtBoss(raw)
  -- First @<token> that resolves against BOSS_ALIASES wins. Class/spec @-tokens
  -- (@unholy, @sp, @disc, ...) and @fresh are not in the map -> skipped.
  for tok in raw:gmatch("@(%w+)") do
    local key = tok:lower()
    local entry = P.BOSS_ALIASES[key]
    if entry then return entry[1], entry[2] end
  end
  return nil, nil
end

function P.extractDiscordStatus(low)
  -- 1. Explicitly NOT required (silent runs).
  if low:find("no%s+discord") or low:find("no%s+voice") or low:find("no%s+mic")
     or low:find("silent%s+run") or low:find("silent%s+raid")
     or low:find("without%s+discord") or low:find("don't%s+need%s+discord") then
    return "not_required"
  end

  -- 2. Explicitly REQUIRED.
  if low:find("discord%s+mandatory") or low:find("mandatory%s+discord")
     or low:find("discord%s+req") or low:find("discord%s+required")
     or low:find("discord%s+must") or low:find("discord%s+a%s+must")
     or low:find("must%s+have%s+discord") or low:find("must%s+join%s+discord")
     or low:find("voice%s+req") or low:find("voice%s+mandatory")
     or low:find("must%s+have%s+voice") or low:find("voice%s+chat%s+req") then
    return "required"
  end

  -- 3. Discord server link OR a bare "discord"/"disc" mention - usually means
  -- you have to join the server. Classified as required here.
  if low:find("discord%.gg/") or low:find("discord%.com/")
     or low:find("%sdiscord%s") or low:find("%sdiscord$") or low:find("^discord%s")
     or low:find("%sdisc%s") or low:find("using%s+discord") or low:find("on%s+discord") then
    return "required"
  end

  return "unknown"
end

-- =============================================================
-- Main entry
-- =============================================================

function P.parse(msg, author)
  local raw = msg or ""
  local low = raw:lower()
  local class = P.classify(raw)

  local out = {
    class = class,
    raw_message = raw,
    author = author,
    msg_normalized = P.normalize(raw),
  }

  if class ~= "LFM_RAID" then
    return out
  end

  local raid_name, size, diff = P.findRaid(low)
  out.raid = raid_name or "?"
  out.size = size
  out.difficulty = diff

  -- Override difficulty when explicit
  if low:find("%shc[%s%)%(/]") or low:find("%shc$") or low:find("heroic") then
    out.difficulty = "HC"
  elseif low:find("%snm[%s%)%(/]") or low:find("%snm$") or low:find("normal") then
    out.difficulty = "NM"
  end

  out.gs_min, out.gs_strict = P.extractGS(low)
  out.current, out.max = P.extractCurrentMax(low)
  out.progress_cur, out.progress_max = P.extractProgress(low)
  out.reserves_raw, out.reserves_tokens = P.extractReserves(raw)
  out.ach_req = P.extractAchReq(raw, low)
  out.role_needs = P.extractRoles(low)
  out.at_boss, out.at_boss_num = P.extractAtBoss(raw)
  out.discord_status = P.extractDiscordStatus(low)

  return out
end
