local env = require("httpnvim.env")
local project = require("httpnvim.project")

describe("project", function()
  it("is the folder named http, named after its parent", function()
    local root = TMP .. "/wms/http"
    vim.fn.mkdir(root .. "/api/inventory", "p")
    local proj = project.find(root .. "/api/inventory")
    eq(root, proj.root)
    eq("wms", proj.name)
    eq({ root, root .. "/api", root .. "/api/inventory" }, project.chain(proj, root .. "/api/inventory"))
  end)

  it("falls back to the nearest folder with an env file", function()
    local dir = TMP .. "/plain"
    write(dir .. "/http-client.env.json", "{}")
    vim.fn.mkdir(dir .. "/sub", "p")
    eq(dir, project.find(dir .. "/sub").root)
  end)
end)

describe("env", function()
  local root = TMP .. "/svc/http"
  write(
    root .. "/http-client.env.json",
    vim.json.encode({
      ["$shared"] = { accept = "json" },
      stag = { base = "https://stag" },
      ["stag/a"] = { id = "a-root" },
      ["stag/b"] = { id = "b-root" },
      prod = { base = "https://prod" },
    })
  )
  write(root .. "/http-client.private.env.json", vim.json.encode({ ["stag/a"] = { id = "a-private" } }))
  write(root .. "/api/http-client.env.json", vim.json.encode({ stag = { base = "https://stag/api" } }))
  local proj = project.find(root)

  it("lists environment names from every env file and secrets", function()
    eq({ "prod", "stag", "stag/a", "stag/b", "stag/c" }, env.names(env.all_files(proj), { ["stag/c"] = {} }))
  end)

  it("applies levels, nearer files winning within a level", function()
    local files = env.files(proj, root .. "/api")
    local vars, sources = env.vars(files, "stag/a")
    eq("https://stag/api", vars.base)
    eq("a-private", vars.id)
    eq("json", vars.accept)
    eq(root .. "/api/http-client.env.json", sources.base.path)
    eq("stag", sources.base.env)
    eq(true, sources.id.private)
  end)

  it("puts env values over @variables and secrets over files", function()
    local files = env.files(proj, root)
    local vars, sources = env.vars(
      files,
      "stag/b",
      { ["stag/b"] = { id = "secret" } },
      { id = "line", x = "1" },
      { x = 3 }
    )
    eq("secret", vars.id)
    eq("secret", sources.id.kind)
    eq("1", vars.x)
    eq({ kind = "line", lnum = 3 }, sources.x)
  end)

  it("remembers the selected environment", function()
    env.select(proj, "stag/b")
    env._reset()
    eq("stag/b", env.selected(proj))
  end)
end)
