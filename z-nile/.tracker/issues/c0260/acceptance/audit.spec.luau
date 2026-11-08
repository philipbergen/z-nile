--!strict
-- c0260 AC3: `./zn audit` checks an issue's capture record with capturecheck (the sections of its document and the raw
-- reviews in capture/), checks none where an issue has no capture section (every issue before c0260), ignores a hidden
-- file, and refuses a designed issue that is still Unconfirmed (unattended). Fixture under .cache/c0260-audit.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0260-audit`
local ITEM = "pickman/.tracker/issues/c0900"

local function front(design: string): string
	return `---\nid: c0900\ntype: chore\ntitle: C\nslug: c\ndesign: {design}\nstatus: new-a-b-c\n---\n\n# c0900: C\n\n## Problem\nP\n\n`
end
local RECORD = "## Ask (verbatim)\n### Message 2026-11-07\n```\nmore ghosts\n```\n\n## Interview\nINTERVIEW\n\n## Idea\nMore ghosts.\n\n"
	.. "## Idea review\n### Round 1\n- F1: ask: how many?\n\n## Confirmation\nCONFIRMATION\n\n## Design\n"
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
		if string.find(line, "capture", 1, true) and string.find(line, "c0900", 1, true) then
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
local REVIEW = "# Review 001\n\n### F1 [low] x\n"

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
		write(
			`{ITEM}/c0900.md`,
			front("draft") .. record("None: unattended, nobody could be asked", UNCONFIRMED)
		)
		write(`{ITEM}/capture/idea-review-001.md`, REVIEW)
		t.expect(captureLines(audit())).toBe("")
	end)

	it("a malformed record is an error at the document, and the audit counts it", function()
		local before = errors(audit())
		write(`{ITEM}/c0900.md`, front("draft") .. record("None:", UNCONFIRMED))
		local out = audit()
		t.expect(has(captureLines(out), "needs the reason")).toBe(true)
		t.expect(errors(out) > before).toBe(true)
	end)

	it("a file in capture/ that is not a raw idea review is an error; a hidden file is not", function()
		write(
			`{ITEM}/c0900.md`,
			front("draft") .. record("None: unattended, nobody could be asked", UNCONFIRMED)
		)
		write(`{ITEM}/capture/.DS_Store`, "junk")
		t.expect(captureLines(audit())).toBe("")
		write(`{ITEM}/capture/notes.md`, "mine\n")
		t.expect(has(captureLines(audit()), "notes.md is not a capture file")).toBe(true)
		fs.removeFile(`{base}/{ITEM}/capture/notes.md`)
		t.expect(captureLines(audit())).toBe("")
	end)

	it(
		"a designed issue whose last confirmation is still Unconfirmed is an error until the user confirms",
		function()
			local unattended = front("reviewed")
				.. record("None: unattended, nobody could be asked", UNCONFIRMED)
			write(`{ITEM}/c0900.md`, unattended)
			t.expect(has(captureLines(audit()), "still Unconfirmed")).toBe(true)
			local confirmed = front("reviewed")
				.. (
					string.gsub(
						record(
							"None: unattended, nobody could be asked\n### Q1\nQuestion: how many?\nOptions: 1 | 2\nAnswer: 2",
							UNCONFIRMED .. "\n" .. CONFIRMED
						),
						"%- F1: ask: how many%?",
						"- F1: fixed: asked as Q1"
					)
				)
			write(`{ITEM}/c0900.md`, confirmed)
			t.expect(captureLines(audit())).toBe("")
			fs.removeDir(base)
		end
	)
end)
