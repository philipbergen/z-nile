--!strict
-- R0112 code review 001 F1: a `for` list is text only when its body uses the variable as text to match (c0371, rule
-- L). When grep's pattern is already given (`-e PAT`, `--regexp PAT`), the next word is its file operand, and a
-- patterns file (`-f FILE`) is a file too: a loop variable there is a use, so the list's words are paths.
local checkpaths = require("@tests/acceptance/c0120/checkpaths")
local t = require("@tests/lib/t")

local function paths(text: string): { string }
	local out = {}
	for _, lit in checkpaths.literals(text) do
		table.insert(out, lit.path)
	end
	return out
end

return t.spec("c0371 a loop variable as grep's file operand is a use (R0112 code review 001 F1)", function(it)
	it("reads the list when the pattern is given by -e or --regexp and the variable is the file", function()
		for _, body in
			{
				'grep -q -e "needle" "$f" || exit 1',
				'grep -q --regexp "needle" "$f" || exit 1',
				'grep -q -e one -e two "$f"',
				'egrep -e "needle" "${f}"',
				'rg -q -e "needle" "$f"',
			}
		do
			t.expect(paths(`for f in tests/missing/a.luau; do {body}; done\n`))
				.toEqual({ "tests/missing/a.luau" })
		end
	end)

	it("reads the list when the variable is a patterns file", function()
		for _, body in { 'grep -qf "$f" out.txt', 'grep -q -f "$f" out.txt', 'grep --file "$f" out.txt' } do
			t.expect(paths(`for f in tests/missing/a.luau; do {body}; done\n`)[1])
				.toBe("tests/missing/a.luau")
		end
	end)

	it("keeps the list as text when the variable is the pattern", function()
		for _, body in
			{
				'grep -qF "$f" "$DOC" || exit 1',
				'grep -q -e "$f" "$DOC"',
				'grep -q --regexp "$f" "$DOC"',
				'grep -q -e one -e "$f" "$DOC"',
			}
		do
			t.expect(paths(`for f in tests/missing/a.luau; do {body}; done\n`)).toEqual({})
		end
	end)

	it("still reads a file operand after a plain pattern", function()
		t.expect(paths('for f in tests/missing/a.luau; do grep -q "needle" "$f"; done\n'))
			.toEqual({ "tests/missing/a.luau" })
	end)
end)
