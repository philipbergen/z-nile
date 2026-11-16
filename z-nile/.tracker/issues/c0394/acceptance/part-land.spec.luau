--!strict
-- c0394 AC2 to AC9: an added issue is placed in the raft's order, nothing lands above a waiting issue, a part lands
-- when the user has not answered yet, and the raft stays in active/ until every member has landed or been rejected.
-- Driven through ./zn in a real-git fixture under .cache/c0394-part-land (a bare origin, a main checkout, one worktree
-- per raft and a gh stub on PATH), as tests/tooling/stack-land.spec.luau does.
--   R0010 is the user's example: it holds T1 (c0010); while T1's layer is open T2 is added in front (--before T1) and
--         T3 last, so the raft is T2, T1, T3. Nothing lands while T2 waits; T2 is approved and implemented, T1 is
--         restacked on it, T2 and T1 land in part; T3 is approved, implemented and lands the raft.
--   R0020 holds V1 and gains W in front of it: W is rejected (with a lesson), which unblocks V1, and done lands it.
--   R0030 holds X1 and gains Y last: X1 lands in part, Y is rejected, and done closes the raft with no merge.
-- Approving and rejecting are the human's commands: they run under `script`, which gives them a terminal.
-- The fixture builds an added issue the way the tool should (new issue --raft --wait --found); when the tool does not
-- yet make it that way, the setup patches the same state in by hand, so each later case fails only for its own rule.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local LESSONS = "z-nile/skills/zz-rules/lessons"
local T1 = "c0010"
local FOUND2 = "R0010 review-001 F3 high"
local FOUND3 = "R0010 c0010 layer"

local CAPTURED = table.concat({
	"## Problem",
	"The marker is missing.",
	"",
	"## Solution",
	"Store the marker.",
	"",
	"## Acceptance criteria",
	"- AC1: the marker is stored",
	"",
}, "\n")

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{issues}\n`
end

local f: trackerfix.Fixture
local log = ""
local env: { [string]: string } = {}
local wt1, wt2, wt3 = "", "", ""
local T2, T3, W, Y = "", "", "", "" -- the added issues

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function zn(dir: string, args: { string }): string
	return must(tr(dir, args), "./zn " .. table.concat(args, " "))
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

-- ./zn <args> with a terminal on stdin and stdout, as the human runs approve and reject
local function human(dir: string, args: { string }): fixture.Result
	local merged: { [string]: string } = { PATH = env.PATH, HOME = process.env.HOME or "" }
	local argv = { "-q", "/dev/null", "./zn" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "script", argv, { env = merged })
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

-- the line of ./zn stack's output that names `id`
local function stackLine(out: string, id: string): string
	for line in string.gmatch(out, "[^\n]+") do
		if has(line, id) then
			return line
		end
	end
	return ""
end

local function where(out: string, id: string): number
	return (string.find(out, id, 1, true)) or math.huge
end

-- Work on the due member's layer: a source file, the final review of this part, one commit, and the finish.
local function deliver(dir: string, raft: string, id: string, src: string, review: string)
	write(dir, `pickman/src/{src}.luau`, `{src}\n`)
	write(dir, `{ROOT}/rafts/active/{raft}/final-review-{review}.md`, "# Final Review\n\nVerdict: approve\n")
	commitAll(dir, `{id} work`)
	zn(dir, { "finish", id })
end

-- ./zn new issue c <slug> --raft <raft> --wait --found <found> [--before <id>]
local function add(dir: string, raft: string, slug: string, found: string, before: string?): fixture.Result
	local args = { "new", "issue", "c", slug, "--raft", raft, "--wait", "--found", found }
	if before then
		table.insert(args, "--before")
		table.insert(args, before)
	end
	return tr(dir, args)
end

local function idOf(r: fixture.Result): string
	return string.match(r.stdout, "(c%d%d%d%d) waits for approval")
		or string.match(r.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md")
		or ""
end

-- Emergent issue creation moves origin/main (the counter): put the layer back on it, as the tool tells to.
local function restacked(dir: string, raft: string)
	local branch = git(dir, { "branch", "--show-current" })
	git(dir, { "push", "-q" })
	zn(dir, { "restack", raft })
	git(dir, { "fetch", "-q", "origin" })
	git(dir, { "reset", "-q", "--hard", `origin/{branch}` })
end

-- The added issue as the tool should have made it: waits, found and before in its frontmatter, and in the raft's
-- issues: line. Patches what is missing.
local function ensureAdded(dir: string, raft: string, id: string, found: string, before: string?)
	local docPath = `{dir}/{ROOT}/issues/active/{id}/{id}.md`
	local doc = fs.readFile(docPath)
	local extra = ""
	if not has(doc, "\nwaits: approval\n") then
		extra ..= "waits: approval\n"
	end
	if not has(doc, "\nfound: ") then
		extra ..= `found: {found}\n`
	end
	if before and not has(doc, "\nbefore: ") then
		extra ..= `before: {before}\n`
	end
	if extra ~= "" then
		fs.writeFile(docPath, (string.gsub(doc, "\nemergent: true\n", `\nemergent: true\n{extra}`, 1)))
	end
	local raftPath = `{dir}/{ROOT}/rafts/active/{raft}/{raft}.md`
	local rd = fs.readFile(raftPath)
	local line = string.match(rd, "\nissues: %[([^\n]*)%]") or ""
	if not has(line, id) then
		fs.writeFile(raftPath, (string.gsub(rd, "\nissues: %[[^\n]*%]", `\nissues: [{line}, {id}]`, 1)))
	end
end

-- The added issue designed to ready, with a check and no approval (a commit under its folder).
local function designAdded(dir: string, id: string)
	local base = `{dir}/{ROOT}/issues/active/{id}`
	local doc = fs.readFile(`{base}/{id}.md`)
	local front = string.match(doc, "^(%-%-%-\n.-\n%-%-%-\n)") :: string
	front = string.gsub(front, "design: %a+", "design: ready", 1)
	local body =
		`\n# {id}\n\n## Problem\nA finding.\n\n## Solution\nFix it.\n\n## Design\nGuess (prep) G1: the small way.\n\n## Acceptance criteria\n- AC1: it is fixed\n\n## Test plan\nThe check.\n`
	fs.writeFile(`{base}/{id}.md`, front .. body)
	write(dir, `{ROOT}/issues/active/{id}/check.sh`, CHECK)
	write(dir, `{ROOT}/issues/active/{id}/acceptance/.gitkeep`, "")
