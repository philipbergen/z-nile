--!strict
-- f0437 step 6, slice 2: the one writer of units.json (the board refresh, beside themes.json). It writes in the main checkout
-- only, atomically and never through a link, in a pcall of its own that never fails the refresh, and writes nothing (and wakes
-- nobody) when the body of the file would be the same. Fixtures under this home's .cache; never the real live state.
local approvalfacts = require("@znile/engine/approvalfacts")
local board = require("@znile/engine/board")
local fixlib = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local unitswrite = require("@znile/engine/unitswrite")

local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local DIR = ".cache/units-write"
local NO_FACTS: any = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }
local NO_TEMPLATES = approvalfacts.templateComments({})

local function fdoc(path: string, id: string, front: string)
	fs.writeDir(path)
	fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n\n## Problem\nIt is a problem.\n`)
end

local function modelOf(title: string): board.Model
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	local base = `{DIR}/tracker`
	fdoc(`{base}/issues/c0001`, "c0001", `type: chore\ntitle: {title}`)
	fdoc(`{base}/issues/done/c0002`, "c0002", "type: chore\ntitle: Done\nstatus: done")
	return board.collect(base, nil, NO_FACTS)
end

local function stubBin(dir: string): (string, string)
	local log, stub = `{dir}/calls.log`, `{dir}/znlive-stub`
	fs.writeFile(stub, `#!/bin/sh\necho "$@" >> {log}\nexit 3\n`)
	t.expect(process.exec("chmod", { "+x", stub }).ok).toBe(true)
	return log, stub
end

