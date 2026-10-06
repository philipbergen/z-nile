--!strict
-- c0430: the workstream plan, worktrees cut from a ref, and stream review files.
-- Fixture under .cache/ws-e2e: a seed clone of the repo (no origin, `main` forced, the working tree's
-- tooling overlaid, tracker emptied) where rafts and issues are created; then a bare `origin.git`
-- cloned from the seed and a clone `main/` for the worktree cases.
local clone = require("@tests/lib/clone")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/ws-e2e`
local seed = `{base}/seed`
local origin = `{base}/origin.git`
local main = `{base}/main`
local wt1 = `{main}/.worktree/R0010`
local stream = `{main}/.worktree/ws-f0010`

-- Fixture repos are throwaway: no background gc/maintenance that could race a re-created fixture. The
-- runner's guard (scripts/lib/fence.sh) turns both off for every git a spec runs; a spec must not set
-- git config through the environment, which would replace the guard's (testing skill).
local NO_GC: { [string]: string } = {}

local function run(cwd: string, cmd: string, args: { string }): Result
	return fixture.exec(cwd, cmd, args, { env = NO_GC })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function git(cwd: string, args: { string }): string
	return must(run(cwd, "git", args), "git " .. table.concat(args, " "))
end

local function tr(cwd: string, args: { string }): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) })
end

local function identity(cwd: string)
	git(cwd, { "config", "user.name", "e2e" })
	git(cwd, { "config", "user.email", "e2e@example.invalid" })
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	fs.writeFile(path, text)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- Replace the issue's Touched modules section with these bullets (none: keep the template comment).
local function touches(id: string, paths: { string })
	local doc = `{seed}/tracker/issues/{id}/{id}.md`
	local text = fs.readFile(doc)
	local a = string.find(text, "### Touched modules", 1, true)
	local b = string.find(text, "### Affected specs", 1, true)
	assert(a and b, "template sections not found")
	local bullets = {}
	for _, p in paths do
		table.insert(bullets, "- `" .. p .. "`")
	end
	fs.writeFile(
		doc,
		string.sub(text, 1, a - 1)
			.. "### Touched modules\n"
			.. table.concat(bullets, "\n")
			.. "\n\n"
			.. string.sub(text, b)
	)
end

local function depends(id: string, deps: { string })
	edit(
		`{seed}/tracker/issues/{id}/{id}.md`,
		"depends_on: %[%]",
		"depends_on: [" .. table.concat(deps, ", ") .. "]"
	)
end

local function countWorktrees(): number
	local _, n = string.gsub(git(main, { "worktree", "list", "--porcelain" }), "worktree ", "")
	return n
end

return t.spec("workstreams", function(it)
	it("workstreams orders waves by depends_on and serializes overlapping modules", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		clone.isolated(root, seed)
		identity(seed)
		git(seed, { "checkout", "-q", "-B", "main" })
		git(seed, { "remote", "remove", "origin" })
		local listed = process.exec(
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", "tracker/templates", ".gitignore" },
			{ cwd = root }
		)
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{seed}/{parent}`)
				end
				fs.writeFile(`{seed}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{seed}/tracker/{kind}/{state}`
				if fs.isDir(dir) then
					for _, name in fs.readDir(dir) do
						if string.match(name, "^[fdcR]%d%d%d%d$") then
							fs.removeDir(dir .. name)
						end
					end
				end
			end
		end
		-- and its counter: without tracker/next ids follow the old rule (c0870)
		if fs.isFile(`{seed}/tracker/next`) then
			fs.removeFile(`{seed}/tracker/next`)
		end
		-- twenty issues f0010..f0200
		for _, slug in
			{
				"a",
				"b",
				"c",
				"d",
				"e",
				"f",
				"g",
				"h",
				"i",
				"j",
				"k",
				"l",
				"m",
				"n",
				"o",
				"p",
				"q",
				"r",
				"s",
				"t",
			}
		do
			must(tr(seed, { "new", "issue", "f", slug }), "new issue " .. slug)
		end
		must(tr(seed, { "new", "raft", "feature", "demo", "f0010", "f0020", "f0030", "f0040" }), "raft demo")
		must(tr(seed, { "new", "raft", "feature", "solo", "f0050", "--single" }), "raft solo")
		must(tr(seed, { "new", "raft", "feature", "chain", "f0060", "f0070", "f0080" }), "raft chain")
		must(tr(seed, { "new", "raft", "feature", "loop", "f0090", "f0100" }), "raft loop")
		must(tr(seed, { "new", "raft", "feature", "line", "f0110", "f0120", "f0130" }), "raft line")
		must(tr(seed, { "new", "raft", "feature", "prefix", "f0140", "f0150", "f0160" }), "raft prefix")
		must(tr(seed, { "new", "raft", "feature", "late", "f0170", "f0180", "f0190", "f0200" }), "raft late")
		touches("f0010", { "src/a" })
		touches("f0020", { "src/b" })
		touches("f0030", { "src/a/sub" })
		touches("f0040", { "src/c" })
		depends("f0040", { "f0020" })
		touches("f0050", { "src/solo" })
		-- f0060 keeps the template's comment only: no touched modules
		touches("f0070", { "src/z" })
		touches("f0080", { "src/y" })
		depends("f0080", { "f0070", "c0999" }) -- c0999 is not in the raft: ignored
		touches("f0090", { "src/p" })
		touches("f0100", { "src/q" })
		depends("f0090", { "f0100" })
		depends("f0100", { "f0090" })
		touches("f0110", { "src/m" })
		touches("f0120", { "src/n" })
		touches("f0130", { "src/o" })
		depends("f0120", { "f0110" })
		depends("f0130", { "f0120" })
		touches("f0140", { "src/a" })
		touches("f0150", { "src/ab" }) -- a sibling of src/a, not inside it
		touches("f0160", { "src/a/x" }) -- inside src/a, and it also depends on f0140
		depends("f0160", { "f0140" })
		touches("f0170", { "src/s1" })
		touches("f0180", { "src/s2" })
		depends("f0180", { "f0170" }) -- wave 2
		touches("f0190", { "src/s3" }) -- wave 1, but a higher id than f0180
		touches("f0200", { "src/s4" })
		depends("f0200", { "f0180", "f0190" })
		-- R0010 and its issues are ready to start
		edit(`{seed}/tracker/rafts/R0010/R0010.md`, "design: draft", "design: ready")
		for _, id in { "f0010", "f0020", "f0030", "f0040" } do
			edit(`{seed}/tracker/issues/{id}/{id}.md`, "design: draft", "design: ready")
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-qm", "fixture" })
		must(process.exec("git", { "clone", "-q", "--bare", seed, origin }), "bare origin")
		must(process.exec("git", { "clone", "-q", origin, main }), "clone main")
		identity(main)

		local r = tr(main, { "workstreams", "R0010" })
		t.expect(must(r, "workstreams R0010")).toBe(table.concat({
			"raft R0010: 4 issues",
			"f0010 wave 1",
			"f0020 wave 1",
			"f0030 wave 2 after f0010 (overlap)",
			"f0040 wave 2 after f0020 (depends_on)",
			"parallel: yes (wave 1: f0010 f0020)",
		}, "\n"))
	end)

	it("a single-issue raft is sequential", function()
		t.expect(must(tr(main, { "workstreams", "R0020" }), "workstreams R0020"))
			.toBe("raft R0020: 1 issue\nf0050 wave 1\nparallel: no")
	end)

	it("an issue without touched modules is serialized with a warning", function()
		local r = tr(main, { "workstreams", "R0030" })
		t.expect(must(r, "workstreams R0030")).toBe(table.concat({
			"raft R0030: 3 issues",
			"f0060 wave 1",
			"f0070 wave 2 after f0060 (no touched modules)",
			"f0080 wave 3 after f0060 (no touched modules), f0070 (depends_on)",
			"parallel: no",
		}, "\n"))
		t.expect(has(r.stderr, "warning: f0060 has no Touched modules; serialized")).toBe(true)
	end)

	it("a dependency cycle and an unknown raft are errors", function()
		local cycle = tr(main, { "workstreams", "R0040" })
		t.expect(cycle.ok).toBe(false)
		t.expect(has(cycle.stderr, "cycle") and has(cycle.stderr, "f0090") and has(cycle.stderr, "f0100"))
			.toBe(true)
		t.expect(tr(main, { "workstreams", "R9999" }).ok).toBe(false)
		t.expect(tr(main, { "workstreams", "f0010" }).ok).toBe(false)
	end)

	it("waves are one more than the latest dependency (a chain of three)", function()
		t.expect(must(tr(main, { "workstreams", "R0050" }), "workstreams R0050")).toBe(table.concat({
			"raft R0050: 3 issues",
			"f0110 wave 1",
			"f0120 wave 2 after f0110 (depends_on)",
			"f0130 wave 3 after f0120 (depends_on)",
			"parallel: no",
		}, "\n"))
	end)

	it("the latest wave in the after set decides, whatever its id", function()
		-- f0200 follows f0180 (wave 2) and f0190 (wave 1, the higher id): its wave is 3, not 2
		t.expect(must(tr(main, { "workstreams", "R0070" }), "workstreams R0070")).toBe(table.concat({
			"raft R0070: 4 issues",
			"f0170 wave 1",
			"f0180 wave 2 after f0170 (depends_on)",
			"f0190 wave 1",
			"f0200 wave 3 after f0180 (depends_on), f0190 (depends_on)",
			"parallel: yes (wave 1: f0170 f0190)",
		}, "\n"))
	end)

	it("overlap compares whole path components and depends_on wins the reason", function()
		-- src/ab is not inside src/a; src/a/x is, but f0160 also depends on f0140, which is the label
		t.expect(must(tr(main, { "workstreams", "R0060" }), "workstreams R0060")).toBe(table.concat({
			"raft R0060: 3 issues",
			"f0140 wave 1",
			"f0150 wave 1",
			"f0160 wave 2 after f0140 (depends_on)",
			"parallel: yes (wave 1: f0140 f0150)",
		}, "\n"))
	end)

	it("worktree --from bases the new worktree on the ref", function()
		t.expect(must(tr(main, { "worktree", "R0010" }), "worktree R0010")).toBe(wt1)
		git(wt1, { "commit", "-q", "--allow-empty", "-m", "raft work" })
		local tip = git(wt1, { "rev-parse", "HEAD" })
		t.expect(tip ~= git(main, { "rev-parse", "origin/main" })).toBe(true)
		t.expect(must(tr(main, { "worktree", "ws-f0010", "--from", "R0010-demo" }), "worktree --from"))
			.toBe(stream)
		t.expect(git(stream, { "branch", "--show-current" })).toBe("ws-f0010")
		t.expect(git(stream, { "rev-parse", "HEAD" })).toBe(tip)
		t.expect(must(tr(main, { "worktree", "ws-f0010", "--from", "R0010-demo" }), "again")).toBe(stream)
	end)

	it("worktree --from rejects an unknown ref and a raft id", function()
		local before = countWorktrees()
		local unknown = tr(main, { "worktree", "ws-f0020", "--from", "no-such-ref" })
		t.expect(unknown.ok).toBe(false)
		t.expect(has(unknown.stderr, "no-such-ref")).toBe(true)
		t.expect(git(main, { "branch", "--list", "ws-f0020" })).toBe("")
		local raft = tr(main, { "worktree", "R0020", "--from", "R0010-demo" })
		t.expect(raft.ok).toBe(false)
		t.expect(has(raft.stderr, "named worktrees")).toBe(true)
		t.expect(countWorktrees()).toBe(before)
		t.expect(fs.isDir(`{main}/.worktree/R0020`)).toBe(false)
	end)

	it("tracker.sh commit refuses while a squash merge is unresolved", function()
		must(tr(wt1, { "start", "R0010" }), "start R0010")
		local notes = `{wt1}/notes.txt`
		fs.writeFile(notes, "one\n")
		git(wt1, { "add", "-A" })
		git(wt1, { "commit", "-qm", "notes" })
		local tip = git(wt1, { "rev-parse", "HEAD" })
		local branch = git(wt1, { "branch", "--show-current" })
		for _, b in { "stream-a", "stream-b" } do
			git(wt1, { "checkout", "-q", "-b", b, tip })
			fs.writeFile(notes, b .. "\n")
			git(wt1, { "add", "-A" })
			git(wt1, { "commit", "-qm", b })
		end
		git(wt1, { "checkout", "-q", branch })
		git(wt1, { "merge", "--squash", "-q", "stream-a" })
		git(wt1, { "commit", "-qm", "stream a" })
		local before = git(wt1, { "rev-parse", "HEAD" })
		t.expect(run(wt1, "git", { "merge", "--squash", "stream-b" }).ok).toBe(false)
		local r = tr(wt1, { "commit", "-m", "stream b" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "unmerged")).toBe(true)
		t.expect(git(wt1, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(has(fs.readFile(notes), "<<<<<<<")).toBe(true) -- the markers were never committed
		git(wt1, { "reset", "-q", "--hard", "HEAD" })
	end)

	it("stream review files are not review rounds", function()
		local dir = `{wt1}/tracker/rafts/active/R0010`
		fs.writeFile(
			`{dir}/stream-review-f0010-001.md`,
			"# Review 001\n\n### F1 [high] x\n\nVerdict: changes\n"
		)
		fs.writeFile(`{dir}/stream-refute-f0010-001.md`, "- F1: fixed: y; consequences: none\n")
		git(wt1, { "add", "-A" })
		git(wt1, { "commit", "-qm", "stream review files" })
		-- with no review-NNN.md, done still asks for the adversarial review, whatever the stream files say
		local done = tr(wt1, { "done", "R0010" })
		t.expect(done.ok).toBe(false)
		t.expect(has(done.stderr, "no review-NNN.md")).toBe(true)
		local metrics = must(tr(wt1, { "metrics" }), "metrics")
		t.expect(has(metrics, "| R0010 | 0 | 0 | none |")).toBe(true)
	end)
end)
