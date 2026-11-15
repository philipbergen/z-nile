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
	{ "z-nile/skills/z-ticket/SKILL.md", "**game or product** behavior" },
	{ "z-nile/skills/z-ticket/SKILL.md", "Anything related to CI or tests is always a chore" },
	{ "z-nile/skills/z-ticket/SKILL.md", "tracker CLI bugs" },
	{ "z-nile/skills/z-ticket/SKILL.md", "a broken gate script, `setup.sh`, hook or workflow;" },
	{ "z-nile/README.md", "CI and test fixes are chores." },
	{ "z-nile/skills/zz-rules/SKILL.md", "includes every CI/test/tooling fix, even bugs" },
	{ "z-nile/skills/zz-test/SKILL.md", "test fixes are always chores" },
	{ "z-nile/skills/zz-test/SKILL.md", "since CI and test bugs are always chores" },
	{ "z-nile/skills/zz-stats/SKILL.md", "that includes every CI and test fix, even ones that are bugs" },
	{
		"z-nile/skills/z-design/checklists/chore.md",
		"CI, test and tooling fixes are chores even when they fix a bug",
	},
}

return t.spec("c0266 the docs let z-nile's root hold every type", function(it)
	it("no doc still says tooling, CI or test fixes are always chores", function()
		for _, row in OLD do
			absent(read(row[1]), row[2], row[1])
		end
	end)

	it(
		"z-ticket classifies a z-nile behaviour that is wrong as a defect, and a wrong spec as a chore",
		function()
			local s = read("z-nile/skills/z-ticket/SKILL.md")
			local w = "z-ticket"
			at(s, "\n1. **Classify the work**", w)
			at(
				s,
				"   - **defect** (`d`): **product** behavior that's wrong compared with an issue that's already done or with an obvious expectation: a game's, the portal's, the arcade library's, or z-nile's own (its commands, the gate, the guards, the runner, the selector). This is rework, and it's counted against the 20% target, so classify honestly.",
				w
			)
			at(
				s,
				"   - **chore** (`c`): refactors, infrastructure or upkeep, with no change in behavior. **A spec that is wrong while the code is right is always a chore, even when it's a bug**, for example:",
				w
			)
			at(s, "     - a flaky or wrong spec, including a promoted acceptance spec;", w)
			at(s, "     - a test-selector graph miss (a hole in the watch map);", w)
			at(s, "     - a game's own spec or test helper that is broken.", w)
			at(s, "     These never count as rework.", w)
			at(
				s,
				"   - **Every root holds all three types** (c0266): z-nile's root (`z-nile/.tracker`) holds its chores, features and defects as a game's root holds the game's. A z-nile command, gate script, guard, hook or workflow that does the wrong thing is a z-nile defect (`--project z-nile`).",
				w
			)
		end
	)

	it("the README, zz-rules, zz-test, zz-stats and the chore checklist say the same", function()
		at(
			read("z-nile/README.md"),
			"One type per raft: feature (`f`), defect (`d`) or chore (`c`). Every project root holds all three, z-nile's included (c0266): a wrong spec is a chore, and a z-nile command, gate or guard that does the wrong thing is a defect (z-ticket). A lone issue still gets a raft.",
			"README"
		)
		at(
			read("z-nile/skills/zz-rules/SKILL.md"),
			"| chore issue | `c` + 4 digits | `c0030` (includes every fix of a wrong spec, even a bug; a z-nile command that does the wrong thing is a defect; see z-ticket) |",
			"zz-rules"
		)
		local zt = read("z-nile/skills/zz-test/SKILL.md")
		at(zt, "Never edit these; if one is wrong, file a chore (a wrong spec is always a chore)", "zz-test")
		at(
			zt,
			"`./zn watch-net` fills it; file the defect it captures for the failing spec, which stays a defect: z-nile's root holds defects (c0266).",
			"zz-test"
		)
		at(
			read("z-nile/skills/zz-stats/SKILL.md"),
			"Chores are excluded, and that includes every fix of a wrong spec, even one that is a bug. Every root's features and defects count, z-nile's included (c0266). The target is **under 20%** on all three.",
			"zz-stats"
		)
		at(
			read("z-nile/skills/z-design/checklists/chore.md"),
			"A fix of a wrong spec is a chore even when it fixes a bug; a z-nile command, gate or guard that does the wrong thing is a defect (z-ticket, Classify the work).",
			"chore checklist"
		)
	end)
end)
