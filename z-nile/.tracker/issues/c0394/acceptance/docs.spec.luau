--!strict
-- c0394 AC13 to AC16: the skills, AGENTS.md, the README, the idea challenger's prompt and the usage text say what c0394's
-- Design says. zz-rules gains Findings (the four ends of a finding and the 50-line threshold, stated once) in place of
-- Emergent issues; no skill tells an agent to open a backlog issue for a finding or a lesson; every skill's Lessons
-- section has the Every lead bullet; zz-execute's report names the added issues; z-ticket and the idea challenger state
-- the z-nile ticket rule; the usage lists the new command line. Reads the real files; writes nothing.
local fs = require("@lune/fs")
local idea = require("@znile/engine/idea")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

-- specs run from their project's home (z-nile/); the repository's files are read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- every skill document of every project (never through the .claude/skills links), keyed by repository-relative path
local function skillDocs(): { [string]: string }
	local out: { [string]: string } = {}
	for _, folder in skills.folders(projects.load(TOP)) do
		local names = fs.readDir(`{TOP}/{folder.path}`)
		table.sort(names)
		for _, name in names do
			local doc = `{folder.path}/{name}/SKILL.md`
			if fs.isFile(`{TOP}/{doc}`) then
				out[doc] = fs.readFile(`{TOP}/{doc}`)
			end
		end
	end
	return out
end

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- the text of the `## <heading>` section, up to the next `## ` heading; raises when there is none
local function section(text: string, heading: string): string
	local start = string.find(text, `\n## {heading}\n`, 1, true)
	if not start then
		error(`no "## {heading}" section`, 2)
	end
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after - 1 else #text)
end

