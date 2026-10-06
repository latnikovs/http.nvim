-- Everything a .http buffer's variables depend on, gathered in one place
local env = require("httpnvim.env")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")
local secrets = require("httpnvim.secrets")

local M = {}

-- The service (top-level folder) a folder of the project is in, or nil
function M.service(proj, dir)
  local chain = project.chain(proj, dir)
  if chain[1] ~= proj.root or not chain[2] then
    return nil
  end
  return vim.fs.basename(chain[2])
end

-- { project, dir, service, lines, files, env, secrets, vars, sources } for a buffer
function M.get(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local path = vim.api.nvim_buf_get_name(buf)
  local proj = project.for_file(path ~= "" and path or (vim.fn.getcwd() .. "/x"))
  local dir = path ~= "" and vim.fs.dirname(vim.fs.normalize(path)) or vim.fn.getcwd()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ctx = { buf = buf, project = proj, dir = dir, lines = lines }
  ctx.files = env.files(proj, dir)
  ctx.secrets = secrets.get(proj)
  ctx.env = env.selected(proj)
  ctx.service = M.service(proj, dir)
  local split = secrets.split(proj, ctx.secrets)
  local service = ctx.service and { name = ctx.service, secrets = split.services[ctx.service] }
  local file_vars, file_lines = parser.file_vars(lines)
  ctx.vars, ctx.sources = env.vars(ctx.files, ctx.env, split.project, file_vars, file_lines, service)
  return ctx
end

-- Environment names for a project: every env file in it, plus secrets (the
-- project's and every service's)
function M.env_names(proj)
  local split = secrets.split(proj, secrets.get(proj))
  local names = vim.deepcopy(split.project)
  for _, by_env in pairs(split.services) do
    for name, vars in pairs(by_env) do
      names[name] = vars
    end
  end
  return env.names(env.all_files(proj), names)
end

return M
