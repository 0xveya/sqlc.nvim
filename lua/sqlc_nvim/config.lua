local M = {}

M.defaults = {
	pick_db_keymap = "<leader>sqa",
	use_last_keymap = "<leader>sql",
	yq_cmd = "yq -o=json . %s",
	config_file = "sqlc.yaml",
	lint_keymap = "<leader>sqv",
	lint_on_save = true,
	sqlc_cmd = "sqlc",
}

M.values = {}

function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", M.defaults, opts or {})
	return M.values
end

return M
