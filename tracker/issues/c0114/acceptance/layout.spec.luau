--!strict
-- c0114 AC2: the engine and the whole build moved into z-nile/, ./zn is the command, and every path that a
-- check.sh or a spec of an unfinished raft names still works through a forwarder: scripts/tracker.sh, scripts/check.sh,
-- scripts/setup.sh, scripts/ci-verify.sh, scripts/lib/ac.sh and scripts/affected.luau run the moved file, and each
-- scripts/tracker/<module>.luau and scripts/lib/{sh,graph,changed}.luau returns the moved module itself. The shared
-- engine files (templates, counter, compaction map) left tracker/; tracker/next stays as a tombstone that never parses.
local fs = require("@lune/fs")
local ids = require("@znile/engine/ids")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- every engine module and moved library, required through both paths
local SHIMS: { { any } } = {
	{ "audit", require("@scripts/tracker/audit") :: any, require("@znile/engine/audit") :: any },
	{ "board", require("@scripts/tracker/board") :: any, require("@znile/engine/board") :: any },
	{ "chart", require("@scripts/tracker/chart") :: any, require("@znile/engine/chart") :: any },
	{ "claims", require("@scripts/tracker/claims") :: any, require("@znile/engine/claims") :: any },
	{ "compact", require("@scripts/tracker/compact") :: any, require("@znile/engine/compact") :: any },
	{ "gate", require("@scripts/tracker/gate") :: any, require("@znile/engine/gate") :: any },
	{ "history", require("@scripts/tracker/history") :: any, require("@znile/engine/history") :: any },
	{ "ids", require("@scripts/tracker/ids") :: any, require("@znile/engine/ids") :: any },
	{ "ledger", require("@scripts/tracker/ledger") :: any, require("@znile/engine/ledger") :: any },
	{ "lessons", require("@scripts/tracker/lessons") :: any, require("@znile/engine/lessons") :: any },
	{ "paths", require("@scripts/tracker/paths") :: any, require("@znile/engine/paths") :: any },
	{ "projects", require("@scripts/tracker/projects") :: any, require("@znile/engine/projects") :: any },
	{ "publish", require("@scripts/tracker/publish") :: any, require("@znile/engine/publish") :: any },
	{ "spend", require("@scripts/tracker/spend") :: any, require("@znile/engine/spend") :: any },
	{ "stats", require("@scripts/tracker/stats") :: any, require("@znile/engine/stats") :: any },
	{ "status", require("@scripts/tracker/status") :: any, require("@znile/engine/status") :: any },
	{ "store", require("@scripts/tracker/store") :: any, require("@znile/engine/store") :: any },
	{ "trail", require("@scripts/tracker/trail") :: any, require("@znile/engine/trail") :: any },
	{ "sh", require("@scripts/lib/sh") :: any, require("@znile/lib/sh") :: any },
	{ "graph", require("@scripts/lib/graph") :: any, require("@znile/lib/graph") :: any },
	{ "changed", require("@scripts/lib/changed") :: any, require("@znile/lib/changed") :: any },
}

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- the lines of a shell script that run something: no shebang, no comment, no blank
local function commands(path: string): { string }
	local out: { string } = {}
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		if not string.match(line, "^%s*#") and string.match(line, "%S") then
			table.insert(out, line)
		end
	end
	return out
end

local function executable(path: string): boolean
	return process.exec("test", { "-x", path }).ok
end

