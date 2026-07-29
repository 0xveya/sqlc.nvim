local M = {}
local uv = vim.uv or vim.loop

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function is_file(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "file"
end

local function strip(value)
	value = value:gsub("%s+#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local quote = value:sub(1, 1)
	if (quote == '"' or quote == "'") and value:sub(-1) == quote then
		value = value:sub(2, -2)
	end
	return value
end

function M.find(start)
	start = start or vim.api.nvim_buf_get_name(0)
	if start == "" then
		start = uv.cwd()
	end
	local names = require("sqlc_nvim.config").values.config_files
	local root = vim.fs.root(start, names)
	if not root then
		return nil, "No sqlc config found above " .. start
	end
	for _, name in ipairs(names) do
		local path = vim.fs.joinpath(root, name)
		if is_file(path) then
			return { root = normalize(root), config = normalize(path) }
		end
	end
	return nil, "No sqlc config found"
end

local function json_entries(path)
	local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(value) ~= "table" then
		return nil, "Invalid JSON in " .. path
	end
	return value.sql or {}
end

-- sqlc's relevant YAML shape is deliberately small. Parsing it here avoids
-- making query navigation depend on yq, while sqlc remains the config validator.
local function yaml_entries(path)
	local entries, current = {}, nil
	local in_sql, in_queries, in_go = false, false, false
	local sql_indent, queries_indent, go_indent = -1, -1, -1

	for _, raw in ipairs(vim.fn.readfile(path)) do
		local indent = #(raw:match("^%s*") or "")
		local text = raw:gsub("^%s+", "")
		if text:match("^sql:%s*$") then
			in_sql, sql_indent = true, indent
		elseif in_sql and indent <= sql_indent and text:match("^[%w_-]+:") then
			in_sql, in_queries, in_go = false, false, false
		elseif in_sql then
			if indent == sql_indent + 2 and text:match("^-%s+[%w_-]+:") then
				current = { queries = {} }
				table.insert(entries, current)
				in_queries, in_go = false, false
				local engine = text:match("^%-%s*engine:%s*(.+)$")
				if engine then
					current.engine = strip(engine)
				end
			elseif current then
				local engine = text:match("^%-?%s*engine:%s*(.+)$")
				if engine then
					current.engine = strip(engine)
				end
				local inline_queries = text:match("^queries:%s*(.+)$")
				if text:match("^queries:%s*$") then
					in_queries, queries_indent, in_go = true, indent, false
				elseif inline_queries then
					inline_queries = strip(inline_queries)
					if inline_queries:match("^%[.*%]$") then
						for value in inline_queries:sub(2, -2):gmatch("[^,]+") do
							table.insert(current.queries, strip(value))
						end
					else
						table.insert(current.queries, inline_queries)
					end
					in_queries = false
				elseif in_queries and indent > queries_indent and text:match("^-%s+") then
					table.insert(current.queries, strip(text:gsub("^-%s+", "", 1)))
				elseif indent <= queries_indent then
					in_queries = false
				end

				if text:match("^go:%s*$") then
					in_go, go_indent = true, indent
				elseif in_go and indent <= go_indent then
					in_go = false
				end
				if in_go then
					local package = text:match("^package:%s*(.+)$")
					if package then
						current.package = strip(package)
					end
				end
			end
		end
	end
	return entries
end

function M.load(start)
	local project, err = M.find(start)
	if not project then
		return nil, err
	end
	local entries, parse_err
	if project.config:match("%.json$") then
		entries, parse_err = json_entries(project.config)
	else
		entries, parse_err = yaml_entries(project.config)
	end
	if not entries then
		return nil, parse_err
	end
	project.sql = entries
	return project
end

local function has_magic(path)
	return path:find("[%*%?%[]") ~= nil
end

function M.query_files(project)
	local result, seen = {}, {}
	local function add(path)
		path = normalize(path)
		if is_file(path) and path:match("%.sql$") and not seen[path] then
			seen[path] = true
			table.insert(result, path)
		end
	end

	for index, entry in ipairs(project.sql or {}) do
		entry.package = entry.package or ("database " .. index)
		entry.files = {}
		for _, configured in ipairs(entry.queries or {}) do
			local path = vim.fs.joinpath(project.root, configured)
			local stat = uv.fs_stat(path)
			local files = {}
			if stat and stat.type == "directory" then
				files = vim.fs.find(function(name)
					return name:match("%.sql$") ~= nil
				end, { path = path, type = "file", limit = math.huge })
			elseif has_magic(configured) then
				files = vim.fn.glob(path, false, true)
			else
				files = { path }
			end
			for _, file in ipairs(files) do
				add(file)
				table.insert(entry.files, normalize(file))
			end
		end
	end
	table.sort(result)
	return result
end

function M.is_managed(project, path)
	path = normalize(path)
	M.query_files(project)
	for _, entry in ipairs(project.sql or {}) do
		for _, file in ipairs(entry.files or {}) do
			if file == path then
				return true
			end
		end
	end
	return false
end

return M