end

-- Starts a raft's first layer in a new worktree.
local function begin(raft: string): string
	local dir = trackerfix.trOk(f, f.main, { "worktree", raft })
	zn(dir, { "start", raft })
	return dir
end

return t.spec("c0394 an added issue is placed in the raft, and a part lands while it waits", function(it)
	it("sets up three readied rafts behind a local origin", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
			[`{LESSONS}/idle-finding.md`] = "---\ntitle: An idle finding is not worth doing\nwhen: build\ntags: [finding, not-worth-doing]\ncheck: Is this finding the idle kind?\n---\nIt costs more than it saves.\n",
			[`{LESSONS}/plain-note.md`] = "---\ntitle: A plain note\nwhen: build\ntags: [finding]\ncheck: Is this a plain note?\n---\nNothing more.\n",
		}
		for _, row in
			{ { "R0010", "alpha", T1 }, { "R0020", "beta", "c0030" }, { "R0030", "gamma", "c0040" } }
		do
			local raft, slug, id = row[1], row[2], row[3]
			seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(raft, slug, id)
			seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
			seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, slug, raft)
			seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
		end
		f = trackerfix.new("c0394-part-land", seed)
		local bin = `{f.base}/bin`
		log = `{f.base}/gh.log`
		fs.writeDir(bin)
		local script = `#!/bin/sh\necho "$*" >> "{log}"\n`
			.. 'case "$1 $2" in\n'
			.. '  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. '  "pr view") echo body; exit 0 ;;\n'
			.. "esac\nexit 0\n"
		fs.writeFile(`{bin}/gh`, script)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		for _, raft in { "R0010", "R0020", "R0030" } do
			trackerfix.trOk(f, f.main, { "ready", raft })
		end
		wt1 = begin("R0010")
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
	end)

	it(
		"new issue --raft --wait writes waits, found and before, joins issues: and says tell the user",
		function()
			-- T2 goes in front of T1 (it breaks with T1); T3 goes last (T1 does not need it)
			local r2 = add(wt1, "R0010", "found-in-front", FOUND2, T1)
			T2 = idOf(r2)
			t.expect(T2 ~= "").toBe(true)
			-- each creation moves origin/main (the counter): commit the stub and restack before the next
			commitAll(wt1, "an added issue in front")
			restacked(wt1, "R0010")
			local r3 = add(wt1, "R0010", "found-last", FOUND3, nil)
			T3 = idOf(r3)
			t.expect(T3 ~= "").toBe(true)
			commitAll(wt1, "an added issue last")
			restacked(wt1, "R0010")

			t.expect(r2.ok).toBe(true)
			t.expect(has(r2.stdout, `{T2} waits for approval in R0010, before {T1}: tell the user`))
				.toBe(true)
			t.expect(r3.ok).toBe(true)
			t.expect(has(r3.stdout, `{T3} waits for approval in R0010, last: tell the user`)).toBe(true)
			local doc2 = fs.readFile(`{wt1}/{ROOT}/issues/active/{T2}/{T2}.md`)
			t.expect(has(doc2, "\nwaits: approval\n")).toBe(true)
			t.expect(has(doc2, `\nfound: {FOUND2}\n`)).toBe(true)
			t.expect(has(doc2, `\nbefore: {T1}\n`)).toBe(true)
			t.expect(has(doc2, "\nemergent: true\n")).toBe(true)
			local doc3 = fs.readFile(`{wt1}/{ROOT}/issues/active/{T3}/{T3}.md`)
			t.expect(has(doc3, "\nwaits: approval\n")).toBe(true)
			t.expect(has(doc3, `\nfound: {FOUND3}\n`)).toBe(true)
			t.expect(has(doc3, "\nbefore: ")).toBe(false)
			local raftText = fs.readFile(`{wt1}/{ROOT}/rafts/active/R0010/R0010.md`)
			local line = string.match(raftText, "\nissues: %[([^\n]*)%]") or ""
			for _, id in { T1, T2, T3 } do
				t.expect(has(line, id)).toBe(true)
			end
		end
	)

	it("--wait needs --raft and --found, and --before needs an unlanded member", function()
		local bare = tr(wt1, { "new", "issue", "c", "found-bare", "--wait", "--found", "R0010 c0010 layer" })
		local noFound = tr(wt1, { "new", "issue", "c", "found-unplaced", "--raft", "R0010", "--wait" })
		local noMember = add(wt1, "R0010", "found-nowhere", FOUND3, "c9999")
		-- a tool that does not refuse leaves stray issues and a moved origin: clean up so the cases below stand alone
		git(wt1, { "clean", "-fdq" })
		restacked(wt1, "R0010")
		t.expect(bare.ok).toBe(false)
		t.expect(
			has(say(bare), "--wait needs --raft <R-id>: an added issue is made in the raft that found it")
		)
			.toBe(true)
		t.expect(noFound.ok).toBe(false)
		t.expect(has(say(noFound), "--found")).toBe(true)
		t.expect(noMember.ok).toBe(false)
		t.expect(has(say(noMember), "c9999")).toBe(true)
	end)

	it("sets up the added issues as the tool should make them and delivers T1", function()
		ensureAdded(wt1, "R0010", T2, FOUND2, T1)
		ensureAdded(wt1, "R0010", T3, FOUND3, nil)
		commitAll(wt1, "the added issues")
		deliver(wt1, "R0010", T1, "alpha", "001")
		t.expect(git(wt1, { "log", "-1", "--format=%s" })).toBe("c0010: alpha")
	end)

	it("stack prints T2, T1, T3 and T1 keeps its branch and pull request", function()
		local out = zn(wt1, { "stack", "R0010" })
		t.expect(where(out, T2) < where(out, T1)).toBe(true)
		t.expect(where(out, T1) < where(out, T3)).toBe(true)
		t.expect(has(stackLine(out, T1), "R0010/1/c0010")).toBe(true)
		-- no layer was renamed or reopened: one branch, one pull request, for T1
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		local calls = fs.readFile(log)
		local _, created = string.gsub(calls, "pr create %-%-draft %-%-base main %-%-head R0010/1/c0010", "")
		t.expect(created).toBe(1)
		t.expect(has(calls, `/{T2}`)).toBe(false)
		t.expect(has(calls, `/{T3}`)).toBe(false)
	end)

	it("start opens no layer for a waiting member and work goes on above it", function()
		local r = tr(wt1, { "start", "R0010" })
		local out = say(r)
		-- a start that succeeded opened a layer of a waiting member: step back so the later cases see layer 1
		if git(wt1, { "branch", "--show-current" }) ~= "R0010/1/c0010" then
			git(wt1, { "switch", "-q", "R0010/1/c0010" })
		end
		t.expect(r.ok).toBe(false)
		t.expect(has(out, `R0010 waits for the user: ./zn approve {T2}, or ./zn reject {T2}`)).toBe(true)
		git(wt1, { "fetch", "-q", "origin" })
		local branches = git(wt1, { "branch", "-r" })
		t.expect(has(branches, `/{T2}`)).toBe(false)
		t.expect(has(branches, `/{T3}`)).toBe(false)
		-- T1 above the waiting T2 was delivered and finished while T2 waits
		t.expect(has(stackLine(zn(wt1, { "stack", "R0010" }), T1), " finished")).toBe(true)
	end)

	it("members omits the waiting issue and what is above it, --all prints every member", function()
		-- T2 waits in front of T1 and T3: nothing can land yet
		local due = tr(wt1, { "members", "R0010" })
		t.expect(due.ok).toBe(true)
		for _, id in { T1, T2, T3 } do
			t.expect(has(due.stdout, id)).toBe(false)
		end
		local all = tr(wt1, { "members", "R0010", "--all" })
		t.expect(all.ok).toBe(true)
		for _, id in { T1, T2, T3 } do
			t.expect(has(all.stdout, id)).toBe(true)
		end
	end)

	it("a commit under a waiting member's folder keeps the layer finished", function()
		designAdded(wt1, T2)
		designAdded(wt1, T3)
		commitAll(wt1, "design the added issues")
		git(wt1, { "push", "-q" })
		-- the document, its check.sh and its acceptance folder: none of it unfinishes layer 1
		local line = stackLine(zn(wt1, { "stack", "R0010" }), T1)
		t.expect(has(line, " finished")).toBe(true)
	end)

	it("done lands nothing while T2 waits in front, and names T2 and what is above it", function()
		local r = tr(wt1, { "done", "R0010" })
		t.expect(r.ok).toBe(false)
		local out = say(r)
		t.expect(has(out, "R0010 has nothing to land")).toBe(true)
		t.expect(has(out, `{T2} waits for ./zn approve {T2}, or ./zn reject {T2}`)).toBe(true)
		t.expect(has(out, "are above it")).toBe(true)
		t.expect(has(out, T1)).toBe(true)
		t.expect(has(out, T3)).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
	end)

	it(
		"after approve, T2 gets the next free layer number on origin/main and restack puts T1 on it",
		function()
			-- the user approves in the raft's worktree: while T2 is only on the layer, the approval is a commit on it
			local approved = human(wt1, { "approve", T2 })
			t.expect(approved.ok).toBe(true)
			if git(wt1, { "status", "--porcelain" }) ~= "" then
				commitAll(wt1, `approve {T2}`)
			end
			git(wt1, { "push", "-q" })
			local started = tr(wt1, { "start", "R0010" })
			t.expect(started.ok).toBe(true)
			-- T1 keeps layer 1: the new layer takes the next free number, on origin/main
			t.expect(git(wt1, { "branch", "--show-current" })).toBe(`R0010/2/{T2}`)
			t.expect(has(fs.readFile(log), `--base main --head R0010/2/{T2}`)).toBe(true)
			deliver(wt1, "R0010", T2, "second", "001")
			zn(wt1, { "restack", "R0010" })
			git(wt1, { "fetch", "-q", "origin" })
			-- T1 is rebased onto T2's layer, and its pull request now targets it
			local below = fixture.exec(
				f.main,
				"git",
				{ "merge-base", "--is-ancestor", `origin/R0010/2/{T2}`, "origin/R0010/1/c0010" }
			)
			t.expect(below.ok).toBe(true)
			t.expect(has(fs.readFile(log), `--base R0010/2/{T2}`)).toBe(true)
			-- the rebased layer is finished again, which reruns its checks on the new base
			git(wt1, { "switch", "-q", "R0010/1/c0010" })
			git(wt1, { "reset", "-q", "--hard", "origin/R0010/1/c0010" })
			zn(wt1, { "finish", T1 })
		end
	)

	it(
		"done lands the part: T2 and T1 done, the raft and T3 active on origin/main, Waiting: in the binding commit",
		function()
			-- a layer left unfinished makes the trace refuse: the done below then reports it
			pcall(seal.trace, wt1, "R0010")
			local r = tr(wt1, { "done", "R0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, `landed R0010 in part: {T3} waits for ./zn approve {T3}`)).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/{T2}/{T2}.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
			t.expect(onOrigin(`{ROOT}/issues/active/{T3}/{T3}.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/{T3}/{T3}.md`)).toBe(nil)
			local bind = git(f.origin, { "log", "-1", "--format=%B", "main" })
			local subject = string.match(bind, "^[^\n]*") or ""
			t.expect(has(subject, "R0010: bind")).toBe(true)
			t.expect(where(subject, T2) < where(subject, T1)).toBe(true) -- landed in the raft's order
			t.expect(has(bind, `Waiting: {T3}`)).toBe(true)
			t.expect(has(bind, `Trace: {ROOT}/rafts/active/R0010/trace.md`)).toBe(true)
		end
	)

	it("audit is green after a part lands", function()
		git(f.main, { "pull", "-q", "origin", "main" })
		-- the part has landed: members done, the raft and the waiting issue still active
		t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/active/{T3}/{T3}.md`) ~= nil).toBe(true)
		local r = tr(f.main, { "audit" })
		t.expect(has(say(r), "0 errors")).toBe(true)
		t.expect(r.ok).toBe(true)
	end)

	it("work next says wait when only T3 is left", function()
		local r = tr(wt1, { "work", "next", "R0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "R0010: wait")).toBe(true)
		t.expect(has(r.stdout, `R0010 waits for the user: ./zn approve {T3}, or ./zn reject {T3}`)).toBe(true)
	end)

	it("sets up R0020 with W in front of V1, and R0030 with Y last landed in part", function()
		wt2 = begin("R0020")
		local rw = add(wt2, "R0020", "found-in-front", "R0020 review-001 F1 high", "c0030")
		W = idOf(rw)
		t.expect(W ~= "").toBe(true)
		commitAll(wt2, "an added issue in front")
		restacked(wt2, "R0020")
		ensureAdded(wt2, "R0020", W, "R0020 review-001 F1 high", "c0030")
		commitAll(wt2, "the added issue")
		deliver(wt2, "R0020", "c0030", "beta", "001")
		designAdded(wt2, W)
		commitAll(wt2, `design {W}`)
		git(wt2, { "push", "-q" })

		wt3 = begin("R0030")
		local ry = add(wt3, "R0030", "found-last", "R0030 c0040 layer", nil)
		Y = idOf(ry)
		t.expect(Y ~= "").toBe(true)
		commitAll(wt3, "an added issue last")
		restacked(wt3, "R0030")
		ensureAdded(wt3, "R0030", Y, "R0030 c0040 layer", nil)
		commitAll(wt3, "the added issue")
		deliver(wt3, "R0030", "c0040", "gamma", "001")
		designAdded(wt3, Y)
		commitAll(wt3, `design {Y}`)
		git(wt3, { "push", "-q" })
		pcall(seal.trace, wt3, "R0030")
		local part = tr(wt3, { "done", "R0030" })
		t.expect(part.ok).toBe(true)
	end)

	it("stop refuses a raft with a landed member", function()
		git(f.main, { "pull", "-q", "origin", "main" })
		-- R0010 has landed T1 and T2 and T3 waits
		local r = tr(f.main, { "stop", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "R0010 has landed")).toBe(true)
		t.expect(has(say(r), T1)).toBe(true)
		t.expect(has(say(r), T2)).toBe(true)
		t.expect(has(say(r), "it can only be done")).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/{T1}/{T1}.md`) ~= nil).toBe(true)
	end)

	it("after approve, T3's layer starts on origin/main and done lands the raft", function()
		-- T3 is on origin/main now: the approval is published as for any issue
		local approved = human(wt1, { "approve", T3, "--publish" })
		t.expect(approved.ok).toBe(true)
		git(wt1, { "fetch", "-q", "origin" })
		local started = tr(wt1, { "start", "R0010" })
		t.expect(started.ok).toBe(true)
		t.expect(git(wt1, { "branch", "--show-current" })).toBe(`R0010/3/{T3}`)
		t.expect(has(fs.readFile(log), `--base main --head R0010/3/{T3}`)).toBe(true)
		-- the second part has its own review number
		deliver(wt1, "R0010", T3, "third", "002")
		pcall(seal.trace, wt1, "R0010")
		local r = tr(wt1, { "done", "R0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "landed R0010")).toBe(true)
		t.expect(has(r.stdout, "in part")).toBe(false)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`)).toBe(nil)
		for _, id in { T1, T2, T3 } do
			t.expect(onOrigin(`{ROOT}/issues/done/{id}/{id}.md`) ~= nil).toBe(true)
		end
	end)

	it(
		"reject removes a waiting issue, needs a not-worth-doing lesson, unblocks what is above it, and done closes the raft",
		function()
			-- R0020: W waits in front of V1, which is finished above it, so nothing lands
			local nothing = tr(wt2, { "members", "R0020" })
			t.expect(has(nothing.stdout, "c0030")).toBe(false)
			-- a lesson that does not exist, a lesson without the tag, and a member that does not wait: all refused
			local unknown = human(wt2, { "reject", W, "--lesson", "no-such-lesson" })
			t.expect(unknown.ok).toBe(false)
			t.expect(has(say(unknown), "no-such-lesson")).toBe(true)
			local untagged = human(wt2, { "reject", W, "--lesson", "plain-note" })
			t.expect(untagged.ok).toBe(false)
			t.expect(has(say(untagged), "not-worth-doing")).toBe(true)
			local member = human(wt2, { "reject", "c0030", "--lesson", "idle-finding" })
			t.expect(member.ok).toBe(false)
			t.expect(has(say(member), "c0030")).toBe(true)
			-- the human's command: a pipe without a terminal is refused too
			t.expect(tr(wt2, { "reject", W, "--lesson", "idle-finding" }).ok).toBe(false)
			t.expect(fs.isDir(`{wt2}/{ROOT}/issues/active/{W}`)).toBe(true)

			-- W is only on the layer: the rejection is a commit on it, and origin/main does not change
			local before = git(f.origin, { "rev-parse", "main" })
			local rejected = human(wt2, { "reject", W, "--lesson", "idle-finding" })
			t.expect(rejected.ok).toBe(true)
			t.expect(has(rejected.stdout, "./zn done R0020")).toBe(true)
			t.expect(fs.isDir(`{wt2}/{ROOT}/issues/active/{W}`)).toBe(false)
			local line = string.match(
				fs.readFile(`{wt2}/{ROOT}/rafts/active/R0020/R0020.md`),
				"\nissues: %[([^\n]*)%]"
			) or ""
			t.expect(has(line, W)).toBe(false)
			t.expect(git(wt2, { "log", "-1", "--format=%s" })).toBe(`tracker: reject {W} (idle-finding)`)
			t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
			-- V1 is no longer blocked
			t.expect(has(tr(wt2, { "members", "R0020" }).stdout, "c0030")).toBe(true)
			git(wt2, { "push", "-q" })
			pcall(seal.trace, wt2, "R0020")
			local landed = tr(wt2, { "done", "R0020" })
			t.expect(landed.ok).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0020/R0020.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/{W}/{W}.md`)).toBe(nil)

			-- R0030: X1 landed in part and Y is on origin/main, so the rejection is published; nothing is left to land
			t.expect(onOrigin(`{ROOT}/issues/active/{Y}/{Y}.md`) ~= nil).toBe(true)
			local published = human(wt3, { "reject", Y, "--lesson", "idle-finding" })
			t.expect(published.ok).toBe(true)
			t.expect(has(published.stdout, "./zn done R0030")).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/{Y}/{Y}.md`)).toBe(nil)
			t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" }))
				.toBe(`tracker: reject {Y} (idle-finding)`)
			local closed = tr(wt3, { "done", "R0030" })
			t.expect(closed.ok).toBe(true)
			-- no merge and no review: the raft moves to done/ in one published tracker commit
			t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" })).toBe("tracker: close R0030")
			t.expect(git(f.origin, { "rev-list", "--merges", "--count", "-1", "main" })).toBe("0")
			t.expect(onOrigin(`{ROOT}/rafts/done/R0030/R0030.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0030/R0030.md`)).toBe(nil)
		end
	)
end)
