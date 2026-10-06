-- The sidebar, in the spirit of vim-dadbod-ui: the project and its selected
-- environment on top, then the environments and the request tree (folders,
-- .http files, the requests in them). Requests open in the window next to
-- it and their responses go below that.
local config = require("httpnvim.config")
local context = require("httpnvim.context")
local env = require("httpnvim.env")
local envfile = require("httpnvim.envfile")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")
local resolve = require("httpnvim.resolve")
local scaffold = require("httpnvim.scaffold")
local secrets = require("httpnvim.secrets")

local M = {}

local ns = vim.api.nvim_create_namespace("httpnvim.sidebar")
local state = { buf = nil, project = nil, expanded = {}, nodes = {}, help = false }

local HELP = {
  "<CR>  open · select · fold",
  "s     send the request",
  "n     new request",
  "b     base URL of a folder",
  "o     open in the editor",
  "e     choose environment",
  "a     add file or folder/",
  "r     rename   d  delete",
  "R     refresh  q  close",
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "http.nvim" })
end

function M.win()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == state.buf then
      return win
    end
  end
end

-- Tree building --------------------------------------------------------------

local function is_request_file(name)
  return name:match("%.http$") or name:match("%.rest$")
end

-- Folders first, then .http files, both by name
local function entries(dir)
  local dirs, files = {}, {}
  for name, kind in vim.fs.dir(dir) do
    if not name:match("^%.") then
      if kind == "directory" then
        table.insert(dirs, name)
      elseif is_request_file(name) then
        table.insert(files, name)
      end
    end
  end
  table.sort(dirs)
  table.sort(files)
  return dirs, files
end

local function file_requests(path)
  local buf = vim.fn.bufnr(path)
  local lines = buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    or vim.fn.readfile(path)
  return parser.requests(lines)
end

-- A folder's base URL for an environment, from the env files down to it
local function base_of(dir, env_name)
  local vars = env.vars(env.files(state.project, dir), env_name)
  return vars.base and resolve.value("base", vars) or nil
end

-- Environment names as a tree: { name, path, children, is_env }
local function env_tree(names)
  local root = { children = {}, order = {} }
  local is_env = {}
  for _, name in ipairs(names) do
    is_env[name] = true
    local node = root
    local path = {}
    for _, part in ipairs(vim.split(name, "/", { plain = true })) do
      table.insert(path, part)
      if not node.children[part] then
        node.children[part] = { name = part, path = table.concat(path, "/"), children = {}, order = {} }
        table.insert(node.order, part)
      end
      node = node.children[part]
    end
  end
  return root, is_env
end

-- Rendering ------------------------------------------------------------------

