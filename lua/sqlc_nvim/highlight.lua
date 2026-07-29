local M = {}
local ns = vim.api.nvim_create_namespace("sqlc.nvim.directives")
local managed = {}

local function render(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		local prefix_start, prefix_end = line:find("^%s*%-%-%s*name:%s*")
		if prefix_start then
			local name_start, name_end = line:find("[%w_]+", prefix_end + 1)
			local command_start, command_end = line:find(":[%w]+", (name_end or prefix_end) + 1)
			vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, prefix_start - 1, {
				end_col = prefix_end,
				hl_group = "SqlcDirective",
				priority = 130,
			})
			if name_start then
				vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, name_start - 1, {
					end_col = name_end,
					hl_group = "SqlcQueryName",
					priority = 131,
				})
			end
			if command_start then
				vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, command_start - 1, {
					end_col = command_end,
					hl_group = "SqlcQueryCommand",
					priority = 131,
				})
			end
		end
	end
end

function M.attach(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local path = vim.api.nvim_buf_get_name(bufnr)
	local project = require("sqlc_nvim.project").load(path)
	managed[bufnr] = project and require("sqlc_nvim.project").is_managed(project, path) or false
	if managed[bufnr] then
		render(bufnr)
	else
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	end
end

function M.setup(group)
	vim.api.nvim_set_hl(0, "SqlcDirective", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "SqlcQueryName", { default = true, link = "Function" })
	vim.api.nvim_set_hl(0, "SqlcQueryCommand", { default = true, link = "Type" })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
		group = group,
		pattern = "*.sql",
		callback = function(args)
			M.attach(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "*.sql",
		callback = function(args)
			if managed[args.buf] then
				render(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			managed[args.buf] = nil
		end,
	})
end

function M.get_namespace()
	return ns
end

return M
