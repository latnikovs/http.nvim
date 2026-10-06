-- Getting started: creating a project's http/ folder, a service folder with
-- its base URLs, and new requests
local context = require("httpnvim.context")
local envfile = require("httpnvim.envfile")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")

local M = {}

-- Headers for the first request of a file
M.DEFAULT_HEADERS = { "Authorization: Basic {{username}} {{password}}", "Accept: application/json" }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "http.nvim" })
end

-- Projects --------------------------------------------------------------------

-- Where a new http/ folder goes: the git root around dir, else dir
function M.repo_root(dir)
  return vim.fs.root(dir, ".git") or dir
end

-- An env file with these environments, empty
function M.env_json(names)
  if #names == 0 then
    return "{}"
  end
  local parts = vim.tbl_map(function(name)
    return ("  %s: {}"):format(vim.json.encode(name))
  end, names)
  return "{\n" .. table.concat(parts, ",\n") .. "\n}"
end

-- Keeps private env files out of git, locally (.git/info/exclude)
local function exclude_private(repo)
  local info = repo .. "/.git/info"
  if not vim.uv.fs_stat(repo .. "/.git") or vim.fn.isdirectory(repo .. "/.git") == 0 then
    return
  end
  vim.fn.mkdir(info, "p")
  local path = info .. "/exclude"
  local lines = vim.uv.fs_stat(path) and vim.fn.readfile(path) or {}
  if not vim.tbl_contains(lines, project.PRIVATE_ENV_FILE) then
    table.insert(lines, project.PRIVATE_ENV_FILE)
    vim.fn.writefile(lines, path)
  end
end

-- Creates <repo>/http with an env file for the given environments; returns
-- the project
function M.create_project(repo, names)
  local root = repo .. "/http"
  vim.fn.mkdir(root, "p")
  local env_path = root .. "/" .. project.ENV_FILE
  if not vim.uv.fs_stat(env_path) then
    vim.fn.writefile(vim.split(M.env_json(names), "\n", { plain = true }), env_path)
  end
  exclude_private(repo)
  return project.find(root)
end

-- Asks whether to create an http/ folder for the current directory's
-- repository, and for its environments; on_done(project) when created
function M.offer_project(on_done)
  local repo = M.repo_root(vim.fn.getcwd())
  local name = vim.fs.basename(repo)
  if vim.fn.confirm(("No http/ folder in %s. Create one?"):format(name), "&Yes\n&No", 1) ~= 1 then
    return
  end
  vim.ui.input({ prompt = "Environments (comma-separated): ", default = "stag" }, function(input)
    if input == nil then
      return
    end
    local names = {}
    for part in vim.gsplit(input, ",", { plain = true }) do
      part = vim.trim(part)
      if part ~= "" then
        table.insert(names, part)
      end
    end
    local proj = M.create_project(repo, names)
    notify(("Created %s"):format(vim.fn.fnamemodify(proj.root, ":~")))
    on_done(proj)
  end)
end

-- Services --------------------------------------------------------------------

-- Top-level environments of a project ("stag", not "stag/client"): where a
-- service's base URL goes
function M.base_envs(proj)
  return vim.tbl_filter(function(name)
    return not name:find("/", 1, true)
  end, context.env_names(proj))
end

-- Asks for the base URL of a new service folder per environment and writes
-- the folder's env file. on_done() at the end.
function M.ask_bases(proj, dir, on_done)
  local names = M.base_envs(proj)
  local i = 0
  local function next_env()
    i = i + 1
    if i > #names then
      return on_done()
    end
    vim.ui.input({ prompt = ("Base URL for %s (empty to skip): "):format(names[i]) }, function(url)
      if url == nil then
        return on_done()
      end
      url = vim.trim(url):gsub("/+$", "")
      if url ~= "" then
        local ok, err = envfile.write(dir .. "/" .. project.ENV_FILE, names[i], "base", url)
        if not ok then
          notify("Can't save the base URL: " .. err, vim.log.levels.ERROR)
        end
      end
      next_env()
    end)
  end
  next_env()
end

-- Requests --------------------------------------------------------------------

-- "GET /path" -> method and URL; paths go after {{base}}, full URLs stay
function M.request_line(input)
  input = vim.trim(input)
  local method, rest = input:match("^(%a+)%s+(.+)$")
  if not (method and parser.METHODS[method:upper()]) then
    method, rest = "GET", input
  end
  method = method:upper()
  local url = vim.trim(rest)
  if not url:match("^%a[%w+.-]*://") and not url:match("^{{") then
    url = "{{base}}" .. (url:sub(1, 1) == "/" and "" or "/") .. url
  end
  return method .. " " .. url
end

-- Lines of a new request, with the headers of template (a parsed request) or
-- the defaults
function M.request_lines(name, input, template)
  local lines = { "### " .. name, M.request_line(input) }
  if template then
    for _, h in ipairs(template.headers) do
      table.insert(lines, h[1] .. ": " .. h[2])
    end
  else
    vim.list_extend(lines, M.DEFAULT_HEADERS)
  end
  return lines
end

-- Asks for a name and "METHOD path", calls fn(name, input)
function M.ask_request(fn)
  vim.ui.input({ prompt = "Request name: " }, function(name)
    if not name or vim.trim(name) == "" then
      return
    end
    vim.ui.input({ prompt = "Method and path: ", default = "GET /" }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      fn(vim.trim(name), input)
    end)
  end)
end

-- Adds a request to buf after the request around lnum (at the end when lnum
-- is nil), copying that request's headers. Returns the request line.
function M.insert_request(buf, lnum, name, input)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local requests = parser.requests(lines)
  local template, insert_at = nil, #lines
  for i, req in ipairs(requests) do
    if not lnum or req.lnum <= lnum then
      template = req
      local next_req = requests[i + 1]
      insert_at = #lines
      if next_req then
        -- Before the next request's ### line
        local sep = next_req.lnum
        while sep > 1 and not lines[sep]:match("^###") do
          sep = sep - 1
        end
        insert_at = sep - 1
      end
    end
  end
  if lnum and not template and requests[1] then
    template = requests[1]
    insert_at = 0
  end
  -- Drop trailing blank lines before the insert point
  while insert_at > 0 and lines[insert_at]:match("^%s*$") do
    insert_at = insert_at - 1
  end
  local new = M.request_lines(name, input, template)
  if insert_at > 0 then
    table.insert(new, 1, "")
  end
  local after = lines[insert_at + 1]
  if after and not after:match("^%s*$") then
    table.insert(new, "")
  end
  if #lines == 1 and lines[1] == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
    return 2
  end
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new)
  return insert_at + (insert_at > 0 and 3 or 2)
end

return M
