--[[
  LFGScanner.UI
  Plywajaca tabelka aktywnych raidow.
  v1: bez scrolla (15 widocznych wierszy), movable, resizable, z tooltipem
  pelnej tresci na hover. LMB = whisper.
]]

LFGScanner = LFGScanner or {}
local A = LFGScanner
A.UI = A.UI or {}
local UI = A.UI

local ROW_HEIGHT = 18
local HEADER_HEIGHT = 22
local TITLEBAR_HEIGHT = 22
local STATUSBAR_HEIGHT = 18
local PADDING = 6

-- Ukladamy kolumny: { key, header, width }
UI.COLUMNS = {
  { key = "raid",     header = "Raid",   width = 80 },
  { key = "progress", header = "Prog",   width = 60 },
  { key = "gs",       header = "GS",     width = 50 },
  { key = "needs",    header = "Needs",  width = 110 },
  { key = "group",    header = "Group",  width = 50 },
  { key = "age",      header = "Age",    width = 50 },
  { key = "poster",   header = "Poster", width = 120 },
  { key = "extras",   header = "+",      width = 40 },  -- ach + reserves icons
}

local function colorize(text, r, g, b)
  return string.format("|cff%02x%02x%02x%s|r",
    math.floor((r or 1)*255), math.floor((g or 1)*255), math.floor((b or 1)*255),
    text)
end

local function fmtRoles(role_needs)
  if not role_needs then return "" end
  if role_needs.all then return colorize("ALL", 1, 0.6, 0.2) end
  local parts = {}
  if (role_needs.TANK or 0) > 0 then table.insert(parts, "T" .. role_needs.TANK) end
  if (role_needs.HEAL or 0) > 0 then table.insert(parts, "H" .. role_needs.HEAL) end
  if (role_needs.MELEE or 0) > 0 then table.insert(parts, "M" .. role_needs.MELEE) end
  if (role_needs.RANGED or 0) > 0 then table.insert(parts, "R" .. role_needs.RANGED) end
  if (role_needs.DPS or 0) > 0 then table.insert(parts, "D" .. role_needs.DPS) end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function fmtGS(gs_min, gs_strict)
  if not gs_min then return "" end
  local s = string.format("%.1fk", gs_min / 1000)
  if not gs_strict then s = s .. "+" end
  return s
end

local function fmtProgress(progress, difficulty)
  local s = ""
  if progress and progress.current and progress.max then
    s = progress.current .. "/" .. progress.max
  end
  if difficulty == "HC" then s = s ~= "" and (s .. " HC") or "HC" end
  if progress and progress.fresh then s = s ~= "" and (s .. " F") or "FRESH" end
  return s
end

local function fmtGroup(raid)
  if raid.current_in_group and raid.max_in_group then
    return raid.current_in_group .. "/" .. raid.max_in_group
  end
  return ""
end

local function fmtAge(raid, now)
  return A.formatAge(now - (raid.first_seen or now))
end

local function fmtPoster(raid)
  return raid.actual_leader or raid.primary_poster or "?"
end

local function fmtExtras(raid)
  local s = ""
  if raid.ach_req and raid.ach_req.required then s = s .. colorize("A", 1, 1, 0.4) end
  if raid.reserves_raw then s = s .. colorize("R", 1, 0.4, 0.4) end
  return s
end

local function rowText(raid, key, now)
  if key == "raid"     then return raid.raid or "?" end
  if key == "progress" then return fmtProgress(raid.progress, raid.difficulty) end
  if key == "gs"       then return fmtGS(raid.gs_min, raid.gs_strict) end
  if key == "needs"    then return fmtRoles(raid.role_needs) end
  if key == "group"    then return fmtGroup(raid) end
  if key == "age"      then return fmtAge(raid, now) end
  if key == "poster"   then return fmtPoster(raid) end
  if key == "extras"   then return fmtExtras(raid) end
  return ""
end

-- =============================================================
-- Frame creation
-- =============================================================

local function applyBackdrop(frame, alpha)
  -- 3.3.5a - SetBackdrop bezposrednio
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, alpha or 0.85)
  frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

