--!strict
-- c0400: the board's own unit cases: the JSON writer, an empty tracker, and the `--open` flag.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local EMPTY = ".cache/board-unit-empty"

return t.spec("board unit", function(it)
	it("encode escapes quotes, backslashes, control characters and <", function()
		t.expect(board.encode('a"b\\c')).toBe('"a\\"b\\\\c"')
		t.expect(board.encode("x\ny\rz\tw")).toBe('"x\\ny\\rz\\tw"')
		t.expect(board.encode("\1")).toBe('"\\u0001"')
		t.expect(board.encode("</script>")).toBe('"\\u003c/script>"')
	end)

	it("encode keeps unicode bytes as they are", function()
		t.expect(board.encode("héllo — ✓")).toBe('"héllo — ✓"')
	end)

	it("encode nests, orders keys, and writes booleans and numbers", function()
		t.expect(board.encode({ z = { 1, 2, { b = true, a = false } }, a = 3, m = {} }))
			.toBe('{"a":3,"m":[],"z":[1,2,{"a":false,"b":true}]}')
	end)

	it("encode refuses a value it cannot write", function()
		local ok = pcall(board.encode, { f = function() end })
		t.expect(ok).toBe(false)
	end)

	it("collect on a tree with no tracker directories gives an empty model", function()
		if fs.isDir(EMPTY) then
			fs.removeDir(EMPTY)
		end
		fs.writeDir(EMPTY)
		local m = board.collect(EMPTY)
		fs.removeDir(EMPTY)
		t.expect(m.rafts).toEqual({})
		t.expect(m.issues).toEqual({})
		t.expect(m.tabs).toEqual({ done = {}, active = {}, waiting = {} })
		t.expect(m.home).toEqual({})
		t.expect(m.initialTab).toBe("waiting")
	end)

	it("--open runs the opener on the page, and does not eat the next argument", function()
		local dir = ".cache/board-unit-open"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		-- fake openers, so the gate never launches a browser
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{dir}/bin/{name}`, `#!/bin/sh\necho "$@" > "{process.cwd}{dir}/opened"\n`)
			process.exec("chmod", { "+x", `{dir}/bin/{name}` })
		end
		local out = `{dir}/page.html`
		local r = process.exec("scripts/tracker.sh", { "board", "--open", "--out", out }, {
			env = { PATH = `{process.cwd}{dir}/bin:{process.env.PATH or ""}` },
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(out)).toBe(true)
		t.expect(string.find(fs.readFile(`{dir}/opened`), out, 1, true) ~= nil).toBe(true)
		fs.removeDir(dir)
	end)
end)
