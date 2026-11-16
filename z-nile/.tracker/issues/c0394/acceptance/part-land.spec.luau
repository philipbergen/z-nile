--!strict
-- c0394 AC2 to AC8: an added issue waits for the user's approval inside the raft that found it, the rest of the raft
-- lands as a part, and the raft stays in active/ until the added issue is approved (then a second part lands it) or
-- rejected (then the raft closes). Driven through ./zn in a real-git fixture under .cache/c0394-part-land (a bare
-- origin, a main checkout and one worktree per raft, a gh stub on PATH), as tests/tooling/stack-land.spec.luau does.
--   R0010: lands in part, then waits (work next, done refused), then the issue is approved and a second part lands it
--   R0020: lands in part, stop refuses, reject needs a not-worth-doing lesson, then done closes the raft
--   R0030: has no added issue and lands whole
-- Approving and rejecting are the human's commands: they run under `script`, which gives them a terminal.
-- The fixture builds an added issue the way the tool should (new issue --raft --wait); when the tool does not yet make
-- it that way, the setup patches the same state in by hand, so each later case fails only for its own rule.
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
local bin, log = "", ""
local env: { [string]: string } = {}
local wt1, wt2, wt3 = "", "", ""
local addedA, addedB = "", "" -- the added issues of R0010 and R0020

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

-- Work on the due member's layer: a source file, the final review, one commit, and the finish.
local function deliver(dir: string, id: string, src: string, round: string)
	write(dir, `pickman/src/{src}.luau`, `{src}\n`)
	write(
		dir,
		`{ROOT}/rafts/active/{string.match(round, "^(R%d+)")}/final-review-{string.match(round, "(%d+)$")}.md`,
		"# Final Review\n\nVerdict: approve\n"
	)
	commitAll(dir, `{id} work`)
	zn(dir, { "finish", id })
end

-- The added issue as the tool should have made it: waits, in the raft's issues: line. Patches what is missing.
local function ensureAdded(dir: string, raft: string, id: string)
	local docPath = `{dir}/{ROOT}/issues/active/{id}/{id}.md`
	local doc = fs.readFile(docPath)
	if not has(doc, "\nwaits: approval\n") then
		doc = string.gsub(doc, "\nemergent: true\n", "\nemergent: true\nwaits: approval\n", 1)
		fs.writeFile(docPath, doc)
	end
	local raftPath = `{dir}/{ROOT}/rafts/active/{raft}/{raft}.md`
	local rd = fs.readFile(raftPath)
	local line = string.match(rd, "\nissues: %[([^\n]*)%]") or ""
	if not has(line, id) then
		fs.writeFile(raftPath, (string.gsub(rd, "\nissues: %[[^\n]*%]", `\nissues: [{line}, {id}]`, 1)))
	end
end

-- Emergent issue creation moves origin/main (the counter): put the layer back on it, as the tool tells to.
local function restacked(dir: string, raft: string)
	local branch = git(dir, { "branch", "--show-current" })
	git(dir, { "push", "-q" })
	zn(dir, { "restack", raft })
	git(dir, { "fetch", "-q", "origin" })
	git(dir, { "reset", "-q", "--hard", `origin/{branch}` })
end

-- The added issue designed to ready, with a check, a spec and no approval (a commit under its folder).
local function designAdded(dir: string, id: string)
	local base = `{dir}/{ROOT}/issues/active/{id}`
	local doc = fs.readFile(`{base}/{id}.md`)
	local front = string.match(doc, "^(%-%-%-\n.-\n%-%-%-\n)") :: string
	front = string.gsub(front, "design: %a+", "design: ready", 1)
	local body =
		`\n# {id}\n\n## Problem\nA finding.\n\n## Solution\nFix it.\n\n## Design\nGuess (prep) G1: the small way.\n\n## Acceptance criteria\n- AC1: it is fixed\n\n## Test plan\nThe spec.\n`
	fs.writeFile(`{base}/{id}.md`, front .. body)
	write(dir, `{ROOT}/issues/active/{id}/check.sh`, CHECK)
	write(dir, `{ROOT}/issues/active/{id}/acceptance/fixed.spec.luau`, "--!strict\nreturn nil\n")
end

