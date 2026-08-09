local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local fixturePath = root .. sep .. "tests" .. sep .. "fixtures" .. sep .. "live_capture.lua"

local function loadFixture()
  local chunk = loadfile(fixturePath)
  if not chunk then return nil end
  return chunk()
end

local function countMap(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

test("captured fixture has character and inventory data", function()
  local fixture = loadFixture()
  if not fixture then
    io.write("[SKIP] captured fixture not found; run tools/import-fixture.ps1 after /xive fixture capture\n")
    return
  end

  A.truthy(fixture.character, "fixture should include character metadata")
  A.truthy(fixture.equipped, "fixture should include equipped items")
  A.truthy(fixture.bags, "fixture should include bag items")
  A.truthy(fixture.pawn, "fixture should include Pawn metadata")
  A.truthy(countMap(fixture.equipped) > 0, "fixture should include at least one equipped item")
end)

test("captured fixture item records expose replayable item metadata", function()
  local fixture = loadFixture()
  if not fixture then return end

  local checked = 0
  for _, item in pairs(fixture.equipped or {}) do
    A.truthy(item.itemID, "equipped item should include itemID")
    A.truthy(item.link, "equipped item should include link")
    A.truthy(item.slotID, "equipped item should include slotID")
    checked = checked + 1
    if checked >= 3 then break end
  end
  A.truthy(checked > 0, "expected equipped item records to validate")
end)

test("captured fixture does not retain direct character identity fields", function()
  local fixture = loadFixture()
  if not fixture then return end

  A.equal(fixture.character.name, "<redacted>", "character name should be redacted")
  A.equal(fixture.character.realm, "<redacted>", "realm should be redacted")
end)

return tests
