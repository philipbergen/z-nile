--!strict
-- c0359 AC3: which changed paths make a gate run the format and lint stages (dispatch.lintable): a Lua or Luau source,
-- or a file of a kind the two tools read as configuration (TOML, YAML, a dotfile), by its name in any case. A document,
-- a check.sh, a JSON file or a reference text (`.luau.txt`) is not.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

return t.spec("c0359 lintable paths", function(it)
	it("a Lua or Luau source anywhere is lintable, in any case", function()
		for _, path in
			{
				"pickman/.tracker/issues/c0010/acceptance/a.spec.luau",
				"z-nile/.tracker/issues/c0010/experiments/probe.luau",
				"pickman/.tracker/rafts/R0050/notes.lua",
				"pickman/.tracker/issues/c0010/acceptance/B.SPEC.LUAU",
				"x.Lua",
			}
		do
			t.expect(`{path}: {tostring(dispatch.lintable(path))}`).toBe(`{path}: true`)
		end
	end)

	it(
		"a TOML, YAML or dotfile is lintable (the tools' settings, standard libraries and ignore lists)",
		function()
			for _, path in
				{
					"pickman/.tracker/issues/c0010/stylua.toml",
					"pickman/.tracker/issues/c0010/.stylua.toml",
					"pickman/.tracker/issues/c0010/selene.toml",
					"pickman/.tracker/issues/c0010/.styluaignore",
					"pickman/.tracker/issues/c0010/roblox.yml",
					"pickman/.tracker/issues/c0010/std.YAML",
					"pickman/.tracker/issues/c0010/Selene.Toml",
				}
			do
				t.expect(`{path}: {tostring(dispatch.lintable(path))}`).toBe(`{path}: true`)
			end
		end
	)

	it("documents, scripts, JSON and reference texts are not", function()
		for _, path in
			{
				"pickman/.tracker/issues/c0010/c0010.md",
				"pickman/.tracker/issues/c0010/check.sh",
				"pickman/.tracker/issues/c0010/experiments/ref.luau.txt",
				"pickman/.tracker/issues/c0010/experiments/out.json",
				"pickman/.tracker/issues/c0010/spend.d/zn.tsv",
				"z-nile/next",
				"pickman/.tracker/issues/c0010/luau",
				"pickman/.tracker/issues/c0010/a.luaux",
			}
		do
			t.expect(`{path}: {tostring(dispatch.lintable(path))}`).toBe(`{path}: false`)
		end
	end)
end)
