--!strict
-- c0400 AC3: `scripts/tracker.sh board` writes the page for the real tracker, to .cache/board.html by
-- default or to --out, prints the path, and the file equals board.build(). `-O` (c0550) keeps the gate
-- from starting a browser; it comes last, so the spec passes before and after c0550.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local OUT = ".cache/c0400-cli/page.html"

return t.spec("c0400 tracker.sh board", function(it)
	it("writes --out and prints its path", function()
		if fs.isDir(".cache/c0400-cli") then
			fs.removeDir(".cache/c0400-cli")
		end
		local r = process.exec("scripts/tracker.sh", { "board", "--out", OUT, "-O" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, OUT, 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		t.expect(fs.readFile(OUT) == board.build()).toBe(true)
		fs.removeDir(".cache/c0400-cli")
	end)

	it("defaults to .cache/board.html", function()
		local r = process.exec("scripts/tracker.sh", { "board", "-O" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, ".cache/board.html", 1, true) ~= nil).toBe(true)
		t.expect(fs.readFile(".cache/board.html") == board.build()).toBe(true)
	end)

	it("the real tracker's page shows every raft and issue", function()
		local m = board.collect()
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
		-- c0114 override: the board reads every project root (c0120: pickman's root is pickman/.tracker)
		for _, base in
			{
				"pickman/.tracker/rafts",
				"pickman/.tracker/rafts/active",
				"pickman/.tracker/rafts/done",
				"z-nile/.tracker/rafts",
				"z-nile/.tracker/rafts/active",
				"z-nile/.tracker/rafts/done",
			}
		do
			for _, name in fs.readDir(base) do
				if string.match(name, "^R%d%d%d%d$") then
					onDisk += 1
				end
			end
		end
		t.expect(rafts).toBe(onDisk)
		-- every issue directory has a place on the page
		for _, base in
			{
				"pickman/.tracker/issues",
				"pickman/.tracker/issues/active",
				"pickman/.tracker/issues/done",
				"z-nile/.tracker/issues",
				"z-nile/.tracker/issues/active",
				"z-nile/.tracker/issues/done",
			}
		do
			for _, name in fs.readDir(base) do
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
