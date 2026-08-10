-- XIVWeights/Import/Pawn.lua
-- Copies a Pawn scale into an editable manual XIVWeights scale.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Import = XIVEquip.XIVWeights.Import or {}
local XIVWeights = XIVEquip.XIVWeights

local PawnImport = {}
XIVWeights.Import.Pawn = PawnImport

function PawnImport.Import(adapter, pawnScaleKey, newID, newName, specID)
  assert(adapter, "Pawn import requires an adapter")
  assert(newID and newID ~= "", "Pawn import requires a new XIVWeights scale id")
  assert(newName and newName ~= "", "Pawn import requires a new XIVWeights scale name")
  assert(tonumber(specID), "Pawn import requires a specialization id")

  local provider = XIVWeights.Providers.Pawn.New(adapter)
  local scale = provider:Resolve(pawnScaleKey, {})
  local imported = XIVWeights.NewScale({
    id = newID,
    name = newName,
    source = {
      kind = "manual",
      importedFrom = "pawn",
      pawnScaleKey = pawnScaleKey,
      importedSourceID = scale.id,
      specID = tonumber(specID),
    },
    weights = scale.weights,
    meta = {
      importedFrom = "pawn",
      pawnScaleKey = pawnScaleKey,
      userEditable = true,
      specID = tonumber(specID),
    },
  })

  XIVWeights.Config.SaveScale(imported)
  return imported
end
