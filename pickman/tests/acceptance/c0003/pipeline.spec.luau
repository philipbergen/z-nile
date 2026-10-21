--!strict
-- c0030 AC5: the runtime tests run in CI against the version the deploy just published (checked on the
-- parsed workflow), and the docs say how the tier works.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local wf: any = serde.decode("yaml" :: "yaml", fs.readFile("../.github/workflows/check.yml"))
local beta: any = wf.jobs.beta
local setup = fs.readFile("../SETUP.md")
local testing = fs.readFile("../.claude/skills/testing/SKILL.md")
local tracker = fs.readFile("../.claude/skills/tracker/SKILL.md")

local function has(s: any, needle: string): boolean
	return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

local function index(pred: (any) -> boolean): number
	for i, step in beta.steps do
		if pred(step) then
			return i
		end
	end
	error("no such step")
end

return t.spec("c0030 runtime tests in the pipeline and docs", function(it)
	it(
		"the beta job runs the runtime tests after the deploy and the comment, on the published version",
		function()
			local deploy = index(function(s: any)
				return s.id == "deploy"
			end)
			local comment = index(function(s: any)
				return has(s.run, "gh pr comment")
			end)
			local runtime = index(function(s: any)
				return has(s.run, "runtime-test")
			end)
			t.expect(deploy < comment).toBe(true)
			t.expect(comment < runtime).toBe(true)
			local step = beta.steps[runtime]
			t.expect(runtime).toBe(5)
			-- exactly these keys and these values: a continue-on-error, a shell, a working-directory or a with
			-- on this step would make "green" mean something else
			local keys = {}
			for k in step do
				if k ~= "name" then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
			-- c0120 override: run from pickman's home, its one extra key
			t.expect(keys).toEqual({ "env", "if", "run", "working-directory" })
			t.expect(step["working-directory"]).toBe("pickman")
			t.expect(step.run).toBe('lune run scripts/runtime-test -- "$VERSION"')
			-- these four at least; c0064's workflow spec pins the whole env with the game place's variable
			for name, value in
				{
					VERSION = "${{ steps.deploy.outputs.version }}",
					ROBLOX_API_KEY = "${{ secrets.ROBLOX_API_KEY }}",
					ROBLOX_BETA_UNIVERSE_ID = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}",
					ROBLOX_BETA_PLACE_ID = "${{ vars.ROBLOX_BETA_PLACE_ID }}",
				}
			do
				t.expect(step.env[name]).toBe(value)
			end
		end
	)

	it("the runtime step runs only when something was published", function()
		local step = beta.steps[index(function(s: any)
			return has(s.run, "runtime-test")
		end)]
		t.expect(step["if"]).toBe("steps.deploy.outputs.version != ''")
	end)

	it(
		"the runtime step has the key and ids in its own env, and no other step but the deploy does",
		function()
			local env = {
				ROBLOX_API_KEY = "${{ secrets.ROBLOX_API_KEY }}",
				ROBLOX_BETA_UNIVERSE_ID = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}",
				ROBLOX_BETA_PLACE_ID = "${{ vars.ROBLOX_BETA_PLACE_ID }}",
			}
			for _, step in beta.steps do
				if has(step.run, "runtime-test") then
					for k, v in env do
						t.expect(step.env[k]).toBe(v)
					end
				elseif step.id ~= "deploy" then
					t.expect(step.env == nil or step.env.ROBLOX_API_KEY == nil).toBe(true)
				end
			end
			t.expect(beta.env).toBe(nil)
		end
	)

	it("SETUP.md names the key scope the runtime tests need, and how to run them", function()
		for _, needle in { "luau-execution-sessions", "scripts/runtime-test" } do
			t.expect(has(setup, needle)).toBe(true)
		end
	end)

	it("merging requires beta, with the rules that make it executable", function()
		local from = string.find(tracker, "## Merging", 1, true)
		t.expect(from ~= nil).toBe(true)
		local merging =
			string.sub(tracker, from :: number, (string.find(tracker, "\n## ", (from :: number) + 5, true)))
		-- each needle is a phrase only the intended rule produces
		for _, needle in
			{
				"A missing `beta` check for the head sha means keep waiting",
				"A `workflow_dispatch` run never satisfies `beta`",
				"gh pr ready --undo",
				"`beta` must be `COMPLETED` with conclusion `SUCCESS`",
				"gh run view <run-id> --json jobs",
				"a `beta` job with no steps was superseded",
				"gh run rerun <run-id> --job <job-id>",
				"60 minutes have passed since the PR became ready",
				"A `beta` job whose steps ran was timed out or cancelled by hand: red",
			}
		do
			t.expect(has(merging, needle)).toBe(true)
		end
	end)

	it("the testing skill lists the runtime tier and how to run it", function()
		t.expect(has(testing, "tests/runtime/")).toBe(true)
		t.expect(has(testing, "scripts/runtime-test")).toBe(true)
		t.expect(has(testing, "Open Cloud")).toBe(true)
	end)
end)
