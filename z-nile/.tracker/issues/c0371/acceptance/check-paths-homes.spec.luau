--!strict
-- c0371: c0120 AC11's scan reads an item's check.sh the way bash runs it. A Touched entry covers a path written as a repo
-- path or as a path from the home; a command after `cd "$ZN_ROOT"` is read from the repo root until its subshell
-- closes; a word in a code span of quoted text is prose. A path missing from where its command runs, and covered by
-- no entry, is still reported (also when it exists elsewhere in the repository).
local fs = require("@lune/fs")
local process = require("@lune/process")
local scanner = require("@tests/acceptance/c0120/checkpaths")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- the checkout's top, with a slash (these specs run from z-nile/)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")) .. "/"

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
	local bad = scanner.scan(FX, function(_text: string): boolean
		return false
	end).bad
	if process.env.C0371_DEBUG then
		print(string.gsub(check, "\n", "\\n"), "=>", table.concat(bad, " | "))
	end
	fs.removeDir(FX)
	return bad
end

-- the findings of one check.sh in a home with a given Touched list; `check` uses [=[ … ]=] strings (no escapes)
local ROOT = "the repository root"
local function bad(home: string, path: string, where: string?): string
	return `{home}/.tracker/issues/c0001/check.sh: {path} (from {where or home})`
end
local HAS = [=[
has() {
  local f=$1 w
  shift
  for w in "$@"; do grep -qF -- "$w" "$f" || { echo "$f does not say: $w"; return 1; }; done
}
]=]

