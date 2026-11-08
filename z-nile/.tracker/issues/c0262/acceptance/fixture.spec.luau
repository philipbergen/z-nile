--!strict
-- c0262 AC7, AC7: `./zn final-view` and `./zn done` driven for real in a throwaway clone under the home's .cache (no
-- remote, so the base is the local main). AC7: the view reads the design from the base, the diff is the issue's Touched
-- modules, and a busy folder, an unknown issue and an empty diff are refused. AC7: done refuses a grouped raft whose
-- member has no on-course final review (a first off-course verdict is a REDO, a second BLOCKED for the human, also when the
-- branch drops the raft's grouped line), and passes with one.
local cleanup = require("@tests/lib/cleanup")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local work = `{fixture.physical(".")}/.cache/c0262-final`
local OUT = `{work}/.cache/final-view-out`

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local REVIEW_OK = "# Review 001\n\nVerdict: approve\n"
local FINAL_NO = "# Review 001: f0010 (final mode)\n\n### F1 [high] the implementation misses the design\nGap: implementation\n\nVerdict: off-course\n"
local FINAL_OK = "# Review 003: f0010 (final mode)\n\nVerdict: on-course\n"
local TICKET = "pickman/.tracker/issues/active/f0010"
local RAFT = "pickman/.tracker/rafts/active/R0010"

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function git(args: { string }): string
	return must(fixture.exec(work, "git", args), "git " .. table.concat(args, " "))
end
local function tr(args: { string }): Result
	return fixture.exec(work, "bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function read(path: string): string
	return fs.readFile(`{work}/{path}`)
end
local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{work}/{parent}`)
	end
	fs.writeFile(`{work}/{path}`, text)
end
local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(read(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function view(args: { string }): Result
	local argv = { "final-view" }
	for _, a in args do
		table.insert(argv, a)
	end
	return tr(argv)
end

return t.spec("c0262 final-view and done, driven for real", function(it)
	it("sets up a clone with a grouped raft created after the cutoff, started, with a code review that approves", function()
		if fs.isDir(work) then
			fs.removeDir(work)
		end
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		git({ "remote", "remove", "origin" })
		local listed = process.exec("git", {
			"ls-files", "-co", "--exclude-standard", "zn", "scripts", "z-nile",
			":(exclude)z-nile/.tracker", ":(exclude)z-nile/next", ":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		git({ "config", "gc.auto", "0" })
		engine.empty(work)
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		git({ "branch", "-M", "main" })
		must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new issue")
		must(tr({ "new", "raft", "feature", "demo", "f0010", "--single", "--project", "pickman" }), "new raft")
		for _, doc in { "pickman/.tracker/issues/f0010/f0010.md", "pickman/.tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit("pickman/.tracker/rafts/R0010/R0010.md", "created: %d%d%d%d%-%d%d%-%d%d", "created: 2026-11-08\ngrouped: [f0010@000000000000]")
		edit("pickman/.tracker/issues/f0010/f0010.md", "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n")
		write("pickman/.tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("pickman/.tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		write(`{RAFT}/review-001.md`, REVIEW_OK)
		write("notes/alpha/a.txt", "alpha work\n")
		write("notes/beta/b.txt", "someone else's work\n")
		edit("pickman/.tracker/issues/active/f0010/f0010.md", "## Problem\n", "## Problem\nP-edited-on-the-branch\n")
		-- the executor's own words, a Touched line dropped on the branch, a change no member claims, an emergent member
		edit("pickman/.tracker/issues/active/f0010/f0010.md", "## Verification log\n", "## Verification log\nVLOG-MARKER\n")
		edit("pickman/.tracker/issues/active/f0010/f0010.md", "%- `notes/alpha`\n", "")
		write("notes/gamma/g.txt", "nobody claims this\n")
		write(
			"pickman/.tracker/issues/active/f0011/f0011.md",
			"---\nid: f0011\ntype: feature\ntitle: emergent\nslug: emergent\nraft: R0010\ndepends_on: []\nemergent: true\ndesign: ready\ncreated: 2026-11-09\nstatus: active-x-y-z\n---\n\n# f0011\n\n## Problem\nfiled during execution\n\n### Touched modules\n- `notes/delta`\n"
		)
		write("notes/delta/d.txt", "emergent work\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "work" })
	end)

	it("AC7: the view takes the design from the base and the branch's edits as a patch, and the diff is the Touched modules only", function()
		local before = git({ "status", "--porcelain" })
		local r = view({ "f0010", "--out", OUT, "--base", "main" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		local design = fs.readFile(`{OUT}/design.md`)
		t.expect(has(design, "P-edited-on-the-branch")).toBe(false)
		t.expect(has(fs.readFile(`{OUT}/design-changes.patch`), "P-edited-on-the-branch")).toBe(true)
		t.expect(has(fs.readFile(`{OUT}/ask.md`), "f0010")).toBe(true)
		t.expect(has(fs.readFile(`{OUT}/ask.md`), "P-edited-on-the-branch")).toBe(false)
		local patch = fs.readFile(`{OUT}/implementation.patch`)
		t.expect(has(patch, "notes/alpha/a.txt")).toBe(true)
		t.expect(has(patch, "notes/beta/b.txt")).toBe(false)
		t.expect(has(patch, "f0010.md")).toBe(false)
		-- Touched is read from the base: the line dropped on the branch does not drop the file; notes/gamma is claimed by
		-- no member, so it rides in unclaimed.patch and the README lists it
		t.expect(has(patch, "notes/gamma")).toBe(false)
		t.expect(has(fs.readFile(`{OUT}/unclaimed.patch`), "notes/gamma/g.txt")).toBe(true)
		t.expect(has(fs.readFile(`{OUT}/README.md`), "notes/gamma/g.txt")).toBe(true)
		-- the executor's own words are in no file of the view, the design-changes patch included
		for _, name in { "design.md", "design-changes.patch", "ask.md", "README.md" } do
			t.expect(has(fs.readFile(`{OUT}/{name}`), "VLOG-MARKER")).toBe(false)
		end
		t.expect(has(fs.readFile(`{OUT}/skill.md`), "Final mode")).toBe(true)
		for _, name in fs.readDir(OUT) do
			for _, bad in { "review", "refute", "harvest", "spend", "prompt" } do
				t.expect(string.find(name, bad, 1, true) == nil or name == "skill.md" or name == "design-changes.patch").toBe(true)
			end
		end
		fs.removeDir(OUT)
		t.expect(git({ "status", "--porcelain" })).toBe(before)
	end)

	it("AC7: an emergent member (only on the branch) gets a view with its design from HEAD; a non-emergent one is refused", function()
		local r = view({ "f0011", "--out", OUT, "--base", "main" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(fs.readFile(`{OUT}/README.md`), "written during execution")).toBe(true)
		t.expect(has(fs.readFile(`{OUT}/design.md`), "filed during execution")).toBe(true)
		t.expect(has(fs.readFile(`{OUT}/implementation.patch`), "notes/delta/d.txt")).toBe(true)
		fs.removeDir(OUT)
		edit("pickman/.tracker/issues/active/f0011/f0011.md", "emergent: true", "emergent: false")
		t.expect(view({ "f0011", "--out", OUT, "--base", "main" }).ok).toBe(false)
		t.expect(fs.isDir(OUT)).toBe(false)
		edit("pickman/.tracker/issues/active/f0011/f0011.md", "emergent: false", "emergent: true")
	end)

	it("AC7: a busy folder, an unknown issue and an empty diff are refused, and nothing is written", function()
		fs.writeDir(OUT)
		fs.writeFile(`{OUT}/keep.txt`, "mine")
		t.expect(view({ "f0010", "--out", OUT, "--base", "main" }).ok).toBe(false)
		t.expect(fs.readFile(`{OUT}/keep.txt`)).toBe("mine")
		fs.removeDir(OUT)
		t.expect(view({ "f9999", "--out", OUT, "--base", "main" }).ok).toBe(false)
		local empty = view({ "f0010", "--out", OUT, "--base", "HEAD" })
		t.expect(empty.ok).toBe(false)
		t.expect(has(empty.stderr, "empty")).toBe(true)
		t.expect(fs.isDir(OUT)).toBe(false)
	end)

	it("AC7: done refuses a grouped raft with no final review, naming the member and the command", function()
		local r = tr({ "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0010") and has(r.stderr, "--mode final")).toBe(true)
		t.expect(fs.isDir(`{work}/{RAFT}`)).toBe(true)
	end)

	it("AC7: done sends a first off-course verdict back (REDO), also when the branch drops the grouped line", function()
		write(`{TICKET}/final-review-001.md`, FINAL_NO)
		edit("pickman/.tracker/rafts/active/R0010/R0010.md", "\ngrouped:[^\n]*", "")
		must(tr({ "commit", "-m", "final review 1 and a dropped grouped line", "--time", "1" }), "commit")
		local r = tr({ "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0010") and has(r.stderr, "REDO") and not has(r.stderr, "BLOCKED")).toBe(true)
		t.expect(fs.isDir(`{work}/{RAFT}`)).toBe(true)
	end)

	it("AC7: a second off-course verdict blocks the ticket for the human", function()
		write(`{TICKET}/final-review-002.md`, FINAL_NO)
		must(tr({ "commit", "-m", "final review 2", "--time", "1" }), "commit")
		local r = tr({ "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "BLOCKED") and has(r.stderr, "human")).toBe(true)
		t.expect(fs.isDir(`{work}/{RAFT}`)).toBe(true)
	end)

	it("AC7: a newer on-course round clears it and done finishes", function()
		write(`{TICKET}/final-review-003.md`, FINAL_OK)
		must(tr({ "commit", "-m", "final review 3", "--time", "1" }), "commit")
		local r = tr({ "done", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(fs.isDir(`{work}/pickman/.tracker/rafts/done/R0010`)).toBe(true)
	end)

	it("cleans up", function()
		cleanup.removeTree(work)
	end)
end)
