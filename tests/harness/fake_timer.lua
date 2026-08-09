-- tests/harness/fake_timer.lua
-- Fakes C_Timer.After with a FIFO queue, lifted from the pattern already
-- proven in tests/specs/equip_execution_spec.lua. Callbacks scheduled by
-- earlier callbacks are appended and drained in order, modeling the async
-- chaining Gear:_runEquipPlan relies on (lock-retry, verify, step, finish).

local FakeTimer = {}

-- Installs the fake and returns a settle(maxSteps) function that drains the
-- queue. Call settle() after invoking any code path that schedules timers
-- (e.g. Gear:EquipBest) to run it to completion synchronously.
function FakeTimer.Install()
  local queue = {}

  _G.C_Timer = {
    After = function(_, fn)
      queue[#queue + 1] = fn
    end,
  }

  return function(maxSteps)
    maxSteps = maxSteps or 200
    local steps = 0
    while #queue > 0 do
      steps = steps + 1
      if steps > maxSteps then error("timer queue did not settle", 2) end
      local fn = table.remove(queue, 1)
      fn()
    end
  end
end

return FakeTimer
