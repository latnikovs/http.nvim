local httpnvim = require("httpnvim")
httpnvim.setup({})
local env = require("httpnvim.env")

describe("service variables", function()
  local root = TMP .. "/svcbase/http"
  write(root .. "/http-client.env.json", vim.json.encode({ stag = {}, ["stag/a"] = { id = "1" } }))
  write(root .. "/integration/actuator/health.http", "GET {{base}}/actuator/health")
  local proj = { root = root, name = "svcbase" }

  it("saves an undefined base in the service folder at the top env level", function()
    env.select(proj, "stag/a")
    vim.cmd.edit(root .. "/integration/actuator/health.http")
    local prompts = {}
    local orig = vim.ui.input
    vim.ui.input = function(opts, cb)
      table.insert(prompts, opts.prompt)
      cb("http://127.0.0.1:9/")
    end
    httpnvim.send_at(vim.api.nvim_get_current_buf(), 1)
    vim.ui.input = orig
    eq({ "base of integration for stag: " }, prompts)
    eq(
      { stag = { base = "http://127.0.0.1:9" } },
      vim.json.decode(table.concat(vim.fn.readfile(root .. "/integration/http-client.env.json"), "\n"))
    )
    eq(
      { stag = {}, ["stag/a"] = { id = "1" } },
      vim.json.decode(table.concat(vim.fn.readfile(root .. "/http-client.env.json"), "\n"))
    )
    httpnvim.cancel()
  end)

  it("keeps other variables at the client level, in the nearest env file", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "GET {{base}}/x/{{warehouseId}}" })
    local orig = vim.ui.input
    vim.ui.input = function(opts, cb)
      eq("warehouseId for stag/a: ", opts.prompt)
      cb("17")
    end
    httpnvim.send_at(vim.api.nvim_get_current_buf(), 1)
    vim.ui.input = orig
    local service_env =
      vim.json.decode(table.concat(vim.fn.readfile(root .. "/integration/http-client.env.json"), "\n"))
    eq({ stag = { base = "http://127.0.0.1:9" }, ["stag/a"] = { warehouseId = "17" } }, service_env)
    httpnvim.cancel()
  end)
end)
