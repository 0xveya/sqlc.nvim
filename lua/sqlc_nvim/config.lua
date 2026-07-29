local M = {}

M.defaults = {
	config_files = { "sqlc.yaml", "sqlc.yml", "sqlc.json" },
	sqlc_cmd = "sqlc",
	lint_on_save = true,
	lint_debounce_ms = 250,
	update_quickfix = false,
	open_quickfix = false,
	notify = true,
	picker = {
		prefer = { "snacks", "telescope", "vim_ui" },
		group_by = "none",
	},
	keymaps = {
		pick = "<leader>sqa",
		pick_last = "<leader>sql",
		pick_package = nil,
		pick_command = nil,
		group = nil,
		vet = "<leader>sqv",
	},
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
	opts = opts or {}

	-- Keep the original option names working.
	opts.keymaps = opts.keymaps or {}
	if opts.pick_db_keymap ~= nil then
		opts.keymaps.pick = opts.pick_db_keymap
	end
	if opts.use_last_keymap ~= nil then
		opts.keymaps.pick_last = opts.use_last_keymap
	end
	if opts.lint_keymap ~= nil then
		opts.keymaps.vet = opts.lint_keymap
	end
	if opts.config_file then
		opts.config_files = { opts.config_file }
	end

	M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	return M.values
end

return M
