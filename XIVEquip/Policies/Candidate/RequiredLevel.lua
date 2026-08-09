-- Policies/Candidate/RequiredLevel.lua
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.required_level",
  phase = "candidate",
  requires = { "character.level" },
  apply = function(candidate, context)
    local req = candidate and candidate.equip and candidate.equip.requiredLevel
    local level = context and context.level
    if type(req) == "number" and type(level) == "number" and req > level then
      return { allow = false, reason = "requires-level" }
    end
    return nil
  end,
})

