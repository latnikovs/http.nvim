-- Filling in {{variables}}
local M = {}

local function uuid()
  return (
    ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
      local v = c == "x" and vim.fn.rand() % 16 or 8 + vim.fn.rand() % 4
      return ("%x"):format(v)
    end)
  )
end

M.DYNAMIC = {
  ["$uuid"] = uuid,
  ["$random.uuid"] = uuid,
  ["$timestamp"] = function()
    return tostring(os.time())
  end,
  ["$isoTimestamp"] = function()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
  end,
}

-- Replace {{name}} in text; values may use other variables. Names that
-- resolve to nothing are added to missing (a set).
function M.expand(text, vars, missing, depth)
  depth = depth or 0
  return (
    text:gsub("{{%s*(.-)%s*}}", function(name)
      if M.DYNAMIC[name] then
        return M.DYNAMIC[name]()
      end
      local value = vars[name]
      if value == nil or depth > 10 then
        missing[name] = true
        return nil
      end
      return M.expand(tostring(value), vars, missing, depth + 1)
    end)
  )
end

-- One variable's final value, or nil and the names it lacks
function M.value(name, vars)
  local missing = {}
  local value = M.expand("{{" .. name .. "}}", vars, missing)
  if next(missing) then
    return nil, missing
  end
  return value
end

-- "Basic user password" or "Basic user:password", as IntelliJ takes it, is
-- sent encoded; an encoded value has neither space nor colon
local function basic_auth(name, value)
  local user, password = value:match("^Basic%s+([^%s:]+)[%s:]+(.+)$")
  if name:lower() == "authorization" and user then
    return "Basic " .. vim.base64.encode(user .. ":" .. password)
  end
  return value
end

-- The request with every variable filled in, and a sorted list of the names
-- that are missing (the request is nil then)
function M.request(req, vars)
  local missing = {}
  local out = { method = req.method, headers = {}, name = req.name, lnum = req.lnum }
  out.url = M.expand(req.url, vars, missing)
  for _, h in ipairs(req.headers) do
    table.insert(out.headers, { h[1], basic_auth(h[1], M.expand(h[2], vars, missing)) })
  end
  out.body = req.body and M.expand(req.body, vars, missing)
  local names = vim.tbl_keys(missing)
  if #names > 0 then
    table.sort(names)
    return nil, names
  end
  return out, {}
end

return M
