-- The IntelliJ HTTP Client format, as far as http.nvim reads it:
--
--   @base = http://localhost:8080        file variable (whole file)
--
--   ### Create order                     starts a request; the rest is its name
--   POST {{base}}/orders                 method (GET if left out) and URL
--       ?page=1                          the URL can go on in indented ?/& lines
--   Content-Type: application/json       headers up to the first blank line
--
--   { "id": 1 }                          then the body
--
-- Lines starting with # or // before the body are comments.
local M = {}

M.METHODS = {
  GET = true,
  POST = true,
  PUT = true,
  PATCH = true,
  DELETE = true,
  HEAD = true,
  OPTIONS = true,
  TRACE = true,
  CONNECT = true,
}

local function is_separator(line)
  return line:match("^###") ~= nil
end

local function is_comment(line)
  return line:match("^%s*#") ~= nil or line:match("^%s*//") ~= nil
end

local function is_file_var(line)
  return line:match("^@[%w_.-]+%s*=") ~= nil
end

-- @name = value lines anywhere in the document, in order. Returns the values
-- and the line number of each.
function M.file_vars(lines)
  local vars, where = {}, {}
  for i, line in ipairs(lines) do
    local name, value = line:match("^@([%w_.-]+)%s*=%s*(.-)%s*$")
    if name then
      vars[name] = value
      where[name] = i
    end
  end
  return vars, where
end

-- Request line, headers up to the first blank line, then the body. Returns
-- nil when the lines hold no request (only comments or variables). line is
-- the request line's index in lines.
function M.parse(lines)
  local i = 1
  while i <= #lines and (lines[i]:match("^%s*$") or is_comment(lines[i]) or is_file_var(lines[i])) do
    i = i + 1
  end
  if i > #lines then
    return nil
  end
  local line = i
  local method, url = lines[i]:match("^(%u+)%s+(%S+)")
  if not (method and M.METHODS[method]) then
    method, url = "GET", lines[i]:match("^%s*(%S+)")
  end
  i = i + 1
  while i <= #lines and lines[i]:match("^%s+[?&]") do
    url = url .. vim.trim(lines[i])
    i = i + 1
  end

  local headers = {}
  while i <= #lines and not lines[i]:match("^%s*$") do
    if not is_comment(lines[i]) then
      local name, value = lines[i]:match("^%s*([^:%s]+)%s*:%s*(.-)%s*$")
      if name then
        table.insert(headers, { name, value })
      end
    end
    i = i + 1
  end

  local body = vim.list_slice(lines, i + 1)
  while #body > 0 and body[#body]:match("^%s*$") do
    table.remove(body)
  end
  return {
    method = method,
    url = url,
    headers = headers,
    body = #body > 0 and table.concat(body, "\n") or nil,
    line = line,
  }
end

-- Start (the ### line, or 1) and end line of the block around lnum
local function bounds(lines, lnum)
  local first, last = 1, #lines
  for i = math.min(lnum, #lines), 1, -1 do
    if is_separator(lines[i]) then
      first = i
      break
    end
  end
  for i = lnum + 1, #lines do
    if is_separator(lines[i]) then
      last = i - 1
      break
    end
  end
  return first, last
end

local function parse_block(lines, first, last)
  local name
  local start = first
  if is_separator(lines[first] or "") then
    name = vim.trim((lines[first]:gsub("^#+", "")))
    start = first + 1
  end
  local req = M.parse(vim.list_slice(lines, start, last))
  if not req then
    return nil
  end
  req.lnum = start + req.line - 1
  req.name = (name and name ~= "") and name or (req.method .. " " .. req.url)
  return req
end

-- The request around a 1-based line, or nil
function M.at(lines, lnum)
  return parse_block(lines, bounds(lines, lnum))
end

-- Every request in the document, in order
function M.requests(lines)
  local starts = { 1 }
  for i, line in ipairs(lines) do
    if is_separator(line) and i > 1 then
      table.insert(starts, i)
    end
  end
  local out = {}
  for n, first in ipairs(starts) do
    local last = (starts[n + 1] or #lines + 1) - 1
    local req = parse_block(lines, first, last)
    if req then
      table.insert(out, req)
    end
  end
  return out
end

-- {{name}} references in a line: { name, start col, end col } (0-based, end exclusive)
function M.references(line)
  local refs = {}
  local init = 1
  while true do
    local s, e, name = line:find("{{%s*(.-)%s*}}", init)
    if not s then
      break
    end
    table.insert(refs, { name, s - 1, e })
    init = e + 1
  end
  return refs
end

return M
