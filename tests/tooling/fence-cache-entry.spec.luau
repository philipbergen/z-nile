--!strict
-- R0210 review 004 F1: the guards never delete through a symlink and never delete recursively. A checkout whose
-- .cache is not a plain folder is refused by pickman_fence and by the runner; a .cache/.git folder is refused, not
-- deleted; a .cache/.git symlink is unlinked, never followed. Every repository here is a stand-in under .cache.
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("@scripts/lib/sh")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/fence-cache-entry`

local function fresh(name: string): string
	local dir = `{base}/{name}`
	fs.writeDir(dir)
	t.expect(process.exec("git", { "init", "-q", dir }).ok).toBe(true)
	return dir
end

-- a stand-in for a real repository's .git, with a marker that must survive
local function standIn(name: string): string
	local dir = `{base}/{name}`
	fs.writeDir(`{dir}/.git`)
	fs.writeFile(`{dir}/.git/marker`, "keep")
	return dir
end

local function fence(checkout: string): Result
	return process.exec(
		"bash",
		{ "-c", 'source "$1" || exit 2; pickman_fence "$2"', "_", `{root}/scripts/lib/fence.sh`, checkout },
		{ cwd = checkout }
	)
end

return t.spec("the guards never delete through .cache", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("a checkout whose .cache is a symlink is refused, and nothing behind it changes", function()
		local fx = fresh("link-cache")
		local victim = standIn("victim-a")
		t.expect(process.exec("ln", { "-s", victim, `{fx}/.cache` }).ok).toBe(true)
		local r = fence(fx)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "not a plain folder", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{victim}/.git`)).toBe(true)
		t.expect(fs.readFile(`{victim}/.git/marker`)).toBe("keep")
	end)

	it("a .cache/.git folder is refused, not deleted", function()
		local fx = fresh("dir-sentinel")
		fs.writeDir(`{fx}/.cache/.git`)
		fs.writeFile(`{fx}/.cache/.git/commondir`, "../../somewhere")
		local r = fence(fx)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "is a folder", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(`{fx}/.cache/.git/commondir`)).toBe(true)
	end)

	it("a .cache/.git symlink is unlinked, never followed", function()
		local fx = fresh("link-sentinel")
		local victim = standIn("victim-b")
		fs.writeDir(`{fx}/.cache`)
		t.expect(process.exec("ln", { "-s", `{victim}/.git`, `{fx}/.cache/.git` }).ok).toBe(true)
		local r = fence(fx)
		if not r.ok then
			error(r.stderr)
		end
		t.expect(process.exec("test", { "-L", `{fx}/.cache/.git` }).ok).toBe(false)
		t.expect(string.find(fs.readFile(`{fx}/.cache/.git`), "pickman-fence", 1, true) ~= nil).toBe(true)
		t.expect(fs.readFile(`{victim}/.git/marker`)).toBe("keep")
	end)

	it("the runner refuses a checkout whose .cache is a symlink before doing anything", function()
		local fx = fresh("link-runner")
		local victim = standIn("victim-c")
		fs.writeDir(`{fx}/tests`)
		fs.writeDir(`{fx}/scripts/lib`)
		for _, rel in { "tests/run.luau", "scripts/lib/fence.sh" } do
			fs.writeFile(`{fx}/{rel}`, fs.readFile(`{root}/{rel}`))
		end
		process.exec("cp", { "-R", `{root}/tests/lib`, `{fx}/tests/lib` })
		fs.writeFile(`{fx}/.luaurc`, fs.readFile(`{root}/.luaurc`))
		t.expect(process.exec("ln", { "-s", victim, `{fx}/.cache` }).ok).toBe(true)
		-- nothing may be written behind the symlink, not even a lock that is removed again: its folder stays untouched
		local function stamp(): string
			local args = if process.os == "macos" then { "-f", "%Fm", victim } else { "-c", "%y", victim }
			local r = process.exec("stat", args)
			assert(r.ok and r.stdout ~= "", "stat failed")
			return r.stdout
		end
		local before = stamp()
		local r = process.exec(
			"lune",
			{ "run", "tests/run", "--" },
			{ cwd = fx, env = { PICKMAN_TEST_FENCE = "" } }
		)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "not a plain folder", 1, true) ~= nil).toBe(true)
		t.expect(fs.readFile(`{victim}/.git/marker`)).toBe("keep")
		t.expect(fs.isDir(`{victim}/tests-run.lock`)).toBe(false)
		t.expect(stamp()).toBe(before)
	end)

	it("a tracker write replaces a symlink at its path instead of writing through it", function()
		local dir = `{base}/writer`
		fs.writeDir(dir)
		local victim = `{base}/victim-d`
		fs.writeFile(victim, "keep")
		t.expect(process.exec("ln", { "-s", victim, `{dir}/tracker-focus` }).ok).toBe(true)
		sh.writeReplacing(`{dir}/tracker-focus`, "c0010")
		t.expect(process.exec("test", { "-L", `{dir}/tracker-focus` }).ok).toBe(false)
		t.expect(fs.readFile(`{dir}/tracker-focus`)).toBe("c0010")
		t.expect(fs.readFile(victim)).toBe("keep")
	end)

	it("a tracker write replaces a symlink to a directory instead of dropping a file into it", function()
		local dir = `{base}/writer-dir`
		fs.writeDir(dir)
		local victim = `{base}/victim-e`
		fs.writeDir(victim)
		fs.writeFile(`{victim}/keep`, "keep")
		t.expect(process.exec("ln", { "-s", victim, `{dir}/tracker-focus` }).ok).toBe(true)
		sh.writeReplacing(`{dir}/tracker-focus`, "c0010")
		t.expect(process.exec("test", { "-L", `{dir}/tracker-focus` }).ok).toBe(false)
		t.expect(fs.readFile(`{dir}/tracker-focus`)).toBe("c0010")
		t.expect(#fs.readDir(victim)).toBe(1)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
