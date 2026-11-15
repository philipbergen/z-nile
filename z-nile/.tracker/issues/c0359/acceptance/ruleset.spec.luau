--!strict
-- c0359 AC2: the ruleset that requires the `static` check on main (.github/rulesets/static.json, which the user posts
-- with `gh api`: SETUP.md). It requires that check, from GitHub Actions, on the default branch, not strict, with the
-- repository admin role as its one bypass (the tracker's own pushes to main: Guess G1 in the issue), and its context is
-- the job static.yml reports. Reads files only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local WORKFLOW = `{TOP}/.github/workflows/static.yml`
local RULESET = `{TOP}/.github/rulesets/static.json`
-- the GitHub Actions app: the app id of every check run this repository's workflows report (E3)
local ACTIONS_APP = 15368

local function read(path: string): string
	if not fs.isFile(path) then
		error(`no {path} (c0359 creates it)`)
	end
	return fs.readFile(path)
end
local function load(): any
	return serde.decode("yaml", read(WORKFLOW))
end

return t.spec("c0359 the static ruleset", function(it)
	it(
		"the ruleset requires that check from GitHub Actions on the default branch, with one admin bypass",
		function()
			local rs = serde.decode("json", read(RULESET))
			t.expect(rs).toEqual({
				name = "static",
				target = "branch",
				enforcement = "active",
				conditions = { ref_name = { include = { "~DEFAULT_BRANCH" }, exclude = {} } },
				bypass_actors = { { actor_id = 5, actor_type = "RepositoryRole", bypass_mode = "always" } },
				rules = {
					{
						type = "required_status_checks",
						parameters = {
							required_status_checks = { { context = "static", integration_id = ACTIONS_APP } },
							strict_required_status_checks_policy = false,
							do_not_enforce_on_create = false,
						},
					},
				},
			})
		end
	)

	it(
		"the required context is the workflow's job, so the check it names is the one static.yml reports",
		function()
			local rs = serde.decode("json", read(RULESET))
			local context = rs.rules[1].parameters.required_status_checks[1].context
			t.expect(load().jobs[context] ~= nil).toBe(true)
			t.expect(load().name).toBe(context)
		end
	)
end)
