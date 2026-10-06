local M = {}

M.defaults = {
  -- Secrets for a project, merged over the env files:
  --   function(project, callback) ... callback({ ["stag/client"] = { password = "…" } }) end
  -- project is { name = "wms", root = "/…/wms/http" }; call callback(nil, err)
  -- on failure. Called once per project and session: when the sidebar opens
  -- (sidebar.unlock), else on the first request that needs a variable the env
  -- files don't have.
  secrets = nil,
  -- Variable names (Lua patterns, matched case-insensitively) whose values are
  -- masked in hints and in the request view
  mask = { "password", "secret", "token", "apikey", "api_key" },
  -- Headers masked in the request view
  mask_headers = { "authorization", "cookie", "x%-api%-key" },
  -- unlock: opening the sidebar loads the secrets (if not yet loaded), then
  -- asks for the environment
  sidebar = { width = 40, unlock = true },
  -- Response pane height, as a fraction of the request window
  pane = { height = 0.45 },
  hints = { enabled = true, max_width = 40 },
  -- Variables that belong to a service, not a client: set from a request,
  -- they go into the env file of its top-level folder (the service) at the
  -- environment's top level ("stag" for "stag/client"), where the sidebar's
  -- b puts the base URL
  service_vars = { "base" },
  curl = { "curl", "-sS", "-L", "--compressed" },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

local function matches(name, patterns)
  name = name:lower()
  for _, pattern in ipairs(patterns) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

function M.masked(name)
  return matches(name, M.options.mask)
end

function M.masked_header(name)
  return matches(name, M.options.mask_headers)
end

return M
