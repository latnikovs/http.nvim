-- Running a resolved request through curl
local config = require("httpnvim.config")

local M = {}

-- curl arguments for a request. When running, the body comes from body_file
-- (an argument can't hold more than 128 KB); a copied command has it inline.
function M.args(req, body_file)
  local args = vim.deepcopy(config.options.curl)
  if req.method == "HEAD" then
    table.insert(args, "--head")
  elseif not (req.method == "GET" and not req.body) and not (req.method == "POST" and req.body) then
    vim.list_extend(args, { "-X", req.method })
  end
  for _, h in ipairs(req.headers) do
    vim.list_extend(args, { "-H", h[1] .. ": " .. h[2] })
  end
  if body_file then
    vim.list_extend(args, { "--data-binary", "@" .. body_file })
  elseif req.body then
    vim.list_extend(args, { "--data-raw", req.body })
  end
  table.insert(args, req.url)
  return args
end

-- A shell command for the request, quoting only what needs it
function M.command(req)
  return table.concat(
    vim.tbl_map(function(arg)
      return arg:match("^[%w_./:=@%%+-]+$") and arg or vim.fn.shellescape(arg)
    end, M.args(req)),
    " "
  )
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return ""
  end
  local text = f:read("*a")
  f:close()
  return text
end

-- The last header block curl wrote (each redirect adds one)
function M.parse_headers(text)
  local blocks = vim.split(vim.trim((text:gsub("\r", ""))), "\n%s*\n")
  local lines = vim.split(blocks[#blocks], "\n", { plain = true })
  local headers = {}
  for i = 2, #lines do
    local name, value = lines[i]:match("^([^:]+):%s*(.*)$")
    if name then
      table.insert(headers, { name, value })
    end
  end
  return lines, headers
end

-- Runs the request; on_done gets { response } or { error, cancelled } on the
-- main loop. Returns the vim.system handle.
function M.run(req, on_done)
  local files = { body = vim.fn.tempname(), headers = vim.fn.tempname(), out = vim.fn.tempname() }
  if req.body then
    local f = assert(io.open(files.body, "wb"))
    f:write(req.body)
    f:close()
  end
  local args = M.args(req, req.body and files.body)
  local url = table.remove(args)
  vim.list_extend(
    args,
    { "-D", files.headers, "-o", files.out, "-w", "%{http_code} %{time_total} %{size_download}", url }
  )
  return vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      local header_text, body = read_file(files.headers), read_file(files.out)
      for _, path in pairs(files) do
        os.remove(path)
      end
      if res.signal ~= 0 then
        on_done({ error = "Cancelled", cancelled = true })
        return
      end
      if res.code ~= 0 then
        on_done({ error = vim.trim(res.stderr) })
        return
      end
      local status, seconds, size = res.stdout:match("(%d+) ([%d.]+) (%d+)")
      local header_lines, headers = M.parse_headers(header_text)
      on_done({
        response = {
          status = tonumber(status) or 0,
          ms = math.floor((tonumber(seconds) or 0) * 1000 + 0.5),
          size = tonumber(size) or 0,
          header_lines = header_lines,
          headers = headers,
          body = body,
        },
      })
    end)
  end)
end

return M
