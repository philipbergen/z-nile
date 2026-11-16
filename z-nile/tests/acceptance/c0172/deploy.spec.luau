--!strict
-- c0172 AC1: the only GitHub Actions workflow publishes the place. It does not run the gate or the runtime tests.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function load(): any
	return serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/deploy.yml`))
end

local function runsOf(job: any): string
	local runs = ""
	for _, step in job.steps do
		if type(step.run) == "string" then
			runs ..= step.run .. "\n"
		end
	end
	return runs
end

local function stepWith(job: any, needle: string): any
	for _, step in job.steps do
		if type(step.run) == "string" and has(step.run, needle) then
			return step
		end
	end
	return nil
end

return t.spec("c0172 deploy workflow", function(it)
	it("the only workflow file is deploy.yml", function()
		local names = fs.readDir(`{TOP}/.github/workflows`)
		table.sort(names)
		t.expect(names).toEqual({ "deploy.yml" })
	end)

	it("the gate workflow, the board workflow and ci-verify are absent", function()
		for _, rel in
			{
				".github/workflows/check.yml",
				".github/workflows/board.yml",
				"z-nile/ci-verify.sh",
				"scripts/ci-verify.sh",
			}
		do
			t.expect(fs.isFile(`{TOP}/{rel}`)).toBe(false)
		end
	end)

	it("one job, deploy, with no needs and no gate", function()
		local wf = load()
		local names = {}
		for name in wf.jobs do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "deploy" })
		t.expect(wf.jobs.deploy.needs).toBe(nil)
		t.expect(wf.jobs.gate).toBe(nil)
		t.expect(wf.jobs.beta).toBe(nil)
	end)

	it("no step runs the gate, the runtime tests or a raft's acceptance specs", function()
		local wf = load()
		local runs = runsOf(wf.jobs.deploy)
		t.expect(has(runs, "check.sh")).toBe(false)
		t.expect(has(runs, "runtime-test")).toBe(false)
		t.expect(has(runs, "zn members")).toBe(false)
		t.expect(has(runs, "acceptance")).toBe(false)
	end)

	it("the publish step carries the four Roblox settings", function()
		local wf = load()
		local publish = stepWith(wf.jobs.deploy, "lune run scripts/deploy-beta")
		t.expect(publish ~= nil).toBe(true)
		for _, key in
			{
				"ROBLOX_API_KEY",
				"ROBLOX_BETA_UNIVERSE_ID",
				"ROBLOX_BETA_PLACE_ID",
				"ROBLOX_BETA_GAME_PLACE_ID",
			}
		do
			t.expect(publish.env[key] ~= nil).toBe(true)
		end
	end)

	it("a draft or a fork does not deploy, and neither does a push or a dispatch", function()
		local wf = load()
		local cond = string.gsub(wf.jobs.deploy["if"] or "", "%s+", " ")
		t.expect(cond).toBe(
			"github.event_name == 'pull_request' && github.event.pull_request.draft == false && github.event.pull_request.head.repo.full_name == github.repository"
		)
	end)

	it("the version comment runs only for a pull request", function()
		local wf = load()
		local comment = stepWith(wf.jobs.deploy, "gh pr comment")
		t.expect(comment ~= nil).toBe(true)
		local cond = string.gsub(if type(comment["if"]) == "string" then comment["if"] else "", "%s+", " ")
		t.expect(cond).toBe("steps.deploy.outputs.version != '' && github.event_name == 'pull_request'")
	end)

	it("one publish at a time, and a running one is not cancelled", function()
		local wf = load()
		local conc = wf.jobs.deploy.concurrency
		t.expect(conc.group).toBe("beta-deploy")
		t.expect(conc["cancel-in-progress"]).toBe(false)
	end)
end)
