--!strict
-- c0248 AC4 to AC9: a layer is complete before the next starts, a stack lands as one bind or as a shorter bind
-- (`done --through`), and every layer's pull request names the stack. Real git in a fixture under .cache: a bare
-- origin whose path contains github.com, a worktree per raft, and a `gh` stub that keeps each PR's base and body.
-- Fixture: .cache/c0248-layers-land-github.com. Nothing here touches the real repository.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local OLDER = "9b8e7f0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60"

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
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nThe {slug} theme: layers that are reviewed one by one.\n\nA second paragraph that is not the Theme line.\n\n## Order & dependencies\n{order}\n`
end

-- gh keeps each pull request's base and body in files, numbered by the layer's branch.
local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
num() { case "$1" in
  R0010/1/*) echo 11 ;; R0010/2/*) echo 12 ;; R0010/3/*) echo 13 ;;
  R0020/1/*) echo 21 ;; R0020/2/*) echo 22 ;;
  R0030/1/*) echo 31 ;; R0030/2/*) echo 32 ;; *) echo 99 ;; esac; }
after() { want="$1"; shift; prev=""; for a in "$@"; do if [ "$prev" = "$want" ]; then echo "$a"; return; fi; prev="$a"; done; }
case "$1 $2" in
  "pr list") case "$*" in *number*) num "$(after --head "$@")" ;; esac; exit 0 ;;
  "pr create") n=$(num "$(after --head "$@")"); after --base "$@" > "@STATE@/base-$n"; echo "https://github.com/x/y/pull/$n"; exit 0 ;;
  "pr view") cat "@STATE@/base-$3" 2>/dev/null || echo main; exit 0 ;;
  "pr edit") n="$3"
    case "$*" in *--body-file*) cat > "@STATE@/body-$n.md" ;; *--base*) after --base "$@" > "@STATE@/base-$n" ;; esac
    exit 0 ;;
esac
exit 0
]=]

local f: trackerfix.Fixture
local log, state = "", ""
local env: { [string]: string } = {}
local wt, wtB, wtC = "", "", ""
local bodyAfterFinish1, bodyAfterBind1 = "", ""

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function zn(dir: string, args: { string }): string
	return must(trackerfix.tr(f, dir, args, env), "./zn " .. table.concat(args, " "))
end

local function znTry(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
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

local function work(dir: string, issueId: string, file: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", `{issueId} work` })
end

local function finishSha(dir: string, issueId: string): string
	for line in string.gmatch(git(dir, { "log", "--format=%H%x09%s", "-80" }) .. "\n", "([^\n]*)\n") do
		local sha, subject = string.match(line, "^(%x+)\t(.*)$")
		if sha and subject and string.sub(subject, 1, #issueId + 2) == `{issueId}: ` then
			return sha
		end
	end
	error(`no finish commit for {issueId}`, 2)
end

-- A layer's review in its issue's folder, committed and pushed on the layer `dir` is on. `names` is the commit the
-- review says it reviewed (the layer's finish commit unless a case gives another).
local function review(dir: string, issueId: string, names: string?)
	local issueDir = zn(dir, { "find", issueId })
	local sha = names or finishSha(dir, issueId)
	write(dir, `{issueDir}/review-001.md`, `# Review 001\n\nCommit: {sha}\nVerdict: approve\n`)
	git(dir, { "add", "-A", issueDir })
	git(dir, { "commit", "-qm", `tracker: review {issueId}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

-- The final review and the trace of one landing, committed on the layer `dir` is on after its finish. `through` scopes
-- both to the layers up to that issue's; `n` numbers the final review (every landing has its own).
local function sealBind(dir: string, raftId: string, through: string?, n: number)
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
	local issueDirs: { [string]: string } = {}
	local checkLines: { [string]: number } = {}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		if not issueDirs[id] then
			issueDirs[id] = zn(dir, { "find", id })
			local idx = 0
			checkLines[id] = 1
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
	write(dir, `{raftDir}/trace.md`, table.concat(lines, "\n"))
	local num = string.format("%03d", n)
	write(dir, `{raftDir}/final-review-{num}.md`, `# Final Review {num}\n\nVerdict: approve\n`)
	git(dir, { "add", "-A", raftDir })
	git(dir, { "commit", "-qm", `{raftId}: final-review-{num}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

-- The bind commit's message starts with these lines; the spend trailers (`Issue: <id> ...`) follow them.
local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function body(number: string): string
	return fs.readFile(`{state}/body-{number}.md`)
end

return t.spec("c0248 layers are complete before the next, and land as one bind or a shorter one", function(it)
	it(
		"sets up three readied rafts behind a local github-shaped origin and a gh that keeps PR bases and bodies",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
					"R0010",
					"stack",
					"c0010, c0020, c0030",
					"c0010\nc0020\nc0030"
				),
				["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc(
					"R0020",
					"pair",
					"c0040, c0050",
					"c0040\nc0050"
				),
				["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc(
					"R0030",
					"gap",
					"c0070, c0080",
					"c0070\nc0080"
				),
			}
			local rafts: { [string]: { string } } = {
				R0010 = { "c0010", "c0020", "c0030" },
				R0020 = { "c0040", "c0050" },
				R0030 = { "c0070", "c0080" },
			}
			for raft, ids in rafts do
				seed[`pickman/.tracker/rafts/{raft}/check.sh`] = CHECK
				for _, id in ids do
					seed[`pickman/.tracker/issues/{id}/{id}.md`] = issue(id, `title {id}`, raft)
					seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
					seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
				end
			end
			f = trackerfix.new("c0248-layers-land-github.com", seed)
			local bin = `{f.base}/bin`
			log, state = `{f.base}/gh.log`, `{f.base}/gh-state`
			fs.writeDir(bin)
			fs.writeDir(state)
			local script = (string.gsub((string.gsub(GH, "@LOG@", log)), "@STATE@", state))
			fs.writeFile(`{bin}/gh`, script)
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			for raft in rafts do
				trackerfix.trOk(f, f.main, { "ready", raft })
			end
			wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		end
	)

	it("AC4: start refuses the next layer until the layer below is complete, naming it", function()
		zn(wt, { "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		work(wt, "c0010", "alpha")
		zn(wt, { "finish", "c0010" })
		bodyAfterFinish1 = body("11")
		-- finished, but no review in the issue's folder
		local none = znTry(wt, { "start", "R0010" })
		t.expect(none.ok).toBe(false)
		t.expect(has(none.stderr, "c0010 is not complete")).toBe(true)
		t.expect(has(none.stderr, "review")).toBe(true)
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
		-- a review of an older commit is not current
		review(wt, "c0010", OLDER)
		local stale = znTry(wt, { "start", "R0010" })
		t.expect(stale.ok).toBe(false)
		t.expect(has(stale.stderr, "c0010 is not complete")).toBe(true)
		t.expect(has(stale.stderr, string.sub(OLDER, 1, 7))).toBe(true)
		t.expect(has(stale.stderr, string.sub(finishSha(wt, "c0010"), 1, 7))).toBe(true)
		t.expect(has(git(f.main, { "branch", "-r" }), "R0010/2/c0020")).toBe(false)
	end)

	it("AC4: a review committed in the issue folder after finish keeps the layer finished", function()
		-- the stale review is a commit after the finish commit; the layer is still finished (not claimed again)
		git(f.other, { "fetch", "-q", "origin" })
		t.expect(has(zn(f.other, { "stack", "R0010" }), "1 R0010/1/c0010 c0010 finished")).toBe(true)
		t.expect(git(wt, { "rev-list", "--count", "origin/main..HEAD" })).toBe("2")
		-- the current review makes it complete; another commit rewriting the file is the same
		review(wt, "c0010")
		git(f.other, { "fetch", "-q", "origin" })
		t.expect(has(zn(f.other, { "stack", "R0010" }), "1 R0010/1/c0010 c0010 complete")).toBe(true)
		-- a layer is finished only while what follows its finish commit is such files: source after it is not
		write(wt, "pickman/src/extra.luau", "return 1\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "unfinishing" })
		git(wt, { "push", "-q" })
		git(f.other, { "fetch", "-q", "origin" })
		t.expect(has(zn(f.other, { "stack", "R0010" }), "1 R0010/1/c0010 c0010 claimed")).toBe(true)
		git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		git(wt, { "push", "-q", "--force-with-lease" })
	end)

	it("AC4: start opens the next layer once the review is settled", function()
		zn(wt, { "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
		t.expect(has(fs.readFile(log), "--base R0010/1/c0010 --head R0010/2/c0020")).toBe(true)
		work(wt, "c0020", "beta")
		zn(wt, { "finish", "c0020" })
		review(wt, "c0020")
		-- the same rule one layer up: its review is settled, so the third layer may start, and is checked below
		t.expect(has(zn(wt, { "stack", "R0010" }), "2 R0010/2/c0020 c0020 complete")).toBe(true)
	end)

	it("AC6: done --through needs its own final review and trace over exactly those layers", function()
		local layer2 = git(wt, { "rev-parse", "HEAD" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
		local before = git(f.main, { "rev-parse", "origin/main" })
		-- no final review yet
		local noReview = znTry(wt, { "done", "R0010", "--through", "c0020" })
		t.expect(noReview.ok).toBe(false)
		t.expect(has(noReview.stderr, "final-review")).toBe(true)
		-- the skeleton covers the layers up to c0020 and names that layer's finish commit
		local skeleton = zn(wt, { "trace", "R0010", "--through", "c0020" })
		t.expect(has(skeleton, `Commit: {finishSha(wt, "c0020")}`)).toBe(true)
		t.expect(has(skeleton, "| c0010:")).toBe(true)
		t.expect(has(skeleton, "| c0020:")).toBe(true)
		t.expect(has(skeleton, "c0030:")).toBe(false)
		-- no trace.md yet: --check fails; the whole raft's trace is over three layers and there are two
		t.expect(znTry(wt, { "trace", "R0010", "--through", "c0020", "--check" }).ok).toBe(false)
		local whole = znTry(wt, { "trace", "R0010", "--check" })
		t.expect(whole.ok).toBe(false)
		sealBind(wt, "R0010", "c0020", 1)
		t.expect(has(zn(wt, { "trace", "R0010", "--through", "c0020", "--check" }), "ok: R0010")).toBe(true)
		-- the trace and review are over the two layers; a done without --through wants a third layer
		local tooMany = znTry(wt, { "done", "R0010" })
		t.expect(tooMany.ok).toBe(false)
		t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
		t.expect(layer2 ~= git(wt, { "rev-parse", "HEAD" })).toBe(true) -- the seal is a commit on the layer
	end)

	it(
		"AC7: done --through refuses a HEAD that is not that layer's tip, a member that is not in the raft, an incomplete layer",
		function()
			local before = git(f.main, { "rev-parse", "origin/main" })
			-- a HEAD on the layer below
			git(wt, { "switch", "-q", "R0010/1/c0010" })
			local wrongHead = znTry(wt, { "done", "R0010", "--through", "c0020" })
			t.expect(wrongHead.ok).toBe(false)
			t.expect(has(wrongHead.stderr, "R0010/2/c0020 is")).toBe(true)
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			-- an id that is not a member of the raft
			local stranger = znTry(wt, { "done", "R0010", "--through", "c0099" })
			t.expect(stranger.ok).toBe(false)
			t.expect(has(stranger.stderr, "c0099")).toBe(true)
			-- a member of another raft is not one of this raft's either
			t.expect(znTry(wt, { "done", "R0010", "--through", "c0040" }).ok).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)

			-- an incomplete layer below the top of the range: layer 2 built by hand on a layer 1 that has no review
			wtC = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
			zn(wtC, { "start", "R0030" })
			work(wtC, "c0070", "gap1")
			zn(wtC, { "finish", "c0070" })
			git(wtC, { "switch", "-q", "-c", "R0030/2/c0080" })
			git(wtC, { "commit", "-q", "--allow-empty", "-m", "tracker: start R0030 gap" })
			work(wtC, "c0080", "gap2")
			zn(wtC, { "finish", "c0080" })
			review(wtC, "c0080")
			write(
				wtC,
				"pickman/.tracker/rafts/active/R0030/final-review-001.md",
				"# Final Review 001\n\nVerdict: approve\n"
			)
			git(wtC, { "add", "-A" })
			git(wtC, { "commit", "-qm", "R0030: final-review-001" })
			git(wtC, { "push", "-q" })
			for _, args in { { "done", "R0030" }, { "done", "R0030", "--through", "c0080" } } do
				local below = znTry(wtC, args)
				t.expect(below.ok).toBe(false)
				t.expect(has(below.stderr, "c0070 is not complete")).toBe(true)
			end
			t.expect(has(git(f.main, { "log", "--format=%s", "origin/main" }), "bind")).toBe(false)

			-- the third layer starts on the sealed second one, so it has a pull request on the second layer's branch;
			-- a HEAD on that layer above is no more the tip of the layer --through names
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			zn(wt, { "start", "R0010" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/3/c0030")
			t.expect(has(fs.readFile(log), "--base R0010/2/c0020 --head R0010/3/c0030")).toBe(true)
			local above = znTry(wt, { "done", "R0010", "--through", "c0020" })
			t.expect(above.ok).toBe(false)
			t.expect(has(above.stderr, "R0010/2/c0020 is")).toBe(true)
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
		end
	)

	it(
		"AC6: done --through lands only the layers up to the named one, moves only them, keeps the raft active, retargets the next PR to main",
		function()
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			local top = git(wt, { "rev-parse", "HEAD" })
			local landed = zn(wt, { "done", "R0010", "--through", "c0020" })
			t.expect(has(landed, "landed R0010")).toBe(true)
			local bind = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
			t.expect(
				startsWith(
					bind,
					"R0010: bind c0010, c0020\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/active/R0010/trace.md\n"
				)
			).toBe(true)
			-- the bind names only what it landed
			t.expect(has(bind, "Issue: c0010")).toBe(true)
			t.expect(has(bind, "Issue: c0020")).toBe(true)
			t.expect(has(bind, "c0030")).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
			-- exactly the landed members moved; the third and the raft did not
			local tree = git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
			t.expect(has(tree, "pickman/.tracker/issues/done/c0010/c0010.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/issues/done/c0020/c0020.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/issues/active/c0030/c0030.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/issues/done/c0030/")).toBe(false)
			t.expect(has(tree, "pickman/.tracker/rafts/active/R0010/R0010.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/rafts/done/R0010/")).toBe(false)
			-- only the landed members' acceptance folders were promoted
			t.expect(has(tree, "pickman/tests/acceptance/c0010/")).toBe(true)
			t.expect(has(tree, "pickman/tests/acceptance/c0020/")).toBe(true)
			t.expect(has(tree, "pickman/tests/acceptance/c0030/")).toBe(false)
			t.expect(has(tree, "pickman/src/alpha.luau") and has(tree, "pickman/src/beta.luau")).toBe(true)
			-- the landed layers' pull requests and the next layer's go to main
			local calls = fs.readFile(log)
			t.expect(has(calls, "pr edit 11 --base main")).toBe(true)
			t.expect(has(calls, "pr edit 12 --base main")).toBe(true)
			t.expect(has(calls, "pr edit 13 --base main")).toBe(true)
			t.expect(fs.readFile(`{state}/base-13`)).toBe("main\n")
			bodyAfterBind1 = body("13")
		end
	)

	it("AC8: the next layer is still stacked when the landed branch is gone from origin", function()
		-- GitHub deletes a merged branch: the landed layers' branches go from origin and from this clone
		git(wt, { "switch", "-q", "R0010/3/c0030" })
		git(wt, { "push", "-q", "origin", "--delete", "R0010/1/c0010", "R0010/2/c0020" })
		git(wt, { "branch", "-q", "-D", "R0010/1/c0010", "R0010/2/c0020" })
		git(wt, { "fetch", "-q", "--prune", "origin" })
		git(f.other, { "fetch", "-q", "--prune", "origin" })
		t.expect(has(git(wt, { "branch", "-a" }), "R0010/2/c0020")).toBe(false)
		-- the third layer is still the layer to build: start resumes it and does not reopen a landed one
		local resumed = zn(wt, { "start", "R0010" })
		t.expect(has(resumed, "on branch R0010/3/c0030")).toBe(true)
		work(wt, "c0030", "gamma")
		local finished = zn(wt, { "finish", "c0030" })
		t.expect(has(finished, "finished R0010/3/c0030")).toBe(true)
		-- stacked on a commit that main holds: finished, not claimed
		local seen = zn(f.other, { "stack", "R0010" })
		t.expect(has(seen, "1 R0010/1/c0010 c0010 landed")).toBe(true)
		t.expect(has(seen, "2 R0010/2/c0020 c0020 landed")).toBe(true)
		t.expect(has(seen, "3 R0010/3/c0030 c0030 finished")).toBe(true)
	end)

	it(
		"AC8: after --through, stack shows landed, and done lands the rest in a second bind and moves the raft",
		function()
			review(wt, "c0030")
			t.expect(has(zn(wt, { "stack", "R0010" }), "3 R0010/3/c0030 c0030 complete")).toBe(true)
			-- a landed layer is not landed twice
			local again = znTry(wt, { "done", "R0010", "--through", "c0010" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr, "c0010 is already landed")).toBe(true)
			-- the first bind's final review does not stand in for this one's
			local reused = znTry(wt, { "done", "R0010" })
			t.expect(reused.ok).toBe(false)
			t.expect(has(reused.stderr, "final-review-001")).toBe(true)
			sealBind(wt, "R0010", nil, 2)
			local trace2 = zn(wt, { "trace", "R0010", "--check" })
			t.expect(has(trace2, "ok: R0010")).toBe(true)
			local landed = zn(wt, { "done", "R0010" })
			t.expect(has(landed, "landed R0010")).toBe(true)
			local bind2 = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
			t.expect(
				startsWith(
					bind2,
					"R0010: bind c0030\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0010/trace.md\n"
				)
			).toBe(true)
			t.expect(has(bind2, "c0010")).toBe(false)
			local tree = git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
			t.expect(has(tree, "pickman/.tracker/issues/done/c0030/c0030.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/rafts/done/R0010/R0010.md")).toBe(true)
			t.expect(has(tree, "pickman/.tracker/rafts/active/R0010/")).toBe(false)
			t.expect(has(tree, "pickman/.tracker/issues/active/c0030/")).toBe(false)
			t.expect(has(tree, "pickman/tests/acceptance/c0030/")).toBe(true)
			-- three landings in two binds: the first bind is still the second parent's ancestor path
			t.expect(git(f.main, { "log", "--format=%s", "--grep=^R0010: bind", "origin/main" }))
				.toBe("R0010: bind c0030\nR0010: bind c0010, c0020")
		end
	)

	it(
		"AC9: every layer PR body names the raft's Theme, Order and the stack, refreshed by finish and done",
		function()
			-- written by start and rewritten by finish: layer 1's body after its finish
			t.expect(has(bodyAfterFinish1, "Raft **R0010**: stack")).toBe(true)
			t.expect(has(bodyAfterFinish1, "The stack theme: layers that are reviewed one by one."))
				.toBe(true)
			t.expect(has(bodyAfterFinish1, "A second paragraph")).toBe(false) -- the Theme is its first paragraph
			t.expect(has(bodyAfterFinish1, "## Order")).toBe(true)
			t.expect(has(bodyAfterFinish1, "c0010\nc0020\nc0030")).toBe(true)
			t.expect(has(bodyAfterFinish1, "## Stack")).toBe(true)
			t.expect(has(bodyAfterFinish1, "| 1 (this layer) | c0010 | `R0010/1/c0010` | #11 | finished |"))
				.toBe(true)
			t.expect(has(bodyAfterFinish1, "| 2 | c0020 | `R0010/2/c0020` | - | missing |")).toBe(true)
			-- rewritten by done for the layer that goes on: the landed layers show as landed, this one is marked
			t.expect(has(bodyAfterBind1, "Raft **R0010**: stack")).toBe(true)
			t.expect(has(bodyAfterBind1, "| 1 | c0010 | `R0010/1/c0010` | - | landed |")).toBe(true)
			t.expect(has(bodyAfterBind1, "| 2 | c0020 | `R0010/2/c0020` | - | landed |")).toBe(true)
			t.expect(has(bodyAfterBind1, "| 3 (this layer) | c0030 | `R0010/3/c0030` | #13 | claimed |"))
				.toBe(true)
			-- and by finish again: the third layer's body after its finish and its review
			local last = body("13")
			t.expect(has(last, "| 3 (this layer) | c0030 | `R0010/3/c0030` | #13 | finished |")).toBe(true)
			t.expect(has(last, "landed")).toBe(true)
			-- the refresh is an edit with the body on standard input
			t.expect(has(fs.readFile(log), "pr edit 13 --body-file -")).toBe(true)
		end
	)

	it("AC5: done refuses a stack whose top layer is not complete", function()
		wtB = trackerfix.trOk(f, f.main, { "worktree", "R0020" })
		zn(wtB, { "start", "R0020" })
		work(wtB, "c0040", "pair1")
		zn(wtB, { "finish", "c0040" })
		review(wtB, "c0040")
		zn(wtB, { "start", "R0020" })
		work(wtB, "c0050", "pair2")
		zn(wtB, { "finish", "c0050" })
		-- its review names an older commit; the final review is there
		review(wtB, "c0050", OLDER)
		write(
			wtB,
			"pickman/.tracker/rafts/active/R0020/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		git(wtB, { "add", "-A" })
		git(wtB, { "commit", "-qm", "R0020: final-review-001" })
		git(wtB, { "push", "-q" })
		for _, args in { { "done", "R0020" }, { "done", "R0020", "--through", "c0050" } } do
			local refused = znTry(wtB, args)
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "c0050 is not complete")).toBe(true)
		end
		t.expect(has(git(f.main, { "log", "--format=%s", "origin/main" }), "R0020: bind")).toBe(false)
	end)

	it("AC5: a full done of complete layers lands the same bind as #296", function()
		review(wtB, "c0050")
		seal.trace(wtB, "R0020")
		local top = git(wtB, { "rev-parse", "HEAD" })
		local landed = zn(wtB, { "done", "R0020" })
		t.expect(has(landed, "landed R0020")).toBe(true)
		-- #296's bind: one --no-ff merge of the top layer, the message, every member and the raft in done/
		local bind = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
		t.expect(
			startsWith(
				bind,
				"R0020: bind c0040, c0050\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0020/trace.md\n"
			)
		).toBe(true)
		t.expect(has(bind, "Issue: c0040") and has(bind, "Issue: c0050")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
		t.expect(git(f.main, { "rev-list", "--count", "--parents", "-n", "1", "origin/main" })).toBe("1")
		local parents = git(f.main, { "log", "-1", "--format=%P", "origin/main" })
		t.expect(select(2, string.gsub(parents, "%x+", ""))).toBe(2)
		local tree = git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
		for _, id in { "c0040", "c0050" } do
			t.expect(has(tree, `pickman/.tracker/issues/done/{id}/{id}.md`)).toBe(true)
			t.expect(has(tree, `pickman/.tracker/issues/active/{id}/`)).toBe(false)
			t.expect(has(tree, `pickman/tests/acceptance/{id}/`)).toBe(true)
		end
		t.expect(has(tree, "pickman/.tracker/rafts/done/R0020/R0020.md")).toBe(true)
		t.expect(has(tree, "pickman/.tracker/rafts/active/R0020/")).toBe(false)
		t.expect(has(tree, "pickman/src/pair1.luau") and has(tree, "pickman/src/pair2.luau")).toBe(true)
		-- every layer's pull request went to main before the push
		local calls = fs.readFile(log)
		t.expect(has(calls, "pr edit 21 --base main")).toBe(true)
		t.expect(has(calls, "pr edit 22 --base main")).toBe(true)
	end)
end)
