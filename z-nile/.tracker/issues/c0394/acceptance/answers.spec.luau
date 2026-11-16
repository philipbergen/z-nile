--!strict
-- c0394 AC11: a review answer may be `dropped <lesson id>: <why>` (a medium or low finding; the lesson must exist and
-- carry the not-worth-doing tag) or `added <id>: <why>` (an added issue of this raft; a HIGH finding only when the added
-- issue is in front of the reviewed layer, or the finding is ruled under `## Open to the human`), in a layer's review,
-- a final review and a design refute, and a written `deferred <id>` is still accepted and called legacy.
-- Real git in a fixture under .cache/c0394-answers-github.com, built on c0248's layers (a layer is complete when its
-- review is settled; `./zn start` refuses the next layer until it is, so it is the probe of a layer's answers):
--   R0010 holds c0010, c0030 and c0050; added issues Y (in front of c0010) and X (last) are made on c0010's layer,
--         and Z (last) on c0030's, so a layer's answers can name a waiting issue of this raft
--   R0020 holds c0200: a final review answered with a legacy `deferred`
--   c0300 is being prepared, with a design review and refute in its folder, and c0310 is bound to it (`with: c0300`)
-- Needs c0248 (`depends_on`): until it is on main these cases fail at the first command only c0248 or c0394 has.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local PREPARING = "preparing-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local LESSONS = "z-nile/skills/zz-rules/lessons"
local FIXED = "fixed abc: ok; consequences: none"

local REVIEW = "# Review\n\n"
	.. "### F1 [high] a high finding\nEvidence: x\n\n"
	.. "### F2 [medium] a medium finding\nEvidence: y\n\n"
	.. "### F3 [low] a low finding\nEvidence: z\n\n"
	.. "Verdict: changes requested\n"

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, title: string, raft: string, status: string?, front: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\n{front or ""}status: {status or PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nThe {slug} theme.\n\n## Order & dependencies\n{issues}\n`
end

-- gh keeps each pull request's base in a file, numbered by the layer's branch: R00<r>0/<n>/... is PR <r><n>
local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
num() { echo "$1" | sed -n 's|^R00\(.\)0/\(.\)/.*|\1\2|p'; }
after() { want="$1"; shift; prev=""; for a in "$@"; do if [ "$prev" = "$want" ]; then echo "$a"; return; fi; prev="$a"; done; }
case "$1 $2" in
  "pr list") case "$*" in *number*) n=$(num "$(after --head "$@")"); [ -n "$n" ] && echo "$n" ;; esac; exit 0 ;;
  "pr create") n=$(num "$(after --head "$@")"); after --base "$@" > "@STATE@/base-$n"; echo "https://github.com/x/y/pull/$n"; exit 0 ;;
  "pr view") cat "@STATE@/base-$3" 2>/dev/null || echo main; exit 0 ;;
  "pr edit") n="$3"
    case "$*" in
      *--body-file*) cat > "@STATE@/body-$n.md" ;;
      *--base*) after --base "$@" > "@STATE@/base-$n" ;;
    esac
    exit 0 ;;
esac
exit 0
]=]

local f: trackerfix.Fixture
local log, state = "", ""
local env: { [string]: string } = {}
local wt, wtB, wtD = "", "", ""
local X, Y, Z = "", "", "" -- the added issues of R0010

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

