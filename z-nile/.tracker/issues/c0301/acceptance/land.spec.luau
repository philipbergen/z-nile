--!strict
-- c0301: `./zn trace R0010` and `--check` on real git: a stack of a source-changing ticket, a tests-only ticket and a
-- ticket that only deletes a spec, each with an empty Judged and Observed. The layers are made by hand (no push, no gate run), so the spec is fast.
-- Fixture under .cache/c0301-trace-land.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local FAST_PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")

local ISSUES = "pickman/.tracker/issues/active"
local RAFT_DIR = "pickman/.tracker/rafts/active/R0010"
local SRC = "pickman/src/alpha.luau"
local SPEC_A = "pickman/tests/unit/alpha.spec.luau"
local SPEC_B = "pickman/tests/unit/beta.spec.luau"
local SPEC_OLD = "pickman/tests/unit/old.spec.luau"
local SPEC_GONE = "pickman/tests/unit/gone.spec.luau"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function spec(name: string, n: number): string
	return `--!strict\nlocal t = require("@tests/lib/t")\nreturn t.spec("{name}", function(it)\n\tit("{name} holds", function()\n\t\tt.expect({n}).toBe({n})\n\tend)\nend)\n`
end

local function ticket(id: string, title: string, touched: { string }): string
	local lines = {
		"---",
		`id: {id}`,
		"type: chore",
		`title: {title}`,
		`slug: {id}`,
		"raft: R0010",
		"depends_on: []",
		"emergent: false",
		"design: ready",
		"created: 2026-11-15",
		"status: active-quiet-copper-falcon",
		"---",
		"",
		`# {id}: {title}`,
		"",
		"## Problem",
		`{title} is wrong.`,
		"",
		"## Solution",
		`- Fix {title}.`,
		"",
		"## Design",
		`The {title} design line.`,
		"",
		"### Touched modules",
	}
	for _, p in touched do
		table.insert(lines, `- \`{p}\``)
	end
	for _, l in
		{
			"",
			"### Affected specs",
			"none",
			"",
			"## Acceptance criteria",
			"",
			"### Checked",
			`- AC1: {title} holds`,
			"",
			"### Judged",
			"<!-- Only if genuinely subjective. JCn: statement + rubric (what pass/fail looks like).",
			"     Ruled on by the adversarial code reviewer. -->",
			"None.",
			"",
			"### Observed",
			"<!-- Minimal Studio playtest steps for the human (OCn). -->",
			"None.",
			"",
			"## Implementation steps",
			"1. Do it.",
			"",
		}
	do
		table.insert(lines, l)
	end
	return table.concat(lines, "\n")
end

local function lineOf(text: string, needle: string): number
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if has(line, needle) then
			return n
		end
	end
	error(`no line has {needle}`)
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

