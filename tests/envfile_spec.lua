local envfile = require("httpnvim.envfile")

describe("envfile", function()
  local path = TMP .. "/ef/http-client.env.json"
  write(path, '{\n  "stag": {\n    "base": "https://stag"\n  },\n  "stag/a": {\n    "id": "1"\n  }\n}')

  it("sets a value for one environment, keeping key order", function()
    ok(envfile.write(path, "stag/a", "id", "2"))
    ok(envfile.write(path, "stag/b", "id", "3"))
    local text = table.concat(vim.fn.readfile(path), "\n")
    eq(
      '{\n  "stag": {\n    "base": "https://stag"\n  },\n  "stag/a": {\n    "id": "2"\n  },\n  "stag/b": {\n    "id": "3"\n  }\n}',
      text
    )
  end)

  it("creates the file if needed", function()
    local new = TMP .. "/ef/new/http-client.env.json"
    ok(envfile.write(new, "dev", "x", "y"))
    eq({ dev = { x = "y" } }, vim.json.decode(table.concat(vim.fn.readfile(new), "\n")))
  end)

  it("finds a definition's line", function()
    eq(6, envfile.find_line(path, "stag/a", "id"))
    eq(9, envfile.find_line(path, "stag/b", "id"))
    eq(5, envfile.find_line(path, "stag/a", "nope"))
  end)
end)
