--!strict
-- c0870: `tracker.sh compact [--force]` renumbers every item from 0001 (issues f/d/c in one space, rafts in their
-- own), in a worktree cut from origin/main, as one local commit. It refuses while another branch changes tracker/
-- or tests/acceptance/ (unless --force), and on a malformed tree. Fixture under .cache/c0870-compact.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local process = require("@lune/process")
local t = require("@tests/lib/t")
-- test data spells `tests/acceptance/` in two parts: the real compaction rewrites every literal path to a
-- promoted folder in the repository, these specs included, and would change their data
local TA = "tests/" .. "acceptance/"

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0870-compact`
local seed, origin, main, other = `{base}/seed`, `{base}/origin.git`, `{base}/main`, `{base}/other`

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "compact" })
	git(dir, { "config", "user.email", "compact@example.invalid" })
end
local function doc(id: string, extra: string, body: string): string
	return `---\nid: {id}\ntype: chore\ntitle: T {id}\nslug: s-{string.lower(id)}\n{extra}design: ready\ncreated: 2026-01-01\n---\n\n# {id}: T\n\n{body}\n`
end
local function checkSh(id: string): string
	return `#!/usr/bin/env bash\nHERE="$(cd "$(dirname "$\{BASH_SOURCE[0]}")" && pwd -P)"\nA="$HERE/acceptance"\n[[ -d $A ]] || A="$PWD/tests/acceptance/{id}"\n`
end
-- a branch on origin that changes `path`, pushed from the other clone
local function pushBranch(name: string, path: string)
	git(other, { "fetch", "-q", "origin" })
	git(other, { "checkout", "-q", "-B", name, "origin/main" })
	write(`{other}/{path}`, "changed on " .. name .. "\n")
	git(other, { "add", "-A" })
	git(other, { "commit", "-q", "-m", name })
	git(other, { "push", "-q", "-f", "origin", `{name}:{name}` })
end
local function dropBranch(name: string)
	git(other, { "push", "-q", "origin", `:{name}` })
end
local function worktree(name: string): string
	local r = tr(main, { "worktree", name })
	if not r.ok then
		error(r.stderr .. r.stdout)
	end
	local wt = trim(r.stdout)
	identity(wt)
	return wt
end
local function read(wt: string, path: string): string?
	local p = `{wt}/{path}`
	return if fs.isFile(p) then fs.readFile(p) else nil
end

-- Issues sort as (1,c) (1,f) (2,f) (10,c) (100,c) (500,d): f0001 -> f0002 lands on the old f0002 before it moves.
local ISSUES = {
	{ "tracker/issues/c0001", "c0001", "" },
	{ "tracker/issues/f0001", "f0001", "" },
	{ "tracker/issues/f0002", "f0002", "" },
	{ "tracker/issues/done/c0010", "c0010", "raft: R0020\n" },
	{ "tracker/issues/c0100", "c0100", "raft: R0280\ndepends_on: [c0010]\n" },
	{ "tracker/issues/d0500", "d0500", "raft: R0280\n" },
}
local WANT = {
	c0001 = "c0001",
	f0001 = "f0002",
	f0002 = "f0003",
	c0010 = "c0004",
	c0100 = "c0005",
	d0500 = "d0006",
	R0020 = "R0001",
	R0280 = "R0002",
}
local templatesBefore = ""
local busyWt = ""

