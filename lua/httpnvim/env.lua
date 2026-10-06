-- Environments. Names form a hierarchy with "/": selecting "stag/client"
-- applies "$shared", then "stag", then "stag/client", each level over the
-- one before. Env files are read in every folder from the project root down
-- to the request's folder (public, then private), and for each level a
-- nearer file wins. Secrets (config.secrets) go over all of it, the request's
-- service's own over the project's, and env values go over @variables in the
-- .http file, as in IntelliJ.
local project = require("httpnvim.project")

local M = {}

local cache = {}

-- An env file's contents, re-read when it changes on disk; nil if absent
function M.read(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    cache[path] = nil
    return nil
  end
  local hit = cache[path]
  if hit and hit.mtime == stat.mtime.sec and hit.nsec == stat.mtime.nsec and hit.size == stat.size then
    return hit.data
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(data) ~= "table" then
    vim.notify("http.nvim: can't read " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.ERROR)
    data = {}
  end
  cache[path] = { mtime = stat.mtime.sec, nsec = stat.mtime.nsec, size = stat.size, data = data }
  return data
end

-- Env files that apply to a folder, root first: { path, data, private }
function M.files(proj, dir)
  local files = {}
  for _, d in ipairs(project.chain(proj, dir)) do
    for _, spec in ipairs({ { project.ENV_FILE, false }, { project.PRIVATE_ENV_FILE, true } }) do
      local path = d .. "/" .. spec[1]
      local data = M.read(path)
      if data then
        table.insert(files, { path = path, data = data, private = spec[2] })
      end
    end
  end
  return files
end

-- Every env file in the project, for the list of environment names
function M.all_files(proj)
  local files = {}
  local found = vim.fs.find(function(name)
    return name == project.ENV_FILE or name == project.PRIVATE_ENV_FILE
  end, { path = proj.root, type = "file", limit = math.huge })
  for _, path in ipairs(found) do
    local data = M.read(path)
    if data then
      table.insert(files, { path = path, data = data })
    end
  end
  return files
end

-- "stag/client" -> { "$shared", "stag", "stag/client" }
function M.levels(env)
  local levels = { "$shared" }
  if env then
    local parts = vim.split(env, "/", { plain = true })
    for i = 1, #parts do
      table.insert(levels, table.concat(parts, "/", 1, i))
    end
  end
  return levels
end

-- Sorted environment names from env files and secrets
function M.names(files, secrets)
  local seen = {}
  for _, file in ipairs(files) do
    for name in pairs(file.data) do
      if not name:match("^%$") then
        seen[name] = true
      end
    end
  end
  for name in pairs(secrets or {}) do
    if not name:match("^%$") then
      seen[name] = true
    end
  end
  local names = vim.tbl_keys(seen)
  table.sort(names)
  return names
end

-- Variables for one environment and where each came from:
--   vars[name] = value
--   sources[name] = { kind = "file"|"secret"|"line"|"session", path, private, env, lnum, service }
-- secrets are the project's, service is { name, secrets } for the request's
-- service; file_vars/file_lines are the @variables of the .http file;
-- session holds values set in this session, over files but not secrets.
function M.vars(files, env, secrets, file_vars, file_lines, service, session)
  local vars, sources = {}, {}
  for name, value in pairs(file_vars or {}) do
    vars[name] = value
    sources[name] = { kind = "line", lnum = file_lines and file_lines[name] }
  end
  for _, level in ipairs(M.levels(env)) do
    for _, file in ipairs(files) do
      local section = file.data[level]
      if type(section) == "table" then
        for name, value in pairs(section) do
          vars[name] = value
          sources[name] = { kind = "file", path = file.path, private = file.private, env = level }
        end
      end
    end
    local scopes = { { secrets = secrets } }
    if service then
      table.insert(scopes, { secrets = service.secrets, service = service.name })
    end
    if level == env then
      for name, value in pairs(session or {}) do
        vars[name] = value
        sources[name] = { kind = "session", env = level }
      end
    end
    for _, scope in ipairs(scopes) do
      local section = scope.secrets and scope.secrets[level]
      if type(section) == "table" then
        for name, value in pairs(section) do
          vars[name] = value
          sources[name] = { kind = "secret", env = level, service = scope.service }
        end
      end
    end
  end
  return vars, sources
end

-- Names that come from secrets in any environment
function M.secret_names(secrets)
  local names = {}
  for _, section in pairs(secrets or {}) do
    if type(section) == "table" then
      for name in pairs(section) do
        names[name] = true
      end
    end
  end
  return names
end

-- Throwaway values (ids and such) set for an environment, kept in memory
-- for the nvim session only: project root -> env -> name -> value
local session = {}

function M.session(proj, env)
  return env and session[proj.root] and session[proj.root][env] or {}
end

-- Sets a session value; nil or "" forgets it
function M.session_set(proj, env, name, value)
  session[proj.root] = session[proj.root] or {}
  session[proj.root][env] = session[proj.root][env] or {}
  session[proj.root][env][name] = value ~= "" and value or nil
end

-- Selected environment per project root, kept across sessions
local state_path = vim.fn.stdpath("state") .. "/httpnvim.json"
local selected

local function load_selected()
  if selected then
    return selected
  end
  selected = {}
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
  end)
  if ok and type(data) == "table" and type(data.env) == "table" then
    selected = data.env
  end
  return selected
end

function M.selected(proj)
  return load_selected()[proj.root]
end

function M.select(proj, env)
  load_selected()[proj.root] = env
  vim.fn.mkdir(vim.fs.dirname(state_path), "p")
  pcall(vim.fn.writefile, { vim.json.encode({ env = selected }) }, state_path)
end

-- For tests
function M._reset(path)
  state_path = path or state_path
  selected = nil
  cache = {}
  session = {}
end

return M
