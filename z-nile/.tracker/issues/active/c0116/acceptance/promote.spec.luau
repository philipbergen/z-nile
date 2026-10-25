--!strict
-- c0116 AC7 (review 001 F4): `promote-check <issue>` takes an issue by itself: it copies that issue's own acceptance
-- specs into its project's tests/acceptance/<id>, says how many (`copied <n> acceptance specs`), type-checks and runs
-- the meta spec, and removes the copies whatever the result; a spec that breaks the type check fails it. Run in a
-- clone of this checkout under .cache/c0116-promote (its tooling overlaid from the working tree, its tracker emptied),
-- never in the real checkout.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ACC = "tests/" .. "acceptance/" -- in two parts, so a compaction never rewrites this spec's own data
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local GOOD = table.concat({
	"--!strict",
	`local t = {REQ}("@tests/lib/t")`,
	'return t.spec("good", function(it)',
	'\tit("passes", function()',
	"\t\tt.expect(1).toBe(1)",
	"\tend)",
	"end)",
	"",
}, "\n")
local BAD = table.concat({
	"--!strict",
	`local t = {REQ}("@tests/lib/t")`,
	'local n: number = "not a number"',
	'return t.spec("bad", function(it)',
	'\tit("never type-checks", function()',
	"\t\tt.expect(n).toBe(n)",
	"\tend)",
	"end)",
	"",
}, "\n")
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "c0116-promote",
	GIT_AUTHOR_EMAIL = "c0116-promote@example.invalid",
	GIT_COMMITTER_NAME = "c0116-promote",
	GIT_COMMITTER_EMAIL = "c0116-promote@example.invalid",
}

type Result = { ok: boolean, code: number, stdout: string, stderr: string }
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- the fixture lives in this home's .cache (z-nile/.cache since c0120), the only place a spec may write
local base = `{fixture.physical(".") :: string}/.cache/c0116-promote`
local work = `{base}/work`

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{work}/{parent}`)
	end
	fs.writeFile(`{work}/{path}`, text)
end
local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local function promote(id: string): Result
	return fixture.exec(work, "bash", { "scripts/tracker.sh", "promote-check", id }, { env = ID })
end

return t.spec("c0116 promote-check takes an issue's own acceptance specs", function(it)
	it("sets up a clone with two prepared z-nile issues, one spec each", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		must(fixture.exec(work, "git", { "remote", "remove", "origin" }), "remote remove")
		-- the tooling as this checkout has it, committed or not
		local args = { "ls-files", "-co", "--exclude-standard" }
		for _, p in engine.PATHSPECS do
			table.insert(args, p)
		end
		for path in string.gmatch(must(process.exec("git", args, { cwd = root }), "ls-files"), "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		engine.empty(work)
		write("z-nile/.tracker/issues/c0010/c0010.md", issue("c0010"))
		write("z-nile/.tracker/issues/c0010/acceptance/good.spec.luau", GOOD)
		write("z-nile/.tracker/issues/c0020/c0020.md", issue("c0020"))
		write("z-nile/.tracker/issues/c0020/acceptance/bad.spec.luau", BAD)
		must(fixture.exec(work, "git", { "add", "-A" }, { env = ID }), "add")
		must(
			fixture.exec(work, "git", { "commit", "-qm", "two issues", "--allow-empty" }, { env = ID }),
			"commit"
		)
	end)

	it("copies the issue's one spec, checks it, and removes the copy", function()
		local r = promote("c0010")
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(string.find(r.stdout, "\ncopied 1 acceptance specs\n", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "promote-check OK", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{work}/z-nile/{ACC}c0010`)).toBe(false) -- z-nile's home is z-nile/ (c0120)
	end)

	it("fails on an issue spec that breaks the type check, and still removes the copy", function()
		local r = promote("c0020")
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout, "\ncopied 1 acceptance specs\n", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{work}/z-nile/{ACC}c0020`)).toBe(false)
	end)
end)
