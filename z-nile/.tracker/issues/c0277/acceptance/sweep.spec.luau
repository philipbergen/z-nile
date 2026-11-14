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

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
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
				[`{P}/c0070/c0070.md`] = trackerfix.stub("c0070", "c0070", "new-a-b-c"),
				[`{P}/c0071/c0071.md`] = trackerfix.stub("c0071", "c0071", "new-a-b-c"),
				[`{P}/c0072/c0072.md`] = trackerfix.stub("c0072", "c0072", "new-a-b-c"),
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = "# architecture\n",
				[`{P}/c0040/c0040.md`] = (string.gsub(
					string.gsub(
						trackerfix.stub("c0040", "c0040", "prepared-quiet-copper-falcon"),
						"design: draft",
						"design: ready"
					),
					"\nraft: \n",
					"\nraft: R0020\n",
					1
				)),
				[`{P}/c0040/check.sh`] = CHECK,
				["pickman/.tracker/rafts/R0020/R0020.md"] = "---\nid: R0020\ntype: chore\ntitle: Lost\nslug: lost\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0020\n",
				["pickman/.tracker/rafts/R0020/check.sh"] = CHECK,
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

	it(
		"work that landed under other shas is recovered: a squash-merged prep whose branch was deleted, a cherry-picked commit and a copied file",
		function()
			-- prep-sq: only a pushed commit; its remote branch is deleted after the squash merge (every sha on it unreachable)
			local sq = trim(must(zn(h.f.main, { "worktree", "prep-sq" }), "worktree"))
			must(zn(sq, { "status", "c0070", "preparing" }, T0), "claim c0070")
			fs.writeFile(`{sq}/pickman/sq.txt`, "squashed\n")
			fixture.git(sq, { "add", "-A" })
			fixture.git(sq, { "commit", "-q", "-m", "sq work" })
			fixture.git(sq, { "push", "-q", "origin", "HEAD:refs/heads/prep-sq" })
			-- prep-cp: an unpushed commit and an untracked file, both taken over into main by hand
			local cp = trim(must(zn(h.f.main, { "worktree", "prep-cp" }), "worktree"))
			must(zn(cp, { "status", "c0071", "preparing" }, T0), "claim c0071")
			fs.writeFile(`{cp}/pickman/cp-commit.txt`, "taken by cherry-pick\n")
			fixture.git(cp, { "add", "-A" })
			fixture.git(cp, { "commit", "-q", "-m", "cp work" })
			fs.writeFile(`{cp}/pickman/cp-file.txt`, "copied by hand\n")
			for _, name in { "prep-sq", "prep-cp" } do
				must(zn(h.f.main, { "worktree", name, "--takeover" }, LATE), `takeover {name}`)
			end
			-- main gets the work under new shas, from another clone: a squash of sq.txt, the cherry-picked and the copied file
			fixture.git(h.f.other, { "pull", "-q", "origin", "main" })
			local landed: { [string]: string } = {
				["sq.txt"] = "squashed\n",
				["cp-commit.txt"] = "taken by cherry-pick\n",
				["cp-file.txt"] = "copied by hand\n",
			}
			for file, text in landed do
				fs.writeFile(`{h.f.other}/pickman/{file}`, text)
			end
			fixture.git(h.f.other, { "add", "-A" })
			fixture.git(h.f.other, { "commit", "-q", "-m", "landed (squash)" })
			fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/prep-sq" }) -- the merged head branch is deleted
			-- the preps are over
			must(zn(dir("prep-sq-1"), { "status", "c0070", "new" }, LATE), "give back c0070")
			must(zn(dir("prep-cp-1"), { "status", "c0071", "new" }, LATE), "give back c0071")
			local r = zn(h.f.main, { "worktree-prune" }, LATE)
			must(r, "prune")
			t.expect(fs.isDir(gone("prep-sq"))).toBe(false)
			t.expect(fs.isDir(gone("prep-cp"))).toBe(false)
			t.expect(has(r.stdout, `removed {gone("prep-sq")}`)).toBe(true)
		end
	)

	it("an unreadable origin/main removes nothing", function()
		local w = trim(must(zn(h.f.main, { "worktree", "prep-blind" }), "worktree"))
		must(zn(w, { "status", "c0072", "preparing" }, T0), "claim c0072")
		must(zn(h.f.main, { "worktree", "prep-blind", "--takeover" }, LATE), "takeover")
		must(zn(dir("prep-blind-1"), { "status", "c0072", "new" }, LATE), "give back c0072") -- the work is over and holds nothing
		local gitShim = fs.readFile(`{h.bin}/git`)
		fs.writeFile(
			`{h.bin}/git`,
			(
				string.gsub(
					gitShim,
					"^#!/bin/sh\n",
					'#!/bin/sh\nif [ "$1" = fetch ] && [ -f "$FAKE_DIR/nofetch" ]; then echo "fatal: fake" >&2; exit 128; fi\n',
					1
				)
			)
		)
		fs.writeFile(`{h.fakes}/nofetch`, "1")
		zn(h.f.main, { "worktree-prune" }, LATE)
		fs.removeFile(`{h.fakes}/nofetch`)
		t.expect(fs.isDir(gone("prep-blind"))).toBe(true) -- origin could not be read: no claim is known to be over
		fs.writeFile(`{h.bin}/git`, gitShim)
		zn(h.f.main, { "worktree-prune" }, LATE)
		t.expect(fs.isDir(gone("prep-blind"))).toBe(false) -- read again, it goes
	end)

	it("stop removes the clean discarded worktree of the raft it gives back", function()
		local wt = trim(must(zn(h.f.main, { "worktree", "raft-sweep" }), "worktree"))
		must(zn(h.f.main, { "ready", "R0020" }, T0), "ready R0020") -- readied: its claim is active-…, beaten by ready
		-- the raft's worktree remembers the claim (z-run adopts it with beat --adopt)
		local rw = trim(must(zn(h.f.main, { "worktree", "R0020" }), "worktree"))
		must(zn(rw, { "beat", "R0020", "--adopt" }, T0), "adopt")
		must(zn(h.f.main, { "worktree", "R0020", "--takeover" }, LATE), "takeover the raft's worktree")
		t.expect(fs.isDir(dir("R0020-discarded-1"))).toBe(true)
		local r = zn(h.f.main, { "stop", "R0020" }, LATE)
		must(r, "stop")
		t.expect(fs.isDir(dir("R0020-discarded-1"))).toBe(false) -- the raft is given back: the clean discarded worktree goes
		t.expect(has(r.stderr, "removed discarded worktree")).toBe(true)
		t.expect(wt ~= "").toBe(true)
	end)
end)
