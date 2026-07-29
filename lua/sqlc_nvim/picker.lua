local M = {}

local function open(item, opts)
	if not item then
		return
	end
	if opts and opts.on_choice then
		opts.on_choice(item)
	end
	if opts and opts.select_only then
		return
	end
	vim.cmd.edit(vim.fn.fnameescape(item.file))
	vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
end

local function format_item(item)
	if item.kind == "scope" then
		return {
			{ item.label, "Type", field = "label" },
			{ ("  %d queries"):format(item.count), "Comment", field = "count" },
		}
	end
	local group = item.group_label and (item.group_label .. "  ") or ""
	return {
		{ group, "DiagnosticHint", field = "group" },
		{ item.query, "Function", field = "query" },
		{ "  " .. item.command, "Comment", field = "command" },
		{ "  " .. item.package, "Type", field = "package" },
		{ "  " .. item.relative, "Comment", field = "file" },
	}
end

local function display_item(item)
	if item.kind == "scope" then
		return ("%s  %d queries"):format(item.label, item.count)
	end
	return ("%s%s  %s  [%s]  %s"):format(
		item.group_label and (item.group_label .. "  ") or "",
		item.query,
		item.command,
		item.package,
		item.relative
	)
end

local function snacks(items, title, opts)
	local ok, mod = pcall(require, "snacks")
	local picker = ok and mod.picker or nil
	if not picker then
		ok, picker = pcall(require, "snacks.picker")
	end
	if not ok or not picker or not picker.pick then
		return false
	end
	picker.pick({
		title = title,
		items = items,
		format = format_item,
		matcher = { sort_empty = false },
		sort = { fields = { "score:desc", "sort", "idx" } },
		confirm = function(p, item)
			p:close()
			open(item, opts)
		end,
	})
	return true
end

local function telescope(items, title, opts)
	local ok, pickers = pcall(require, "telescope.pickers")
	if not ok then
		return false
	end
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	pickers
		.new({}, {
			prompt_title = title,
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return {
						value = item,
						display = display_item(item),
						ordinal = item.text,
						filename = not opts.select_only and item.file or nil,
						lnum = not opts.select_only and item.lnum or nil,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = not opts.select_only and conf.file_previewer({}) or nil,
			attach_mappings = function(bufnr)
				local actions = require("telescope.actions")
				actions.select_default:replace(function()
					local selected = require("telescope.actions.state").get_selected_entry()
					actions.close(bufnr)
					open(selected.value, opts)
				end)
				return true
			end,
		})
		:find()
	return true
end

function M.pick(items, opts)
	opts = opts or {}
	local prefer = require("sqlc_nvim.config").values.picker.prefer
	for _, name in ipairs(prefer) do
		if name == "snacks" and snacks(items, opts.title, opts) then
			return
		elseif name == "telescope" and telescope(items, opts.title, opts) then
			return
		elseif name == "vim_ui" then
			vim.ui.select(items, {
				prompt = opts.title,
				format_item = display_item,
			}, function(item)
				open(item, opts)
			end)
			return
		end
	end
end

return M
