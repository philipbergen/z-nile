--!strict
-- c0306 AC3 to AC6 and AC8: the real ./zn commands judge the reviews of a marked item and refuse the rest. Real git in
-- a fixture under .cache: a bare origin whose path contains github.com, a prep worktree, a gh stub, and the tracker's own
-- commands (so the claim, the carried move to prepared, ready, work next, spend and commit run as they do). The cases
-- build on each other in order; every case has its own item, because a move is consumed by the command that makes it.
--   issues  c0110 AC3 claim (no review)   c0120 AC3 claim (a design review exists)   c0160 and c0161 AC3 new raft
--           c0130..c0139 AC4 marked   c0150 and c0151 AC4 unmarked   c0152 AC4 marked, no review
--           c0170..c0175 AC8 spend
--   rafts   R0040..R0044 AC5 (ready and work next)
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftplan = require("@znile/engine/raftplan")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARING = "preparing-quiet-copper-falcon"
local PREPARED = "prepared-quiet-copper-falcon"
local NEW = "new-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

-- a terminal: no agent marker is set (an empty variable is not set to the hint)
local TERMINAL: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

local function issue(id: string, status: string, raft: string, design: string, marked: boolean): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: {design}\n{if marked
		then "reviews: judged\n"
		else ""}rank: 7\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nThe thing is slow.\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n`
end

local function raftDoc(id: string, status: string, issues: string, grouped: string?, marked: boolean): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\n{if grouped
		then `grouped: {grouped}\n`
		else ""}design: ready\n{if marked then "reviews: judged\n" else ""}rank: 3\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Theme\nThe {id} theme.\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n`
end

-- a review file: its record (the tool's two lines) when a model is given, then the review
local function review(model: string?, effort: string?, extra: string?): string
	local head = if model then `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}` else ""
	return `{head}# Review 001: x (design mode)\nInputs: the design\n{extra or ""}\nVerdict: approve\n`
end

local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
exit 0
]=]

