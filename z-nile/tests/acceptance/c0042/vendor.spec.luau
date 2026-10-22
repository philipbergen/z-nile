--!strict
-- c0400 AC4: the Markdown renderer is the pinned marked 18.0.14 UMD build, vendored with its licence.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home (z-nile/); the vendored marked is read from the checkout's top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

return t.spec("c0400 vendored marked", function(it)
	it("is the pinned file", function()
		t.expect(board.MARKED_PATH).toBe("z-nile/vendor/marked.umd.js")
		t.expect(board.MARKED_SHA256).toBe("21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62")
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		t.expect(serde.hash("sha256", fs.readFile(`{TOP}/{board.MARKED_PATH}`))).toBe(board.MARKED_SHA256)
	end)

	it("ships with marked's MIT licence next to it", function()
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		local licence = fs.readFile(`{TOP}/z-nile/vendor/marked.LICENSE`)
		t.expect(string.find(licence, "Permission is hereby granted", 1, true) ~= nil).toBe(true)
		t.expect(string.find(licence, "MarkedJS", 1, true) ~= nil).toBe(true)
	end)

	it("build refuses a vendored file that does not match the pin", function()
		-- render takes any script text; build and the CLI go through checkMarked
		local ok = pcall(board.checkMarked, "tampered")
		t.expect(ok).toBe(false)
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		board.checkMarked(fs.readFile(`{TOP}/{board.MARKED_PATH}`))
	end)
end)
