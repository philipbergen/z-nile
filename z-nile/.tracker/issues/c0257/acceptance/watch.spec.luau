--!strict
-- c0257 AC10: a change to the omarchy app selects c0257's specs once they are promoted. `./zn finish` writes a ticket's
-- watch map with watch.forSuite, which keeps a tooling spec's paths to the tooling folders; z-nile-omarchy/ is z-nile's, so
-- the folder joins them (a game spec still does not keep it).
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

return t.spec("c0257 AC10: the watch map reaches the app", function(it)
	it("AC10: a tooling spec keeps the app's paths, a game spec does not", function()
		local paths = { "z-nile-omarchy/znile.board/Model.js", "pickman/src/A.luau", "z-nile/lib/watch.luau" }
		t.expect(watch.forSuite("z-nile/tests/acceptance/c0257/app.spec.luau", paths)).toEqual({
			"z-nile-omarchy/znile.board/Model.js",
			"z-nile/lib/watch.luau",
		})
		t.expect(watch.forSuite("pickman/tests/unit/a.spec.luau", paths)).toEqual({ "pickman/src/A.luau" })
	end)
end)
