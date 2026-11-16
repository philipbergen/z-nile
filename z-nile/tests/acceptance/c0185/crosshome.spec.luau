--!strict
-- c0185 AC6: the two structural rules for code shared across homes, on fixture graphs: a Logic require that resolves
-- outside the home is reported (by a relative path, which the graph resolves on disk, or by an alias, which Roblox does not
-- read), and a spec that skips the home's place re-export is reported. The rules are z-nile/tests/lib/crosshome.luau; the
-- spec that applies them to a real home is every home's tests/meta/architecture.spec.luau (check.sh AC6 runs it on a
-- fixture home). Pure: no files.
local crosshome = require("@tests/lib/crosshome")
local t = require("@tests/lib/t")

local LOGIC = "src/shared/Logic"

return t.spec("c0185 the cross-home rules", function(it)
	it(
		"AC6: a Logic file whose require resolves outside the home is reported, each with its target",
		function()
			local deps = {
				["src/shared/Logic/Rng/init.luau"] = {
					"src/shared/Logic/Rng/Impl.luau",
					"../arcade/src/shared/Logic/Rng/init.luau",
				},
				["src/shared/Logic/Maze/init.luau"] = {
					"src/shared/Logic/Rng/init.luau",
					"../other/src/x.luau",
				},
				["src/shared/Logic/Clean/init.luau"] = { "src/shared/Logic/Maze/init.luau" },
			}
			t.expect(crosshome.logicOutside(deps, LOGIC)).toEqual({
				"src/shared/Logic/Maze/init.luau -> ../other/src/x.luau",
				"src/shared/Logic/Rng/init.luau -> ../arcade/src/shared/Logic/Rng/init.luau",
			})
		end
	)

	it(
		"AC6: only Logic is judged: an adapter or a spec may reach another home, a look-alike folder is no Logic",
		function()
			local deps = {
				["src/client/Main.client.luau"] = { "../arcade/src/shared/Info.luau" },
				["src/shared/Net.luau"] = { "../arcade/src/shared/Info.luau" },
				["tests/unit/Rng/rng.spec.luau"] = {
					"../arcade/src/shared/Logic/Rng/init.luau",
					"../z-nile/tests/lib/t.luau",
				},
				["src/shared/LogicX/a.luau"] = { "../arcade/src/shared/Info.luau" },
				["src/shared/Logic.luau"] = { "../arcade/src/shared/Info.luau" },
			}
			t.expect(crosshome.logicOutside(deps, LOGIC)).toEqual({})
		end
	)

	it(
		"AC6: a dependency inside the home is fine at any depth, and nothing is reported for no files",
		function()
			t.expect(crosshome.logicOutside({}, LOGIC)).toEqual({})
			local deps = {
				["src/shared/Logic/A/init.luau"] = {
					"src/shared/Logic/B/init.luau",
					"src/shared/Config.luau",
					"src/a/../b.luau",
				},
			}
			t.expect(crosshome.logicOutside(deps, LOGIC)).toEqual({})
		end
	)

	it(
		"AC6: a file that requires the shared place harness, other than the home's re-export, is reported",
		function()
			local shared, wrapper = "../z-nile/tests/lib/place.luau", "tests/lib/place.luau"
			local deps = {
				["tests/lib/place.luau"] = { shared },
				["tests/place/library.spec.luau"] = {
					"tests/lib/place.luau",
					"../z-nile/tests/lib/placespec.luau",
				},
				["tests/place/ok.spec.luau"] = { "tests/lib/place.luau" },
				["tests/place/skip.spec.luau"] = { shared, "tests/lib/t.luau" },
				["tests/unit/also.spec.luau"] = { "tests/lib/t.luau", shared },
			}
			t.expect(crosshome.placeBypass(deps, shared, wrapper)).toEqual({
				`tests/place/skip.spec.luau -> {shared}`,
				`tests/unit/also.spec.luau -> {shared}`,
			})
			t.expect(crosshome.placeBypass({ [wrapper] = { shared } }, shared, wrapper)).toEqual({})
			-- a helper in tests/lib that wraps the shared harness hides its specs from the selector too: only the re-export is exempt
			t.expect(crosshome.placeBypass({ ["tests/lib/helper.luau"] = { shared } }, shared, wrapper))
				.toEqual({ `tests/lib/helper.luau -> {shared}` })
			-- another file of the harness is not the place harness
			t.expect(
				crosshome.placeBypass(
					{ ["tests/a.spec.luau"] = { "../z-nile/tests/lib/placespec.luau" } },
					shared,
					wrapper
				)
			).toEqual({})
		end
	)
end)
