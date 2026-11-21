--!strict
-- f0399 AC13, AC14: a raft readied `--on` a raft that has not landed (its ready commit records On:, `start` builds a base
-- commit on the base's top layer, restack and done put it on main). Real git in a fixture under .cache (a bare origin
-- whose path contains github.com, a worktree per raft and a `gh` stub that keeps each pull request's base).
--   R0010 (D) holds two chores: c0010 and c0020, which adds src/base.luau.
--   R0020 (R) holds the feature f0030, which depends on c0020 and whose check needs src/base.luau.
--   R0030 holds f0040, which depends on c0020 and on c0090 (in no raft); R0040 holds f0050, which depends on nothing.
-- Every issue is approved at the seed, so approval plays no part here. Cases run in order and share the fixture.
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

local function issue(id: string, kind: string, raft: string, deps: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, kind: string, issues: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n`
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

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

local f: trackerfix.Fixture = nil :: any
local setUpA = false
local log = ""
local env: { [string]: string } = {}
local wtD, wtR = "", ""
local built, onBase, laidOut = false, false, false
local DOC20 = raftDoc("R0020", "feature", "f0030")

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

-- a setup command: today's engine runs it, so a failure is a broken fixture
local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- an f0399 command: not built yet, so a failure is the assertion that it works
local function expectOk(r: fixture.Result, what: string): string
	if not r.ok then
		error(`expected ./zn {what} to succeed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{id} work`)
end

local function setup()
	if setUpA then
		return
	end
	setUpA = true
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
	}
	local function item(id: string, doc: string, check: string)
		seed[`{ROOT}/issues/{id}/{id}.md`] = doc
		seed[`{ROOT}/issues/{id}/check.sh`] = check
	end
	local function raft(id: string, kind: string, issues: string)
		seed[`{ROOT}/rafts/{id}/{id}.md`] = raftDoc(id, kind, issues)
		seed[`{ROOT}/rafts/{id}/check.sh`] = CHECK
	end
	raft("R0010", "chore", "c0010, c0020")
	raft("R0020", "feature", "f0030")
	raft("R0030", "feature", "f0040")
	raft("R0040", "feature", "f0050")
	item("c0010", issue("c0010", "chore", "R0010", ""), CHECK)
	item("c0020", issue("c0020", "chore", "R0010", ""), CHECK)
	item("f0030", issue("f0030", "feature", "R0020", "c0020"), CHECK_BASE)
	item("f0040", issue("f0040", "feature", "R0030", "c0020, c0090"), CHECK)
	item("f0050", issue("f0050", "feature", "R0040", ""), CHECK)
	item("c0090", issue("c0090", "chore", "", ""), CHECK)
	f = trackerfix.new("f0399-on-github.com", seed)
	local bin, state = `{f.base}/bin`, `{f.base}/state`
	log = `{f.base}/gh.log`
	fs.writeDir(bin)
	fs.writeDir(state)
	fs.writeFile(`{bin}/gh`, (string.gsub(string.gsub(GH, "@LOG@", log), "@STATE@", state)))
	process.exec("chmod", { "+x", `{bin}/gh` })
	env = { PATH = `{bin}:{process.env.PATH or ""}` }
end

local function sealAgain(dir: string, raftId: string)
	-- a trace written again after a restack may differ in nothing but the commit it names; a repeat that changes
	-- nothing is not a failure of the layers
	pcall(seal.trace, dir, raftId)
end

local function readyBody(raft: string): string
	return git(f.origin, { "log", "-1", "--format=%B", `--grep=^tracker: ready {raft} `, "main" })
end

local function withoutStatus(doc: string): string
	return (string.gsub(doc, "\nstatus: [^\n]*", ""))
end

return t.spec("f0399: a raft built on a raft that has not landed", function(it)
	it(
		"ready --on refuses a base that is not active, has an unfinished layer, does not hold every unmet dependency, or holds none",
		function()
			setup()
			local plain = tr(f.main, { "ready", "R0020" })
			t.expect(plain.ok).toBe(false)
			t.expect(has(say(plain), "it must be done first")).toBe(true)

			-- D is still in the backlog
			local inactive = tr(f.main, { "ready", "R0020", "--on", "R0010" })
			t.expect(inactive.ok).toBe(false)
			t.expect(has(say(inactive), "--on R0010: R0010 is not an active raft")).toBe(true)

			-- D is active and has no layer yet: nothing in R0040 depends on it, and f0040 depends on c0090 too
			zn(f.main, { "ready", "R0010" })
			local none = tr(f.main, { "ready", "R0040", "--on", "R0010" })
			t.expect(none.ok).toBe(false)
			t.expect(has(say(none), "--on R0010: nothing in R0040 depends on R0010")).toBe(true)
			local partial = tr(f.main, { "ready", "R0030", "--on", "R0010" })
			t.expect(partial.ok).toBe(false)
			t.expect(has(say(partial), "f0040 depends on c0090, which is not done and not in R0010"))
				.toBe(true)
			local open = tr(f.main, { "ready", "R0020", "--on", "R0010" })
			t.expect(open.ok).toBe(false)
			t.expect(has(say(open), "R0010's layer for c0010 is not finished")).toBe(true)

			-- every layer of D is built and finished
			wtD = zn(f.main, { "worktree", "R0010" })
			zn(wtD, { "start", "R0010" })
			write(
				wtD,
				`{ROOT}/rafts/active/R0010/final-review-001.md`,
				"# Final Review 001\n\nVerdict: approve\n"
			)
			layerWork(wtD, "alpha", "c0010")
			zn(wtD, { "finish", "c0010" })
			local half = tr(f.main, { "ready", "R0020", "--on", "R0010" })
			t.expect(half.ok).toBe(false)
			t.expect(has(say(half), "R0010's layer for c0020 is not finished")).toBe(true)
			zn(wtD, { "start", "R0010" })
			layerWork(wtD, "base", "c0020")
			zn(wtD, { "finish", "c0020" })
			laidOut = true
		end
	)

	it("ready --on readies the raft and records On: and Lands: approved in its ready commit", function()
		setup()
		t.expect(laidOut).toBe(true)
		local r = tr(f.main, { "ready", "R0020", "--on", "R0010" })
		t.expect(has(expectOk(r, "ready R0020 --on R0010"), "readied R0020")).toBe(true)
		local body = readyBody("R0020")
		t.expect(has(body, "On: R0010")).toBe(true)
		t.expect(has(body, "Lands: approved")).toBe(true)
		t.expect(withoutStatus(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) or ""))
			.toBe(withoutStatus(DOC20))
		t.expect(onOrigin(`{ROOT}/issues/active/f0030/f0030.md`) ~= nil).toBe(true)
		-- plain ready records no On:
		t.expect(has(readyBody("R0010"), "On:")).toBe(false)
	end)

	it(
		"start builds the base commit on the base's top layer with the raft's own folders as on main, cuts the first layer from it as an active raft, and stack says built on",
		function()
			setup()
			t.expect(has(readyBody("R0020"), "On: R0010")).toBe(true)
			wtR = zn(f.main, { "worktree", "R0020" })
			expectOk(tr(wtR, { "start", "R0020" }), "start R0020 (on R0010)")
			onBase = true
			git(wtR, { "fetch", "-q", "origin" })
			local top = git(wtR, { "rev-parse", "origin/R0010/2/c0020" })
			local base = git(wtR, { "rev-parse", "origin/R0020/base" })
			t.expect(git(wtR, { "log", "-1", "--format=%s", base })).toBe("tracker: base R0020 on R0010")
			t.expect(git(wtR, { "rev-parse", `{base}^` })).toBe(top)
			-- the base commit changes only R0020's folder and f0030's folder, at both state paths
			local own = {
				`{ROOT}/rafts/R0020/`,
				`{ROOT}/rafts/active/R0020/`,
				`{ROOT}/issues/f0030/`,
				`{ROOT}/issues/active/f0030/`,
			}
			local changed = string.split(git(wtR, { "diff", "--name-only", top, base }), "\n")
			t.expect(#changed > 0 and changed[1] ~= "").toBe(true)
			for _, path in changed do
				local inside = false
				for _, prefix in own do
					inside = inside or string.sub(path, 1, #prefix) == prefix
				end
				t.expect(inside).toBe(true)
			end
			local tree = git(wtR, { "ls-tree", "-r", "--name-only", base })
			t.expect(has(tree, `{ROOT}/rafts/active/R0020/R0020.md`)).toBe(true)
			t.expect(has(tree, `{ROOT}/issues/active/f0030/f0030.md`)).toBe(true)
			t.expect(has(tree, `{ROOT}/issues/f0030/`)).toBe(false)
			t.expect(has(tree, `{ROOT}/rafts/R0020/`)).toBe(false)
			t.expect((string.gsub(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) or "", "%s+$", "")))
				.toBe(git(wtR, { "show", `{base}:{ROOT}/rafts/active/R0020/R0020.md` }))
			-- the worktree reads R0020 as active, with its folders really there
			t.expect(git(wtR, { "branch", "--show-current" })).toBe("R0020/1/f0030")
			t.expect(fixture.exec(wtR, "git", { "merge-base", "--is-ancestor", base, "HEAD" }).ok).toBe(true)
			t.expect(fs.isFile(`{wtR}/{ROOT}/rafts/active/R0020/R0020.md`)).toBe(true)
			t.expect(fs.isFile(`{wtR}/{ROOT}/issues/active/f0030/f0030.md`)).toBe(true)
			t.expect(fs.isDir(`{wtR}/{ROOT}/issues/f0030`)).toBe(false)
			t.expect(has(fs.readFile(log), "--base R0020/base --head R0020/1/f0030")).toBe(true)
			t.expect(has(zn(wtR, { "stack", "R0020" }), "built on R0010 (R0010/2/c0020)")).toBe(true)

			write(
				wtR,
				`{ROOT}/rafts/active/R0020/final-review-001.md`,
				"# Final Review 001\n\nVerdict: approve\n"
			)
			write(wtR, `{ROOT}/rafts/active/R0020/review-001.md`, "# Review 001\n\nVerdict: approve\n")
			layerWork(wtR, "feature", "f0030")
			-- its check needs src/base.luau, which only D's second layer has
			t.expect(tr(wtR, { "finish", "f0030" }).ok).toBe(true)
			t.expect(git(wtR, { "rev-parse", "HEAD^" })).toBe(base)
			built = true
		end
	)

	it("done refuses while the base has not landed", function()
		setup()
		t.expect(built).toBe(true)
		seal.trace(wtR, "R0020")
		local before = git(f.origin, { "rev-parse", "main" })
		local r = tr(wtR, { "done", "R0020" })
		t.expect(r.ok).toBe(false)
		t.expect(
			has(
				say(r),
				"R0020 is built on R0010, which has not landed: ./zn done R0010 first, then ./zn restack R0020"
			)
		).toBe(true)
		t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
		-- f0420: with --one the raft's own wait stays; named alone, the session is given the base's activity
		local next = tr(f.main, { "work", "next", "R0020", "--one" })
		t.expect(has(say(next), "R0020: wait - ")).toBe(true)
		t.expect(has(say(next), "is built on R0010, which has not landed")).toBe(true)
		local walked = tr(f.main, { "work", "next", "R0020" })
		t.expect(has(say(walked), "R0010 layer ")).toBe(true)
		t.expect(has(say(walked), "For R0020: ")).toBe(true)
		t.expect(has(say(walked), "is built on R0010, which has not landed")).toBe(false)
	end)

	it(
		"after the base lands restack puts the raft on main with only its own commits and no backlog copy, and done lands it",
		function()
			setup()
			t.expect(built).toBe(true)
			-- readying R0020 moved main, so the base raft is restacked before it is sealed
			zn(wtD, { "restack", "R0010" })
			seal.trace(wtD, "R0010")
			zn(wtD, { "done", "R0010" })
			t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)

			git(wtR, { "push", "-q", "origin", "R0020/1/f0030" })
			expectOk(tr(wtR, { "restack", "R0020" }), "restack R0020")
			git(wtR, { "fetch", "-q", "origin" })
			local layer = "origin/R0020/1/f0030"
			t.expect(fixture.exec(wtR, "git", { "merge-base", "--is-ancestor", "origin/main", layer }).ok)
				.toBe(true)
			local subjects = string.split(git(wtR, { "log", "--format=%s", `origin/main..{layer}` }), "\n")
			local own = 0
			for _, subject in subjects do
				t.expect(string.match(subject, "^c0010") == nil and string.match(subject, "^c0020") == nil)
					.toBe(true)
				t.expect(
					string.match(subject, "^R0010") == nil and string.match(subject, "^tracker: base") == nil
				)
					.toBe(true)
				if string.sub(subject, 1, 7) == "f0030: " then
					own += 1
				end
			end
			t.expect(own).toBe(1)
			local tree = git(wtR, { "ls-tree", "-r", "--name-only", layer })
			t.expect(has(tree, `{ROOT}/issues/f0030/`)).toBe(false)
			t.expect(has(tree, `{ROOT}/rafts/R0020/`)).toBe(false)
			t.expect(has(tree, `{ROOT}/issues/active/f0030/f0030.md`)).toBe(true)
			t.expect(has(fs.readFile(log), "pr edit 21 --base main")).toBe(true)

			git(wtR, { "reset", "-q", "--hard", layer })
			sealAgain(wtR, "R0020")
			local landed = tr(wtR, { "done", "R0020" })
			t.expect(has(expectOk(landed, "done R0020"), "landed R0020")).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/f0030/f0030.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/done/R0020/R0020.md`) ~= nil).toBe(true)
			t.expect(onBase).toBe(true)
		end
	)
end)
