--!strict
-- f0437 step 5: the themes facts of the real board model, and the one writer (the board refresh, `./zn board`). A fixture
-- tracker under this home's .cache; the writer is asked for a throwaway folder, never the real live state.
local board = require("@znile/engine/board")
local fixlib = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local livecall = require("@znile/engine/livecall")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local themefacts = require("@znile/engine/themefacts")
local themewrite = require("@znile/engine/themewrite")
local trackerfix = require("@tests/lib/trackerfix")

local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local DIR = ".cache/theme-write"

local function fdoc(path: string, id: string, front: string, body: string?)
	fs.writeDir(path)
	fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n{body or ""}`)
end

-- alpha: R0009 done, R0010 active (a worker holds it), c0020 raftless and not started; R0011 is beta's raft with one member
-- that names alpha, so it counts in both; c0021 runs; c0022 waits; c0030 has questions.md; R0012 is an empty raft.
local function fixture(): string
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	local base = `{DIR}/tracker`
	fdoc(`{base}/rafts/done/R0009`, "R0009", "type: chore\ntitle: Landed\nstatus: done\ntributary: alpha")
	fdoc(`{base}/issues/done/c0009`, "c0009", "type: chore\ntitle: Landed\nraft: R0009\nstatus: done")
	fdoc(
		`{base}/rafts/active/R0010`,
		"R0010",
		"type: chore\ntitle: Running\ndesign: ready\nstatus: active-a-b-c\ntributary: alpha"
	)
	fdoc(
		`{base}/issues/active/c0010`,
		"c0010",
		"type: chore\ntitle: Running member\nraft: R0010\nstatus: active-a-b-c"
	)
	fdoc(`{base}/rafts/R0011`, "R0011", "type: chore\ntitle: Not started\ntributary: beta")
	fdoc(`{base}/issues/c0011`, "c0011", "type: chore\ntitle: Member\nraft: R0011\ntributary: alpha")
	fdoc(`{base}/rafts/R0012`, "R0012", "type: chore\ntitle: Empty raft\ntributary: beta")
	fdoc(`{base}/issues/c0020`, "c0020", "type: chore\ntitle: Raftless\ntributary: alpha")
	fdoc(
		`{base}/issues/active/c0021`,
		"c0021",
		"type: chore\ntitle: Raftless running\nstatus: active-d-e-f\ntributary: beta"
	)
	fdoc(
		`{base}/issues/c0022`,
		"c0022",
		"type: chore\ntitle: After the member\ndepends_on: [c0011]\ntributary: beta"
	)
	fdoc(`{base}/issues/c0030`, "c0030", "type: chore\ntitle: Blocked on you\ntributary: beta")
	fs.writeFile(`{base}/issues/c0030/questions.md`, "1. which one?\n")
	fdoc(`{base}/issues/c0040`, "c0040", "type: chore\ntitle: No theme")
	fs.writeFile(
		`{base}/tributaries.toml`,
		'[[tributary]]\nname = "alpha"\npurpose = "The first body."\n\n[[tributary]]\nname = "beta"\npurpose = "The second body."\n\n[[tributary]]\nname = "gamma"\npurpose = "Nothing yet."\n'
	)
	return `{base}`
end

local NO_FACTS: any = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }

return t.spec("f0437 theme facts from the board's model, and the one writer", function(it)
	it("counts each unit once per theme it belongs to, by the one rule", function()
		local base = fixture()
		local live: any = {
			at = 1,
			workers = { { id = "w1", cli = "claude", state = "working", can = {} } },
			claims = { { unit = "R0010", activity = "code", worker = "w1", since = 7 } },
		}
		local facts: any = NO_FACTS
		facts = { asOf = nil, refs = {}, worktrees = {}, dispatch = {}, live = live }
		local model = board.collect(base, nil, facts)
		local units = themefacts.units(model, {})
		local defs: { themefacts.ThemeDef } = {}
		for _, row in model.tributaries.tracker do
			if not row.implicit then
				table.insert(defs, { project = "tracker", name = row.name, purpose = row.purpose })
			end
		end
		t.expect(#defs).toBe(3)
		local built = themefacts.build({
			at = 9,
			themes = defs,
			units = units,
			approvalsAt = nil,
			approvalsScope = "",
			live = true,
		})
		local by: { [string]: themefacts.Theme } = {}
		for _, th in built.themes do
			by[th.id] = th
		end
		t.expect(by.alpha.counts).toEqual({ done = 1, flight = 1, approval = 0, owner = 0, open = 2 }) -- R0011 (by its member's line) and c0020; c0040 is unsorted
		t.expect(by.beta.counts).toEqual({ done = 0, flight = 1, approval = 0, owner = 1, open = 2 })
		t.expect(by.gamma.counts).toEqual({ done = 0, flight = 0, approval = 0, owner = 0, open = 0 })
		t.expect(by.unsorted.counts.open).toBe(1)
		t.expect(by.alpha.workers).toEqual({ "claude w1" })
		t.expect(by.beta.workers).toEqual({})
		t.expect(by.alpha.units[1].id).toBe("R0010")
		t.expect(by.alpha.units[1].stage).toBe("code")
		t.expect(by.alpha.units[1].holder).toBe("claude w1")
		fs.removeDir(DIR)
	end)

	it(
		"writes themes.json beside the approval facts, atomically, and reads the units that wait from them",
		function()
			local base = fixture()
			local live = `{HERE}/{DIR}/live`
			fs.writeDir(live)
			fs.writeFile(
				`{live}/approvals.json`,
				'{"version":1,"at":55,"run":"","scope":"","themes":[{"id":"alpha","rafts":[{"id":"R0011","tickets":[]}]}]}'
			)
			local model = board.collect(base, nil, NO_FACTS)
			local path = themewrite.write(live, model, "abc1234")
			t.expect(path).toBe(`{live}/themes.json`)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/themes.json`))
			t.expect(got.version).toBe(1)
			t.expect(got.live).toBe(false) -- the model carries no live snapshot: who holds what is unknown, and the file says so
			t.expect(got.approvalsAt).toBe(55)
			local names: { string } = {}
			for _, th in got.themes do
				table.insert(names, th.id)
			end
			t.expect(names).toEqual({ "alpha", "beta", "gamma", "unsorted" })
			t.expect(got.themes[1].counts.approval).toBe(1) -- R0011 waits, by the last approval queue
			t.expect(got.themes[2].counts.approval).toBe(1)
			for _, name in fs.readDir(live) do
				t.expect((string.find(name, "pickman-tmp", 1, true))).toBe(nil) -- no temporary file is left beside the facts
			end
			t.expect(got.commit).toBe("abc1234") -- the commit the tracker was read at is carried
			fs.removeDir(DIR)
		end
	)

	it(
		"with the live layer off and no folder named, the refresh writes nothing under the checkout's own .cache",
		function()
			local base = fixture()
			local root = `{HERE}/{DIR}/fake-main`
			fs.writeDir(root)
			-- the runner's fence turns the live layer off for every spec, and names no folder
			t.expect(livecall.off()).toBe(true)
			themewrite.refresh(root, board.collect(base, nil, NO_FACTS))
			t.expect(fs.isDir(`{root}/.cache`)).toBe(false) -- nothing at all, so no state folder either
			fs.removeDir(DIR)
		end
	)

	it(
		"the board refresh writes the facts to a named folder, and writes nothing when the live layer is off and none is named",
		function()
			local f = trackerfix.new("theme-write-board", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
			})
			local live = `{f.base}/livestate`
			local out = `{f.base}/page.html`
			local r = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", out }, {
				env = { ZN_LIVE = "off", ZN_LIVE_DIR = live },
			})
			t.expect(r.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/themes.json`))
			t.expect(got.version).toBe(1)
			t.expect(#got.themes > 0).toBe(true)
			fs.removeDir(live)
			local again = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", out }, {
				env = { ZN_LIVE = "off", ZN_LIVE_DIR = "" },
			})
			t.expect(again.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(false)
			fs.removeDir(f.base)
		end
	)

	it("a write replaces the file and never writes through a link left at its path", function()
		local base = fixture()
		local live = `{HERE}/{DIR}/live`
		fs.writeDir(live)
		fs.writeFile(`{HERE}/{DIR}/decoy.txt`, "decoy")
		local ln = process.exec("ln", { "-s", `{HERE}/{DIR}/decoy.txt`, `{live}/themes.json` })
		t.expect(ln.ok).toBe(true)
		themewrite.write(live, board.collect(base, nil, NO_FACTS))
		t.expect(fs.readFile(`{HERE}/{DIR}/decoy.txt`)).toBe("decoy")
		t.expect(fs.readFile(`{live}/themes.json`) ~= "decoy").toBe(true)
		fs.removeDir(DIR)
	end)

	it("the board counts a raft's and a ticket's questions.md as waiting on the owner", function()
		local base = fixture()
		fdoc(`{base}/rafts/R0013`, "R0013", "type: chore\ntitle: Asks\ntributary: gamma")
		fdoc(`{base}/issues/c0050`, "c0050", "type: chore\ntitle: Member of asking raft\nraft: R0013")
		fs.writeFile(`{base}/rafts/R0013/questions.md`, "1. which one?\n")
		local rows: { [string]: board.TributaryRow } = {}
		for _, row in board.collect(base, nil, NO_FACTS).tributaries.tracker do
			rows[row.name] = row
		end
		t.expect(rows.gamma.waiting).toBe(1) -- the raft's own questions.md
		t.expect(rows.beta.waiting).toBe(1) -- c0030's
		fs.removeDir(DIR)
	end)

	it("a written file wakes the daemon with the reason themes", function()
		local f = trackerfix.new("theme-write-poke", {
			["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
				"c0001",
				"One",
				"new-quiet-copper-falcon"
			),
		})
		local live = `{f.base}/livestate`
		local out = `{f.base}/page.html`
		local log = `{f.base}/calls.log`
		local stub = `{f.base}/znlive-stub`
		fs.writeFile(stub, `#!/bin/sh\necho "$@" >> {log}\nexit 3\n`)
		t.expect(process.exec("chmod", { "+x", stub }).ok).toBe(true)
		local r = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", out }, {
			env = { ZN_LIVE = "", ZN_LIVE_BIN = stub, ZN_LIVE_DIR = live },
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
		t.expect(string.find(fs.readFile(log), "poke --reason themes", 1, true) ~= nil).toBe(true)
		fs.removeDir(f.base)
	end)

	it("./zn sync in the main checkout writes the facts to a named folder, like the board command", function()
		local f = trackerfix.new("theme-write-sync", {
			["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
				"c0001",
				"One",
				"new-quiet-copper-falcon"
			),
		})
		local live = `{f.base}/livestate`
		local r = fixlib.exec(f.main, "./zn", { "sync" }, { env = { ZN_LIVE = "off", ZN_LIVE_DIR = live } })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
		fs.removeDir(f.base)
	end)

	it("a write that fails leaves the earlier facts alone and the refresh still returns", function()
		local base = fixture()
		local live = `{HERE}/{DIR}/live`
		local model = board.collect(base, nil, NO_FACTS)
		themewrite.write(live, model)
		local before = fs.readFile(`{live}/themes.json`)
		for _, r in model.rafts do
			r.title = "T \255"
		end
		for _, i in model.issues do
			i.title = "T \255"
		end
		t.expect((pcall(themewrite.write, live, model))).toBe(false) -- a stray byte cannot be encoded
		process.env.ZN_LIVE_DIR = live
		local ok = pcall(themewrite.refresh, `{HERE}/{DIR}/fake-main`, model)
		process.env.ZN_LIVE_DIR = nil
		t.expect(ok).toBe(true)
		-- the file is an older complete write with its own time and commit: it is not removed, for it may be what a newer refresh just wrote
		t.expect(fs.readFile(`{live}/themes.json`)).toBe(before)
		fs.removeDir(DIR)
	end)

	it(
		"the board's per-theme counts equal the themes facts' counts, phase by phase (f0437 round 2: one fact per unit)",
		function()
			local base = fixture()
			-- a raft with a member that asks (the raft is waiting on the owner), a stored claim nobody holds (counts as not started),
			-- a prepared raft whose member a live worker holds (in flight) and a raft that names two themes through its members
			fdoc(`{base}/rafts/R0014`, "R0014", "type: chore\ntitle: Member asks\ntributary: alpha")
			fdoc(`{base}/issues/c0060`, "c0060", "type: chore\ntitle: Asks\nraft: R0014")
			fs.writeFile(`{base}/issues/c0060/questions.md`, "1. which one?\n")
			fdoc(
				`{base}/issues/c0061`,
				"c0061",
				"type: chore\ntitle: Claimed\nstatus: preparing-a-b-c\ntributary: alpha"
			)
			fdoc(`{base}/rafts/R0015`, "R0015", "type: chore\ntitle: Held\ntributary: beta")
			fdoc(`{base}/issues/c0062`, "c0062", "type: chore\ntitle: Held member\nraft: R0015")
			fdoc(`{base}/rafts/R0016`, "R0016", "type: chore\ntitle: Two themes\ntributary: gamma")
			fdoc(
				`{base}/issues/c0063`,
				"c0063",
				"type: chore\ntitle: Names alpha\nraft: R0016\ntributary: alpha"
			)
			local facts: any = {
				asOf = nil,
				refs = {},
				worktrees = {},
				dispatch = {},
				live = {
					at = 1,
					workers = { { id = "w2", cli = "kimi", state = "working", can = {} } },
					claims = {
						{ unit = "c0062", activity = "bundle", worker = "w2", raft = "R0015", since = 3 },
					},
				},
			}
			local model = board.collect(base, nil, facts)
			local defs: { themefacts.ThemeDef } = {}
			for _, row in model.tributaries.tracker do
				if not row.implicit then
					table.insert(defs, { project = "tracker", name = row.name, purpose = row.purpose })
				end
			end
			local built = themefacts.build({
				at = 9,
				themes = defs,
				units = themefacts.units(model, {}),
				approvalsAt = nil,
				approvalsScope = "",
				live = true,
			})
			local by: { [string]: themefacts.Theme } = {}
			for _, th in built.themes do
				by[th.id] = th
			end
			local compared = 0
			for _, row in model.tributaries.tracker do
				local th = by[row.name]
				t.expect(th ~= nil).toBe(true)
				t.expect(row.done).toBe(th.counts.done)
				t.expect(row.inFlight).toBe(th.counts.flight)
				t.expect(row.waiting).toBe(th.counts.owner + th.counts.approval)
				t.expect(row.notStarted).toBe(th.counts.open)
				compared += 1
			end
			t.expect(compared >= 4).toBe(true) -- alpha, beta, gamma and unsorted
			-- the cases themselves, so the equality is not between two zeros
			t.expect(by.alpha.counts.owner).toBe(1) -- R0014: its member asks
			t.expect(by.beta.counts.flight >= 2).toBe(true) -- R0015 held through its member, and the active raftless c0021
			t.expect(by.alpha.counts.open >= 3).toBe(true) -- c0061 (a claim nobody holds) and R0016 (through its member) among them
			t.expect(by.gamma.counts.open).toBe(1) -- R0016 in its own theme
			local claimed = false
			for _, u in by.alpha.units do
				if u.id == "c0061" then
					claimed = u.phase == "claimed"
				end
			end
			t.expect(claimed).toBe(true)
			fs.removeDir(DIR)
		end
	)

	it(
		"./zn board in a worktree writes no themes file: only the main checkout's tracker is the app's",
		function()
			local f = trackerfix.new("theme-write-tree", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
			})
			local live = `{f.base}/livestate`
			local env = { ZN_LIVE = "off", ZN_LIVE_DIR = live }
			local tree = `{f.base}/tree`
			fixlib.git(f.main, { "worktree", "add", "-q", "-b", "tree-branch", tree })
			local inTree = fixlib.exec(
				tree,
				"./zn",
				{ "board", "-O", "--out", `{f.base}/tree-page.html` },
				{ env = env }
			)
			t.expect(inTree.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(false) -- a branch's tracker is not the app's
			local inMain = fixlib.exec(
				f.main,
				"./zn",
				{ "board", "-O", "--out", `{f.base}/main-page.html` },
				{ env = env }
			)
			t.expect(inMain.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/themes.json`))
			t.expect(#got.commit >= 7).toBe(true) -- the short commit the facts were read at
			fs.removeDir(f.base)
		end
	)

	it(
		"a claimed unit's day is the commit that wrote the status line, and a raft claimed through members takes the oldest",
		function()
			local function doc(id: string, raft: string, status: string, body: string): string
				return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: slug-{id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-01\nstatus: {status}\n---\n\n# {id}\n{body}`
			end
			local root = "pickman/.tracker"
			local f = trackerfix.new("theme-write-claimday", {
				[`{root}/issues/c0001/c0001.md`] = doc("c0001", "", "new-quiet-copper-falcon", ""),
				[`{root}/issues/c0002/c0002.md`] = doc("c0002", "R0001", "new-quiet-copper-falcon", ""),
				[`{root}/issues/c0003/c0003.md`] = doc("c0003", "R0001", "new-quiet-copper-falcon", ""),
				[`{root}/rafts/R0001/R0001.md`] = `---\nid: R0001\ntype: chore\ntitle: Raft\nslug: raft-r\nsingle: false\nissues: [c0002, c0003]\ndesign: draft\ncreated: 2026-10-01\nstatus: new-quiet-copper-falcon\n---\n\n# R0001\n`,
			})
			local function commit(day: string, message: string)
				fixlib.exec(f.main, "git", { "add", "-A" }, {})
				local r = fixlib.exec(
					f.main,
					"git",
					{ "commit", "-q", "-m", message },
					{ env = { GIT_COMMITTER_DATE = `{day}T12:00:00Z`, GIT_AUTHOR_DATE = `{day}T12:00:00Z` } }
				)
				t.expect(r.ok).toBe(true)
			end
			local function setStatus(id: string, dir: string, status: string, day: string)
				local file = `{f.main}/{root}/{dir}/{id}/{id}.md`
				fs.writeFile(file, (string.gsub(fs.readFile(file), "status: [%w%-]+", `status: {status}`)))
				commit(day, `claim {id}`)
			end
			setStatus("c0001", "issues", "preparing-aa-bb-cc", "2026-10-31")
			setStatus("c0002", "issues", "preparing-dd-ee-ff", "2026-11-02")
			setStatus("c0003", "issues", "preparing-gg-hh-ii", "2026-10-30")
			-- a later commit whose BODY quotes the first stamp must not become its day
			local file = `{f.main}/{root}/issues/c0001/c0001.md`
			fs.writeFile(file, fs.readFile(file) .. "\nTaken earlier as preparing-aa-bb-cc, see the log.\n")
			commit("2026-11-20", "quote the stamp in the body")
			local model = board.collect(`{f.main}/{root}`, nil, NO_FACTS)
			local day: { [string]: string? } = {}
			for _, i in model.issues do
				day[i.id] = i.claimedAt
			end
			for _, r in model.rafts do
				day[r.id] = r.claimedAt
			end
			t.expect(day["c0001"]).toBe("2026-10-31") -- the line's commit, not the body's
			t.expect(day["R0001"]).toBe("2026-10-30") -- the raft itself is not claimed: the oldest of its members' days
			fs.removeDir(f.base)
		end
	)
end)
