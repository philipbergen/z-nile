--!strict
-- c0156 AC5: R0045's mutation record (c0128's, the one the Solution names) joins a line onto a comment in each of the
-- three pinned files, each of its join entries really is that mutant (applied to the file as it is now, it turns exactly
-- one line break into a space after a line that holds a `--`, once, and the pin rule's digest of the result differs), it
-- runs the promoted specs, and it refuses to run on anything but the pickman home of a separate clone under the temp
-- folder, each of its four conditions on its own. The record lists its join entries as JSON (`mutants.py --joins`,
-- read-only). The refusals run with TMPDIR pointed at a fixture folder under this home's .cache, so "under the temp
-- folder" is a folder made here (under the checkout's z-nile/.cache, which check.sh fences), and the accept case stops
-- at its first missing file and writes nothing. A refusal is checked by its effect (exit, output), not by its words alone.
local fs = require("@lune/fs")
local pin = require("@tests/lib/pin")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local scripted = require("./scripted")
local serde = require("@lune/serde")

local TOP = scripted.top()
local has = scripted.has
-- spelled in two parts so a compaction does not rewrite the path; the id is mapped through the compaction map
local RECORD = `{TOP}/pickman/.tracker/rafts/done/{renamed.id("R0045")}/experiments/mutants.py`

type Join = { name: string, path: string, old: string, new: string }

local function count(text: string, needle: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(text, needle, from, true)
		if at == nil then
			return n
		end
		n += 1
		from = at + #needle
	end
end

local listed = process.exec("python3", { "-I", RECORD, "--joins" })
scripted.check("the record lists its join entries", listed.code == 0, listed.stderr)
local joins: { Join } = if listed.code == 0 then serde.decode("json", listed.stdout) :: { Join } else {}

local names: { [string]: boolean } = {}
local paths: { [string]: boolean } = {}
for _, j in joins do
	names[j.name] = true
	paths[j.path] = true
end
scripted.check("it has four join entries", #joins == 4)
for _, name in
	{ "join-f0024-comment", "join-f0026-reads-comment", "join-f0026-companion-comment", "join-f0014-comment" }
do
	scripted.check(`it has {name}`, names[name] == true)
end
local acc = "tests/" .. "acceptance/"
scripted.check("it touches f0014's keys.spec", paths[acc .. renamed.id("f0014") .. "/keys.spec.luau"] == true)
scripted.check(
	"it touches f0024's adapter.spec",
	paths[acc .. renamed.id("f0024") .. "/adapter.spec.luau"] == true
)
scripted.check(
	"it touches f0026's adapters.spec",
	paths[acc .. renamed.id("f0026") .. "/adapters.spec.luau"] == true
)

for _, j in joins do
	local src = string.gsub(fs.readFile(`{TOP}/pickman/{j.path}`), "\r\n", "\n")
	local at = string.find(j.old, "\n", 1, true)
	local start = string.find(src, j.old, 1, true)
	local oneBreak = count(j.old, "\n") == 1 and at ~= nil
	scripted.check(
		`{j.name}: its old text occurs once in the file and holds one line break`,
		count(src, j.old) == 1 and oneBreak
	)
	if at ~= nil and start ~= nil and count(src, j.old) == 1 then
		scripted.check(
			`{j.name}: its new text is the old with that break a space`,
			j.new == string.sub(j.old, 1, at - 1) .. " " .. string.sub(j.old, at + 1)
		)
		local lineStart = 1
		for i = start - 1, 1, -1 do
			if string.sub(src, i, i) == "\n" then
				lineStart = i + 1
				break
			end
		end
		scripted.check(
			`{j.name}: the line that ends at that break holds a comment`,
			has(string.sub(src, lineStart, start + at - 2), "--")
		)
		local mutated = string.sub(src, 1, start - 1) .. j.new .. string.sub(src, start + #j.old)
		scripted.check(
			`{j.name}: the pin's digest of the file changes`,
			pin.digest(mutated) ~= pin.digest(src)
		)
	end
end

local text = fs.readFile(RECORD)
scripted.check("it runs c0128's promoted specs", has(text, "tests/acceptance/c0128/"))
scripted.check(
	"it runs c0103's promoted narrowed.spec",
	has(text, "tests/acceptance/c0103/narrowed.spec.luau")
)
scripted.check(
	"it no longer names the old sequestered folder",
	not has(text, "tracker/issues/c0128/acceptance")
)

-- the refusal, one condition at a time. A fixture folder stands for the temp folder (TMPDIR for the record's process).
local REFUSAL = "not the pickman home of a separate clone under"
local fixture = `{TOP}/z-nile/.cache/c0156-record`
if fs.isDir(fixture) then
	fs.removeDir(fixture)
end
local tmp = `{fixture}/tmp`
fs.writeDir(tmp)

local function clone(base: string, gitDir: boolean?, worktree: boolean?, homeName: string?): string
	fs.writeDir(base)
	if gitDir == true then
		fs.writeDir(`{base}/.git`)
	elseif gitDir == false then
		fs.writeFile(`{base}/.git`, "gitdir: /nowhere")
	end
	if worktree == true then
		fs.writeDir(`{base}/.worktree`)
	end
	local dir = `{base}/{homeName or "pickman"}`
	fs.writeDir(dir)
	return dir
end

-- the record stopped at its guard: it exited non-zero with nothing on stdout and one line on stderr holding the refusal
-- (a guard that only prints the words and goes on would crash later with a traceback, or edit files, so the words alone
-- are not the refusal)
local function refused(dir: string): (boolean, string)
	local r = process.exec("python3", { "-I", RECORD, dir }, { env = { TMPDIR = tmp } })
	local oneLine = #string.split((string.gsub(r.stderr, "\n+$", "")), "\n") == 1
	local stopped = r.code ~= 0 and r.stdout == "" and oneLine and not has(r.stderr, "Traceback")
	return stopped and has(r.stderr, REFUSAL), r.stderr
end

-- the accepted clone went past the guard: no refusal, and it stopped later at its first missing file
local function accepted(dir: string): (boolean, string)
	local r = process.exec("python3", { "-I", RECORD, dir }, { env = { TMPDIR = tmp } })
	return not has(r.stderr, REFUSAL) and has(r.stderr, "FileNotFoundError"), r.stderr
end

local cases: { { any } } = {
	{ "a clone with a .worktree folder", clone(`{tmp}/a`, true, true), true },
	{ "a worktree (.git is a file)", clone(`{tmp}/b`, false), true },
	{ "a home not named pickman", clone(`{tmp}/c`, true, false, "home"), true },
	{ "a folder outside the temp folder", clone(`{fixture}/outside`, true), true },
	{ "a pickman home of a plain clone under the temp folder", clone(`{tmp}/d`, true), false },
}
for _, c in cases do
	local ok, err = false, ""
	if c[3] then
		ok, err = refused(c[2])
	else
		ok, err = accepted(c[2])
	end
	scripted.check(`the record {if c[3] then "refuses" else "does not refuse"} {c[1]}`, ok, err)
end
scripted.check("the accepted clone is left as it was", #fs.readDir(`{tmp}/d/pickman`) == 0)
fs.removeDir(fixture)

scripted.finish()
