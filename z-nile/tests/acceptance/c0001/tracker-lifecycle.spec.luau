--!strict
-- c0010 AC1: the tracker CLI lifecycle works end to end, driven for real in a throwaway clone
-- of the committed HEAD (no remote, so start/done skip push and gh).
local buffer = require("@znile/engine/buffer")
local clone = require("@tests/lib/clone")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: a spec writes only under its home's .cache (the jail refuses the checkout top's); root stays the
-- repository it clones
local dir = `{fixture.physical(".")}/.cache/tracker-e2e`

-- The fixture's identity rides in the environment, not in its git config: a run of the spec runner nested in
-- the fixture (tracker.sh done runs one) refuses a repository whose own identity is a fixture's (c0640).
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
}

local function run(cmd: string, args: { string }): Result
	return fixture.exec(dir, cmd, args, { env = ID })
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

local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'

return t.spec("tracker lifecycle", function(it)
	it("allocates ids in steps of 10 across issue types", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		clone.isolated(root, dir)
		git({ "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted tracker changes are what gets tested
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{dir}/{parent}`)
				end
				fs.writeFile(`{dir}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		-- start from an empty tracker so ids are predictable regardless of the real backlog
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		engine.empty(dir)
		-- c0120 override: engine.REGISTRY's layout keeps pickman's items in pickman/.tracker and its home (specs, promoted
		-- specs) in pickman/; every path below names that root and home
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new f"))
			.toBe("pickman/.tracker/issues/f0010/f0010.md")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(must(tr({ "new", "issue", "d", "beta", "--project", "pickman" }), "new d"))
			.toBe("pickman/.tracker/issues/d0020/d0020.md")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(must(tr({ "new", "issue", "f", "gamma", "--project", "pickman" }), "new f"))
			.toBe("pickman/.tracker/issues/f0030/f0030.md")
	end)

	it("rejects a raft that mixes types", function()
		local r = tr({ "new", "raft", "feature", "mixed", "f0010", "d0020", "--project", "pickman" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "cannot contain", 1, true) ~= nil).toBe(true)
	end)

	it("renumber steps an id and rewrites references", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(
			must(
				tr({ "new", "raft", "feature", "demo", "f0010", "f0030", "--project", "pickman" }),
				"new raft"
			)
		)
			.toBe("pickman/.tracker/rafts/R0010/R0010.md")
		must(tr({ "renumber", "f0030", "f0031" }), "renumber")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local raftDoc = read("pickman/.tracker/rafts/R0010/R0010.md")
		t.expect(string.find(raftDoc, "f0031", 1, true) ~= nil).toBe(true)
		t.expect((string.find(raftDoc, "f0030", 1, true))).toBe(nil)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{dir}/pickman/.tracker/issues/f0031/f0031.md`)).toBe(true)
	end)

	it("start refuses issues that are not design: ready", function()
		seal.prep(dir)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep draft" })
		local r = tr({ "start", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "design: ready", 1, true) ~= nil).toBe(true)
	end)

	it("start branches, moves items to active, and commits exactly once", function()
		for _, doc in
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			{
				"pickman/.tracker/issues/f0010/f0010.md",
				"pickman/.tracker/issues/f0031/f0031.md",
				"pickman/.tracker/rafts/R0010/R0010.md",
			}
		do
			edit(doc, "design: draft", "design: ready")
		end
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		edit(
			"pickman/.tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		edit(
			"pickman/.tracker/issues/f0031/f0031.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/gamma`\n"
		)
		for _, p in
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			{
				"pickman/.tracker/issues/f0010/check.sh",
				"pickman/.tracker/issues/f0031/check.sh",
				"pickman/.tracker/rafts/R0010/check.sh",
			}
		do
			write(p, TRIVIAL_CHECK)
		end
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		fs.writeDir(`{dir}/pickman/.tracker/issues/f0010/acceptance`)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/issues/f0010/acceptance/alpha.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		local before = tonumber(git({ "rev-list", "--count", "HEAD" })) :: number
		must(tr({ "start", "R0010" }), "start")
		t.expect(git({ "branch", "--show-current" })).toBe("R0010/1/f0010")
		t.expect(tonumber(git({ "rev-list", "--count", "HEAD" }))).toBe(before + 1)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: start R0010 Demo")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/issues/active/f0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/issues/active/f0031`)).toBe(true)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/issues/d0020`)).toBe(true)
	end)

	it("commit records spend whose lines equal the diff, split by Touched modules", function()
		fs.writeDir(`{dir}/notes/alpha`)
		fs.writeDir(`{dir}/notes/gamma`)
		write("notes/alpha/a.txt", "1\n2\n3\n4\n5\n")
		write("notes/gamma/g.txt", "1\n2\n3\n")
		must(tr({ "commit", "-m", "work", "--issue", "f0010", "--issue", "f0031", "--time", "8" }), "commit")
		local added = 0
		for line in
			-- c0120 override: pickman's files live in pickman/ (its home)
			string.gmatch(
				git({ "show", "--numstat", "--format=", "HEAD", "--", ".", ":(exclude)pickman/.tracker" }),
				"[^\n]+"
			)
		do
			added += tonumber(string.match(line, "^(%d+)")) or 0
		end
		t.expect(added).toBe(8)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local function measured(id: string): string
			local folder = `{dir}/pickman/.tracker/issues/active/{id}/spend.d`
			local names = fs.readDir(folder)
			table.sort(names)
			return fs.readFile(`{folder}/{names[#names]}`)
		end
		local a = buffer.parseTsv(measured("f0010"))
		local g = buffer.parseTsv(measured("f0031"))
		t.expect(a ~= nil and g ~= nil).toBe(true)
		t.expect((a :: { any })[1].added).toBe(5)
		t.expect((g :: { any })[1].added).toBe(3)
		t.expect((a :: { any })[1].minutes).toBe(0)
		t.expect((g :: { any })[1].minutes).toBe(0)
		t.expect(string.find(git({ "log", "-1", "--format=%B" }), "Issue: f0010 +5/-0 0.0m", 1, true) ~= nil)
			.toBe(true)
	end)

	it("done requires a clean tree and a resolved review", function()
		local r1 = tr({ "done", "R0010" })
		t.expect(r1.ok).toBe(false)
		t.expect(string.find(r1.stderr, "no review", 1, true) ~= nil).toBe(true)

		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Final Review 001\n\n### F1 [medium] thing\nEvidence: x\n\n### F2 [low] other\nEvidence: y\n\nVerdict: changes\n"
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/rafts/active/R0010/final-refute-001.md",
			"- F1: fixed abc: done; consequences: none\n"
		)
		local dirty = tr({ "done", "R0010" })
		t.expect(dirty.ok).toBe(false)
		t.expect(string.find(dirty.stderr, "clean tree", 1, true) ~= nil).toBe(true)

		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		local r2 = tr({ "done", "R0010" })
		t.expect(r2.ok).toBe(false)
		t.expect(string.find(r2.stderr, "F2", 1, true) ~= nil).toBe(true)
	end)

	it("done rolls back when a promoted acceptance spec fails", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/rafts/active/R0010/final-refute-001.md",
			"- F1: fixed abc: done; consequences: none\n- F2: refuted: by design\n"
		)
		local raftDoc = "pickman/.tracker/rafts/active/R0010/R0010.md"
		write(
			raftDoc,
			read(raftDoc)
				.. "\n## Open to the human\n- F2: other. Answer: by design. Decision: accept.\n  Ruled (user, 2026-11-10): accepted.\n"
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local good = read("pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau",
			(string.gsub(good, "toBe%(1%)", "toBe(2)"))
		)
		must(tr({ "commit", "-m", "review 001 answered", "--time", "1" }), "commit")
		must(tr({ "finish", "f0010" }), "finish f0010")
		seal.layerReview(dir, "f0010") -- c0248: a layer is complete before the next starts or done binds it
		must(tr({ "start", "R0010" }), "start f0031")
		write("notes/f0031.txt", "gamma\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "f0031 work" })
		must(tr({ "finish", "f0031" }), "finish f0031")
		seal.layerReview(dir, "f0031") -- c0248: a layer is complete before the next starts or done binds it
		seal.trace(dir, "R0010")
		local head = git({ "rev-parse", "HEAD" })
		local r = tr({ "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "rolled back", 1, true) ~= nil).toBe(true)
		t.expect(git({ "rev-parse", "HEAD" })).toBe(head)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isFile(`{dir}/pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau`))
			.toBe(true)
		write("pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau", good)
		must(tr({ "commit", "-m", "fix acceptance fixture", "--time", "1" }), "commit")
		must(tr({ "finish", "f0031" }), "finish the fix")
		seal.layerReview(dir, "f0031") -- c0248: a layer is complete before the next starts or done binds it
		seal.trace(dir, "R0010")
	end)

	it("done promotes acceptance specs and finishes", function()
		must(tr({ "done", "R0010" }), "done")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/rafts/done/R0010`)).toBe(true)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/issues/done/f0010`)).toBe(true)
		t.expect(fs.isFile(`{dir}/pickman/tests/acceptance/f0010/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{dir}/pickman/.tracker/issues/done/f0010/acceptance`)).toBe(false)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("R0010: bind f0010, f0031")
	end)
end)
