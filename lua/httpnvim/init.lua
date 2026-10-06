-- http.nvim: run requests from .http files through curl
local config = require("httpnvim.config")
local context = require("httpnvim.context")
local curl = require("httpnvim.curl")
local env = require("httpnvim.env")
local envfile = require("httpnvim.envfile")
local hints = require("httpnvim.hints")
local pane = require("httpnvim.pane")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")
local resolve = require("httpnvim.resolve")
local secrets = require("httpnvim.secrets")

local M = {}

local state = { job = nil, last = nil }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "http.nvim" })
end

function M.refresh()
  hints.refresh()
  local ok, sidebar = pcall(require, "httpnvim.sidebar")
  if ok then
    sidebar.refresh()
  end
end

-- Environments ---------------------------------------------------------------

local UNLOCK = "Unlock secrets…"

local function choose_env(proj, on_choice)
  local items = context.env_names(proj)
  if not secrets.is_loaded(proj) then
    table.insert(items, UNLOCK)
  end
  vim.ui.select(items, { prompt = "Environment (" .. proj.name .. ")" }, function(choice)
    if choice == UNLOCK then
      secrets.load(proj, function(loaded)
        if loaded then
          choose_env(proj, on_choice)
        end
      end)
    elseif choice then
      on_choice(choice)
    end
  end)
end

-- The project of the current directory, else of the current .http buffer
function M.project()
  local proj = project.from_cwd()
  if proj then
    return proj
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype == "http" and vim.api.nvim_buf_get_name(buf) ~= "" then
    return context.get(buf).project
  end
end

-- Selects an environment (asks when name is empty) for a project (default:
-- the current one)
function M.select_env(name, proj)
  proj = proj or M.project()
  if not proj then
    notify("No http project here", vim.log.levels.WARN)
    return
  end
  local function apply(choice)
    env.select(proj, choice)
    M.refresh()
    notify("Environment: " .. choice)
  end
  if name and name ~= "" then
    apply(name)
  else
    choose_env(proj, apply)
  end
end

-- Calls fn(env) with the project's environment, asking for one if none is
-- selected (nil if the project has none)
local function with_env(proj, fn)
  local selected = env.selected(proj)
  local names = context.env_names(proj)
  if selected then
    fn(selected)
  elseif #names == 0 then
    fn(nil)
  elseif #names == 1 then
    env.select(proj, names[1])
    M.refresh()
    fn(names[1])
  else
    choose_env(proj, function(choice)
      env.select(proj, choice)
      M.refresh()
      fn(choice)
    end)
  end
end

-- Variables ------------------------------------------------------------------

-- The {{name}} under the cursor in the current window, or nil
local function name_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  for _, ref in ipairs(parser.references(line)) do
    if col >= ref[2] and col < ref[3] then
      return ref[1]
    end
  end
end

-- Asks for a value and writes it for the selected environment. on_done(ok).
local function ask_and_set(buf, name, on_done)
  local ctx = context.get(buf)
  if not ctx.env then
    notify("Select or name an environment first (:HttpEnv)", vim.log.levels.WARN)
    return on_done(false)
  end
  local source = ctx.sources[name]
  if (source and source.kind == "secret") or env.secret_names(ctx.secrets)[name] then
    notify(name .. " comes from secrets; set it there", vim.log.levels.WARN)
    return on_done(false)
  end
  local current = ctx.vars[name] ~= nil and tostring(ctx.vars[name]) or ""
  vim.ui.input({ prompt = ("%s for %s: "):format(name, ctx.env), default = current }, function(value)
    if value == nil then
      return on_done(false)
    end
    local path = envfile.target(ctx, name)
    local ok, err = envfile.write(path, ctx.env, name, value)
    if not ok then
      notify("Can't set " .. name .. ": " .. err, vim.log.levels.ERROR)
      return on_done(false)
    end
    local shown = config.masked(name) and "••••" or value
    notify(("%s = %s for %s in %s"):format(name, shown, ctx.env, project.relative(ctx.project, path)))
    M.refresh()
    on_done(true)
  end)
end

-- Sets a variable (default: the one under the cursor) for the environment
function M.set_var(name)
  local buf = vim.api.nvim_get_current_buf()
  name = (name and name ~= "") and name or name_under_cursor()
  local proj = context.get(buf).project
  local function go(n)
    with_env(proj, function()
      ask_and_set(buf, n, function() end)
    end)
  end
  if name then
    go(name)
  else
    vim.ui.input({ prompt = "Variable: " }, function(input)
      if input and input ~= "" then
        go(vim.trim(input))
      end
    end)
  end
end

-- Jumps to where the variable under the cursor is defined; plain gd elsewhere
function M.goto_var()
  local name = name_under_cursor()
  if not name then
    vim.cmd("normal! gd")
    return
  end
  local ctx = context.get(0)
  local source = ctx.sources[name]
  if not source then
    notify(name .. " is not defined for " .. (ctx.env or "any environment"), vim.log.levels.WARN)
  elseif source.kind == "line" then
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { source.lnum, 0 })
  elseif source.kind == "secret" then
    notify(name .. " comes from secrets (" .. source.env .. ")")
  else
    vim.cmd("normal! m'")
    vim.cmd.edit(vim.fn.fnameescape(source.path))
    vim.api.nvim_win_set_cursor(0, { envfile.find_line(source.path, source.env, name), 0 })
    vim.cmd("normal! ^")
  end
