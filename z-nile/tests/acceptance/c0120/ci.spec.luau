--!strict
-- c0120 AC12: CI follows the homes. A push touching only a project root (pickman/.tracker, z-nile/.tracker) or the
-- counter skips the deploy (c0172: deploy.yml carries the ignore list). deploy-beta builds a project's "$path"s
-- relative to the project file's own folder, and its step runs from pickman/. These specs run from z-nile/: the
-- repository is read from its top. Fixtures under .cache/c0120-ci.
local deploylist = require("@tests/lib/deploylist")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local wf = serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/deploy.yml`)) :: any

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function step(job: string, needle: string): any
	for _, s in wf.jobs[job].steps do
		if type(s.run) == "string" and has(s.run, needle) then
			return s
		end
	end
	error(`no {job} step runs {needle}`)
end

return t.spec("c0120 CI follows the homes", function(it)
	it("pushes touching only a project root or the counter skip the gate; tracker/ is not ignored", function()
		t.expect(wf["on"].push["paths-ignore"]).toEqual(deploylist.ignored(TOP)) -- c0183 override: every registered root, then the counter
	end)

	it("the deploy job publishes from pickman/, and sets up from the root", function()
		t.expect(step("deploy", "lune run scripts/deploy-beta")["working-directory"]).toBe("pickman")
		t.expect(step("deploy", "z-nile/setup.sh --tools")["working-directory"]).toBe(nil)
	end)

	it("deploy-beta builds a project's paths relative to the project file's folder", function()
		local text = fs.readFile(`{TOP}/pickman/scripts/deploy-beta.luau`)
		t.expect(has(text, 'local dir = string.match(source, "^(.*)/[^/]+$") or root')).toBe(true)
		t.expect(has(text, "pcall(Beta.project, fs.readFile(source), dir, target.attributes)")).toBe(true)
	end)
end)
