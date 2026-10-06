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

-- Forget loaded secrets (all projects, or one)
function M.reset(proj)
  if proj then
    loaded[proj.root] = nil
  else
    loaded = {}
  end
end

return M
