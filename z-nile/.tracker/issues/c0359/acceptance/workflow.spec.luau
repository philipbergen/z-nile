--!strict
-- c0359 AC1: the `static` check GitHub runs on every pull request (.github/workflows/static.yml): the gate's format and
-- lint stages (`z-nile/check.sh --lint`) and nothing else, on every pull request event whatever it changes, reading no
-- secret. Reads files only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local WORKFLOW = `{TOP}/.github/workflows/static.yml`

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function keys(tbl: any): { string }
	local out: { string } = {}
	for k in tbl do
		table.insert(out, tostring(k))
	end
	table.sort(out)
	return out
end
local function read(path: string): string
	if not fs.isFile(path) then
		error(`no {path} (c0359 creates it)`)
	end
	return fs.readFile(path)
end
local function load(): any
	return serde.decode("yaml", read(WORKFLOW))
end

return t.spec("c0359 the static workflow", function(it)
	it("static.yml is one job, static, on every pull request event it can see, with no filter", function()
		local wf = load()
		t.expect(wf.name).toBe("static")
		-- YAML 1.1 reads a bare `on` key as true; GitHub reads it as `on`: accept either spelling of the one key
		local on = wf.on or wf[true]
		t.expect(type(on)).toBe("table")
		t.expect(keys(on)).toEqual({ "pull_request" })
		t.expect(keys(on.pull_request)).toEqual({ "types" })
		local types = table.clone(on.pull_request.types)
		table.sort(types)
		t.expect(types).toEqual({ "opened", "ready_for_review", "reopened", "synchronize" })
		t.expect(keys(wf.jobs)).toEqual({ "static" })
		local job = wf.jobs.static
		-- the check's name is the job's id: no name to rename it, no condition to skip it, nothing it waits for
		t.expect(job.name).toBe(nil)
		t.expect(job["if"]).toBe(nil)
		t.expect(job.needs).toBe(nil)
		t.expect(job["runs-on"]).toBe("ubuntu-latest")
		t.expect(type(job["timeout-minutes"]) == "number" and job["timeout-minutes"] <= 20).toBe(true)
	end)

	it(
		"its steps check out, install the pinned tools and run z-nile/check.sh --lint, and nothing else",
		function()
			local job = load().jobs.static
			t.expect(#job.steps).toBe(3)
			t.expect(job.steps[1].uses).toBe("actions/checkout@v4")
			t.expect(job.steps[1].run).toBe(nil)
			t.expect(job.steps[2].run).toBe("z-nile/setup.sh --tools")
			t.expect(job.steps[2].env.GH_TOKEN).toBe("${{ github.token }}")
			t.expect(job.steps[3].run).toBe("z-nile/check.sh --lint")
			t.expect(job.steps[3].uses).toBe(nil)
		end
	)

	it("it reads no secret and can only read the repository", function()
		local text = read(WORKFLOW)
		t.expect(has(text, "secrets.")).toBe(false)
		t.expect(has(text, "pull_request_target")).toBe(false)
		local wf = load()
		t.expect(wf.permissions).toEqual({ contents = "read" })
		t.expect(wf.jobs.static.permissions).toBe(nil)
	end)
end)
