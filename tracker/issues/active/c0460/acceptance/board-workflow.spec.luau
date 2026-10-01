--!strict
-- c0460: the board workflow builds the tracker board on pushes to main and uploads it as an Actions artifact.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local PATH = ".github/workflows/board.yml"

local function load(): any
	return serde.decode("yaml" :: any, fs.readFile(PATH))
end

local function keys(tbl: any): { string }
	local out = {}
	for k in tbl do
		table.insert(out, tostring(k))
	end
	table.sort(out)
	return out
end

local function job(wf: any): any
	local names = keys(wf.jobs)
	t.expect(#names).toBe(1)
	return wf.jobs[names[1]]
end

-- the step whose `run` text contains `needle`, with its index
local function runStep(steps: { any }, needle: string): (any?, number)
	for i, s in steps do
		if type(s.run) == "string" and string.find(s.run, needle, 1, true) then
			return s, i
		end
	end
	return nil, 0
end

local function usesStep(steps: { any }, prefix: string): (any?, number)
	for i, s in steps do
		if type(s.uses) == "string" and string.sub(s.uses, 1, #prefix) == prefix then
			return s, i
		end
	end
	return nil, 0
end

return t.spec("c0460 board workflow", function(it)
	it("runs only on pushes to main and manual dispatch", function()
		local wf = load()
		t.expect(keys(wf.on)).toEqual({ "push", "workflow_dispatch" })
		t.expect(wf.on.push.branches).toEqual({ "main" })
	end)

	it("has read-only permissions and no Pages or OIDC rights", function()
		local wf = load()
		t.expect(wf.permissions).toEqual({ contents = "read" })
		t.expect(job(wf).permissions).toBe(nil)
	end)

	it("serializes runs per ref and cancels superseded ones", function()
		local wf = load()
		t.expect(wf.concurrency.group).toBe("board-${{ github.ref }}")
		t.expect(wf.concurrency["cancel-in-progress"]).toBe(true)
	end)

	it("runs only for refs/heads/main, even when dispatched by hand", function()
		local j = job(load())
		t.expect(j["if"]).toBe("github.ref == 'refs/heads/main'")
	end)

	it("runs on ubuntu-latest with no step conditions and no continue-on-error", function()
		local j = job(load())
		t.expect(j["runs-on"]).toBe("ubuntu-latest")
		t.expect(j["continue-on-error"]).toBe(nil)
		for _, step in j.steps do
			t.expect(step["if"]).toBe(nil)
			t.expect(step["continue-on-error"]).toBe(nil)
		end
	end)

	it("bootstraps with setup.sh --tools, and only the tools", function()
		local steps = job(load()).steps
		local setup = runStep(steps, "scripts/setup.sh")
		t.expect(setup).toBeTruthy()
		t.expect(setup.run).toBe("scripts/setup.sh --tools")
		-- without the token setup.sh dies on CI ("GH_TOKEN missing or invalid")
		t.expect(setup.env.GH_TOKEN).toBe("${{ github.token }}")
		t.expect(keys(setup.env)).toEqual({ "GH_TOKEN" })
	end)

	it("builds the board after setup and uploads exactly that file after the build", function()
		local steps = job(load()).steps
		local _, setupAt = runStep(steps, "scripts/setup.sh --tools")
		local build, buildAt = runStep(steps, "scripts/tracker.sh board --out ")
		local upload, uploadAt = usesStep(steps, "actions/upload-artifact@v4")
		t.expect(build).toBeTruthy()
		t.expect(upload).toBeTruthy()
		t.expect(setupAt < buildAt).toBe(true)
		t.expect(buildAt < uploadAt).toBe(true)
		local out = string.match((build :: any).run, "scripts/tracker%.sh board %-%-out (%S+)")
		t.expect(out).toBe("dist/board.html")
		t.expect(upload.with.path).toBe(out)
		t.expect(upload.with.name).toBe("tracker-board")
		t.expect(upload.with["if-no-files-found"]).toBe("error")
	end)

	it("has exactly four steps: checkout, setup, build, upload, with their exact inputs", function()
		local steps = job(load()).steps
		t.expect(#steps).toBe(4)
		t.expect(steps[1]).toEqual({ uses = "actions/checkout@v4" })
		t.expect(steps[3]).toEqual({ run = "scripts/tracker.sh board --out dist/board.html" })
		t.expect(steps[4].uses).toBe("actions/upload-artifact@v4")
		t.expect(steps[4].with).toEqual({
			name = "tracker-board",
			path = "dist/board.html",
			["retention-days"] = 30,
			["if-no-files-found"] = "error",
		})
	end)

	it("checks the repository out before anything else", function()
		local steps = job(load()).steps
		t.expect(steps[1].uses).toBe("actions/checkout@v4")
	end)
end)
