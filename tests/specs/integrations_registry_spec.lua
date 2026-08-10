local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function newAddon()
  local addon = { Log = {} }
  _G.XIVEquip_Settings = {}
  local settings = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "Global" .. sep .. "Settings.lua"))
  settings("XIVEquip", addon)
  Bootstrap.LoadWeights(root, addon)
  return addon
end

local function scale(addon, id, kind)
  return addon.XIVWeights.NewScale({
    id = id,
    name = id,
    source = { kind = kind },
    weights = { strength = 1 },
  })
end

test("Automatic integrations resolve in hard-coded priority order", function()
  local addon = newAddon()
  local registry = addon.Integrations.Registry
  local lower = scale(addon, "future:scale", "future")

  registry:Register({
    id = "future",
    label = "Future",
    automaticPriority = 100,
    IsAvailable = function() return true end,
    Resolve = function() return lower end,
  })

  local resolved, entry = registry:ResolveAutomatic({ specID = 66, runtime = {} })

  A.equal(resolved.id, "future:scale")
  A.equal(entry.id, "future")
end)

test("Pawn wins Automatic resolution when Pawn and a lower-priority integration are usable", function()
  local addon = newAddon()
  local registry = addon.Integrations.Registry
  local pawn = scale(addon, "pawn:scale", "pawn")
  local lower = scale(addon, "future:scale", "future")

  registry:Register({
    id = "future",
    label = "Future",
    automaticPriority = 100,
    IsAvailable = function() return true end,
    Resolve = function() return lower end,
  })

  local runtime = {
    PawnProvider = function()
      return { Resolve = function() return pawn end }
    end,
  }
  local resolved, entry = registry:ResolveAutomatic({ specID = 66, runtime = runtime })

  A.equal(resolved.id, "pawn:scale")
  A.equal(entry.id, "pawn")
end)

test("Automatic integrations return a stable fallback reason when none can resolve", function()
  local addon = newAddon()
  local resolved, reason = addon.Integrations.Registry:ResolveAutomatic({ specID = 66, runtime = {} })

  A.equal(resolved, nil)
  A.equal(reason, "no-suitable-integration-scale")
end)

return tests
