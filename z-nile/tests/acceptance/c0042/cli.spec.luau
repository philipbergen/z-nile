--!strict
-- c0400 AC3: `scripts/tracker.sh board` writes the page for the real tracker, to .cache/board.html by
-- default or to --out, prints the path, and the file equals board.build(). `-O` (c0550) keeps the gate
-- from starting a browser; it comes last, so the spec passes before and after c0550.
local board = require("@scripts/tracker/board")
-- c0120 override: the spec runs from its project's home after the move
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: specs run from their project's home (z-nile/), and the jail refuses writes to the checkout top's
-- .cache, where `./zn` (which runs at the top) puts a relative --out and its default page. So the real tracker's page
-- goes to an absolute --out under the home's .cache, the default is checked in a stand-in checkout there, and each is
-- compared with board.build() of the checkout it read.
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local OUT = `{HERE}/.cache/c0400-cli/page.html`

return t.spec("c0400 tracker.sh board", function(it)
	it("writes --out and prints its path", function()
		if fs.isDir(".cache/c0400-cli") then
			fs.removeDir(".cache/c0400-cli")
		end
		-- c0120 override: the real checkout's tracker.sh, at its top; compared with that checkout's page
		local r = process.exec(`{TOP}/scripts/tracker.sh`, { "board", "--out", OUT, "-O" }, { cwd = TOP })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, OUT, 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		t.expect(fs.readFile(OUT) == board.build(nil, TOP)).toBe(true)
		fs.removeDir(".cache/c0400-cli")
	end)

	it("defaults to .cache/board.html", function()
		-- c0120 override: a stand-in checkout under the home's .cache (the tooling, no items), since the real default
		-- page is outside the jail
		local repo = `{HERE}/.cache/c0400-cli/repo`
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		engine.copy(TOP, repo)
		engine.roots(repo)
		local r = process.exec(`{repo}/scripts/tracker.sh`, { "board", "-O" }, { cwd = repo })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, ".cache/board.html", 1, true) ~= nil).toBe(true)
		-- c0120 override: the spec runs from its project's home after the move
		t.expect(fs.readFile(`{repo}/.cache/board.html`) == board.build(nil, repo)).toBe(true)
		fs.removeDir(`{HERE}/.cache/c0400-cli`)
	end)

	it("the real tracker's page shows every raft and issue", function()
		local m = board.collect(nil, TOP) -- c0120 override: the real checkout's tracker, at its top
		local rafts, issues = 0, 0
		for _, r in m.rafts do
			if not r.pseudo then
				rafts += 1
			end
		end
		for _ in m.issues do
			issues += 1
		end
		local onDisk = 0
		-- c0120 override: pickman's files live in pickman/ (its home)
		-- c0114 override: the board reads every project root (c0120: pickman's root is pickman/.tracker)
		for _, base in
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			{
				"pickman/.tracker/rafts",
				"pickman/.tracker/rafts/active",
				"pickman/.tracker/rafts/done",
				"z-nile/.tracker/rafts",
				"z-nile/.tracker/rafts/active",
				"z-nile/.tracker/rafts/done",
			}
		do
			for _, name in fs.readDir(`{TOP}/{base}`) do -- c0120 override: read from the checkout's top
				if string.match(name, "^R%d%d%d%d$") then
					onDisk += 1
				end
			end
		end
		t.expect(rafts).toBe(onDisk)
		-- every issue directory has a place on the page
		for _, base in
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			{
				"pickman/.tracker/issues",
				"pickman/.tracker/issues/active",
				"pickman/.tracker/issues/done",
				"z-nile/.tracker/issues",
				"z-nile/.tracker/issues/active",
				"z-nile/.tracker/issues/done",
			}
		do
			for _, name in fs.readDir(`{TOP}/{base}`) do -- c0120 override: read from the checkout's top
				if string.match(name, "^[fdc]%d%d%d%d$") then
					t.expect(m.home[name] ~= nil).toBe(true)
				end
			end
		end
		for id in m.home do
			t.expect(string.match(id, "^[fdcR]%d%d%d%d$") ~= nil).toBe(true)
		end
		t.expect(issues > 0).toBe(true)
	end)
end)
