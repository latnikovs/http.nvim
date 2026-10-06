-- Secrets from config.secrets, loaded once per project and session
local config = require("httpnvim.config")

local M = {}

local loaded = {} -- root -> { [env] = { name = value } }

function M.enabled()
  return type(config.options.secrets) == "function"
end

-- Secrets for the project if they are loaded, else nil
function M.get(proj)
  return loaded[proj.root]
end

function M.is_loaded(proj)
  return not M.enabled() or loaded[proj.root] ~= nil
end

-- Loads them if needed, then calls on_done(secrets) (nil after an error,
-- which is reported)
function M.load(proj, on_done)
  if not M.enabled() then
    on_done({})
    return
  end
  if loaded[proj.root] then
    on_done(loaded[proj.root])
    return
  end
  local ok, err = pcall(config.options.secrets, { name = proj.name, root = proj.root }, function(secrets, cb_err)
    vim.schedule(function()
      if not secrets then
        if cb_err then
          vim.notify("http.nvim: secrets: " .. cb_err, vim.log.levels.ERROR)
        end
        on_done(nil)
        return
      end
      loaded[proj.root] = secrets
      on_done(secrets)
      require("httpnvim").refresh()
    end)
  end)
  if not ok then
    vim.notify("http.nvim: secrets: " .. tostring(err), vim.log.levels.ERROR)
    on_done(nil)
  end
end

-- Top-level folder names of a project: the services
local function services(proj)
  local names = {}
  for name, kind in vim.fs.dir(proj.root) do
    if kind == "directory" and not name:match("^%.") then
      names[name] = true
    end
  end
  return names
end

-- Secrets by scope. A path that starts with a service (a top-level folder),
-- "integration/stag/client", applies to that service's requests only, as
-- "stag/client"; any other path applies to the whole project:
--   { project = { [env] = vars }, services = { [service] = { [env] = vars } } }
function M.split(proj, raw)
  local out = { project = {}, services = {} }
  if not raw then
    return out
  end
  local names = services(proj)
  for path, vars in pairs(raw) do
    local service, rest = path:match("^([^/]+)/(.+)$")
    if service and names[service] then
      out.services[service] = out.services[service] or {}
      out.services[service][rest] = vars
    else
      out.project[path] = vars
    end
  end
  return out
end

-- Forget loaded secrets (all projects, or one)
function M.reset(proj)
  if proj then
    loaded[proj.root] = nil
  else
    loaded = {}
  end
end

return M
