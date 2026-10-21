--!strict
-- c0120 AC11 (finished half): every literal path in a finished item's check.sh that resolved from the repository root
-- before the move resolves from the item's home after it (decided with the user, 2026-10-21: "Rewrite them too"). The
-- rewrite (rewrites.luau) is proved on a fixture with a real move commit: a moved path is rewritten from the home, a
-- path that still resolves is kept, a path stale before the move is kept, a root file becomes ../, prose and comments
-- stay, and a second run changes nothing. Then the rule is checked on the repository itself: every finished check.sh,
-- each path either resolves from its home or was already stale before the move. These specs run from z-nile/.
-- Fixture under .cache/c0120-finished (this home's).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("./rewrites")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local FX = `{here}/.cache/c0120-finished`

local function put(rel: string, text: string)
	fs.writeDir(string.match(`{FX}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{FX}/{rel}`, text)
end

local PICKMAN_DONE = table.concat({
	"#!/usr/bin/env bash",
	"# tracker/architecture.md in a comment stays",
	'check "AC1: tracker/architecture.md is prose" grep -q deps tracker/architecture.md',
	'check "AC2: the server is untouched" git diff --quiet -- src/server',
	'check "AC3: the gate" z-nile/check.sh --full',
	'for dir in $(./zn members R0001); do check "x" bash "$dir/check.sh"; done',
	'check "AC4: gone before the move" test -f tests/gone.luau',
	"check \"AC5: a glob\" bash -c 'ls tracker/issues/done/*/check.sh'",
	"",
}, "\n")
local ZNILE_DONE = table.concat({
	"#!/usr/bin/env bash",
	'check "AC1: ci" scripts/ci-verify.sh',
	'check "AC2: specs" lune run tests/run -- tests/tooling/x.spec.luau',
	'check "AC3: a pickman spec" test -f tests/acceptance/f0001/a.spec.luau',
	'check "AC4: the gate" z-nile/check.sh --full',
	"",
}, "\n")

local function git(args: { string }): string
	return fixture.git(FX, args)
end

return t.spec("c0120 finished check.sh files still name paths that resolve from their home", function(it)
	it("rewrites a finished check.sh's moved paths from its home, and nothing else", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		fs.writeDir(FX)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", FX }).ok).toBe(true)
		git({ "config", "user.name", "c0120" })
		git({ "config", "user.email", "c0120@example.invalid" })
		-- before the move: c0114's tree, pickman at tracker/, the tooling at the root
		put("zn", "#!/usr/bin/env bash\n")
		put("z-nile/check.sh", "#!/usr/bin/env bash\n")
		put("scripts/ci-verify.sh", "#!/usr/bin/env bash\n")
		put("src/server/Main.server.luau", "--!strict\nreturn nil\n")
		put("tests/run.luau", "--!strict\nreturn nil\n")
		put("tests/tooling/x.spec.luau", "--!strict\nreturn nil\n")
		put("tests/acceptance/f0001/a.spec.luau", "--!strict\nreturn nil\n")
		put("tracker/architecture.md", "deps\n")
		put("tracker/issues/done/f0001/f0001.md", "---\nid: f0001\n---\n")
		put("tracker/issues/done/f0001/check.sh", "#!/usr/bin/env bash\n")
		put(rewrites.MARK, PICKMAN_DONE)
		put("z-nile/.tracker/issues/done/c0001/check.sh", ZNILE_DONE)
		put(
			"z-nile/projects.toml",
			'[[project]]\nname = "pickman"\nroot = "tracker"\n\n[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		git({ "add", "-A" })
		git({ "commit", "-qm", "before the move" })
		-- the move: renames only
		for _, pair in
			{
				{ "src", "pickman/src" },
				{ "tests/acceptance/f0001", "pickman/tests/acceptance/f0001" },
				{ "tests/run.luau", "z-nile/tests/run.luau" },
				{ "tests/tooling", "z-nile/tests/tooling" },
				{ "tracker/architecture.md", "pickman/.tracker/architecture.md" },
				{ "tracker/issues", "pickman/.tracker/issues" },
				{ "tracker/rafts", "pickman/.tracker/rafts" },
			}
		do
			fs.writeDir(string.match(`{FX}/{pair[2]}`, "^(.*)/[^/]+$") :: string)
			git({ "mv", pair[1], pair[2] })
		end
		put(
			"z-nile/projects.toml",
			'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
				.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		put("pickman/tests/run.luau", "--!strict\nreturn nil\n") -- a home's runner, as c0120 adds
		git({ "add", "-A" })
		git({ "commit", "-qm", "the move" })
		local pre, why = rewrites.premove(FX)
		t.expect(why).toBe(nil)
		local world = rewrites.world(FX, pre :: string)
		local pickman =
			rewrites.rewrite(fs.readFile(`{FX}/pickman/.tracker/rafts/done/R0001/check.sh`), "pickman", world)
		t.expect(pickman).toBe(table.concat({
			"#!/usr/bin/env bash",
			"# tracker/architecture.md in a comment stays",
			'check "AC1: tracker/architecture.md is prose" grep -q deps .tracker/architecture.md',
			'check "AC2: the server is untouched" git diff --quiet -- src/server',
			'check "AC3: the gate" ../z-nile/check.sh --full',
			'for dir in $(../zn members R0001); do check "x" bash "$dir/check.sh"; done',
			'check "AC4: gone before the move" test -f tests/gone.luau',
			"check \"AC5: a glob\" bash -c 'ls .tracker/issues/done/*/check.sh'",
			"",
		}, "\n"))
		local znile = rewrites.rewrite(fs.readFile(`{FX}/z-nile/.tracker/issues/done/c0001/check.sh`), "z-nile", world)
		t.expect(znile).toBe(table.concat({
			"#!/usr/bin/env bash",
			'check "AC1: ci" ../scripts/ci-verify.sh',
			'check "AC2: specs" lune run tests/run -- tests/tooling/x.spec.luau',
			'check "AC3: a pickman spec" test -f ../pickman/tests/acceptance/f0001/a.spec.luau',
			'check "AC4: the gate" ./check.sh --full',
			"",
		}, "\n"))
		-- written and run again, it changes nothing
		fs.writeFile(`{FX}/pickman/.tracker/rafts/done/R0001/check.sh`, pickman)
		t.expect(rewrites.rewrite(pickman, "pickman", world)).toBe(pickman)
		t.expect(rewrites.rewrite(znile, "z-nile", world)).toBe(znile)
		fs.removeDir(FX)
	end)

	it("the path from one folder to another", function()
		t.expect(rewrites.relative("pickman", "pickman/.tracker/x")).toBe(".tracker/x")
		t.expect(rewrites.relative("pickman", "z-nile/check.sh")).toBe("../z-nile/check.sh")
		t.expect(rewrites.relative("z-nile", "z-nile/check.sh")).toBe("check.sh")
		t.expect(rewrites.relative("z-nile/sub", "zn")).toBe("../../zn")
	end)

	it(
		"every finished check.sh in the repository names paths that resolve from its home, or were stale before",
		function()
			local pre, why = rewrites.premove(TOP)
			if not pre then
				error(`the tree before the move is not known: {why}`)
			end
			local world = rewrites.world(TOP, pre)
			local reg = projects.load(TOP, true)
			local bad: { string } = {}
			local read = 0
			for _, root in projects.roots(reg) do
				for _, kind in { "issues", "rafts" } do
					local dir = `{TOP}/{root}/{kind}/done`
					if fs.isDir(dir) then
						for _, id in fs.readDir(dir) do
							local file = `{root}/{kind}/done/{id}/check.sh`
							if string.match(id, "^[fdcR]%d%d%d%d$") and fs.isFile(`{TOP}/{file}`) then
								read += 1
								local home = projects.homeOf(reg, file)
								for _, l in rewrites.literals(fs.readFile(`{TOP}/{file}`)) do
									local from = if l.dir == "" then home else `{home}/{l.dir}`
									if not world.now(`{from}/{l.path}`) and world.before(l.dir .. l.path) then
										table.insert(bad, `{file}: {l.word} (from {home})`)
									end
								end
							end
						end
					end
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
			t.expect(read > 0).toBe(true)
		end
	)
end)
