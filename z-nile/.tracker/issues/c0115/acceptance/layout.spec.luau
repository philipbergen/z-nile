--!strict
-- c0115 AC3: the eleven old skills are renamed, not copied: the pipeline is z-ticket, z-design, z-ready, z-run
-- (launch-raft) and z-stop, the skills called from inside a step are zz-execute (execute-raft), zz-review, zz-rules,
-- zz-arch, zz-test and zz-stats, all in z-nile/skills/; pickman's own are pickman-arch and pickman-test in pickman/skills/. No old
-- folder is left anywhere, .claude/skills holds one committed link (mode 120000) per skill folder and nothing
-- else, the old architecture lessons are zz-arch's, .claude/README.md is gone, and z-design
-- has its three checklists. Reads the real tree only (fs, git ls-files, git show).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local OLD = {
	"make-issue",
	"ticket-prep",
	"ready-raft",
	"launch-raft",
	"execute-raft",
	"stop-raft",
	"review",
	"tracker",
	"architecture",
	"testing",
	"metrics",
}
local ZNILE = {
	"z-ticket",
	"z-design",
	"z-ready",
	"z-run",
	"zz-execute",
	"z-stop",
	"zz-review",
	"zz-rules",
	"zz-arch",
	"zz-test",
	"zz-stats",
}
local PICKMAN = { "pickman-arch", "pickman-test" }

local function git(args: { string }): string
	local r = process.exec("git", args)
	if not r.ok then
		error(`git {table.concat(args, " ")}: {r.stderr}`, 2)
	end
	return r.stdout
end
local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function folders(base: string): { string }
	local out = {}
	for _, name in fs.readDir(base) do
		if fs.isDir(`{base}/{name}`) then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end
local function sorted(list: { string }): { string }
	local c = table.clone(list)
	table.sort(c)
	return c
end
local function frontName(text: string): string?
	return string.match(text, "^%-%-%-\nname: ([^\n]+)\n")
end

return t.spec("c0115 the skills are renamed and live in their projects' folders", function(it)
	it(
		"z-nile/skills holds exactly the ten z- and zz- skills, each a SKILL.md named for its folder",
		function()
			t.expect(folders("z-nile/skills")).toEqual(sorted(ZNILE))
			for _, name in ZNILE do
				local path = `z-nile/skills/{name}/SKILL.md`
				t.expect(fs.isFile(path)).toBe(true)
				t.expect(frontName(fs.readFile(path))).toBe(name)
				t.expect(git({ "ls-files", "--", path })).toBe(path .. "\n")
			end
		end
	)

	it("pickman/skills holds pickman-arch and pickman-test", function()
		for _, name in PICKMAN do
			local path = `pickman/skills/{name}/SKILL.md`
			t.expect(frontName(fs.readFile(path))).toBe(name)
			t.expect(git({ "ls-files", "--", path })).toBe(path .. "\n")
		end
	end)

	it("no old skill folder is left, tracked or not", function()
		for _, old in OLD do
			for _, base in { "z-nile/skills", "pickman/skills", ".claude/skills" } do
				t.expect(fs.isDir(`{base}/{old}`)).toBe(false)
			end
			t.expect(git({
				"ls-files",
				"--",
				`.claude/skills/{old}`,
				`z-nile/skills/{old}`,
				`pickman/skills/{old}`,
			})).toBe("")
		end
	end)

	it(".claude/skills tracks one relative link per skill folder and nothing else", function()
		local links: { string } = {}
		local others: { string } = {}
		for _, line in lines(git({ "ls-files", "-s", "--", ".claude" })) do
			local mode, path = string.match(line, "^(%d+) %x+ %d+\t(.+)$")
			if mode == "120000" and string.match(path :: string, "^%.claude/skills/[^/]+$") then
				local name = string.match(path :: string, "[^/]+$") :: string
				table.insert(links, name)
				local base = if fs.isDir(`pickman/skills/{name}`) then "pickman" else "z-nile"
				t.expect(git({ "show", `HEAD:{path}` })).toBe(`../../{base}/skills/{name}`)
			elseif string.sub(path :: string, 1, #".claude/skills/") == ".claude/skills/" then
				table.insert(others, path :: string)
			end
		end
		local all = folders("z-nile/skills")
		for _, n in folders("pickman/skills") do
			table.insert(all, n)
		end
		t.expect(#all >= #ZNILE + #PICKMAN).toBe(true)
		t.expect(sorted(links)).toEqual(sorted(all))
		t.expect(others).toEqual({})
	end)

	it(
		"launch-raft became z-run and execute-raft zz-execute, two skills; .claude/README.md is gone",
		function()
			local run = fs.readFile("z-nile/skills/z-run/SKILL.md")
			local exec = fs.readFile("z-nile/skills/zz-execute/SKILL.md")
			t.expect(string.find(run, "./zn prompt <R> --path", 1, true) ~= nil).toBe(true)
			t.expect((string.find(run, "\n## Phase 0", 1, true))).toBe(nil) -- the protocol is not in z-run
			t.expect(string.find(exec, "\n## Phase 0", 1, true) ~= nil).toBe(true)
			t.expect((string.find(exec, "./zn prompt <R> --path", 1, true))).toBe(nil) -- nor the launch in zz-execute
			t.expect(fs.isFile(".claude/README.md")).toBe(false)
			t.expect(git({ "ls-files", "--", ".claude/README.md" })).toBe("")
		end
	)

	it("the old architecture lessons are zz-arch's", function()
		for _, slug in
			{
				"guards-trust-only-origin",
				"lock-reads-live-state",
				"one-reader-per-format",
				"parsers-refuse-ambiguity",
			}
		do
			t.expect(fs.isFile(`z-nile/skills/zz-arch/lessons/{slug}.md`)).toBe(true)
		end
	end)

	it("z-design has a feature, a defect and a chore checklist", function()
		for _, kind in { "feature", "defect", "chore" } do
			local text = fs.readFile(`z-nile/skills/z-design/checklists/{kind}.md`)
			t.expect(string.sub(text, 1, #`# Design checklist: {kind}\n`))
				.toBe(`# Design checklist: {kind}\n`)
			local items = 0
			for _ in string.gmatch(text, "\n%- %*%*") do
				items += 1
			end
			t.expect(items >= 5).toBe(true)
		end
	end)
end)
