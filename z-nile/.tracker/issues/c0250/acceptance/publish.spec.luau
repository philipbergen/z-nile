--!strict
-- c0250 AC14: the publish rule for a `blocked` or `resolve` commit (publish.commit's fifth argument), through
-- crafted changes against a bare origin, the way c0263's publish spec drives provenance.md. The commit keeps every
-- line of the origin text in order and may only add a Decided or Scope decision line inside `## Problem`, change the
-- status:, blocked:, design:, raft:, issues:, grouped: lines of the item, its raft's members and the Layer member,
-- create or append escalation.md, keep a resolved note as escalation-NNN.md, and change a coherence review's Grouped:
-- lines. Anything else is refused, naming the file. A fresh origin per case, under .cache/c0250-publish.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0250-publish`
local origin, work = `{base}/origin.git`, `{base}/work`

local function git(cwd: string, args: { string }): string
	local r: Result = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function identity(cwd: string)
	git(cwd, { "config", "user.name", "t" })
	git(cwd, { "config", "user.email", "t@example.invalid" })
end

local ROOT = "pickman/.tracker"
local RAFT = `{ROOT}/rafts/R0010`
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function doc(id: string, front: string, body: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\n{front}---\n\n# {id}\n\n{body}`
end
local PROBLEM = "## Problem\nThe thing is slow.\n"
local DECIDED = 'Decided with the user (2026-11-10), resolve approve: "use json"\n'
local SCOPE = 'Scope decision (user, 2026-11-10): "split it" (split into c0099)\n'
local SOLUTION = "\n## Solution\nMake it fast.\n"
local NOTE =
	'# Escalation: R0010\nItem: R0010\nReason: red-gate\nFrom: active\nLayer: c0020\nActor: human:Ann\nWhen: 2026-11-10 10:00\n\n## Question\nWhich?\n\n## What was tried\nTwice.\n\n## Open findings or error\nF1.\n\n## Options\n- retry: again (recommended)\n- abort: stop\n\n## Resume\n./zn resolve R0010 retry --answer "<your answer>"\n'
local RESOLVED = NOTE
	.. "\n## Resolution\nDecision: retry\nAnswer: none\nBy: human:Ann\nWhen: 2026-11-11 10:00\n"
local REVIEW =
	"# Coherence review\nGrouped: [c0010@aaaaaaaaaaaa, c0020@bbbbbbbbbbbb]\n\n### F1 [low]\nA note.\n"

-- the files on origin, by path
local SEED: { [string]: string } = {
	[`{ROOT}/issues/c0010/c0010.md`] = doc(
		"c0010",
		"raft: \nstatus: preparing-a-b-c\n",
		PROBLEM .. DECIDED .. SCOPE .. SOLUTION
	),
	[`{ROOT}/issues/c0020/c0020.md`] = doc(
		"c0020",
		"raft: R0010\nstatus: blocked-a-b-c\nblocked: red-gate\ndesign: ready\n",
		PROBLEM .. SOLUTION
	),
	[`{ROOT}/issues/c0030/c0030.md`] = doc(
		"c0030",
		"raft: R0099\nstatus: prepared-a-b-c\n",
		PROBLEM .. SOLUTION
	),
	[`{RAFT}/R0010.md`] = doc(
		"R0010",
		"issues: [c0020]\ngrouped: [c0020@bbbbbbbbbbbb]\nstatus: blocked-a-b-c\nblocked: red-gate\n",
		"## Theme\nT\n"
	),
	[`{RAFT}/escalation.md`] = NOTE,
	[`{RAFT}/escalation-001.md`] = RESOLVED,
	[`{RAFT}/design-review-001.md`] = REVIEW,
}

-- the commit of crafted changes: what the case replaces on origin's text, as { path = content }
local function commit(edits: { [string]: string }, creates: { [string]: string }?): (boolean, string)
	local result = publish.commit(work, function(paths, read)
		local changes: { publish.Change } = {}
		for path, content in edits do
			if not table.find(paths, path) or read(path) == nil then
				return `the case edits {path}, which is not on origin`
			end
			table.insert(changes, { path = path, content = content })
		end
		for path, content in creates or {} do
			table.insert(changes, { path = path, content = content })
		end
		return changes
	end, "tracker: crafted", 1, true)
	return result.ok, if result.ok then "" else (result :: any).reason
end

local function fresh()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(`{base}/seed`)
	git(`{base}/seed`, { "init", "-q", "-b", "main" })
	identity(`{base}/seed`)
	engine.registry(`{base}/seed`)
	for path, content in SEED do
		local dir = string.match(path, "^(.*)/[^/]+$") :: string
		fs.writeDir(`{base}/seed/{dir}`)
		fs.writeFile(`{base}/seed/{path}`, content)
	end
	git(`{base}/seed`, { "add", "-A" })
	git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
	git(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
	git(base, { "clone", "-q", origin, work })
	identity(work)
end

local function onOrigin(path: string): string
	return git(origin, { "show", `main:{path}` })
end

local function refused(edits: { [string]: string }, creates: { [string]: string }?, expect: string)
	fresh()
	local before = git(origin, { "rev-parse", "main" })
	local ok, why = commit(edits, creates)
	t.expect(ok).toBe(false)
	t.expect(has(why, expect)).toBe(true)
	t.expect(git(origin, { "rev-parse", "main" })).toBe(before) -- nothing was published
end

local C10 = `{ROOT}/issues/c0010/c0010.md`
local C20 = `{ROOT}/issues/c0020/c0020.md`
local C30 = `{ROOT}/issues/c0030/c0030.md`
local R10 = `{RAFT}/R0010.md`
-- the note a resolve of c0010 writes beside its document
local C10NOTE = { [`{ROOT}/issues/c0010/escalation.md`] = RESOLVED }

return t.spec("c0250 the publish rule of a block or resolve commit", function(it)
	it(
		"accepts the listed edits: a Decided line, the keys of the item and its member, a Resolution, a Grouped line",
		function()
			fresh()
			local item = SEED[R10]
			item = (
				string.gsub(
					item,
					"status: blocked%-a%-b%-c\nblocked: red%-gate\n",
					"status: prepared-a-b-c\n"
				)
			)
			item = (string.gsub(item, "grouped: %[c0020@bbbbbbbbbbbb%]", "grouped: [c0020@cccccccccccc]"))
			local member = SEED[C20]
			member = (
				string.gsub(
					member,
					"status: blocked%-a%-b%-c\nblocked: red%-gate\n",
					"status: prepared-a-b-c\n"
				)
			)
			member = (string.gsub(member, PROBLEM, PROBLEM .. DECIDED, 1))
			local review = (string.gsub(REVIEW, "c0020@bbbbbbbbbbbb", "c0020@cccccccccccc"))
			local ok, why = commit({
				[R10] = item,
				[C20] = member,
				[`{RAFT}/escalation.md`] = RESOLVED,
				[`{RAFT}/design-review-001.md`] = review,
			})
			t.expect(why).toBe("")
			t.expect(ok).toBe(true)
			t.expect(has(onOrigin(C20), "resolve approve")).toBe(true)
			t.expect(has(onOrigin(`{RAFT}/design-review-001.md`), "c0020@cccccccccccc")).toBe(true)
		end
	)

	it("refuses an edited Scope decision line", function()
		refused(
			{ [C10] = (string.gsub(SEED[C10], '"split it"', '"split it differently"')) },
			C10NOTE,
			`{C10}:`
		)
	end)

	it("refuses a removed Decided line", function()
		local at = string.find(SEED[C10], DECIDED, 1, true) :: number
		refused(
			{ [C10] = string.sub(SEED[C10], 1, at - 1) .. string.sub(SEED[C10], at + #DECIDED) },
			C10NOTE,
			"no other line may change or go"
		)
	end)

	it("refuses a Decided line outside the Problem", function()
		refused(
			{ [C10] = SEED[C10] .. DECIDED },
			C10NOTE,
			"only a Decided or Scope decision line inside ## Problem"
		)
		refused(
			{ [C10] = (string.gsub(SEED[C10], "Make it fast.\n", "Make it fast.\n" .. DECIDED, 1)) },
			C10NOTE,
			"inside ## Problem"
		)
	end)

	it("refuses any other added or changed line of the body", function()
		refused(
			{ [C10] = (string.gsub(SEED[C10], "The thing is slow.", "The thing is quick.", 1)) },
			C10NOTE,
			`{C10}:`
		)
		refused(
			{ [C10] = (string.gsub(SEED[C10], PROBLEM, PROBLEM .. "Some other line.\n", 1)) },
			C10NOTE,
			"inside ## Problem"
		)
	end)

	it("refuses raft: changed on an issue that is neither the item nor one of its members", function()
		refused({
			[C30] = (string.gsub(SEED[C30], "raft: R0099", "raft: ")),
			[`{RAFT}/escalation.md`] = RESOLVED,
		}, nil, "c0030 is neither the item R0010")
	end)

	it("refuses a key the role may not change: the item's raft: or title:, a member's issues:", function()
		refused({
			[R10] = (string.gsub(SEED[R10], "title: R0010", "title: other")),
			[`{RAFT}/escalation.md`] = RESOLVED,
		}, nil, "its title: line may not change here")
		refused({
			[C20] = (string.gsub(SEED[C20], "design: ready", "design: ready\nissues: [c0030]")),
			[`{RAFT}/escalation.md`] = RESOLVED,
		}, nil, "its issues: line may not change here")
	end)

	it("refuses a rewritten escalation-NNN.md", function()
		refused({
			[`{RAFT}/escalation-001.md`] = RESOLVED .. "Edited: yes\n",
			[`{RAFT}/escalation.md`] = RESOLVED,
		}, nil, "escalation-001.md")
	end)

	it("refuses an edited note body, and a second Resolution", function()
		refused(
			{ [`{RAFT}/escalation.md`] = (string.gsub(NOTE, "Which%?", "What?")) },
			nil,
			"only appended to"
		)
		refused(
			{ [`{RAFT}/escalation.md`] = NOTE .. "\nSome words.\n" },
			nil,
			"only appended to, by one ## Resolution"
		)
		refused({
			[`{RAFT}/escalation.md`] = RESOLVED
				.. "\n## Resolution\nDecision: abort\nAnswer: none\nBy: x\nWhen: y\n",
		}, nil, "only appended to")
	end)

	it("refuses a coherence review changed outside its Grouped: lines", function()
		refused({
			[`{RAFT}/design-review-001.md`] = (string.gsub(REVIEW, "A note.", "A different note.")),
			[`{RAFT}/escalation.md`] = RESOLVED,
		}, nil, "only the Grouped: lines of a coherence review")
	end)

	it("refuses a note that does not parse", function()
		refused(
			{},
			{ [`{ROOT}/issues/c0010/escalation.md`] = "this is not a note\n" },
			"not an escalation note that parses"
		)
	end)
end)