local function makeRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.cells = {}
  local x = PADDING
  for _, col in ipairs(UI.COLUMNS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(col.width - 4)
    fs:SetJustifyH("LEFT")
    fs:SetText("")
    row.cells[col.key] = fs
    x = x + col.width
  end
  -- Highlight przy hover
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints(row)

  row:SetScript("OnEnter", function(self)
    if not self.raid then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetWidth(420)
    GameTooltip:AddLine(self.raid.raid or "?", 1, 1, 0)
    GameTooltip:AddLine(self.raid.raw_message or "", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    local posters = {}
    for p in pairs(self.raid.posters or {}) do table.insert(posters, p) end
    GameTooltip:AddDoubleLine("Posters", table.concat(posters, ", "), 0.7, 0.7, 0.7, 1, 1, 1)
    local channels = {}
    for c in pairs(self.raid.channels or {}) do table.insert(channels, c) end
    GameTooltip:AddDoubleLine("Channels", table.concat(channels, ", "), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Posts", tostring(self.raid.posts_count or 1), 0.7, 0.7, 0.7, 1, 1, 1)
    if self.raid.actual_leader then
      GameTooltip:AddDoubleLine("Leader (@)", self.raid.actual_leader, 0.7, 0.7, 0.7, 1, 1, 0.4)
    end
    GameTooltip:AddDoubleLine("Status", self.raid.status or "?", 0.7, 0.7, 0.7,
      self.raid.status == "active" and 0.4 or 0.8,
      self.raid.status == "active" and 1 or 0.8,
      self.raid.status == "active" and 0.4 or 0.4)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row:SetScript("OnClick", function(self, button)
    if not self.raid then return end
    if button == "LeftButton" then
      local target = self.raid.actual_leader or self.raid.primary_poster
      if target then
        ChatFrame_OpenChat("/w " .. target .. " ")
      end
    end
  end)

  return row
end

local function makeHeader(parent)
  local header = CreateFrame("Frame", nil, parent)
  header:SetHeight(HEADER_HEIGHT)
  local x = PADDING
  for _, col in ipairs(UI.COLUMNS) do
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", header, "LEFT", x, 0)
    fs:SetWidth(col.width - 4)
    fs:SetJustifyH("LEFT")
    fs:SetText(col.header)
    fs:SetTextColor(1, 0.82, 0)
    x = x + col.width
  end
  return header
end

function UI.Init()
  if UI.frame then return UI.frame end

  local f = CreateFrame("Frame", "LFGScannerFrame", UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetMinResize(420, 160)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  applyBackdrop(f, 0.88)

  -- Tytul / drag bar
  local title = CreateFrame("Frame", nil, f)
  title:SetHeight(TITLEBAR_HEIGHT)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  title:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    UI.SaveLayout()
  end)

  local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", title, "LEFT", PADDING, 0)
  titleText:SetText("LFG Scanner")
  titleText:SetTextColor(1, 0.82, 0)

  local closeBtn = CreateFrame("Button", nil, title, "UIPanelCloseButton")
  closeBtn:SetPoint("RIGHT", title, "RIGHT", 2, 0)
  closeBtn:SetSize(24, 24)
  closeBtn:SetScript("OnClick", function() UI.Hide() end)

  -- Status bar (bottom)
  local statusBar = CreateFrame("Frame", nil, f)
  statusBar:SetHeight(STATUSBAR_HEIGHT)
  statusBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("LEFT", statusBar, "LEFT", PADDING, 0)
  statusText:SetText("0 raids")
  f.statusText = statusText

  -- Resize handle (prawy dolny rog)
  local resize = CreateFrame("Button", nil, f)
  resize:SetSize(16, 16)
  resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resize:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  resize:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI.SaveLayout()
    UI.Refresh()
  end)

  -- Header tabeli
  local header = makeHeader(f)
  header:SetPoint("TOPLEFT", title, "BOTTOMLEFT", PADDING, -2)
  header:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", -PADDING, -2)
  f.header = header

  -- Wiersze - bedziemy tworzyc dynamicznie zaleznie od wysokosci
  f.rows = {}
  UI.frame = f

  UI.RestoreLayout()
  return f
end

local function ensureRows(count)
  local f = UI.frame
  for i = #f.rows + 1, count do
    local row = makeRow(f, i)
    row:SetPoint("LEFT", f, "LEFT", 0, 0)
    row:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.rows[i] = row
  end
  -- przepozycjonuj wszystkie
  for i, row in ipairs(f.rows) do
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -((i - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -((i - 1) * ROW_HEIGHT))
  end
end

function UI.Refresh()
  if not UI.frame then return end
  local f = UI.frame
  local now = A.now()

  local raids = A.Aggregator.list({ hide_inactive = false })
  local total = A.Aggregator.count()

  -- Ile wierszy zmiesci sie w aktualnej wysokosci
  local available_height = f:GetHeight() - TITLEBAR_HEIGHT - HEADER_HEIGHT - STATUSBAR_HEIGHT - 4
  local row_count = math.max(1, math.floor(available_height / ROW_HEIGHT))
  ensureRows(row_count)

  for i, row in ipairs(f.rows) do
    local raid = (i <= row_count) and raids[i] or nil
    if raid then
      row:Show()
      row.raid = raid
      local alpha = (raid.status == "inactive") and 0.5 or 1
      for _, col in ipairs(UI.COLUMNS) do
        local cell = row.cells[col.key]
        cell:SetText(rowText(raid, col.key, now))
        cell:SetAlpha(alpha)
      end
    else
      row:Hide()
      row.raid = nil
    end
  end

  local active_n = 0
  for _, raid in pairs(A.state.raids) do
    if raid.status == "active" then active_n = active_n + 1 end
  end
  f.statusText:SetText(string.format("%d active / %d total", active_n, total))
end

function UI.Show()
  UI.Init()
  UI.frame:Show()
  if A.db then A.db.ui.shown = true end
  UI.Refresh()
end

function UI.Hide()
  if UI.frame then UI.frame:Hide() end
  if A.db then A.db.ui.shown = false end
end

function UI.Toggle()
  if UI.frame and UI.frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.SaveLayout()
  if not UI.frame or not A.db then return end
  local f = UI.frame
  local point, _, _, x, y = f:GetPoint()
  A.db.ui.point = point or "CENTER"
  A.db.ui.rel_x = x or 0
  A.db.ui.rel_y = y or 0
  A.db.ui.width = f:GetWidth()
  A.db.ui.height = f:GetHeight()
end

function UI.RestoreLayout()
  if not UI.frame or not A.db then return end
  local f = UI.frame
  local ui = A.db.ui
  f:SetSize(ui.width or 720, ui.height or 360)
  f:ClearAllPoints()
  f:SetPoint(ui.point or "CENTER", UIParent, ui.point or "CENTER", ui.rel_x or 0, ui.rel_y or 0)
  if ui.shown == false then f:Hide() else f:Show() end
end
