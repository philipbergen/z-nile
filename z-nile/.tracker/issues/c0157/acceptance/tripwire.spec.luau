--!strict
-- c0157: a ref another session commits under a fixture identity in the real repository trips every running gate's
-- tripwire like a spec's escape. The skills keep prototypes in scratch clones and fixture identities out of the real
-- repository, and the tripwire's message names each appeared ref's author and subject with that cause. The message is
-- read from the fence's own snapshot and changes (z-nile/tests/lib/fence.luau), run by a child Lune in a fixture
-- repository under .cache/c0157-tripwire.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local FX = `{here}/.cache/c0157-tripwire`
local R = "req" .. "uire" -- keeps literal require text out of this file (the require scanner)
local RULE = "Prototypes and experiments live in a scratch clone (`git clone` of the checkout into the scratchpad or "
	.. "`$TMPDIR`), never in a branch or worktree of the real repository, and nothing is ever committed in the real "
	.. "repository under a fixture identity (`@example.invalid`): every gate running on the machine reads such a ref "
	.. "as a spec's escape and fails (c0157)."

local function git(args: { string }): string
	local r = process.exec("git", args, { cwd = `{FX}/repo` })
	if not r.ok then
		error(`git {table.concat(args, " ")}: {r.stderr}`)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

return t.spec("c0157 another session's prototype refs", function(it)
	it("the tripwire names an appeared fixture ref's author and subject, and the likely cause", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		fs.writeDir(`{FX}/repo/.cache`)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", `{FX}/repo` }).ok).toBe(true)
		git({
			"-c",
			"user.name=base",
			"-c",
			"user.email=base@example.invalid",
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"base",
		})
		fs.writeDir(`{FX}/probe`)
		-- the probe: snapshot, a ref another session commits under a fixture identity, snapshot, the changes
		fs.writeFile(
			`{FX}/probe/probe.luau`,
			table.concat({
				`local fence = {R}("../../../tests/lib/fence")`,
				`local process = {R}("@lune/process")`,
				`local before = fence.snapshot("{FX}/repo/.cache")`,
				"local function g(a) assert(process.exec('git', a).ok, table.concat(a, ' ')) end",
				"local tree = process.exec('git', { 'rev-parse', 'HEAD^{tree}' }).stdout:gsub('%s+$', '')",
				"local c = process.exec('git', { '-c', 'user.name=proto', '-c', 'user.email=proto@example.invalid',",
				"\t'commit-tree', tree, '-m', 'proto f0126 round 8 (scratch)' }).stdout:gsub('%s+$', '')",
				"g({ 'update-ref', 'refs/heads/proto-base2', c })",
				`local after = fence.snapshot("{FX}/repo/.cache")`,
				"print(table.concat(fence.changes(before, after), '\\n'))",
				"",
			}, "\n")
		)
		local r = process.exec("lune", { "run", `{FX}/probe/probe.luau` }, { cwd = `{FX}/repo` })
		if not r.ok then
			print(r.stdout .. r.stderr)
		end
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		local function has(needle: string): boolean
			return string.find(out, needle, 1, true) ~= nil
		end
		t.expect(has("refs written by a fixture appeared")).toBe(true)
		t.expect(string.match(out, "refs/heads/proto%-base2 %x+ %(proto <proto@example%.invalid>, ") ~= nil)
			.toBe(true)
		t.expect(has(": proto f0126 round 8 (scratch))")).toBe(true)
		t.expect(has("prototypes belong in scratch clones")).toBe(true)
		fs.removeDir(FX)
	end)

	it("z-design, zz-execute and zz-test state the rule in the same words", function()
		for _, skill in { "z-design", "zz-execute", "zz-test" } do
			local text = fs.readFile(`{root}/z-nile/skills/{skill}/SKILL.md`)
			t.expect((string.find(text, RULE, 1, true)) ~= nil).toBe(true)
		end
		-- the mutation check no longer sends a prototype to a scratch worktree of the real repository
		local design = fs.readFile(`{root}/z-nile/skills/z-design/SKILL.md`)
		t.expect((string.find(design, "scratch worktree", 1, true))).toBe(nil)
	end)
end)
