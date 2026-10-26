--!strict
-- c0137: four finished checks read `.claude` from z-nile/, their project home since c0120, where it does not exist, so
-- they pass vacuously: c0044 AC9's and c0067 AC10's banned-phrase greps, R0025 RC1's, and c0067 AC10's
-- `[ ! -e .claude/skills/make-prompt ]`. Each line is taken from its finished check.sh as it is in the checkout and run
-- in a fixture home under .cache with the folders it names (the skills' real folders since c0115: z-nile/skills and
-- pickman/skills, behind the .claude/skills links), clean and with a phrase planted in each folder, and once in the real
-- home, where it must find nothing. Reads the real files only; writes only under .cache.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HOME = `{TOP}/z-nile` -- the finished checks' project home (c0120)
local FX = `{process.cwd}/.cache/c0137-scans` -- the fixture checkout's top; its home is {FX}/z-nile

-- the line of `file` (repository-relative) that contains `needle`, exactly one
local function line(file: string, needle: string): string
	local found: { string } = {}
	for l in string.gmatch(fs.readFile(`{TOP}/{file}`), "[^\n]+") do
		if string.find(l, needle, 1, true) then
			table.insert(found, l)
		end
	end
	if #found ~= 1 then
		error(`{file}: {#found} lines contain {needle}`)
	end
	return found[1]
end

-- the four lines c0137 rewrites, each found by text only it has
local SCANS = {
	{
		name = "c0044 AC9",
		file = "z-nile/.tracker/issues/done/c0044/check.sh",
		needle = '-e "-<slug>.md"',
		phrase = "-<slug>.md",
	},
	{
		name = "c0067 AC10",
		file = "z-nile/.tracker/issues/done/c0067/check.sh",
		needle = '-e "pbcopy"',
		phrase = "pbcopy",
	},
	{
		name = "R0025 RC1",
		file = "z-nile/.tracker/rafts/done/R0025/check.sh",
		needle = '-e "./zn launch"',
		phrase = "./zn launch",
	},
}
local EXISTS = { file = "z-nile/.tracker/issues/done/c0067/check.sh", needle = "make-prompt ]" }

local function put(rel: string, text: string)
	local path = `{FX}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
-- a fixture checkout with every folder the lines name, and the .claude/skills links to the real folders
local function setUp()
	if fs.isDir(FX) then
		fs.removeDir(FX)
	end
	for _, rel in
		{
			"z-nile/skills/zz-a/SKILL.md",
			"z-nile/templates/t.md",
			"z-nile/scripts/s.sh",
			"pickman/skills/pickman-a/SKILL.md",
			"AGENTS.md",
			"SETUP.md",
			".claude/settings.json",
		}
	do
		put(rel, "nothing banned here\n")
	end
	fs.writeDir(`{FX}/.claude/skills`)
	process.exec("ln", { "-s", "../../z-nile/skills/zz-a", `{FX}/.claude/skills/zz-a` })
	process.exec("ln", { "-s", "../../pickman/skills/pickman-a", `{FX}/.claude/skills/pickman-a` })
end

-- what a grep line leaves in $bad, run from `home`
local function bad(scan: string, home: string): string
	local r = process.exec("bash", { "-c", scan .. '\nprintf "%s" "$bad"' }, { cwd = home })
	return r.stdout
end
-- how a grep line ends when run from `home` (no planted phrase): whether its script went on, and what it wrote to
-- stderr. A folder the grep names that is missing must stop it (design review 001 F1): grep's exit 2 is not "clean".
local function runs(scan: string, home: string): { ok: boolean, stderr: string }
	local r = process.exec("bash", { "-c", scan .. '\nprintf "%s" "$bad"' }, { cwd = home })
	return { ok = r.ok, stderr = r.stderr }
end
-- the folders an existence line tests (`-e <dir>/make-prompt`)
local function testedDirs(test: string): { string }
	local out: { string } = {}
	for dir in string.gmatch(test, "%-e (%S+)/make%-prompt") do
		table.insert(out, dir)
	end
	return out
end
-- whether an existence line passes, run from `home`
local function absent(test: string, home: string): boolean
	local r = process.exec("bash", { "-c", (string.gsub(test, "%s*||.*$", "")) }, { cwd = home })
	return r.ok
end

-- a bare `.claude` operand: `.claude` after the start, a space, a quote or a parenthesis (the capture's search)
local function bareClaude(l: string): boolean
	return string.find(" " .. l, '[ "(]%.claude[ /"]') ~= nil or string.find(l, '[ "(]%.claude$') ~= nil
end

-- the shell script of a whole `check "<label>…" bash -c '…'` criterion in a finished check.sh (design review 002 F1:
-- a fixed line is only reachable when every statement before it in its criterion passes)
local function criterion(file: string, label: string): string
	local text = fs.readFile(`{TOP}/{file}`)
	local start = string.find(text, `\ncheck "{label}`, 1, true)
	if not start then
		error(`{file}: no criterion {label}`)
	end
	local open = string.find(text, "bash -c '", start, true)
	local close = string.find(text, "'\n", (open :: number) + 9, true)
	if not open or not close then
		error(`{file}: {label} is not a bash -c criterion`)
	end
	return string.sub(text, (open :: number) + 9, (close :: number) - 1)
