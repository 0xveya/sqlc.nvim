local M = {}
local config = require("sqlc_nvim.config")
local ns = vim.api.nvim_create_namespace("sqlc_diagnostics")

M.cache = {}
M.run_id = 0

local function get_project_root()
	local markers = {
		"sqlc.yaml",
		"sqlc.yml",
		".git",
	}

	local bufname = vim.api.nvim_buf_get_name(0)
	if bufname ~= "" and vim.fs and vim.fs.root then
		return vim.fs.root(bufname, markers) or vim.fn.getcwd()
	end

	return vim.fn.getcwd()
end

local function normalize_path(path, root)
	if vim.fs and vim.fs.normalize then
		path = vim.fs.normalize(path)
	end

	if vim.fs and vim.fs.is_absolute and vim.fs.is_absolute(path) then
		return path
	end

	return vim.fs.joinpath(root, path)
end

local function parse_sqlc_line(line)
	do
		local path, lnum, col, severity, msg = line:match("^([^|]+)|(%d+)%s+col%s+(%d+)%s+([^|]+)|%s*(.*)$")
		if path and lnum and col and severity and msg then
			return path, tonumber(lnum), tonumber(col), severity, msg
		end
	end

	do
		local path, lnum, col, msg = line:match("^([^:]+):(%d+):(%d+):%s*(.*)$")
		if path and lnum and col and msg then
			return path, tonumber(lnum), tonumber(col), "error", msg
		end
	end

	return nil
end

function M.clear()
	for file, _ in pairs(M.cache) do
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == file then
				pcall(vim.diagnostic.reset, ns, bufnr)
			end
		end
	end

	M.cache = {}
	vim.fn.setqflist({}, "r")
end

function M.apply_to_buffer(bufnr)
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		return
	end

	local diags = M.cache[file]
	vim.diagnostic.reset(ns, bufnr)

	if diags and #diags > 0 then
		vim.diagnostic.set(ns, bufnr, diags)
	end
end

local function collect_results(output, root)
	local qf_list = {}
	local file_diags = {}

	for _, line in ipairs(output) do
		local path, lnum, col, _severity, msg = parse_sqlc_line(line)

		if path and lnum and col and msg then
			local full_path = normalize_path(path, root)
			local lnum0 = math.max(lnum - 1, 0)
			local col0 = math.max(col - 1, 0)

			table.insert(qf_list, {
				filename = full_path,
				lnum = lnum,
				col = col,
				text = msg,
				type = "E",
			})

			file_diags[full_path] = file_diags[full_path] or {}
			table.insert(file_diags[full_path], {
				lnum = lnum0,
				col = col0,
				severity = vim.diagnostic.severity.ERROR,
				source = "sqlc vet",
				message = msg,
			})
		end
	end

	return qf_list, file_diags
end

local function publish_results(qf_list, file_diags)
	M.cache = file_diags

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		M.apply_to_buffer(bufnr)
	end

	vim.fn.setqflist({}, "r", {
		title = "SQLC Vet Errors",
		items = qf_list,
	})
end

function M.run_vet()
	local root = get_project_root()
	local sqlc_cmd = config.values.sqlc_cmd or "sqlc"
	M.run_id = M.run_id + 1
	local current_run = M.run_id

	local function handle_output(stdout, stderr)
		if current_run ~= M.run_id then
			return
		end

		local output = {}

		if stdout and stdout ~= "" then
			for line in stdout:gmatch("[^\r\n]+") do
				table.insert(output, line)
			end
		end

		if stderr and stderr ~= "" then
			for line in stderr:gmatch("[^\r\n]+") do
				table.insert(output, line)
			end
		end

		local qf_list, file_diags = collect_results(output, root)
		publish_results(qf_list, file_diags)
	end

	if vim.system then
		vim.system({ sqlc_cmd, "vet" }, { cwd = root, text = true }, function(result)
			vim.schedule(function()
				handle_output(result.stdout, result.stderr)
			end)
		end)
	else
		vim.schedule(function()
			local cmdline = "cd " .. vim.fn.shellescape(root) .. " && " .. vim.fn.shellescape(sqlc_cmd) .. " vet"
			local output = vim.fn.systemlist(cmdline)
			local qf_list, file_diags = collect_results(output, root)
			publish_results(qf_list, file_diags)
		end)
	end
end

return M
