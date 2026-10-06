local parser = require("httpnvim.parser")

local doc = {
  "@base = http://x",
  "",
  "### List items",
  "GET {{base}}/items",
  "    ?page=1",
  "    &size=2",
  "Accept: application/json",
  "# a comment",
  "",
  "### Create",
  "POST {{base}}/items HTTP/1.1",
  "Content-Type: application/json",
  "",
  "{",
  '  "a": 1',
  "}",
  "",
  "",
  "###",
  "{{base}}/health",
}

describe("parser", function()
  it("reads file variables with their lines", function()
    local vars, where = parser.file_vars(doc)
    eq({ base = "http://x" }, vars)
    eq({ base = 1 }, where)
  end)

  it("parses the request around a line", function()
    local req = parser.at(doc, 7)
    eq("GET", req.method)
    eq("{{base}}/items?page=1&size=2", req.url)
    eq({ { "Accept", "application/json" } }, req.headers)
    eq(nil, req.body)
    eq("List items", req.name)
    eq(4, req.lnum)
  end)

  it("keeps the body and drops trailing blank lines", function()
    local req = parser.at(doc, 11)
    eq("POST", req.method)
    eq('{\n  "a": 1\n}', req.body)
  end)

  it("defaults to GET and names unnamed requests", function()
    local req = parser.at(doc, 20)
    eq("GET", req.method)
    eq("GET {{base}}/health", req.name)
  end)

  it("lists every request", function()
    local names = vim.tbl_map(function(r)
      return r.name .. "@" .. r.lnum
    end, parser.requests(doc))
    eq({ "List items@4", "Create@11", "GET {{base}}/health@20" }, names)
  end)

  it("returns nil where there is no request", function()
    eq(nil, parser.at({ "@a = 1", "", "# only a comment" }, 1))
  end)

  it("finds references with columns", function()
    eq({ { "base", 4, 12 }, { "id", 13, 21 } }, parser.references("GET {{base}}/{{ id }}"))
  end)
end)
