# http.nvim

A REST client for Neovim. Requests live in `.http` files (the IntelliJ HTTP
Client format), run through curl, and their responses open in a pane below
the request. Plain Lua, nothing to download besides curl, MIT licensed.

- Send the request under the cursor; body (JSON formatted by jq), headers and
  the request as sent in the response pane
- Environments in `http-client.env.json` with a hierarchy: `stag/client`
  builds on `stag`
- Env files merged from the project root down to the request's folder
- Each variable's value and origin shown at the end of the line
- Undefined variables (ids and such) are asked for on send and kept for the
  session, per environment; nothing is written to your files
- A sidebar with the environments and the request tree, in the spirit of
  vim-dadbod-ui
- A hook for secrets, so credentials can come from a password manager

## Requirements

- Neovim 0.11+
- curl
- jq (formats JSON responses; needed to set variables)
- The `http` tree-sitter parser, for highlighting (optional)

## Install

With lazy.nvim:

```lua
{
  "latnikovs/http.nvim",
  ft = "http",
  cmd = { "HttpToggle", "HttpEnv" },
  opts = {},
}
```

`setup()` takes the options in [config.lua](lua/httpnvim/config.lua). There
are no default global keymaps; see [Keymaps](#keymaps).

## Getting started

Open the sidebar (`:HttpToggle`) in a repository without an `http/` folder
and it offers to create one at the git root, asking for the environments
(`stag, prod`). Private env files go into `.git/info/exclude`.

In the sidebar, `a` with a name ending in `/` adds a folder; a top-level
folder is a service, so it also asks for its base URL per environment and
writes the folder's env file. Folders with an env file show their base URL
for the selected environment, and `b` changes it (for `stag` when
`stag/client` is selected, so every client shares it). `n` adds a request ("Health", then
`GET /actuator/health`), with the headers of the request before it, or
`Authorization: Basic {{username}} {{password}}` and `Accept:
application/json` in a new file. `:HttpNew` does the same below the request
under the cursor.

## Requests

```http
@token = abc

### Inventory status
GET {{base}}/inventory/{{inventoryId}}/status
Authorization: Basic {{username}} {{password}}
Accept: application/json

### Create order
POST {{base}}/orders
Content-Type: application/json

{ "id": "{{$uuid}}" }
```

- `###` starts a request; the rest of the line is its name
- Method and URL, then headers up to the first blank line, then the body. A
  long URL can go on in indented `?a=1` / `&b=2` lines
- `@name = value` lines define variables for the whole file
- `Authorization: Basic user password` is base64-encoded when sent
- Built in: `{{$uuid}}`, `{{$timestamp}}`, `{{$isoTimestamp}}`

## Projects and environments

A project is a folder called `http/` (named after the folder it is in), or
else the nearest folder with an `http-client.env.json`. Organise requests in
folders as deep as you like:

```
wms/http/
  http-client.env.json          environments and client-level values
  http-client.private.env.json  values to keep out of git
  api/
    http-client.env.json        base URL of this service per environment
    inventory/status.http
  data-api/
    http-client.env.json
    stock.http
```

Environment names form a hierarchy with `/`. Selecting `stag/client-a`
applies `$shared`, then `stag`, then `stag/client-a`:

```json
{
  "$shared": { "accept": "application/json" },
  "stag": { "base": "https://stag.example.com/v1" },
  "stag/client-a": { "inventoryId": "1001" },
  "stag/client-b": { "inventoryId": "2002" }
}
```

Env files are read in every folder from the project root down to the
request's folder, public then private. For each level a nearer file wins, and
a more specific level wins over a nearer file. Env values win over
`@variables`, as in IntelliJ. The selected environment is remembered per
project.

IntelliJ reads the same files, but without the hierarchy: there,
`stag/client-a` doesn't inherit `base` from `stag`.

## Variables

Each `{{variable}}` gets a hint at the end of its line with its value for the
selected environment and where it comes from (`api · stag`,
`. private · stag/client-a`, `secrets · stag/client-a`, `session · stag/client-a`,
`@line 1`). Undefined
ones are red. Values of names matching `mask` (password, token, …) show as
`••••`.

- Sending a request with undefined variables asks for each. The values are
  throwaway: kept in memory for the selected environment until nvim exits,
  never written to env files (put a value in an env file yourself to keep it)
- `:HttpSetVar` (on a `{{variable}}`) asks for a value the same way, also to
  override one from an env file for the session; an empty value forgets it
- `base` (see `service_vars`) is config, not a throwaway value: it is saved
  in the env file of the request's top-level folder, for the top environment
  level (`stag` when `stag/client-a` is selected)
- `require("httpnvim").goto_var()` jumps to the definition

## Sidebar

`:HttpToggle` opens the sidebar for the project of the current directory:

```
 wms  stag/client-a

▾ Environments
    stag
    ● client-a
      client-b
▾ Requests
  ▾ api
    ▾ inventory
      ▾ status.http
          GET    Inventory status
  ▸ data-api
```

| Key | |
|---|---|
| `<CR>` | select environment, fold, open request |
| `s` | send the request |
| `n` | new request (in the file, or a file in the folder) |
| `b` | set the base URL of a folder for the environment |
| `o` | open in the editor |
| `e` | choose environment |
| `a` | add a file, or a folder ending in `/` |
| `r` / `d` | rename / delete |
| `R` / `q` / `?` | refresh / close / help |

## Response pane

`<Tab>` / `<S-Tab>` switch between body, headers and request; `<C-c>`
cancels; `q` closes. The window bar shows status, method and URL, time, size
and environment.

## Secrets

```lua
opts = {
  secrets = function(project, callback)
    -- project = { name = "wms", root = "/…/wms/http" }
    callback({ ["stag/client-a"] = { username = "…", password = "…" } })
  end,
}
```

A path that starts with a service (a top-level folder of the project) holds
that service's own secrets: `integration/stag/client-a` applies to requests
in `integration/` only, over the project-wide `stag/client-a`. Environments
are listed without the service.

The hook runs once per project and session: when the sidebar opens, which
then asks for the environment right away (as dadbod-ui does with its
connections; `sidebar = { unlock = false }` turns it off), else on the first
send that needs a variable the env files don't have, or from the sidebar's
"unlock secrets".
Secrets go over env files, environments that exist only there are listed
too, and a missing secret is an error instead of a prompt.
`:HttpSecretsReset` forgets them.

## Commands

| Command | |
|---|---|
| `:HttpSend` | send the request under the cursor |
| `:HttpReplay` | send the last request again |
| `:HttpCancel` | cancel the running request |
| `:HttpEnv [name]` | select an environment |
| `:HttpSetVar [name]` | set a variable for the environment (this session) |
| `:HttpView [body\|headers\|request]` | switch the response view |
| `:HttpCurl` | copy the request as a curl command |
| `:HttpToggle` | toggle the sidebar |
| `:HttpNew` | add a request below the current one |
| `:HttpSecretsReset` | forget loaded secrets |

## Keymaps

None by default. For example:

```lua
vim.keymap.set("n", "<leader>H", "<cmd>HttpToggle<cr>", { desc = "HTTP Sidebar" })
vim.api.nvim_create_autocmd("FileType", {
  pattern = "http",
  callback = function(ev)
    local http = require("httpnvim")
    local map = function(lhs, fn, desc)
      vim.keymap.set("n", lhs, function() fn() end, { buffer = ev.buf, desc = desc })
    end
    map("<leader>Rs", http.send_at, "Send Request")
    map("<leader>Re", http.select_env, "Select Environment")
    map("<leader>Rv", http.set_var, "Set Variable")
    map("gd", http.goto_var, "Go to Variable")
  end,
})
```

## Development

```sh
make test   # headless Neovim, tests/*_spec.lua (send tests need python3)
make lint   # stylua --check
```

## License

MIT
