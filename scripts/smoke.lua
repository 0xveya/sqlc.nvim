local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)

local function check(value, message)
	if not value then
		error(message, 2)
	end
end

require("sqlc_nvim").setup({ notify = false, lint_on_save = false })

local fixture = vim.env.SQLC_NVIM_FIXTURE
check(fixture and fixture ~= "", "SQLC_NVIM_FIXTURE is required")

local project, err = require("sqlc_nvim.project").load(fixture)
check(project, err)
local files = require("sqlc_nvim.project").query_files(project)
check(#files > 0, "fixture contains no managed query files")
check(require("sqlc_nvim.project").is_managed(project, files[1]), "managed-file detection failed")

local done = false
require("sqlc_nvim.lint").run({ path = files[1] })
vim.wait(10000, function()
	local state = require("sqlc_nvim.lint").projects[project.root]
	done = state ~= nil
	return done
end)
check(done, "sqlc vet timed out")
check(require("sqlc_nvim.lint").projects[project.root].code == 0, "fixture did not pass sqlc vet")

print(("sqlc.nvim smoke: %d managed files, vet passed"):format(#files))
