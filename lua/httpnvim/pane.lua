-- The response pane: one per tab, below the window the request was sent
-- from. Three views: body (JSON formatted with jq), headers, and the request
-- as it was sent. The window bar sums it up.
local config = require("httpnvim.config")

local M = {}

local state = { buf = nil, view = "body", result = nil }

M.VIEWS = { "body", "headers", "request" }

local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

local function human_size(bytes)
  if bytes < 1024 then
    return bytes .. " B"
  elseif bytes < 1024 * 1024 then
    return ("%.1f KB"):format(bytes / 1024)
  end
  return ("%.1f MB"):format(bytes / 1024 / 1024)
end

function M.buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "httpnvim://response")
  vim.bo[buf].bufhidden = "hide"
  local map = function(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc })
  end
  map("q", M.close, "Close Response")
  map("<C-c>", function()
    require("httpnvim").cancel()
  end, "Cancel Request")
  map("<Tab>", function()
    M.cycle(1)
  end, "Next View")
  map("<S-Tab>", function()
    M.cycle(-1)
  end, "Previous View")
  state.buf = buf
  return buf
end

function M.win()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == state.buf then
      return win
    end
  end
end

-- The pane's window, opened below anchor (the request window) if it isn't
-- open in this tab. Focus stays where it is.
local function open(anchor)
  local win = M.win()
  if win then
    return win
  end
  anchor = (anchor and vim.api.nvim_win_is_valid(anchor)) and anchor or 0
  local height = math.max(5, math.floor(vim.api.nvim_win_get_height(anchor) * config.options.pane.height))
  win = vim.api.nvim_open_win(M.buf(), false, { split = "below", win = anchor, height = height })
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  return win
end

local function show(lines, filetype, winbar, anchor)
  local buf = M.buf()
  local win = open(anchor)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = filetype
  vim.wo[win].wrap = false -- after the filetype, whose plugins may set it
  vim.wo[win].winbar = winbar
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

local function header(headers, name)
  name = name:lower()
  for _, h in ipairs(headers) do
    if h[1]:lower() == name then
      return h[2]
    end
  end
end

local function body_filetype(content_type)
  content_type = (content_type or ""):lower()
  for _, pair in ipairs({ { "json", "json" }, { "html", "html" }, { "xml", "xml" }, { "javascript", "javascript" } }) do
    if content_type:find(pair[1], 1, true) then
      return pair[2]
    end
  end
  return "text"
end

local function request_lines(req)
  local lines = { req.method .. " " .. req.url }
  for _, h in ipairs(req.headers) do
    local value = config.masked_header(h[1]) and (h[2]:match("^(%S+%s)") or "") .. "••••" or h[2]
    table.insert(lines, h[1] .. ": " .. value)
  end
  if req.body then
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(req.body, "\n", { plain = true }))
  end
  return lines
end

local function render(anchor)
  local result = state.result
  if not result then
    return
  end
  local req, r = result.request, result.response
  -- The URL goes last, after %<, so a long one is cut instead of the status
  local target = "%<" .. escape(req.method .. " " .. req.url)
  local env = result.env and (escape(result.env) .. " · ") or ""
  local view = state.view ~= "body" and (state.view .. " · ") or ""

  if result.running then
    show({}, "text", " Sending… (<C-c> cancels) · " .. env .. target, anchor)
    return
  end
  if result.error then
    local lines = state.view == "request" and request_lines(req) or vim.split(result.error, "\n")
    show(lines, "text", " %#DiagnosticError#failed%* · " .. env .. view .. target, anchor)
    return
  end

  local hl = r.status >= 400 and "DiagnosticError" or r.status >= 300 and "DiagnosticWarn" or "DiagnosticOk"
  local winbar = ("%%#%s# %d %%* %d ms · %s · %s%s%s"):format(
    hl,
    r.status,
    r.ms,
    human_size(r.size),
    env,
    view,
    target
  )
  if state.view == "headers" then
    show(r.header_lines, "http", winbar, anchor)
  elseif state.view == "request" then
    show(request_lines(req), "http", winbar, anchor)
  else
    local ft = body_filetype(header(r.headers, "content-type"))
    local body = r.body
    if ft == "json" and vim.fn.executable("jq") == 1 then
      local res = vim.system({ "jq", "." }, { stdin = body, text = true }):wait()
      if res.code == 0 then
        body = res.stdout
      end
    end
    show(vim.split((body:gsub("\n$", "")), "\n", { plain = true }), ft, winbar, anchor)
  end
end

-- result: { request, env, running } | { request, env, response } | { request, env, error }
function M.update(result, anchor)
  state.result = result
  render(anchor)
end

function M.set_view(view)
  state.view = view
  render()
end

function M.cycle(step)
  local i = 1
  for n, view in ipairs(M.VIEWS) do
    if view == state.view then
      i = n
    end
  end
  M.set_view(M.VIEWS[(i - 1 + step) % #M.VIEWS + 1])
end

function M.close()
  local win = M.win()
  if win then
    pcall(vim.api.nvim_win_close, win, false)
  end
end

return M
