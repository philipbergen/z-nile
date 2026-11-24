--!strict
-- c0266 AC2: every place that restated "CI, test and tooling fixes are chores" in z-nile's skills and README now says
-- what the user ruled (Scope decision, 2026-11-12): every project root holds chores, features and defects, z-nile's
-- included; a wrong spec is a chore, and a z-nile command, gate or guard that does the wrong thing is a defect; z-nile's
-- defects count in the rework rate like every root's (lesson z-design/restated-rules-move-together). Reads the real
-- tree, plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the spec runs from z-nile/, its home: every path it reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end

-- every restatement of the chores-only rule c0266 replaces, and the file it was in
local OLD: { { string } } = {
	-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
	{ "z-nile/skills/z-idea/SKILL.md", "**game or product** behavior" },
	{ "z-nile/skills/z-idea/SKILL.md", "Anything related to CI or tests is always a chore" },
	{ "z-nile/skills/z-idea/SKILL.md", "tracker CLI bugs" },
	{ "z-nile/skills/z-idea/SKILL.md", "a broken gate script, `setup.sh`, hook or workflow;" },
	{ "z-nile/README.md", "CI and test fixes are chores." },
	{ "z-nile/skills/zz-rules/SKILL.md", "includes every CI/test/tooling fix, even bugs" },
	{ "z-nile/skills/zz-test/SKILL.md", "test fixes are always chores" },
	{ "z-nile/skills/zz-test/SKILL.md", "since CI and test bugs are always chores" },
	{ "z-nile/skills/zz-stats/SKILL.md", "that includes every CI and test fix, even ones that are bugs" },
	{
		"z-nile/skills/z-design/checklists/chore.md",
		"CI, test and tooling fixes are chores even when they fix a bug",
	},
	-- design review 001 F1: a watch miss is a chore (user decision, 2026-11-04), and a slow gate is upkeep
	{ "z-nile/skills/zz-test/SKILL.md", "which stays a defect" },
	{ "z-nile/skills/zz-test/SKILL.md", "is a gate defect" },
}

-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
-- z-idea's step 1 (Classify the work), from its heading to step 2's
local function classify(s: string): string
	local from = string.find(s, "\n1. **Classify the work**", 1, true)
	local to = from and string.find(s, "\n2. **", from, true)
	if not from or not to then
		-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
		error("z-idea has no step 1 (Classify the work) followed by step 2", 2)
	end
	return string.sub(s, from, to)
end

-- design review 001 F2: the chore's examples, exactly
local EXAMPLES = table.concat({
	"     - a flaky or wrong spec, including a promoted acceptance spec;",
	"     - a test-selector graph miss (a hole in the watch map);",
	"     - a game's own spec or test helper that is broken.",
}, "\n")
-- the forms of the z-nile defects the chore's examples named before c0266, in any wording
local STEMS = { "gate script", "setup.sh", "hook", "workflow", "CLI bug", "tracker CLI" }
-- a line that names a watch miss, and what such a line may never say (design review 001 F1)
local MISS =
	{ "watch miss", "watch-miss", "graph miss", "graph-miss", "hole in the map", "hole in the watch map" }
local MISS_DEFECT =
	{ "stays a defect", "file the defect", "is a defect", "watch-miss defect", "graph-miss defect" }
