--!strict
-- c0277: a discarded worktree is kept until the work it was discarded for ends (Q1, Q2: the raft merged or was stopped, the
-- prep merged or was given back), then removed with its renamed branch by `./zn sync` and `./zn worktree-prune` (`done`
-- and `stop` run the same sweep); one that still holds uncommitted files or commits that exist nowhere else is kept and
-- listed by `./zn reap`, never removed: the work is not lost with the worktree. The copy of a done raft goes with it.
-- Time is ZN_NOW. Fixture under .cache/c0277-sweep.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local LATE = T0 + 3 * heartbeat.STALE
local P = "pickman/.tracker/issues"
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"\n  exit 0\nfi\nexit 0\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function dir(name: string): string
	return `{h.f.main}/.worktree/{name}`
end
local function gone(name: string): string -- the renamed directory of a discarded worktree
	return dir(`{name}-discarded-1`)
end
local function branches(): string
	return fixture.git(h.f.main, { "branch", "--format=%(refname:short)" })
end
-- an old worker in `name` that claimed `id`, pushed its branch, and then left `extra` behind
local function worker(name: string, id: string, extra: (string) -> ())
	local wt = trim(must(zn(h.f.main, { "worktree", name }), "worktree"))
	must(zn(wt, { "status", id, "preparing" }, T0), `claim {id}`)
	fs.writeFile(`{wt}/pickman/{name}.txt`, "pushed\n")
	fixture.git(wt, { "add", "-A" })
	fixture.git(wt, { "commit", "-q", "-m", `{name} pushed` })
	fixture.git(wt, { "push", "-q", "origin", `HEAD:refs/heads/{name}` })
	extra(wt)
end

return t.spec("c0277 discarded worktrees go when their work ends", function(it)
	it(
		"sets up three old workers (clean, uncommitted file, unpushed commit) and a raft's done copy, all taken over",
		function()
			h = fakecli.new("c0277-sweep", {
				[`{P}/c0010/c0010.md`] = trackerfix.stub("c0010", "c0010", "new-a-b-c"),
				[`{P}/c0020/c0020.md`] = trackerfix.stub("c0020", "c0020", "new-a-b-c"),
				[`{P}/c0030/c0030.md`] = trackerfix.stub("c0030", "c0030", "new-a-b-c"),
				["pickman/.tracker/rafts/done/R0010/R0010.md"] = "---\nid: R0010\ntype: chore\nstatus: done\n---\n",
			})
			fs.writeFile(`{h.bin}/gh`, GH)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			worker("prep-clean", "c0010", function(_) end)
			worker("prep-dirty", "c0020", function(wt)
				fs.writeFile(`{wt}/pickman/untracked.txt`, "kept\n")
			end)
			worker("prep-ahead", "c0030", function(wt)
				fs.writeFile(`{wt}/pickman/ahead.txt`, "local\n")
				fixture.git(wt, { "add", "-A" })
				fixture.git(wt, { "commit", "-q", "-m", "ahead of the remote" })
			end)
			for _, name in { "prep-clean", "prep-dirty", "prep-ahead" } do
				must(zn(h.f.main, { "worktree", name, "--takeover" }, LATE), `takeover {name}`)
			end
			-- a done raft's numbered copy and an unfinished one's
			fixture.git(h.f.main, { "worktree", "add", "-q", "--detach", dir("R0010-1"), "HEAD" })
			fixture.git(h.f.main, { "worktree", "add", "-q", "--detach", dir("R0011-1"), "HEAD" })
		end
	)

	it(
		"while a discarded worktree's claim is still a claim, prune keeps it and says whose work it holds",
		function()
			local r = zn(h.f.main, { "worktree-prune" }, LATE)
			must(r, "prune")
			for _, name in { "prep-clean", "prep-dirty", "prep-ahead" } do
				t.expect(fs.isDir(gone(name))).toBe(true)
				t.expect(has(r.stdout, `{gone(name)}: holds the discarded work of`)).toBe(true)
			end
			t.expect(has(branches(), "prep-clean-discarded-1")).toBe(true)
			-- the copy of a done raft goes with the raft, an unfinished raft's copy stays
			t.expect(fs.isDir(dir("R0010-1"))).toBe(false)
			t.expect(fs.isDir(dir("R0011-1"))).toBe(true)
			-- and a plain reap lists nothing: no work has ended yet
			t.expect(has(zn(h.f.main, { "reap", "--dry-run" }, LATE).stderr, "left over")).toBe(false)
		end
	)

	it(
		"when the work ends, a clean discarded worktree goes with its branch; one with unrecovered work is kept",
		function()
			-- the three preps are given back (from the takers' copies, which remember nothing)
			for _, id in { "c0010", "c0020", "c0030" } do
				local copy = if id == "c0010"
					then "prep-clean-1"
					elseif id == "c0020" then "prep-dirty-1"
					else "prep-ahead-1"
				must(zn(dir(copy), { "status", id, "new" }, LATE), `give back {id}`)
			end
			local synced = zn(h.f.main, { "sync" }, LATE)
			must(synced, "sync")
			t.expect(fs.isDir(gone("prep-clean"))).toBe(false)
			t.expect(has(branches(), "prep-clean-discarded-1")).toBe(false)
			t.expect(has(synced.stderr, `removed discarded worktree {gone("prep-clean")}`)).toBe(true)
			-- uncommitted files and commits on no origin ref are never removed
			t.expect(fs.isFile(`{gone("prep-dirty")}/pickman/untracked.txt`)).toBe(true)
			t.expect(fs.isDir(gone("prep-ahead"))).toBe(true)
			t.expect(has(branches(), "prep-ahead-discarded-1")).toBe(true)
			t.expect(has(synced.stderr, `kept discarded worktree {gone("prep-dirty")}`)).toBe(true)
			t.expect(has(synced.stderr, "1 uncommitted file(s)")).toBe(true)
			t.expect(has(synced.stderr, "1 commit(s) exist nowhere else")).toBe(true)
		end
	)

	it("a plain reap lists what was left over and removes none of it", function()
		local r = zn(h.f.main, { "reap", "--dry-run" }, LATE)
		t.expect(has(r.stderr, `reap: discarded worktree left over {gone("prep-dirty")}`)).toBe(true)
		t.expect(has(r.stderr, `reap: discarded worktree left over {gone("prep-ahead")}`)).toBe(true)
		t.expect(fs.isDir(gone("prep-dirty"))).toBe(true)
		-- the session-end and quiet forms say nothing of them
		t.expect(has(zn(h.f.main, { "reap", "--session-end" }, LATE).stderr, "left over")).toBe(false)
		t.expect(has(zn(h.f.main, { "reap", "--quiet" }, LATE).stderr, "left over")).toBe(false)
	end)

	it(
		"once the work is recovered (committed and pushed, nothing uncommitted) the sweep removes it",
		function()
			local dirty = gone("prep-dirty")
			fs.removeFile(`{dirty}/pickman/untracked.txt`)
			local ahead = gone("prep-ahead")
			fixture.git(ahead, { "push", "-q", "origin", "HEAD:refs/heads/prep-ahead-recovered" })
			local r = zn(h.f.main, { "worktree-prune" }, LATE)
			must(r, "prune")
			t.expect(fs.isDir(dirty)).toBe(false)
			t.expect(fs.isDir(ahead)).toBe(false)
			t.expect(has(branches(), "discarded")).toBe(false)
			t.expect(has(r.stdout, `removed {dirty}`)).toBe(true)
		end
	)
end)