-- Lines and their nodes; each line is a list of { text, hl } chunks
local function build()
  local proj = state.project
  local lines, nodes = {}, {}
  local function add(chunks, node)
    table.insert(lines, chunks)
    nodes[#lines] = node
  end
  local selected = env.selected(proj)

  add({
    { " " .. proj.name, "HttpnvimSidebarTitle" },
    { "  " },
    {
      selected or "no environment",
      selected and "HttpnvimSidebarEnv" or "Comment",
    },
  }, { kind = "header" })
  add({ { "" } }, { kind = "blank" })

  -- Environments
  local open = state.expanded["section:env"] ~= false
  add(
    { { (open and "▾ " or "▸ ") .. "Environments", "HttpnvimSidebarSection" } },
    { kind = "section", key = "section:env" }
  )
  if open then
    if not secrets.is_loaded(proj) then
      add({ { "    unlock secrets", "DiagnosticWarn" } }, { kind = "unlock", key = "unlock" })
    end
    local tree, is_env = env_tree(context.env_names(proj))
    local function walk(node, depth)
      for _, part in ipairs(node.order) do
        local child = node.children[part]
        local indent = ("  "):rep(depth + 1)
        if is_env[child.path] then
          local current = child.path == selected
          add({
            { indent .. (current and "● " or "  "), "HttpnvimSidebarEnv" },
            { child.name, current and "HttpnvimSidebarEnv" or "Normal" },
          }, { kind = "env", env = child.path, key = "env:" .. child.path })
        else
          add({ { indent .. "  " .. child.name, "Directory" } }, { kind = "envgroup", key = "envgroup:" .. child.path })
        end
        walk(child, depth + 1)
      end
    end
    walk(tree, 0)
  end
  add({ { "" } }, { kind = "blank" })

  -- Requests
  open = state.expanded["section:req"] ~= false
  add(
    { { (open and "▾ " or "▸ ") .. "Requests", "HttpnvimSidebarSection" } },
    { kind = "section", key = "section:req", dir = proj.root }
  )
  if open then
    local function walk(dir, depth)
      local indent = ("  "):rep(depth + 1)
      local dirs, files = entries(dir)
      for _, name in ipairs(dirs) do
        local path = dir .. "/" .. name
        local key = "dir:" .. path
        local dopen = state.expanded[key] == true
        local chunks = { { indent .. (dopen and "▾ " or "▸ ") .. name, "Directory" } }
        -- Folders with their own env file show their base URL
        if selected and vim.uv.fs_stat(path .. "/" .. project.ENV_FILE) then
          local base = base_of(path, selected)
          if base then
            table.insert(chunks, { "  " .. base:gsub("^%a+://", ""), "Comment" })
          end
        end
        add(chunks, { kind = "dir", path = path, key = key })
        if dopen then
          walk(path, depth + 1)
        end
      end
      for _, name in ipairs(files) do
        local path = dir .. "/" .. name
        local key = "file:" .. path
        local fopen = state.expanded[key] == true
        add({ { indent .. (fopen and "▾ " or "▸ ") .. name } }, { kind = "file", path = path, key = key })
        if fopen then
          for _, req in ipairs(file_requests(path)) do
            local method, rest = req.name:match("^(%u+) (.*)$")
            local label = (method and parser.METHODS[method]) and rest or req.name
            add({
              { indent .. "    " },
              { ("%-6s "):format(req.method), "HttpnvimSidebarMethod" },
              { label },
            }, { kind = "request", path = path, lnum = req.lnum, key = "req:" .. path .. ":" .. req.lnum })
          end
        end
      end
    end
    walk(proj.root, 0)
  end

  add({ { "" } }, { kind = "blank" })
  if state.help then
    for _, line in ipairs(HELP) do
      add({ { " " .. line, "Comment" } }, { kind = "help" })
    end
  else
    add({ { " ? help", "Comment" } }, { kind = "help" })
  end
  return lines, nodes
end

local function current_node()
  local win = M.win()
  if not win then
    return nil
  end
  return state.nodes[vim.api.nvim_win_get_cursor(win)[1]]
end

function M.render()
  local win = M.win()
  if not win or not state.project then
    return
  end
  local keep = current_node()
  local lines, nodes = build()
  local text = {}
  for i, chunks in ipairs(lines) do
    text[i] = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, chunks))
  end
  local buf = state.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, chunks in ipairs(lines) do
    local col = 0
    for _, c in ipairs(chunks) do
      if c[2] and #c[1] > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = col + #c[1], hl_group = c[2] })
      end
      col = col + #c[1]
    end
  end
  state.nodes = nodes
  -- Back to the node the cursor was on
  if keep and keep.key then
    for i, node in ipairs(nodes) do
      if node.key == keep.key then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        return
      end
    end
  end
  local row = math.min(vim.api.nvim_win_get_cursor(win)[1], #lines)
  vim.api.nvim_win_set_cursor(win, { row, 0 })
end

function M.refresh()
  if M.win() then
    M.render()
  end
end

-- Actions --------------------------------------------------------------------

-- The window requests open in: the last other normal window, or a new one
-- to the right of the sidebar
local function editor_win()
  local sidebar = M.win()
  local pane = require("httpnvim.pane").win()
  local function usable(win)
    return win ~= sidebar and win ~= pane and vim.api.nvim_win_get_config(win).relative == ""
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev ~= 0 and usable(prev) then
    return prev
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable(win) then
      return win
    end
  end
  local win = vim.api.nvim_open_win(0, false, { split = "right", win = sidebar })
  vim.api.nvim_win_set_width(sidebar, config.options.sidebar.width)
  return win
end

local function open_file(path, lnum)
  local win = editor_win()
  vim.api.nvim_set_current_win(win)
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= path then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if lnum then
    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
    vim.cmd("normal! zz")
  end
  return win
end

local function toggle(node)
  state.expanded[node.key] = not (
    state.expanded[node.key] == true or (node.kind == "section" and state.expanded[node.key] ~= false)
  )
  M.render()
end

function M.activate()
  local node = current_node()
  if not node then
    return
  end
  if node.kind == "section" or node.kind == "dir" or node.kind == "file" then
    toggle(node)
  elseif node.kind == "env" then
    require("httpnvim").select_env(node.env, state.project)
  elseif node.kind == "unlock" then
    secrets.load(state.project, function()
      M.render()
    end)
  elseif node.kind == "request" then
    open_file(node.path, node.lnum)
  elseif node.kind == "help" then
    state.help = not state.help
    M.render()
  end
end

function M.open_node()
  local node = current_node()
  if node and (node.kind == "file" or node.kind == "request") then
    open_file(node.path, node.lnum)
  elseif node then
    M.activate()
  end
end

function M.send()
  local node = current_node()
  if not node or node.kind ~= "request" then
    notify("Put the cursor on a request", vim.log.levels.WARN)
    return
  end
  local sidebar = M.win()
  local win = open_file(node.path, node.lnum)
  require("httpnvim").send_at(vim.api.nvim_win_get_buf(win), node.lnum, win)
  if sidebar and vim.api.nvim_win_is_valid(sidebar) then
    vim.api.nvim_set_current_win(sidebar)
  end
end

-- The folder new files go into for a node
local function folder_of(node)
  if node and node.kind == "dir" then
    return node.path
  elseif node and (node.kind == "file" or node.kind == "request") then
    return vim.fs.dirname(node.path)
  end
  return state.project.root
end

function M.add()
  local node = current_node()
  local dir = folder_of(node)
  local where = project.relative(state.project, dir)
  vim.ui.input({ prompt = ("New in %s (file, or folder/): "):format(where) }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    input = vim.trim(input)
    local path = dir .. "/" .. input:gsub("/$", "")
    local is_service = false
    if input:match("/$") then
      vim.fn.mkdir(path, "p")
      state.expanded["dir:" .. path] = true
      -- A top-level folder is a service: ask for its base URLs
      is_service = vim.fs.dirname(path) == state.project.root
    else
      if not is_request_file(path) then
        path = path .. ".http"
      end
      if vim.uv.fs_stat(path) then
        notify(vim.fs.basename(path) .. " exists already", vim.log.levels.WARN)
        return
      end
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({ "### " .. vim.fn.fnamemodify(path, ":t:r"), "GET {{base}}/" }, path)
      open_file(path, 2)
    end
    -- Show where it went
    local d = vim.fs.dirname(path)
    while d ~= state.project.root and #d > #state.project.root do
      state.expanded["dir:" .. d] = true
      d = vim.fs.dirname(d)
    end
    M.render()
    if is_service then
      scaffold.ask_bases(state.project, path, M.render)
    end
  end)
end

-- Sets the base URL of the folder under the cursor (a file's folder, or the
-- root) for the selected environment's top level ("stag" for "stag/toplog"),
-- in that folder's env file
function M.set_base()
  local node = current_node()
  local dir = folder_of(node)
  local selected = env.selected(state.project)
  if not selected then
    notify("Select an environment first", vim.log.levels.WARN)
    return
  end
  local level = selected:match("^[^/]+")
  local where = project.relative(state.project, dir)
  vim.ui.input({
    prompt = ("Base URL of %s for %s: "):format(where, level),
    default = base_of(dir, level),
  }, function(url)
    if not url or vim.trim(url) == "" then
      return
    end
    url = vim.trim(url):gsub("/+$", "")
    local ok, err = envfile.write(dir .. "/" .. project.ENV_FILE, level, "base", url)
    if not ok then
      notify("Can't save the base URL: " .. err, vim.log.levels.ERROR)
      return
    end
    notify(("base = %s for %s in %s"):format(url, level, where))
    require("httpnvim").refresh()
  end)
end

-- A new request: added to the file (after the request) under the cursor, or
-- to a file asked for in the folder under the cursor
function M.new_request()
  local node = current_node()
  local function add(path, lnum)
    scaffold.ask_request(function(name, input)
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      local win = open_file(path)
      local buf = vim.api.nvim_win_get_buf(win)
      local line = scaffold.insert_request(buf, lnum, name, input)
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      require("httpnvim.hints").render(buf)
      state.expanded["file:" .. path] = true
      local d = vim.fs.dirname(path)
      while #d > #state.project.root do
        state.expanded["dir:" .. d] = true
        d = vim.fs.dirname(d)
      end
      M.render()
    end)
  end
  if node and (node.kind == "file" or node.kind == "request") then
    add(node.path, node.lnum)
    return
  end
  local dir = folder_of(node)
  vim.ui.input({
    prompt = ("File in %s (requests.http): "):format(project.relative(state.project, dir)),
  }, function(input)
    if input == nil then
      return
    end
    local path = dir .. "/" .. (vim.trim(input) ~= "" and vim.trim(input) or "requests.http")
    if not is_request_file(path) then
      path = path .. ".http"
    end
    add(path, nil)
  end)
end

function M.rename()
  local node = current_node()
  if not node or (node.kind ~= "dir" and node.kind ~= "file") then
    notify("Put the cursor on a file or folder", vim.log.levels.WARN)
    return
  end
  local old = node.path
  vim.ui.input({ prompt = "Rename to: ", default = vim.fs.basename(old) }, function(input)
    if not input or vim.trim(input) == "" or vim.trim(input) == vim.fs.basename(old) then
      return
    end
    local new = vim.fs.dirname(old) .. "/" .. vim.trim(input)
    if vim.uv.fs_stat(new) then
      notify(vim.trim(input) .. " exists already", vim.log.levels.WARN)
      return
    end
    local ok, err = vim.uv.fs_rename(old, new)
    if not ok then
      notify("Rename failed: " .. err, vim.log.levels.ERROR)
      return
    end
    -- Loaded buffers follow the file
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name == old or name:sub(1, #old + 1) == old .. "/" then
        vim.api.nvim_buf_set_name(buf, new .. name:sub(#old + 1))
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! write!")
        end)
      end
    end
    M.render()
  end)
end

function M.delete()
  local node = current_node()
  if not node or (node.kind ~= "dir" and node.kind ~= "file") then
    notify("Put the cursor on a file or folder", vim.log.levels.WARN)
    return
  end
  local what = project.relative(state.project, node.path)
  if
    vim.fn.confirm("Delete " .. what .. (node.kind == "dir" and " and everything in it" or "") .. "?", "&Yes\n&No", 2)
    ~= 1
  then
    return
  end
  if vim.fn.delete(node.path, node.kind == "dir" and "rf" or "") ~= 0 then
    notify("Couldn't delete " .. what, vim.log.levels.ERROR)
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name == node.path or name:sub(1, #node.path + 1) == node.path .. "/" then
      -- Keep the windows that show it, with an empty buffer instead
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.render()
end

-- Window ---------------------------------------------------------------------

local function make_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "httpnvim://sidebar")
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "httpnvim"
  local map = function(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true })
  end
  map("<CR>", M.activate, "Open, Select or Fold")
  map("o", M.open_node, "Open in Editor")
  map("s", M.send, "Send Request")
  map("e", function()
    require("httpnvim").select_env(nil, state.project)
  end, "Choose Environment")
  map("a", M.add, "Add File or Folder")
  map("n", M.new_request, "New Request")
  map("b", M.set_base, "Set Base URL")
  map("r", M.rename, "Rename")
  map("d", M.delete, "Delete")
  map("R", M.render, "Refresh")
  map("q", M.close, "Close")
  map("?", function()
    state.help = not state.help
    M.render()
  end, "Help")
  state.buf = buf
  return buf
end

function M.open(proj)
  proj = proj or require("httpnvim").project()
  if not proj then
    scaffold.offer_project(M.open)
    return
  end
  if not state.project or state.project.root ~= proj.root then
    state.expanded = {}
  end
  state.project = proj
  local win = M.win()
  local opened = not win
  if not win then
    win = vim.api.nvim_open_win(make_buf(), true, { split = "left", win = -1, width = config.options.sidebar.width })
    for option, value in pairs({
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      wrap = false,
      cursorline = true,
      winfixwidth = true,
      spell = false,
      list = false,
    }) do
      vim.wo[win][option] = value
    end
  end
  vim.api.nvim_set_current_win(win)
  M.render()
  if opened and config.options.sidebar.unlock and not secrets.is_loaded(proj) then
    -- Like dadbod-ui with its connections: unlock right away, then pick the
    -- environment, so the first send needs no more questions
    vim.schedule(function()
      vim.cmd.redraw()
      secrets.load(proj, function(loaded)
        if loaded and M.win() and state.project.root == proj.root then
          require("httpnvim").select_env(nil, proj)
        end
      end)
    end)
  end
end

function M.close()
  require("httpnvim.pane").close()
  local win = M.win()
  if not win then
    return
  end
  local others = vim.tbl_filter(function(w)
    return w ~= win and vim.api.nvim_win_get_config(w).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
  if #others == 0 then
    -- The last window: leave an empty buffer rather than fail
    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
  else
    vim.api.nvim_win_close(win, false)
  end
end

function M.toggle()
  if M.win() then
    M.close()
  else
    M.open()
  end
end

function M.setup()
  for group, link in pairs({
    HttpnvimSidebarTitle = "Title",
    HttpnvimSidebarSection = "Statement",
    HttpnvimSidebarEnv = "DiagnosticOk",
    HttpnvimSidebarMethod = "Type",
  }) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
  local group = vim.api.nvim_create_augroup("httpnvim.sidebar", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.http", "*.rest", project.ENV_FILE, project.PRIVATE_ENV_FILE },
    callback = M.refresh,
  })
end

return M
