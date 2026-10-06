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

  it("keeps other variables for the session only, per environment", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "GET {{base}}/x/{{warehouseId}}" })
    local orig = vim.ui.input
    vim.ui.input = function(opts, cb)
      eq("warehouseId for stag/a (this session): ", opts.prompt)
      cb("17")
    end
    httpnvim.send_at(vim.api.nvim_get_current_buf(), 1)
    vim.ui.input = orig
    local service_env =
      vim.json.decode(table.concat(vim.fn.readfile(root .. "/integration/http-client.env.json"), "\n"))
    eq({ stag = { base = "http://127.0.0.1:9" } }, service_env)
    eq("17", require("httpnvim.context").get(0).vars.warehouseId)
    env.select(proj, "stag")
    eq(nil, require("httpnvim.context").get(0).vars.warehouseId)
    env.select(proj, "stag/a")
    httpnvim.cancel()
  end)
end)

describe("service secrets", function()
  local root = TMP .. "/svcsec/http"
  write(root .. "/http-client.env.json", vim.json.encode({ stag = {} }))
  write(root .. "/integration/a.http", "GET {{base}}/a\nAuthorization: Basic {{username}} {{password}}")
  write(root .. "/print/b.http", "GET {{base}}/b\nAuthorization: Basic {{username}} {{password}}")
  local proj = require("httpnvim.project").find(root)
  local secrets = require("httpnvim.secrets")
  local context = require("httpnvim.context")
  local raw = {
    ["stag/toplog"] = { username = "shared", password = "shared-pw", extra = "x" },
    ["integration/stag/toplog"] = { username = "int-user", password = "int-pw" },
    ["integration/prod/toplog"] = { username = "int-prod" },
  }

  it("splits paths that start with a service folder", function()
    local split = secrets.split(proj, raw)
    eq({ ["stag/toplog"] = raw["stag/toplog"] }, split.project)
    eq(
      { ["stag/toplog"] = raw["integration/stag/toplog"], ["prod/toplog"] = raw["integration/prod/toplog"] },
      split.services.integration
    )
  end)

  it("uses a service's own secrets over the project's, only in that service", function()
    httpnvim.setup({
      secrets = function(_, cb)
        cb(raw)
      end,
    })
    secrets.load(proj, function() end)
    vim.wait(100)
    require("httpnvim.env").select(proj, "stag/toplog")

    vim.cmd.edit(root .. "/integration/a.http")
    local ctx = context.get(0)
    eq("integration", ctx.service)
    eq("int-user", ctx.vars.username)
    eq("x", ctx.vars.extra)
    eq({ kind = "secret", env = "stag/toplog", service = "integration" }, ctx.sources.username)
    eq("secrets · integration · stag/toplog", require("httpnvim.hints").describe(ctx, ctx.sources.username))

    vim.cmd.edit(root .. "/print/b.http")
    ctx = context.get(0)
    eq("print", ctx.service)
    eq("shared", ctx.vars.username)
    eq("secrets · stag/toplog", require("httpnvim.hints").describe(ctx, ctx.sources.username))
  end)

  it("lists environments from service secrets without the service", function()
    eq({ "prod/toplog", "stag", "stag/toplog" }, context.env_names(proj))
    secrets.reset()
    httpnvim.setup({})
  end)
end)

describe("service secrets", function()
  local root = TMP .. "/svcsec/http"
  write(root .. "/http-client.env.json", vim.json.encode({ stag = {} }))
  write(root .. "/integration/a.http", "GET {{base}}/a\nAuthorization: Basic {{username}} {{password}}")
  write(root .. "/print/b.http", "GET {{base}}/b\nAuthorization: Basic {{username}} {{password}}")
  local proj = require("httpnvim.project").find(root)
  local secrets = require("httpnvim.secrets")
  local context = require("httpnvim.context")
  local raw = {
    ["stag/toplog"] = { username = "shared", password = "shared-pw", extra = "x" },
    ["integration/stag/toplog"] = { username = "int-user", password = "int-pw" },
    ["integration/prod/toplog"] = { username = "int-prod" },
  }

  it("splits paths that start with a service folder", function()
    local split = secrets.split(proj, raw)
    eq({ ["stag/toplog"] = raw["stag/toplog"] }, split.project)
    eq(
      { ["stag/toplog"] = raw["integration/stag/toplog"], ["prod/toplog"] = raw["integration/prod/toplog"] },
      split.services.integration
    )
  end)

  it("uses a service's own secrets over the project's, only in that service", function()
    httpnvim.setup({
      secrets = function(_, cb)
        cb(raw)
      end,
    })
    secrets.load(proj, function() end)
    vim.wait(100)
    require("httpnvim.env").select(proj, "stag/toplog")

    vim.cmd.edit(root .. "/integration/a.http")
    local ctx = context.get(0)
    eq("integration", ctx.service)
    eq("int-user", ctx.vars.username)
    eq("x", ctx.vars.extra)
    eq({ kind = "secret", env = "stag/toplog", service = "integration" }, ctx.sources.username)
    eq("secrets · integration · stag/toplog", require("httpnvim.hints").describe(ctx, ctx.sources.username))

    vim.cmd.edit(root .. "/print/b.http")
    ctx = context.get(0)
    eq("print", ctx.service)
    eq("shared", ctx.vars.username)
    eq("secrets · stag/toplog", require("httpnvim.hints").describe(ctx, ctx.sources.username))
  end)

  it("lists environments from service secrets without the service", function()
    eq({ "prod/toplog", "stag", "stag/toplog" }, context.env_names(proj))
    secrets.reset()
    httpnvim.setup({})
  end)
end)
