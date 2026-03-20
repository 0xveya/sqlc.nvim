local config = require("sqlc_nvim.config")
local M = {}

M.last_used_pkg = nil

function M.parse_sqlc_config()
	local cfg = config.values
	local config_path = vim.fn.getcwd() .. "/" .. cfg.config_file

	if vim.fn.filereadable(config_path) == 0 then
		return nil
	end

	local cmd = string.format(cfg.yq_cmd, vim.fn.shellescape(config_path))
	local json_data = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, json_data)
	return ok and decoded or nil
end

local function get_queries_from_file(filepath)
	local queries = {}
	local abs_path = vim.fn.fnamemodify(filepath, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return queries
	end

	local line_num = 1
	for line in io.lines(abs_path) do
		local name_with_type = line:match("%-%-%s*name:%s*(%w+.*)")
		if name_with_type then
			name_with_type = name_with_type:gsub("%s+$", "")
			table.insert(queries, {
				name = name_with_type,
				path = abs_path,
				lnum = line_num,
			})
		end
		line_num = line_num + 1
	end
	return queries
end

local function open_picker(pkg_name, all_queries)
	local has_snacks, snacks = pcall(require, "snacks")
	if has_snacks and snacks.picker then
		snacks.picker.pick({
			source = "sqlc_queries",
			items = all_queries,
			title = "SQLC: " .. pkg_name,
			format = "text",
			-- Map internal fields to Snacks format
			transform = function(item)
				item.text = item.name
				item.file = item.path
				item.pos = { item.lnum, 0 }
				return item
			end,
			confirm = function(picker, item)
				picker:close()
				vim.cmd("edit " .. item.path)
				vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
			end,
		})
		return
	end

	local has_telescope, _ = pcall(require, "telescope")
	if has_telescope then
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		pickers
			.new({}, {
				prompt_title = "SQLC Queries: " .. pkg_name,
				finder = finders.new_table({
					results = all_queries,
					entry_maker = function(entry)
						return {
							value = entry,
							display = entry.name,
							ordinal = entry.name,
							path = entry.path,
							lnum = entry.lnum,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = conf.file_previewer({}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						actions.close(prompt_bufnr)
						local selection = action_state.get_selected_entry()
						vim.cmd("edit " .. selection.path)
						vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
					end)
					return true
				end,
			})
			:find()
		return
	end

	vim.ui.select(all_queries, {
		prompt = "SQLC Queries (" .. pkg_name .. "):",
		format_item = function(item)
			return item.name
		end,
	}, function(choice)
		if choice then
			vim.cmd("edit " .. choice.path)
			vim.api.nvim_win_set_cursor(0, { choice.lnum, 0 })
		end
	end)
end

function M.pick_query(use_last)
	local config = M.parse_sqlc_config()
	if not config or not config.sql then
		return
	end

	local function run(pkg_name, query_files)
		M.last_used_pkg = pkg_name
		local all_queries = {}
		for _, file in ipairs(query_files) do
			local file_queries = get_queries_from_file(file)
			for _, q in ipairs(file_queries) do
				table.insert(all_queries, q)
			end
		end
		open_picker(pkg_name, all_queries)
	end

	-- Logic for 'Use Last'
	if use_last and M.last_used_pkg then
		for _, entry in ipairs(config.sql) do
			if entry.gen.go.package == M.last_used_pkg then
				return run(entry.gen.go.package, entry.queries)
			end
		end
	end

	-- Ask for DB
	local db_options = {}
	for _, entry in ipairs(config.sql) do
		table.insert(db_options, { pkg = entry.gen.go.package, queries = entry.queries })
	end

	vim.ui.select(db_options, {
		prompt = "Select Database:",
		format_item = function(item)
			return item.pkg
		end,
	}, function(choice)
		if choice then
			run(choice.pkg, choice.queries)
		end
	end)
end

function M.setup(opts)
	local cfg = config.setup(opts)

	if cfg.pick_db_keymap then
		vim.keymap.set("n", cfg.pick_db_keymap, function()
			M.pick_query(false)
		end, { desc = "SQLC: Select DB and Query" })
	end

	if cfg.use_last_keymap then
		vim.keymap.set("n", cfg.use_last_keymap, function()
			M.pick_query(true)
		end, { desc = "SQLC: Last DB Queries" })
	end
end

return M
