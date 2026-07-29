local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)
local fixture = repo .. "/tests/fixtures"

local function check(value, message)
	if not value then
		error(message, 2)
	end
end

require("sqlc_nvim").setup({
	notify = false,
	lint_on_save = false,
	sqlc_cmd = repo .. "/tests/fake-sqlc",
})

local project, err = require("sqlc_nvim.project").load(fixture .. "/queries/widgets.sql")
check(project, err)
local files = require("sqlc_nvim.project").query_files(project)
check(#files == 1, "directory query expansion failed")
check(project.sql[1].package == "fixturedb", "package parsing failed")

vim.cmd.edit(vim.fn.fnameescape(files[1]))
local picked
vim.ui.select = function(items, _, callback)
	picked = items
	callback(items[1])
end
local plugin = require("sqlc_nvim")
plugin.pick_query(false)
check(#picked == 2, "query picker did not include both named queries")
check(picked[1].text:match("fixturedb"), "query picker search text omitted the package")
check(picked[1].text:match("queries/widgets.sql"), "query picker search text omitted the file")
check(picked[1].text:match("many:") or picked[2].text:match("many:"), "typed command prefix was omitted")
check(picked[1].text:match("db:fixturedb"), "typed database prefix was omitted")
check(plugin.last_package == "fixturedb", "last selected package was not remembered")

local selections = {}
vim.ui.select = function(items, _, callback)
	table.insert(selections, items)
	callback(items[1])
end
plugin.pick_scope("command")
check(#selections == 2, "command scope did not open a query picker")
local selected_command = selections[1][1].label
for _, item in ipairs(selections[2]) do
	check(item.command == selected_command, "command scope leaked a different query type")
end

plugin.set_group("type")
vim.ui.select = function(items, _, callback)
	picked = items
	callback(items[1])
end
plugin.pick_query(false)
check(picked[1].group_label ~= nil, "type grouping did not add a display heading")

local highlights = require("sqlc_nvim.highlight")
highlights.attach(0)
local marks = vim.api.nvim_buf_get_extmarks(0, highlights.get_namespace(), 0, -1, {})
check(#marks == 6, "sqlc directives did not receive three highlights each")

vim.env.SQLC_NVIM_FAKE_PASS = "0"
local lint = require("sqlc_nvim.lint")
lint.run({ path = files[1] })
check(
	vim.wait(3000, function()
		local state = lint.projects[project.root]
		return state and state.code == 1
	end),
	"failed vet run timed out"
)
check(#vim.diagnostic.get(0, { namespace = lint.get_namespace() }) == 1, "diagnostic was not applied")

vim.env.SQLC_NVIM_FAKE_PASS = "1"
lint.run({ path = files[1] })
check(
	vim.wait(3000, function()
		local state = lint.projects[project.root]
		return state and state.code == 0
	end),
	"passing vet run timed out"
)
check(#vim.diagnostic.get(0, { namespace = lint.get_namespace() }) == 0, "stale diagnostic was not cleared")

print("sqlc.nvim headless: config, discovery, diagnostics refresh passed")
