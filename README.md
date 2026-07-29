# sqlc.nvim

Fast query navigation and quiet, reliable `sqlc vet` diagnostics for Neovim.

`sqlc.nvim` finds the nearest sqlc project from the current buffer, reads named
queries without an extra YAML dependency, and presents every query in one fuzzy
picker. Diagnostics are cached per project and refreshed after managed query
files are saved.

## Features

- One searchable picker containing query name, sqlc command, generated package,
  and relative source path.
- Optional package and command-type scope pickers, modeled after
  `go-mono-repo.nvim` entrypoint scopes.
- Prefix-aware fuzzy filtering: `many: invoice`, `db: accounts`,
  `engine:postgresql`, `file:archive`, and `query:GetUser`.
- Display-only grouping by database, query type, or file.
- Dedicated highlighting for `-- name: Query :many` directives in managed SQL
  files.
- Snacks picker with preview, Telescope fallback, and a built-in `vim.ui.select`
  fallback.
- Project discovery from the current buffer, including multiple sqlc projects
  in one Neovim session.
- Query files configured as individual files, directories, or globs.
- Asynchronous, debounced `sqlc vet` on save.
- Stale diagnostics are removed after a clean run and reapplied when a buffer is
  opened later.
- Quickfix updates are opt-in, so automatic linting does not overwrite or open
  lists used by other tools.
- No `yq` dependency. `sqlc` remains the authoritative config validator.

## Requirements

- Neovim 0.10+
- `sqlc`
- Optional: `snacks.nvim` or `telescope.nvim`

## Installation

With `lazy.nvim`:

```lua
{
  "0xveya/sqlc.nvim",
  opts = {},
}
```

Defaults:

```lua
require("sqlc_nvim").setup({
  config_files = { "sqlc.yaml", "sqlc.yml", "sqlc.json" },
  sqlc_cmd = "sqlc",
  lint_on_save = true,
  lint_debounce_ms = 250,
  update_quickfix = false,
  open_quickfix = false,
  notify = true,
  picker = {
    prefer = { "snacks", "telescope", "vim_ui" },
    group_by = "none", -- "none", "database", "type", or "file"
  },
  keymaps = {
    pick = "<leader>sqa",
    pick_last = "<leader>sql",
    pick_package = nil,
    pick_command = nil,
    group = nil,
    vet = "<leader>sqv",
  },
})
```

The old `pick_db_keymap`, `use_last_keymap`, `lint_keymap`, and `config_file`
options remain supported.

## Commands

| Command | Behavior |
| --- | --- |
| `:SqlcQueries [package]` | Fuzzy-pick all queries, optionally scoped to a package |
| `:SqlcPackages` | Pick a package scope, then fuzzy-pick its queries |
| `:SqlcQueryCommands` | Pick `:one`, `:many`, `:exec`, etc., then fuzzy-pick matching queries |
| `:SqlcGroup [none\|database\|type\|file]` | Change picker grouping without changing SQL files |
| `:SqlcVet` | Run vet now and report the result |
| `:SqlcDiagnosticsClear` | Clear diagnostics for the current project |

Automatic lint runs stay quiet unless the process fails without a parseable
diagnostic. Manual `:SqlcVet` runs report pass/fail and the issue count.

The normal query picker accepts typed prefixes. Prefixes are ordinary fuzzy
tokens and can be combined, for example `db:accounts many: invoice`.

To mirror diagnostics into quickfix, set `update_quickfix = true`. Set
`open_quickfix = true` as well only if you explicitly want the list opened after
failed runs.

## Testing

Run the deterministic headless suite:

```sh
nvim --headless -u NONE -l tests/headless.lua
```

Run against a real sqlc project:

```sh
SQLC_NVIM_FIXTURE=/path/to/project/query.sql \
  nvim --headless -u NONE -l scripts/smoke.lua
```