end

-- Sending --------------------------------------------------------------------

-- Resolves req in buf, loading secrets and asking for undefined variables
-- (saved for the environment) as needed, then calls fn(resolved, ctx)
local function resolve_request(buf, req, fn, tried_secrets)
  local ctx = context.get(buf)
  local resolved, missing = resolve.request(req, ctx.vars)
  if resolved then
    return fn(resolved, ctx)
  end
  if not tried_secrets and not secrets.is_loaded(ctx.project) then
    return secrets.load(ctx.project, function(loaded)
      if loaded then
        resolve_request(buf, req, fn, true)
      end
    end)
  end
  local secret_names = env.secret_names(ctx.secrets)
  for _, name in ipairs(missing) do
    if secret_names[name] then
      notify(("%s is not in the secrets for %s"):format(name, ctx.env or "this environment"), vim.log.levels.ERROR)
      return
    end
  end
  if not ctx.env then
    notify("Undefined: " .. table.concat(missing, ", ") .. " (no environment selected)", vim.log.levels.ERROR)
    return
  end
  local i = 0
  local function next_name(ok)
    if ok == false then
      return
    end
    i = i + 1
    if i > #missing then
      return resolve_request(buf, req, fn, true)
    end
    ask_and_set(buf, missing[i], next_name)
  end
  next_name()
end

-- Sends a resolved request; the response opens below anchor (a window)
function M.send(req, env_name, anchor)
  M.cancel()
  state.last = { request = req, env = env_name, anchor = anchor }
  pane.update({ request = req, env = env_name, running = true }, anchor)
  local job
  job = curl.run(req, function(result)
    if state.job ~= job then
      return -- replaced by a newer request
    end
    state.job = nil
    result.request, result.env = req, env_name
    pane.update(result, anchor)
  end)
  state.job = job
end

-- Sends the request at a line of a buffer (default: under the cursor)
function M.send_at(buf, lnum, anchor)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  anchor = anchor or vim.api.nvim_get_current_win()
  local ctx = context.get(buf)
  local req = parser.at(ctx.lines, lnum)
  if not req then
    notify("No request here", vim.log.levels.WARN)
    return
  end
  with_env(ctx.project, function()
    resolve_request(buf, req, function(resolved, rctx)
      M.send(resolved, rctx.env, anchor)
    end)
  end)
end

function M.replay()
  if not state.last then
    notify("No request sent yet", vim.log.levels.WARN)
    return
  end
  M.send(state.last.request, state.last.env, state.last.anchor)
end

function M.cancel()
  if state.job then
    state.job:kill("sigterm")
  end
end

function M.copy_curl()
  local buf = vim.api.nvim_get_current_buf()
  local ctx = context.get(buf)
  local req = parser.at(ctx.lines, vim.api.nvim_win_get_cursor(0)[1])
  if not req then
    notify("No request here", vim.log.levels.WARN)
    return
  end
  with_env(ctx.project, function()
    resolve_request(buf, req, function(resolved)
      vim.fn.setreg("+", curl.command(resolved))
      notify("Copied curl command")
    end)
  end)
end

function M.jump(forward)
  vim.fn.search("^###", forward and "W" or "bW")
end

function M.toggle()
  require("httpnvim.sidebar").toggle()
end

-- Adds a request below the one under the cursor (headers copied from it)
function M.new_request()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  require("httpnvim.scaffold").ask_request(function(name, input)
    local line = require("httpnvim.scaffold").insert_request(buf, lnum, name, input)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
  end)
end

function M.view(name)
  if name and name ~= "" then
    pane.set_view(name)
  else
    pane.cycle(1)
  end
end

function M.close()
  pane.close()
end

-- Setup ----------------------------------------------------------------------

local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

function M.setup(opts)
  config.setup(opts)
  hints.setup()
  require("httpnvim.sidebar").setup()
  command("HttpSend", function()
    M.send_at()
  end, { desc = "Send the request under the cursor" })
  command("HttpReplay", M.replay, { desc = "Send the last request again" })
  command("HttpCancel", M.cancel, { desc = "Cancel the running request" })
  command("HttpCurl", M.copy_curl, { desc = "Copy the request under the cursor as curl" })
  command("HttpToggle", M.toggle, { desc = "Toggle the sidebar" })
  command("HttpNew", M.new_request, { desc = "Add a request below the current one" })
  command("HttpEnv", function(o)
    M.select_env(o.args)
  end, {
    nargs = "?",
    desc = "Select an environment",
    complete = function()
      local proj = M.project()
      return proj and context.env_names(proj) or {}
    end,
  })
  command("HttpSetVar", function(o)
    M.set_var(o.args)
  end, { nargs = "?", desc = "Set a variable for the environment" })
  command("HttpView", function(o)
    M.view(o.args)
  end, {
    nargs = "?",
    complete = function()
      return pane.VIEWS
    end,
    desc = "Show the response body, headers or request",
  })
  command("HttpSecretsReset", function()
    secrets.reset()
    M.refresh()
  end, { desc = "Forget loaded secrets" })
end

return M
