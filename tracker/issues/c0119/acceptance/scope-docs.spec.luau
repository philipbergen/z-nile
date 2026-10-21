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
		at(line, "every idea the user gives under Solution")
		-- the capture lookup relies on make-issue's commit subject
		at(doc, 'git commit -m "tracker: new <id> <title>"')
	end)

	it("ticket-prep opens with the scope rule, before step 1", function()
		local doc = read(`{SKILLS}/ticket-prep/SKILL.md`)
		local p = paragraph(doc, "**Scope is what was captured.**")
		t.expect(at(doc, "**Scope is what was captured.**") < at(doc, "\n## 1. Form the raft")).toBe(true)
		at(p, "its title, its Problem and the ideas under its Solution as they stood at capture")
		at(p, "`scripts/tracker.sh capture <id>` prints that version")
		at(
			p,
			"whose subject is `tracker: new` followed by a list of ids that includes the item's id at the time"
		)
		at(p, "marked `(no capture commit: first add)`, across folder moves and every compaction")
		at(p, "it keeps the captured Solution bullets as they are and adds after them")
		at(p, "`Decided with the user (YYYY-MM-DD)`")
		at(p, "never rewrites, narrows, defers or drops a captured outcome")
		at(p, "Non-goals fence only what the capture did not ask for")
		at(p, "AskUserQuestion in Claude Code; otherwise stop and report the options and what each costs")
		at(p, '`Scope decision (user, YYYY-MM-DD): "<their words>"`')
		at(p, "A reviewer's recommendation is not a decision")
		at(p, "split into sequenced rafts, never shrunk")
		at(p, "Splitting an issue moves outcomes into new issues captured through make-issue")
		at(p, "the original Problem gains a `Scope decision` line naming the new ids")
	end)

	it("ticket-prep forbids answering a finding by a cut, in the answering step", function()
		local s5 = section(read(`{SKILLS}/ticket-prep/SKILL.md`), "5.")
		local three, four = at(s5, "\n3. "), at(s5, "\n4. ")
		local rule = at(s5, "**Never answer a finding by cutting scope.**")
		t.expect(rule > three and rule < four).toBe(true)
		local line = string.sub(s5, rule, (string.find(s5, "\n", rule, true) :: number) - 1)
		at(line, "ask the user before you answer it")
		at(line, "`Scope decision` line")
		at(line, "Without that line, the answer is a redesign that keeps the outcome.")
	end)

	it(
		"ticket-prep restarts the round count after a scope reset, and checks scope before design: ready",
		function()
			local s5 = section(read(`{SKILLS}/ticket-prep/SKILL.md`), "5.")
			local four, five = at(s5, "\n4. "), at(s5, "\n5. ")
			local restart = at(s5, "A re-prep after the user resets an item's scope restarts the count")
			t.expect(restart > four and restart < five).toBe(true)
			local check = at(s5, "Then **check the scope**")
			t.expect(check > five and check < at(s5, "set `design: ready`")).toBe(true)
			local line = string.sub(s5, check, (string.find(s5, "\n", check, true) :: number) - 1)
			at(line, "compare each member's document with `scripts/tracker.sh capture <id>`")
			at(line, "every captured outcome has a Design and an acceptance criterion")
			at(line, "goes to the user before `design: ready`")
		end
	)

	it("ready-raft checks each member's scope against its capture first", function()
		local doc = read(`{SKILLS}/ready-raft/SKILL.md`)
		local two = at(doc, "2. **Check readiness")
		local scope = at(doc, "First, **scope**")
		t.expect(scope > two and scope < at(doc, "\n3. ")).toBe(true)
		at(doc, "stop and ask the user. Their answer lands as a `Scope decision` line")
		at(doc, "merged with the subject `tracker: scope <id> <what>`")
		at(doc, "If they restore the captured scope instead, the raft goes back to prep.")
		at(doc, "`scripts/tracker.sh capture <id>`")
		at(
			doc,
			"a capture marked `(no capture commit: first add)` or `(ambiguous: …)` counts as not matching"
		)
	end)

	it("review never prescribes a cut, and design mode checks scope fidelity after Lessons", function()
		local doc = read(`{SKILLS}/review/SKILL.md`)
		local rule = paragraph(doc, "**Never prescribe a cut.**")
		t.expect(at(doc, "**Never prescribe a cut.**") < at(doc, "\n## Design mode")).toBe(true)
		at(rule, "never makes an outcome the issue's Problem asks for smaller, later or optional")
		at(rule, "`escalate to the user:`")
		at(rule, "including what keeping the full scope would cost")
		local design = section(doc, "Design mode")
		local ten, eleven = at(design, "\n10. **Lessons**"), at(design, "\n11. **Scope fidelity**")
		t.expect(eleven > ten).toBe(true)
		local item = string.sub(design, eleven)
		at(item, "print its capture (`scripts/tracker.sh capture <id>`)")
		at(item, "with no `Scope decision` or `Decided with the user` line")
		at(item, "`Scope decision (user, YYYY-MM-DD)`")
		at(item, "every captured outcome has a Design and an acceptance criterion")
		at(item, "Judged or Observed only where the testing skill allows it")
		at(item, "moved into Non-goals")
		at(item, "left without a criterion")
		at(item, "or a Problem rewritten to match a smaller design")
		at(item, "is **high**")
		at(
			item,
			"A capture marked `(no capture commit: first add)` or `(ambiguous: …)` is not a confirmed capture"
		)
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
	it("the tracker skill lists capture as a read-only command that may run in the main checkout", function()
		local doc = read(`{SKILLS}/tracker/SKILL.md`)
		local row = string.match(doc, "\n| capture | [^\n]*") :: string
		t.expect(row ~= nil).toBe(true)
		at(row, "`tracker.sh capture <id>`")
		at(row, "read-only")
		at(row, "before each compaction")
		at(row, "A `renumber` is not followed.")
		at(row, "`(no capture commit: first add)` when no commit is a capture")
		at(row, "`(ambiguous: two items held this id at once)` when the id had two copies")
		at(row, "`tracker: new raft …` and `tracker: scope …` are not captures")
		at(section(doc, "Worktrees"), "`capture <id>`")
	end)
end)
