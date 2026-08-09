-- Comparers/Pawn/Command.lua
--
-- Purpose:
--   Implements the `/xive pawn ...` command namespace.
--
-- Notes:
--   This file MUST NOT mutate or re-initialize global command registries.
--   It should only register handlers against `XIVEquip.Commands`.

local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}

local Cmd = XIVEquip.Commands

-- pawn_help:
--   Prints help text for Pawn subcommands.
local function pawn_help()
  print("  /xive pawn                          – list Pawn subcommands")
  print("  /xive pawn scales [all]             – list active (or all) scales")
  print("  /xive pawn weights [name|key]       – show weights (active or by name/key)")
  print("  /xive pawn score <link> [scale <..>]– score with Pawn (optional scale)")
end

-- Namespace handler:
--   Dispatches `/xive pawn <sub> ...` commands.
Cmd.RegisterNamespace("pawn", function(rest)
  rest = tostring(rest or "")
  local sub, tail = rest:match("^(%S+)%s*(.*)$")
  sub = (sub or ""):lower()
  tail = tail or ""

  if sub == "" or sub == "help" then
    pawn_help();
    return
  end

  -- /xive pawn scales [all]
  --   Lists Pawn scale records. Default is active scales only.
  if sub == "scales" then
    local wantAll = (tail:lower():find("%f[%a]all%f[%A]", 1, false) ~= nil)
    local list = {}
    if XIVEquip.Pawn then
      if wantAll and XIVEquip.Pawn.GetAllScales then
        list = XIVEquip.Pawn.GetAllScales() or {}
      elseif (not wantAll) and XIVEquip.Pawn.GetActiveScales then
        list = XIVEquip.Pawn.GetActiveScales() or {}
      elseif XIVEquip.Pawn.GetAllScales then
        -- Fallback: if the Pawn integration doesn't expose active scales, show all.
        list = XIVEquip.Pawn.GetAllScales() or {}
      end
    end

    if type(list) ~= "table" or #list == 0 then
      print("  (none)")
      return
    end

    for _, r in ipairs(list) do
      print(string.format(
        "  %-35s  %-8s  key=%s  %s",
        tostring(r.name),
        tostring(r.type or "?"),
        tostring(r.key or "?"),
        r.active and "[ACTIVE]" or ""
      ))
    end
    return
  end

  -- /xive pawn weights [name|key]
  --   Dumps the weights table for a specific scale, or the first active scale.
  if sub == "weights" then
    local q = tail and tail:match("scale%s+(.+)$") or tail
    q = (q and q ~= "") and q or nil

    local entry = nil
    if q and XIVEquip.Pawn and XIVEquip.Pawn.GetAllScales then
      for _, r in ipairs(XIVEquip.Pawn.GetAllScales() or {}) do
        if (r.name and r.name:lower() == q:lower()) or (r.key and r.key:lower() == q:lower()) then
          entry = r
          break
        end
      end
    end

    if not entry and XIVEquip.Pawn and XIVEquip.Pawn.GetActiveScales then
      local active = XIVEquip.Pawn.GetActiveScales() or {}
      entry = active[1]
    end

    if not entry then
      print("  No Pawn scale found.")
      return
    end

    local vals = entry.values
    print("  Weights for:", entry.name or entry.key or "?")
    if type(vals) ~= "table" then
      print("   (no table available)")
      return
    end

    local ks = {}
    for k in pairs(vals) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do
      print("   ", k, "=", tostring(vals[k]))
    end
    return
  end

  -- /xive pawn score <link> [scale <name|key>]
  --   Scores a single item link using Pawn integration.
  if sub == "score" then
    local link = tail:match("(|c%x+|Hitem:[^|]+|h[^|]*|h|r)") or tail:match("(|Hitem:[^|]+|h[^|]*|h)")
    if not link then
      print("  Usage: /xive pawn score <link> [scale <name|key>]")
      return
    end

    if XIVEquip.Pawn and XIVEquip.Pawn.ScoreItemLink then
      local v, _, entry = XIVEquip.Pawn.ScoreItemLink(link)
      local scaleName = (entry and (entry.name or entry.key)) or "Pawn"
      print(string.format("  Score: %.2f (%s)", tonumber(v) or 0, scaleName))
    else
      print("  Pawn scoring not available.")
    end
    return
  end

  pawn_help()
end)

-- Contribute Pawn-specific lines to the global /xive help
Cmd.Help(" /xive pawn                          – Pawn module commands")
Cmd.Help(" /xive pawn scales [all]             – list Pawn scales (active or all)")
Cmd.Help(" /xive pawn weights [name | key]       – show weights (active or by name/key)")
Cmd.Help(" /xive pawn score <link> [scale <..>]– score with Pawn (optional scale)")