local function namesMiss(line: string): boolean
	local lower = string.lower(line)
	for _, needle in MISS do
		if string.find(lower, needle, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0266 the docs let z-nile's root hold every type", function(it)
	it("no doc still says tooling, CI or test fixes are always chores", function()
		for _, row in OLD do
			absent(read(row[1]), row[2], row[1])
		end
	end)

	it(
		-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
		"z-idea classifies a z-nile behaviour that is wrong as a defect, and a wrong spec as a chore",
		function()
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			local s = read("z-nile/skills/z-idea/SKILL.md")
			local w = "z-idea"
			local step = classify(s)
			at(
				step,
				"   - **defect** (`d`): **product** behavior that's wrong compared with an issue that's already done or with an obvious expectation: a game's, the portal's, the arcade library's, or z-nile's own (its commands, the gate, the guards, the runner, the selector's code; a hole in the watch map is a chore). This is rework, and it's counted against the 20% target, so classify honestly.",
				w
			)
			at(
				step,
				"   - **chore** (`c`): refactors, infrastructure or upkeep, with no change in behavior. **A spec that is wrong while the code is right is always a chore, even when it's a bug**, for example:",
				w
			)
			local first = string.find(step, "for example:\n", 1, true)
			local last = string.find(step, "\n     These never count as rework.", 1, true)
			if not first or not last then
				-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
				error("z-idea's chore has no example list ending in 'These never count as rework.'")
			end
			local examples = string.sub(step, first + #"for example:\n", last - 1)
			t.expect(examples).toBe(EXAMPLES)
			for _, stem in STEMS do
				-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
				absent(string.lower(examples), string.lower(stem), "z-idea's chore examples")
			end
			at(
				step,
				"   - **Every root holds all three types** (c0266): z-nile's root (`z-nile/.tracker`) holds its chores, features and defects as a game's root holds the game's. A z-nile command, gate script, guard, hook or workflow that does the wrong thing is a z-nile defect (`--project z-nile`).",
				w
			)
		end
	)

	it("the README, zz-rules, zz-test, zz-stats and the chore checklist say the same", function()
		at(
			read("z-nile/README.md"),
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			"One type per raft: feature (`f`), defect (`d`) or chore (`c`). Every project root holds all three, z-nile's included (c0266): a wrong spec is a chore, and a z-nile command, gate or guard that does the wrong thing is a defect (z-idea). A lone issue still gets a raft.",
			"README"
		)
		at(
			read("z-nile/skills/zz-rules/SKILL.md"),
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			"| chore issue | `c` + 4 digits | `c0030` (includes every fix of a wrong spec, even a bug; a z-nile command that does the wrong thing is a defect; see z-idea) |",
			"zz-rules"
		)
		local zt = read("z-nile/skills/zz-test/SKILL.md")
		at(zt, "Never edit these; if one is wrong, file a chore (a wrong spec is always a chore)", "zz-test")
		at(
			zt,
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			"That's a hole in the map, a chore (z-idea). `./zn watch-net` fills it and captures it, though it still types the capture a defect (d0353).",
			"zz-test"
		)
		at(
			zt,
			"is slow-gate upkeep, a chore while the gate's results are right (c0266): **optimise** it now if it is in your Touched modules, otherwise file one (`./zn new issue c gate-slow-<what> --project z-nile`).",
			"zz-test"
		)
		at(
			read("z-nile/skills/zz-stats/SKILL.md"),
			"Chores are excluded, and that includes every fix of a wrong spec, even one that is a bug. Every root's features and defects count, z-nile's included (c0266). The target is **under 20%** on all three.",
			"zz-stats"
		)
		at(
			read("z-nile/skills/z-design/checklists/chore.md"),
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			"A fix of a wrong spec is a chore even when it fixes a bug; a z-nile command, gate or guard that does the wrong thing is a defect (z-idea, Classify the work).",
			"chore checklist"
		)
	end)

	-- design review 001 F1: one type for a watch miss in every text that tells someone to file one
	-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
	it("every line of z-idea, zz-execute and zz-test that names a watch miss calls it a chore", function()
		local seen = 0
		for _, path in
			{
				-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
				"z-nile/skills/z-idea/SKILL.md",
				"z-nile/skills/zz-execute/SKILL.md",
				"z-nile/skills/zz-test/SKILL.md",
			}
		do
			local s = read(path)
			-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
			-- z-idea's chore examples sit under the chore bullet, which says chore for them
			local examples = if string.find(path, "z-idea", 1, true) then EXAMPLES else nil
			for line in string.gmatch(s, "[^\n]+") do
				if namesMiss(line) then
					seen += 1
					local lower = string.lower(line)
					if not (examples and string.find(examples, line, 1, true)) then
						at(lower, "chore", `{path}: {line}`)
					end
					for _, bad in MISS_DEFECT do
						absent(lower, bad, `{path}: {line}`)
					end
				end
			end
		end
		-- c0436 override: z-idea and z-code are the renamed z-ticket and z-run
		-- z-idea's example and its defect bullet, zz-execute's red merge gate, zz-test's table row and its Watch miss
		t.expect(seen >= 5).toBe(true)
	end)
end)
