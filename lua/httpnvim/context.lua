-- Everything a .http buffer's variables depend on, gathered in one place
local env = require("httpnvim.env")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")
local secrets = require("httpnvim.secrets")

local M = {}

-- { project, dir, lines, files, env, secrets, vars, sources } for a buffer
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
  local file_vars, file_lines = parser.file_vars(lines)
  ctx.vars, ctx.sources = env.vars(ctx.files, ctx.env, ctx.secrets, file_vars, file_lines)
  return ctx
end

-- Environment names for a project: every env file in it, plus secrets
function M.env_names(proj)
  return env.names(env.all_files(proj), secrets.get(proj))
end

return M
