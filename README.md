# http.nvim

A REST client for Neovim that runs requests from `.http` files (the IntelliJ
HTTP Client format) through curl. Plain Lua, no external binaries beyond curl,
MIT licensed.

> Work in progress: not usable yet.

## Planned

- Send the request under the cursor; response in a pane below the request
- Environments from `http-client.env.json` / `http-client.private.env.json`,
  with a hierarchy (`stag` → `stag/client`) and env files merged up the folder
  tree
- Resolved variable values shown inline, set per environment from the request
- A sidebar (in the spirit of vim-dadbod-ui) to pick the environment and
  browse and run requests
- A hook for secrets, so credentials can come from a password manager

## Requirements

- Neovim 0.11+
- curl
- jq (optional, formats JSON responses)

## License

MIT
