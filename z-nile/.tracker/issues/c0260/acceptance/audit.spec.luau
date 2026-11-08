--!strict
-- c0260: `./zn audit` checks an issue's capture/ folder with capturecheck, reads only the folder it is told (an issue
-- with no capture/ is not checked: every issue before c0260), and names the folder in each problem it reports.
-- Fixture under this home's .cache/c0260-audit.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0260-audit`

local ASK = "# Ask for c0900\n\n## Verbatim ask\nmore ghosts\n\n## Interview\nNone: the ask was complete\n\n## Confirmation\n"
	.. 'Confirmed (user, 2026-11-07) after idea-review-001: "yes"\n'
local ITEM = "pickman/.tracker/issues/c0900"

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

return t.spec("c0260 audit checks the capture folder", function(it)
	it("an issue with no capture/ folder is not checked, and a complete one passes", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		engine.copy(root, base)
		engine.roots(base)
		write(
			`{ITEM}/c0900.md`,
			"---\nid: c0900\ntype: chore\ntitle: C\nslug: c\ndesign: draft\nstatus: new-a-b-c\n---\n"
		)
		t.expect(captureLines(audit())).toBe("")
		write(`{ITEM}/capture/ask.md`, ASK)
		write(`{ITEM}/capture/idea-review-001.md`, "# Review 001\n\nVerdict: approve\n")
		write(`{ITEM}/capture/idea-refute-001.md`, "")
		t.expect(captureLines(audit())).toBe("")
	end)

	it("a malformed ask.md is an error at the item's capture folder, and the audit counts it", function()
		local before = errors(audit())
		write(`{ITEM}/capture/ask.md`, (string.gsub(ASK, "more ghosts", "")))
		local out = audit()
		t.expect(has(captureLines(out), "error capture")).toBe(true)
		t.expect(has(captureLines(out), "Verbatim ask is empty")).toBe(true)
		t.expect(errors(out)).toBe(before + 1) -- exactly one more: this problem
		write(`{ITEM}/capture/ask.md`, ASK)
	end)

	it("a capture/ with no ask.md, or with a file that is not a capture file, is an error", function()
		fs.removeFile(`{base}/{ITEM}/capture/ask.md`)
		t.expect(has(captureLines(audit()), "capture/ has no ask.md")).toBe(true)
		write(`{ITEM}/capture/ask.md`, ASK)
		write(`{ITEM}/capture/notes.md`, "mine\n")
		t.expect(has(captureLines(audit()), "notes.md is not a capture file")).toBe(true)
		fs.removeFile(`{base}/{ITEM}/capture/notes.md`)
		t.expect(captureLines(audit())).toBe("")
	end)

	it("a review round the confirmation does not name is an error", function()
		write(`{ITEM}/capture/idea-review-002.md`, "# Review 002\n")
		write(`{ITEM}/capture/idea-refute-002.md`, "")
		t.expect(has(captureLines(audit()), "but the last round is idea-review-002")).toBe(true)
		fs.removeFile(`{base}/{ITEM}/capture/idea-review-002.md`)
		fs.removeFile(`{base}/{ITEM}/capture/idea-refute-002.md`)
	end)

	it(
		"a hidden file (a Finder's .DS_Store) is no capture file; a designed issue that is still unattended is an error",
		function()
			write(`{ITEM}/capture/.DS_Store`, "junk")
			t.expect(captureLines(audit())).toBe("")
			fs.removeFile(`{base}/{ITEM}/capture/.DS_Store`)
			write(`{ITEM}/capture/idea-review-002.md`, "# Review 002\n")
			write(`{ITEM}/capture/idea-refute-002.md`, "")
			local unattended = (string.gsub(ASK, "None: the ask was complete", "None: unattended"))
			unattended = (
				string.gsub(
					unattended,
					'Confirmed %(user, 2026%-11%-07%) after idea%-review%-001: "yes"',
					"Confirmed (unattended, 2026-11-07) after idea-review-002: started by the user"
				)
			)
			write(`{ITEM}/capture/ask.md`, unattended)
			t.expect(captureLines(audit())).toBe("") -- a draft may be unattended
			write(
				`{ITEM}/c0900.md`,
				"---\nid: c0900\ntype: chore\ntitle: C\nslug: c\ndesign: ready\nstatus: prepared-a-b-c\n---\n"
			)
			t.expect(has(captureLines(audit()), "still unattended")).toBe(true)
			fs.removeDir(base)
		end
	)
end)
