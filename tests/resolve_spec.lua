local resolve = require("httpnvim.resolve")

describe("resolve", function()
  it("fills variables, nested ones too", function()
    local req = resolve.request({
      method = "GET",
      url = "{{api}}/items/{{id}}",
      headers = { { "Authorization", "Basic {{user}} {{pass}}" } },
    }, { api = "{{base}}/v1", base = "http://x", id = 7, user = "u", pass = "p w" })
    eq("http://x/v1/items/7", req.url)
    eq("Basic " .. vim.base64.encode("u:p w"), req.headers[1][2])
  end)

  it("reports missing names", function()
    local req, missing = resolve.request({ method = "GET", url = "{{a}}/{{b}}/{{c}}", headers = {} }, { b = "{{d}}" })
    eq(nil, req)
    eq({ "a", "c", "d" }, missing)
  end)

  it("knows built-in variables", function()
    ok(resolve.value("$uuid", {}):match("^%x+%-%x+%-4%x+%-[89ab]%x+%-%x+$"))
  end)
end)
