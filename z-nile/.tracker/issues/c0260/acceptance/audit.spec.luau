--!strict
-- c0260 AC3: `./zn audit` checks an issue's capture record with capturecheck (the sections of its document and the
-- idea-review-NNN.md files beside it), checks none where an issue has no capture section (every issue before c0260),
-- and refuses a designed issue that is still Unconfirmed (unattended). Fixture under .cache/c0260-audit.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0260-audit`
local ITEM = "pickman/.tracker/issues/c0900"

local Q1TEXT = "### Q1\nQuestion: restate?\nOptions: approve | correct\nAnswer: approve"
local function front(design: string, unmarked: boolean?): string
	local mark = if unmarked then "" else "capture: required\n"
	return `---\nid: c0900\ntype: chore\ntitle: C\nslug: c\ndesign: {design}\n{mark}status: preparing-a-b-c\n---\n\n# c0900: C\n\n## Problem\nP\n\n`
end
local RECORD = "## Ask (verbatim)\n### Message 2026-11-07\n```\nmore ghosts\n```\n\n## Interview\nINTERVIEW\n\n"
	.. "## Confirmation\nCONFIRMATION\n\n## Design\n"
local CONFIRMED = 'Confirmed (user, 2026-11-07) after round 1: "yes"'
local UNCONFIRMED =
	"Unconfirmed (unattended, 2026-11-07) after round 1: the dispatch was started with this ask"
local function record(interview: string, confirmation: string): string
	return (string.gsub(string.gsub(RECORD, "INTERVIEW", interview), "CONFIRMATION", confirmation))
