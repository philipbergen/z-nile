--!strict
-- c0374 AC1: c0120's finished-check scan (the last case of tests/acceptance/c0120/finished.spec.luau, "every
-- finished check.sh in the repository names paths that resolve from its home, or were stale before") reads a bare file
-- name inside single quotes as the message, case name or script it is, and nothing else changes: an unquoted path, a
-- path with a folder, and a quote the walk cannot balance are still findings, and a path missing before the move is
-- still allowed.
-- The promoted spec takes seconds for that case and minutes for the rest, so the cases below run only that case: this
-- spec cuts it out of the promoted file (its head up to the spec's opening line, then the case to the end), puts the cut
-- in a --no-hardlinks clone of this checkout under .cache, adds one finished item `c9999` to the clone, and runs the
-- cut there with the clone's own runner. Nothing here writes the real repository.
-- This file has no .spec.luau name on purpose (design review 001 F2, lesson zz-test/specs-never-burn-real-resources):
-- it clones the repository and starts nested runs, which no full gate should repeat for ever. check.sh runs it by path
-- while the sequestered folder exists; the live-tree proof stays in the promoted slow-tier c0120/finished.spec.
-- Fixture under .cache/c0374-reads-homes (this home's).
local clone = require("@tests/lib/clone")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local FX = `{here}/.cache/c0374-reads-homes`
local HOME = `{FX}/repo/z-nile`
local PROMOTED = "tests/acceptance/c0120/finished.spec.luau"
local CUT = "tests/acceptance/c0120/c0374-cut.spec.luau"
local ITEM = `{HOME}/.tracker/issues/done/c9999/check.sh`
local TITLE =
	"every finished check.sh in the repository names paths that resolve from its home, or were stale before"
local PREFIX = "c9999/check.sh: "

-- the promoted spec's head and its last case, as one spec file
local function cut(): string
	local text = fs.readFile(`{TOP}/z-nile/{PROMOTED}`)
	local opening = string.find(text, "\nreturn t.spec(", 1, true)
	local title = string.find(text, TITLE, 1, true)
	t.expect(opening ~= nil and title ~= nil).toBe(true)
	local nextLine = string.find(text, "\n", (opening :: number) + 1, true) :: number
	-- the `it(` that opens the case: the last one before its title
	local at, from = nil, 1
	while true do
		local found = string.find(text, "\tit(", from, true)
		if found == nil or found > (title :: number) then
			break
		end
		at, from = found, found + 1
	end
	t.expect(at ~= nil).toBe(true)
	return string.sub(text, 1, nextLine) .. string.sub(text, at :: number, #text)
end

local prepared = false
local function prepare()
	if prepared then
		return
	end
	prepared = true
	if fs.isDir(FX) then
		fs.removeDir(FX)
	end
	fs.writeDir(FX)
	clone.isolated(TOP, `{FX}/repo`)
	fs.writeFile(`{HOME}/{CUT}`, cut())
end

-- Runs the cut with `script` as the finished item c9999's check.sh (nil: the repository as cloned), and returns
-- whether it passed and what it printed.
local function run(script: string?): (boolean, string)
	prepare()
	if fs.isDir(`{HOME}/.tracker/issues/done/c9999`) then
		fs.removeDir(`{HOME}/.tracker/issues/done/c9999`)
	end
	if script then
		fs.writeDir(`{HOME}/.tracker/issues/done/c9999`)
		fs.writeFile(ITEM, script)
	end
	local r = process.exec("lune", { "run", "tests/run", "--", CUT }, { cwd = HOME })
	return r.ok, r.stdout .. r.stderr
end

-- how many times `needle` is printed
local function count(out: string, needle: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(out, needle, from, true)
		if at == nil then
			return n
		end
		n += 1
		from = at + #needle
	end
end

return t.spec("c0374 the finished-check scan reads single-quoted bare names as text", function(it)
	it("passes on the repository as it is", function()
		local ok, out = run(nil)
		t.expect(count(out, "(from z-nile)")).toBe(0)
		t.expect(ok).toBe(true)
	end)

	it(
		"reads ./zn inside single quotes (a helper's text, a bash -c script over several lines) as text",
		function()
			local ok, out = run(table.concat({
				"#!/usr/bin/env bash",
				"vocabulary() { :; }",
				"vocabulary 'A person approves a design with `./zn approve <id>`' 'the same entries `./zn who` prints'",
				"cases commit-land --run 'AC3: ./zn commit leaves it' 'AC4: ./zn done lands'",
				[[check "AC5: a bash -c script" bash -c 'cd "$ZN_ROOT" && x=$(./zn find c9999)]],
				"  ./zn find c9999 | head -1",
				[[  echo '"'"'./zn'"'"' done']],
				"",
			}, "\n"))
			t.expect(count(out, PREFIX)).toBe(0)
			t.expect(ok).toBe(true)
		end
	)

	it("still reads an unquoted ./zn and zn, also after single-quoted text on the same line", function()
		local ok, out = run(table.concat({
			"#!/usr/bin/env bash",
			"vocabulary 'see ./zn who'; ./zn find x",
			[[check "AC1: y" test -f zn]],
			[[y="$(./zn find c9999)/c9999.md"]],
			"",
		}, "\n"))
		t.expect(ok).toBe(false)
		t.expect(count(out, `{PREFIX}./zn (from z-nile)`)).toBe(2)
		t.expect(count(out, `{PREFIX}zn (from z-nile)`)).toBe(1)
		t.expect(count(out, PREFIX)).toBe(3)
	end)

	it("still reads a path with a folder inside single quotes", function()
		local ok, out = run("#!/usr/bin/env bash\ncheck \"AC1: x\" bash -c 'test -f src/server'\n")
		t.expect(ok).toBe(false)
		t.expect(count(out, `{PREFIX}src/server (from z-nile)`)).toBe(1)
		t.expect(count(out, PREFIX)).toBe(1)
	end)

	it("still allows a path that was missing before the move", function()
		local ok, out = run(
			'#!/usr/bin/env bash\ncheck "AC1: x" test -f tests/gone.luau\ncheck "AC2: y" bash -c \'ls src/nowhere/x\'\n'
		)
		t.expect(count(out, PREFIX)).toBe(0)
		t.expect(ok).toBe(true)
	end)

	it("fails closed on a check.sh whose quotes do not balance", function()
		local ok, out = run("#!/usr/bin/env bash\necho 'unterminated ./zn\n")
		t.expect(ok).toBe(false)
		t.expect(count(out, `{PREFIX}its quotes do not balance`)).toBe(1)
	end)

	it("reads a comment, an escaped quote and a quote inside double quotes as the shell does", function()
		local ok, out = run(table.concat({
			"#!/usr/bin/env bash",
			"# don't count this apostrophe",
			[[x=$(cd "$ZN_ROOT" && "$ZN_ROOT/zn" find c9999 | head -1) # it's fine]],
			[[echo \' ./zn]],
			[[echo "it's" ./zn]],
			"",
		}, "\n"))
		t.expect(count(out, `{PREFIX}its quotes do not balance`)).toBe(0)
		t.expect(count(out, `{PREFIX}./zn (from z-nile)`)).toBe(2)
		t.expect(count(out, PREFIX)).toBe(2)
		t.expect(ok).toBe(false)
	end)

	it("reads a quote inside $( ) inside double quotes, and a # inside a word, as the shell does", function()
		local ok, out = run(table.concat({
			"#!/usr/bin/env bash",
			[[x="$(echo "it's")"]],
			"./zn find c9999",
			"echo issue#1 'see ./zn",
			"here' ./zn find c9999",
			"",
		}, "\n"))
		t.expect(count(out, `{PREFIX}its quotes do not balance`)).toBe(0)
		t.expect(count(out, `{PREFIX}./zn (from z-nile)`)).toBe(2)
		t.expect(count(out, PREFIX)).toBe(2)
		t.expect(ok).toBe(false)
	end)

	it("reads a bare root file inside bash -c single quotes as text, with no cd before it (G1)", function()
		local ok, out =
			run("#!/usr/bin/env bash\ncheck \"AC1: x\" bash -c 'test -x zn && test -f AGENTS.md'\n")
		t.expect(count(out, PREFIX)).toBe(0)
		t.expect(ok).toBe(true)
	end)

	it("reads a heredoc body as shell text (a known edge): its apostrophes can hide a bare name", function()
		local ok, out = run(table.concat({
			"#!/usr/bin/env bash",
			"cat > x.sh <<EOF",
			"we don't",
			"test -x zn",
			"it's done",
			"EOF",
			"",
		}, "\n"))
		t.expect(count(out, `{PREFIX}its quotes do not balance`)).toBe(0)
		t.expect(count(out, PREFIX)).toBe(0)
		t.expect(ok).toBe(true)
	end)

	it("leaves no fixture behind", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		t.expect(fs.isDir(FX)).toBe(false)
	end)
end)
