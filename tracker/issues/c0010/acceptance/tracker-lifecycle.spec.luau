--!strict
-- c0010 AC1: the tracker CLI lifecycle works end to end, driven for real in a throwaway clone
-- of the committed HEAD (no remote, so start/done skip push and gh).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{root}/.cache/tracker-e2e`

local function run(cmd: string, args: { string }): Result
	return process.exec(cmd, args, { cwd = dir })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function tr(args: { string }): Result
	return run("bash", { "scripts/tracker.sh", table.unpack(args) })
end

local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end

local function read(path: string): string
	return fs.readFile(`{dir}/{path}`)
end

local function write(path: string, text: string)
	fs.writeFile(`{dir}/{path}`, text)
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(read(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'

return t.spec("tracker lifecycle", function(it)
	it("allocates ids in steps of 10 across issue types", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		must(process.exec("git", { "clone", "-q", root, dir }), "clone")
		git({ "remote", "remove", "origin" })
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		t.expect(must(tr({ "new", "issue", "f", "alpha" }), "new f"))
			.toBe("tracker/issues/f0010/f0010-alpha.md")
		t.expect(must(tr({ "new", "issue", "d", "beta" }), "new d"))
			.toBe("tracker/issues/d0020/d0020-beta.md")
		t.expect(must(tr({ "new", "issue", "f", "gamma" }), "new f"))
			.toBe("tracker/issues/f0030/f0030-gamma.md")
	end)

	it("rejects a raft that mixes types", function()
		local r = tr({ "new", "raft", "feature", "mixed", "f0010", "d0020" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "cannot contain", 1, true) ~= nil).toBe(true)
	end)

	it("renumber steps an id and rewrites references", function()
		t.expect(must(tr({ "new", "raft", "feature", "demo", "f0010", "f0030" }), "new raft"))
			.toBe("tracker/rafts/R0010/R0010-demo.md")
		must(tr({ "renumber", "f0030", "f0031" }), "renumber")
		local raftDoc = read("tracker/rafts/R0010/R0010-demo.md")
		t.expect(string.find(raftDoc, "f0031", 1, true) ~= nil).toBe(true)
		t.expect(string.find(raftDoc, "f0030", 1, true)).toBe(nil)
		t.expect(fs.isFile(`{dir}/tracker/issues/f0031/f0031-gamma.md`)).toBe(true)
	end)

	it("start refuses issues that are not design: ready", function()
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep draft" })
		local r = tr({ "start", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "design: ready", 1, true) ~= nil).toBe(true)
	end)

	it("start branches, moves items to active, and commits exactly once", function()
		for _, doc in
			{
				"tracker/issues/f0010/f0010-alpha.md",
				"tracker/issues/f0031/f0031-gamma.md",
				"tracker/rafts/R0010/R0010-demo.md",
			}
		do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"tracker/issues/f0010/f0010-alpha.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		edit(
			"tracker/issues/f0031/f0031-gamma.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/gamma`\n"
		)
		for _, p in
			{
				"tracker/issues/f0010/check.sh",
				"tracker/issues/f0031/check.sh",
				"tracker/rafts/R0010/check.sh",
			}
		do
			write(p, TRIVIAL_CHECK)
		end
		fs.writeDir(`{dir}/tracker/issues/f0010/acceptance`)
		write("tracker/issues/f0010/acceptance/alpha.spec.luau", "--!strict\nreturn nil\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		local before = tonumber(git({ "rev-list", "--count", "HEAD" })) :: number
		must(tr({ "start", "R0010" }), "start")
		t.expect(git({ "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(tonumber(git({ "rev-list", "--count", "HEAD" }))).toBe(before + 1)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: start R0010 Demo")
		t.expect(fs.isDir(`{dir}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/active/f0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/active/f0031`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/d0020`)).toBe(true)
	end)

	it("commit records spend whose lines equal the diff, split by Touched modules", function()
		fs.writeDir(`{dir}/notes/alpha`)
		fs.writeDir(`{dir}/notes/gamma`)
		write("notes/alpha/a.txt", "1\n2\n3\n4\n5\n")
		write("notes/gamma/g.txt", "1\n2\n3\n")
		must(tr({ "commit", "-m", "work", "--issue", "f0010", "--issue", "f0031", "--time", "8" }), "commit")
		local added = 0
		for line in
			string.gmatch(
				git({ "show", "--numstat", "--format=", "HEAD", "--", ".", ":(exclude)tracker" }),
				"[^\n]+"
			)
		do
			added += tonumber(string.match(line, "^(%d+)")) or 0
		end
		t.expect(added).toBe(8)
		local a = read("tracker/issues/active/f0010/spend.md")
		local g = read("tracker/issues/active/f0031/spend.md")
		t.expect(string.match(a, "totals: added=(%d+)")).toBe("5")
		t.expect(string.match(g, "totals: added=(%d+)")).toBe("3")
		t.expect(string.match(a, "minutes=([%d%.]+)")).toBe("5.0")
		t.expect(string.match(g, "minutes=([%d%.]+)")).toBe("3.0")
		t.expect(string.find(git({ "log", "-1", "--format=%B" }), "Issue: f0010 +5/-0 5.0m", 1, true) ~= nil)
			.toBe(true)
	end)

	it("done requires a resolved review, then promotes acceptance specs and finishes", function()
		local r1 = tr({ "done", "R0010" })
		t.expect(r1.ok).toBe(false)
		t.expect(string.find(r1.stderr, "no review", 1, true) ~= nil).toBe(true)

		write(
			"tracker/rafts/active/R0010/review-001.md",
			"# Review 001\n\n### F1 [medium] thing\nEvidence: x\n\n### F2 [low] other\nEvidence: y\n\nVerdict: changes\n"
		)
		write("tracker/rafts/active/R0010/refute-001.md", "- F1: fixed abc: done\n")
		local r2 = tr({ "done", "R0010" })
		t.expect(r2.ok).toBe(false)
		t.expect(string.find(r2.stderr, "F2", 1, true) ~= nil).toBe(true)

		write("tracker/rafts/active/R0010/refute-001.md", "- F1: fixed abc: done\n- F2: refuted: by design\n")
		must(tr({ "commit", "-m", "review 001 answered", "--time", "1" }), "commit")
		must(tr({ "done", "R0010" }), "done")
		t.expect(fs.isDir(`{dir}/tracker/rafts/done/R0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/done/f0010`)).toBe(true)
		t.expect(fs.isFile(`{dir}/tests/acceptance/f0010/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/done/f0010/acceptance`)).toBe(false)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
	end)
end)
