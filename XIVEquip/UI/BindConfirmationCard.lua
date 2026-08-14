-- UI/BindConfirmationCard.lua
-- A read-only companion to Blizzard's protected bind-confirmation popup.
-- The card deliberately owns no buttons and never modifies StaticPopupDialogs:
-- Blizzard remains solely responsible for accepting/cancelling the pending
-- equip, while XIVEquip supplies the recommendation context beside it.
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}

local Card = {}
XIVEquip.UI.BindConfirmationCard = Card

local BIND_DIALOGS = {
  "EQUIP_BIND",
  "EQUIP_BIND_REFUNDABLE",
  "EQUIP_BIND_TRADEABLE",
}

-- Ordered for readability rather than magnitude. Each stat uses the first
-- Blizzard token present because some clients expose both long and _SHORT
-- aliases for the same value; summing aliases would double-count it.
local STAT_ROWS = {
  { label = "Strength", tokens = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STRENGTH" } },
  { label = "Agility", tokens = { "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_AGILITY" } },
  { label = "Intellect", tokens = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_INTELLECT" } },
  { label = "Stamina", tokens = { "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STAMINA" } },
  { label = "Armor", tokens = { "ITEM_MOD_ARMOR_SHORT", "ITEM_MOD_ARMOR", "RESISTANCE0_NAME" } },
  { label = "Bonus Armor", tokens = { "ITEM_MOD_BONUS_ARMOR_SHORT" } },
  { label = "Crit", tokens = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING" } },
  { label = "Haste", tokens = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_RATING" } },
  { label = "Mastery", tokens = { "ITEM_MOD_MASTERY_RATING_SHORT", "ITEM_MOD_MASTERY_RATING" } },
  { label = "Versatility", tokens = { "ITEM_MOD_VERSATILITY", "ITEM_MOD_VERSATILITY_SHORT" } },
  { label = "Leech", tokens = { "ITEM_MOD_LIFESTEAL_SHORT", "ITEM_MOD_LIFESTEAL" } },
  { label = "Avoidance", tokens = { "ITEM_MOD_AVOIDANCE_RATING_SHORT", "ITEM_MOD_AVOIDANCE_RATING" } },
  { label = "Speed", tokens = { "ITEM_MOD_SPEED_RATING_SHORT", "ITEM_MOD_SPEED_RATING" } },
}

local frame

local function firstStat(stats, tokens)
  for _, token in ipairs(tokens) do
    local amount = stats and stats[token]
    if type(amount) == "number" then return amount end
  end
  return 0
end

local function itemStats(link)
  local fn = _G.GetItemStats or (_G.C_Item and _G.C_Item.GetItemStats)
  if type(fn) ~= "function" or type(link) ~= "string" then return {} end
  local ok, stats = pcall(fn, link)
  return ok and type(stats) == "table" and stats or {}
end

local function itemTexture(link)
  if type(_G.GetItemInfo) ~= "function" or type(link) ~= "string" then return nil end
  local ok, texture = pcall(function() return select(10, _G.GetItemInfo(link)) end)
  return ok and texture or nil
end

-- BuildView is intentionally pure apart from the injected/default item reads,
-- making the exact player-facing numbers testable without creating frames.
function Card.BuildView(details, getStats, getTexture)
  details = details or {}
  getStats = getStats or itemStats
  getTexture = getTexture or itemTexture
  local oldStats = getStats(details.oldLink) or {}
  local newStats = getStats(details.newLink) or {}
  local rows = {}

  for _, spec in ipairs(STAT_ROWS) do
    local delta = firstStat(newStats, spec.tokens) - firstStat(oldStats, spec.tokens)
    if delta ~= 0 then rows[#rows + 1] = { label = spec.label, delta = delta } end
  end

  return {
    slotName = details.slotName or (details.slot and ("Slot " .. tostring(details.slot))) or "Recommended item",
    oldLink = details.oldLink or "|cff888888(None)|r",
    newLink = details.newLink or details.link or "|cff888888(Unknown item)|r",
    deltaScore = tonumber(details.deltaScore) or 0,
    deltaIlvl = tonumber(details.deltaIlvl) or 0,
    texture = getTexture(details.newLink or details.link),
    stats = rows,
  }
end

local function findDialog()
  for _, which in ipairs(BIND_DIALOGS) do
    if type(_G.StaticPopup_FindVisible) == "function" then
      local ok, dialog = pcall(_G.StaticPopup_FindVisible, which)
      if ok and dialog then return dialog end
    end
    if type(_G.StaticPopup_Visible) == "function" then
      local ok, _, dialog = pcall(_G.StaticPopup_Visible, which)
      if ok and dialog then return dialog end
    end
  end

  -- Compatibility fallback for clients/UI replacements that keep the
  -- traditional named popup frames but do not expose the lookup helpers.
  for i = 1, 4 do
    local dialog = _G["StaticPopup" .. tostring(i)]
    if dialog and dialog.which then
      for _, which in ipairs(BIND_DIALOGS) do
        if dialog.which == which and (not dialog.IsShown or dialog:IsShown()) then return dialog end
      end
    end
  end
  return nil
end

local function font(parent, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template)
  if label.SetJustifyH then label:SetJustifyH("LEFT") end
  return label
end

local function ensureFrame()
  if frame or type(_G.CreateFrame) ~= "function" then return frame end
  local parent = _G.UIParent
  frame = _G.CreateFrame("Frame", "XIVEquipBindConfirmationCard", parent, "BackdropTemplate")
  frame:SetSize(410, 150)
  if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG") end
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.EnableMouse then frame:EnableMouse(false) end
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.035, 0.055, 0.075, 0.97)
    frame:SetBackdropBorderColor(0.20, 0.72, 0.95, 0.95)
  end

  frame.title = font(frame, "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", 14, -12)
  frame.title:SetText("|cff33ccffXIVEquip recommendation|r")

  frame.slot = font(frame, "GameFontHighlightSmall")
  frame.slot:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(38, 38)
  frame.icon:SetPoint("TOPLEFT", frame.slot, "BOTTOMLEFT", 0, -7)

  frame.newItem = font(frame, "GameFontNormal")
  frame.newItem:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 9, -1)
  frame.newItem:SetWidth(335)

  frame.replacing = font(frame, "GameFontHighlightSmall")
  frame.replacing:SetPoint("TOPLEFT", frame.newItem, "BOTTOMLEFT", 0, -5)
  frame.replacing:SetWidth(335)

  frame.summary = font(frame, "GameFontHighlight")
  frame.summary:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -10)

  frame.statLabels = {}
  frame:Hide()
  return frame
end

local function signedColor(value)
  return value >= 0 and "|cff7fff7f" or "|cffff5a5a"
end

local function anchorBeside(card, dialog)
  card:ClearAllPoints()

  -- Prefer the right side. If the popup is already close enough to the
  -- screen's right edge that the card would be clamped back over it, use
  -- the left instead. Missing geometry APIs simply fall through to the
  -- predictable right-side anchor.
  local parentWidth = _G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()
  local dialogRight = dialog.GetRight and dialog:GetRight()
  local cardWidth = card.GetWidth and card:GetWidth() or 410
  if parentWidth and dialogRight and (parentWidth - dialogRight) < (cardWidth + 12) then
    card:SetPoint("RIGHT", dialog, "LEFT", -10, 0)
  else
    card:SetPoint("LEFT", dialog, "RIGHT", 10, 0)
  end
end

function Card.Show(details, dialog)
  dialog = dialog or findDialog()
  if not dialog then return false end
  local card = ensureFrame()
  if not card then return false end

  local view = Card.BuildView(details)
  card.slot:SetText(view.slotName)
  card.newItem:SetText(view.newLink)
  card.replacing:SetText("|cffaaaaaaReplacing:|r " .. tostring(view.oldLink))
  card.summary:SetText(string.format(
    "%s%+.1f score|r   |cff7fbfff%+d ilvl|r",
    signedColor(view.deltaScore), view.deltaScore, view.deltaIlvl))
  card.icon:SetTexture(view.texture or "Interface\\Icons\\INV_Misc_QuestionMark")

  for index, row in ipairs(view.stats) do
    local label = card.statLabels[index]
    if not label then
      label = font(card, "GameFontHighlightSmall")
      card.statLabels[index] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", card.summary, "BOTTOMLEFT", 0, -4 - ((index - 1) * 15))
    label:SetText(string.format("%s%+d %s|r", signedColor(row.delta), row.delta, row.label))
    label:Show()
  end
  for index = #view.stats + 1, #card.statLabels do card.statLabels[index]:Hide() end

  card:SetHeight(126 + (#view.stats * 15))
  anchorBeside(card, dialog)
  if card.SetFrameLevel and dialog.GetFrameLevel then card:SetFrameLevel(dialog:GetFrameLevel() + 1) end
  card:Show()
  return true
end

function Card.Hide()
  if frame then frame:Hide() end
end

function Card.GetFrame()
  return frame
end
