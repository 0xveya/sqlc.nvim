local config = require("sqlc_nvim.config")
local project_mod = require("sqlc_nvim.project")
local M = {}
local ns = vim.api.nvim_create_namespace("sqlc.nvim")

M.projects = {}
M.timers = {}
M.run_id = {}

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function is_absolute(path)
	return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function notify(message, level)
	if config.values.notify then
		vim.notify(message, level or vim.log.levels.INFO, { title = "sqlc.nvim" })
	end
end

local function parse_line(line, root)
	local path, lnum, col, message = line:match("^(.-):(%d+):(%d+):%s*(.+)$")
	if not path then
		path, lnum, col, _, message = line:match("^(.-)|(%d+)%s+col%s+(%d+)%s+([^|]+)|%s*(.+)$")
	end
	if not path then
		return nil
	end
	if not is_absolute(path) then
		path = vim.fs.joinpath(root, path)
	end
	return normalize(path), tonumber(lnum), tonumber(col), message
end

local function apply(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return
	end
	local file = normalize(name)
	vim.diagnostic.reset(ns, bufnr)
	for _, state in pairs(M.projects) do
		local diagnostics = state.diagnostics[file]
		if diagnostics then
			vim.diagnostic.set(ns, bufnr, diagnostics)
			return
		end
	end
end

function M.apply_to_buffer(bufnr)
	apply(bufnr)
end

local function publish(project, lines, code, manual)
	local state = { diagnostics = {}, quickfix = {}, code = code }
	for _, line in ipairs(lines) do
		local path, lnum, col, message = parse_line(line, project.root)
		if path then
			state.diagnostics[path] = state.diagnostics[path] or {}
			table.insert(state.diagnostics[path], {
				lnum = math.max(lnum - 1, 0),
				col = math.max(col - 1, 0),
				severity = vim.diagnostic.severity.ERROR,
				source = "sqlc",
				message = message,
			})
			table.insert(state.quickfix, {
				filename = path,
				lnum = lnum,
				col = col,
				text = message,
				type = "E",
			})
		end
	end
	M.projects[project.root] = state
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		apply(bufnr)
	end

	if config.values.update_quickfix then
		vim.fn.setqflist({}, "r", { title = "sqlc: " .. project.root, items = state.quickfix })
		if config.values.open_quickfix and #state.quickfix > 0 then
			vim.cmd.copen()
		end
	end
	if manual then
		if #state.quickfix > 0 then
			notify(("%d sqlc issue%s"):format(#state.quickfix, #state.quickfix == 1 and "" or "s"), vim.log.levels.WARN)
		elseif code == 0 then
			notify("sqlc vet passed")
		else
			notify("sqlc vet failed; see :messages", vim.log.levels.ERROR)
		end
	elseif code ~= 0 and #state.quickfix == 0 then
		notify("sqlc vet failed without parseable diagnostics", vim.log.levels.ERROR)
	end
end

function M.run(opts)
	opts = opts or {}
	local project, err = project_mod.load(opts.path)
	if not project then
		if opts.manual then
			notify(err, vim.log.levels.WARN)
		end
		return
	end
	M.run_id[project.root] = (M.run_id[project.root] or 0) + 1
	local id = M.run_id[project.root]
	local args = { config.values.sqlc_cmd, "vet", "-f", project.config }
	vim.system(args, { cwd = project.root, text = true }, function(result)
		vim.schedule(function()
			if id ~= M.run_id[project.root] then
				return
			end
			local lines = {}
			for line in ((result.stdout or "") .. "\n" .. (result.stderr or "")):gmatch("[^\r\n]+") do
				table.insert(lines, line)
			end
			publish(project, lines, result.code, opts.manual)
		end)
	end)
end

function M.schedule(path)
	local project = project_mod.find(path)
	if not project then
		return
	end
	local old = M.timers[project.root]
	if old then
		old:stop()
		old:close()
	end
	local timer = (vim.uv or vim.loop).new_timer()
	M.timers[project.root] = timer
	timer:start(
		config.values.lint_debounce_ms,
		0,
		vim.schedule_wrap(function()
			if M.timers[project.root] == timer then
				M.timers[project.root] = nil
			end
			timer:close()
			M.run({ path = path })
		end)
	)
end

function M.clear(path)
	local project = project_mod.find(path)
	if project then
		M.projects[project.root] = nil
	else
		M.projects = {}
	end
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		apply(bufnr)
	end
end

function M.get_namespace()
	return ns
end

return M