return t.spec("c0394 a part lands and the raft waits for the added issue", function(it)
	it("sets up three readied rafts behind a local origin", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
			[`{LESSONS}/idle-finding.md`] = "---\ntitle: An idle finding is not worth doing\nwhen: build\ntags: [finding, not-worth-doing]\ncheck: Is this finding the idle kind?\n---\nIt costs more than it saves.\n",
			[`{LESSONS}/plain-note.md`] = "---\ntitle: A plain note\nwhen: build\ntags: [finding]\ncheck: Is this a plain note?\n---\nNothing more.\n",
		}
		for _, row in
			{
				{ "R0010", "alpha", "c0010" },
				{ "R0020", "beta", "c0030" },
				{ "R0030", "gamma", "c0040" },
			}
		do
			local raft, slug, id = row[1], row[2], row[3]
			seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(raft, slug, id)
			seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
			seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, slug, raft)
			seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
		end
		f = trackerfix.new("c0394-part-land", seed)
		bin, log = `{f.base}/bin`, `{f.base}/gh.log`
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
		wt1 = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt1, { "start", "R0010" })
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
	end)

	it("new issue --raft --wait writes waits, joins issues: and says tell the user", function()
		local r = tr(wt1, { "new", "issue", "c", "found-one", "--raft", "R0010", "--wait" })
		t.expect(r.ok).toBe(true)
		addedA = string.match(r.stdout, "(c%d%d%d%d)") or ""
		t.expect(addedA ~= "").toBe(true)
		t.expect(has(r.stdout, `{addedA} waits for approval in R0010: tell the user`)).toBe(true)
		local doc = fs.readFile(`{wt1}/{ROOT}/issues/active/{addedA}/{addedA}.md`)
		t.expect(has(doc, "\nwaits: approval\n")).toBe(true)
		t.expect(has(doc, "\nemergent: true\n")).toBe(true)
		local raftText = fs.readFile(`{wt1}/{ROOT}/rafts/active/R0010/R0010.md`)
		local line = string.match(raftText, "\nissues: %[([^\n]*)%]") or ""
		t.expect(has(line, "c0010")).toBe(true)
		t.expect(has(line, addedA)).toBe(true)
	end)

	it("--wait without --raft is refused", function()
		local r = tr(wt1, { "new", "issue", "c", "found-bare", "--wait" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "--wait needs --raft")).toBe(true)
	end)

	it("sets up the delivered layer and the designed added issue", function()
		-- when --wait did not make the added issue, make it the way the tool should have
		if addedA == "" then
			local made = zn(wt1, { "new", "issue", "c", "found-one", "--raft", "R0010" })
			addedA = string.match(made, "(c%d%d%d%d)") or ""
		end
		ensureAdded(wt1, "R0010", addedA)
		commitAll(wt1, "an added issue")
		restacked(wt1, "R0010")
		deliver(wt1, "c0010", "alpha", "R0010/001")
		t.expect(git(wt1, { "log", "-1", "--format=%s" })).toBe("c0010: alpha")
	end)

	it("start skips a waiting member and names approve and reject", function()
		local r = tr(wt1, { "start", "R0010" })
		local out = say(r)
		-- a start that succeeded opened a layer of the waiting member: step back so the later cases see layer 1
		if git(wt1, { "branch", "--show-current" }) ~= "R0010/1/c0010" then
			git(wt1, { "switch", "-q", "R0010/1/c0010" })
		end
		t.expect(r.ok).toBe(false)
		t.expect(has(out, `R0010 waits for the user: ./zn approve {addedA}, or ./zn reject {addedA}`))
			.toBe(true)
		t.expect(git(wt1, { "branch", "--show-current" })).toBe("R0010/1/c0010")
	end)

	it("members omits a waiting member, --all prints it", function()
		local due = tr(wt1, { "members", "R0010" })
		t.expect(due.ok).toBe(true)
		t.expect(has(due.stdout, "issues/active/c0010")).toBe(true)
		t.expect(has(due.stdout, addedA)).toBe(false)
		local all = tr(wt1, { "members", "R0010", "--all" })
		t.expect(all.ok).toBe(true)
		t.expect(has(all.stdout, "issues/active/c0010")).toBe(true)
		t.expect(has(all.stdout, `issues/active/{addedA}`)).toBe(true)
	end)

	it("a commit under the waiting member's folder keeps the layer finished", function()
		designAdded(wt1, addedA)
		commitAll(wt1, `design {addedA}`)
		git(wt1, { "push", "-q" })
		-- the document, its check.sh and its acceptance specs: none of it unfinishes layer 1
		local seen = zn(wt1, { "stack", "R0010" })
		t.expect(has(seen, "1 R0010/1/c0010 c0010 finished")).toBe(true)
	end)

	it(
		"done lands the part: due members done, raft and waiting member active on origin/main, Waiting: in the binding commit",
		function()
			-- a layer left unfinished makes the trace refuse: the done below then reports it
			pcall(seal.trace, wt1, "R0010")
			local r = tr(wt1, { "done", "R0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "landed R0010 in part")).toBe(true)
			t.expect(has(r.stdout, `{addedA} waits for ./zn approve {addedA}`)).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
			t.expect(onOrigin(`{ROOT}/issues/active/{addedA}/{addedA}.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/{addedA}/{addedA}.md`)).toBe(nil)
			local bind = git(f.origin, { "log", "-1", "--format=%B", "main" })
			t.expect(has(bind, "R0010: bind c0010")).toBe(true)
			t.expect(has(bind, `Waiting: {addedA}`)).toBe(true)
			t.expect(has(bind, `Trace: {ROOT}/rafts/active/R0010/trace.md`)).toBe(true)
		end
	)

	it("audit is green after a part lands", function()
		git(f.main, { "pull", "-q", "origin", "main" })
		-- the part has landed: a member done, the raft and the waiting member still active
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/active/{addedA}/{addedA}.md`) ~= nil).toBe(true)
		local r = tr(f.main, { "audit" })
		t.expect(has(say(r), "0 errors")).toBe(true)
		t.expect(r.ok).toBe(true)
	end)

	it("done with only a waiting member is refused", function()
		local r = tr(wt1, { "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "R0010 has nothing to land")).toBe(true)
		t.expect(has(say(r), `it waits for ./zn approve {addedA}, or ./zn reject {addedA}`)).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
	end)

	it("work next says wait", function()
		local r = tr(wt1, { "work", "next", "R0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "R0010: wait")).toBe(true)
		t.expect(has(r.stdout, `R0010 waits for the user: ./zn approve {addedA}, or ./zn reject {addedA}`))
			.toBe(true)
	end)

	it("sets up R0020 landed in part with its added issue waiting", function()
		wt2 = trackerfix.trOk(f, f.main, { "worktree", "R0020" })
		zn(wt2, { "start", "R0020" })
		local made = tr(wt2, { "new", "issue", "c", "found-two", "--raft", "R0020", "--wait" })
		if not made.ok then
			made = tr(wt2, { "new", "issue", "c", "found-two", "--raft", "R0020" })
		end
		addedB = string.match(made.stdout, "(c%d%d%d%d)") or ""
		t.expect(addedB ~= "").toBe(true)
		ensureAdded(wt2, "R0020", addedB)
		commitAll(wt2, "an added issue")
		restacked(wt2, "R0020")
		deliver(wt2, "c0030", "beta", "R0020/001")
		designAdded(wt2, addedB)
		commitAll(wt2, `design {addedB}`)
		git(wt2, { "push", "-q" })
		pcall(seal.trace, wt2, "R0020")
		local landed = tr(wt2, { "done", "R0020" })
		t.expect(landed.ok).toBe(true)
	end)

	it("stop refuses a raft with a landed member", function()
		git(f.main, { "pull", "-q", "origin", "main" })
		local r = tr(f.main, { "stop", "R0020" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "R0020 has landed c0030")).toBe(true)
		t.expect(has(say(r), "it can only be done")).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
	end)

	it("reject removes the issue, needs a not-worth-doing lesson, and done closes the raft", function()
		git(wt2, { "fetch", "-q", "origin" })
		local before = git(f.origin, { "rev-parse", "main" })
		-- a lesson that does not exist, a lesson without the tag, and a member that is not waiting: all refused
		local unknown = human(wt2, { "reject", addedB, "--lesson", "no-such-lesson" })
		t.expect(unknown.ok).toBe(false)
		t.expect(has(say(unknown), "no-such-lesson")).toBe(true)
		local untagged = human(wt2, { "reject", addedB, "--lesson", "plain-note" })
		t.expect(untagged.ok).toBe(false)
		t.expect(has(say(untagged), "not-worth-doing")).toBe(true)
		local landedOne = human(wt2, { "reject", "c0030", "--lesson", "idle-finding" })
		t.expect(landedOne.ok).toBe(false)
		t.expect(has(say(landedOne), "c0030")).toBe(true)
		t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
		t.expect(onOrigin(`{ROOT}/issues/active/{addedB}/{addedB}.md`) ~= nil).toBe(true)
		-- the human's command, so a pipe without a terminal is refused too
		t.expect(tr(wt2, { "reject", addedB, "--lesson", "idle-finding" }).ok).toBe(false)
		t.expect(onOrigin(`{ROOT}/issues/active/{addedB}/{addedB}.md`) ~= nil).toBe(true)

		local rejected = human(wt2, { "reject", addedB, "--lesson", "idle-finding" })
		t.expect(rejected.ok).toBe(true)
		t.expect(has(rejected.stdout, "./zn done R0020")).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/active/{addedB}/{addedB}.md`)).toBe(nil)
		local raftLine = string.match(
			onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) or "",
			"\nissues: %[([^\n]*)%]"
		) or ""
		t.expect(has(raftLine, addedB)).toBe(false)
		t.expect(
			has(
				git(f.origin, { "log", "-1", "--format=%s", "main" }),
				`tracker: reject {addedB} (idle-finding)`
			)
		).toBe(true)

		-- nothing is due or waiting: the raft closes with no merge and no review
		local closed = tr(wt2, { "done", "R0020" })
		t.expect(closed.ok).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0020/R0020.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`)).toBe(nil)
		t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" })).toBe("tracker: close R0020")
		t.expect(git(f.origin, { "rev-list", "--merges", "--count", "-1", "main" })).toBe("0")
	end)

	it("a raft with no added issue lands whole", function()
		wt3 = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
		zn(wt3, { "start", "R0030" })
		deliver(wt3, "c0040", "gamma", "R0030/001")
		seal.trace(wt3, "R0030")
		-- no waiting member: --all prints what the plain list prints
		local plain = tr(wt3, { "members", "R0030" })
		local all = tr(wt3, { "members", "R0030", "--all" })
		t.expect(all.ok).toBe(true)
		t.expect(all.stdout).toBe(plain.stdout)
		local r = tr(wt3, { "done", "R0030" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "landed R0030")).toBe(true)
		t.expect(has(r.stdout, "in part")).toBe(false)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0030/R0030.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0030/R0030.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/done/c0040/c0040.md`) ~= nil).toBe(true)
		local bind = git(f.origin, { "log", "-1", "--format=%B", "main" })
		t.expect(has(bind, "R0030: bind c0040")).toBe(true)
		t.expect(has(bind, "Waiting:")).toBe(false)
	end)

	it("after approve, start opens the next layer on origin/main and done lands the raft", function()
		-- the human approves the added issue in a worktree off origin/main and publishes the approval
		git(f.main, { "fetch", "-q", "origin" })
		local wtA = `{f.base}/approve-wt`
		git(f.main, { "worktree", "add", "-q", "-b", "approve-added", wtA, "origin/main" })
		local approved = human(wtA, { "approve", addedA })
		t.expect(approved.ok).toBe(true)
		commitAll(wtA, `approved {addedA}`)
		git(wtA, { "push", "-q", "origin", "HEAD:main" })

		git(wt1, { "fetch", "-q", "origin" })
		-- the raft's worktree reads the approval from its working tree: bring origin/main into it
		fixture.exec(wt1, "git", { "merge", "-q", "--no-edit", "origin/main" })
		local started = tr(wt1, { "start", "R0010" })
		t.expect(started.ok).toBe(true)
		t.expect(git(wt1, { "branch", "--show-current" })).toBe(`R0010/2/{addedA}`)
		t.expect(has(fs.readFile(log), `--base main --head R0010/2/{addedA}`)).toBe(true)
		-- the second part has its own review numbers
		deliver(wt1, addedA, "added", "R0010/002")
		-- a layer left unfinished makes the trace refuse: the done below then reports it
		pcall(seal.trace, wt1, "R0010")
		local r = tr(wt1, { "done", "R0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "landed R0010")).toBe(true)
		t.expect(has(r.stdout, "in part")).toBe(false)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/done/{addedA}/{addedA}.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
	end)
end)
