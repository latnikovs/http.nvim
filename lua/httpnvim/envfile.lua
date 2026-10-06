-- Writing variables into env files, per environment
local env = require("httpnvim.env")
local project = require("httpnvim.project")

local M = {}

-- The file a variable is written to: the env file that defines it now if it
-- comes from one, else the nearest env file above the request's folder, else
-- a new one at the project root
function M.target(ctx, name)
  local source = ctx.sources[name]
  if source and source.kind == "file" then
    return source.path
  end
  for i = #ctx.files, 1, -1 do
    if not ctx.files[i].private then
      return ctx.files[i].path
    end
  end
  return ctx.project.root .. "/" .. project.ENV_FILE
end

-- Sets env_name.name = value in the file with jq, which keeps the key order
-- and adds new keys at the end. Returns true or nil and an error.
function M.write(path, env_name, name, value)
  if vim.fn.executable("jq") ~= 1 then
    return nil, "setting variables needs jq"
  end
  local text = "{}"
  if vim.uv.fs_stat(path) then
    text = table.concat(vim.fn.readfile(path), "\n")
  end
  local res = vim
    .system({
      "jq",
      "--indent",
      "2",
      "--arg",
      "env",
      env_name,
      "--arg",
      "name",
      name,
      "--arg",
      "value",
      value,
      ".[$env][$name] = $value",
    }, { stdin = text, text = true })
    :wait()
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr)
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if vim.fn.writefile(vim.split(vim.trim(res.stdout), "\n", { plain = true }), path) ~= 0 then
    return nil, "can't write " .. path
  end
  -- Buffers showing the file pick up the change
  vim.cmd("silent! checktime")
  env.read(path)
  return true
end

-- Line of a variable's definition in an env file: the "name" key after the
-- "env" key, or the env key itself
function M.find_line(path, env_name, name)
  local lines = vim.fn.readfile(path)
  local function key(k)
    return '^%s*"' .. vim.pesc(k) .. '"%s*:'
  end
  for i, line in ipairs(lines) do
    if line:find(key(env_name)) then
      for j = i, #lines do
        if j > i and lines[j]:find('^%s*"[^"]*"%s*:%s*{') then
          break -- the next environment
        end
        if lines[j]:find(key(name)) or (j == i and lines[j]:find('"' .. vim.pesc(name) .. '"%s*:', #env_name + 3)) then
          return j
        end
      end
      return i
    end
  end
  return 1
end

return M
