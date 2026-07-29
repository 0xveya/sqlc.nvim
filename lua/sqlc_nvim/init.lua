local config = require("sqlc_nvim.config")
local project_mod = require("sqlc_nvim.project")
local M = { last_package = nil, last_command = nil, group_by = "none" }

local function notify(message, level)
	if config.values.notify then
		vim.notify(message, level or vim.log.levels.INFO, { title = "sqlc.nvim" })
	end
end

local function map(lhs, rhs, desc)
	if lhs and lhs ~= "" then
		vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
	end
end

local function query_items(project, filters)
	filters = filters or {}
	project_mod.query_files(project)
	local items = {}
	for _, entry in ipairs(project.sql) do
		if not filters.package or entry.package == filters.package then
			for _, path in ipairs(entry.files or {}) do
				for lnum, line in ipairs(vim.fn.readfile(path)) do
					local name, command = line:match("^%s*%-%-%s*name:%s*([%w_]+)%s*:?([%w]*)")
					command = command ~= "" and command or "exec"
					if name and (not filters.command or command:lower() == filters.command:lower()) then
						local prefix = project.root:gsub("([^%w])", "%%%1") .. "/"
						local relative = path:gsub("^" .. prefix, "")
						table.insert(items, {
							query = name,
							command = command,
							package = entry.package,
							database = entry.package,
							engine = entry.engine or "sql",
							file = path,
							relative_file = relative,
							relative = relative .. ":" .. lnum,
							lnum = lnum,
							pos = { lnum, 0 },
							preview = "file",
							text = table.concat({
								name,
								command,
								entry.package,
								relative,
								"query:" .. name,
								command .. ":",
								"type:" .. command,
								"db:" .. entry.package,
								"package:" .. entry.package,
								"engine:" .. (entry.engine or "sql"),
								"file:" .. relative,
							}, " "),
						})
					end
				end
			end
		end
	end
	local group_fields = { database = "database", type = "command", file = "relative_file" }
	local group_field = group_fields[M.group_by]
	table.sort(items, function(a, b)
		if group_field and a[group_field] ~= b[group_field] then
			return a[group_field]:lower() < b[group_field]:lower()
		end
		return a.query:lower() < b.query:lower()
	end)
	for index, item in ipairs(items) do
		local value = group_field and item[group_field] or nil
		local previous = index > 1 and group_field and items[index - 1][group_field] or nil
		item.group_label = value and value ~= previous and ("[" .. value .. "]") or nil
		item.sort = ("%s %s"):format(value or "", item.query:lower())
	end
	return items
end

local function scope_items(items, field)
	local counts = {}
	for _, item in ipairs(items) do
		counts[item[field]] = (counts[item[field]] or 0) + 1
	end
	local result = {}
	for label, count in pairs(counts) do
		table.insert(result, {
			kind = "scope",
			label = label,
			count = count,
			text = label .. " " .. count .. " queries",
		})
	end
	table.sort(result, function(a, b)
		return a.label:lower() < b.label:lower()
	end)
	return result
end

local function load_project()
	local project, err = project_mod.load()
	if not project then
		notify(err, vim.log.levels.WARN)
		return nil
	end
	return project
end

function M.pick_query(opts)
	if type(opts) == "boolean" then
		opts = { package = opts and M.last_package or nil }
	end
	opts = opts or {}
	local project = load_project()
	if not project then
		return
	end
	local items = query_items(project, opts)
	if #items == 0 and opts.package == M.last_package then
		opts.package, items = nil, query_items(project, opts)
	end
	if #items == 0 then
		notify("No named sqlc queries match this scope", vim.log.levels.WARN)
		return
	end
	require("sqlc_nvim.picker").pick(items, {
		title = ("sqlc queries%s%s"):format(
			opts.package and (" · package:" .. opts.package) or "",
			opts.command and (" · command:" .. opts.command) or ""
		),
		on_choice = function(item)
			M.last_package = item.package
			M.last_command = item.command
		end,
	})
end

