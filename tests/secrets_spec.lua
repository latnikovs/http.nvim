local httpnvim = require("httpnvim")
local secrets = require("httpnvim.secrets")
local env = require("httpnvim.env")
local pane = require("httpnvim.pane")

local calls = 0
httpnvim.setup({
  secrets = function(project, cb)
    calls = calls + 1
    eq("vault", project.name)
    cb({ ["stag/a"] = { username = "user-a", password = "pw-a" }, ["stag/c"] = { username = "user-c" } })
  end,
})

local root = TMP .. "/vault/http"
write(root .. "/http-client.env.json", vim.json.encode({ stag = { base = "http://127.0.0.1:9" }, ["stag/a"] = {} }))
write(root .. "/t.http", "GET {{base}}/x\nAuthorization: Basic {{username}} {{password}}")
local proj = { root = root, name = "vault" }

describe("secrets", function()
  vim.cmd.edit(root .. "/t.http")
  local buf = vim.api.nvim_get_current_buf()

  it("shows variables as locked until secrets are loaded", function()
    env.select(proj, "stag/a")
    local hints = require("httpnvim.hints")
    hints.render(buf)
    local mark = vim.api.nvim_buf_get_extmarks(buf, hints.ns, { 1, 0 }, { 1, -1 }, { details = true })[1]
    local text = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, mark[4].virt_text))
    ok(text:find("username (secrets locked)", 1, true), text)
  end)

  it("loads them once, on the first send that needs them", function()
    httpnvim.send_at(buf, 1)
    vim.wait(3000, function()
      return pane.win() and not vim.wo[pane.win()].winbar:find("Sending")
    end)
    eq(1, calls)
    httpnvim.view("request")
    local text = table.concat(vim.api.nvim_buf_get_lines(pane.buf(), 0, -1, false), "\n")
    ok(text:find("GET http://127.0.0.1:9/x", 1, true), text)
    httpnvim.send_at(buf, 1)
    eq(1, calls)
  end)

  it("adds secret-only environments to the list", function()
    eq({ "stag", "stag/a", "stag/c" }, require("httpnvim.context").env_names(proj))
  end)

  it("refuses to ask for a secret that is missing", function()
    env.select(proj, "stag/c")
    local asked = false
    local orig = vim.ui.input
    vim.ui.input = function()
      asked = true
    end
    NOTES = {}
    httpnvim.send_at(buf, 1)
    vim.ui.input = orig
    eq(false, asked)
    ok(NOTES[#NOTES]:find("password is not in the secrets for stag/c", 1, true), NOTES[#NOTES])
  end)

  it("forgets them on reset", function()
    secrets.reset()
    eq(nil, secrets.get(proj))
    httpnvim.view("body")
  end)
end)
