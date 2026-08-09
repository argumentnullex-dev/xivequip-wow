-- Policies/EvaluationContext/CharacterIdentity.lua
-- Doc section 15.1's "character identity and specialization" example.
-- Self-registers via the public XIVEquip:RegisterPolicy path at load time
-- (doc 15.9's requirement that built-in policies use the exact same
-- registration mechanism as third-party ones) -- requires
-- PublicAPI/Policies.lua to have already run.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.character_identity",
  phase = "evaluation_context",
  provides = {
    "character.class_id",
    "character.class_file",
    "character.spec_id",
    "character.spec_name",
    "character.level",
  },
  apply = function(builder, runtime)
    -- UnitClass/UnitLevel require a unit token -- calling them with none
    -- isn't "the player" by default, it's a missing-argument error against
    -- the real API (production code elsewhere always uses UnitClass("player")).
    local _, classFile, classID = runtime.UnitClass("player")
    local specIndex = runtime.GetSpecialization and runtime.GetSpecialization()
    local specID, specName
    if specIndex then
      specID, specName = runtime.GetSpecializationInfo(specIndex)
    end

    builder:Set("classID", classID)
    builder:Set("classFile", classFile)
    builder:Set("specID", specID)
    builder:Set("specName", specName)
    builder:Set("level", runtime.UnitLevel and runtime.UnitLevel("player"))
  end,
})
