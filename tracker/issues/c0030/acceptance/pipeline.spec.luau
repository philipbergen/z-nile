--!strict
-- c0030 AC5: the runtime tests run in CI against the version the deploy just published, and the people who
-- set the repo up can find out how the Beta publishing is configured.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local workflow = fs.readFile(".github/workflows/check.yml")
local setup = fs.readFile("SETUP.md")
local testing = fs.readFile(".claude/skills/testing/SKILL.md")

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0030 runtime tests in the pipeline and docs", function(it)
	local from = string.find(workflow, "\n  beta:\n", 1, true)
	local beta = if from then string.sub(workflow, from) else ""

	it("the beta job runs the runtime tests after the deploy, on the published version", function()
		t.expect(has(beta, "lune run scripts/runtime-test")).toBe(true)
		local deploy = string.find(beta, "lune run scripts/deploy-beta", 1, true) :: number
		local runtime = string.find(beta, "lune run scripts/runtime-test", 1, true) :: number
		t.expect(deploy < runtime).toBe(true)
		t.expect(has(beta, "VERSION: ${{ steps.deploy.outputs.version }}")).toBe(true)
		t.expect(has(beta, 'scripts/runtime-test -- "$VERSION"')).toBe(true)
	end)

	it("the runtime step only runs when something was published", function()
		local runtime = string.find(beta, "lune run scripts/runtime-test", 1, true) :: number
		local before = string.sub(beta, 1, runtime)
		-- the nearest `if:` above the command is the publish guard
		local guard: number? = nil
		local pos = 1
		while true do
			local s, e = string.find(before, "if: steps.deploy.outputs.version != ''", pos, true)
			if not s then
				break
			end
			guard = s
			pos = (e :: number) + 1
		end
		t.expect(guard ~= nil).toBe(true)
		t.expect(runtime - (guard :: number) < 250).toBe(true)
	end)

	it("SETUP.md names the key scope the runtime tests need, and how to run them", function()
		for _, needle in { "luau-execution-sessions", "scripts/runtime-test" } do
			t.expect(has(setup, needle)).toBe(true)
		end
	end)

	it("the testing skill lists the runtime tier and how to run it", function()
		t.expect(has(testing, "tests/runtime/")).toBe(true)
		t.expect(has(testing, "scripts/runtime-test")).toBe(true)
		t.expect(has(testing, "Open Cloud")).toBe(true)
	end)
end)
