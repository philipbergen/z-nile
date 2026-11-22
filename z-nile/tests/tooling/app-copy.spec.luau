--!strict
-- f0437: z-nile/app/index.html is a copy of the f0425 mockup with two edits (the title, and one script line that loads
-- live.js). Until a step deliberately diverges from the mockup, any other difference is drift, and this spec says which file
-- to re-copy. The mockup's path is not in this spec's watch file, because f0425 moves between issues/, issues/active/ and
-- issues/done/ and a watch file naming a moved path would fail someone else's publish: a change to the mockup is caught by
-- the full runs, and a change to the page by this spec's watch file.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local MOCKUPS = {
	"z-nile/.tracker/issues/f0425/mockup/index.html",
	"z-nile/.tracker/issues/active/f0425/mockup/index.html",
	"z-nile/.tracker/issues/done/f0425/mockup/index.html",
}
local APP = "z-nile/app/index.html"

return t.spec("f0437 the app page is the mockup plus its two edits", function(it)
	it("has no other difference from the mockup", function()
		local home = fixture.physical(".") :: string
		local root = string.match(home, "^(.*)/z%-nile/?$") or home
		local MOCKUP: string? = nil
		for _, candidate in MOCKUPS do
			if fs.isFile(`{root}/{candidate}`) then
				MOCKUP = candidate
				break
			end
		end
		if not MOCKUP then
			error(
				`the f0425 mockup is in none of {table.concat(MOCKUPS, ", ")}: find it, or update MOCKUPS in this spec`,
				0
			)
		end
		local mock = fs.readFile(`{root}/{MOCKUP}`)
		local page = fs.readFile(`{root}/{APP}`)
		local expected =
			string.gsub(mock, "<title>z%-nile app mockup</title>", "<title>z-nile app</title>", 1)
		expected = string.gsub(expected, "</body>", '<script src="live.js"></script>\n</body>', 1) -- the mockup has one
		if page ~= expected then
			error(
				`{APP} differs from {MOCKUP} beyond its title and the live.js script line: re-copy {MOCKUP} to {APP} and re-apply those two edits`,
				0
			)
		end
	end)
end)
