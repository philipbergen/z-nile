--!strict
-- c0250 AC15: `./zn audit` reports a blocked item without `blocked:` or without an unresolved note that parses,
-- `blocked:` on an item that is not blocked, and a reason outside the list, each naming the command that clears it. A
-- member of a blocked raft is covered by the raft's note; a clean blocked item reports nothing. Plain folders under
-- .cache/c0250-audit, no git.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = ".cache/c0250-audit"

local NOTE =
	"# Escalation: x\nItem: x\nReason: red-gate\nFrom: preparing\nActor: human:Ann\nWhen: 2026-11-10 10:00\n\n## Question\nWhich?\n\n## What was tried\nTwice.\n\n## Open findings or error\nF1.\n\n## Options\n- retry: again (recommended)\n- abort: stop\n\n## Resume\n./zn resolve x retry\n"
local RESOLVED = NOTE
	.. "\n## Resolution\nDecision: retry\nAnswer: none\nBy: human:Ann\nWhen: 2026-11-11 10:00\n"

local function doc(id: string, front: string): string
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s{id}\n{front}---\n\n# {id}\n`
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
-- a tree with the registry and the counter, and `files` (path under the checkout -> text)
local function tree(name: string, files: { [string]: string }): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	write(`{dir}/z-nile/projects.toml`, fs.readFile(`{TOP}/z-nile/projects.toml`))
	write(`{dir}/z-nile/next`, "issue 100 a-b-c\nraft 100 a-b-c\n")
	for path, text in files do
		write(`{dir}/{path}`, text)
	end
	return dir
end
-- the blocked-* problems of a tree: "<code> <path-tail>: <message>"
local function blocked(dir: string): { string }
	local out: { string } = {}
	for _, p in audit.run(dir) do
		if string.sub(p.code, 1, 8) == "blocked-" then
			t.expect(p.level).toBe("error")
			table.insert(out, `{p.code} {p.path}: {p.message}`)
		end
	end
	table.sort(out)
	return out
end
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local ISSUES = "pickman/.tracker/issues"
local RAFTS = "pickman/.tracker/rafts"

return t.spec("c0250 audit: the blocked invariants", function(it)
	it("a blocked item with a reason and an unresolved note that parses is clean", function()
		local dir = tree("clean", {
			[`{ISSUES}/c0010/c0010.md`] = doc("c0010", "status: blocked-a-b-c\nblocked: red-gate\n"),
			[`{ISSUES}/c0010/escalation.md`] = NOTE,
			-- a raft's blocked members are covered by the raft's note
			[`{RAFTS}/R0010/R0010.md`] = doc(
				"R0010",
				"issues: [c0020]\nstatus: blocked-a-b-c\nblocked: red-gate\n"
			),
			[`{RAFTS}/R0010/escalation.md`] = NOTE,
			[`{ISSUES}/c0020/c0020.md`] = doc(
				"c0020",
				"raft: R0010\nstatus: blocked-a-b-c\nblocked: red-gate\n"
			),
			[`{ISSUES}/c0030/c0030.md`] = doc("c0030", "status: new-a-b-c\n"),
		})
		t.expect(blocked(dir)).toEqual({})
	end)

	it("a blocked item without blocked: names ./zn block, which sets it and re-files the note", function()
		local dir = tree("no-reason", {
			[`{ISSUES}/c0010/c0010.md`] = doc("c0010", "status: blocked-a-b-c\n"),
			[`{ISSUES}/c0010/escalation.md`] = NOTE,
		})
		local found = blocked(dir)
		t.expect(#found).toBe(1)
		t.expect(has(found[1], "blocked-no-reason")).toBe(true)
		t.expect(has(found[1], "c0010 is blocked without a blocked: line: ./zn block c0010 <reason>"))
			.toBe(true)
	end)

	it("a blocked item without a readable unresolved note names ./zn block, which re-files it", function()
		local dir = tree("no-note", {
			[`{ISSUES}/c0010/c0010.md`] = doc("c0010", "status: blocked-a-b-c\nblocked: red-gate\n"),
			[`{ISSUES}/c0020/c0020.md`] = doc("c0020", "status: blocked-a-b-c\nblocked: red-gate\n"),
			[`{ISSUES}/c0020/escalation.md`] = "this is not a note\n",
			[`{ISSUES}/c0030/c0030.md`] = doc("c0030", "status: blocked-a-b-c\nblocked: red-gate\n"),
			[`{ISSUES}/c0030/escalation.md`] = RESOLVED,
		})
		local found = blocked(dir)
		t.expect(#found).toBe(3)
		for _, line in found do
			t.expect(has(line, "blocked-no-note")).toBe(true)
			t.expect(has(line, "./zn block c")).toBe(true)
			t.expect(has(line, " red-gate re-files the note")).toBe(true)
		end
		t.expect(has(found[1], "c0010 is blocked but has no escalation.md")).toBe(true)
		t.expect(has(found[2], "does not parse")).toBe(true)
		t.expect(has(found[3], "has only a resolved escalation.md")).toBe(true)
	end)

	it("blocked: on an item that is not blocked is an error", function()
		local dir = tree("stray", {
			[`{ISSUES}/c0010/c0010.md`] = doc("c0010", "status: new-a-b-c\nblocked: red-gate\n"),
		})
		local found = blocked(dir)
		t.expect(#found).toBe(1)
		t.expect(has(found[1], "blocked-stray")).toBe(true)
		t.expect(has(found[1], "c0010 has blocked: red-gate but is not blocked: remove the line")).toBe(true)
	end)

	it("a reason outside the list is an error naming ./zn resolve", function()
		local dir = tree("bad-reason", {
			[`{ISSUES}/c0010/c0010.md`] = doc("c0010", "status: blocked-a-b-c\nblocked: bored\n"),
			[`{ISSUES}/c0010/escalation.md`] = NOTE,
		})
		local found = blocked(dir)
		t.expect(#found).toBe(1)
		t.expect(has(found[1], "blocked-bad-reason")).toBe(true)
		t.expect(has(found[1], "c0010's blocked: bored is not a reason (review-exhausted, design-gap"))
			.toBe(true)
		t.expect(has(found[1], "./zn resolve c0010 <decision> clears the block")).toBe(true)
	end)
end)
