# sqlc.nvim

A small Neovim plugin for working with [`sqlc`](https://sqlc.dev/) projects.
It reads your `sqlc.yaml`, lets you jump between named SQL queries, and can run
`sqlc vet` into Neovim diagnostics and the quickfix list.

## Features

- Parse `sqlc.yaml`/`sqlc.yml` and discover configured query files.
- Pick SQL queries by generated Go package.
- Remember the last selected package for faster repeat navigation.
- Use Snacks picker when available, Telescope as a fallback, and `vim.ui.select`
  as the built-in fallback.
- Run `sqlc vet` and publish errors as native Neovim diagnostics.
- Optionally run vet automatically when managed SQL query files are saved.

## Requirements

- Neovim 0.10+
- `sqlc`
- `yq` for YAML-to-JSON parsing
- Optional: `snacks.nvim` or `telescope.nvim` for a richer picker UI

## Installation

With `lazy.nvim`:

```lua
{
  "0xveya/sqlc.nvim",
  dependencies = {
    -- Optional, used automatically when installed:
    -- "folke/snacks.nvim",
    -- "nvim-telescope/telescope.nvim",
  },
  opts = {
    pick_db_keymap = "<leader>sqa",
    use_last_keymap = "<leader>sql",
    lint_keymap = "<leader>sqv",
    lint_on_save = true,
  },
}
```

## Usage

Open a project with a `sqlc.yaml` file and run:

```vim
:SqlcVet
```

Default keymaps:

- `<leader>sqa`: select a sqlc package, then pick one of its named queries
- `<leader>sql`: reuse the last selected package
- `<leader>sqv`: run `sqlc vet`

The query picker jumps to the selected `-- name:` declaration in the SQL file.
`sqlc vet` diagnostics are shown in the buffer and mirrored into the quickfix
list.

## Configuration

```lua
require("sqlc_nvim").setup({
  pick_db_keymap = "<leader>sqa",
  use_last_keymap = "<leader>sql",
  lint_keymap = "<leader>sqv",
  lint_on_save = true,
  config_file = "sqlc.yaml",
  yq_cmd = "yq -o=json . %s",
  sqlc_cmd = "sqlc",
})
```
