local httpnvim = require("httpnvim")
httpnvim.setup({})
local sidebar = require("httpnvim.sidebar")
local env = require("httpnvim.env")

local repo = TMP .. "/side"
local root = repo .. "/http"
write(
  root .. "/http-client.env.json",
  vim.json.encode({
    stag = { base = "http://127.0.0.1:9" },
    ["stag/a"] = { id = "1" },
    ["stag/b"] = { id = "2" },
  })
)
write(
  root .. "/api/inventory/status.http",
  "### Status\nGET {{base}}/inventory/{{id}}/status\n\n### Other\nPOST {{base}}/x"
)
write(root .. "/data-api/stock.http", "GET {{base}}/stock")

local function lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, -1, false)
end

local function goto_line(pattern)
  for i, line in ipairs(lines()) do
    if line:find(pattern, 1, true) then
      vim.api.nvim_win_set_cursor(sidebar.win(), { i, 0 })
      return i
    end
  end
  error("no line with " .. pattern .. " in\n" .. table.concat(lines(), "\n"))
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end

describe("sidebar", function()
  vim.cmd.cd(repo)

  it("opens on the left with the project and environments", function()
    vim.cmd("only")
    sidebar.toggle()
    ok(sidebar.win())
    eq(1, vim.fn.win_screenpos(sidebar.win())[2])
    local text = table.concat(lines(), "\n")
    ok(text:find(" side  no environment", 1, true), text)
    ok(text:find("  stag\n    a\n    b", 1, true) or text:find("stag", 1, true), text)
  end)

  it("selects an environment with <CR>", function()
    goto_line("    b")
    press("<CR>")
    eq("stag/b", env.selected({ root = root }))
    ok(lines()[1]:find("stag/b", 1, true))
    ok(table.concat(lines(), "\n"):find("● b", 1, true))
  end)

  it("unfolds folders and files down to requests", function()
    goto_line("▸ api")
    press("<CR>")
    goto_line("▸ inventory")
    press("<CR>")
    goto_line("▸ status.http")
    press("<CR>")
    goto_line("GET    Status")
    goto_line("POST   Other")
  end)

  it("opens a request in the editor next to it", function()
    goto_line("GET    Status")
    press("<CR>")
    eq(root .. "/api/inventory/status.http", vim.api.nvim_buf_get_name(0))
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    ok(vim.api.nvim_get_current_win() ~= sidebar.win())
  end)

  it("adds files and folders", function()
    vim.api.nvim_set_current_win(sidebar.win())
    goto_line("▾ inventory")
    local orig = vim.ui.input
    vim.ui.input = function(_, cb)
      cb("levels")
    end
    sidebar.add()
    vim.ui.input = orig
    ok(vim.uv.fs_stat(root .. "/api/inventory/levels.http"))
    vim.api.nvim_set_current_win(sidebar.win())
    goto_line("levels.http")
  end)

  it("renames and deletes", function()
    goto_line("levels.http")
    local orig = vim.ui.input
    vim.ui.input = function(_, cb)
      cb("stock-levels.http")
    end
    sidebar.rename()
    vim.ui.input = orig
    ok(vim.uv.fs_stat(root .. "/api/inventory/stock-levels.http"))
    ok(not vim.uv.fs_stat(root .. "/api/inventory/levels.http"))
    goto_line("stock-levels.http")
    local confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 1
    end
    sidebar.delete()
    vim.fn.confirm = confirm
    ok(not vim.uv.fs_stat(root .. "/api/inventory/stock-levels.http"))
  end)

  it("closes with the toggle", function()
    sidebar.toggle()
    eq(nil, sidebar.win())
  end)
end)