return t.spec("c0870 compact", function(it)
	it("sets up an origin with items, promoted specs and references to them", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		fs.writeDir(`{seed}/tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		-- a template that names ids which the compaction moves: templates are never rewritten
		write(`{seed}/z-nile/templates/issue/example.md`, "For example c0010, f0001 and R0020.\n")
		write(`{seed}/z-nile/next`, "issue 501 a-b-c\nraft 281 a-b-c\n")
		for _, i in ISSUES do
			write(
				`{seed}/{i[1]}/{i[2]}.md`,
				doc(i[2], i[3], `Blocks c0100; see c0010 and R0280 (not c00100).`)
			)
			write(`{seed}/{i[1]}/check.sh`, checkSh(i[2]))
		end
		write(
			`{seed}/tracker/issues/c0100/acceptance/a.spec.luau`,
			'local P = "' .. TA .. 'c0010/x.spec.luau" -- c0010 stays: ids in .luau are not rewritten\n'
		)
		write(`{seed}/tracker/issues/c0100/experiments/e1.txt`, "c0100 and c0010 stay here\n")
		write(`{seed}/tracker/rafts/done/R0020/R0020.md`, doc("R0020", "issues: [c0010]\n", "Done."))
		write(`{seed}/tracker/rafts/R0280/R0280.md`, doc("R0280", "issues: [c0100, d0500]\n", "After R0020."))
		write(`{seed}/tracker/architecture.md`, "# Architecture\n\nc0100 added the store.\n")
		-- promoted specs: a fixture path inside one must stay as it is
		write(
			`{seed}/tests/acceptance/c0010/x.spec.luau`,
			"local inside = `{dir}/tests/acceptance/c0010/y` -- c0100\n"
		)
		write(`{seed}/tests/acceptance/f0001/y.spec.luau`, "return 1\n")
		write(`{seed}/tests/acceptance/f0002/z.spec.luau`, "return 2\n")
		write(
			`{seed}/tests/tooling/ref.spec.luau`,
			'-- See c0010.\nlocal LIST = { "'
				.. TA
				.. 'c0010/x.spec.luau", "'
				.. TA
				.. 'f0002/z.spec.luau" }\n'
		)
		write(`{seed}/docs.md`, "Run `" .. TA .. "f0001/y.spec.luau` (c0100).\n")
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		for _, c in { main, other } do
			process.exec("git", { "clone", "-q", origin, c }) -- raw: clone to a named path
			identity(c)
		end
		local files = string.split(git(seed, { "ls-files", "z-nile/templates" }), "\n")
		for _, f in files do
			templatesBefore ..= f .. "\n" .. fs.readFile(`{seed}/{f}`)
		end
	end)

	it("refuses in the main checkout and changes nothing", function()
		local before = git(main, { "rev-parse", "HEAD" })
		local r = tr(main, { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("audit is read-only and runs in the main checkout", function()
		local r = tr(main, { "audit" })
		t.expect(r.ok).toBe(true)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("refuses while a branch on origin changes tracker/, and names it", function()
		pushBranch("prep-busy", "tracker/issues/c0100/notes.md")
		pushBranch("code-only", "src/thing.luau")
		local wt = worktree("compact-a")
		local head = git(wt, { "rev-parse", "HEAD" })
		local r = tr(wt, { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "prep-busy")).toBe(true)
		t.expect(has(r.stderr, "code-only")).toBe(false)
		t.expect(has(r.stderr, "--force")).toBe(true)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		dropBranch("prep-busy")
	end)

	it("a branch that changes tests/acceptance/ is busy too", function()
		pushBranch("spec-busy", TA .. "c0010/w.spec.luau")
		local r = tr(worktree("compact-b"), { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "spec-busy")).toBe(true)
		dropBranch("spec-busy")
	end)

	it("a local branch that changes tracker/ is busy too", function()
		git(main, { "branch", "-q", "local-busy", "origin/main" })
		local wt = worktree("local-busy-wt")
		git(wt, { "switch", "-q", "local-busy" })
		write(`{wt}/tracker/issues/c0001/more.md`, "more\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "local work" })
		local r = tr(worktree("compact-c"), { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "local-busy")).toBe(true)
		git(main, { "worktree", "remove", "--force", wt })
		git(main, { "branch", "-q", "-D", "local-busy" })
	end)

	it("refuses unless HEAD is origin/main, and on a dirty tree", function()
		local wt = worktree("compact-d")
		write(`{wt}/scratch.txt`, "dirty\n")
		t.expect(tr(wt, { "compact" }).ok).toBe(false)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "ahead of origin/main" })
		local r = tr(wt, { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "origin/main")).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/issues/c0010`) or fs.isDir(`{wt}/tracker/issues/done/c0010`))
			.toBe(true)
	end)

	it("refuses a tree the audit rejects (a duplicate id) and names the problem", function()
		git(other, { "checkout", "-q", "main" })
		git(other, { "pull", "-q", "origin", "main" })
		write(`{other}/tracker/issues/done/c0100/c0100.md`, doc("c0100", "", "a second copy"))
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "duplicate" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local wt = worktree("compact-e")
		local r = tr(wt, { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "duplicate")).toBe(true)
		t.expect(has(r.stderr, "c0100")).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/issues/c0100`)).toBe(true)
		git(other, { "rm", "-rq", "tracker/issues/done/c0100" })
		git(other, { "commit", "-q", "-m", "drop the duplicate" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
	end)

	it("compacts every item from 0001 in one local commit", function()
		local wt = worktree("compact-f")
		local start = git(wt, { "rev-parse", "origin/main" })
		local r = tr(wt, { "compact" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(git(wt, { "rev-parse", "HEAD^" })).toBe(start)
		t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("tracker: compact ids")
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		t.expect(git(origin, { "rev-parse", "main" })).toBe(start) -- nothing pushed
		busyWt = wt
	end)

	it("renames every item directory and document, chains included", function()
		local wt = busyWt
		for _, path in
			{
				"tracker/issues/c0001/c0001.md",
				"tracker/issues/f0002/f0002.md",
				"tracker/issues/f0003/f0003.md",
				"tracker/issues/done/c0004/c0004.md",
				"tracker/issues/c0005/c0005.md",
				"tracker/issues/d0006/d0006.md",
				"tracker/rafts/done/R0001/R0001.md",
				"tracker/rafts/R0002/R0002.md",
			}
		do
			t.expect(fs.isFile(`{wt}/{path}`)).toBe(true)
		end
		for _, gone in { "f0001", "done/c0010", "c0100", "d0500" } do
			t.expect(fs.isDir(`{wt}/tracker/issues/{gone}`)).toBe(false)
		end
		t.expect(fs.isDir(`{wt}/tracker/rafts/R0280`)).toBe(false)
		-- the old f0002 became f0003, with its own text (not overwritten by the old f0001)
		t.expect(has(read(wt, "tracker/issues/f0003/f0003.md"), "id: f0003")).toBe(true)
		t.expect(has(read(wt, "tracker/issues/f0002/f0002.md"), "id: f0002\n")).toBe(true)
		t.expect(has(read(wt, "tracker/issues/f0002/f0002.md"), "# f0002: T")).toBe(true)
	end)

	it("rewrites ids in tracker documents and check.sh files in one pass", function()
		local wt = busyWt
		local c5 = read(wt, "tracker/issues/c0005/c0005.md") :: string
		t.expect(has(c5, "Blocks c0005; see c0004 and R0002 (not c00100).")).toBe(true)
		t.expect(has(c5, "raft: R0002")).toBe(true)
		t.expect(has(c5, "depends_on: [c0004]")).toBe(true)
		t.expect(has(read(wt, "tracker/rafts/R0002/R0002.md"), "issues: [c0005, d0006]")).toBe(true)
		t.expect(has(read(wt, "tracker/architecture.md"), "c0005 added the store.")).toBe(true)
		t.expect(has(read(wt, "tracker/issues/done/c0004/check.sh"), 'A="$PWD/tests/acceptance/c0004"'))
			.toBe(true)
		-- not .md or .sh: left alone
		t.expect(read(wt, "tracker/issues/c0005/experiments/e1.txt")).toBe("c0100 and c0010 stay here\n")
	end)

	it(
		"renames promoted spec folders unchanged and rewrites real paths to them, not fixture paths",
		function()
			local wt = busyWt
			t.expect(read(wt, TA .. "c0004/x.spec.luau"))
				.toBe("local inside = `{dir}/tests/acceptance/c0010/y` -- c0100\n")
			t.expect(read(wt, TA .. "f0002/y.spec.luau")).toBe("return 1\n")
			t.expect(read(wt, TA .. "f0003/z.spec.luau")).toBe("return 2\n")
			t.expect(fs.isDir(`{wt}/tests/acceptance/c0010`)).toBe(false)
			t.expect(fs.isDir(`{wt}/tests/acceptance/f0001`)).toBe(false)
			t.expect(read(wt, "tests/tooling/ref.spec.luau")).toBe(
				'-- See c0010.\nlocal LIST = { "'
					.. TA
					.. 'c0004/x.spec.luau", "'
					.. TA
					.. 'f0003/z.spec.luau" }\n'
			)
			t.expect(read(wt, "docs.md")).toBe("Run `" .. TA .. "f0002/y.spec.luau` (c0100).\n")
			t.expect(read(wt, "tracker/issues/c0005/acceptance/a.spec.luau"))
				.toBe('local P = "' .. TA .. 'c0004/x.spec.luau" -- c0010 stays: ids in .luau are not rewritten\n')
			-- git records the promoted specs as pure renames
			local moved =
				git(wt, { "diff", "--name-status", "-M100%", "HEAD^", "HEAD", "--", "tests/acceptance" })
			for line in string.gmatch(moved, "[^\n]+") do
				t.expect(string.sub(line, 1, 4)).toBe("R100")
			end
		end
	)

	it("leaves the templates alone", function()
		local now = ""
		for _, f in string.split(git(busyWt, { "ls-files", "z-nile/templates" }), "\n") do
			now ..= f .. "\n" .. fs.readFile(`{busyWt}/{f}`)
		end
		t.expect(now).toBe(templatesBefore)
	end)

	it("writes the counter one above each space and the full map", function()
		local c = ids.parse(read(busyWt, ids.FILE) or "") :: ids.Counters
		t.expect(c.issue).toBe(7)
		t.expect(c.raft).toBe(3)
		t.expect(ids.parseMap(read(busyWt, ids.MAP_FILE) or "")).toEqual(WANT)
	end)

	it("the compacted tree passes the audit", function()
		local r = tr(busyWt, { "audit" })
		t.expect(r.ok).toBe(true)
	end)

	it("--force compacts despite a busy branch and tells its owner to remap", function()
		pushBranch("prep-late", "tracker/issues/c0100/late.md")
		local wt = worktree("compact-g")
		local r = tr(wt, { "compact", "--force" })
		t.expect(r.ok).toBe(true)
		local said = r.stdout .. r.stderr
		t.expect(has(said, "prep-late")).toBe(true)
		t.expect(has(said, "remap")).toBe(true)
		t.expect(fs.isFile(`{wt}/tracker/issues/c0005/c0005.md`)).toBe(true)
		dropBranch("prep-late")
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
