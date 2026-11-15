--!strict
-- E1: what the prototype's literals() reads from the cases of the root-cd rule (prints path and root per line)
local scanner = require("@tests/acceptance/c0120/check-paths-scan")
for _, l in
	{
		'(cd "$ZN_ROOT" && lune run z-nile/roots -- --luau-dirs) | tr " " "\\n"',
		"bash -c 'cd \"$(git rev-parse --show-toplevel)\" && test -f z-nile/roots.luau'",
		'cd "$ZN_ROOT/z-nile" && test -f tests/run.luau',
		'(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau',
		'(cd "$ZN_ROOT" && test -f tests/run.luau)',
	}
do
	local out = {}
	for _, lit in scanner.literals(l) do
		table.insert(out, `{lit.path}{if lit.root then "@root" else ""}`)
	end
	print(l, "=>", table.concat(out, " "))
end