local function count(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local s, e = string.find(text, needle, at, true)
		if not s then
			return n
		end
		n += 1
		at = e + 1
	end
end

return t.spec("f0437 slice 2: the units writer", function(it)
	it(
		"writes units.json, and writes nothing when the body is the same (the time and the commit do not count)",
		function()
			local model = modelOf("First title")
			local live = `{HERE}/{DIR}/live`
			local path, wrote = unitswrite.write(live, model, "", NO_TEMPLATES, "aaa1111", 100)
			t.expect(path).toBe(`{live}/units.json`)
			t.expect(wrote).toBe(true)
			local first = serde.decode("json" :: "json", fs.readFile(path))
			t.expect(first.version).toBe(1)
			t.expect(first.at).toBe(100)
			t.expect(first.commit).toBe("aaa1111")
			-- the same tracker, later, another commit: no write at all (the file keeps its own time)
			local _, again = unitswrite.write(live, model, "", NO_TEMPLATES, "bbb2222", 200)
			t.expect(again).toBe(false)
			local kept = serde.decode("json" :: "json", fs.readFile(path))
			t.expect(kept.at).toBe(100)
			t.expect(kept.commit).toBe("aaa1111")
			-- a changed title is a write
			local changed = modelOf("Second title")
			local _, third = unitswrite.write(live, changed, "", NO_TEMPLATES, "ccc3333", 300)
			t.expect(third).toBe(true)
			t.expect(serde.decode("json" :: "json", fs.readFile(path)).at).toBe(300)
			-- a withdrawn id in the log is a change too
			local log = "@@\t2026-11-02\ttracker: withdraw c0261\nz-nile/.tracker/issues/c0261/c0261.md\n"
			local _, fourth = unitswrite.write(live, changed, log, NO_TEMPLATES, "ddd4444", 400)
			t.expect(fourth).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(path))
			local stub = false
			for _, u in got.units do
				if u.id == "c0261" then
					stub = u.state == "withdrawn"
						and u.subject == "tracker: withdraw c0261"
						and u.when == "2026-11-02"
				end
			end
			t.expect(stub).toBe(true)
			for _, name in fs.readDir(live) do
				t.expect((string.find(name, "pickman-tmp", 1, true))).toBe(nil)
			end
			fs.removeDir(DIR)
		end
	)

	it("a write replaces the file and never writes through a link left at its path", function()
		local model = modelOf("T")
		local live = `{HERE}/{DIR}/live`
		fs.writeDir(live)
		fs.writeFile(`{HERE}/{DIR}/decoy.txt`, "decoy")
		t.expect(process.exec("ln", { "-s", `{HERE}/{DIR}/decoy.txt`, `{live}/units.json` }).ok).toBe(true)
		unitswrite.write(live, model, "", NO_TEMPLATES, nil, 1)
		t.expect(fs.readFile(`{HERE}/{DIR}/decoy.txt`)).toBe("decoy")
		t.expect(fs.readFile(`{live}/units.json`) ~= "decoy").toBe(true)
		fs.removeDir(DIR)
	end)

	it("a file that is not a regular file or not valid is replaced, never trusted for the skip", function()
		local model = modelOf("T")
		local live = `{HERE}/{DIR}/live`
		fs.writeDir(live)
		fs.writeFile(`{live}/units.json`, '{"sig":"x"}')
		local _, wrote = unitswrite.write(live, model, "", NO_TEMPLATES, nil, 1)
		t.expect(wrote).toBe(true)
		fs.writeFile(`{live}/units.json`, "not json")
		local _, again = unitswrite.write(live, model, "", NO_TEMPLATES, nil, 2)
		t.expect(again).toBe(true)
		fs.removeDir(DIR)
	end)

	it(
		"the board refresh writes the index in the main checkout, wakes the daemon once, and not again when nothing changed",
		function()
			local f = trackerfix.new("units-write-poke", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
			})
			local live = `{f.base}/livestate`
			local out = `{f.base}/page.html`
			local log, stub = stubBin(f.base)
			local env = { ZN_LIVE = "", ZN_LIVE_BIN = stub, ZN_LIVE_DIR = live }
			local r = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", out }, { env = env })
			t.expect(r.ok).toBe(true)
			t.expect(fs.isFile(`{live}/units.json`)).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/units.json`))
			local ids: { string } = {}
			for _, u in got.units do
				table.insert(ids, u.id)
			end
			t.expect(ids).toEqual({ "c0001" })
			t.expect(count(fs.readFile(log), "poke --reason units")).toBe(1)
			-- the same tracker again: the themes facts are made again (they hold the time), the index is not
			local r2 = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", out }, { env = env })
			t.expect(r2.ok).toBe(true)
			t.expect(count(fs.readFile(log), "poke --reason units")).toBe(1)
			t.expect(count(fs.readFile(log), "poke --reason themes")).toBe(2)
			fs.removeDir(f.base)
		end
	)

	it(
		"a withdrawn ticket is found in the history: its stub carries the date and the subject of the commit that removed it",
		function()
			local f = trackerfix.new("units-write-withdrawn", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
				["z-nile/.tracker/issues/c0261/c0261.md"] = trackerfix.stub(
					"c0261",
					"Will go",
					"new-quiet-copper-falcon"
				),
				["z-nile/.tracker/issues/c0262/c0262.md"] = trackerfix.stub(
					"c0262",
					"Moves",
					"new-quiet-copper-falcon"
				),
			})
			fixlib.git(f.main, { "rm", "-q", "-r", "z-nile/.tracker/issues/c0261" })
			fixlib.git(f.main, { "commit", "-q", "-m", "tracker: withdraw c0261 (met by #299)" })
			-- a move (a delete in one folder and an add in another) is no withdrawal
			fixlib.git(f.main, { "mv", "z-nile/.tracker/issues/c0262", "z-nile/.tracker/issues/done" })
			fixlib.git(f.main, { "commit", "-q", "-m", "finish c0262" })
			local live = `{f.base}/livestate`
			local r = fixlib.exec(f.main, "./zn", { "board", "-O", "--out", `{f.base}/page.html` }, {
				env = { ZN_LIVE = "off", ZN_LIVE_DIR = live },
			})
			t.expect(r.ok).toBe(true)
			local got = serde.decode("json" :: "json", fs.readFile(`{live}/units.json`))
			local by: { [string]: any } = {}
			for _, u in got.units do
				by[u.id] = u
			end
			t.expect(by.c0261.state).toBe("withdrawn")
			t.expect(by.c0261.subject).toBe("tracker: withdraw c0261 (met by #299)")
			t.expect(#by.c0261.when).toBe(10)
			t.expect(by.c0262.state).toBe("done") -- it exists now
			t.expect(by.c0001.state).toBe("backlog")
			fs.removeDir(f.base)
		end
	)

	it(
		"a branch's tracker is not the app's: a refresh from a worktree writes nothing, even with ZN_LIVE_DIR set",
		function()
			local f = trackerfix.new("units-write-tree", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
			})
			local live = `{f.base}/livestate`
			local tree = `{f.base}/tree`
			fixlib.git(f.main, { "worktree", "add", "-q", "-b", "tree-branch", tree })
			local model = board.collect(`{tree}/z-nile/.tracker`, nil, NO_FACTS)
			process.env.ZN_LIVE_DIR = live
			local ok = pcall(unitswrite.refresh, tree, model, "abc")
			t.expect(ok).toBe(true)
			t.expect(fs.isFile(`{live}/units.json`)).toBe(false)
			-- the same call from the main checkout writes
			pcall(unitswrite.refresh, f.main, board.collect(`{f.main}/z-nile/.tracker`, nil, NO_FACTS), "abc")
			process.env.ZN_LIVE_DIR = nil
			t.expect(fs.isFile(`{live}/units.json`)).toBe(true)
			fs.removeDir(f.base)
		end
	)

	it("a write that fails leaves the earlier index alone and the refresh still returns", function()
		local f = trackerfix.new("units-write-fail", {
			["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
				"c0001",
				"One",
				"new-quiet-copper-falcon"
			),
		})
		local live = `{f.base}/livestate`
		local model = board.collect(`{f.main}/z-nile/.tracker`, nil, NO_FACTS)
		process.env.ZN_LIVE_DIR = live
		unitswrite.refresh(f.main, model, "abc")
		local before = fs.readFile(`{live}/units.json`)
		for _, i in model.issues do
			i.title = "T \255" -- a stray byte cannot be encoded
		end
		local ok = pcall(unitswrite.refresh, f.main, model, "abc")
		process.env.ZN_LIVE_DIR = nil
		t.expect(ok).toBe(true)
		t.expect(fs.readFile(`{live}/units.json`)).toBe(before)
		fs.removeDir(f.base)
	end)

	it(
		"with the live layer off and no folder named, the refresh writes nothing under the checkout's own .cache",
		function()
			local f = trackerfix.new("units-write-off", {
				["z-nile/.tracker/issues/c0001/c0001.md"] = trackerfix.stub(
					"c0001",
					"One",
					"new-quiet-copper-falcon"
				),
			})
			unitswrite.refresh(f.main, board.collect(`{f.main}/z-nile/.tracker`, nil, NO_FACTS), "abc")
			t.expect(fs.isDir(`{f.main}/.cache`)).toBe(false)
			fs.removeDir(f.base)
		end
	)
end)
