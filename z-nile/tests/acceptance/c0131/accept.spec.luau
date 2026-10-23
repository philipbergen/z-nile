--!strict
-- c0131 AC1: the ref guard (z-nile/lib/git-hooks/reference-transaction since c0114) accepts an empty ref transaction (a
-- fetch with nothing new) in a protected repository from a check.sh flow, and refuses everything it refused
-- before: an empty transaction during a spec run, any update outside refs/remotes/, and a deleted ref. The hook
-- is driven directly, as git calls it, in a fixture repository under .cache that the environment names as
-- protected (PICKMAN_FENCE_REAL_GIT), so nothing outside the fixture is involved.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: the spec runs from z-nile/, its home; its fixtures go in its home's .cache
local home = (string.gsub(process.cwd, "/+$", ""))
local hook = `{root}/z-nile/lib/git-hooks/reference-transaction` -- c0114: the guards moved
-- c0120 override: the spec runs from z-nile/, its home; its runner copy has the homes layout
local base = `{home}/.cache/c0131-accept`
local ZERO = string.rep("0", 40)
local ONE = string.rep("1", 40)
local TWO = string.rep("2", 40)

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local common = ""
local function setUp()
	if common ~= "" then
		return
	end
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	local r = process.exec("git", { "init", "-q", base })
	assert(r.ok, r.stderr)
	common = trim(process.exec("git", { "rev-parse", "--path-format=absolute", "--git-common-dir" }, {
		cwd = base,
	}).stdout)
end

-- Runs the hook in the fixture as git would at `phase`, with `lines` on stdin; `specs` marks a spec run.
local function guard(phase: string, lines: string, specs: boolean): { ok: boolean, stderr: string }
	setUp()
	local r = process.exec(hook, { phase }, {
		cwd = base,
		stdio = { stdin = lines },
		env = { PICKMAN_FENCE_REAL_GIT = common, PICKMAN_FENCE_SPECS = if specs then "1" else "" },
	})
	return { ok = r.ok, stderr = r.stderr }
end

return t.spec("c0131 the ref guard accepts a fetch with nothing new", function(it)
	it("AC1: an empty transaction from a check.sh flow is accepted in every phase", function()
		local seen = {}
		for _, phase in { "preparing", "prepared", "committed" } do
			table.insert(seen, `{phase} {guard(phase, "", false).ok}`)
		end
		t.expect(seen).toEqual({ "preparing true", "prepared true", "committed true" })
	end)

	it("AC1: a fetch that creates or moves a remote-tracking ref is still accepted", function()
		t.expect(guard("prepared", `{ZERO} {ONE} refs/remotes/origin/x\n`, false).ok).toBe(true)
		t.expect(guard("prepared", `{ONE} {TWO} refs/remotes/origin/x\n`, false).ok).toBe(true)
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
