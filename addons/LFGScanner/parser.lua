--[[
  LFGScanner.Parser
  Czysta logika klasyfikacji + ekstrakcji pol z wiadomosci czatu.
  Heurystyki spisane w docs/PARSING.md.
  Idealnie testowalna bez WoW API (uzywa tylko string/table/math).
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner
A.Parser = A.Parser or {}
local P = A.Parser

-- =============================================================
-- Slowniki
-- =============================================================

-- Wzorce raidow. Kolejnosc istotna: dluzsze/specyficzniejsze pierwsze.
-- { lua_pattern, normalized_name, size, default_difficulty }
P.RAID_PATTERNS = {
  -- ICC (najpopularniejsze)
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
  -- TOGC (przed TOC zeby nie dopasowalo "toc")
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
  -- Inne
  { "ulduar%s*25",       "ULDUAR",  25, "NM" },
  { "ulduar",            "ULDUAR",  25, "NM" },
  { "naxx",              "NAXX",    25, "NM" },
  { "os%s*25",           "OS25",    25, "NM" },
  { "os%s*10",           "OS10",    10, "NM" },
  { "lod",               "LOD",     25, "HC" },
  { "bane",              "BANE",    25, "HC" },
}

-- Tokeny rol (plain strings, dopasowanie exact match per slowo).
P.ROLE_TOKENS = {
  TANK   = { "tank", "tanks", "mt", "ot", "prot", "bdk", "bear", "ppal", "pwar" },
  HEAL   = { "heal", "heals", "healer", "healers", "hpala", "disco", "discp", "holy", "hpriest", "rsham", "hdruid", "hpal" },
  MELEE  = { "melee", "mdps", "fwar", "ret", "rogue", "rogues", "rog", "enha", "fdk", "kit", "feral" },
  RANGED = { "ranged", "rdps", "boomy", "hunter", "hunters", "hunt", "mage", "mages", "sp", "spriest", "demo", "affli", "ele", "lock", "locks", "warlock" },
  DPS    = { "dps", "dd" },
}

-- Sygnaly antywskazujace LFM_RAID. Jezeli wystapi, klasyfikator nie wybierze LFM.
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

-- Sygnaly pozytywne dla LFM_RAID.
P.POSITIVE_PATTERNS = {
  "^lfm[%s%-#]", "^#lfm", "%slfm[%s%-]", "^lfm$",
  "^lf%s",                          -- "LF tank", "LF healer"
  "%(%d+/%d+%)",                    -- (21/25)
  "/w%s+me", "pst%s+me", "pst%s+for", "whisper%s+me",
  "last%s+spot", "last%s+%d+%s+spot",
  "fresh%s+%d+/", "fresh%s+run",
  "need%s+%d", "need%s+all", "%sneed%s",
}

-- =============================================================
-- Helpery
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
-- Filtr jezykowy (akceptujemy tylko angielski)
-- =============================================================

-- Tagi jezykowe wskazujace nie-angielski.
P.NON_EN_LANG_TAGS = {
  "%[ru%]", "%[rus%]", "%[de%]", "%[ger%]", "%[fr%]", "%[fra%]",
  "%[es%]", "%[esp%]", "%[br%]", "%[pt%]", "%[pl%]",
  "%[balkan%]", "%[sr%]", "%[srb%]", "%[bs%]", "%[hr%]",
  "%[bg%]", "%[ge%]", "%[gr%]", "%[it%]", "%[tr%]", "%[cn%]",
}

-- Slowa charakterystyczne dla nie-angielskiego.
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
  -- RU/CYR translit (charakterystyczne fragmenty)
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
  -- Cyrylica zatluszczona ASCII charakteryzuje sie:
  -- - mieszanymi kapitalami: "JIb", "BO", "yI", "OB"
  -- - cyfra w srodku slowa: "9l", "g9eT", "u9eT"
  -- - ciagi 2+ kapitalnych nie na poczatku: "BCEX", "K/\ACCOB"
  if word:len() < 4 then return false end
  if word:match("[a-z][A-Z][A-Z]") then return true end       -- npurJI
  if word:match("[A-Za-z]%d[A-Za-z]") then return true end    -- u9eT, g9eT
  if word:match("[A-Z][A-Z][A-Z]") and not word:match("^[A-Z][A-Z][A-Z]+$") then
    return true                                                 -- BCEX wewnatrz
  end
  return false
end

function P.isEnglishOnly(raw)
  if not raw or raw == "" then return true end
  local low = raw:lower()

  -- 1. Tagi jezykowe na poczatku/w naglowku
  for _, tag in ipairs(P.NON_EN_LANG_TAGS) do
    if low:find(tag) then return false end
  end

  -- 2. Bajty UTF-8 spoza ASCII (cyrylica, polskie/niemieckie/balkanowskie diakrytyki)
  if P.hasNonAsciiBytes(raw, 5) then return false end

  -- 3. Slowa-markery jezykow obcych
  for _, kw in ipairs(P.NON_EN_KEYWORDS) do
    if low:find(kw) then return false end
  end

  -- 4. Heurystyka cyrylicy zatluszczonej ASCII (translit)
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
-- Klasyfikacja
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
  -- Prefix < ... > / > ... < / << ... >> na poczatku - prawie zawsze gildia/boost,
  -- chyba ze sa silne sygnaly LFM_RAID (LFM + (N/M) + Need + raid).
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
    -- LFM z (N/M) i nazwa raidu wygrywa - to nadal LFM_RAID, achievement to wymog
    if low:find("%(%d+/%d+%)") then return false end
    if low:find("^lfm") or low:find("%slfm%s") then return false end
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

  -- Filtr jezyka: tylko angielski wpada do dalszej klasyfikacji.
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
  -- Drugi pass - zliczamy DODATKOWE pozytywy poza glownym LFM-trigger.
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
-- Ekstrakcja pol
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

  -- "all +6,2+achiv" - wzorzec ze danych
  a, b = low:match("all%s*%+?(%d)[%.,](%d)")
  if a then return tonumber(a) * 1000 + tonumber(b) * 100, false end

  return nil, nil
end

function P.extractCurrentMax(low)
  -- Najlepiej (N/M) na koncu
  local n, m
  for nn, mm in low:gmatch("%((%d+)/(%d+)%)") do
    nn, mm = tonumber(nn), tonumber(mm)
    if mm == 10 or mm == 25 then n, m = nn, mm end
  end
  if n then return n, m end

  -- Bez nawiasow na koncu
  local nn, mm = low:match("(%d+)/(%d+)%s*$")
  if nn then
    nn, mm = tonumber(nn), tonumber(mm)
    if mm == 10 or mm == 25 then return nn, mm end
  end
  return nil, nil
end

function P.extractProgress(low)
  -- Progres bossow: M in {12, 5, 4, 6} (raidy WotLK)
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
  -- Kazdy blok w nawiasach zawierajacy "res"
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

  -- Pozycja slowa "need" - akceptuj kazdy nastepny znak (przecinek, dwukropek, spacja).
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

function P.extractActualLeader(raw)
  local nick = raw:match("@(%w+)")
  if nick and nick:len() >= 2 then return nick end
  return nil
end

-- =============================================================
-- Glowny entry
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

  -- Override difficulty jezeli explicit
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
  out.actual_leader = P.extractActualLeader(raw)
  out.fresh = (low:find("fresh") and true) or false

  return out
end