local f: trackerfix.Fixture
local inHome = false -- the case that reads a session runs ./zn with the fixture's home
local env: { [string]: string } = {}
local prep = ""
local log = ""

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function zn(dir: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local out: { [string]: string } = table.clone(env)
	for k, v in TERMINAL do
		out[k] = v
	end
	local more: { [string]: string } = extra or {}
	for k, v in more do
		out[k] = v
	end
	if inHome then
		out.HOME = `{f.base}/home`
	end
	return fixture.exec(dir, "./zn", args, { env = out })
end

local function znOk(dir: string, args: { string }, extra: { [string]: string }?): string
	local r = zn(dir, args, extra)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function originFile(path: string): string?
	local r = fixture.exec(f.main, "git", { "show", `origin/main:{path}` })
	return if r.ok then r.stdout else nil
end

local function fetch()
	git(f.main, { "fetch", "-q", "origin" })
end

local function head(): string
	return git(f.main, { "rev-parse", "origin/main" })
end

local function front(text: string?, key: string): string?
	return if text
		then string.match(
			"\n" .. (string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or "") .. "\n",
			`\n{key}: ?([^\n]*)\n`
		)
		else nil
end

local function docOf(id: string): string
	return `{ROOT}/issues/{id}/{id}.md`
end

local function localFront(dir: string, id: string, key: string): string?
	return front(fs.readFile(`{dir}/{docOf(id)}`), key)
end

-- the design-review-001.md of an issue in the prep worktree
local function reviewIn(id: string, text: string)
	write(prep, `{ROOT}/issues/{id}/design-review-001.md`, text)
end

-- AC4: the carried move to prepared. Returns the command's result; the local status says whether it moved.
local function prepared(id: string): fixture.Result
	return zn(prep, { "status", id, "prepared" })
end

local function moved(id: string): boolean
	return string.sub(localFront(prep, id, "status") or "", 1, 9) == "prepared-"
end

local OPUS = review("claude-opus-5-5", "high")
local SONNET = review("claude-sonnet-5-5", "high")

return t.spec("c0306 commands refuse a review off the review models", function(it)
	it(
		"sets up a github-shaped origin with issues and prepared rafts, a prep worktree and a gh that records",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["z-nile/next"] = "issue 400 quiet-copper-falcon\nraft 70 quiet-copper-falcon\n",
			}
			local function item(id: string, text: string)
				seed[`{ROOT}/issues/{id}/{id}.md`] = text
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			end
			-- the claims, and the issues for a new raft (all new)
			item("c0110", issue("c0110", NEW, "", "draft", false))
			item("c0120", issue("c0120", NEW, "", "draft", false))
			seed[`{ROOT}/issues/c0120/design-review-001.md`] = SONNET
			item("c0160", issue("c0160", NEW, "", "draft", false))
			item("c0161", issue("c0161", NEW, "", "draft", false))
			item("c0180", issue("c0180", NEW, "", "draft", false))
			item("c0181", issue("c0181", NEW, "", "draft", false))
			-- the carried move to prepared: preparing issues with design: ready, marked or not
			for _, id in
				{
					"c0130",
					"c0131",
					"c0132",
					"c0133",
					"c0134",
					"c0135",
					"c0136",
					"c0137",
					"c0138",
					"c0139",
					"c0152",
					"c0170",
				}
			do
				item(id, issue(id, PREPARING, "", "ready", true))
			end
			for _, id in { "c0150", "c0151", "c0171", "c0172", "c0173", "c0174", "c0175", "c0176" } do
				item(id, issue(id, PREPARING, "", "ready", false))
			end
			-- prepared rafts with the record z-raft wrote: each member's design hash and the coherence review quoting it
			local function preparedRaft(
				raft: string,
				member: string,
				marked: boolean,
				coherence: string,
				memberReview: string?
			)
				local doc = issue(member, PREPARED, raft, "ready", marked)
				local files: { [string]: string } =
					{ [`{member}.md`] = doc, ["check.sh"] = CHECK, ["acceptance/.gitkeep"] = "" }
				if memberReview then
					files["design-review-001.md"] = memberReview
				end
				local grouped = `[{member}@{raftplan.recordHash(member, files)}]`
				seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(raft, PREPARED, member, grouped, marked)
				seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
				seed[`{ROOT}/rafts/{raft}/design-review-001.md`] = (
					string.gsub(coherence, "\nVerdict", `\nGrouped: {grouped}\nVerdict`, 1)
				)
				item(member, doc)
				seed[`{ROOT}/issues/{member}/acceptance/.gitkeep`] = ""
				if memberReview then
					seed[`{ROOT}/issues/{member}/design-review-001.md`] = memberReview
				end
			end
			preparedRaft("R0040", "c0240", true, SONNET, OPUS) -- the coherence review is off the review models
			preparedRaft("R0041", "c0241", true, OPUS, SONNET) -- a member's design review is
			preparedRaft("R0042", "c0242", true, review(nil, nil), OPUS) -- the coherence review records none
			preparedRaft("R0043", "c0243", false, SONNET, SONNET) -- unmarked: any review passes
			preparedRaft("R0044", "c0244", true, OPUS, OPUS) -- marked and fine
			-- a raft in rafting (claimed, preparing) whose members z-raft grouped: its coherence review is off the review models
			do
				local grouped: { string } = {}
				for _, member in { "c0290", "c0291" } do
					local doc = issue(member, PREPARED, "", "ready", false)
					item(member, doc)
					seed[`{ROOT}/issues/{member}/acceptance/.gitkeep`] = ""
					local files =
						{ [`{member}.md`] = doc, ["check.sh"] = CHECK, ["acceptance/.gitkeep"] = "" }
					table.insert(grouped, `{member}@{raftplan.recordHash(member, files)}`)
				end
				local record = `[{table.concat(grouped, ", ")}]`
				seed[`{ROOT}/rafts/R0200/R0200.md`] =
					raftDoc("R0200", PREPARING, "c0290, c0291", record, true)
				seed[`{ROOT}/rafts/R0200/check.sh`] = CHECK
				seed[`{ROOT}/rafts/R0200/design-review-001.md`] = (
					string.gsub(SONNET, "\nVerdict", `\nGrouped: {record}\nVerdict`, 1)
				)
			end
			f = trackerfix.new("c0306-commands-github.com", seed)
			local bin = `{f.base}/bin`
			log = `{f.base}/gh.log`
			fs.writeDir(bin)
			fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@LOG@", log)))
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			-- a home of its own for the one case that reads a session; rokit's shims (which find lune) read ~/.rokit
			fs.writeDir(`{f.base}/home`)
			process.exec("ln", { "-s", `{process.env.HOME or ""}/.rokit`, `{f.base}/home/.rokit` })
			prep = `{f.base}/wt-prep`
			git(f.main, { "worktree", "add", "-q", "-b", "prep-c0306", prep, "origin/main" })
		end
	)

	it(
		"AC3: status preparing writes reviews: judged into an issue with no design review, in the claim's one commit",
		function()
			fetch()
			local before = head()
			znOk(prep, { "status", "c0110", "preparing" })
			fetch()
			t.expect(front(originFile(docOf("c0110")), "reviews")).toBe("judged")
			t.expect(string.sub(front(originFile(docOf("c0110")), "status") or "", 1, 10)).toBe("preparing-")
			-- one commit, which touches the one document
			t.expect(git(f.main, { "log", "--format=%s", `{before}..origin/main` }))
				.toBe("tracker: c0110 preparing")
			t.expect(git(f.main, { "show", "--no-renames", "--name-status", "--format=", "origin/main" }))
				.toBe(`M\t{docOf("c0110")}`)
		end
	)

	it("AC3: status preparing leaves an issue that has a design review unmarked", function()
		znOk(prep, { "status", "c0120", "preparing" })
		fetch()
		t.expect(front(originFile(docOf("c0120")), "reviews")).toBe(nil)
		t.expect(string.sub(front(originFile(docOf("c0120")), "status") or "", 1, 10)).toBe("preparing-")
	end)

	it("AC3: new raft writes reviews: judged into the raft and not into its members", function()
		local out = znOk(prep, { "new", "raft", "chore", "demo", "c0160", "c0161", "--project", "pickman" })
		local raft = string.match(out, "(R%d%d%d%d)") :: string
		fetch()
		t.expect(front(originFile(`{ROOT}/rafts/{raft}/{raft}.md`), "reviews")).toBe("judged")
		t.expect(front(originFile(docOf("c0160")), "reviews")).toBe(nil)
		t.expect(front(originFile(docOf("c0161")), "reviews")).toBe(nil)
	end)

	it("AC3: the local new raft writes reviews: judged into the raft it makes", function()
		local out = znOk(
			prep,
			{ "new", "raft", "chore", "local", "c0180", "c0181", "--project", "pickman" },
			{ PICKMAN_PUBLISH = "0" }
		)
		local path = string.match(out, "(%S+%.md)") :: string
		t.expect(string.match(path, "/rafts/R%d%d%d%d/R%d%d%d%d%.md$") ~= nil).toBe(true)
		t.expect(front(fs.readFile(`{prep}/{path}`), "reviews")).toBe("judged")
		t.expect(front(fs.readFile(`{prep}/{docOf("c0180")}`), "reviews")).toBe(nil)
		t.expect(front(fs.readFile(`{prep}/{docOf("c0181")}`), "reviews")).toBe(nil)
	end)

	it(
		"AC4: status prepared refuses a marked issue whose design review records a model that is not a review model, naming the file, the model and the four kinds",
		function()
			reviewIn("c0130", SONNET)
			local r = prepared("c0130")
			t.expect(r.ok).toBe(false)
			local said = say(r)
			t.expect(has(said, "c0130")).toBe(true)
			t.expect(has(said, "design-review-001.md")).toBe(true)
			t.expect(has(said, "claude-sonnet-5-5")).toBe(true)
			for _, kind in { "claude-opus-", "claude-fable-", "kimi-code-k3", "grok-" } do
				t.expect(has(said, kind)).toBe(true)
			end
			t.expect(moved("c0130")).toBe(false)
		end
	)

	it("AC4: status prepared refuses a marked issue whose design review records no Model: line", function()
		reviewIn("c0131", review(nil, nil))
		local r = prepared("c0131")
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "design-review-001.md")).toBe(true)
		t.expect(has(say(r), "no `Model:` line")).toBe(true)
		t.expect(moved("c0131")).toBe(false)
	end)

	it(
		"AC4: status prepared's refusal of an off-model record names only a new round, and of a missing record also the spend that records it",
		function()
			reviewIn("c0139", SONNET)
			local off = say(prepared("c0139"))
			t.expect(has(off, "claude-sonnet-5-5")).toBe(true)
			t.expect(has(off, "./zn dispatch zz-review c0139 --mode design")).toBe(true)
			t.expect(has(off, "./zn spend")).toBe(false)
			t.expect(has(off, "code|final")).toBe(false)
			t.expect(has(off, "pull request")).toBe(false) -- the file is in this worktree
			-- c0131's design review still records no model
			local none = say(prepared("c0131"))
			t.expect(has(none, "no `Model:` line")).toBe(true)
			t.expect(has(none, "./zn dispatch zz-review c0131 --mode design")).toBe(true)
			t.expect(has(none, "./zn spend c0131 --phase design-review --note design-review-001 --model"))
				.toBe(true)
		end
	)

	it("AC4: status prepared judges every round, not only the last", function()
		reviewIn("c0132", SONNET)
		write(prep, `{ROOT}/issues/c0132/design-review-002.md`, OPUS)
		write(prep, `{ROOT}/issues/c0132/design-refute-001.md`, "- F1: refuted: no\n")
		local r = prepared("c0132")
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "design-review-001.md")).toBe(true)
		t.expect(moved("c0132")).toBe(false)
	end)

	it("AC4: status prepared passes a marked issue on each review kind", function()
		local kinds: { { string } } = {
			{ "c0133", "claude-opus-5-5[1m]", "low" },
			{ "c0134", "claude-fable-5-2", "high" },
			{ "c0135", "kimi-code-k3.2", "high" },
			{ "c0136", "grok-4.7", "xhigh" },
		}
		for _, k in kinds do
			reviewIn(k[1], review(k[2], k[3]))
			local r = prepared(k[1])
			if not r.ok then
				error(`{k[2]} was refused: {say(r)}`)
			end
			t.expect(moved(k[1])).toBe(true)
		end
	end)

	it("AC4: status prepared refuses grok- below xhigh and with no effort", function()
		reviewIn("c0137", review("grok-4.7", "high"))
		local low = prepared("c0137")
		t.expect(low.ok).toBe(false)
		t.expect(has(say(low), "grok-4.7")).toBe(true)
		reviewIn("c0138", review("grok-4.7", nil))
		local none = prepared("c0138")
		t.expect(none.ok).toBe(false)
		t.expect(moved("c0138")).toBe(false)
	end)

	it(
		"AC4: status prepared passes an unmarked issue on any review, and does not refuse a marked issue with no design review",
		function()
			reviewIn("c0150", SONNET)
			t.expect(prepared("c0150").ok).toBe(true)
			reviewIn("c0151", review(nil, nil))
			t.expect(prepared("c0151").ok).toBe(true)
			local r = prepared("c0152")
			if not r.ok then
				error(`a marked issue with no review was refused: {say(r)}`)
			end
			t.expect(moved("c0152")).toBe(true)
		end
	)

	it("AC4: status prepared on a raft does not judge its coherence review: ready does", function()
		local r = zn(prep, { "status", "R0200", "prepared" })
		if not r.ok then
			error(`a raft's own coherence review was judged at prepared: {say(r)}`)
		end
		t.expect(string.sub(front(fs.readFile(`{prep}/{ROOT}/rafts/R0200/R0200.md`), "status") or "", 1, 9))
			.toBe("prepared-")
	end)

	it(
		"AC5: ./zn ready and ./zn work next refuse a marked raft whose coherence review is off the review models",
		function()
			for _, cmd in { { "ready", "R0040" }, { "work", "next", "R0040" } } do
				local r = zn(f.main, cmd)
				local said = say(r)
				t.expect(has(said, "design-review-001.md")).toBe(true)
				t.expect(has(said, "claude-sonnet-5-5")).toBe(true)
				t.expect(has(said, "claude-opus-")).toBe(true)
				if cmd[1] == "ready" then
					t.expect(r.ok).toBe(false)
				end
			end
			fetch()
			t.expect(originFile(`{ROOT}/rafts/R0040/R0040.md`) ~= nil).toBe(true) -- still in the backlog
		end
	)

	it(
		"AC5: ./zn ready and ./zn work next refuse a marked raft whose member's design review is off the review models, naming the member",
		function()
			for _, cmd in { { "ready", "R0041" }, { "work", "next", "R0041" } } do
				local r = zn(f.main, cmd)
				local said = say(r)
				t.expect(has(said, "c0241")).toBe(true)
				t.expect(has(said, "claude-sonnet-5-5")).toBe(true)
				if cmd[1] == "ready" then
					t.expect(r.ok).toBe(false)
				end
			end
		end
	)

	it(
		"AC5: ./zn ready and ./zn work next refuse a marked raft whose coherence review records no model",
		function()
			for _, cmd in { { "ready", "R0042" }, { "work", "next", "R0042" } } do
				local r = zn(f.main, cmd)
				t.expect(has(say(r), "no `Model:` line")).toBe(true)
				if cmd[1] == "ready" then
					t.expect(r.ok).toBe(false)
				end
			end
		end
	)

	it("AC5: an unmarked raft, and a marked raft on a review model, are readied", function()
		for _, id in { "R0043", "R0044" } do
			local said = say(zn(f.main, { "work", "next", id }))
			t.expect(has(said, "not a review model")).toBe(false)
			znOk(f.main, { "ready", id })
			fetch()
			t.expect(originFile(`{ROOT}/rafts/active/{id}/{id}.md`) ~= nil).toBe(true)
		end
	end)

	-- AC8: ./zn spend --phase design-review stamps the review file it records
	local function spend(id: string, extra: { string }, env2: { [string]: string }?): fixture.Result
		local args = { "spend", id, "--phase", "design-review", "--note", "design-review-001" }
		for _, a in extra do
			table.insert(args, a)
		end
		return zn(prep, args, env2)
	end
	local function tsv(id: string): string
		local folder = `{prep}/{ROOT}/issues/{id}/spend.d`
		local out = ""
		if fs.isDir(folder) then
			for _, name in fs.readDir(folder) do
				out ..= fs.readFile(`{folder}/{name}`)
			end
		end
		return out
	end
	local function reviewOf(id: string): string
		return fs.readFile(`{prep}/{ROOT}/issues/{id}/design-review-001.md`)
	end

	it(
		"AC8: spend --phase design-review is refused without --model, naming the flag, and stamps nothing",
		function()
			reviewIn("c0170", review(nil, nil))
			local r = spend("c0170", {})
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "--model")).toBe(true)
			t.expect(reviewOf("c0170")).toBe(review(nil, nil))
			t.expect(tsv("c0170")).toBe("")
		end
	)

	it(
		"AC8: an unmarked issue's spend --phase design-review with no --model records as today and stamps nothing",
		function()
			reviewIn("c0176", review(nil, nil))
			local r = spend("c0176", {})
			if not r.ok then
				error(`spend refused an unmarked issue: {say(r)}`)
			end
			t.expect(reviewOf("c0176")).toBe(review(nil, nil))
			t.expect(tsv("c0176") ~= "").toBe(true)
		end
	)

	it(
		"AC8: spend --phase design-review --model --effort stamps the review file with both and records the model",
		function()
			local r = spend("c0170", { "--model", "claude-opus-5-5[1m]", "--effort", "xhigh" })
			if not r.ok then
				error(`spend refused: {say(r)}`)
			end
			t.expect(reviewOf("c0170"))
				.toBe("Model: claude-opus-5-5[1m]\nEffort: xhigh\n" .. review(nil, nil))
			t.expect(has(tsv("c0170"), "claude-opus-5-5[1m]")).toBe(true)
		end
	)

	it(
		"AC8: a review is recorded once: a second spend naming the same file is refused, whether the model differs or not",
		function()
			for _, model in { "claude-sonnet-5-5", "claude-opus-5-5[1m]" } do
				local r = spend("c0170", { "--model", model })
				t.expect(r.ok).toBe(false)
				t.expect(has(say(r), "already records")).toBe(true)
				t.expect(reviewOf("c0170"))
					.toBe("Model: claude-opus-5-5[1m]\nEffort: xhigh\n" .. review(nil, nil))
			end
		end
	)

	it(
		"AC8: the effort is CLAUDE_EFFORT when --effort is not typed, and the line is left out when there is neither",
		function()
			reviewIn("c0171", review(nil, nil))
			znOk(prep, {
				"spend",
				"c0171",
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
				"--model",
				"claude-opus-5-5",
			}, { CLAUDE_EFFORT = "high" })
			t.expect(reviewOf("c0171")).toBe("Model: claude-opus-5-5\nEffort: high\n" .. review(nil, nil))
			reviewIn("c0172", review(nil, nil))
			znOk(prep, {
				"spend",
				"c0172",
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
				"--model",
				"claude-opus-5-5",
			})
			t.expect(reviewOf("c0172")).toBe("Model: claude-opus-5-5\n" .. review(nil, nil))
			-- a typed --effort wins over the environment
			reviewIn("c0175", review(nil, nil))
			znOk(prep, {
				"spend",
				"c0175",
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
				"--model",
				"claude-opus-5-5",
				"--effort",
				"low",
			}, { CLAUDE_EFFORT = "high" })
			t.expect(reviewOf("c0175")).toBe("Model: claude-opus-5-5\nEffort: low\n" .. review(nil, nil))
		end
	)

	it(
		"AC8: a typed --model wins over the session's measured model, which a spend with none records",
		function()
			-- a Claude Code session of this worktree in the fixture's home, with one assistant message on claude-sonnet-5-5
			local cwd = fixture.physical(prep) :: string
			local sessions = `{f.base}/home/.claude/projects/{string.gsub(cwd, "/", "-")}`
			inHome = true
			znOk(prep, { "spend", "c0173", "--phase", "design-review", "--begin" })
			znOk(prep, { "spend", "c0174", "--phase", "deliver", "--begin" })
			local ts = (os.date("!%Y-%m-%dT%H:%M:%S") :: string) .. ".500Z" -- after the begins: inside the span
			local line = '{"type":"assistant","timestamp":"'
				.. ts
				.. '","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":10,"output_tokens":5}}}\n'
			-- spend asks for the folder of process.cwd, which Lune gives with a trailing slash: the session is filed under both names
			for _, dir in { sessions, sessions .. "-" } do
				fs.writeDir(dir)
				fs.writeFile(`{dir}/s1.jsonl`, line)
			end
			-- the premise: with no typed model the measured one is what a row records (a deliver spend needs no review file)
			znOk(prep, { "spend", "c0174", "--phase", "deliver" })
			if not has(tsv("c0174"), "claude-sonnet-5-5") then
				error(
					`the fixture session was not read: rows {tsv("c0174")}, session {sessions}, files {table.concat(
						fs.readDir(sessions),
						","
					)}`
				)
			end
			-- the typed model wins
			reviewIn("c0173", review(nil, nil))
			znOk(prep, {
				"spend",
				"c0173",
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
				"--model",
				"claude-opus-5-5",
				"--effort",
				"high",
			})
			t.expect(has(tsv("c0173"), "claude-opus-5-5")).toBe(true)
			t.expect(has(tsv("c0173"), "claude-sonnet-5-5")).toBe(false)
			t.expect(reviewOf("c0173")).toBe("Model: claude-opus-5-5\nEffort: high\n" .. review(nil, nil))
			inHome = false
		end
	)

	-- AC6: ./zn work next, on a started and finished raft, says to run ./zn done only when done would accept it
	local function finishedRaft(raft: string, member: string): string
		local out = znOk(f.main, { "worktree", raft })
		local wt =
			fixture.physical(string.match(out, "(/[^\n]*)\n?$") or `{f.main}/.worktree/{raft}`) :: string
		znOk(wt, { "start", raft })
		write(wt, `notes/{member}.txt`, "1\n2\n")
		znOk(wt, { "commit", "-m", `{member}: work`, "--issue", member })
		znOk(wt, { "finish", member })
		return wt
	end

	it(
		"AC6: work next says to run done for a raft whose reviews are on review models, and names the refusal for a marked raft whose final review is not",
		function()
			local marked = finishedRaft("R0044", "c0244")
			local dir = `{ROOT}/rafts/active/R0044`
			write(marked, `{dir}/review-001.md`, review("claude-opus-5-5", "high"))
			git(marked, { "add", "-A" })
			git(marked, { "commit", "-q", "-m", "R0044: review-001" })
			seal.trace(marked, "R0044") -- the final review is the layer review, on claude-opus-5-5
			local ok = say(zn(f.main, { "work", "next", "R0044" }))
			t.expect(has(ok, "./zn done R0044")).toBe(true)
			t.expect(has(ok, "not a review model")).toBe(false)
			-- the final review is rewritten on claude-sonnet-5-5 (the trace's presence is all work next reads)
			write(marked, `{dir}/final-review-001.md`, review("claude-sonnet-5-5", "high"))
			git(marked, { "add", "-A" })
			git(marked, { "commit", "-q", "-m", "R0044: final review on sonnet" })
			git(marked, { "push", "-q", "origin", "HEAD" })
			local refused = say(zn(f.main, { "work", "next", "R0044" }))
			t.expect(has(refused, "final-review-001.md")).toBe(true)
			t.expect(has(refused, "claude-sonnet-5-5")).toBe(true)
			t.expect(has(refused, "./zn done R0044")).toBe(false)
		end
	)

	it(
		"AC6: work next says to run done for an unmarked raft whose final review is on claude-sonnet-5-5",
		function()
			local unmarked = finishedRaft("R0043", "c0243")
			local dir = `{ROOT}/rafts/active/R0043`
			write(unmarked, `{dir}/review-001.md`, review("claude-sonnet-5-5", "high"))
			git(unmarked, { "add", "-A" })
			git(unmarked, { "commit", "-q", "-m", "R0043: review-001" })
			seal.trace(unmarked, "R0043") -- the final review is the layer review, on claude-sonnet-5-5
			local said = say(zn(f.main, { "work", "next", "R0043" }))
			t.expect(has(said, "./zn done R0043")).toBe(true)
			t.expect(has(said, "not a review model")).toBe(false)
		end
	)

	it("cleans up", function()
		git(f.main, { "worktree", "remove", "--force", prep })
		fs.removeDir(f.base)
	end)
end)
