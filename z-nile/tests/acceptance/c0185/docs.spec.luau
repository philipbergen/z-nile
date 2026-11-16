--!strict
-- c0185 AC7: the sentences that restate the library wiring, the place tier and the selector's inputs move together with the
-- code (z-design lesson restated-rules-move-together). z-nile's own documents only (the README and zz-test); the sentences in
-- pickman's and the five homes' skills are check.sh's, which runs once at done. Read-only: the real tree.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} is missing: {needle}`)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still has: {needle}`)
	end
end

return t.spec("c0185 the restated rules", function(it)
	it(
		"AC7: the README describes the library alias, the library's two $paths and the place tier of a home",
		function()
			local readme = read("z-nile/README.md")
			at(
				readme,
				"`arcade` at the library's `src/shared` (`../arcade/src/shared`, the same line in every home, the library's included)",
				"README"
			)
			at(
				readme,
				"Every `$path` is a folder of the home, but for the library's two (`../arcade/src/shared` and `../arcade/src/server`), which the default place maps as `ReplicatedStorage.Arcade` and `ServerStorage.Arcade` in every home (c0185).",
				"README"
			)
			at(
				readme,
				"`tests/lib/place.luau` (the shared place harness, re-exported) and `tests/place/library.spec.luau` (the shared place spec, called with it) are the home's place tier.",
				"README"
			)
			absent(readme, "(c0185 adds the library's)", "README")
		end
	)

	it(
		"AC7: zz-test says the place harness is shared, the selector's inputs, and where to verify the library",
		function()
			local test = read("z-nile/skills/zz-test/SKILL.md")
			at(
				test,
				"`place` re-exports the shared harness's (`z-nile/tests/lib/place.luau`, c0185)",
				"zz-test"
			)
			at(
				test,
				"and the same place tier: `tests/lib/place.luau` and `tests/place/library.spec.luau`",
				"zz-test"
			)
			at(
				test,
				"`.luaurc` or any `*.project.json` (under its home) selects a spec only when that spec's watch file names it",
				"zz-test"
			)
			absent(
				test,
				"`.luaurc` or `default.project.json` (under its home) forces that project's",
				"zz-test"
			)
			absent(
				test,
				"`.luaurc` or any `*.project.json` (under its home) forces that project's",
				"zz-test"
			)
			at(
				test,
				"is selected when its watch file names what the place is built from: the home's project files and every `$path` they map",
				"zz-test"
			)
			at(
				test,
				"Verify an arcade change against its dependents with `z-nile/check.sh --affected`",
				"zz-test"
			)
		end
	)
end)
