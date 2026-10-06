-- Inline hints: after a line with {{variables}}, each one's value for the
-- selected environment and where it comes from. Undefined ones are red.
local config = require("httpnvim.config")
local context = require("httpnvim.context")
local parser = require("httpnvim.parser")
local project = require("httpnvim.project")
local resolve = require("httpnvim.resolve")
local secrets = require("httpnvim.secrets")

local M = {}

M.ns = vim.api.nvim_create_namespace("httpnvim.hints")

local function truncate(text, width)
  text = text:gsub("\n", "⏎")
  if vim.fn.strchars(text) > width then
    return vim.fn.strcharpart(text, 0, width - 1) .. "…"
  end
  return text
end

-- "api/http-client.env.json" -> "api", "." for the root; " private" added
function M.describe(ctx, source)
  if source.kind == "line" then
    return "@line " .. (source.lnum or "?")
  elseif source.kind == "secret" then
    return "secrets · " .. source.env
  end
  local dir = project.relative(ctx.project, vim.fs.dirname(source.path))
  return dir .. (source.private and " private" or "") .. " · " .. source.env
end

-- Hint chunks for one variable
local function chunks(ctx, name)
  if resolve.DYNAMIC[name] then
    return nil
  end
  local value, missing = resolve.value(name, ctx.vars)
  if not value then
    local locked = not secrets.is_loaded(ctx.project)
    local what = ctx.vars[name] == nil and name or (name .. " → " .. table.concat(vim.tbl_keys(missing), ", "))
    if locked then
      return { { what .. " (secrets locked)", "HttpnvimHintLocked" } }
    end
    return { { what .. " undefined" .. (ctx.env and "" or " (no environment)"), "HttpnvimHintMissing" } }
  end
  local shown = config.masked(name) and "••••" or truncate(value, config.options.hints.max_width)
  return {
    { name .. " = ", "HttpnvimHintName" },
    { shown, "HttpnvimHint" },
    { "  " .. M.describe(ctx, ctx.sources[name]), "HttpnvimHintSource" },
  }
end

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  if not config.options.hints.enabled then
    return
  end
  local ctx = context.get(buf)
  for i, line in ipairs(ctx.lines) do
    local text = {}
    local seen = {}
    for _, ref in ipairs(parser.references(line)) do
      if not seen[ref[1]] then
        seen[ref[1]] = true
        local c = chunks(ctx, ref[1])
        if c then
          table.insert(text, { #text == 0 and "  " or "   ", "HttpnvimHintSource" })
          vim.list_extend(text, c)
        end
      end
    end
    if #text > 0 then
      vim.api.nvim_buf_set_extmark(
        buf,
        M.ns,
        i - 1,
        0,
        { virt_text = text, virt_text_pos = "eol", hl_mode = "combine" }
      )
    end
  end
end

-- Every visible .http buffer
function M.refresh()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "http" and vim.bo[buf].buftype == "" then
      M.render(buf)
    end
  end
end

function M.setup()
  local links = {
    HttpnvimHint = "Comment",
    HttpnvimHintName = "Comment",
    HttpnvimHintSource = "NonText",
    HttpnvimHintMissing = "DiagnosticError",
    HttpnvimHintLocked = "DiagnosticWarn",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
  local group = vim.api.nvim_create_augroup("httpnvim.hints", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave", "FileType" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "http" and vim.bo[ev.buf].buftype == "" then
        M.render(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { project.ENV_FILE, project.PRIVATE_ENV_FILE },
    callback = M.refresh,
  })
end

return M
