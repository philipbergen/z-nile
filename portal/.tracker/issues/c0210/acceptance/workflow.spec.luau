--!strict
-- c0210 AC6: deploy.yml runs the publish from portal/ and hands it every variable the manifest names, each from the
-- repository's variables, so a place is published from the moment its variable is set, with no edit here.
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local wf = serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/deploy.yml`)) :: any

local function publishStep(): any
	for _, s in wf.jobs.deploy.steps do
		if type(s.run) == "string" and string.find(s.run, "scripts/deploy-beta", 1, true) then
			return s
		end
	end
	error("no step runs scripts/deploy-beta")
end

return t.spec("c0210 deploy.yml publishes every place of the manifest", function(it)
	it("the publish runs lune run scripts/deploy-beta from portal/", function()
		local step = publishStep()
		t.expect(step.run).toBe("lune run scripts/deploy-beta")
		t.expect(step["working-directory"]).toBe("portal")
	end)

	it(
		"every variable of the manifest is passed from the repository's variables, and the key from its secret",
		function()
			local m = Experience.parse(fs.readFile("experience.json")) :: Experience.Manifest
			local env = publishStep().env
			local expected: { [string]: string } = {
				ROBLOX_API_KEY = "${{ secrets.ROBLOX_API_KEY }}",
				ROBLOX_BETA_UNIVERSE_ID = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}",
			}
			for _, place in m.places do
				for _, var in place.env do
					expected[var] = `$\{\{ vars.{var} \}\}`
				end
			end
			t.expect(env).toEqual(expected)
		end
	)

	it("the pull request's comment still names Pickman's version", function()
		local found = false
		for _, s in wf.jobs.deploy.steps do
			if
				type(s["if"]) == "string" and string.find(s["if"], "steps.deploy.outputs.version", 1, true)
			then
				found = s.env.VERSION == "${{ steps.deploy.outputs.version }}"
			end
		end
		t.expect(found).toBe(true)
	end)
end)
