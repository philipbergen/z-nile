--!strict
-- c0115 AC13 and AC14's one trusted base (design review 011 F1): `experiments/trusted-base.luau` takes main's tip
-- from the remote (`git ls-remote origin refs/heads/main`), never the local refs/remotes/origin/main, and is red when
-- origin can't be read, its tip isn't local, or there is no merge-base. Fixtures under .cache/c0115-base: a clone
-- whose origin is a local bare repository.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local TOP = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- the helper, in c0115's folder wherever it is in its lifecycle
local ITEM = trim(process.exec("bash", { `{TOP}/zn`, "find", "c0115" }, { cwd = TOP }).stdout)
local HELPER = `{TOP}/{ITEM}/experiments/trusted-base`
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0115-base`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local function must(r: { ok: boolean, code: number, stdout: string, stderr: string }, what: string)
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "t" })
	git(dir, { "config", "user.email", "t@example.invalid" })
end
local function helper(dir: string): fixture.Result
	return fixture.exec(dir, "lune", { "run", HELPER, "--", "--print", dir })
end
-- `<base> empty|range`; the second line names the URL ls-remote read (design review 012 F1)
local function firstLine(out: string): string
	return trim(string.match(out, "^[^\n]*") or "")
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0115 the trusted base comes from the remote", function(it)
	it("sets up a clone whose origin is a local bare repository, with a branch one commit ahead", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		-- creating a fixture names its new path explicitly, so it needs no check (tests/lib/fixture)
		must(process.exec("git", { "init", "-q", "-b", "main", seed }), "init")
		identity(seed)
		git(seed, { "commit", "-q", "--allow-empty", "-m", "main 1" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone")
		identity(main)
		git(main, { "switch", "-q", "-c", "work" })
		git(main, { "commit", "-q", "--allow-empty", "-m", "work 1" })
		t.expect(helper(main).ok).toBe(true)
	end)

	it("an honest clone gets the merge-base and a range", function()
		local r = helper(main)
		t.expect(r.ok).toBe(true)
		t.expect(firstLine(r.stdout)).toBe(`{git(main, { "rev-parse", "origin/main" })} range`)
		t.expect(has(r.stdout, `\nfrom {origin}`)).toBe(true)
	end)

	it(
		"a forged refs/remotes/origin/main is never read: forged to HEAD, or to the branch's own commit",
		function()
			local honest = git(main, { "rev-parse", "origin/main" })
			git(main, { "update-ref", "refs/remotes/origin/main", "HEAD" })
			t.expect(firstLine(helper(main).stdout)).toBe(`{honest} range`)
			git(main, { "commit", "-q", "--allow-empty", "-m", "work 2" })
			-- forged to the first branch commit, so a ref-based base would already hold the branch's edit
			git(main, { "update-ref", "refs/remotes/origin/main", "HEAD~1" })
			t.expect(firstLine(helper(main).stdout)).toBe(`{honest} range`)
			git(main, { "update-ref", "refs/remotes/origin/main", honest })
		end
	)

	it("a remote main that isn't fetched is red, naming the fetch", function()
		git(seed, { "commit", "-q", "--allow-empty", "-m", "main 2" })
		git(seed, { "push", "-q", origin, "main" })
		local r = helper(main)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "fetch origin")).toBe(true)
		git(main, { "fetch", "-q", "origin" })
		t.expect(helper(main).ok).toBe(true)
	end)

	it("an unreachable origin is red", function()
		git(main, { "remote", "set-url", "origin", `{base}/nowhere.git` })
		local r = helper(main)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "ls-remote")).toBe(true)
		git(main, { "remote", "set-url", "origin", origin })
	end)

	it("no merge-base (an unrelated history) is red", function()
		git(main, { "switch", "-q", "--orphan", "alone" })
		git(main, { "commit", "-q", "--allow-empty", "-m", "alone" })
		local r = helper(main)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "no merge-base")).toBe(true)
		git(main, { "switch", "-q", "work" })
	end)

	it("on origin's main itself the range is empty (the landed case)", function()
		git(main, { "switch", "-q", "-C", "landed", "origin/main" })
		local r = helper(main)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, " empty")).toBe(true)
		fs.removeDir(base)
	end)
end)