function M.pick_scope(field)
	local project = load_project()
	if not project then
		return
	end
	local items = query_items(project)
	local scopes = scope_items(items, field)
	if #scopes == 0 then
		notify("No named sqlc queries found", vim.log.levels.WARN)
		return
	end
	require("sqlc_nvim.picker").pick(scopes, {
		title = field == "package" and "sqlc packages" or "sqlc query commands",
		select_only = true,
		on_choice = function(item)
			M.pick_query({ [field] = item.label })
		end,
	})
end

function M.set_group(group)
	if not ({ none = true, database = true, type = true, file = true })[group] then
		notify("Unknown grouping: " .. tostring(group), vim.log.levels.WARN)
		return
	end
	M.group_by = group
	notify("sqlc query grouping: " .. group)
end

local function complete_scope(field)
	return function()
		local project = project_mod.load()
		if not project then
			return {}
		end
		return vim.tbl_map(function(item)
			return item.label
		end, scope_items(query_items(project), field))
	end
end

function M.setup(opts)
	local cfg = config.setup(opts)
	M.group_by = cfg.picker.group_by
	local group = vim.api.nvim_create_augroup("sqlc.nvim", { clear = true })
	require("sqlc_nvim.highlight").setup(group)

	vim.api.nvim_create_user_command("SqlcQueries", function(command)
		M.pick_query({ package = command.args ~= "" and command.args or nil })
	end, {
		force = true,
		nargs = "?",
		complete = complete_scope("package"),
		desc = "Pick a named sqlc query, optionally by package",
	})
	vim.api.nvim_create_user_command("SqlcPackages", function()
		M.pick_scope("package")
	end, { force = true, desc = "Pick a sqlc package, then a query" })
	vim.api.nvim_create_user_command("SqlcQueryCommands", function()
		M.pick_scope("command")
	end, { force = true, desc = "Pick a sqlc command type, then a query" })
	vim.api.nvim_create_user_command("SqlcGroup", function(command)
		if command.args ~= "" then
			M.set_group(command.args)
			return
		end
		vim.ui.select({ "none", "database", "type", "file" }, { prompt = "sqlc query grouping" }, function(choice)
			if choice then
				M.set_group(choice)
			end
		end)
	end, {
		force = true,
		nargs = "?",
		complete = function()
			return { "none", "database", "type", "file" }
		end,
		desc = "Choose display-only query grouping",
	})
	vim.api.nvim_create_user_command("SqlcVet", function()
		require("sqlc_nvim.lint").run({ manual = true })
	end, { force = true, desc = "Run sqlc vet and refresh diagnostics" })
	vim.api.nvim_create_user_command("SqlcDiagnosticsClear", function()
		require("sqlc_nvim.lint").clear()
	end, { force = true, desc = "Clear sqlc diagnostics" })

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
		group = group,
		pattern = "*.sql",
		callback = function(args)
			require("sqlc_nvim.lint").apply_to_buffer(args.buf)
		end,
	})
	if cfg.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = group,
			pattern = "*.sql",
			callback = function(args)
				local path = vim.api.nvim_buf_get_name(args.buf)
				local project = project_mod.load(path)
				if project and project_mod.is_managed(project, path) then
					require("sqlc_nvim.lint").schedule(path)
				end
			end,
		})
	end

	map(cfg.keymaps.pick, function()
		M.pick_query(false)
	end, "sqlc: query picker")
	map(cfg.keymaps.pick_last, function()
		M.pick_query(true)
	end, "sqlc: last package queries")
	map(cfg.keymaps.pick_package, function()
		M.pick_scope("package")
	end, "sqlc: package scope")
	map(cfg.keymaps.pick_command, function()
		M.pick_scope("command")
	end, "sqlc: query command scope")
	map(cfg.keymaps.group, function()
		vim.cmd.SqlcGroup()
	end, "sqlc: query grouping")
	map(cfg.keymaps.vet, function()
		require("sqlc_nvim.lint").run({ manual = true })
	end, "sqlc: vet project")
end

return M
