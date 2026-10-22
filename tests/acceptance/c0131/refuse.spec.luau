--!strict
-- c0131 AC2: the ref guard (scripts/lib/git-hooks/reference-transaction) accepts an empty ref transaction (a
-- fetch with nothing new) in a protected repository from a check.sh flow, and refuses everything it refused
-- before: an empty transaction during a spec run, any update outside refs/remotes/, and a deleted ref. The hook
-- is driven directly, as git calls it, in a fixture repository under .cache that the environment names as
-- protected (PICKMAN_FENCE_REAL_GIT), so nothing outside the fixture is involved.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local hook = `{root}/scripts/lib/git-hooks/reference-transaction`
local base = `{root}/.cache/c0131-refuse`
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

return t.spec("c0131 the ref guard still refuses the rest", function(it)
	it("AC2: an empty transaction during a spec run is still refused", function()
		local r = guard("prepared", "", true)
		t.expect({ ok = r.ok, said = string.find(r.stderr, "refused", 1, true) ~= nil }).toEqual({
			ok = false,
			said = true,
		})
	end)

	it(
		"AC2: a branch update, a deleted remote-tracking ref and any update during a spec run are still refused",
		function()
			t.expect(guard("prepared", `{ONE} {TWO} refs/heads/main\n`, false).ok).toBe(false)
			t.expect(guard("prepared", `{ONE} {ZERO} refs/remotes/origin/x\n`, false).ok).toBe(false)
			t.expect(guard("prepared", `{ZERO} {ONE} refs/remotes/origin/x\n`, true).ok).toBe(false)
			t.expect(
				guard("prepared", `{ZERO} {ONE} refs/remotes/origin/x\n{ONE} {TWO} refs/heads/main\n`, false).ok
			)
				.toBe(false)
		end
	)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
