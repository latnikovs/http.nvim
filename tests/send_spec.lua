-- Sends real requests to a local echo server (skipped without python3)
if vim.fn.executable("python3") ~= 1 then
  return
end

local server = [[
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def handle_one(self):
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n).decode() if n else ''
        if self.path == '/slow':
            time.sleep(5)
        out = json.dumps({'method': self.command, 'path': self.path, 'auth': self.headers.get('Authorization'), 'body': body}).encode()
        self.send_response(404 if self.path == '/missing' else 200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(out)
    do_GET = do_POST = do_PUT = do_DELETE = handle_one
    def log_message(self, *a): pass
s = HTTPServer(('127.0.0.1', 0), H)
print(s.server_port, flush=True)
s.serve_forever()
]]

local port
local proc = vim.system({ "python3", "-c", server }, {
  stdout = function(_, data)
    port = port or (data and data:match("(%d+)"))
  end,
})
vim.wait(5000, function()
  return port ~= nil
end)

local httpnvim = require("httpnvim")
httpnvim.setup({})
local pane = require("httpnvim.pane")

local root = TMP .. "/send/http"
write(root .. "/http-client.env.json", vim.json.encode({ dev = { base = "http://127.0.0.1:" .. port } }))
write(root .. "/http-client.private.env.json", vim.json.encode({ dev = { user = "u", password = "p" } }))
write(
  root .. "/api/t.http",
  table.concat({
    "### Get",
    "GET {{base}}/items/{{id}}",
    "Authorization: Basic {{user}} {{password}}",
    "",
    "### Post",
    "POST {{base}}/echo",
    "Content-Type: application/json",
    "",
    '{"n": 1}',
    "",
    "### Missing",
    "DELETE {{base}}/missing",
    "",
    "### Slow",
    "GET {{base}}/slow",
  }, "\n")
)
write(root .. "/api/http-client.env.json", vim.json.encode({ dev = { id = "42" } }))

vim.cmd.edit(root .. "/api/t.http")
local buf = vim.api.nvim_get_current_buf()

local function pane_text()
  local b = pane.buf()
  return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n"), vim.wo[pane.win()].winbar
end

local function send(lnum)
  httpnvim.send_at(buf, lnum)
  vim.wait(5000, function()
    local _, bar = pane_text()
    return not bar:find("Sending")
  end, 20)
  return pane_text()
end

describe("send", function()
  it("selects the only environment and sends with variables", function()
    local text, bar = send(2)
    local body = vim.json.decode(text)
    eq("/items/42", body.path)
    eq("Basic " .. vim.base64.encode("u:p"), body.auth)
    ok(bar:find(" 200 "), bar)
    ok(bar:find("dev"), bar)
  end)

  it("opens the response below the request", function()
    local pos = vim.fn.win_screenpos(pane.win())
    local req = vim.fn.win_screenpos(vim.fn.bufwinid(buf))
    ok(pos[1] > req[1], "pane below")
  end)

  it("posts the body", function()
    local text = send(6)
    eq('{"n": 1}', vim.json.decode(text).body)
  end)

  it("shows errors in red", function()
    local _, bar = send(12)
    ok(bar:find("DiagnosticError#%s404"), bar)
  end)

  it("shows the request as sent, masked", function()
    send(2)
    httpnvim.view("request")
    local text = pane_text()
    ok(text:find("Authorization: Basic ••••", 1, true), text)
    httpnvim.view("body")
  end)

  it("cancels", function()
    httpnvim.send_at(buf, 15)
    vim.wait(300)
    httpnvim.cancel()
    vim.wait(3000, function()
      return pane_text():find("Cancelled") ~= nil
    end)
    ok(pane_text():find("Cancelled"))
  end)

  it("asks for an undefined variable, saves it for the environment, and sends", function()
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "GET {{base}}/items/{{other}}" })
    local orig = vim.ui.input
    vim.ui.input = function(opts, cb)
      eq("other for dev: ", opts.prompt)
      cb("99")
    end
    local text = send(2)
    vim.ui.input = orig
    eq("/items/99", vim.json.decode(text).path)
    local saved = vim.json.decode(table.concat(vim.fn.readfile(root .. "/api/http-client.env.json"), "\n"))
    eq({ dev = { id = "42", other = "99" } }, saved)
  end)

  it("shows hints with values and sources", function()
    local hints = require("httpnvim.hints")
    hints.render(buf)
    local marks = vim.api.nvim_buf_get_extmarks(buf, hints.ns, 0, -1, { details = true })
    local text = {}
    for _, m in ipairs(marks) do
      local line = {}
      for _, chunk in ipairs(m[4].virt_text) do
        table.insert(line, chunk[1])
      end
      text[m[2] + 1] = table.concat(line)
    end
    ok(text[2]:find("other = 99  api · dev", 1, true), text[2])
    ok(text[3]:find("password = ••••", 1, true), text[3])
  end)

  it("jumps to a variable's definition with goto_var", function()
    vim.api.nvim_set_current_win(vim.fn.bufwinid(buf))
    vim.api.nvim_win_set_cursor(0, { 2, 25 }) -- on {{other}}
    httpnvim.goto_var()
    eq(root .. "/api/http-client.env.json", vim.api.nvim_buf_get_name(0))
    ok(vim.api.nvim_get_current_line():find('"other"', 1, true), vim.api.nvim_get_current_line())
    vim.cmd("buffer " .. buf)
  end)
end)

proc:kill("sigterm")
