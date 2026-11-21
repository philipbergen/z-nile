--!strict
-- d0331 with f0399: a raft readied `--on` another raft. Its layer 1 sits on the base commit `<R>/base` until the
-- raft it is built on lands. After that landing a base commit in layer 1 (the current one, or an older one a
-- stopped restack left) is not the layer's own, so finish, trace and done judge that layer against main's tip and
-- refuse it naming ./zn restack (f0399's "then ./zn restack"); the restacked layer is judged against its fork.
-- Real git in .cache/d0331-on-landed-github.com (a bare origin, a worktree per raft, a `gh` stub, an update hook
-- that rejects layer 1's push on demand). Fixture: R0010 holds c0020 (adds src/base.luau); R0020 holds f0030,
-- which depends on c0020. Cases run in order and share the fixture.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local HEAD =
	'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: ok" true\nfinish\n'
local CHECK_BASE = HEAD .. 'check "AC1: the base is there" test -f src/base.luau\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, kind: string, raft: string, deps: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, kind: string, issues: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{issues}\n`
end

-- gh keeps each pull request's base in a file, numbered by the layer's branch: R00<r>0/<n>/... is PR <r><n>
local GH = [=[#!/bin/sh
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

local f: trackerfix.Fixture = nil :: any
local env: { [string]: string } = {}
local wtD, wtR = "", ""
local refusedOk, movedBase = false, false
local oldBaseOf = ""

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

-- a setup command, so a failure is a broken fixture or a missing d0331: on main before d0331 the setup's trace
-- of R0010 refuses ("not stacked on the layer below"), because readying R0020 moved main
local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function readyBody(): string
	return git(f.origin, { "log", "-1", "--format=%B", "--grep=^tracker: ready R0020 ", "main" })
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", `{id} work` })
end

-- R0010's one layer is finished
local setUp = false
local function setup()
	if setUp then
		return
	end
	setUp = true
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		[`{ROOT}/rafts/R0010/R0010.md`] = raftDoc("R0010", "chore", "c0020"),
		[`{ROOT}/rafts/R0010/check.sh`] = CHECK,
		[`{ROOT}/rafts/R0020/R0020.md`] = raftDoc("R0020", "feature", "f0030"),
		[`{ROOT}/rafts/R0020/check.sh`] = CHECK,
		[`{ROOT}/issues/c0020/c0020.md`] = issue("c0020", "chore", "R0010", ""),
		[`{ROOT}/issues/c0020/check.sh`] = CHECK,
		[`{ROOT}/issues/f0030/f0030.md`] = issue("f0030", "feature", "R0020", "c0020"),
		[`{ROOT}/issues/f0030/check.sh`] = CHECK_BASE,
	}
	f = trackerfix.new("d0331-on-landed-github.com", seed)
	local bin, state = `{f.base}/bin`, `{f.base}/state`
	fs.writeDir(bin)
	fs.writeDir(state)
	fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@STATE@", state)))
	process.exec("chmod", { "+x", `{bin}/gh` })
	env = { PATH = `{bin}:{process.env.PATH or ""}` }
	-- origin rejects pushes of R0020's layer 1 while the file reject exists (a restack stopped at that layer)
	fs.writeFile(
		`{f.origin}/hooks/update`,
		'#!/bin/sh\ncase "$1" in refs/heads/R0020/1/*)\n  if [ -f "'
			.. f.base
			.. '/reject" ]; then echo "rejected on purpose" >&2; exit 1; fi ;;\nesac\nexit 0\n'
	)
	process.exec("chmod", { "+x", `{f.origin}/hooks/update` })

	zn(f.main, { "ready", "R0010" })
	wtD = zn(f.main, { "worktree", "R0010" })
	zn(wtD, { "start", "R0010" })
	write(wtD, `{ROOT}/rafts/active/R0010/final-review-001.md`, "# Final Review 001\n\nVerdict: approve\n")
	layerWork(wtD, "base", "c0020")
	zn(wtD, { "finish", "c0020" })
end

-- R0020 is readied on R0010 (the first case) and its layer 1 is finished on the base commit
local readied, built, baseLanded = false, false, false
local function build()
	setup()
	if built then
		return
	end
	built = true
	if not readied then
		error("fixture: R0020 was not readied --on R0010 (the first case failed)", 2)
	end
	wtR = zn(f.main, { "worktree", "R0020" })
	zn(wtR, { "start", "R0020" })
	write(wtR, `{ROOT}/rafts/active/R0020/final-review-001.md`, "# Final Review 001\n\nVerdict: approve\n")
	write(wtR, `{ROOT}/rafts/active/R0020/review-001.md`, "# Review 001\n\nVerdict: approve\n")
	layerWork(wtR, "feature", "f0030")
	zn(wtR, { "finish", "f0030" })
	git(wtR, { "push", "-q", "origin", "R0020/1/f0030" })
end

-- R0010 lands (with no restack: d0331 lets a moved main through)
local function land()
	build()
	if baseLanded then
		return
	end
	baseLanded = true
	seal.layerReview(wtD, "c0020") -- c0248: done lands only complete (reviewed) layers
	seal.trace(wtD, "R0010")
	zn(wtD, { "done", "R0010" })
	git(wtR, { "fetch", "-q", "origin" })
end

return t.spec("d0331: layer 1 of a raft built on a raft that landed", function(it)
	it("AC15: ready --on accepts a base raft whose finished layer 1 main moved past", function()
		setup()
		trackerfix.elsewhere(f, { ["pickman/src/early.luau"] = "early\n" }, "elsewhere: early")
		git(wtD, { "fetch", "-q", "origin" })
		t.expect(fixture.exec(wtD, "git", { "merge-base", "--is-ancestor", "origin/main", "HEAD" }).ok)
			.toBe(false)
		local r = tr(f.main, { "ready", "R0020", "--on", "R0010" })
		if not r.ok then
			error(
				`expected ./zn ready R0020 --on R0010 to accept R0010's finished layer after main moved: {say(
					r
				)}`
			)
		end
		t.expect(has(readyBody(), "On: R0010")).toBe(true)
		readied = true
	end)

	it(
		"AC15: before the raft it is built on lands, a restack stopped at layer 1 after rebuilding the base leaves that layer judged against the new base: finish refuses naming ./zn restack",
		function()
			build()
			-- R0010's top layer moves, so the next restack of R0020 rebuilds R0020/base on it
			layerWork(wtD, "base2", "c0020")
			zn(wtD, { "finish", "c0020" })
			local oldBase = git(wtR, { "rev-parse", "origin/R0020/base" })
			local head = git(wtR, { "rev-parse", "HEAD" })
			fs.writeFile(`{f.base}/reject`, "")
			local stopped = tr(wtR, { "restack", "R0020" })
			fs.removeFile(`{f.base}/reject`)
			t.expect(stopped.ok).toBe(false)
			t.expect(has(say(stopped), "not pushed: R0020/1/f0030")).toBe(true)
			git(wtR, { "fetch", "-q", "origin" })
			local newBase = git(wtR, { "rev-parse", "origin/R0020/base" })
			t.expect(newBase ~= oldBase).toBe(true)
			t.expect(git(wtR, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fixture.exec(wtR, "git", { "merge-base", "--is-ancestor", newBase, "HEAD" }).ok)
				.toBe(false)

			local finished = tr(wtR, { "finish", "f0030" })
			t.expect(finished.ok).toBe(false)
			t.expect(has(say(finished), "./zn restack R0020")).toBe(true)
			t.expect(git(wtR, { "rev-parse", "HEAD" })).toBe(head)

			-- layer 1 stays on the old base commit through R0010's landing (design review 003 F1): no second restack
			oldBaseOf = oldBase
			movedBase = true
		end
	)

	it(
		"AC15: after the raft it is built on lands, finish, trace and done refuse a layer 1 still on an older base commit, naming ./zn restack, and leave it as it was",
		function()
			t.expect(movedBase).toBe(true)
			land()
			t.expect(
				fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{ROOT}/rafts/done/R0010/R0010.md` }).ok
			)
				.toBe(true)
			-- layer 1 still holds the older base commit, not the one origin's R0020/base names now
			local head = git(wtR, { "rev-parse", "HEAD" })
			t.expect(git(wtR, { "rev-parse", "HEAD^" })).toBe(oldBaseOf)
			t.expect(git(wtR, { "rev-parse", "origin/R0020/base" }) ~= oldBaseOf).toBe(true)

			local finished = tr(wtR, { "finish", "f0030" })
			t.expect(finished.ok).toBe(false)
			t.expect(has(say(finished), "./zn restack R0020")).toBe(true)
			t.expect(git(wtR, { "rev-parse", "HEAD" })).toBe(head)

			local traced = tr(wtR, { "trace", "R0020" })
			t.expect(traced.ok).toBe(false)
			t.expect(has(say(traced), "./zn restack R0020")).toBe(true)

			local mainBefore = git(f.origin, { "rev-parse", "main" })
			local landed = tr(wtR, { "done", "R0020" })
			t.expect(landed.ok).toBe(false)
			t.expect(has(say(landed), "./zn restack R0020")).toBe(true)
			t.expect(has(say(landed), "./zn finish f0030")).toBe(false)
			t.expect(git(f.origin, { "rev-parse", "main" })).toBe(mainBefore)

			-- another clone, with origin's R0020/base and no local branch of it, judges the layer the same way
			git(f.other, { "pull", "-q", "origin", "main" })
			git(f.other, { "fetch", "-q", "origin" })
			t.expect(
				fixture.exec(f.other, "git", { "rev-parse", "--verify", "-q", "refs/heads/R0020/base" }).ok
			)
				.toBe(false)
			local elsewhere = tr(f.other, { "trace", "R0020" })
			t.expect(elsewhere.ok).toBe(false)
			t.expect(has(say(elsewhere), "./zn restack R0020")).toBe(true)
			t.expect(has(say(elsewhere), "./zn finish f0030")).toBe(false)
			refusedOk = true
		end
	)

	it(
		"AC15: restack moves that layer onto main as its own one commit, and then it is judged against its fork: main moves again and done lands it with no second restack",
		function()
			land()
			t.expect(refusedOk).toBe(true)
			local restacked = tr(wtR, { "restack", "R0020" })
			if not restacked.ok then
				error(`expected ./zn restack R0020 to succeed: {say(restacked)}`)
			end
			git(wtR, { "fetch", "-q", "origin" })
			git(wtR, { "reset", "-q", "--hard", "origin/R0020/1/f0030" })
			-- the restack leaves one commit above main, f0030's own, with none of R0010's files and no base commit
			local own = git(wtR, { "log", "--format=%s", "origin/main..HEAD" })
			t.expect(string.sub(own, 1, 7)).toBe("f0030: ")
			t.expect(has(own, "\n")).toBe(false)
			local files = git(wtR, { "diff", "--name-only", "origin/main", "HEAD" })
			t.expect(has(files, "pickman/src/feature.luau")).toBe(true)
			t.expect(has(files, "base.luau") or has(files, "base2.luau")).toBe(false)
			t.expect(has(files, "rafts/active/R0010/")).toBe(false)
			seal.layerReview(wtR, "f0030") -- c0248: the restacked layer is reviewed before done
			pcall(seal.trace, wtR, "R0020")
			git(wtR, { "push", "-q", "origin", "R0020/1/f0030" })

			trackerfix.elsewhere(f, { ["pickman/src/moved.luau"] = "moved\n" }, "elsewhere: moved")
			git(wtR, { "fetch", "-q", "origin" })
			local tip = git(wtR, { "rev-parse", "origin/main" })
			local landed = tr(wtR, { "done", "R0020" })
			if not landed.ok then
				error(`expected ./zn done R0020 to land with no second restack: {say(landed)}`)
			end
			t.expect(has(say(landed), "restack")).toBe(false)
			t.expect(git(f.origin, { "rev-parse", "main^1" })).toBe(tip)
			t.expect(
				fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{ROOT}/rafts/done/R0020/R0020.md` }).ok
			)
				.toBe(true)
		end
	)
end)