return t.spec("c0371 check-paths reads homes right", function(it)
	it(
		"a Touched entry still covers the path of its own work, from either convention (c0141's reading)",
		function()
			local check = "test -f src/shared/Logic/New/init.luau\ntest -d tests/unit/New\n"
			t.expect(findings("pickman", { "pickman/src/shared/Logic/New", "pickman/tests/unit/New" }, check))
				.toEqual({})
			t.expect(findings("pickman", { "src/shared/Logic/New", "tests/unit/New" }, check)).toEqual({})
		end
	)

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
				bad("pickman", "src/gone.luau"),
				bad("pickman", "tests/unit/New"),
			})
			-- pickman/src/server exists; z-nile has none, and an entry for pickman's is not z-nile's
			t.expect(findings("z-nile", { "pickman/src/server" }, "test -f src/server\n"))
				.toEqual({ bad("z-nile", "src/server") })
			t.expect(findings("z-nile", {}, "git diff --quiet -- scripts/gone.sh\n"))
				.toEqual({ bad("z-nile", "scripts/gone.sh") })
		end
	)

	it(
		"a command after cd to the repository root is read from the root until its group or script closes",
		function()
			t.expect(
				findings(
					"z-nile",
					{},
					'(cd "$ZN_ROOT" && lune run z-nile/roots -- --luau-dirs) | tr " " "\\n"\n'
				)
			).toEqual({})
			t.expect(
				findings(
					"z-nile",
					{},
					[=[bash -c 'cd "$(git rev-parse --show-toplevel)" && test -f z-nile/roots.luau']=] .. "\n"
				)
			).toEqual({})
			t.expect(findings("pickman", {}, 'cd "$ZN_ROOT/z-nile" && test -f tests/run.luau\n')).toEqual({})
			t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && test -f z-nile/gone.luau)\n'))
				.toEqual({ bad("z-nile", "z-nile/gone.luau", ROOT) })
			t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && test -f tests/run.luau)\n'))
				.toEqual({ bad("z-nile", "tests/run.luau", ROOT) })
			-- after the closing paren the home again
			t.expect(findings("z-nile", {}, '(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau\n'))
				.toEqual({ bad("z-nile", "z-nile/roots.luau") })
			-- a cd inside a command substitution in double quotes (f0221's `S="$ZN_ROOT/$(cd "$ZN_ROOT" && ./zn find f0220)/acceptance"`)
			t.expect(
				findings(
					"z-nile",
					{},
					'S="$ZN_ROOT/$(cd "$ZN_ROOT" && ./zn find f0220)/acceptance"\nlune run tests/run -- x\n'
				)
			).toEqual({})
		end
	)

	it(
		"the root reading goes on over the lines of its script and its file, and ends where the script or group does",
		function()
			-- line 2 of a bash -c script (c0292 AC7's shape)
			t.expect(
				findings(
					"z-nile",
					{},
					'check "AC1" bash -c \'cd "$ZN_ROOT" || exit 1\n  test -f tests/run.luau\'\n'
				)
			).toEqual({ bad("z-nile", "tests/run.luau", ROOT) })
			-- a top-level cd
			t.expect(findings("z-nile", {}, 'cd "$ZN_ROOT"\ntest -f tests/run.luau\n'))
				.toEqual({ bad("z-nile", "tests/run.luau", ROOT) })
			-- parentheses inside quotes neither end nor extend the group
			t.expect(
				findings("z-nile", {}, '(cd "$ZN_ROOT" && test "$x" != ")" && test -f tests/run.luau)\n')
			)
				.toEqual({ bad("z-nile", "tests/run.luau", ROOT) })
			t.expect(
				findings("z-nile", {}, '(cd "$ZN_ROOT" && test "$x" != "(" ); test -f z-nile/roots.luau\n')
			)
				.toEqual({ bad("z-nile", "z-nile/roots.luau") })
			-- a literal cd after the root cd goes on from the root
			t.expect(
				findings(
					"z-nile",
					{},
					'cd "$ZN_ROOT" && cd pickman && test -d src/server && test -d src/gone\n'
				)
			).toEqual({ bad("z-nile", "pickman/src/gone", ROOT) })
			-- the script's closing quote ends it
			t.expect(
				findings(
					"z-nile",
					{},
					'check "AC1" bash -c \'cd "$ZN_ROOT" && true\' && test -f z-nile/roots.luau\n'
				)
			).toEqual({ bad("z-nile", "z-nile/roots.luau") })
		end
	)

	it("a word in a code span is prose, all of the span, and a bare path next to it is still read", function()
		t.expect(
			findings(
				"z-nile",
				{},
				[=[foo "\`git diff -- src/server\` and \`tests/run\`" src/gone.luau]=] .. "\n"
			)
		).toEqual({ bad("z-nile", "src/gone.luau") })
		t.expect(findings("z-nile", {}, [=[foo "\`src/a\`" tests/gone.md]=] .. "\n"))
			.toEqual({ bad("z-nile", "tests/gone.md") })
	end)

	it(
		"the message of an echo or printf is prose, in command position only, and the next command is still read",
		function()
			local check =
				'test -f tests/run.luau || { echo "z-nile/roots and src/gone.luau no longer exist"; test -f src/gone2.luau; }\n'
			t.expect(findings("z-nile", {}, check)).toEqual({ bad("z-nile", "src/gone2.luau") })
			t.expect(findings("z-nile", {}, 'printf "z-nile/roots is gone\\n"; test -f src/gone2.luau\n'))
				.toEqual({ bad("z-nile", "src/gone2.luau") })
			-- the word echo as an argument marks nothing
			t.expect(findings("z-nile", {}, 'grep -qF "echo" tests/gone.md\n'))
				.toEqual({ bad("z-nile", "tests/gone.md") })
			t.expect(findings("z-nile", {}, 'foo "grep" tests/gone.md\n'))
				.toEqual({ bad("z-nile", "tests/gone.md") })
			t.expect(findings("z-nile", {}, 'foo "run echo" tests/gone.md\n'))
				.toEqual({ bad("z-nile", "tests/gone.md") })
			-- an echo inside a bash -c script is still a command
			t.expect(findings("z-nile", {}, 'check "AC1" bash -c \'echo "src/gone.luau is gone"\'\n'))
				.toEqual({})
		end
	)

	it(
		"the quoted arguments of a search helper the check defines are text, across line continuations",
		function()
			-- c0292's `has`: file first, a loop over the texts; the call spans lines
			local call = 'has "$L" "full gate" "tests/run" \\\n  "src/nothing" \\\n  "z-nile/roots"\n'
			t.expect(findings("z-nile", {}, HAS .. call)).toEqual({})
			-- the same words with no definition are paths
			t.expect(findings("z-nile", {}, 'foo "$L" "tests/run" \\\n  "src/nothing"\n'))
				.toEqual({ bad("z-nile", "src/nothing"), bad("z-nile", "tests/run") })
			-- a bare path argument is still read, and a command after the call
			t.expect(findings("z-nile", {}, HAS .. 'has "$L" "x" tests/gone.md\ntest -f src/gone.luau\n'))
				.toEqual({ bad("z-nile", "src/gone.luau"), bad("z-nile", "tests/gone.md") })
			-- pattern first (c0256-style one-liner `g`), single-quoted text with backticks (c0264's `words`), a helper that calls a helper
			t.expect(
				findings("z-nile", {}, 'g() { grep -qF -e "$1" "$2" || return 1; }\ng "src/server" "$F"\n')
			)
				.toEqual({})
			t.expect(
				findings(
					"z-nile",
					{},
					HAS .. 'words() { has "$1" "$2"; }\nwords "$F" \'a `tests/run` b src/nothing\'\n'
				)
			).toEqual({})
			-- inside a bash -c script that exports the helper
			t.expect(
				findings("z-nile", {}, HAS .. 'check "AC1" bash -c \'has "$L" "tests/run" "src/nothing"\'\n')
			)
				.toEqual({})
			-- a function that does not search is not a search helper
			t.expect(findings("z-nile", {}, 'typecheck() { lune run "$1"; }\ntypecheck "src/gone.luau"\n'))
				.toEqual({ bad("z-nile", "src/gone.luau") })
		end
	)

	it("a for list that is only matched as text is prose; one the loop opens as a file is read", function()
		local text =
			'for f in z-nile/engine/scan.luau z-nile/tests/lib/loops.luau; do case "$E" in *"$f"*) ;; *) echo "does not name $f"; exit 1;; esac; done\n'
		t.expect(findings("z-nile", {}, text)).toEqual({})
		t.expect(findings("z-nile", {}, 'for f in src/gone.luau; do test -f "$f"; done\n'))
			.toEqual({ bad("z-nile", "src/gone.luau") })
		t.expect(
			findings(
				"z-nile",
				{},
				'for f in src/gone.luau; do case "$E" in *"$f"*) test -f "$f";; esac; done\n'
			)
		).toEqual({ bad("z-nile", "src/gone.luau") })
	end)

	it("the live tree passes, every check.sh read", function()
		-- the check.sh files c0120 exempts by their blob id (its RESTAMPED list), read from its spec
		local exempt: { [string]: boolean } = {}
		local spec = fs.readFile(`{TOP}z-nile/tests/acceptance/c0120/check-paths.spec.luau`)
		for id in string.gmatch(spec, '%["(%x+)"%]%s*=') do
			exempt[id] = true
		end
		local s = scanner.scan(TOP, function(text: string): boolean
			return exempt[serde.hash("sha1", `blob {#text}\0{text}`)] == true
		end)
		t.expect(table.concat(s.bad, "\n")).toBe("")
		t.expect(s.checked).toBe(s.found)
	end)
end)
