--!strict
-- c0120 AC4: the one spec runner (z-nile/tests/run.luau) runs from a project's home: `lune run tests/run` in pickman/
-- (pickman/tests/run.luau requires z-nile's) collects pickman's specs only, loads a spec by a path relative to the home
-- or an absolute one, and runs it with the home as its working directory, so its `.cache/...` fixtures are the home's
-- and its aliases are pickman/.luaurc's (`@tests` is pickman/tests, `@logic` pickman's Logic), while aliases
-- pickman/.luaurc does not name come from the root's, and the compaction map is the checkout's. From z-nile/ it runs
-- z-nile's specs only. From the repository root, which belongs to no project, it refuses (decided with the user,
-- 2026-10-21: "z-nile/ is its home").
-- Fixture under .cache/c0120-runner (this home's .cache): a copy of the runner, its harness and the guards, with two
-- homes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the checkout's top (the tooling is copied from there) and this home's .cache (these specs run from z-nile/)
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-runner`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	local parent = string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string
	fs.writeDir(parent)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{base}/{rel}` }).ok).toBe(true)
end
local function runIn(dir: string, args: { string }): (boolean, string)
	local argv = { "run", "tests/run", "--", "--jobs", "1" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = dir })
	return r.ok, r.stdout .. r.stderr
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- a pickman spec: where it runs, which aliases it sees, and where a relative .cache path lands
local PICKMAN_SPEC = table.concat({
	"--!strict",
	`local fs = {R}("@lune/fs")`,
	`local process = {R}("@lune/process")`,
	`local t = {R}("@tests/lib/t")`,
	`local probe = {R}("@logic/Probe")`,
	`local only = {R}("@tests/lib/only")`,
	`local shared = {R}("@shared/Shared")`,
	`local inherited = {R}("@znile/inherited")`,
	`local renamed = {R}("@tests/lib/renamed")`,
	'return t.spec("pickman home", function(it)',
	'\tit("runs from pickman/ with its own aliases", function()',
	'\t\tt.expect(string.match(process.cwd, "/pickman/?$") ~= nil).toBe(true)',
	'\t\tt.expect(probe.who).toBe("pickman logic")',
	'\t\tt.expect(only.who).toBe("pickman tests lib")',
	'\t\tt.expect(shared.who).toBe("pickman shared")',
	'\t\tt.expect(inherited.who).toBe("root z-nile")',
	-- the compaction map is the checkout's, found from the home too
	'\t\tt.expect(renamed.id("f0001")).toBe("f0002")',
	'\t\tfs.writeDir(".cache/c0120-runner-probe")',
	'\t\tfs.writeFile(".cache/c0120-runner-probe/written", "x")',
	"\tend)",
	"end)",
	"",
}, "\n")
local ZNILE_SPEC = table.concat({
	"--!strict",
	`local process = {R}("@lune/process")`,
	`local t = {R}("@tests/lib/t")`,
	'return t.spec("z-nile home", function(it)',
	'\tit("runs from z-nile/ and does not see pickman/tests/lib", function()',
	'\t\tt.expect(string.match(process.cwd, "/c0120%-runner/z%-nile/?$") ~= nil).toBe(true)',
	`\t\tt.expect((pcall({R}, "@tests/lib/only"))).toBe(false)`,
	"\tend)",
	"end)",
	"",
}, "\n")

return t.spec("c0120 the runner runs from a project's home", function(it)
	it("sets up a copy of the runner with a root and a pickman home", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		for _, rel in
			{
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
				"z-nile/lib",
				"z-nile/.luaurc",
				".luaurc",
				"pickman/tests/run.luau",
				"pickman/.luaurc",
			}
		do
			copy(rel)
		end
		copy("pickman/tests/lib/t.luau")
		copy("pickman/tests/lib/renamed.luau")
		write("z-nile/compaction.txt", "# a map at the checkout's root\nf0001 f0002\n")
		write("pickman/src/shared/Logic/Probe/init.luau", '--!strict\nreturn { who = "pickman logic" }\n')
		write("pickman/src/shared/Shared.luau", '--!strict\nreturn { who = "pickman shared" }\n')
		write("pickman/tests/lib/only.luau", '--!strict\nreturn { who = "pickman tests lib" }\n')
		write("z-nile/inherited.luau", '--!strict\nreturn { who = "root z-nile" }\n')
		write("pickman/tests/unit/Probe/where.spec.luau", PICKMAN_SPEC)
		write("z-nile/tests/tooling/home.spec.luau", ZNILE_SPEC)
	end)

	it("from pickman/ it collects pickman's specs only and runs them there, with pickman's aliases", function()
		local ok, out = runIn(`{base}/pickman`, {})
		t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
		t.expect(ok).toBe(true)
		-- the relative .cache path landed in the home's .cache
		t.expect(fs.isFile(`{base}/pickman/.cache/c0120-runner-probe/written`)).toBe(true)
		t.expect(fs.isDir(`{base}/.cache/c0120-runner-probe`)).toBe(false)
	end)

	it("from z-nile/ it collects z-nile's specs only", function()
		local ok, out = runIn(`{base}/z-nile`, {})
		t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
		t.expect(ok).toBe(true)
	end)

	it("from the repository root, which is no project's home, it refuses", function()
		write("tests/stray.spec.luau", ZNILE_SPEC)
		local r = process.exec("lune", { "run", "z-nile/tests/run" }, { cwd = base })
		local ok, out = r.ok, r.stdout .. r.stderr
		fs.removeDir(`{base}/tests`)
		t.expect(ok).toBe(false)
		t.expect(has(out, "is no project's home")).toBe(true)
		t.expect(has(out, "passed")).toBe(false)
	end)

	it("a spec named relative to the home, or by its absolute path, loads from the home", function()
		local ok, out = runIn(`{base}/pickman`, { "tests/unit/Probe/where.spec.luau" })
		t.expect(ok).toBe(true)
		t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
		local okAbs, outAbs = runIn(`{base}/pickman`, { `{base}/pickman/tests/unit/Probe/where.spec.luau` })
		t.expect(okAbs).toBe(true)
		t.expect(has(outAbs, "1 passed, 0 failed, 1 spec files")).toBe(true)
	end)

	it("a root-relative path is not a pickman spec: from the home it names nothing", function()
		local ok, out = runIn(`{base}/pickman`, { "pickman/tests/unit/Probe/where.spec.luau" })
		t.expect(ok).toBe(false)
		t.expect(has(out, "could not load spec")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