end
local CRITERIA = {
	{ file = "z-nile/.tracker/issues/done/c0044/check.sh", label = "AC9:" },
	{ file = "z-nile/.tracker/issues/done/c0067/check.sh", label = "AC10:" },
	{ file = "z-nile/.tracker/rafts/done/R0025/check.sh", label = "RC1:" },
}

return t.spec("c0137 finished checks read the skills where they are", function(it)
	it("the bare-operand test sees each form and leaves ../.claude alone", function()
		t.expect(bareClaude("bad=$(grep -rn x .claude scripts || true)")).toBe(true)
		t.expect(bareClaude("[ ! -e .claude/skills/x ] || exit 1")).toBe(true)
		t.expect(bareClaude("grep x ../.claude/skills/y skills")).toBe(false)
	end)

	it("no rewritten line reads .claude from z-nile/", function()
		for _, s in SCANS do
			t.expect({ name = s.name, bare = bareClaude(line(s.file, s.needle)) })
				.toEqual({ name = s.name, bare = false })
		end
		t.expect(bareClaude(line(EXISTS.file, EXISTS.needle))).toBe(false)
	end)

	it("each grep is clean on a clean fixture and red for a phrase in each skills folder", function()
		for _, s in SCANS do
			setUp()
			local l = line(s.file, s.needle)
			t.expect({ name = s.name, clean = bad(l, `{FX}/z-nile`) }).toEqual({ name = s.name, clean = "" })
			for _, where in { "z-nile/skills/zz-a/SKILL.md", "pickman/skills/pickman-a/SKILL.md" } do
				put(where, `uses {s.phrase} here\n`)
				t.expect({ name = s.name, at = where, found = bad(l, `{FX}/z-nile`) ~= "" })
					.toEqual({ name = s.name, at = where, found = true })
				put(where, "nothing banned here\n")
			end
		end
	end)

	it(
		"the make-prompt test passes when it is absent and fails where a skill of that name could be",
		function()
			setUp()
			local l = line(EXISTS.file, EXISTS.needle)
			t.expect(absent(l, `{FX}/z-nile`)).toBe(true)
			for _, where in
				{
					"z-nile/skills/make-prompt/SKILL.md",
					"pickman/skills/make-prompt/SKILL.md",
					".claude/skills/make-prompt/SKILL.md",
				}
			do
				setUp()
				put(where, "x\n")
				t.expect({ at = where, absent = absent(l, `{FX}/z-nile`) })
					.toEqual({ at = where, absent = false })
			end
		end
	)

	it("a grep line stops, not passes, when a folder it reads is missing", function()
		for _, s in SCANS do
			setUp()
			fs.removeDir(`{FX}/z-nile/skills`)
			local r = runs(line(s.file, s.needle), `{FX}/z-nile`)
			t.expect({ name = s.name, ok = r.ok }).toEqual({ name = s.name, ok = false })
		end
	end)

	it(
		"in the real home every line finds nothing, reads every folder it names, and the finished checks stay green",
		function()
			for _, s in SCANS do
				local l = line(s.file, s.needle)
				t.expect({ name = s.name, found = bad(l, HOME) }).toEqual({ name = s.name, found = "" })
				local r = runs(l, HOME)
				t.expect({ name = s.name, ok = r.ok, stderr = r.stderr })
					.toEqual({ name = s.name, ok = true, stderr = "" })
			end
			local test = line(EXISTS.file, EXISTS.needle)
			t.expect(absent(test, HOME)).toBe(true)
			local dirs = testedDirs(test)
			t.expect(#dirs).toBe(3)
			for _, dir in dirs do
				t.expect({ dir = dir, there = fs.isDir(`{HOME}/{dir}`) }).toEqual({ dir = dir, there = true })
			end
		end
	)

	it("each whole criterion the four lines sit in passes in the real home, as ./zn check runs it", function()
		for _, c in CRITERIA do
			local r = process.exec("bash", { "-c", criterion(c.file, c.label) }, { cwd = HOME })
			t.expect({ criterion = c.file .. " " .. c.label, ok = r.ok, out = r.stdout .. r.stderr })
				.toEqual({ criterion = c.file .. " " .. c.label, ok = true, out = "" })
		end
	end)

	it("cleans up", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		t.expect(fs.isDir(FX)).toBe(false)
	end)
end)
