--!strict
-- c0193 AC6: on the real tree, every while and repeat loop in the tooling (z-nile/, scripts/, pickman/scripts/, minus
-- specs, promoted specs, fixtures and vendored code) provably advances or is on the reviewed list, in file order, with
-- a reason; every entry names a file and a loop that are still there and a scanners case that exists.
local loops = require("@tests/lib/loops")
local scanners = require("@tests/lib/scanners")
local t = require("@tests/lib/t")

return t.spec("c0193 the tooling's loops", function(it)
	it(
		"covers the tooling's files and none of the specs, promoted specs, fixtures or vendored code",
		function()
			local files = loops.files()
			-- every root the lint covers contributes files (a rename of one file does not turn this red)
			for _, root in loops.ROOTS do
				local any = false
				for path in files do
					any = any or string.sub(path, 1, #root + 1) == root .. "/"
				end
				t.expect(`{root} {any}`).toBe(`{root} true`)
			end
			for path in files do
				t.expect(string.find(path, ".spec.luau", 1, true) == nil).toBe(true)
				t.expect(string.find(path, "/tests/acceptance/", 1, true) == nil).toBe(true)
				t.expect(string.find(path, "/.tracker/", 1, true) == nil).toBe(true)
				t.expect(string.find(path, "/.cache/", 1, true) == nil).toBe(true)
				t.expect(string.find(path, "/vendor/", 1, true) == nil).toBe(true)
			end
		end
	)

	it(
		"[zz-arch/scanning-loops-advance] has no loop that is neither proven nor listed, and no stale entry",
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

	it(
		"lists a scanners case only by a name that exists and whose module is the listed loop's own file",
		function()
			local sweeps = scanners.files()
			local bad: { string } = {}
			for path, list in loops.ALLOWED do
				for _, a in list do
					if type(a.sweep) == "string" and sweeps[a.sweep] ~= path then
						table.insert(
							bad,
							`{path}: "{a.loop}" names the case "{a.sweep}" (module {sweeps[a.sweep]})`
						)
					end
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
		end
	)

	it(
		"has a case for every scanner file that a landed sibling brought (raftcheck, boundcmd), once it exists",
		function()
			-- raftcheck.luau (PR #125) and boundcmd.luau (c0191) read quoted, escaped text: the incident's own class
			local files = loops.files()
			local swept = scanners.files()
			for _, file in { "z-nile/engine/raftcheck.luau", "z-nile/engine/boundcmd.luau" } do
				if files[file] then
					local found = false
					for _, f in swept do
						found = found or f == file
					end
					t.expect(`{file} swept {found}`).toBe(`{file} swept true`)
				end
			end
		end
	)

	it(
		"lists the loops of the c0193 incident's file once it exists (PR #125's raftcheck) and sweeps it",
		function()
			-- raftcheck.luau reads the RC lines of a raft's check.sh: the loop that spun on an unquoted backslash. Whichever
			-- of that PR and c0193 lands second adds its case to tests/lib/scanners.luau
			local files = loops.files()
			if files["z-nile/engine/raftcheck.luau"] then
				-- raftcheck.judge returns early unless the text starts with the raft template's RC0 head, so the case
				-- puts that head and the opening of an RC line before every hostile text (its prefix), and a witness
				-- proves the call reaches word(): the head and a valid RC line give no problem
				local case: any = nil
				for _, c in scanners.CASES do
					if c.name == "raftcheck.judge" then
						case = c
					end
				end
				t.expect(case ~= nil).toBe(true)
				t.expect(case.witness ~= nil).toBe(true)
				t.expect(string.sub(case.prefix or "", -#'check "RC1: ') == 'check "RC1: ').toBe(true)
			end
		end
	)
end)
