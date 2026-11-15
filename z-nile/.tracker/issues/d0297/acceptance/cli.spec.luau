--!strict
-- d0297: `lune run z-nile/affected`, the program the gate runs, never prints a sequestered spec: not on a prep branch
-- that adds them (committed, or untracked in the working tree), not in the gate's own `--project` form, and not on a
-- layer branch, whose ticket's own sequestered specs it prints only with --own-acceptance (./zn finish's flag). The
-- gate never passes that flag; finish does. Fixture: .cache/d0297-cli (no origin push, no publish).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SPEC = "--!strict\nreturn nil\n"
local NEXT = "issue 1 fixture\nraft 1 fixture\n"
local OWN = "pickman/.tracker/issues/active/c0010/acceptance/own.spec.luau"
local SEQUESTERED = {
	"z-nile/.tracker/issues/c0261/acceptance/docs.spec.luau",
	"pickman/.tracker/issues/f0001/acceptance/a.spec.luau",
	"pickman/.tracker/issues/f0001/proofs/race.spec.luau",
}
local UNTRACKED = "pickman/.tracker/issues/f0001/acceptance/late.spec.luau"
local ADDED = "pickman/tests/unit/added.spec.luau"

local f: trackerfix.Fixture

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

-- `lune run z-nile/affected -- <args>` in the fixture's main clone: its printed lines (raises when it fails)
local function affected(args: { string }): { string }
	local argv = { "run", "z-nile/affected", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = fixture.exec(f.main, "lune", argv)
	if not r.ok then
		error(`z-nile/affected {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

return t.spec("d0297 the program the gate runs never prints a sequestered spec", function(it)
	it("sets up a fixture with a layer ticket and a prep branch", function()
		local stub = trackerfix.stub
		f = trackerfix.new("d0297-cli", {
			["z-nile/next"] = NEXT,
			["pickman/src/alpha.luau"] = "return {}\n",
			["pickman/.tracker/issues/active/c0010/c0010.md"] = stub(
				"c0010",
				"own",
				"active-quiet-copper-falcon"
			),
			[OWN] = SPEC,
		})
		fixture.git(f.main, { "checkout", "-q", "-b", "prep-demo" })
		for _, path in SEQUESTERED do
			write(f.main, path, SPEC)
		end
		write(
			f.main,
			"z-nile/.tracker/issues/c0261/c0261.md",
			stub("c0261", "docs", "preparing-quiet-copper-falcon")
		)
		write(f.main, "z-nile/.tracker/issues/c0261/check.sh", "#!/usr/bin/env bash\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "prep" })
		write(f.main, UNTRACKED, SPEC)
		t.expect(fs.isFile(`{f.main}/{UNTRACKED}`)).toBe(true)
	end)

	it(
		"AC2: on a prep branch the selector prints none of its sequestered specs, in every form the gate uses",
		function()
			t.expect(affected({})).toEqual({}) -- the branch against origin/main, untracked files included
			t.expect(affected({ "--project", "z-nile", "--base", "main" })).toEqual({}) -- the gate's own call
			t.expect(affected(SEQUESTERED)).toEqual({}) -- the captured reproduction: the paths named
			-- the flag adds only a layer's own ticket: a prep branch has none
			t.expect(affected({ "--own-acceptance" })).toEqual({})
			-- control: a spec the branch adds under tests/ is still printed beside them
			write(f.main, ADDED, SPEC)
			write(f.main, "pickman/tests/unit/added.watch.txt", "pickman/src/alpha.luau\n")
			t.expect(affected({})).toEqual({ ADDED })
			t.expect(affected({ "--project", "pickman" })).toEqual({ "tests/unit/added.spec.luau" })
			fs.removeFile(`{f.main}/{ADDED}`)
			fs.removeFile(`{f.main}/pickman/tests/unit/added.watch.txt`)
		end
	)

	it(
		"AC2: on a layer branch the ticket's own sequestered specs print only with --own-acceptance",
		function()
			fixture.git(f.main, { "checkout", "-q", "main" })
			fixture.git(f.main, { "checkout", "-q", "-b", "R0010/1/c0010" })
			local src = "pickman/src/alpha.luau"
			t.expect(affected({ src })).toEqual({})
			-- the forms a raft's RC0 gate runs on a layer branch: the branch's own committed change, with --project
			write(f.main, src, "return { layer = true }\n")
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-q", "-m", "layer work" })
			t.expect(affected({ "--project", "pickman" })).toEqual({})
			t.expect(affected({ "--project", "pickman", "--base", "main" })).toEqual({})
			t.expect(affected({ "--own-acceptance", src })).toEqual({ OWN })
			t.expect(affected({ "--project", "pickman", "--own-acceptance", src })).toEqual({
				".tracker/issues/active/c0010/acceptance/own.spec.luau",
			})
		end
	)

	it("AC2: ./zn finish is the one caller that passes --own-acceptance; the gate never does", function()
		local gate = fs.readFile(`{TOP}/z-nile/check.sh`)
		t.expect(string.find(gate, "z-nile/affected", 1, true) ~= nil).toBe(true)
		-- uses of the flag in code: a comment that names it is not a use (in a .luau file a `--` line or a ` -- ` line
		-- end, in any other file a `#` line or a ` # ` line end)
		local function count(text: string, luau: boolean): number
			local n = 0
			for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
				local code = if luau
					then string.gsub(string.gsub(line, "^%s*%-%-.*$", ""), "%s%-%-%s.*$", "")
					else string.gsub(string.gsub(line, "^%s*#.*$", ""), "%s#%s.*$", "")
				for _ in string.gmatch(code, "%-%-own%-acceptance") do
					n += 1
				end
			end
			return n
		end
		local function ls(paths: { string }): { string }
			local argv = { "ls-files", "--" }
			for _, path in paths do
				table.insert(argv, path)
			end
			table.insert(argv, ":(exclude,glob)**/.tracker/**")
			local r = process.exec("git", argv, { cwd = TOP })
			t.expect(r.ok).toBe(true)
			local out: { string } = {}
			for path in string.gmatch(r.stdout, "[^\n]+") do
				if fs.isFile(`{TOP}/{path}`) then
					table.insert(out, path)
				end
			end
			return out
		end
		-- (a) no file a gate, hook or forwarder runs from uses the flag (the selector, which defines it, aside)
		local holders: { string } = {}
		for _, path in ls({
			"zn",
			"scripts",
			":(glob)z-nile/*.sh",
			":(glob)z-nile/*.luau",
			"z-nile/bin",
			"z-nile/lib",
			"z-nile/scripts",
			".claude",
		}) do
			if
				path ~= "z-nile/affected.luau"
				and count(fs.readFile(`{TOP}/{path}`), string.sub(path, -5) == ".luau") > 0
			then
				table.insert(holders, path)
			end
		end
		t.expect(holders).toEqual({})
		-- (b) in the engine, whichever file holds finish (c0180 may split main.luau by command), every use lies in the
		-- argv of a selector call (from its "z-nile/affected" to the run that follows), in a file that also writes the
		-- layer's results.txt; (c) there is at least one
		local total = 0
		for _, path in ls({ "z-nile/engine" }) do
			local text = fs.readFile(`{TOP}/{path}`)
			local n = count(text, string.sub(path, -5) == ".luau")
			if n > 0 then
				t.expect({ path = path, writesResults = string.find(text, "results.txt", 1, true) ~= nil })
					.toEqual({
						path = path,
						writesResults = true,
					})
				local inCalls = 0
				local from = 1
				while true do
					local at = string.find(text, '"z-nile/affected"', from, true)
					if not at then
						break
					end
					local stop = #text
					for _, run in { "sh.run(", "sh.stream(", "process.exec(" } do
						local found = string.find(text, run, at, true)
						if found and found < stop then
							stop = found
						end
					end
					inCalls += count(string.sub(text, at, stop), true)
					from = stop + 1
				end
				t.expect({ path = path, outsideSelectorCalls = n - inCalls }).toEqual({
					path = path,
					outsideSelectorCalls = 0,
				})
				total += n
			end
		end
		t.expect(total >= 1).toBe(true)
	end)
end)
