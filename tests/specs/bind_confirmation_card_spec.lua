local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newRegion()
  local region = { visible = true }
  function region:SetPoint(...) self.point = { ... } end
  function region:ClearAllPoints() self.point = nil end
  function region:SetText(text) self.text = text end
  function region:SetTexture(texture) self.texture = texture end
  function region:SetSize(width, height) self.width, self.height = width, height end
  function region:SetWidth(width) self.width = width end
  function region:GetWidth() return self.width end
  function region:SetJustifyH(value) self.justifyH = value end
  function region:Show() self.visible = true end
  function region:Hide() self.visible = false end
  return region
end

local function loadCard(statsByLink)
  local created
  local dialog = { which = "EQUIP_BIND" }
  function dialog:GetFrameLevel() return 20 end

  _G.UIParent = {}
  _G.C_Item = nil
  _G.GetItemStats = function(link) return statsByLink[link] or {} end
  _G.GetItemInfo = function()
    return nil, nil, nil, nil, nil, nil, nil, nil, nil, "item-icon"
  end
  _G.StaticPopup_Visible = nil
  _G.StaticPopup_FindVisible = function(which)
    if which == "EQUIP_BIND" then return dialog end
  end
  _G.CreateFrame = function()
    local frame = newRegion()
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:SetBackdrop(value) self.backdrop = value end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:SetBackdropBorderColor(...) self.borderColor = { ... } end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:SetHeight(value) self.height = value end
    function frame:CreateFontString() return newRegion() end
    function frame:CreateTexture() return newRegion() end
    created = frame
    return frame
  end

  local addon = {}
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "UI" .. sep .. "BindConfirmationCard.lua"))
  chunk("XIVEquip", addon)
  return addon.UI.BindConfirmationCard, created, dialog
end

test("builds a complete stat-difference view without double-counting Blizzard aliases", function()
  local oldLink, newLink = "old", "new"
  local Card = loadCard({
    [oldLink] = {
      ITEM_MOD_AGILITY_SHORT = 100,
      ITEM_MOD_AGILITY = 100,
      ITEM_MOD_MASTERY_RATING_SHORT = 50,
    },
    [newLink] = {
      ITEM_MOD_AGILITY_SHORT = 140,
      ITEM_MOD_AGILITY = 140,
      ITEM_MOD_MASTERY_RATING_SHORT = 35,
      ITEM_MOD_CRIT_RATING_SHORT = 25,
    },
  })

  local view = Card.BuildView({
    slot = 7, slotName = "Legs", oldLink = oldLink, newLink = newLink,
    deltaScore = 58.25, deltaIlvl = 13,
  })

  A.equal(view.slotName, "Legs")
  A.equal(view.deltaScore, 58.25)
  A.same(view.stats, {
    { label = "Agility", delta = 40 },
    { label = "Crit", delta = 25 },
    { label = "Mastery", delta = -15 },
  })
end)

test("shows beside Blizzard's dialog and hides without owning confirmation controls", function()
  local Card = loadCard({ old = {}, new = { ITEM_MOD_VERSATILITY = 18 } })

  A.truthy(Card.Show({
    slotName = "Feet", oldLink = "old", newLink = "new",
    deltaScore = 31.5, deltaIlvl = 9,
  }))

  local frame = Card.GetFrame()
  A.truthy(frame.visible)
  A.equal(frame.strata, "DIALOG")
  A.equal(frame.frameLevel, 21)
  A.equal(frame.point[1], "LEFT")
  A.equal(frame.point[2].which, "EQUIP_BIND")
  A.equal(frame.point[3], "RIGHT")
  A.contains({ frame.summary.text }, "+31.5 score")
  A.contains({ frame.summary.text }, "+9 ilvl")
  A.equal(frame.statLabels[1].text, "|cff7fff7f+18 Versatility|r")
  A.equal(frame.icon.texture, "item-icon")

  Card.Hide()
  A.falsy(frame.visible)
end)

test("moves to the popup's left side when the right edge is crowded", function()
  local Card, _, dialog = loadCard({ old = {}, new = {} })
  function _G.UIParent:GetWidth() return 1000 end
  function dialog:GetRight() return 750 end

  A.truthy(Card.Show({ oldLink = "old", newLink = "new" }))

  local frame = Card.GetFrame()
  A.equal(frame.point[1], "RIGHT")
  A.equal(frame.point[2], dialog)
  A.equal(frame.point[3], "LEFT")
end)

return tests
