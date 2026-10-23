--!strict
-- c0114 AC14: finished items' check.sh files name the moved paths' new locations (decided with the user, 2026-10-21:
-- "Rewrite finished files"; the user's exception to "sequestered files never change", for finished items only, in
-- c0114's PR). rewrites.luau is the one rewrite and the fixed list of files it covers (those finished when c0114
-- lands); finished.luau (run by check.sh) checks each file against its base text. Reads the real tree, read-only;
-- writes only under .cache/c0114-finished and .cache/c0114-finished-tip.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local rewrites = require("./rewrites")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

-- every item id whose folder is under z-nile/.tracker in the tree at `base`
local function movedIds(base: string): { [string]: boolean }
	local moved: { [string]: boolean } = {}
	for _, kind in { "issues", "rafts" } do
		for _, state in { "", "active/", "done/" } do
			local dir = `{base}/z-nile/.tracker/{kind}/{state}`
			if fs.isDir(dir) then
				for _, id in fs.readDir(dir) do
					if string.match(id, "^[fdcR]%d%d%d%d$") then
						moved[id] = true
					end
				end
			end
		end
	end
	return moved
end

-- The listed files (rewrites.FINISHED, relative to `base`) that still name a moved path. Only the list is read, never
-- the live done/ folders: a raft that finishes later keeps its old paths (decided with the user, 2026-10-21: "Only
-- items done at landing"), and its `done` must not turn this spec red.
local function unsettled(base: string): { string }
	local moved = movedIds(base)
	local out: { string } = {}
	for _, f in rewrites.FINISHED do
		local path = `{base}/{f}`
		if not fs.isFile(path) then
			table.insert(out, `{f} (missing)`)
		else
			local text = fs.readFile(path)
			local settled = rewrites.paths(text, moved) == text
			-- an item whose special edits undo a rewrite (a spec case name) is settled when they give the same text
			if not settled and rewrites.SPECIAL[f] then
				local ok, again = pcall(rewrites.expected, f, text, moved)
				settled = ok and again == text
			end
			if not settled then
				table.insert(out, f)
			end
		end
	end
	return out
end

return t.spec("c0114 finished items' check.sh files name the new paths", function(it)
	it("the rewrite moves each moved path, the command and the moved items, and nothing else", function()
		local moved = { c0005 = true, R0013 = true }
		local function rw(text: string): string
			return rewrites.paths(text, moved)
		end
		t.expect(rw('source "$(git rev-parse --show-toplevel)/scripts/lib/ac.sh"'))
			.toBe('source "$(git rev-parse --show-toplevel)/z-nile/lib/ac.sh"')
		t.expect(rw("check x scripts/tracker.sh members R0013")).toBe("check x ./zn members R0013")
		t.expect(rw('bash "$ROOT/scripts/tracker.sh" find')).toBe('bash "$ROOT/zn" find')
		t.expect(rw("grep -qF 'tracker.sh launch' x")).toBe("grep -qF './zn launch' x")
		t.expect(rw("scripts/check.sh --full")).toBe("z-nile/check.sh --full")
		t.expect(rw("grep x scripts/tracker/main.luau")).toBe("grep x z-nile/engine/main.luau")
		t.expect(rw("cat tracker/templates/prompt.md")).toBe("cat z-nile/templates/prompt.md")
		t.expect(rw("bash tracker/issues/done/c0005/check.sh"))
			.toBe("bash z-nile/.tracker/issues/done/c0005/check.sh")
		t.expect(rw("bash tracker/rafts/done/R0013/check.sh"))
			.toBe("bash z-nile/.tracker/rafts/done/R0013/check.sh")
		-- a game item, the game's scripts, the counter, a skill and a longer path stay
		for _, same in
			{
				"bash tracker/issues/done/f0010/check.sh",
				"scripts/runtime-test.luau scripts/lib/opencloud.luau scripts/deploy-beta.luau",
				"tracker/next tracker/architecture.md",
				".claude/skills/tracker/SKILL.md .claude/skills/tracker/templates",
				"my-scripts/check.sh tracker2/templates",
			}
		do
			t.expect(rw(same)).toBe(same)
		end
		-- applied twice, it changes nothing more
		local once = rw("scripts/tracker.sh find c0005; scripts/lib/fence.sh; tracker/issues/c0005")
		t.expect(rw(once)).toBe(once)
	end)

	it("every check.sh finished when c0114 lands is already rewritten", function()
		t.expect(#rewrites.FINISHED > 100).toBe(true)
		local bad = unsettled(".")
		if #bad > 0 then
			error(`still naming a moved path: {table.concat(bad, ", ")}`)
		end
	end)

	it("a raft that finishes later with old paths in its check.sh leaves this spec green", function()
		-- a copy of the listed files, plus a later raft's done check.sh that sources the old ac.sh path
		local base = ".cache/c0114-finished"
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		for _, f in rewrites.FINISHED do
			local dir = string.match(f, "^(.*)/[^/]+$") :: string
			fs.writeDir(`{base}/{dir}`)
			fs.writeFile(`{base}/{f}`, fs.readFile(f))
		end
		fs.writeDir(`{base}/tracker/rafts/done/R9990`)
		fs.writeFile(
			`{base}/tracker/rafts/done/R9990/check.sh`,
			'source "$(git rev-parse --show-toplevel)/scripts/lib/ac.sh"\ncheck "RC0: gate" scripts/check.sh --full\nfinish\n'
		)
		fs.writeDir(`{base}/z-nile/.tracker/issues/done/c9990`)
		fs.writeFile(
			`{base}/z-nile/.tracker/issues/done/c9990/check.sh`,
			"bash scripts/tracker.sh members R9990\n"
		)
		t.expect(#unsettled(base)).toBe(0)
		fs.removeDir(base)
	end)

	it("each special edit names a listed finished file and applies once", function()
		for path, edits in rewrites.SPECIAL do
			t.expect(#edits > 0).toBe(true)
			if not table.find(rewrites.FINISHED, path) then
				error(`SPECIAL {path}: not a listed finished check.sh`)
			end
			local text = fs.readFile(path)
			for _, e in edits do
				t.expect(string.find(text, e[2], 1, true) ~= nil).toBe(true)
			end
		end
		t.expect(movedIds(".").c0114).toBe(true)
	end)

	it(
		"finished.luau reads main's tip from origin: a forged local ref stays red, and it refuses three ways",
		function()
			-- decided with the user, 2026-10-23 ("Allow the locked edit"): never the local origin/main
			local f = trackerfix.new("c0114-finished-tip", {
				["tracker/issues/c0200/c0200.md"] = trackerfix.stub("c0200", "c0200", "new-a-b-c"),
				["tracker/issues/c0200/check.sh"] = "echo base\n",
				["z-nile/.tracker/issues/active/c0114/c0114.md"] = "---\nid: c0114\nraft: R0043\n---\n",
			})
			local item = `{f.main}/z-nile/.tracker/issues/active/c0114`
			-- this folder before `done`, tests/acceptance/c0114 after it
			local script =
				`{fixture.physical(".")}/z-nile/.tracker/issues/active/c0114/acceptance/finished.luau`
			if not fs.isFile(script) then
				script = `{fixture.physical(".")}/tests/acceptance/c0114/finished.luau`
			end
			local function run(): fixture.Result
				return fixture.exec(f.main, "lune", { "run", script, item })
			end
			local function said(r: fixture.Result, needle: string)
				t.expect(r.ok).toBe(false)
				if not string.find(r.stdout .. r.stderr, needle, 1, true) then
					error(`finished.luau did not say "{needle}": {r.stdout}{r.stderr}`)
				end
			end
			t.expect(run().ok).toBe(true) -- nothing changed yet
			-- an unfinished item's check.sh changed on the branch: red
			fs.writeFile(`{f.main}/tracker/issues/c0200/check.sh`, "echo changed\n")
			fixture.git(f.main, { "commit", "-q", "-am", "edit a sequestered file" })
			said(run(), "changed: tracker/issues/c0200/check.sh")
			-- the author moves the local ref onto the branch: still red, since origin is asked
			fixture.git(f.main, { "update-ref", "refs/remotes/origin/main", "HEAD" })
			said(run(), "changed: tracker/issues/c0200/check.sh")
			-- origin's tip not in this checkout: refuse, asking for a fetch
			fixture.git(f.other, { "commit", "-q", "--allow-empty", "-m", "main moves on" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			said(run(), "which this checkout doesn't have: fetch")
			-- no shared history with origin's tip: refuse
			fixture.git(f.main, { "fetch", "-q", "origin" })
			fixture.git(f.main, { "checkout", "-q", "--orphan", "unrelated" })
			fixture.git(f.main, { "commit", "-q", "-m", "no shared history" })
			said(run(), "share no history")
			-- origin can't be read: refuse
			fixture.git(f.main, { "remote", "set-url", "origin", `{f.base}/missing.git` })
			said(run(), "cannot read main's tip from origin")
			fs.removeDir(f.base)
		end
	)
end)
