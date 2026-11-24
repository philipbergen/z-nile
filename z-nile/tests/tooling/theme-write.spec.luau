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

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
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
		local units = themefacts.units(model, {}, model.live)
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
			local path = themewrite.write(live, model)
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
			t.expect(fs.isFile(`{live}/themes.json.tmp`)).toBe(false)
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
			t.expect(fs.isFile(`{root}/.cache/live/themes.json`)).toBe(false)
			t.expect(fs.isDir(`{root}/.cache`)).toBe(false)
			fs.removeDir(DIR)
		end
	)

	it(
		"the board refresh writes the facts to a named folder, and writes nothing when the live layer is off and none is named",
		function()
			fixture()
			local live = `{HERE}/{DIR}/live`
			local out = `{HERE}/{DIR}/page.html`
			local r = process.exec("scripts/tracker.sh", { "board", "-O", "--out", out }, {
				cwd = TOP,
				env = { ZN_LIVE = "off", ZN_LIVE_DIR = live },
			})
			t.expect(r.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/themes.json`))
			t.expect(got.version).toBe(1)
			t.expect(#got.themes > 0).toBe(true)
			fs.removeDir(live)
			local again = process.exec("scripts/tracker.sh", { "board", "-O", "--out", out }, {
				cwd = TOP,
				env = { ZN_LIVE = "off", ZN_LIVE_DIR = "" },
			})
			t.expect(again.ok).toBe(true)
			t.expect(fs.isFile(`{live}/themes.json`)).toBe(false)
			fs.removeDir(DIR)
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
		fixture()
		local live = `{HERE}/{DIR}/live`
		local out = `{HERE}/{DIR}/page.html`
		local log = `{HERE}/{DIR}/calls.log`
		local stub = `{HERE}/{DIR}/znlive-stub`
		fs.writeFile(stub, `#!/bin/sh\necho "$@" >> {log}\nexit 3\n`)
		t.expect(process.exec("chmod", { "+x", stub }).ok).toBe(true)
		local r = process.exec("scripts/tracker.sh", { "board", "-O", "--out", out }, {
			cwd = TOP,
			env = { ZN_LIVE = "", ZN_LIVE_BIN = stub, ZN_LIVE_DIR = live },
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
		t.expect(string.find(fs.readFile(log), "poke --reason themes", 1, true) ~= nil).toBe(true)
		fs.removeDir(DIR)
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

	it("a facts file that cannot be written is removed and the refresh still returns", function()
		local base = fixture()
		local live = `{HERE}/{DIR}/live`
		local model = board.collect(base, nil, NO_FACTS)
		themewrite.write(live, model)
		t.expect(fs.isFile(`{live}/themes.json`)).toBe(true)
		for _, r in model.rafts do
			r.title = "T \255"
		end
		for _, i in model.issues do
			i.title = "T \255"
		end
		t.expect(pcall(themewrite.write, live, model)).toBe(false) -- a stray byte cannot be encoded
		process.env.ZN_LIVE_DIR = live
		local ok = pcall(themewrite.refresh, `{HERE}/{DIR}/fake-main`, model)
		process.env.ZN_LIVE_DIR = nil
		t.expect(ok).toBe(true)
		t.expect(fs.isFile(`{live}/themes.json`)).toBe(false)
		fs.removeDir(DIR)
	end)
end)
