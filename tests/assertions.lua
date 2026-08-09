local A = {}

function A.equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message or "assertion failed", tostring(expected), tostring(actual)), 2)
  end
end

function A.truthy(value, message)
  if not value then
    error(message or "expected truthy value", 2)
  end
end

function A.falsy(value, message)
  if value then
    error(message or "expected falsy value", 2)
  end
end

local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function A.same(actual, expected, message)
  if not deepEqual(actual, expected) then
    error(string.format("%s: values are not equal", message or "assertion failed"), 2)
  end
end

function A.contains(list, substring, message)
  for _, item in ipairs(list or {}) do
    if tostring(item):find(substring, 1, true) then return end
  end
  error(string.format("%s: none of %d item(s) contained '%s'", message or "assertion failed", #(list or {}), tostring(substring)), 2)
end

return A