return t.spec("c0114 the engine and the build live in z-nile/", function(it)
	it("the engine, the build, the templates, the counter and the map are under z-nile/", function()
		for _, f in
			{
				"z-nile/engine/main.luau",
				"z-nile/engine/board.html",
				"z-nile/engine/projects.luau",
				"z-nile/lib/ac.sh",
				"z-nile/lib/fence.sh",
				"z-nile/lib/par.sh",
				"z-nile/lib/replace-file.pl",
				"z-nile/lib/sh.luau",
				"z-nile/lib/graph.luau",
				"z-nile/lib/changed.luau",
				"z-nile/lib/git-hooks/reference-transaction",
				"z-nile/lib/git-hooks/pre-push",
				"z-nile/check.sh",
				"z-nile/affected.luau",
				"z-nile/setup.sh",
				"z-nile/ci-verify.sh",
				"z-nile/templates/issue/doc.md",
				"z-nile/templates/issue/check.sh",
				"z-nile/templates/raft/doc.md",
				"z-nile/templates/raft/check.sh",
				"z-nile/templates/prompt.md",
				"z-nile/vendor/marked.umd.js",
				"z-nile/projects.toml",
			}
		do
			if not fs.isFile(f) then
				error(`missing: {f}`)
			end
		end
		for _, f in
			{
				"zn",
				"z-nile/check.sh",
				"z-nile/setup.sh",
				"z-nile/ci-verify.sh",
				"z-nile/lib/git-hooks/pre-push",
			}
		do
			t.expect(executable(f)).toBe(true)
		end
		t.expect(ids.FILE).toBe("z-nile/next")
		t.expect(ids.MAP_FILE).toBe("z-nile/compaction.txt")
		t.expect(ids.parse(fs.readFile("z-nile/next")) ~= nil).toBe(true)
		t.expect(ids.parseMap(fs.readFile("z-nile/compaction.txt")) ~= nil).toBe(true)
	end)

	it("nothing of the build is left at its old path, and tracker/next is a tombstone", function()
		for _, gone in
			{
				"tracker/templates",
				"tracker/compaction.txt",
				"scripts/vendor",
				"scripts/lib/fence.sh",
				"scripts/lib/par.sh",
				"scripts/lib/replace-file.pl",
				"scripts/lib/git-hooks",
				"scripts/tracker/main.luau",
				"scripts/tracker/board.html",
			}
		do
			if fs.isFile(gone) or fs.isDir(gone) then
				error(`still there: {gone}`)
			end
		end
		-- an engine from before the move reads tracker/next: it must refuse to number, never fall back
		t.expect(fs.isFile(ids.OLD_FILE)).toBe(true)
		t.expect(ids.OLD_FILE).toBe("tracker/next")
		t.expect(ids.parse(fs.readFile(ids.OLD_FILE))).toBe(nil)
	end)

	it("./zn runs the engine from the repository root", function()
		local zn = commands("zn")
		t.expect(table.find(zn, 'cd "$(dirname "$0")"') ~= nil).toBe(true)
		t.expect(table.find(zn, 'exec lune run z-nile/engine/main -- "$@"') ~= nil).toBe(true)
		local usage = process.exec("bash", { "zn" })
		t.expect(has(usage.stdout, "usage: ./zn <command>")).toBe(true)
	end)

	it("each forwarder is one command that runs the moved file", function()
		local want: { [string]: string } = {
			["scripts/tracker.sh"] = 'exec bash "$(dirname "$0")/../zn" "$@"',
			["scripts/check.sh"] = 'exec bash "$(dirname "$0")/../z-nile/check.sh" "$@"',
			["scripts/setup.sh"] = 'exec bash "$(dirname "$0")/../z-nile/setup.sh" "$@"',
			["scripts/ci-verify.sh"] = 'exec bash "$(dirname "$0")/../z-nile/ci-verify.sh" "$@"',
		}
		for path, line in want do
			t.expect(commands(path)).toEqual({ line })
			t.expect(executable(path)).toBe(true)
		end
		local ac = commands("scripts/lib/ac.sh")
		t.expect(#ac).toBe(1)
		t.expect(has(ac[1], 'source "$(dirname "${BASH_SOURCE[0]}")/../../z-nile/lib/ac.sh"')).toBe(true)
		t.expect(has(ac[1], "exit 1")).toBe(true) -- a missing target fails the check.sh
		t.expect(has(fs.readFile("scripts/affected.luau"), '"z-nile/affected"')).toBe(true)
	end)

	it("the forwarders give the same output and exit code as the moved files", function()
		local function run(argv: { string }): process.ExecResult
			return process.exec("bash", argv)
		end
		local a, b = run({ "scripts/tracker.sh", "find", "c0114" }), run({ "zn", "find", "c0114" })
		t.expect(a.ok).toBe(true)
		t.expect(a.stdout).toBe(b.stdout)
		local x, y = run({ "scripts/tracker.sh", "find", "c9999" }), run({ "zn", "find", "c9999" })
		t.expect(x.ok).toBe(false)
		t.expect(x.code).toBe(y.code)
		local sel = process.exec("lune", { "run", "scripts/affected", "--", "z-nile/engine/main.luau" })
		t.expect(sel.ok).toBe(true)
		t.expect(sel.stdout).toBe("ALL\n")
	end)

	it(
		"every scripts/ module shim returns the moved module itself, so its types and state are shared",
		function()
			t.expect(#SHIMS).toBe(21)
			for _, s in SHIMS do
				if not rawequal(s[2], s[3]) then
					error(`{s[1]}: the scripts/ path is not the moved module`)
				end
			end
		end
	)

	it("the znile alias names z-nile/", function()
		t.expect(has(fs.readFile(".luaurc"), '"znile": "./z-nile"')).toBe(true)
	end)
end)
