--!strict
-- c0293 AC6 (the narrowing half): an Override is the smallest change, never a gutted spec. Check time only (it reads
-- the merge base, so it runs where ZN_C0293_CARRY is set: c0293's AC6 line and `done`; the gate's copy returns).
--  - the five Overrides known at prep are the base with exactly the listed substitutions, byte for byte;
--  - c0172's narrowed.spec changes by one digest, the one of c0120/docs.spec.luau as it is on HEAD (the algorithm is
--    its own: SHA-256 of the text with item ids masked and CRLF made LF);
--  - c0136's, c0112's and c0181's promoted docs specs (their text does not exist at prep) lose lines only: no added
--    line but a comment, and no removed line reads a skill unless it also names AGENTS (the code reviewer reads the
--    rest: JC2).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- each hunk is a changed span with one line of context each side (from the prototype: c0293.md, Overrides)
local SUBS: { { path: string, hunks: { { old: string, new: string } } } } = {
	{
		path = "z-nile/tests/acceptance/c0111/skill-docs.spec.luau",
		hunks = {
			{
				old = [==[			at(read(`{TOP}/z-nile/skills/zz-stats/SKILL.md`), "./zn lessons")
			-- c0120 override: the spec runs from its home: the checkout's files are read from the top
			local agents = read(`{TOP}/AGENTS.md`)
			at(agents, "lessons/")
			at(agents, "./zn lessons")
			at(agents, "capture a new lesson as an issue")
			t.expect(string.find(agents, "records new ones when it finishes", 1, true) == nil).toBe(true)
			local prompt = read(`{TOP}/z-nile/templates/prompt.md`) -- c0120 override: read from the checkout's top]==],
				new = [==[			at(read(`{TOP}/z-nile/skills/zz-stats/SKILL.md`), "./zn lessons")
			-- c0293 override: the root AGENTS.md no longer holds the lesson rules (every skill states its own)
			local prompt = read(`{TOP}/z-nile/templates/prompt.md`) -- c0120 override: read from the checkout's top]==],
			},
		},
	},
	{
		path = "z-nile/tests/acceptance/c0115/docs.spec.luau",
		hunks = {
			{
				old = [==[			local agents = read("AGENTS.md")
			for _, n in ALL do
				at(agents, `| \`{Z}/{n}/SKILL.md\` |`, "AGENTS.md")
			end
			at(agents, "| `pickman/skills/pickman-arch/SKILL.md` |", "AGENTS.md")
			at(agents, "| `pickman/skills/pickman-test/SKILL.md` |", "AGENTS.md")
			at(agents, "Start execution with `/z-run <R-id>`", "AGENTS.md")]==],
				new = [==[			local agents = read("AGENTS.md")
			-- c0293 override: the root lists the pipeline (z-) skills; the zz- skills are named by the stages that call
			-- them, and pickman's rows are in pickman/AGENTS.md
			for _, n in ALL do
				if string.sub(n, 1, 3) ~= "zz-" then
					at(agents, `| \`{Z}/{n}/SKILL.md\` |`, "AGENTS.md")
				end
			end
			local pickman = read("pickman/AGENTS.md")
			at(pickman, "| `pickman/skills/pickman-arch/SKILL.md` |", "pickman/AGENTS.md")
			at(pickman, "| `pickman/skills/pickman-test/SKILL.md` |", "pickman/AGENTS.md")
			at(agents, "Start execution with `/z-run <R-id>`", "AGENTS.md")]==],
			},
		},
	},
	{
		path = "z-nile/tests/acceptance/c0120/docs.spec.luau",
		hunks = {
			{
				old = [==[		at(read(`z-nile/skills/z-design/SKILL.md`), "`pickman/.tracker/game-design.md`", "ticket-prep skill")
		at(read("AGENTS.md"), "The game is the `pickman` project, in `pickman/`", "AGENTS.md")
		at(read("AGENTS.md"), "designing or writing anything in `pickman/src/`", "AGENTS.md")
		at(read("AGENTS.md"), "runs one suite per checkout and project home at a time", "AGENTS.md")]==],
				new = [==[		at(read(`z-nile/skills/z-design/SKILL.md`), "`pickman/.tracker/game-design.md`", "ticket-prep skill")
		-- c0293 override: pickman's parts moved to pickman/AGENTS.md
		at(read("pickman/AGENTS.md"), "The game is the `pickman` project, in `pickman/`", "pickman/AGENTS.md")
		at(read("pickman/AGENTS.md"), "designing or writing anything in `pickman/src/`", "pickman/AGENTS.md")
		at(read("AGENTS.md"), "runs one suite per checkout and project home at a time", "AGENTS.md")]==],
			},
		},
	},
	{
		path = "z-nile/tests/acceptance/c0183/docs.spec.luau",
		hunks = {
			{
				old = [==[			fs.readFile(`{TOP}/AGENTS.md`),
			"The game is the `pickman` project, in `pickman/`",
			function(n)]==],
				new = [==[			fs.readFile(`{TOP}/AGENTS.md`),
			-- c0293 override: the root names every project's folder in its pointer to their AGENTS.md files
			"in its folder's `AGENTS.md`: `pickman/`",
			function(n)]==],
			},
		},
	},
	{
		path = "z-nile/tests/acceptance/c0184/docs.spec.luau",
		hunks = {
			{
				old = [==[		function()
			local agents, readme = read("AGENTS.md"), read("z-nile/README.md")
			at(agents, "Every project with code has the same home as `pickman/` (c0184)", "AGENTS.md")
			at(
				agents,
				"which the gate checks for each registered project (z-nile/README.md, A project's home).",
				"AGENTS.md"
			)
			at(readme, "## A project's home", "README")]==],
				new = [==[		function()
			-- c0293 override: the root AGENTS.md no longer restates the home (the README does); each project's own
			-- AGENTS.md names its skills
			local readme = read("z-nile/README.md")
			at(readme, "## A project's home", "README")]==],
			},
			{
				old = [==[			for _, p in others() do
				t.expect(line(agents, { "-arch/SKILL.md", `\`{p.name}\`` })).toBe(true)
				t.expect(line(readme, { `{p.name}-arch`, `{p.name}-test` })).toBe(true)
			end
			t.expect(line(agents, { "pickman-arch/SKILL.md" })).toBe(true)
		end]==],
				new = [==[			for _, p in others() do
				t.expect(line(read(`{p.name}/AGENTS.md`), { "-arch/SKILL.md", `\`{p.name}/` })).toBe(true)
				t.expect(line(readme, { `{p.name}-arch`, `{p.name}-test` })).toBe(true)
			end
			t.expect(line(read("pickman/AGENTS.md"), { "pickman-arch/SKILL.md" })).toBe(true)
		end]==],
			},
		},
	},
}

local LATE = {
	"z-nile/tests/acceptance/c0112/docs.spec.luau",
	"z-nile/tests/acceptance/c0136/docs.spec.luau",
	"z-nile/tests/acceptance/c0181/docs.spec.luau",
}
local C0172 = "z-nile/tests/acceptance/c0172/narrowed.spec.luau"
local C0120 = "z-nile/tests/acceptance/c0120/docs.spec.luau"

local function count(text: string, needle: string): number
	local n, from = 0, 1
	while true do
		local a, b = string.find(text, needle, from, true)
		if not a then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end

-- the base text with every hunk replaced once; a hunk that is absent or ambiguous is a problem
local function apply(base: string, hunks: { { old: string, new: string } }): (string, { string })
	local problems: { string } = {}
	local text = base
	for i, h in hunks do
		local n = count(text, h.old)
		if n ~= 1 then
			table.insert(problems, `hunk {i} occurs {n} times in the base, not once`)
		else
			local a, b = string.find(text, h.old, 1, true)
			text = string.sub(text, 1, (a :: number) - 1) .. h.new .. string.sub(text, (b :: number) + 1)
		end
	end
	return text, problems
end

-- a rule for specs whose text is not known at prep: lines are removed, only comments are added, and a removed line
-- that reads a skill must name AGENTS (the root file) too
local function removalsOnly(diff: string): { string }
	local problems: { string } = {}
	for line in string.gmatch(diff, "([^\n]*)\n") do
		if string.sub(line, 1, 3) ~= "---" and string.sub(line, 1, 3) ~= "+++" then
			local sign, rest = string.sub(line, 1, 1), string.sub(line, 2)
			if
				sign == "+"
				and string.match(rest, "^%s*%-%-") == nil
				and string.match(rest, "^%s*$") == nil
			then
				table.insert(problems, `an added line that is not a comment: {rest}`)
			elseif
				sign == "-"
				and (string.find(rest, "SKILL.md", 1, true) ~= nil or string.find(rest, "skills/", 1, true) ~= nil)
				and string.find(string.lower(rest), "agents", 1, true) == nil
			then
				table.insert(problems, `a removed line reads a skill and not AGENTS.md: {rest}`)
			end
		end
	end
	return problems
end

local function normalized(text: string): string
	local out = string.gsub(text, "\r\n", "\n")
	out = string.gsub(out, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return out
end

local function git(args: { string }): string
	local r = process.exec("git", args, { cwd = root })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}`)
	end
	return r.stdout
end

local function baseOrFail(): string
	local b = process.exec("git", { "merge-base", "HEAD", "refs/remotes/origin/main" }, { cwd = root })
	if not b.ok then
		error("cannot find the merge base with origin/main: this case compares against it")
	end
	return (string.gsub(b.stdout, "%s+$", ""))
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

return t.spec("c0293 the Overrides are the smallest narrowing", function(it)
	it("AC6: the substitution helper finds each hunk once and refuses a missing or a repeated one", function()
		local text, p = apply("a\nb\nc\n", { { old = "b\n", new = "B\n" } })
		t.expect(text).toBe("a\nB\nc\n")
		none(p)
		some(select(2, apply("a\nb\n", { { old = "z", new = "y" } })), "0 times")
		some(select(2, apply("a\na\n", { { old = "a", new = "y" } })), "2 times")
	end)

	it("AC6: a removal-only rule refuses an added assertion and a removed skill read", function()
		none(removalsOnly('-\tat(agents, "x")\n+\t-- c0293 override: moved\n'))
		some(removalsOnly('+\tat(agents, "y")\n'), "added line")
		some(removalsOnly('-\tat(read("z-nile/skills/zz-rules/SKILL.md"), "x")\n'), "reads a skill")
		none(removalsOnly('-\tat(agents, "AGENTS.md", read("z-nile/skills/x/SKILL.md"))\n'))
	end)

	it(
		"AC6: the five Overrides known at prep are the base with only their substitutions (check time only)",
		function()
			if process.env.ZN_C0293_CARRY == nil then
				return
			end
			local base = baseOrFail()
			for _, s in SUBS do
				local want, problems = apply(git({ "show", `{base}:{s.path}` }), s.hunks)
				none(problems)
				if want ~= fs.readFile(`{root}/{s.path}`) then
					error(`{s.path} is not the base with exactly its substitutions`)
				end
			end
		end
	)

	it(
		"AC6: c0172's narrowed.spec changes by the one digest of c0120/docs.spec.luau (check time only)",
		function()
			if process.env.ZN_C0293_CARRY == nil then
				return
			end
			local base = baseOrFail()
			local was = normalized(git({ "show", `{base}:{C0120}` }))
			local oldDigest = serde.hash("sha256", was)
			local newDigest = serde.hash("sha256", normalized(fs.readFile(`{root}/{C0120}`)))
			local text = git({ "show", `{base}:{C0172}` })
			t.expect(count(text, oldDigest)).toBe(1)
			local a, b = string.find(text, oldDigest, 1, true)
			local want = string.sub(text, 1, (a :: number) - 1)
				.. newDigest
				.. string.sub(text, (b :: number) + 1)
			if want ~= fs.readFile(`{root}/{C0172}`) then
				error(
					"c0172's narrowed.spec is not the base with the digest of c0120/docs.spec.luau replaced and nothing else"
				)
			end
		end
	)

	it(
		"AC6: c0136's, c0112's and c0181's docs specs only lose their reads of the root AGENTS.md (check time only)",
		function()
			if process.env.ZN_C0293_CARRY == nil then
				return
			end
			local base = baseOrFail()
			for _, path in LATE do
				none(removalsOnly(git({ "diff", "-U0", base, "HEAD", "--", path })))
			end
		end
	)
end)
