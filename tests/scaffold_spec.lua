local httpnvim = require("httpnvim")
httpnvim.setup({})
local scaffold = require("httpnvim.scaffold")
local sidebar = require("httpnvim.sidebar")

-- Answers vim.ui.input prompts in order, records them
local function answer(replies)
  local prompts = {}
  local orig = vim.ui.input
  vim.ui.input = function(opts, cb)
    table.insert(prompts, opts.prompt)
    cb(table.remove(replies, 1))
  end
  return prompts, function()
    vim.ui.input = orig
  end
end

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

describe("scaffold", function()
  it("turns method and path into a request line", function()
    eq("GET {{base}}/actuator/health", scaffold.request_line("GET /actuator/health"))
    eq("POST {{base}}/orders", scaffold.request_line("post orders"))
    eq("GET {{base}}/health", scaffold.request_line("/health"))
    eq("GET https://x.dev/a", scaffold.request_line("https://x.dev/a"))
    eq("PUT {{api}}/x", scaffold.request_line("PUT {{api}}/x"))
  end)

  it("inserts after the current request, copying its headers", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "### A",
      "GET {{base}}/a",
      "Authorization: Basic {{username}} {{password}}",
      "",
      "### B",
      "GET {{base}}/b",
    })
    local line = scaffold.insert_request(buf, 2, "New", "GET /new")
    eq({
      "### A",
      "GET {{base}}/a",
      "Authorization: Basic {{username}} {{password}}",
      "",
      "### New",
      "GET {{base}}/new",
      "Authorization: Basic {{username}} {{password}}",
      "",
      "### B",
      "GET {{base}}/b",
    }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    eq(6, line)
  end)

  it("appends at the end, and uses default headers in an empty file", function()
    local buf = vim.api.nvim_create_buf(false, true)
    eq(2, scaffold.insert_request(buf, nil, "First", "GET /one"))
    eq(
      vim.list_extend({ "### First", "GET {{base}}/one" }, scaffold.DEFAULT_HEADERS),
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    )
    local line = scaffold.insert_request(buf, nil, "Second", "DELETE /two")
    eq("DELETE {{base}}/two", vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1])
    eq("", vim.api.nvim_buf_get_lines(buf, line - 3, line - 2, false)[1])
  end)
end)

describe("onboarding", function()
  local repo = TMP .. "/newrepo"
  vim.fn.mkdir(repo .. "/.git/info", "p")
  vim.fn.mkdir(repo .. "/src/deep", "p")

  it("offers to create http/ at the git root when the sidebar opens", function()
    vim.cmd.cd(repo .. "/src/deep")
    vim.cmd("silent! only")
    local confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 1
    end
    local _, restore = answer({ "stag, prod" })
    sidebar.toggle()
    restore()
    vim.fn.confirm = confirm
    eq('{\n  "stag": {},\n  "prod": {}\n}', read(repo .. "/http/http-client.env.json"))
    ok(read(repo .. "/.git/info/exclude"):find("http-client.private.env.json", 1, true))
    ok(sidebar.win())
    ok(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, 1, false)[1]:find("newrepo", 1, true))
  end)

  it("asks for base URLs when adding a service folder", function()
    vim.api.nvim_set_current_win(sidebar.win())
    local prompts, restore = answer({ "integration/", "", "https://integration.stag.example/" })
    sidebar.add()
    restore()
    eq(
      { "New in . (file, or folder/): ", "Base URL for prod (empty to skip): ", "Base URL for stag (empty to skip): " },
      prompts
    )
    eq(
      { stag = { base = "https://integration.stag.example" } },
      vim.json.decode(read(repo .. "/http/integration/http-client.env.json"))
    )
  end)

  it("adds a new request to a file in a folder with n", function()
    vim.api.nvim_set_current_win(sidebar.win())
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find("integration", 1, true) then
        vim.api.nvim_win_set_cursor(sidebar.win(), { i, 0 })
      end
    end
    local prompts, restore = answer({ "actuator", "Health", "GET /actuator/health" })
    sidebar.new_request()
    restore()
    eq("File in integration (requests.http): ", prompts[1])
    local path = repo .. "/http/integration/actuator.http"
    eq(
      vim.list_extend({ "### Health", "GET {{base}}/actuator/health" }, vim.deepcopy(scaffold.DEFAULT_HEADERS)),
      vim.fn.readfile(path)
    )
    eq(path, vim.api.nvim_buf_get_name(0))
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, -1, false), "\n")
    ok(text:find("GET    Health", 1, true), text)
  end)

  it("shows hints in the new request right away", function()
    require("httpnvim.env").select({ root = repo .. "/http" }, "stag")
    local buf = vim.api.nvim_get_current_buf()
    local marks = vim.api.nvim_buf_get_extmarks(buf, require("httpnvim.hints").ns, 0, -1, {})
    ok(#marks > 0, "no hints")
  end)

  it("shows a folder's base URL and sets it with b", function()
    require("httpnvim").refresh()
    vim.api.nvim_set_current_win(sidebar.win())
    local function sidebar_text()
      return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, -1, false), "\n")
    end
    ok(sidebar_text():find("integration  integration.stag.example", 1, true), sidebar_text())
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar.win()), 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find("integration  ", 1, true) then
        vim.api.nvim_win_set_cursor(sidebar.win(), { i, 0 })
      end
    end
    local prompts, restore = answer({ "https://new.stag.example/" })
    sidebar.set_base()
    restore()
    eq("Base URL of integration for stag: ", prompts[1])
    eq(
      { stag = { base = "https://new.stag.example" } },
      vim.json.decode(read(repo .. "/http/integration/http-client.env.json"))
    )
    ok(sidebar_text():find("integration  new.stag.example", 1, true), sidebar_text())
    vim.cmd("wincmd p")
  end)

  it("adds a request below the current one in a buffer", function()
    local _, restore = answer({ "Info", "/actuator/info" })
    httpnvim.new_request()
    restore()
    eq("GET {{base}}/actuator/info", vim.api.nvim_get_current_line())
    sidebar.toggle()
  end)
end)
