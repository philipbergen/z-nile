--!strict
-- c0371: c0120 AC11's scan reads an item's check.sh the way bash runs it. A Touched entry covers a path written as a repo
-- path or as a path from the home; a command after `cd "$ZN_ROOT"` is read from the repo root until its subshell
-- closes; a word in a code span of quoted text is prose. A path missing from where its command runs, and covered by
-- no entry, is still reported (also when it exists elsewhere in the repository).
local fs = require("@lune/fs")
local scanner = require("@tests/acceptance/c0120/check-paths-scan")
local t = require("@tests/lib/t")

local FX = ".cache/c0371-check-paths/"
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local function put(rel: string, text: string)
	fs.writeDir(string.match(FX .. rel, "^(.*)/[^/]+$") :: string)
	fs.writeFile(FX .. rel, text)
end
local function fresh()
	if fs.isDir(FX) then
		fs.removeDir(FX)
	end
	put("z-nile/projects.toml", REGISTRY)
	put("pickman/src/server/Main.server.luau", "--!strict\nreturn nil\n")
	put("z-nile/roots.luau", "--!strict\nreturn nil\n")
	put("z-nile/tests/run.luau", "--!strict\nreturn nil\n")
end
-- one item in a home with a Touched section (empty list: none) and a check.sh; returns the scan's findings
local function findings(home: string, touched: { string }, check: string): { string }
	fresh()
	local lines = {}
	for _, p in touched do
		table.insert(lines, "- `" .. p .. "`")
	end
	put(
		`{home}/.tracker/issues/c0001/c0001.md`,
		`---\nid: c0001\n---\n### Touched modules\n{table.concat(lines, "\n")}\n\n## Next\n`
	)
	put(`{home}/.tracker/issues/c0001/check.sh`, check)
	local bad = scanner.scan(FX).bad
	fs.removeDir(FX)
	return bad
end

return t.spec("c0371 check-paths reads homes right", function(it)
	it("a Touched entry covers a path written as a repo path or from the home", function()
		local check = "test -f src/shared/Logic/New/init.luau\ntest -d tests/unit/New\n"
		t.expect(findings("pickman", { "pickman/src/shared/Logic/New", "pickman/tests/unit/New" }, check))
			.toEqual({})
		t.expect(findings("pickman", { "src/shared/Logic/New", "tests/unit/New" }, check)).toEqual({})
		-- a parent of an entry and a mixed list
		t.expect(findings("pickman", { "pickman/src/shared/Logic/New/init.luau", "tests/unit/New" }, check))
			.toEqual({})
	end)

	it(
		"a path covered by no entry is still reported, also when it exists elsewhere in the repository",
		function()
			t.expect(
				findings(
					"pickman",
					{ "pickman/src/shared/Logic/New" },
					"test -f src/gone.luau\ntest -d tests/unit/New\n"
				)
			).toEqual({
				"pickman/.tracker/issues/c0001/check.sh: src/gone.luau (from pickman)",
				"pickman/.tracker/issues/c0001/check.sh: tests/unit/New (from pickman)",
			})
			-- pickman/src/server exists; z-nile has none, and an entry for pickman's is not z-nile's
			t.expect(findings("z-nile", { "pickman/src/server" }, "test -f src/server\n")).toEqual({
				"z-nile/.tracker/issues/c0001/check.sh: src/server (from z-nile)",
			})
			-- a sibling folder with the same first letters is not covered
			t.expect(
				findings("pickman", { "pickman/src/shared/Logic/New" }, "test -d src/shared/Logic/Newer\n")
			)
				.toEqual({
					"pickman/.tracker/issues/c0001/check.sh: src/shared/Logic/Newer (from pickman)",
				})
			t.expect(findings("z-nile", {}, "git diff --quiet -- scripts/gone.sh\n")).toEqual({
				"z-nile/.tracker/issues/c0001/check.sh: scripts/gone.sh (from z-nile)",
			})
		end
	)

	it("a command after cd to the repository root is read from the root until its subshell closes", function()
		t.expect(
			findings("z-nile", {}, '(cd "$ZN_ROOT" && lune run z-nile/roots -- --luau-dirs) | tr " " "\\n"\n')
		)
			.toEqual({})
		t.expect(
			findings(
				"z-nile",
				{},
				"bash -c 'cd \"$(git rev-parse --show-toplevel)\" && test -f z-nile/roots.luau'\n"
			)
		).toEqual({})
		t.expect(findings("pickman", {}, 'cd "$ZN_ROOT/z-nile" && test -f tests/run.luau\n')).toEqual({})
		-- a missing path after the cd is reported from the root; one after the closing paren is read from the home again
		t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && test -f z-nile/gone.luau)\n')).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: z-nile/gone.luau (from the repository root)",
		})
		t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau\n')).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: z-nile/roots.luau (from z-nile)",
		})
		-- a path of the home is not found from the root
		t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && test -f tests/run.luau)\n')).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: tests/run.luau (from the repository root)",
		})
	end)

	it("a word in a code span of quoted text is prose, and a bare path next to it is still read", function()
		local check = 'has "$L" "full gate" "\\`tests/run\\`" "\\`src/nothing\\`"\ntest -f src/gone.luau\n'
		t.expect(findings("z-nile", {}, check)).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: src/gone.luau (from z-nile)",
		})
		t.expect(findings("z-nile", {}, 'has "$L" tests/gone.md\n')).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: tests/gone.md (from z-nile)",
		})
	end)

	it("the message of an echo is prose, and the next command is still read", function()
		local check =
			'test -f tests/run.luau || { echo "z-nile/roots and src/gone.luau no longer exist"; test -f src/gone2.luau; }\n'
		t.expect(findings("z-nile", {}, check)).toEqual({
			"z-nile/.tracker/issues/c0001/check.sh: src/gone2.luau (from z-nile)",
		})
	end)
end)
