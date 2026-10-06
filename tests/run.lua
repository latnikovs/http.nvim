-- Minimal test runner: nvim --headless --clean -l tests/run.lua [spec ...]
-- Each tests/*_spec.lua calls describe/it; eq/ok compare values.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/?.lua;" .. package.path

local failures, passed = {}, 0
local prefix = {}

function _G.describe(name, fn)
  table.insert(prefix, name)
  fn()
  table.remove(prefix)
end

function _G.it(name, fn)
  local full = table.concat(prefix, " › ") .. " › " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
  else
    table.insert(failures, full .. "\n" .. err)
  end
end

function _G.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function _G.ok(value, msg)
  if not value then
    error(msg or "expected a true value", 2)
  end
end

-- Keep notifications out of the output
_G.NOTES = {}
vim.notify = function(msg)
  table.insert(_G.NOTES, msg)
end

-- A scratch folder per run
_G.TMP = vim.fn.tempname()
vim.fn.mkdir(_G.TMP, "p")
function _G.write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end

require("httpnvim.env")._reset(_G.TMP .. "/state.json")

local specs = _G.arg and #_G.arg > 0 and _G.arg or vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
for _, spec in ipairs(specs) do
  dofile(spec)
end

vim.fn.delete(_G.TMP, "rf")
for _, f in ipairs(failures) do
  io.stdout:write("FAIL " .. f .. "\n\n")
end
io.stdout:write(("%d passed, %d failed\n"):format(passed, #failures))
os.exit(#failures == 0 and 0 or 1)
