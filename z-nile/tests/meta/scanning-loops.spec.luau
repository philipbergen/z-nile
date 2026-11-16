--!strict
-- The scanning-loop rule on the tooling's own files (zz-arch skill, lesson scanning-loops-advance): every `while` or
-- `repeat` loop in z-nile/, scripts/ and pickman/scripts/ provably advances or is on the reviewed list in
-- tests/lib/loops.luau, with a reason and, for a loop that reads text, the scanners case that sweeps it. This case is
-- the lesson's enforcing ref while its sequestered twin (tests/acceptance/c0193/tree.spec) is not promoted yet.
local loops = require("@tests/lib/loops")
local scanners = require("@tests/lib/scanners")
local t = require("@tests/lib/t")

return t.spec("scanning loops (tooling)", function(it)
	it(
		"[zz-arch/scanning-loops-advance] every loop in the tooling provably advances or is on the reviewed list",
		function()
			local sweeps = scanners.files()
			local bad: { string } = {}
			local files = loops.files()
			for path, text in files do
				for _, p in loops.problems(path, text, loops.ALLOWED[path], sweeps) do
					table.insert(bad, p)
				end
			end
			for path in loops.ALLOWED do
				if not files[path] then
					table.insert(
						bad,
						`loops.ALLOWED lists {path}, which is not a covered file: remove its entries`
					)
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
		end
	)
end)