local function work(dir: string, issueId: string, file: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{issueId} work`)
end

-- A layer's review as the reviewer writes it (no stamp), committed by the tool, which stamps it.
local function review(dir: string, issueId: string)
	local folder = zn(dir, { "find", issueId })
	local top = 0
	for _, name in fs.readDir(`{dir}/{folder}`) do
		top = math.max(top, tonumber((string.match(name, "^review%-(%d+)%.md$"))) or 0)
	end
	write(dir, `{folder}/review-{string.format("%03d", top + 1)}.md`, "# Review\n\nVerdict: approve\n")
	zn(dir, { "commit", "-m", `tracker: review {issueId}` })
	git(dir, { "push", "-q" })
end

-- The final review and the trace of one landing, committed on the layer `dir` is on after its finish. Each landing has
-- its own: the round is the newest final review not yet on origin/main, else one more than the last on it.
local function sealBind(dir: string, raftId: string, through: string?)
	local args = { "trace", raftId }
	if through then
		table.insert(args, "--through")
		table.insert(args, through)
	end
	local parsed, err = trace.parse(zn(dir, args))
	if not parsed then
		error(`trace skeleton did not parse: {err}`, 2)
	end
	local raftDir = zn(dir, { "find", raftId })
	local top, topLocal = 0, 0
	for _, name in fs.readDir(`{dir}/{raftDir}`) do
		local k = tonumber((string.match(name, "^final%-review%-(%d+)%.md$")))
		if k then
			if fixture.exec(dir, "git", { "cat-file", "-e", `origin/main:{raftDir}/{name}` }).ok then
				top = math.max(top, k)
			end
			topLocal = math.max(topLocal, k)
		end
	end
	local num = string.format("%03d", if topLocal > top then topLocal else top + 1)
	local issueDirs: { [string]: string } = {}
	local checkLines: { [string]: number } = {}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		if not issueDirs[id] then
			issueDirs[id] = zn(dir, { "find", id })
			checkLines[id] = 1
			local idx = 0
			for line in string.gmatch(fs.readFile(`{dir}/{issueDirs[id]}/check.sh`) .. "\n", "([^\n]*)\n") do
				idx += 1
				if string.match(line, "^%s*check%s+") then
					checkLines[id] = idx
					break
				end
			end
		end
	end
	local codeRef = if #parsed.sources > 0 then `{parsed.sources[1].file}:1` else "none"
	local firstClaim = if #parsed.claims > 0 then parsed.claims[1].claimId else ""
	local lines = {
		`# Trace: {raftId}`,
		"",
		`Commit: {parsed.commit}`,
		"",
		"## Claims",
		"",
		"| claim | design | test | code |",
		"|---|---|---|---|",
	}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		table.insert(
			lines,
			`| {row.rawClaim} | {issueDirs[id]}/{id}.md:1 | {issueDirs[id]}/check.sh:{checkLines[id]} | {codeRef} |`
		)
	end
	table.insert(lines, "")
	table.insert(lines, "## Source files")
	table.insert(lines, "")
	table.insert(lines, "| file | claims |")
	table.insert(lines, "|---|---|")
	for _, srow in parsed.sources do
		table.insert(lines, `| {srow.file} | {firstClaim} |`)
	end
	table.insert(lines, "")
	write(dir, `{raftDir}/trace-{num}.md`, table.concat(lines, "\n"))
	write(dir, `{raftDir}/final-review-{num}.md`, `# Final Review {num}\n\nVerdict: approve\n`)
	git(dir, { "add", "-A", raftDir })
	git(dir, { "commit", "-qm", `{raftId}: final-review-{num}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

-- Starts a raft's first layer in a new worktree.
local function begin(raft: string): string
	local dir = trackerfix.trOk(f, f.main, { "worktree", raft })
	zn(dir, { "start", raft })
	return dir
end

-- Main moved (the added issue was published): put the layer back on it, as the tool tells to.
local function restacked(dir: string, raft: string)
	local branch = git(dir, { "branch", "--show-current" })
	git(dir, { "push", "-q", "origin", branch })
	zn(dir, { "restack", raft })
	git(dir, { "fetch", "-q", "origin" })
	git(dir, { "reset", "-q", "--hard", `origin/{branch}` })
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

-- The added issue as the tool should have published it: waits, found, before and idea in its frontmatter, and in the
-- raft's issues: line, on origin/main. When the tool did not publish it, publish what it made in the worktree.
local function ensurePublished(dir: string, raft: string, id: string, found: string, before: string?)
	local docPath = `{ROOT}/issues/active/{id}/{id}.md`
	if onOrigin(docPath) ~= nil then
		return
	end
	local doc = fs.readFile(`{dir}/{docPath}`)
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
		doc = string.gsub(doc, "\nemergent: true\n", `\nemergent: true\n{extra}`, 1)
	end
	local raftPath = `{ROOT}/rafts/active/{raft}/{raft}.md`
	local rd = onOrigin(raftPath) or ""
	local line = string.match(rd, "\nissues: %[([^\n]*)%]") or ""
	if not has(line, id) then
		rd = string.gsub(rd, "\nissues: %[[^\n]*%]", `\nissues: [{line}, {id}]`, 1)
	end
	trackerfix.elsewhere(f, { [docPath] = doc, [raftPath] = rd }, `tracker: add {id} to {raft}`)
	-- what the tool made in the worktree is not part of the layer
	git(dir, { "checkout", "-q", "--", "." })
	git(dir, { "clean", "-fdq" })
end

-- Rewrites the layer's refute with these answers, commits it (the tool stamps it) and asks for the next layer.
local function attempt(dir: string, issueId: string, answers: { string }): fixture.Result
	local folder = zn(dir, { "find", issueId })
	write(dir, `{folder}/refute-001.md`, table.concat(answers, "\n") .. "\n")
	zn(dir, { "commit", "-m", `tracker: refute {issueId}` })
	git(dir, { "push", "-q" })
	return tr(dir, { "start", "R0010" })
end

-- A refusal names the finding and its reason, and no layer was opened.
local function refused(r: fixture.Result, layerBranch: string, ...: string)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		t.expect(has(say(r), needle)).toBe(true)
	end
	t.expect(git(wt, { "branch", "--show-current" })).toBe(layerBranch)
end

return t.spec("c0394 review answers: dropped, added, and a legacy deferred", function(it)
	it("sets up R0010 on its first layer with Y in front and X last, and a layer review to answer", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
			[`{LESSONS}/idle-finding.md`] = "---\ntitle: An idle finding is not worth doing\nwhen: build\ntags: [finding, not-worth-doing]\ncheck: Is this finding the idle kind?\n---\nIt costs more than it saves.\n",
			[`{LESSONS}/plain-note.md`] = "---\ntitle: A plain note\nwhen: build\ntags: [finding]\ncheck: Is this a plain note?\n---\nNothing more.\n",
		}
		for _, row in { { "R0010", "answers", "c0010, c0030, c0050" }, { "R0020", "legacy", "c0200" } } do
			seed[`{ROOT}/rafts/{row[1]}/{row[1]}.md`] = raftDoc(row[1], row[2], row[3])
			seed[`{ROOT}/rafts/{row[1]}/check.sh`] = CHECK
		end
		for _, row in
			{
				{ "c0010", "R0010" },
				{ "c0030", "R0010" },
				{ "c0050", "R0010" },
				{ "c0200", "R0020" },
				{ "c0070", "" },
				{ "c0099", "" },
			}
		do
			seed[`{ROOT}/issues/{row[1]}/{row[1]}.md`] = issue(row[1], row[1], row[2])
			seed[`{ROOT}/issues/{row[1]}/check.sh`] = CHECK
			seed[`{ROOT}/issues/{row[1]}/acceptance/.gitkeep`] = ""
		end
		-- c0300 is being prepared with a design review and its answers; c0310 is bound to it
		seed[`{ROOT}/issues/c0300/c0300.md`] = issue("c0300", "c0300", "", PREPARING, "size: 100\n")
		seed[`{ROOT}/issues/c0300/check.sh`] = CHECK
		seed[`{ROOT}/issues/c0300/design-review-001.md`] = REVIEW
		seed[`{ROOT}/issues/c0310/c0310.md`] = issue(
			"c0310",
			"c0310",
			"",
			PREPARING,
			"size: 100\nwith: c0300\nwaits: approval\nfound: c0300 design F3 low\nidea: finding\n"
		)
		seed[`{ROOT}/issues/c0310/check.sh`] = CHECK
		f = trackerfix.new("c0394-answers-github.com", seed)
		local bin = `{f.base}/bin`
		log, state = `{f.base}/gh.log`, `{f.base}/gh-state`
		fs.writeDir(bin)
		fs.writeDir(state)
		fs.writeFile(`{bin}/gh`, (string.gsub((string.gsub(GH, "@LOG@", log)), "@STATE@", state)))
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		trackerfix.trOk(f, f.main, { "ready", "R0020" })
		wt = begin("R0010")
		git(f.other, { "pull", "-q", "origin", "main" })
		t.expect(has(fs.readFile(`{f.other}/{ROOT}/rafts/active/R0010/R0010.md`), "\nlayers: reviewed\n"))
			.toBe(true)
		-- Y goes in front of c0010 and X last, both made while c0010's layer is open; each is published to origin/main
		work(wt, "c0010", "alpha")
		local ry = add(wt, "R0010", "found-in-front", "R0010 c0010 review-001 F1 high", "c0010")
		Y = idOf(ry)
		ensurePublished(wt, "R0010", Y, "R0010 c0010 review-001 F1 high", "c0010")
		restacked(wt, "R0010")
		local rx = add(wt, "R0010", "found-last", "R0010 c0010 layer", nil)
		X = idOf(rx)
		ensurePublished(wt, "R0010", X, "R0010 c0010 layer", nil)
		restacked(wt, "R0010")
		t.expect(Y ~= "" and X ~= "").toBe(true)
		zn(wt, { "finish", "c0010" })
		-- the layer's review, with three findings, in the issue's folder (the tool stamps it)
		local folder = zn(wt, { "find", "c0010" })
		write(wt, `{folder}/review-001.md`, REVIEW)
		zn(wt, { "commit", "-m", "tracker: review c0010" })
		git(wt, { "push", "-q" })
	end)

	it("dropped needs a not-worth-doing lesson and a medium or low finding", function()
		-- a high finding is never dropped, even with a good lesson
		refused(
			attempt(
				wt,
				"c0010",
				{ "- F1: dropped idle-finding: not worth it", `- F2: {FIXED}`, `- F3: {FIXED}` }
			),
			"R0010/1/c0010",
			"F1",
			"high"
		)
		-- a lesson that does not exist
		refused(
			attempt(
				wt,
				"c0010",
				{ `- F1: {FIXED}`, "- F2: dropped no-such-lesson: not worth it", `- F3: {FIXED}` }
			),
			"R0010/1/c0010",
			"F2",
			"no-such-lesson"
		)
		-- a lesson without the not-worth-doing tag
		refused(
			attempt(
				wt,
				"c0010",
				{ `- F1: {FIXED}`, "- F2: dropped plain-note: not worth it", `- F3: {FIXED}` }
			),
			"R0010/1/c0010",
			"F2",
			"not-worth-doing"
		)
	end)

	it("added needs an added issue of this raft", function()
		-- a backlog issue that is not a member, a member that is not an added issue, and one that does not exist
		refused(
			attempt(wt, "c0010", { `- F1: {FIXED}`, "- F2: added c0070: later", `- F3: {FIXED}` }),
			"R0010/1/c0010",
			"F2",
			"c0070"
		)
		refused(
			attempt(wt, "c0010", { `- F1: {FIXED}`, "- F2: added c0030: later", `- F3: {FIXED}` }),
			"R0010/1/c0010",
			"F2",
			"c0030"
		)
		refused(
			attempt(wt, "c0010", { `- F1: {FIXED}`, "- F2: added c9999: later", `- F3: {FIXED}` }),
			"R0010/1/c0010",
			"F2",
			"c9999"
		)
	end)

	it(
		"a high added in front of its layer is accepted, and last is refused without the user's ruling",
		function()
			-- X is last: the high finding would land on main before the user has seen it
			local last = attempt(wt, "c0010", { `- F1: added {X}: later`, `- F2: {FIXED}`, `- F3: {FIXED}` })
			refused(last, "R0010/1/c0010", `F1 [high] is added as {X}, which is not in front of c0010`)
			t.expect(has(say(last), "--before")).toBe(true)
			t.expect(has(say(last), "## Open to the human")).toBe(true)
			-- Y is in front of c0010: accepted, and the next layer (c0030, with Y waiting in front) opens
			local front = attempt(
				wt,
				"c0010",
				{ `- F1: added {Y}: main is worse off without it`, `- F2: {FIXED}`, `- F3: {FIXED}` }
			)
			if not front.ok then
				error(say(front), 0)
			end
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0030")

			-- c0030's layer: Z is added last and a high is answered with it. Refused until the user rules it
			work(wt, "c0030", "beta")
			local rz = add(wt, "R0010", "found-late", "R0010 c0030 layer", nil)
			Z = idOf(rz)
			ensurePublished(wt, "R0010", Z, "R0010 c0030 layer", nil)
			restacked(wt, "R0010")
			zn(wt, { "finish", "c0030" })
			local folder = zn(wt, { "find", "c0030" })
			write(wt, `{folder}/review-001.md`, REVIEW)
			write(wt, `{folder}/refute-001.md`, `- F1: added {Z}: later\n- F2: {FIXED}\n- F3: {FIXED}\n`)
			zn(wt, { "commit", "-m", "tracker: review and refute c0030" })
			git(wt, { "push", "-q" })
			local unruled = tr(wt, { "start", "R0010" })
			refused(unruled, "R0010/2/c0030", `F1 [high] is added as {Z}, which is not in front of c0030`)
			-- the user rules it: a Ruled (user, ...) bullet under ## Open to the human in the issue document
			local doc = `{wt}/{folder}/c0030.md`
			fs.writeFile(
				doc,
				fs.readFile(doc)
					.. "\n## Open to the human\n- F1: a high finding. Answer: added last.\n  Ruled (user, 2026-11-16): it may go last.\n"
			)
			zn(wt, { "commit", "-m", "tracker: the user rules F1 of c0030" })
			git(wt, { "push", "-q" })
			local ruled = tr(wt, { "start", "R0010" })
			if not ruled.ok then
				error(say(ruled), 0)
			end
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/3/c0050")
		end
	)

	it("a design refute's dropped and added answers are judged when the issue is prepared", function()
		wtD = trackerfix.trOk(f, f.main, { "worktree", "prep-c0300" })
		local folder = `{wtD}/{ROOT}/issues/c0300`
		local function answered(lines: { string }): fixture.Result
			fs.writeFile(`{folder}/design-refute-001.md`, table.concat(lines, "\n") .. "\n")
			git(wtD, { "add", "-A" })
			git(wtD, { "commit", "-qm", "design refute", "--allow-empty" })
			return tr(wtD, { "status", "c0300", "prepared" })
		end
		-- a high finding is never dropped; an unknown lesson; an added issue that is not bound to c0300
		local high = answered({ "- F1: dropped idle-finding: no", `- F2: {FIXED}`, `- F3: {FIXED}` })
		t.expect(high.ok).toBe(false)
		t.expect(has(say(high), "F1")).toBe(true)
		local unknown = answered({ `- F1: {FIXED}`, "- F2: dropped no-such-lesson: no", `- F3: {FIXED}` })
		t.expect(unknown.ok).toBe(false)
		t.expect(has(say(unknown), "no-such-lesson")).toBe(true)
		local stranger = answered({ `- F1: {FIXED}`, "- F2: added c0099: later", `- F3: {FIXED}` })
		t.expect(stranger.ok).toBe(false)
		t.expect(has(say(stranger), "c0099")).toBe(true)
		-- valid answers: a dropped with its lesson, and an added issue whose with: names c0300
		local fine = answered({
			`- F1: {FIXED}`,
			"- F2: dropped idle-finding: not worth it",
			"- F3: added c0310: needs its own design",
		})
		if not fine.ok then
			error(say(fine), 0)
		end
		t.expect(has(fs.readFile(`{folder}/c0300.md`), "\nstatus: prepared-")).toBe(true)
	end)

	it("a deferred answer is still accepted and called legacy", function()
		-- R0020: one layer, a final review whose medium finding is answered with a written `deferred <id>`
		wtB = begin("R0020")
		work(wtB, "c0200", "legacy")
		zn(wtB, { "finish", "c0200" })
		review(wtB, "c0200")
		sealBind(wtB, "R0020", nil)
		local raftDir = zn(wtB, { "find", "R0020" })
		write(
			wtB,
			`{raftDir}/final-review-001.md`,
			"# Final Review 001\n\n### F1 [medium] a medium finding\nEvidence: y\n\nVerdict: changes requested\n"
		)
		write(wtB, `{raftDir}/final-refute-001.md`, "- F1: deferred c0070: needs its own design\n")
		git(wtB, { "add", "-A", raftDir })
		git(wtB, { "commit", "-qm", "R0020: final review answered with a legacy deferred" })
		git(wtB, { "push", "-q", "origin", git(wtB, { "branch", "--show-current" }) })
		local r = tr(wtB, { "done", "R0020" })
		if not r.ok then
			error(say(r), 0)
		end
		t.expect(has(say(r), "deferred is legacy (c0394): answer dropped or added")).toBe(true)
		t.expect(has(r.stdout, "landed R0020")).toBe(true)
		-- the legacy follow-up stays in the backlog, where it was
		t.expect(onOrigin(`{ROOT}/issues/c0070/c0070.md`) ~= nil).toBe(true)
	end)
end)