return t.spec(
	"c0301: ./zn trace on a stack with a tests-only ticket and empty Judged and Observed",
	function(it)
		it(
			"AC3: the skeleton has no None. row, --check passes only when each code cell cites its own ticket's files, a deleted spec included, and seal.trace fills such a table",
			function()
				local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
					.. 'check "AC1: holds" true\nfinish\n'
				local docA = ticket("c0010", "alpha module", { SRC, SPEC_A })
				local docB = ticket("c0020", "beta spec", { SPEC_B, SPEC_OLD })
				local docC = ticket("c0030", "gone spec", { "tests/unit/gone.spec.luau" }) -- written from pickman's home
				local raftDoc = table.concat({
					"---",
					"id: R0010",
					"type: chore",
					"title: two-ticket stack",
					"slug: two-ticket-stack",
					"single: false",
					"issues: [c0010, c0020, c0030]",
					"design: ready",
					"created: 2026-11-15",
					"status: active-quiet-copper-falcon",
					"---",
					"",
					"# R0010: two-ticket stack",
					"",
					"## Order & dependencies",
					"c0010",
					"c0020",
					"c0030",
					"",
				}, "\n")
				local f = trackerfix.new("c0301-trace-land", {
					["z-nile/projects.toml"] = FAST_PROJECTS,
					[`{ISSUES}/c0010/c0010.md`] = docA,
					[`{ISSUES}/c0010/check.sh`] = CHECK,
					[`{ISSUES}/c0020/c0020.md`] = docB,
					[`{ISSUES}/c0020/check.sh`] = CHECK,
					[`{ISSUES}/c0030/c0030.md`] = docC,
					[`{ISSUES}/c0030/check.sh`] = CHECK,
					[`{RAFT_DIR}/R0010.md`] = raftDoc,
					[SPEC_GONE] = spec("gone", 1),
					[SPEC_B] = spec("beta", 1),
					[SPEC_OLD] = spec("old", 1),
				})
				local dir = f.main
				local function git(args: { string }): string
					return fixture.git(dir, args)
				end

				-- layer 1, c0010: a source file and its spec; layer 2, c0020: only a spec file it already had
				git({ "checkout", "-q", "-b", "R0010/1/c0010" })
				write(dir, SRC, "--!strict\nreturn { alpha = 1 }\n")
				write(dir, SPEC_A, spec("alpha", 1))
				git({ "add", "-A" })
				git({ "commit", "-qm", "c0010: alpha module" })
				git({ "checkout", "-q", "-b", "R0010/2/c0020" })
				write(dir, SPEC_B, spec("beta", 2))
				git({ "add", "-A" })
				git({ "commit", "-qm", "c0020: beta spec" })
				-- layer 3, c0030: only deletes a spec file. gone.spec and alpha.spec (added by layer 1) differ in one word, so
				-- `git diff --name-only` pairs them as a rename and names only alpha.spec: the deleted spec must come from a
				-- list that does not pair renames
				git({ "checkout", "-q", "-b", "R0010/3/c0030" })
				git({ "rm", "-q", SPEC_GONE })
				git({ "commit", "-qm", "c0030: gone spec" })
				local top = git({ "rev-parse", "HEAD" })

				local skel = trackerfix.tr(f, dir, { "trace", "R0010" })
				t.expect(skel.ok).toBe(true)
				t.expect(has(skel.stdout, `Commit: {top}`)).toBe(true)
				t.expect(has(skel.stdout, "| c0010:AC1: alpha module holds |")).toBe(true)
				t.expect(has(skel.stdout, "| c0020:AC1: beta spec holds |")).toBe(true)
				t.expect(has(skel.stdout, "| c0030:AC1: gone spec holds |")).toBe(true)
				t.expect(has(skel.stdout, "None.")).toBe(false)
				t.expect(has(skel.stdout, ":AC2")).toBe(false)
				t.expect(has(skel.stdout, `| {SRC} |  |`)).toBe(true)
				t.expect(has(skel.stdout, `| {SPEC_B} |`)).toBe(false)

				local designA = `{ISSUES}/c0010/c0010.md:{lineOf(docA, "design line")}`
				local designB = `{ISSUES}/c0020/c0020.md:{lineOf(docB, "design line")}`
				local testA = `{ISSUES}/c0010/check.sh:2`
				local testB = `{ISSUES}/c0020/check.sh:2`
				local designC = `{ISSUES}/c0030/c0030.md:{lineOf(docC, "design line")}`
				local testC = `{ISSUES}/c0030/check.sh:2`
				-- `codes` maps a row's claim to its code cell; `extra` is one more row
				local function tableWith(codes: { [string]: string }, extra: string?): string
					local rows = {
						"# Trace: R0010",
						"",
						`Commit: {top}`,
						"",
						"## Claims",
						"",
						"| claim | design | test | code |",
						"|---|---|---|---|",
					}
					for _, key in { "P1", "S1", "AC1" } do
						table.insert(
							rows,
							`| c0010:{key} | {designA} | {testA} | {codes[`c0010:{key}`] or `{SRC}:2`} |`
						)
					end
					for _, key in { "P1", "S1", "AC1" } do
						table.insert(
							rows,
							`| c0020:{key} | {designB} | {testB} | {codes[`c0020:{key}`] or `{SPEC_B}:5`} |`
						)
					end
					for _, key in { "P1", "S1", "AC1" } do
						table.insert(
							rows,
							`| c0030:{key} | {designC} | {testC} | {codes[`c0030:{key}`] or `{SPEC_GONE}:5`} |`
						)
					end
					if extra then
						table.insert(rows, extra)
					end
					for _, l in
						{
							"",
							"## Source files",
							"",
							"| file | claims |",
							"|---|---|",
							`| {SRC} | c0010:P1, c0010:S1, c0010:AC1 |`,
							"",
						}
					do
						table.insert(rows, l)
					end
					return table.concat(rows, "\n")
				end
				local tracePath = `{RAFT_DIR}/trace.md`
				write(dir, tracePath, tableWith({}))
				git({ "add", tracePath })
				git({ "commit", "-qm", "R0010: trace" })

				local pass = trackerfix.tr(f, dir, { "trace", "R0010", "--check" })
				t.expect(pass.stderr).toBe("")
				t.expect(pass.ok).toBe(true)
				t.expect(has(pass.stdout, "ok: R0010")).toBe(true)

				-- one table with a wrong code cell in five rows, written over the committed one (the check reads the worktree
				-- at the top layer's tip): each wrong row is named, and the rows left as they were are not
				write(
					dir,
					tracePath,
					tableWith({
						["c0010:P1"] = `{SPEC_A}:5`, -- a source-changing ticket cites its spec
						["c0020:P1"] = `{SRC}:2`, -- the tests-only ticket cites the other ticket's source
						["c0020:S1"] = `{SPEC_OLD}:5`, -- in its Touched modules, not changed by the stack
						["c0020:AC1"] = `{SPEC_A}:5`, -- changed by the stack, not by its layer, not in its Touched modules
						["c0030:P1"] = `{SPEC_GONE}:99`, -- the deleted spec had 7 lines on main
					}, `| c0020:AC2: None. | {designB} | {testB} | {SPEC_B}:5 |`)
				)
				local fail = trackerfix.tr(f, dir, { "trace", "R0010", "--check" })
				t.expect(fail.ok).toBe(false)
				local findings: { string } = {}
				for line in string.gmatch(fail.stderr, "[^\n]+") do
					table.insert(findings, line)
				end
				table.sort(findings)
				t.expect(findings).toEqual({
					`row c0010:P1, code: {SPEC_A} is a spec file, not a source file this stack changed`,
					`row c0020:AC1, code: {SPEC_A} is neither changed by ticket c0020's layer nor in its Touched modules`,
					"row c0020:AC2, claim: unknown claim c0020:AC2",
					`row c0020:P1, code: ticket c0020 changed no source file; {SRC} is not a spec file it touched`,
					`row c0020:S1, code: {SPEC_OLD} was not changed by this stack`,
					`row c0030:P1, code: {SPEC_GONE}:99 does not exist at the stack's base (the stack deleted it)`,
				})

				-- the fixtures' table filler, seal.trace, cites a tests-only ticket's own spec, so its table passes too
				write(dir, tracePath, tableWith({}))
				seal.trace(dir, "R0010")
				local sealed = trackerfix.tr(f, dir, { "trace", "R0010", "--check" })
				t.expect(sealed.stderr).toBe("")
				t.expect(sealed.ok).toBe(true)
				local table2 = fs.readFile(`{dir}/{tracePath}`)
				local c0020Rows = 0
				for line in string.gmatch(table2, "[^\n]+") do
					if string.sub(line, 1, 8) == "| c0020:" then
						c0020Rows += 1
						t.expect(string.sub(line, -(#SPEC_B + 4))).toBe(`{SPEC_B}:1 |`)
					end
				end
				t.expect(c0020Rows).toBe(3)
				local c0030Rows = 0
				for line in string.gmatch(table2, "[^\n]+") do
					if string.sub(line, 1, 8) == "| c0030:" then
						c0030Rows += 1
						t.expect(string.sub(line, -(#SPEC_GONE + 4))).toBe(`{SPEC_GONE}:1 |`)
					end
				end
				t.expect(c0030Rows).toBe(3)
			end
		)
	end
)