local function count(text: string, part: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(text, part, from, true)
		if not at then
			return n
		end
		n += 1
		from = at + #part
	end
end

local function missing(where: string, text: string, parts: { string })
	for _, part in parts do
		if not has(text, part) then
			error(`{where}: missing "{part}"`, 2)
		end
	end
end

-- Phrases that send an agent to the backlog with a finding or a lesson. Built by concatenation where they would
-- otherwise be read as real text by a scanner.
local BACKLOG_FOR_FINDING = {
	"Can be postponed",
	"Follow-ups filed",
	"deferred <id>",
	"deferred <" .. "id>",
	'follow "Emergent issues"',
	"into the backlog, mention it in the final report",
}
local BACKLOG_FOR_LESSON = {
	"lesson-<slug>",
	"captures it: `./zn new issue",
	"must capture a new lesson as an issue",
	"capture a new lesson as an issue",
	"**Any other lead**",
}

return t.spec("c0394 the skills say where a finding goes", function(it)
	it(
		"zz-rules has Findings with the four ends, the 50-line threshold and the in-front-or-last question, and no Emergent issues section",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			t.expect(has(rules, "\n## Emergent issues")).toBe(false)
			local findings = section(rules, "Findings")
			missing("zz-rules Findings", findings, {
				"not-worth-doing", -- the don't-worry lesson's tag
				"don't-worry lesson",
				"50 changed lines", -- the threshold
				"--raft", -- end 1: a must-fix emergent issue, as today
				"--wait", -- end 4, found while delivering a raft
				"--found",
				"--before", -- in front of the layer that found it; else last
				"--with", -- end 4, found while designing an issue
			})
			-- the threshold is stated once: here, and in no other skill
			t.expect(count(findings, "50 changed lines")).toBe(1)
			for path, text in skillDocs() do
				if path ~= "z-nile/skills/zz-rules/SKILL.md" then
					t.expect(has(text, "50 changed lines")).toBe(false)
					t.expect(string.find(text, "[Ss]mall means at most") == nil).toBe(true)
					t.expect(string.find(text, "at most %**%d+%** changed lines") == nil).toBe(true)
				end
			end
			-- the other skills point at it
			missing("zz-execute", read("z-nile/skills/zz-execute/SKILL.md"), { "Findings" })
			t.expect(has(read("z-nile/skills/zz-execute/SKILL.md"), 'follow "Emergent issues"')).toBe(false)
		end
	)

	it(
		"no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding or a lesson",
		function()
			local docs = skillDocs()
			docs["AGENTS.md"] = read("AGENTS.md")
			docs["z-nile/README.md"] = read("z-nile/README.md")
			local n = 0
			for path, text in docs do
				n += 1
				for _, phrase in BACKLOG_FOR_FINDING do
					if has(text, phrase) then
						error(`{path} still says "{phrase}"`, 0)
					end
				end
				for _, phrase in BACKLOG_FOR_LESSON do
					if has(text, phrase) then
						error(`{path} still says "{phrase}"`, 0)
					end
				end
			end
			t.expect(n >= 27).toBe(true) -- the 25 skills, AGENTS.md and the README
		end
	)

	it("every skill's Lessons section has the Every lead bullet and no lesson-<slug> capture", function()
		local n = 0
		for path, text in skillDocs() do
			n += 1
			local lessons = section(text, "Lessons")
			missing(path, lessons, {
				"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.",
				"- **A subagent** (",
				"- **Every lead** (",
				"lessons/<slug>.md",
				"`from:`",
				"lessons-<slug>",
				"No lead opens an issue for a lesson.",
			})
			for _, phrase in BACKLOG_FOR_LESSON do
				if has(lessons, phrase) then
					error(`{path} Lessons still says "{phrase}"`, 0)
				end
			end
			t.expect(has(lessons, "- **The lead of a prep or raft**")).toBe(false)
		end
		t.expect(n >= 25).toBe(true) -- z-nile's 13 skills and the 12 project skills
		local agents = read("AGENTS.md")
		missing("AGENTS.md", agents, { "writes it under the skill it improves" })
		t.expect(has(agents, "must capture a new lesson as an issue")).toBe(false)
	end)

	it("zz-execute has the Added comment line and the report line, and no Follow-ups filed", function()
		local execute = read("z-nile/skills/zz-execute/SKILL.md")
		local report = section(execute, "Final report format")
		missing("zz-execute report", report, {
			"Added issues waiting for approval: <id>: <title> (found <where>; <before <id> | last>; <n> guesses) | none",
		})
		-- the pull-request comment that tells the user (zz-execute prescribes it)
		missing("zz-execute", execute, {
			"Added <id> (<title>), found <where>, <before <issue> | last>: waits for approval, <n> guesses",
		})
		t.expect(has(execute, "Follow-ups filed")).toBe(false)
		-- the review answers it lists: dropped and added in place of deferred
		missing(
			"zz-execute answers",
			execute,
			{ "- F3: dropped <lesson id>: <why>", "- F3: added <id>: <why>" }
		)
		t.expect(has(execute, "deferred")).toBe(false)
		-- z-design's report gains the same line
		missing("z-design", read("z-nile/skills/z-design/SKILL.md"), { "Added issues waiting for approval" })
	end)

	it(
		"z-ticket states the z-nile ticket rule and the challenge prompt asks for it for z-nile only and not for a finding",
		function()
			local ticket = read("z-nile/skills/z-ticket/SKILL.md")
			missing("z-ticket", ticket, {
				"the user asked for it",
				"happened twice",
				"first one-off incident gets a lesson",
				"(zz-rules, Findings)",
			})
			-- the prompt takes the issue's project: the rule is asked of z-nile only
			local doc = "---\nid: c0001\n---\n\n# c0001\n\n## Problem\nA thing broke once.\n"
			local challenge = idea.challengePrompt :: any
			missing("idea.challengePrompt", challenge(doc, "z-nile"), {
				"not a ticket: a first incident is a lesson (zz-rules, Findings)",
			})
			t.expect(has(challenge(doc, "pickman"), "not a ticket: a first incident is a lesson")).toBe(false)
			local finding =
				"---\nid: c0002\nidea: finding\nfound: R0010 c0010 layer\n---\n\n# c0002\n\n## Problem\nA finding.\n"
			t.expect(has(challenge(finding, "z-nile"), "not a ticket: a first incident is a lesson"))
				.toBe(false)
		end
	)

	it("usage lists --wait, --before, --found, --with and reject", function()
		local main = read("z-nile/engine/main.luau")
		local usage = string.match(main, "local USAGE = %[%[\n(.-)%]%]") :: string
		t.expect(usage ~= nil).toBe(true)
		-- one command's lines: its own line and the continuation lines (indented deeper) below it
		local function entry(word: string): string
			local out: { string } = {}
			local on = false
			for line in string.gmatch(usage .. "\n", "([^\n]*)\n") do
				if
					string.sub(line, 1, 3) == "  " .. string.sub(word, 1, 1)
					and string.sub(line, 3, 2 + #word) == word
				then
					on = true
					table.insert(out, line)
				elseif on and string.match(line, "^%s%s%s%s") then
					table.insert(out, line)
				else
					on = false
				end
			end
			return table.concat(out, "\n")
		end
		local newIssue = entry("new issue")
		missing("usage new issue", newIssue, { "--wait", "--before", "--found", "--with" })
		local reject = entry("reject")
		missing("usage reject", reject, { "reject <id> --lesson" })
	end)
end)
