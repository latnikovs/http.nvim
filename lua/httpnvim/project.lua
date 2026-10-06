-- A project is a folder of .http files and env files, normally a folder
-- called http/ in a repository (wms/http, named "wms"). Without one, the
-- nearest folder with an http-client.env.json counts.
local M = {}

M.ENV_FILE = "http-client.env.json"
M.PRIVATE_ENV_FILE = "http-client.private.env.json"

local function is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

local function new(root)
  local name = vim.fs.basename(root)
  if name == "http" then
    name = vim.fs.basename(vim.fs.dirname(root))
  end
  return { root = root, name = name }
end

-- The project around a folder: the nearest folder named http above it (or it
-- itself), else the nearest one with an env file
function M.find(dir)
  dir = vim.fs.normalize(dir)
  for d in vim.fs.parents(dir .. "/x") do
    if vim.fs.basename(d) == "http" then
      return new(d)
    end
  end
  for d in vim.fs.parents(dir .. "/x") do
    if is_file(d .. "/" .. M.ENV_FILE) or is_file(d .. "/" .. M.PRIVATE_ENV_FILE) then
      return new(d)
    end
  end
  return nil
end

-- The project for the current directory: its http/ folder if it has one
-- (a repository root), else the one around it
function M.from_cwd()
  local cwd = vim.fn.getcwd()
  if is_dir(cwd .. "/http") then
    return new(vim.fs.normalize(cwd .. "/http"))
  end
  return M.find(cwd)
end

-- The project of a file, or a stand-in rooted at its folder
function M.for_file(path)
  local dir = vim.fs.dirname(vim.fs.normalize(path))
  return M.find(dir) or new(dir)
end

-- Folders from the root down to dir (just dir if it is outside the root)
function M.chain(project, dir)
  dir = vim.fs.normalize(dir)
  local dirs = {}
  for d in vim.fs.parents(dir .. "/x") do
    table.insert(dirs, 1, d)
    if d == project.root then
      return dirs
    end
  end
  return { dir }
end

-- Path relative to the project root, "." for the root itself
function M.relative(project, path)
  if path == project.root then
    return "."
  end
  local prefix = project.root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return vim.fn.fnamemodify(path, ":~")
end

return M
