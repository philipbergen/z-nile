--!strict
-- c0293 AC1 and AC2: the root AGENTS.md says how the pipeline's skills are engaged, then the shared rules, and
-- nothing else. c0293 writes four paragraphs of its own (TITLE, INTRO, TABLE, MAP, pinned here word for word) and
-- carries the rest from the base: the **Non-negotiable:** paragraph and every shared rule (KEPT), byte for byte.
-- The carry check (AC2) reads the merge base and runs only where ZN_C0293_CARRY is set (c0293's check line and
-- `done`): once c0293 has landed, a later item may edit a shared rule, and the gate must not pin today's words.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local TITLE = "# Engaging the pipeline"
local INTRO = "Work in this repository moves through z-nile's pipeline, one skill per stage: capture, design, raft, "
	.. "ready and run. This file says how each stage is engaged, then the rules every session follows."
local TABLE = table.concat({
	"| Skill | Engage it | Read when |",
	"|---|---|---|",
	"| `z-nile/skills/z-ticket/SKILL.md` | `/z-ticket`, when the user describes work, a bug or a chore | capturing a new feature, defect or chore |",
	"| `z-nile/skills/z-design/SKILL.md` | `/z-design <id>`, on a captured issue | designing one issue to prepared (includes the design review) |",
	"| `z-nile/skills/z-raft/SKILL.md` | `/z-raft`, or `/z-raft <ids>` to group as asked | grouping prepared issues into rafts, recombining backlog rafts |",
	"| `z-nile/skills/z-ready/SKILL.md` | `/z-ready <R-id>`, from the main checkout | readying a raft: claim, move to active/, write its prompt |",
	"| `z-nile/skills/z-run/SKILL.md` | `/z-run <R-id>`, in a session started in the main checkout | launching a readied raft from the main checkout (`/z-run R0010`) |",
	"| `z-nile/skills/z-stop/SKILL.md` | `/z-stop <R-id>`, from the main checkout | undoing z-ready or aborting a raft |",
}, "\n")
-- the map paragraph ends with every registered project's folder but z-nile's, in the registry's order, so a project
-- registered later is named here by its own issue (c0184's rule: a promoted check over projects runs over the registry)
local MAP_HEAD = "The `z-` skills are the pipeline, in order; the `zz-` skills are called from inside a step, and each "
	.. "stage's skill names the ones it reads. `z-nile/README.md` is the map: the flow, the five parts and every "
	.. "skill. A project's own skills and decisions are in its folder's `AGENTS.md`: "
local function mapFor(homes: { string }): string
	local names: { string } = {}
	for _, h in homes do
		table.insert(names, `\`{h}/\``)
	end
	local last = table.remove(names)
	local list = if #names == 0 then last else `{table.concat(names, ", ")} and {last}`
	return `{MAP_HEAD}{list}.`
end
local function registryHomes(): { string }
	local out: { string } = {}
	for _, p in projects.load(root).projects do
		if p.name ~= "z-nile" then
			table.insert(out, p.home)
		end
	end
	return out
end
-- c0293's day: the six homes, for the cases that build their own texts
local MAP = mapFor({ "pickman", "arcade", "portal", "snake", "invaders", "asteroids" })
local NONNEG = "**Non-negotiable:**"
-- the shared rules the user kept in the root (c0293's Problem, both decisions of 2026-11-10); the first three are
-- required, and c0194's lands before c0293 (depends_on)
local KEPT = {
	"**Subagents:**",
	"**Processes:**",
	"**No check may ever change the real repository.**",
	"**Temporary trees live in `.cache/.tmp/`",
}
local REQUIRED = 3
-- the base paragraphs c0293 drops or moves, by how each starts (c0293's Design, Dropped and moved)
local DROPS = {
	"# pickman",
	"A first-person Pac-Man clone for Roblox",
	"The skills are z-nile's",
	"| Skill | Read when |",
	"The `z-` skills are the pipeline, in order; the `zz-` skills are called from inside a step. The `zz-` and `z-` prefixes are z-nile's",
	"Each skill keeps what reviews and mistakes taught it",
}

local function paragraphs(text: string): { string }
	local out: { string } = {}
	local cur: { string } = {}
	for line in string.gmatch(string.gsub(text, "\r\n", "\n") .. "\n", "([^\n]*)\n") do
		if line == "" then
			if #cur > 0 then
				table.insert(out, table.concat(cur, "\n"))
				cur = {}
			end
		else
			table.insert(cur, line)
		end
	end
	if #cur > 0 then
		table.insert(out, table.concat(cur, "\n"))
	end
	return out
end

local function starts(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function keptLead(p: string): string?
	for _, lead in KEPT do
		if starts(p, lead) then
			return lead
		end
	end
	return nil
end

local function head(p: string): string
	return (string.gsub(string.sub(p, 1, 80), "\n", " "))
end

-- the shape of the new file: TITLE, INTRO, the Non-negotiable paragraph, TABLE, MAP, then shared rules only
local function shape(new: string, map: string): { string }
	local problems: { string } = {}
	local ps = paragraphs(new)
	local want = { TITLE, INTRO, NONNEG, TABLE, map }
	for i, w in want do
		local p = ps[i]
		if p == nil then
			table.insert(problems, `paragraph {i} is missing: {head(w)}`)
		elseif w == NONNEG then
			if not starts(p, NONNEG) then
				table.insert(problems, `paragraph {i} is not the {NONNEG} paragraph: {head(p)}`)
			end
		elseif p ~= w then
			table.insert(problems, `paragraph {i} is not c0293's text: {head(p)}`)
		end
	end
	local seen: { [string]: boolean } = {}
	for i = #want + 1, #ps do
		local lead = keptLead(ps[i])
		if lead == nil then
			table.insert(
				problems,
				`paragraph {i} is neither the pipeline part nor a shared rule: {head(ps[i])}`
			)
		elseif seen[lead] then
			table.insert(problems, `the shared rule {lead} appears twice`)
		else
			seen[lead] = true
		end
	end
	for k = 1, REQUIRED do
		if not seen[KEPT[k]] then
			table.insert(problems, `the shared rule {KEPT[k]} is missing`)
		end
	end
	return problems
end

-- what the base holds goes somewhere: carried byte for byte (in the base's order), c0293's own text, or a named drop;
-- anything else is a paragraph nobody has placed, which stops the run (zz-execute stop conditions)
local function carry(base: string, new: string, map: string): { string }
	local problems: { string } = {}
	local np = paragraphs(new)
	local mine: { [string]: boolean } = { [TITLE] = true, [INTRO] = true, [TABLE] = true, [map] = true }
	local carried: { string } = {}
	local nonneg = 0
	for _, p in paragraphs(base) do
		if starts(p, NONNEG) or keptLead(p) ~= nil then
			if starts(p, NONNEG) then
				nonneg += 1
			end
			if table.find(np, p) == nil then
				table.insert(problems, `not carried byte for byte: {head(p)}`)
			end
			table.insert(carried, p)
		elseif not mine[p] then
			local dropped = false
			for _, d in DROPS do
				if starts(p, d) then
					dropped = true
					break
				end
			end
			if not dropped then
				table.insert(problems, `a base paragraph c0293 neither keeps nor drops (escalate): {head(p)}`)
			end
		end
	end
	if nonneg ~= 1 then
		table.insert(problems, `the base has {nonneg} {NONNEG} paragraphs, not one`)
	end
	if #carried < 1 + REQUIRED then
		table.insert(problems, `the base has {#carried} paragraphs to carry, fewer than {1 + REQUIRED}`)
	end
	local last = 0
	for _, p in carried do
		local at = table.find(np, p)
		if at ~= nil then
			if at < last then
				table.insert(problems, `out of the base's order: {head(p)}`)
			end
			last = at
		end
	end
	return problems
end

local function git(args: { string }): string
	local r = process.exec("git", args, { cwd = root })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}`)
	end
	return r.stdout
end

local function none(problems: { string })
	if #problems > 0 then
		error(table.concat(problems, "\n"))
	end
end

local function some(problems: { string }, needle: string)
	for _, p in problems do
		if string.find(p, needle, 1, true) ~= nil then
			return
		end
	end
	error(`no problem names "{needle}": {table.concat(problems, " | ")}`)
end

local NONNEG_P = "**Non-negotiable:** no code without a tracker issue. Start execution with `/z-run <R-id>`."
local SUB = "**Subagents:** don't use `fork` subagents."
local PROC = "**Processes:** Run every probe through `./zn run`."
local NOCHECK = "**No check may ever change the real repository.** Specs change only fixtures."
local GOOD = table.concat({ TITLE, INTRO, NONNEG_P, TABLE, MAP, SUB, PROC, NOCHECK }, "\n\n") .. "\n"
local OLD = table.concat({
	"# pickman",
	"A first-person Pac-Man clone for Roblox, built with Rojo.",
	NONNEG_P,
	SUB,
	PROC,
	NOCHECK,
	"The skills are z-nile's (`z-nile/skills/`).",
	"| Skill | Read when |\n|---|---|\n| `z-nile/skills/zz-test/SKILL.md` | writing specs |",
	"The `z-` skills are the pipeline, in order; the `zz-` skills are called from inside a step. The `zz-` and `z-` prefixes are z-nile's: a project's skills are named `<project>-…`.",
	"Each skill keeps what reviews and mistakes taught it in its `lessons/` folder.",
}, "\n\n") .. "\n"

return t.spec("c0293 root AGENTS.md", function(it)
	it("AC1: the root AGENTS.md is the pipeline part, then the shared rules, and nothing else", function()
		none(shape(fs.readFile(`{root}/AGENTS.md`), mapFor(registryHomes())))
	end)

	it(
		"AC1: the map names every registered project's folder but z-nile's, in the registry's order",
		function()
			local homes = registryHomes()
			if #homes < 6 then
				error(
					`the registry lists {#homes} projects besides z-nile, fewer than the six of c0293's day`
				)
			end
			t.expect(mapFor({ "a" })).toBe(`{MAP_HEAD}\`a/\`.`)
			t.expect(mapFor({ "a", "b", "c" })).toBe(`{MAP_HEAD}\`a/\`, \`b/\` and \`c/\`.`)
			some(
				shape(
					GOOD,
					mapFor({ "pickman", "arcade", "portal", "snake", "invaders", "asteroids", "pong" })
				),
				"paragraph 5"
			)
		end
	)

	it("AC1: the shape refuses a leftover row, a missing or doubled rule, and the old title", function()
		none(shape(GOOD, MAP))
		some(
			shape(GOOD .. "\n| `z-nile/skills/zz-test/SKILL.md` | writing specs |\n", MAP),
			"neither the pipeline part"
		)
		some(
			shape(table.concat({ TITLE, INTRO, NONNEG_P, TABLE, MAP, SUB, NOCHECK }, "\n\n"), MAP),
			"**Processes:** is missing"
		)
		some(shape(GOOD .. "\n" .. PROC .. "\n", MAP), "appears twice")
		some(
			shape((string.gsub(GOOD, "^# Engaging the pipeline", "# pickman")), MAP),
			"paragraph 1 is not c0293's text"
		)
		some(
			shape(table.concat({ TITLE, INTRO, TABLE, MAP, NONNEG_P, SUB, PROC, NOCHECK }, "\n\n"), MAP),
			"is not the"
		)
	end)

	it(
		"AC2: the carry keeps every shared rule byte for byte, in order, and stops on an unplaced paragraph",
		function()
			none(carry(OLD, GOOD, MAP))
			none(carry(GOOD, GOOD, MAP)) -- after c0293 lands, the base is the new file
			some(
				carry(OLD, (string.gsub(GOOD, "through `./zn run`", "through ./zn run")), MAP),
				"not carried byte for byte"
			)
			some(carry(OLD .. "\n**Foo:** a rule nobody placed.\n", GOOD, MAP), "neither keeps nor drops")
			some(
				carry(
					OLD,
					table.concat({ TITLE, INTRO, NONNEG_P, TABLE, MAP, PROC, SUB, NOCHECK }, "\n\n"),
					MAP
				),
				"out of the base's order"
			)
			some(carry("# pickman\n", GOOD, MAP), "not one")
			local temp =
				"**Temporary trees live in `.cache/.tmp/`, never in the system temp folder.** Use `./zn tmp new`."
			some(carry(OLD .. "\n" .. temp .. "\n", GOOD, MAP), "not carried byte for byte")
		end
	)

	it(
		"AC2: the root carries the merge base's Non-negotiable paragraph and shared rules (check time only)",
		function()
			if process.env.ZN_C0293_CARRY == nil then
				return -- the gate's copy: AC2's check line sets ZN_C0293_CARRY, so the carry runs at check and `done`
			end
			local tip = string.gsub(git({ "rev-parse", "HEAD" }), "%s+$", "")
			local b = process.exec(
				"git",
				{ "merge-base", "HEAD", "refs/remotes/origin/main" },
				{ cwd = root }
			)
			local base = if b.ok then (string.gsub(b.stdout, "%s+$", "")) else tip
			none(
				carry(
					git({ "show", `{base}:AGENTS.md` }),
					fs.readFile(`{root}/AGENTS.md`),
					mapFor(registryHomes())
				)
			)
		end
	)
end)
