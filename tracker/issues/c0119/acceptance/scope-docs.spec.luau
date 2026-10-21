--!strict
-- c0119: captured scope is frozen and only the user narrows it. make-issue, ticket-prep, review (both modes) and
-- execute-raft say so in the places c0119's Design names (AC1).
-- Reads the real files; writes nothing.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SKILLS = ".claude/skills"

local function read(path: string): string
	return fs.readFile(path)
end

-- the text of the `## <prefix>` section of a document, up to the next `## ` heading
local function section(text: string, prefix: string): string
	local start = string.find(text, "\n## " .. prefix, 1, true)
	if not start then
		error(`no "## {prefix}" section`, 2)
	end
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after - 1 else #text)
end

local function at(text: string, phrase: string): number
	local i = string.find(text, phrase, 1, true)
	if not i then
		error(`missing: {phrase}`, 2)
	end
	return i
end

-- the paragraph (up to the next blank line) that starts with `lead`
local function paragraph(text: string, lead: string): string
	local i = at(text, lead)
	local j = string.find(text, "\n\n", i, true)
	return string.sub(text, i, if j then j - 1 else #text)
end

return t.spec("c0119 scope rules in the skills", function(it)
	it("make-issue says the Problem's outcomes are the scope prep may not narrow", function()
		local doc = read(`{SKILLS}/make-issue/SKILL.md`)
		local line = string.match(doc, "\n%s*%- %*%*Problem%*%*:[^\n]*") :: string
		t.expect(line ~= nil).toBe(true)
		at(line, "never narrows, defers or drops an outcome without the user")
	end)

	it("ticket-prep opens with the scope rule, before step 1", function()
		local doc = read(`{SKILLS}/ticket-prep/SKILL.md`)
		local p = paragraph(doc, "**Scope is what was captured.**")
		t.expect(at(doc, "**Scope is what was captured.**") < at(doc, "\n## 1. Form the raft")).toBe(true)
		at(p, "on `origin/main` when prep starts")
		at(p, "never rewrites, narrows, defers or drops an outcome the Problem asks for")
		at(p, "Non-goals fence only what the Problem did not ask for")
		at(p, "AskUserQuestion")
		at(p, '`Scope decision (user, YYYY-MM-DD): "<their words>"`')
		at(p, "A reviewer's recommendation is not a decision")
		at(p, "split into sequenced rafts, never shrunk")
	end)

	it("ticket-prep forbids answering a finding by a cut, in the answering step", function()
		local s5 = section(read(`{SKILLS}/ticket-prep/SKILL.md`), "5.")
		local three, four = at(s5, "\n3. "), at(s5, "\n4. ")
		local rule = at(s5, "**Never answer a finding by cutting scope.**")
		t.expect(rule > three and rule < four).toBe(true)
		local line = string.sub(s5, rule, (string.find(s5, "\n", rule, true) :: number) - 1)
		at(line, "ask the user before you answer it")
		at(line, "`Scope decision` line")
	end)

	it("review never prescribes a cut, and design mode checks scope fidelity after Lessons", function()
		local doc = read(`{SKILLS}/review/SKILL.md`)
		local rule = paragraph(doc, "**Never prescribe a cut.**")
		t.expect(at(doc, "**Never prescribe a cut.**") < at(doc, "\n## Design mode")).toBe(true)
		at(rule, "never makes an outcome the issue's Problem asks for smaller, later or optional")
		at(rule, "`escalate to the user:`")
		local design = section(doc, "Design mode")
		local ten, eleven = at(design, "\n10. **Lessons**"), at(design, "\n11. **Scope fidelity**")
		t.expect(eleven > ten).toBe(true)
		local item = string.sub(design, eleven)
		at(item, "`git diff origin/main -- <doc>`")
		at(item, "`Scope decision (user, YYYY-MM-DD)`")
		at(item, "moved into Non-goals")
		at(item, "is **high**")
	end)

	it("code review treats a deviation that shrinks the Problem as high", function()
		local code = section(read(`{SKILLS}/review/SKILL.md`), "Code mode")
		local i = at(code, "\n4. **Design adherence**")
		local line = string.sub(code, i + 1, (string.find(code, "\n", i + 1, true) :: number) - 1)
		at(line, "drops or shrinks an outcome the issue's Problem asks for is **high**")
		at(line, "escalate")
	end)

	it("execute-raft stops when delivery would shrink an outcome", function()
		local stops = section(read(`{SKILLS}/execute-raft/SKILL.md`), "Stop conditions")
		at(stops, "- Delivering an issue would drop or shrink an outcome its Problem asks for")
		at(stops, "Only the user changes scope.")
	end)
end)