end
local function write(rel: string, text: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{base}/{rel}`, text)
end
local function audit(): string
	local r = process.exec("bash", { "zn", "audit" }, { cwd = base, env = { PICKMAN_PUBLISH = "0" } })
	return r.stdout .. r.stderr
end
local function captureLines(out: string): string
	local keep = {}
	for line in string.gmatch(out, "[^\n]+") do
		if string.find(line, "capture", 1, true) and string.find(line, "c090", 1, true) then
			table.insert(keep, line)
		end
	end
	return table.concat(keep, "\n")
end
local function errors(out: string): number
	return tonumber(string.match(out, "audit: (%d+) errors")) or -1
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
local REVIEW = "# Idea review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"

return t.spec("c0260 audit checks the capture record", function(it)
	it("an issue with no capture section is not checked, and a complete record passes", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		engine.copy(root, base)
		engine.roots(base)
		write(`{ITEM}/c0900.md`, front("draft") .. "## Design\n")
		t.expect(captureLines(audit())).toBe("")
		write(`{ITEM}/c0900.md`, front("draft") .. record(Q1TEXT, UNCONFIRMED))
		write(`{ITEM}/idea-review-001.md`, REVIEW)
		t.expect(captureLines(audit())).toBe("")
	end)

	it("a malformed record is an error at the document, and the audit counts it", function()
		local before = errors(audit())
		write(`{ITEM}/c0900.md`, front("draft") .. record("None:", UNCONFIRMED))
		local out = audit()
		t.expect(has(captureLines(out), "not an interview")).toBe(true)
		t.expect(errors(out) > before).toBe(true)
	end)

	it(
		"an unmarked issue is never judged, even with a record of another shape (ten tickets hold one)",
		function()
			local legacy =
				'## Ask (verbatim)\n### Message 2026-11-11\n```\nx\n```\n\n## Interview\nfree prose\n\n## Idea\nI.\n\n## Idea review\n### Round 1\n- F1: fixed\n\n## Confirmation\nConfirmed (Phil, 2026-11-11) after round 3: "ok"\n\n## Design\n'
			write(`{ITEM}/c0900.md`, front("ready", true) .. legacy)
			t.expect(captureLines(audit())).toBe("")
			write(`{ITEM}/c0900.md`, front("ready") .. legacy)
			t.expect(captureLines(audit()) ~= "").toBe(true) -- marked, the same text is judged
		end
	)

	it("a ready design with an idea point still unruled is an error; a reviewed one is not", function()
		local open = "## Open to the human\n- F1: a point.\n\n"
		local rec = record(Q1TEXT, CONFIRMED)
		write(`{ITEM}/c0900.md`, front("reviewed") .. open .. rec)
		write(`{ITEM}/idea-review-001.md`, REVIEW)
		t.expect(captureLines(audit())).toBe("")
		write(`{ITEM}/c0900.md`, front("ready") .. open .. rec)
		t.expect(has(captureLines(audit()), "not ruled although the design is ready")).toBe(true)
		write(
			`{ITEM}/c0900.md`,
			front("ready") .. "## Open to the human\n- F1: a point. Ruled (user, 2026-11-08): ok\n\n" .. rec
		)
		t.expect(captureLines(audit())).toBe("")
	end)

	it("a round gap or a confirmation of another round is an error", function()
		write(`{ITEM}/c0900.md`, front("draft") .. record(Q1TEXT, CONFIRMED))
		write(`{ITEM}/idea-review-002.md`, REVIEW)
		t.expect(has(captureLines(audit()), "last round is 2")).toBe(true)
		fs.removeFile(`{base}/{ITEM}/idea-review-002.md`)
		write(`{ITEM}/idea-review-003.md`, REVIEW)
		t.expect(has(captureLines(audit()), "idea-review-002.md is missing")).toBe(true)
		fs.removeFile(`{base}/{ITEM}/idea-review-003.md`)
		t.expect(captureLines(audit())).toBe("")
	end)

	it(
		"a designed issue whose last confirmation is still Unconfirmed is an error until the user confirms",
		function()
			local unattended = front("reviewed") .. record(Q1TEXT, UNCONFIRMED)
			write(`{ITEM}/c0900.md`, unattended)
			t.expect(has(captureLines(audit()), "still Unconfirmed")).toBe(true)
			local confirmed = front("reviewed")
				.. record(
					Q1TEXT .. "\n### Q2\nQuestion: how many?\nOptions: 1 | 2\nAnswer: 2",
					UNCONFIRMED .. "\n" .. CONFIRMED
				)
			write(`{ITEM}/c0900.md`, confirmed)
			t.expect(captureLines(audit())).toBe("")
			fs.removeDir(base)
		end
	)

	it(
		"AC3: a marked issue at reviewed or ready needs the record or the marker; with a complete record, or unmarked, it is clean",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			engine.copy(root, base)
			engine.roots(base)
			local function marked(design: string, tail: string): string
				return front(design) .. tail
			end
			for _, design in { "reviewed", "ready" } do
				write(`{ITEM}/c0900.md`, marked(design, "## Design\n"))
				t.expect(has(captureLines(audit()), "made after the capture record landed")).toBe(true)
			end
			write(`{ITEM}/c0900.md`, front("reviewed", true) .. "## Design\n") -- unmarked: older
			t.expect(captureLines(audit())).toBe("")
			write(`{ITEM}/idea-review-001.md`, REVIEW)
			write(`{ITEM}/c0900.md`, marked("reviewed", record(Q1TEXT, CONFIRMED)))
			t.expect(captureLines(audit())).toBe("")
			fs.removeDir(base)
		end
	)

	it(
		"AC3: the everyday states pass clean: a fresh marked stub at draft, an agent-filed marked ticket at reviewed, a marked unrecorded issue under done/",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			engine.copy(root, base)
			engine.roots(base)
			local function marked(design: string, tail: string): string
				return front(design) .. tail
			end
			write(`{ITEM}/c0900.md`, marked("draft", "## Design\n")) -- a fresh stub: not yet a candidate for the refusal
			t.expect(captureLines(audit())).toBe("")
			local agentTail = "## Filed by (agent)\nSource: agent:c0260/graph-miss\n\n## Design\n"
			write(
				`{ITEM}/c0900.md`,
				(
					string.gsub(
						marked("reviewed", agentTail),
						"## Problem\nP\n",
						"## Problem\nP\nScope decision (user, 2026-11-08): agent-filed tickets are exempt from the ask, interview, idea review and confirmation (c0260)\n"
					)
				)
			)
			t.expect(captureLines(audit())).toBe("")
			fs.removeFile(`{base}/{ITEM}/c0900.md`)
			write(
				"pickman/.tracker/issues/done/c0901/c0901.md",
				(string.gsub(marked("ready", "## Design\n"), "c0900", "c0901"))
			)
			t.expect(captureLines(audit())).toBe("") -- a finished item passed the claim gate; the audit does not judge it
			fs.removeDir(base)
		end
	)
end)
